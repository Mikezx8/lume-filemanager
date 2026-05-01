#pragma once
#include <QAbstractListModel>
#include <QThread>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QTimer>
#include <QAtomicInt>
#include <QVector>

// ─────────────────────────────────────────────────────────────────────────────
// SearchHit – plain data passed between worker and model
// ─────────────────────────────────────────────────────────────────────────────
struct SearchHit {
    QString path;
    QString name;
    bool    isDir = false;
};
Q_DECLARE_METATYPE(QVector<SearchHit>)

// ─────────────────────────────────────────────────────────────────────────────
// SearchWorker – lives on its own QThread, never touches the UI thread
// ─────────────────────────────────────────────────────────────────────────────
class SearchWorker : public QObject {
    Q_OBJECT
public:
    explicit SearchWorker(QObject *parent = nullptr) : QObject(parent) {}

signals:
    void batchReady(QVector<SearchHit> hits);
    void finished();

public slots:
    void run(QString rootPath, QString query, bool showHidden, QAtomicInt *cancel) {
        QVector<SearchHit> batch;
        batch.reserve(40);
        walk(rootPath, query.toLower(), showHidden, cancel, batch);
        if (!batch.isEmpty() && !cancel->loadAcquire())
            emit batchReady(batch);
        emit finished();
    }

private:
    void walk(const QString &dir, const QString &query, bool showHidden,
              QAtomicInt *cancel, QVector<SearchHit> &batch)
    {
        if (cancel->loadAcquire()) return;

        QDir d(dir);
        QDir::Filters f = QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System;
        if (showHidden) f |= QDir::Hidden;

        for (const QFileInfo &fi : d.entryInfoList(f, QDir::DirsFirst | QDir::Name)) {
            if (cancel->loadAcquire()) return;

            if (fi.fileName().toLower().contains(query)) {
                batch.append({ fi.absoluteFilePath(), fi.fileName(), fi.isDir() });
                if (batch.size() >= 40) {
                    emit batchReady(batch);
                    batch.clear();
                    batch.reserve(40);
                    QThread::yieldCurrentThread();
                }
            }

            if (fi.isDir() && !fi.isSymLink())
                walk(fi.absoluteFilePath(), query, showHidden, cancel, batch);
        }
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// SystemSearchModel – QAbstractListModel exposed to QML
// ─────────────────────────────────────────────────────────────────────────────
class SystemSearchModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(bool isSearching READ isSearching NOTIFY isSearchingChanged)

public:
    enum Roles {
        PathRole  = Qt::UserRole + 1,
        UrlRole,
        NameRole,
        IsDirRole,
        KindRole
    };

    explicit SystemSearchModel(QObject *parent = nullptr)
        : QAbstractListModel(parent)
    {
        qRegisterMetaType<QVector<SearchHit>>("QVector<SearchHit>");

        m_debounce.setSingleShot(true);
        m_debounce.setInterval(250);
        connect(&m_debounce, &QTimer::timeout, this, &SystemSearchModel::startSearch);
    }

    ~SystemSearchModel() override {
        cancelCurrent();
    }

    // ── QML API ──────────────────────────────────────────────────────────────
    Q_INVOKABLE void setQuery(const QString &query) {
        if (m_query == query) return;
        m_query = query;
        if (query.isEmpty()) {
            m_debounce.stop();
            cancelCurrent();
            clearResults();
            setSearching(false);
        } else {
            m_debounce.start();
        }
    }

    Q_INVOKABLE void setRootPath(const QString &path) { m_rootPath = path; }
    Q_INVOKABLE void setShowHidden(bool v)             { m_showHidden = v; }

    bool isSearching() const { return m_searching; }

    // ── QAbstractListModel ────────────────────────────────────────────────────
    int rowCount(const QModelIndex &) const override { return m_results.size(); }

    QVariant data(const QModelIndex &index, int role) const override {
        if (!index.isValid() || index.row() >= m_results.size()) return {};
        const SearchHit &h = m_results.at(index.row());
        switch (role) {
        case PathRole:  return h.path;
        case UrlRole:   return QUrl::fromLocalFile(h.path);
        case NameRole:  return h.name;
        case IsDirRole: return h.isDir;
        case KindRole:  return h.isDir ? QStringLiteral("Folder") : kindFor(h.name);
        default:        return {};
        }
    }

    QHash<int, QByteArray> roleNames() const override {
        return {
            { PathRole,  "path"  },
            { UrlRole,   "url"   },
            { NameRole,  "name"  },
            { IsDirRole, "isDir" },
            { KindRole,  "kind"  },
        };
    }

signals:
    void isSearchingChanged();

private slots:
    void startSearch() {
        if (m_query.isEmpty()) return;

        cancelCurrent();
        clearResults();
        setSearching(true);

        const QString query    = m_query;
        const QString root     = m_rootPath.isEmpty() ? QDir::homePath() : m_rootPath;
        const bool    hidden   = m_showHidden;

        m_cancel = new QAtomicInt(0);
        QAtomicInt *cancelPtr = m_cancel;

        QThread      *thread = new QThread;
        SearchWorker *worker = new SearchWorker;
        worker->moveToThread(thread);

        connect(worker, &SearchWorker::batchReady,
                this,   &SystemSearchModel::onBatch,
                Qt::QueuedConnection);

        connect(worker, &SearchWorker::finished, this, [this, cancelPtr]() {
            if (m_cancel == cancelPtr) {
                setSearching(false);
                delete cancelPtr;
                m_cancel = nullptr;
            }
        }, Qt::QueuedConnection);

        connect(worker, &SearchWorker::finished, thread, &QThread::quit);
        connect(thread, &QThread::finished,      worker, &QObject::deleteLater);
        connect(thread, &QThread::finished,      thread, &QObject::deleteLater);

        connect(thread, &QThread::started, worker, [=]() {
            worker->run(root, query, hidden, cancelPtr);
        });
        thread->start();
    }

    void onBatch(QVector<SearchHit> hits) {
        if (hits.isEmpty()) return;
        const int first = m_results.size();
        const int last  = first + hits.size() - 1;
        beginInsertRows({}, first, last);
        m_results.append(hits);
        endInsertRows();
    }

private:
    void cancelCurrent() {
        if (m_cancel) {
            m_cancel->storeRelease(1);
            m_cancel = nullptr;
        }
    }

    void clearResults() {
        if (m_results.isEmpty()) return;
        beginResetModel();
        m_results.clear();
        endResetModel();
    }

    void setSearching(bool v) {
        if (m_searching == v) return;
        m_searching = v;
        emit isSearchingChanged();
    }

    static QString kindFor(const QString &name) {
        const QString ext = name.section(QLatin1Char('.'), -1).toLower();
        if (ext=="jpg"||ext=="jpeg"||ext=="png"||ext=="gif"||ext=="webp"||ext=="bmp"||ext=="svg")
            return QStringLiteral("Image");
        if (ext=="mp4"||ext=="mkv"||ext=="avi"||ext=="mov"||ext=="webm"||ext=="flv")
            return QStringLiteral("Video");
        if (ext=="mp3"||ext=="flac"||ext=="ogg"||ext=="wav"||ext=="aac"||ext=="m4a")
            return QStringLiteral("Audio");
        if (ext=="pdf")  return QStringLiteral("PDF");
        if (ext=="zip"||ext=="tar"||ext=="gz"||ext=="bz2"||ext=="xz"||ext=="rar"||ext=="7z")
            return QStringLiteral("Archive");
        return QStringLiteral("File");
    }

    QTimer             m_debounce;
    QString            m_query;
    QString            m_rootPath;
    bool               m_showHidden = false;
    bool               m_searching  = false;
    QVector<SearchHit> m_results;
    QAtomicInt        *m_cancel = nullptr;
};
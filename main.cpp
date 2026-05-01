#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QPainterPath>
#include <QRegion>
#include <QAbstractListModel>
#include <QAbstractItemModel>
#include <QStorageInfo>
#include <QVector>
#include <QQuickImageProvider>
#include <QStandardPaths>
#include <QCryptographicHash>
#include <QProcess>
#include <QImage>
#include <QColor>
#include <QUrl>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutex>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QMutexLocker>
#include <QPainter>
#include <QPen>
#include <QFont>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusError>
#include <QDebug>
#include <QDrag>
#include <QMimeData>
#include <QCursor>
#include <QQuickItem>

#include "SystemSearchModel.h"

class AudioThumbProvider : public QQuickImageProvider {
public:
    AudioThumbProvider()
        : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override {
        const QString sourcePath = normalizePath(id);
        if (sourcePath.isEmpty() || !QFileInfo::exists(sourcePath))
            return fallbackImage(size, requestedSize);

        const QString cachePath = cachedThumbPath(sourcePath);
        {
            QMutexLocker locker(&m_mutex);
            if (QFileInfo::exists(cachePath)) {
                QImage cached(cachePath);
                if (!cached.isNull()) {
                    if (size) *size = cached.size();
                    return scaledImage(cached, requestedSize);
                }
            }
        }

        QDir().mkpath(QFileInfo(cachePath).absolutePath());

        const QStringList args = {
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", sourcePath,
            "-an",
            "-vcodec", "png",
            "-vframes", "1",
            "-vf", "scale=320:-1",
            cachePath
        };

        const int exitCode = QProcess::execute("ffmpeg", args);
        if (exitCode == 0 && QFileInfo::exists(cachePath)) {
            QImage generated(cachePath);
            if (!generated.isNull()) {
                if (size) *size = generated.size();
                return scaledImage(generated, requestedSize);
            }
        }

        return fallbackImage(size, requestedSize);
    }

private:
    mutable QMutex m_mutex;

    static QString normalizePath(const QString &id) {
        if (id.startsWith("file:"))
            return QUrl(id).toLocalFile();
        if (id.startsWith("/"))
            return id;
        return QUrl::fromPercentEncoding(id.toUtf8());
    }

    static QString cachedThumbPath(const QString &sourcePath) {
        const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
        const QString dir = base.isEmpty() ? QDir::tempPath() + "/lume-audio-cache" : base + "/audio-thumbs";
        const QByteArray hash = QCryptographicHash::hash(sourcePath.toUtf8(), QCryptographicHash::Sha1).toHex();
        return dir + "/" + QString::fromLatin1(hash) + ".png";
    }

    static QImage scaledImage(const QImage &img, const QSize &requestedSize) {
        if (!requestedSize.isValid())
            return img;
        return img.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    static QImage fallbackImage(QSize *size, const QSize &requestedSize) {
        QSize s = requestedSize.isValid() ? requestedSize : QSize(320, 220);
        QImage img(s, QImage::Format_ARGB32_Premultiplied);
        img.fill(QColor("#151515"));

        QPainter painter(&img);
        painter.setRenderHint(QPainter::Antialiasing);
        QRectF circleRect(s.width() / 2 - 40, s.height() / 2 - 40, 80, 80);
        painter.setBrush(QColor("#7c6af7"));
        painter.setPen(Qt::NoPen);
        painter.drawEllipse(circleRect);
        painter.setPen(QPen(QColor("#ffffff"), 3));
        painter.setFont(QFont("Arial", 36, QFont::Bold));
        painter.drawText(circleRect, Qt::AlignCenter, "♪");
        painter.end();

        if (size) *size = img.size();
        return img;
    }
};

class VideoThumbProvider : public QQuickImageProvider {
public:
    VideoThumbProvider()
        : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override {
        const QString sourcePath = normalizePath(id);
        if (sourcePath.isEmpty() || !QFileInfo::exists(sourcePath))
            return fallbackImage(size, requestedSize);

        const QString cachePath = cachedThumbPath(sourcePath);
        {
            QMutexLocker locker(&m_mutex);
            if (QFileInfo::exists(cachePath)) {
                QImage cached(cachePath);
                if (!cached.isNull()) {
                    if (size) *size = cached.size();
                    return scaledImage(cached, requestedSize);
                }
            }
        }

        QDir().mkpath(QFileInfo(cachePath).absolutePath());

        const QStringList args = {
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-ss", "00:00:01",
            "-i", sourcePath,
            "-frames:v", "1",
            "-vf", "scale=320:-1",
            "-q:v", "4",
            cachePath
        };

        const int exitCode = QProcess::execute("ffmpeg", args);
        if (exitCode == 0 && QFileInfo::exists(cachePath)) {
            QImage generated(cachePath);
            if (!generated.isNull()) {
                if (size) *size = generated.size();
                return scaledImage(generated, requestedSize);
            }
        }

        return fallbackImage(size, requestedSize);
    }

private:
    mutable QMutex m_mutex;

    static QString normalizePath(const QString &id) {
        if (id.startsWith("file:"))
            return QUrl(id).toLocalFile();
        if (id.startsWith("/"))
            return id;
        return QUrl::fromPercentEncoding(id.toUtf8());
    }

    static QString cachedThumbPath(const QString &sourcePath) {
        const QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
        const QString dir = base.isEmpty() ? QDir::tempPath() + "/lume-thumb-cache" : base + "/video-thumbs";
        const QByteArray hash = QCryptographicHash::hash(sourcePath.toUtf8(), QCryptographicHash::Sha1).toHex();
        return dir + "/" + QString::fromLatin1(hash) + ".jpg";
    }

    static QImage scaledImage(const QImage &img, const QSize &requestedSize) {
        if (!requestedSize.isValid())
            return img;
        return img.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    static QImage fallbackImage(QSize *size, const QSize &requestedSize) {
        QSize s = requestedSize.isValid() ? requestedSize : QSize(320, 180);
        QImage img(s, QImage::Format_ARGB32_Premultiplied);
        img.fill(QColor("#151515"));
        if (size) *size = img.size();
        return img;
    }
};

class DriveModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        MountPathRole,
        UsedTextRole,
        TotalTextRole,
        UsedPctRole
    };

    explicit DriveModel(QObject *parent = nullptr) : QAbstractListModel(parent) {
        reload();
    }

    int rowCount(const QModelIndex &parent = QModelIndex()) const override {
        return parent.isValid() ? 0 : m_items.size();
    }

    QVariant data(const QModelIndex &index, int role) const override {
        if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
            return {};

        const auto &it = m_items.at(index.row());
        switch (role) {
        case NameRole:      return it.name;
        case MountPathRole: return it.mountPath;
        case UsedTextRole:   return it.usedText;
        case TotalTextRole:  return it.totalText;
        case UsedPctRole:    return it.usedPct;
        default:             return {};
        }
    }

    QHash<int, QByteArray> roleNames() const override {
        return {
            { NameRole, "name" },
            { MountPathRole, "mountPath" },
            { UsedTextRole, "usedText" },
            { TotalTextRole, "totalText" },
            { UsedPctRole, "usedPct" }
        };
    }

    Q_INVOKABLE void reload() {
        beginResetModel();
        m_items.clear();

        const auto volumes = QStorageInfo::mountedVolumes();
        for (const QStorageInfo &s : volumes) {
            if (!s.isValid() || !s.isReady())
                continue;
            if (isPseudoStorage(s))
                continue;

            const qint64 total = s.bytesTotal();
            const qint64 avail  = s.bytesAvailable();
            if (total <= 0 || avail < 0)
                continue;

            const qint64 used = qMax<qint64>(0, total - avail);
            const int pct = int((used * 100) / total);

            Item item;
            item.name = s.displayName().isEmpty() ? s.rootPath() : s.displayName();
            item.mountPath = s.rootPath();
            item.usedText = formatBytes(used);
            item.totalText = formatBytes(total);
            item.usedPct = qBound(0, pct, 100);
            m_items.push_back(item);
        }

        endResetModel();
    }

private:
    struct Item {
        QString name;
        QString mountPath;
        QString usedText;
        QString totalText;
        int usedPct = 0;
    };

    QVector<Item> m_items;

    static bool isPseudoStorage(const QStorageInfo &s) {
        const QString fs = QString::fromUtf8(s.fileSystemType()).toLower();
        const QString root = s.rootPath();

        const QStringList pseudoTypes = {
            "proc", "sysfs", "tmpfs", "devtmpfs", "devpts", "cgroup", "cgroup2",
            "overlay", "squashfs", "nsfs", "mqueue", "tracefs", "securityfs",
            "pstore", "ramfs", "fusectl", "debugfs", "efivarfs", "autofs"
        };

        if (pseudoTypes.contains(fs))
            return true;

        const QStringList pseudoRoots = {
            "/proc", "/sys", "/dev", "/run", "/snap", "/var/lib", "/tmp"
        };

        for (const QString &p : pseudoRoots) {
            if (root == p || root.startsWith(p + "/"))
                return true;
        }

        return false;
    }

    static QString formatBytes(qint64 bytes) {
        const double b = double(bytes);
        if (b < 1024.0) return QString::number(bytes) + " B";
        if (b < 1024.0 * 1024.0) return QString::number(b / 1024.0, 'f', 1) + " KB";
        if (b < 1024.0 * 1024.0 * 1024.0) return QString::number(b / 1024.0 / 1024.0, 'f', 1) + " MB";
        return QString::number(b / 1024.0 / 1024.0 / 1024.0, 'f', 1) + " GB";
    }
};

class ConfigManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString bg READ bg NOTIFY configChanged)
    Q_PROPERTY(QString surface READ surface NOTIFY configChanged)
    Q_PROPERTY(QString surface2 READ surface2 NOTIFY configChanged)
    Q_PROPERTY(QString accent READ accent NOTIFY configChanged)
    Q_PROPERTY(QString textColor READ textColor NOTIFY configChanged)
    Q_PROPERTY(QString textSecondary READ textSecondary NOTIFY configChanged)
    Q_PROPERTY(QString borderColor READ borderColor NOTIFY configChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY configChanged)
    Q_PROPERTY(int radius READ radius NOTIFY configChanged)
    Q_PROPERTY(QString heroBanner READ heroBanner NOTIFY configChanged)
    Q_PROPERTY(QString viewMode READ viewMode NOTIFY configChanged)
    Q_PROPERTY(QString selectionColor READ selectionColor NOTIFY configChanged)
    Q_PROPERTY(QVariantList contextMenuFile READ contextMenuFile NOTIFY configChanged)
    Q_PROPERTY(QVariantList contextMenuFolder READ contextMenuFolder NOTIFY configChanged)
    Q_PROPERTY(QVariantList contextMenuBackground READ contextMenuBackground NOTIFY configChanged)
    Q_PROPERTY(QString iconColor READ iconColor NOTIFY configChanged)
    Q_PROPERTY(QString iconBg READ iconBg NOTIFY configChanged)
    Q_PROPERTY(double iconBgOpacity READ iconBgOpacity NOTIFY configChanged)
    Q_PROPERTY(QVariantList shortcuts READ shortcuts NOTIFY configChanged)
    Q_PROPERTY(QString textHeaderColor READ textHeaderColor NOTIFY configChanged)
    Q_PROPERTY(QString textSidebarColor READ textSidebarColor NOTIFY configChanged)
    Q_PROPERTY(QString textFolderColor READ textFolderColor NOTIFY configChanged)
    Q_PROPERTY(QString textHoverColor READ textHoverColor NOTIFY configChanged)
    Q_PROPERTY(QString textSelectedColor READ textSelectedColor NOTIFY configChanged)
    Q_PROPERTY(QString textSidebarHoverColor READ textSidebarHoverColor NOTIFY configChanged)

public:
    explicit ConfigManager(QObject *parent = nullptr) : QObject(parent) {
        load();
    }

    QString bg() const { return v("bg", "#0a0a0a"); }
    QString surface() const { return v("surface", "#111111"); }
    QString surface2() const { return v("surface2", "#1a1a1a"); }
    QString accent() const { return v("accent", "#7c6af7"); }
    QString textColor() const { return v("text", "#f0f0f0"); }
    QString textSecondary() const { return v("text_secondary", "#6a6a6a"); }
    QString borderColor() const { return v("border", "#222222"); }
    QString fontFamily() const { return v("font_family", "Inter"); }
    int radius() const { return m_data.value("radius", 10).toInt(); }
    QString heroBanner() const { return v("hero_banner", ""); }
    QString viewMode() const { return v("view_mode", "grid"); }
    QString selectionColor() const { return v("selection_color", "#1e1a3a"); }
    QVariantList contextMenuFile() const { return m_data.value("context_menu_file").toList(); }
    QVariantList contextMenuFolder() const { return m_data.value("context_menu_folder").toList(); }
    QVariantList contextMenuBackground() const { return m_data.value("context_menu_background").toList(); }
    QString iconColor() const { return v("icon_color", ""); }
    QString iconBg() const { return v("icon_bg", "#171717"); }
    double iconBgOpacity() const { return m_data.value("icon_bg_opacity", 1.0).toDouble(); }
    QVariantList shortcuts() const { return m_data.value("shortcuts").toList(); }
    QString textHeaderColor() const { return v("text_header", textColor()); }
    QString textSidebarColor() const { return v("text_sidebar", textColor()); }
    QString textFolderColor() const { return v("text_folder", textColor()); }
    QString textHoverColor() const { return v("text_hover", textColor()); }
    QString textSelectedColor() const { return v("text_selected", accent()); }
    QString textSidebarHoverColor() const { return v("text_sidebar_hover", textColor()); }

    Q_INVOKABLE void saveViewMode(const QString &mode) {
        m_data["view_mode"] = mode;
        save();
    }

signals:
    void configChanged();

private:
    QVariantMap m_data;
    QString m_path;

    QString v(const char *key, const QString &def) const {
        return m_data.value(key, def).toString();
    }

    void load() {
        m_path = QDir::homePath() + "/.lumeconf/config.json";
        QFile f(m_path);
        if (!f.open(QIODevice::ReadOnly)) {
            writeDefaults();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        if (doc.isObject())
            m_data = doc.object().toVariantMap();
    }

    void writeDefaults() {
        QDir().mkpath(QDir::homePath() + "/.lumeconf");
        QFile f(m_path);
        if (!f.open(QIODevice::WriteOnly))
            return;

        const QByteArray defaults = R"({
  "bg": "#0a0a0a",
  "surface": "#111111",
  "surface2": "#1a1a1a",
  "accent": "#7c6af7",
  "text": "#f0f0f0",
  "text_secondary": "#6a6a6a",
  "border": "#222222",
  "font_family": "Inter",
  "radius": 10,
  "hero_banner": "",
  "view_mode": "grid",
  "selection_color": "#1e1a3a",
  "icon_color": "",
  "icon_bg": "#171717",
  "icon_bg_opacity": 1.0,
  "shortcuts": [
    { "key": "Ctrl+H", "action": "toggle_hidden" },
    { "key": "Ctrl+L", "action": "focus_path_bar" },
    { "key": "Ctrl+F", "action": "toggle_search" },
    { "key": "F5", "action": "refresh" },
    { "key": "Alt+Left", "action": "go_back" },
    { "key": "Alt+Right", "action": "go_forward" },
    { "key": "Ctrl+A", "action": "select_all" },
    { "key": "Delete", "action": "delete_selected" },
    { "key": "Ctrl+C", "action": "copy_selected" },
    { "key": "Ctrl+V", "action": "paste" },
    { "key": "Escape", "action": "clear_selection" }
  ],
  "context_menu_file": [
    { "name": "Open with Code", "icon": "⌨", "command": "code {path}" },
    { "name": "Open with VLC", "icon": "▶", "command": "vlc {path}" },
    { "name": "Copy Path", "icon": "⎘", "command": "__copy_path__" },
    { "name": "Open Terminal Here", "icon": "⬡", "command": "x-terminal-emulator" }
  ],
  "context_menu_folder": [
    { "name": "Open Terminal Here", "icon": "⬡", "command": "x-terminal-emulator" },
    { "name": "Copy Path", "icon": "⎘", "command": "__copy_path__" },
    { "name": "Open with Code", "icon": "⌨", "command": "code {path}" }
  ],
  "context_menu_background": [
    { "name": "Open Terminal Here", "icon": "⬡", "command": "x-terminal-emulator" },
    { "name": "New Folder", "icon": "📁", "command": "__new_folder__" },
    { "name": "Paste", "icon": "⎗", "command": "__paste__" },
    { "name": "Refresh", "icon": "↺", "command": "__refresh__" }
  ]
})";
        f.write(defaults);
    }

    void save() {
        QFile f(m_path);
        if (!f.open(QIODevice::WriteOnly))
            return;
        f.write(QJsonDocument(QJsonObject::fromVariantMap(m_data)).toJson(QJsonDocument::Indented));
        emit configChanged();
    }
};

class AppHelper : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasClipboard READ hasClipboard NOTIFY clipboardChanged)
public:
    explicit AppHelper(QObject *parent = nullptr) : QObject(parent) {}

    bool hasClipboard() const { return !m_clipboard.isEmpty(); }

    Q_INVOKABLE void openTerminalAt(const QString &path) {
        const QStringList terms = {
            "x-terminal-emulator", "gnome-terminal", "konsole",
            "xfce4-terminal", "lxterminal", "mate-terminal",
            "alacritty", "kitty", "xterm"
        };

        for (const QString &term : terms) {
            QStringList args;
            if (term == "gnome-terminal")
                args << "--working-directory=" + path;
            if (QProcess::startDetached(term, args, path))
                return;
        }
    }

    Q_INVOKABLE bool runContextCommand(const QString &command, const QString &path) {
        if (command.startsWith("__"))
            return false;

        QString cmd = command;
        cmd.replace("{path}", path);

        const QStringList parts = cmd.split(' ', Qt::SkipEmptyParts);
        if (parts.isEmpty())
            return true;

        const QString prog = parts.first();
        const QStringList args = parts.mid(1);
        const QString workDir = QFileInfo(path).isDir() ? path : QFileInfo(path).absolutePath();
        QProcess::startDetached(prog, args, workDir);
        return true;
    }

    Q_INVOKABLE void copyFiles(const QStringList &paths) {
        m_clipboard = paths;
        emit clipboardChanged();
    }

    Q_INVOKABLE void pasteFiles(const QString &destDir) {
        for (const QString &src : std::as_const(m_clipboard)) {
            QFileInfo fi(src);
            if (!fi.exists())
                continue;

            QString dest = destDir + "/" + fi.fileName();
            if (QFileInfo::exists(dest)) {
                QString base = fi.completeBaseName();
                QString ext = fi.suffix();
                int n = 1;
                do {
                    dest = destDir + "/" + base + " (" + QString::number(n++) + ")" + (ext.isEmpty() ? QString() : "." + ext);
                } while (QFileInfo::exists(dest));
            }

            if (fi.isDir())
                copyDir(src, dest);
            else
                QFile::copy(src, dest);
        }
        emit pasteCompleted();
    }

    Q_INVOKABLE bool createFolder(const QString &parentDir) {
        QString name = "New Folder";
        QString path = parentDir + "/" + name;
        int n = 1;
        while (QFileInfo::exists(path))
            path = parentDir + "/" + name + " " + QString::number(++n);
        return QDir().mkdir(path);
    }

    Q_INVOKABLE QString colorizeIcon(const QString &iconPath, const QString &colorHex) {
        QImage img(iconPath);
        if (img.isNull())
            return iconPath;

        QColor color(colorHex);
        for (int y = 0; y < img.height(); ++y) {
            for (int x = 0; x < img.width(); ++x) {
                QColor pixel = img.pixelColor(x, y);
                if (pixel.red() < 50 && pixel.green() < 50 && pixel.blue() < 50)
                    img.setPixelColor(x, y, color);
            }
        }

        const QString cachePath = QDir::tempPath() + "/lume_icons/" +
                                  QCryptographicHash::hash((iconPath + colorHex).toUtf8(), QCryptographicHash::Md5).toHex() + ".png";
        QDir().mkpath(QFileInfo(cachePath).absolutePath());
        img.save(cachePath);
        return "file://" + cachePath;
    }

    // Native system drag — works across all apps via X11 XDND
    Q_INVOKABLE void startNativeDrag(const QStringList &paths, QQuickItem *sourceItem) {
        if (paths.isEmpty()) return;

        QMimeData *mime = new QMimeData;

        // text/uri-list is the standard for file drag across apps
        QList<QUrl> urls;
        for (const QString &p : paths)
            urls << QUrl::fromLocalFile(p);
        mime->setUrls(urls);

        // Also set text/plain for apps that only accept text
        QStringList plainPaths;
        for (const QString &p : paths) plainPaths << p;
        mime->setText(plainPaths.join("\n"));

        QDrag *drag = new QDrag(sourceItem ? sourceItem->window() : nullptr);
        drag->setMimeData(mime);

        // Simple drag pixmap — file icon placeholder
        QPixmap pix(48, 48);
        pix.fill(Qt::transparent);
        QPainter p(&pix);
        p.setRenderHint(QPainter::Antialiasing);
        p.setBrush(QColor(100, 100, 255, 180));
        p.setPen(Qt::NoPen);
        p.drawRoundedRect(0, 0, 48, 48, 8, 8);
        p.setPen(Qt::white);
        p.setFont(QFont("sans", 10, QFont::Bold));
        p.drawText(pix.rect(), Qt::AlignCenter,
                   paths.size() > 1 ? QString::number(paths.size()) : "1");
        p.end();
        drag->setPixmap(pix);
        drag->setHotSpot(QPoint(24, 24));

        // exec() blocks until drop or cancel — runs its own event loop
        drag->exec(Qt::CopyAction | Qt::MoveAction | Qt::LinkAction);
    }

    Q_INVOKABLE QStringList pathsInRange(QObject *modelObj, int from, int to) {
        auto *model = qobject_cast<QAbstractItemModel *>(modelObj);
        QStringList result;
        if (!model)
            return result;

        const QHash<int, QByteArray> roles = model->roleNames();
        int pathRole = -1;
        for (auto it = roles.cbegin(); it != roles.cend(); ++it) {
            if (it.value() == "filePath" || it.value() == "path") {
                pathRole = it.key();
                break;
            }
        }
        if (pathRole < 0)
            return result;

        const int lo = qMin(from, to);
        const int hi = qMax(from, to);
        for (int i = lo; i <= hi; ++i) {
            const QString p = model->data(model->index(i, 0), pathRole).toString();
            if (!p.isEmpty())
                result << p;
        }
        return result;
    }

signals:
    void clipboardChanged();
    void pasteCompleted();

private:
    QStringList m_clipboard;

    static bool copyDir(const QString &src, const QString &dst) {
        QDir srcDir(src), dstDir;
        if (!dstDir.mkpath(dst))
            return false;

        const auto entries = srcDir.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot);
        for (const QFileInfo &fi : entries) {
            const QString d = dst + "/" + fi.fileName();
            if (fi.isDir()) {
                if (!copyDir(fi.filePath(), d))
                    return false;
            } else {
                if (!QFile::copy(fi.filePath(), d))
                    return false;
            }
        }
        return true;
    }
};

class FilePickerService : public QObject {
    Q_OBJECT
public:
    explicit FilePickerService(QObject *parent = nullptr) : QObject(parent) {}

    bool registerOnBus() {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.isConnected()) {
            qWarning() << "lume-file: no session bus";
            return false;
        }

        if (!bus.registerService("org.lume.FilePicker")) {
            qWarning() << "lume-file: registerService failed for org.lume.FilePicker:"
                       << bus.lastError().name() << bus.lastError().message();
            return false;
        }

        if (!bus.registerObject("/org/lume/FilePicker", this,
                                QDBusConnection::ExportAllSlots |
                                QDBusConnection::ExportAllSignals)) {
            qWarning() << "lume-file: registerObject failed:"
                       << bus.lastError().name() << bus.lastError().message();
            return false;
        }

        qDebug() << "lume-file: DBus ready on org.lume.FilePicker";
        return true;
    }

    Q_INVOKABLE void emitSelectionMade(const QStringList &paths) {
        QDBusMessage sig = QDBusMessage::createSignal(
            "/org/lume/FilePicker", "org.lume.FilePicker", "SelectionMade");
        sig << paths;
        QDBusConnection::sessionBus().send(sig);
    }

    Q_INVOKABLE void emitSelectionCancelled() {
        QDBusMessage sig = QDBusMessage::createSignal(
            "/org/lume/FilePicker", "org.lume.FilePicker", "SelectionCancelled");
        QDBusConnection::sessionBus().send(sig);
    }

public slots:
    void onRequestOpen(const QString &appId, const QString &title,
                       const QString &startPath, bool multiSelect, bool dirsOnly) {
        m_pendingOpen = true;
        m_pendingAppId = appId; m_pendingTitle = title;
        m_pendingPath = startPath; m_pendingMulti = multiSelect; m_pendingDirs = dirsOnly;
        emit openRequested(appId, title, startPath, multiSelect, dirsOnly);
    }

    void onRequestSave(const QString &appId, const QString &title,
                       const QString &startPath, const QString &suggestedName) {
        m_pendingSave = true;
        m_pendingAppId = appId; m_pendingTitle = title;
        m_pendingPath = startPath; m_pendingSuggested = suggestedName;
        emit saveRequested(appId, title, startPath, suggestedName);
    }

    void onCancel() {
        m_pendingOpen = false; m_pendingSave = false;
        emit cancelled();
    }

    // Called from QML once it's fully loaded — replays any pending request
    void flushPending(QObject *rootObj) {
        if (m_pendingOpen) {
            m_pendingOpen = false;
            QMetaObject::invokeMethod(rootObj, "pickerHandleOpen",
                Q_ARG(QVariant, m_pendingAppId), Q_ARG(QVariant, m_pendingTitle),
                Q_ARG(QVariant, m_pendingPath),  Q_ARG(QVariant, m_pendingMulti),
                Q_ARG(QVariant, m_pendingDirs));
        } else if (m_pendingSave) {
            m_pendingSave = false;
            QMetaObject::invokeMethod(rootObj, "pickerHandleSave",
                Q_ARG(QVariant, m_pendingAppId),    Q_ARG(QVariant, m_pendingTitle),
                Q_ARG(QVariant, m_pendingPath),     Q_ARG(QVariant, m_pendingSuggested));
        }
    }

signals:
    void openRequested(const QString &appId, const QString &title,
                       const QString &startPath, bool multiSelect, bool dirsOnly);
    void saveRequested(const QString &appId, const QString &title,
                       const QString &startPath, const QString &suggestedName);
    void cancelled();
    void SelectionMade(const QStringList &paths);
    void SelectionCancelled();

private:
    bool    m_pendingOpen = false;
    bool    m_pendingSave = false;
    QString m_pendingAppId;
    QString m_pendingTitle;
    QString m_pendingPath;
    QString m_pendingSuggested;
    bool    m_pendingMulti = false;
    bool    m_pendingDirs  = false;
    QStringList m_clipboard;
};

class FileManager1Service : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.FileManager1")
public:
    explicit FileManager1Service(QObject *parent = nullptr) : QObject(parent) {}

    bool registerOnBus() {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.isConnected()) {
            qWarning() << "lume-file: session bus not connected";
            return false;
        }

        if (!bus.registerService("org.freedesktop.FileManager1")) {
            qWarning() << "lume-file: failed to claim org.freedesktop.FileManager1:"
                       << bus.lastError().name() << bus.lastError().message();
            return false;
        }

        if (!bus.registerObject("/org/freedesktop/FileManager1",
                                this,
                                QDBusConnection::ExportAllSlots)) {
            qWarning() << "lume-file: failed to register /org/freedesktop/FileManager1:"
                       << bus.lastError().name() << bus.lastError().message();
            return false;
        }

        qDebug() << "lume-file: registered org.freedesktop.FileManager1";
        return true;
    }

signals:
    void showFoldersRequested(const QStringList &paths, const QString &startupId);
    void showItemsRequested(const QStringList &paths, const QString &startupId);
    void showItemPropertiesRequested(const QStringList &paths, const QString &startupId);

public slots:
    void ShowFolders(const QStringList &uris, const QString &startupId) {
        emit showFoldersRequested(normalizeUris(uris), startupId);
    }

    void ShowItems(const QStringList &uris, const QString &startupId) {
        emit showItemsRequested(normalizeUris(uris), startupId);
    }

    void ShowItemProperties(const QStringList &uris, const QString &startupId) {
        emit showItemPropertiesRequested(normalizeUris(uris), startupId);
    }

private:
    static QStringList normalizeUris(const QStringList &uris) {
        QStringList out;
        out.reserve(uris.size());

        for (const QString &u : uris) {
            QUrl url(u);
            if (url.isLocalFile())
                out << url.toLocalFile();
            else if (u.startsWith("file:"))
                out << QUrl(u).toLocalFile();
            else if (u.contains("://"))
                out << u;
            else
                out << QUrl::fromPercentEncoding(u.toUtf8());
        }
        return out;
    }
};

#include "main.moc"

int main(int argc, char *argv[]) {
    QSurfaceFormat fmt;
    fmt.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(fmt);
    QQuickWindow::setDefaultAlphaBuffer(true);

    QApplication app(argc, argv);

    QString startPath;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        QString arg = args.at(i);
        if (arg.startsWith("file://"))
            arg = QUrl(arg).toLocalFile();

        QFileInfo fi(arg);
        if (fi.isDir()) {
            startPath = arg;
            break;
        }
        if (fi.exists()) {
            startPath = fi.absolutePath();
            break;
        }
    }

    QQmlApplicationEngine engine;
    engine.addImageProvider("videoThumb", new VideoThumbProvider);
    engine.addImageProvider("audioThumb", new AudioThumbProvider);

    DriveModel driveModel;
    SystemSearchModel searchModel;
    AppHelper appHelper;
    ConfigManager cfg;
    FilePickerService pickerService;
    FileManager1Service fmService;

    pickerService.registerOnBus();
    fmService.registerOnBus();

    engine.rootContext()->setContextProperty("searchModel", &searchModel);
    engine.rootContext()->setContextProperty("driveModel", &driveModel);
    engine.rootContext()->setContextProperty("appHelper", &appHelper);
    engine.rootContext()->setContextProperty("cfg", &cfg);
    engine.rootContext()->setContextProperty("pickerService", &pickerService);
    // Only hide window if explicitly launched by DBus activation (no args at all)
    // When user launches normally, always show
    bool launchedForPicker = false;
    engine.rootContext()->setContextProperty("startPath", startPath);
    engine.rootContext()->setContextProperty("launchedForPicker", launchedForPicker);

    engine.load(QUrl(QStringLiteral("qrc:/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    QObject *rootObj = engine.rootObjects().first();

    QObject::connect(&pickerService, &FilePickerService::openRequested,
                     rootObj, [rootObj](const QString &appId, const QString &title,
                                        const QString &startPath, bool multiSelect, bool dirsOnly) {
        QMetaObject::invokeMethod(rootObj, "pickerHandleOpen",
                                  Q_ARG(QVariant, appId),
                                  Q_ARG(QVariant, title),
                                  Q_ARG(QVariant, startPath),
                                  Q_ARG(QVariant, multiSelect),
                                  Q_ARG(QVariant, dirsOnly));
    });

    QObject::connect(&pickerService, &FilePickerService::saveRequested,
                     rootObj, [rootObj](const QString &appId, const QString &title,
                                        const QString &startPath, const QString &suggestedName) {
        QMetaObject::invokeMethod(rootObj, "pickerHandleSave",
                                  Q_ARG(QVariant, appId),
                                  Q_ARG(QVariant, title),
                                  Q_ARG(QVariant, startPath),
                                  Q_ARG(QVariant, suggestedName));
    });

    QObject::connect(&pickerService, &FilePickerService::cancelled,
                     rootObj, [rootObj]() {
        QMetaObject::invokeMethod(rootObj, "pickerCancel");
    });

    // Flush any picker request that arrived before QML finished loading
    QTimer::singleShot(300, rootObj, [&pickerService, rootObj]() {
        pickerService.flushPending(rootObj);
    });

    auto bringToFront = [rootObj]() {
        if (auto *w = qobject_cast<QQuickWindow *>(rootObj)) {
            w->show();
            w->raise();
            w->requestActivate();
        }
    };

    QObject::connect(&fmService, &FileManager1Service::showFoldersRequested,
                     &app, [&engine, bringToFront](const QStringList &paths, const QString &) {
        const QString path = paths.isEmpty() ? QString() : paths.first();
        if (!path.isEmpty()) {
            const QFileInfo fi(path);
            const QString folder = fi.isDir() ? path : fi.absolutePath();
            engine.rootContext()->setContextProperty("startPath", folder);
        }
        bringToFront();
    });

    QObject::connect(&fmService, &FileManager1Service::showItemsRequested,
                     &app, [&engine, bringToFront](const QStringList &paths, const QString &) {
        const QString path = paths.isEmpty() ? QString() : paths.first();
        if (!path.isEmpty()) {
            const QFileInfo fi(path);
            const QString folder = fi.isDir() ? path : fi.absolutePath();
            engine.rootContext()->setContextProperty("startPath", folder);
            engine.rootContext()->setContextProperty("selectedPath", path);
        }
        bringToFront();
    });

    QObject::connect(&fmService, &FileManager1Service::showItemPropertiesRequested,
                     &app, [&engine, bringToFront](const QStringList &paths, const QString &) {
        const QString path = paths.isEmpty() ? QString() : paths.first();
        if (!path.isEmpty()) {
            const QFileInfo fi(path);
            const QString folder = fi.isDir() ? path : fi.absolutePath();
            engine.rootContext()->setContextProperty("startPath", folder);
            engine.rootContext()->setContextProperty("selectedPath", path);
        }
        bringToFront();
    });

    QQuickWindow *window = qobject_cast<QQuickWindow *>(rootObj);
    if (window) {
        const int radius = 12;
        auto applyMask = [window, radius]() {
            if (window->width() <= 0 || window->height() <= 0)
                return;
            QPainterPath path;
            path.addRoundedRect(0, 0, window->width(), window->height(), radius, radius);
            window->setMask(QRegion(path.toFillPolygon().toPolygon()));
        };

        applyMask();
        QObject::connect(window, &QQuickWindow::widthChanged, window, applyMask);
        QObject::connect(window, &QQuickWindow::heightChanged, window, applyMask);
        QObject::connect(window, &QQuickWindow::closing, &app, [window, rootObj](QQuickCloseEvent *) {
            QVariant pickerMode = rootObj->property("pickerMode");
            if (pickerMode.toBool()) {
                QMetaObject::invokeMethod(rootObj, "pickerCancel");
            } else {
                QApplication::quit();
            }
        });

        QObject::connect(&fmService, &FileManager1Service::showFoldersRequested,
                         window, [window]() {
            window->show();
            window->raise();
            window->requestActivate();
        });
        QObject::connect(&fmService, &FileManager1Service::showItemsRequested,
                         window, [window]() {
            window->show();
            window->raise();
            window->requestActivate();
        });
        QObject::connect(&fmService, &FileManager1Service::showItemPropertiesRequested,
                         window, [window]() {
            window->show();
            window->raise();
            window->requestActivate();
        });
    }

    return app.exec();
}
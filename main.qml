import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Qt.labs.folderlistmodel 2.1
import Qt5Compat.GraphicalEffects 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1200
    height: 760
    title: "Files"
    flags: Qt.FramelessWindowHint | Qt.Window
    color: "transparent"

    property string homePath: "/home/mik3"
    property string currentPath: (typeof startPath !== "undefined" && startPath !== "") ? startPath : homePath
    property string displayedPath: currentPath

    // ── File Picker / DBus mode ───────────────────────────────────────────
    property bool   pickerMode:        false   // true when launched by an app via DBus
    property bool   pickerSaveMode:    false   // true for save dialogs
    property bool   pickerMultiSelect: false
    property bool   pickerDirsOnly:    false
    property string pickerAppId:       ""      // calling app name
    property string pickerTitle:       ""      // dialog title
    property string pickerSuggestedName: ""    // for save mode
    property string pickerTypedName:   ""      // user-typed filename in save mode
    property var    pickerSelected:    []       // currently highlighted items in picker mode

    property string pickerLastClickedPath: ""  // tracks last single-clicked item in picker mode

    function pickerConfirm() {
        var paths = getSelectedPaths()
        if (paths.length === 0 && pickerLastClickedPath !== "")
            paths = [pickerLastClickedPath]
        if (paths.length === 0)
            paths = [currentPath]
        pickerService.emitSelectionMade(paths)
        pickerMode = false
        pickerLastClickedPath = ""
        pickerSelected = []
        clearSelection()
        Qt.callLater(function() { Qt.quit() })
    }

    function pickerCancel() {
        pickerService.emitSelectionCancelled()
        pickerMode = false
        pickerLastClickedPath = ""
        pickerSelected = []
        clearSelection()
        Qt.callLater(function() { Qt.quit() })
    }

    // Drag & drop
    property string dropFolderIcon: "file:///home/mik3/.lumeconf/unicode/folder_9389039.png"
    property var    activeDragPaths: []   // paths currently being dragged internally
    property bool   isDragging: false     // true while any internal drag is live
    property string dragGhostName: ""    // label shown on the ghost

    property string searchText: ""
    property bool searchOpen: false
    property real searchReveal: 0.0
    property bool showHiddenFiles: false
    property string viewMode: cfg ? cfg.viewMode : "grid"   // initialized from config
    property bool canGoBack: false
    property bool canGoForward: false

    // Theme shortcuts — null-safe fallbacks if cfg hasn't loaded yet
    readonly property color clrBg:       cfg ? cfg.bg            : "#0a0a0a"
    readonly property color clrSurface:  cfg ? cfg.surface       : "#111111"
    readonly property color clrSurface2: cfg ? cfg.surface2      : "#1a1a1a"
    readonly property color clrAccent:   cfg ? cfg.accent        : "#7c6af7"
    readonly property color clrText:     cfg ? cfg.textColor     : "#f0f0f0"
    readonly property color clrMuted:    cfg ? cfg.textSecondary : "#6a6a6a"
    readonly property color clrBorder:   cfg ? cfg.borderColor   : "#222222"
    readonly property color clrSel:      cfg ? cfg.selectionColor: "#1e1a3a"
    readonly property color clrTextSecondary: cfg ? cfg.textSecondary : "#6a6a6a"

// Add these new properties
readonly property color clrTextHover:        "#ffffff"
readonly property color clrTextSelected:     cfg ? cfg.accent        : "#7c6af7"
readonly property color clrTextSidebarHover: "#ffffff"

// Add these text color variants
readonly property color clrTextHeader:    cfg ? cfg.textColor  : "#f0f0f0"
readonly property color clrTextMuted:     "#4a4a4a"
readonly property color clrTextSidebar:   cfg ? cfg.textColor  : "#c0c0c0"

    // Icon theming
    // iconColor: "" = no tint (natural image colors); hex = colorize all black icons
    readonly property string iconColorStr:   cfg ? cfg.iconColor    : ""
    readonly property bool   iconColorize:   iconColorStr !== ""
    readonly property color  clrIcon:        iconColorize ? iconColorStr : "#ffffff"
    // iconBg: "" or "none" = transparent (floating); hex = solid background box
    readonly property string iconBgStr:      cfg ? cfg.iconBg       : "#171717"
    readonly property bool   iconBgVisible:  iconBgStr !== "" && iconBgStr !== "none"
    readonly property color  clrIconBg:      iconBgVisible ? iconBgStr : "transparent"
    readonly property double iconBgOpacity:  cfg ? cfg.iconBgOpacity : 1.0

    // Shortcuts from config
    readonly property var cfgShortcuts: cfg ? cfg.shortcuts : []

    property int heroNormalHeight: 340
    property int heroMaxHeight: 560

    property var backStack: []
    property var forwardStack: []

    property real pageOpacity: 1.0
    property int pageShift: 0

    property bool usingSearchResults: searchText.length > 0
    property var activeModel: usingSearchResults ? searchModel : folderModel

    // Multi-selection state
    property var selectedIndices: ({})   // { index: filePath } for ctrl-selected items
    property int rangeStart: -1          // anchor index for shift-select
    property int rangeEnd:   -1          // current end index for shift-select

    function isSelected(idx) {
        if (root.selectedIndices[idx] !== undefined) return true
        if (root.rangeStart >= 0 && root.rangeEnd >= 0) {
            var lo = Math.min(root.rangeStart, root.rangeEnd)
            var hi = Math.max(root.rangeStart, root.rangeEnd)
            return idx >= lo && idx <= hi
        }
        return false
    }

    function clearSelection() {
        root.selectedIndices = {}
        root.rangeStart = -1
        root.rangeEnd   = -1
    }

    function getSelectedPaths() {
        var paths = []
        // ctrl-selected items
        var keys = Object.keys(root.selectedIndices)
        for (var i = 0; i < keys.length; i++)
            paths.push(root.selectedIndices[keys[i]])
        // shift-range items (C++ reads the model for us)
        if (root.rangeStart >= 0 && root.rangeEnd >= 0) {
            var rangePaths = appHelper.pathsInRange(root.activeModel, root.rangeStart, root.rangeEnd)
            for (var j = 0; j < rangePaths.length; j++)
                if (paths.indexOf(rangePaths[j]) < 0)
                    paths.push(rangePaths[j])
        }
        return paths
    }

    // Ctrl+C — copy selected files for paste
    Shortcut {
        sequence: "Ctrl+C"
        onActivated: {
            var paths = root.getSelectedPaths()
            if (paths.length > 0)
                appHelper.copyFiles(paths)
        }
    }

    // Ctrl+V — paste previously copied files into current dir
    Shortcut {
        sequence: "Ctrl+V"
        onActivated: appHelper.pasteFiles(root.currentPath)
    }

    TextEdit { id: clipHelper; visible: false }
    function copyToClipboard(text) {
        clipHelper.text = text
        clipHelper.selectAll()
        clipHelper.copy()
    }

    Timer {
        id: navTimer
        interval: 140
        repeat: false
        onTriggered: {
            root.displayedPath = root.currentPath
            root.pageOpacity = 1.0
            root.pageShift = 0
        }
    }

    Timer {
        id: searchDebounce
        interval: 180
        repeat: false
        onTriggered: {
            if (typeof searchModel !== "undefined" && searchModel.setQuery) {
                searchModel.setQuery(root.searchText)
            }
        }
    }

    onSearchOpenChanged: searchReveal = searchOpen ? 1.0 : 0.0

    onCurrentPathChanged: {
        if (typeof searchModel !== "undefined" && searchModel.setRootPath)
            searchModel.setRootPath(root.currentPath)
    }

    onShowHiddenFilesChanged: {
        if (typeof searchModel !== "undefined" && searchModel.setShowHidden) {
            searchModel.setShowHidden(root.showHiddenFiles)
        }
    }

    Shortcut {
        sequences: [ StandardKey.ZoomIn ]
        onActivated: root.increaseTileSize()
    }

    Shortcut {
        sequences: [ StandardKey.ZoomOut ]
        onActivated: root.decreaseTileSize()
    }

    function toFileUrl(path) {
        if (!path)
            return "file:///"
        if (path.indexOf("file:") === 0)
            return path
        return "file://" + path
    }

    function heroHeight() {
        return visibility === Window.Maximized ? heroMaxHeight : heroNormalHeight
    }

    function baseName(path) {
        if (!path || path === "/")
            return "/"
        var p = path
        while (p.length > 1 && p.endsWith("/"))
            p = p.slice(0, -1)
        var idx = p.lastIndexOf("/")
        return idx >= 0 ? p.slice(idx + 1) : p
    }

    function parentPath(path) {
        if (!path || path === "/")
            return "/"
        var p = path
        while (p.length > 1 && p.endsWith("/"))
            p = p.slice(0, -1)
        var idx = p.lastIndexOf("/")
        if (idx <= 0)
            return "/"
        return p.slice(0, idx)
    }

    function isImageFile(suffix) {
        var s = (suffix || "").toLowerCase()
        return ["png", "jpg", "jpeg", "bmp", "gif", "webp", "tif", "tiff", "svg"].indexOf(s) !== -1
    }

    function isVideoFile(suffix) {
        var s = (suffix || "").toLowerCase()
        return ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ogv", "mpg", "mpeg"].indexOf(s) !== -1
    }

    function animatePageChange() {
        pageOpacity = 0.12
        pageShift = 20
        navTimer.restart()
    }

    function syncNavState() {
        canGoBack = backStack.length > 0
        canGoForward = forwardStack.length > 0
    }

    function navigateTo(path, pushHistory) {
        if (!path || path === currentPath)
            return
        if (pushHistory) {
            backStack = backStack.concat([currentPath])
            forwardStack = []
        }
        currentPath = path
        clearSelection()
        syncNavState()
        animatePageChange()
    }

    function goBack() {
        if (backStack.length === 0)
            return
        forwardStack = forwardStack.concat([currentPath])
        currentPath = backStack[backStack.length - 1]
        backStack = backStack.slice(0, backStack.length - 1)
        syncNavState()
        animatePageChange()
    }

    function goForward() {
        if (forwardStack.length === 0)
            return
        backStack = backStack.concat([currentPath])
        currentPath = forwardStack[forwardStack.length - 1]
        forwardStack = forwardStack.slice(0, forwardStack.length - 1)
        syncNavState()
        animatePageChange()
    }

    function openHome() {
        navigateTo(homePath, true)
    }

    function nextViewMode() {
        if (viewMode === "grid")
            viewMode = "horizontal"
        else if (viewMode === "horizontal")
            viewMode = "list"
        else
            viewMode = "grid"
        cfg.saveViewMode(viewMode)
    }

    function viewModeIcon() {
        if (viewMode === "grid")
            return "▦"
        if (viewMode === "horizontal")
            return "↔"
        return "☰"
    }

    function formatBytes(bytes) {
        if (bytes === undefined || bytes === null)
            return "—"

        var b = Number(bytes)
        if (!isFinite(b) || b < 0)
            return "—"
        if (b < 1024)
            return Math.round(b) + " B"
        if (b < 1024 * 1024)
            return (b / 1024).toFixed(1) + " KB"
        if (b < 1024 * 1024 * 1024)
            return (b / 1024 / 1024).toFixed(1) + " MB"
        return (b / 1024 / 1024 / 1024).toFixed(1) + " GB"
    }

    function formatDate(value) {
        if (!value)
            return "—"

        var d = (value instanceof Date) ? value : new Date(value)
        if (isNaN(d.getTime()))
            return "—"

        return Qt.formatDateTime(d, "yyyy-MM-dd HH:mm")
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: root.clrBg
        clip: true
        layer.enabled: true

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            width: 228
            color: Qt.darker(root.clrBg, 1.15)

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: root.clrBorder
            }

            Flickable {
                id: sideFlick
                anchors.fill: parent
                anchors.topMargin: 16
                contentWidth: width
                contentHeight: sideColumn.implicitHeight + 24
                clip: true
                boundsBehavior: Flickable.DragAndOvershootBounds
                flickDeceleration: 180
                maximumFlickVelocity: 14000
                pixelAligned: false

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    interactive: true
                }

                Column {
                    id: sideColumn
                    width: 228
                    spacing: 2
                    topPadding: 8
                    bottomPadding: 24

                    Text {
                        text: "PLACES"
                        color: root.clrTextMuted  // Was "#3a3a3a"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                        leftPadding: 18
                        bottomPadding: 6
                        width: parent.width
                    }

                    Repeater {
                        model: [
                            { label: "Home",      icon: "⌂", path: "/home/mik3" },
                            { label: "Desktop",   icon: "▣", path: "/home/mik3/Desktop" },
                            { label: "Documents", icon: "📄", path: "/home/mik3/Documents" },
                            { label: "Downloads", icon: "↓", path: "/home/mik3/Downloads" },
                            { label: "Pictures",  icon: "▦", path: "/home/mik3/Pictures" },
                            { label: "Videos",    icon: "▶", path: "/home/mik3/Videos" },
                            { label: "Music",     icon: "♪", path: "/home/mik3/Music" },
                            { label: "Trash",     icon: "🗑", path: root.homePath + "/.local/share/Trash/files" }
                        ]

                        // Sidebar items
// Sidebar items
Rectangle {
    required property var modelData
    width: 204
    height: 36
    x: 12
    radius: 8
    color: "transparent"
    
    // Smooth hover background
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.clrAccent
        opacity: placeArea.containsMouse ? 0.15 : 0
        Behavior on opacity {
            NumberAnimation { 
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }
    
    // Scale effect on hover
    scale: placeArea.containsMouse ? 1.02 : 1.0
    Behavior on scale {
        NumberAnimation { 
            duration: 150
            easing.type: Easing.OutBack
        }
    }
    
    Row {
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 10

        Text {
            text: modelData.icon
            color: placeArea.containsMouse ? root.clrAccent : Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.7)
            font.pixelSize: 15
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
            text: modelData.label
            color: placeArea.containsMouse ? root.clrTextHover : root.clrTextSidebar
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    MouseArea {
        id: placeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigateTo(modelData.path, true)
    }
}
                    }

                    Text {
                        text: "DRIVES"
                        color: root.clrTextMuted  // Was "#3a3a3a"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                        leftPadding: 18
                        topPadding: 18
                        bottomPadding: 6
                        width: parent.width
                    }

                    Repeater {
                        model: driveModel

// Drive items
Rectangle {
    required property string name
    required property string mountPath
    required property string usedText
    required property string totalText
    required property int usedPct

    width: 204
    height: 62
    x: 12
    radius: 8
    color: driveArea.containsMouse ? Qt.lighter(root.clrSurface2, 1.3) : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 5

        Row {
            width: parent.width
            spacing: 8

            Text {
                text: "▤"
                color: driveArea.containsMouse ? root.clrTextHover : root.clrAccent
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: name
                color: driveArea.containsMouse ? root.clrTextHover : root.clrTextSidebar
                font.pixelSize: 13
                elide: Text.ElideRight
                width: parent.width - 26
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            width: parent.width
            text: mountPath + "  ·  " + usedText + " used  ·  " + totalText + " total"
            color: driveArea.containsMouse ? root.clrTextSecondary : root.clrTextMuted
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        Rectangle {
            width: parent.width
            height: 3
            radius: 2
            color: "#1e1e1e"

            Rectangle {
                width: parent.width * Math.min(usedPct, 100) / 100
                height: parent.height
                radius: 2
                color: usedPct > 85 ? "#e04040" : root.clrAccent
                Behavior on width {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    MouseArea {
        id: driveArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigateTo(mountPath, true)
    }
}
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: hero
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: root.heroHeight()

                Behavior on height {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                Image {
                    anchors.fill: parent
                    source: (cfg && cfg.heroBanner) ? "file://" + cfg.heroBanner : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0.04, 0.04, 0.04, 0.42)
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.55; color: Qt.rgba(Qt.darker(root.clrBg, 1.0).r, Qt.darker(root.clrBg, 1.0).g, Qt.darker(root.clrBg, 1.0).b, 0.45) }
                        GradientStop { position: 1.0;  color: root.clrBg }
                    }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: parent.width * 0.28
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root.clrBg }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Rectangle {
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: parent.width * 0.24
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: root.clrBg }
                    }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    height: parent.height * 0.24
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(root.clrBg.r, root.clrBg.g, root.clrBg.b, 0.62) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Item {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    height: 28

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor

                        onPressed: function(mouse) {
                            if (mouse.button === Qt.LeftButton) {
                                root.startSystemMove()
                                mouse.accepted = true
                            }
                        }

                        onDoubleClicked: {
                            if (root.visibility === Window.Maximized)
                                root.showNormal()
                            else
                                root.showMaximized()
                        }
                    }
                }

                Row {
    id: leftButtons
    anchors.left: parent.left
    anchors.leftMargin: 16
    anchors.top: parent.top
    anchors.topMargin: 14
    spacing: 6
    z: 4

    Rectangle {
        width: 34; height: 26; radius: 7
        color: backArea.containsMouse ? "#262626" : Qt.rgba(0, 0, 0, 0.32)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.04)
        opacity: backArea.enabled ? 1.0 : 0.35
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: "←"; color: "#ffffff"; font.pixelSize: 12
        }
        MouseArea {
            id: backArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            enabled: root.canGoBack; onClicked: root.goBack()
        }
    }

    Rectangle {
        width: 34; height: 26; radius: 7
        color: forwardArea.containsMouse ? "#262626" : Qt.rgba(0, 0, 0, 0.32)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.04)
        opacity: forwardArea.enabled ? 1.0 : 0.35
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: "→"; color: "#ffffff"; font.pixelSize: 12
        }
        MouseArea {
            id: forwardArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            enabled: root.canGoForward; onClicked: root.goForward()
        }
    }

    Rectangle {
        width: 34; height: 26; radius: 7
        color: homeArea.containsMouse ? "#262626" : Qt.rgba(0, 0, 0, 0.32)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.04)
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: "⌂"; color: "#ffffff"; font.pixelSize: 12
        }
        MouseArea {
            id: homeArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.openHome()
        }
    }
}

// Window controls - far right
Row {
    id: windowControls
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.top: parent.top
    anchors.topMargin: 14
    spacing: 4
    z: 4

    Item {
        width: 24; height: 24
        Text {
            anchors.centerIn: parent
            text: "─"; color: minArea.containsMouse ? root.clrText : root.clrTextSecondary
            font.pixelSize: 16; font.bold: true
        }
        MouseArea {
            id: minArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.showMinimized()
        }
    }

    Item {
        width: 24; height: 24
        Text {
            anchors.centerIn: parent
            text: root.visibility === Window.Maximized ? "▢" : "▣"
            color: maxArea.containsMouse ? root.clrText : root.clrTextSecondary
            font.pixelSize: 16
        }
        MouseArea {
            id: maxArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.visibility === Window.Maximized) root.showNormal()
                else root.showMaximized()
            }
        }
    }

    Item {
        width: 24; height: 24
        Text {
            anchors.centerIn: parent
            text: "✕"; color: closeArea.containsMouse ? "#ff4444" : root.clrTextSecondary
            font.pixelSize: 16
        }
        MouseArea {
            id: closeArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
        }
    }
}

// Action buttons - right side, spaced from window controls
Row {
    id: actionButtons
    anchors.right: windowControls.left
    anchors.rightMargin: 20
    anchors.top: parent.top
    anchors.topMargin: 14
    spacing: 8
    z: 4

    Rectangle {
        width: 34; height: 26; radius: 7
        color: viewModeArea.containsMouse ? "#262626" : Qt.rgba(0, 0, 0, 0.32)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.04)
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: root.viewModeIcon(); color: "#ffffff"; font.pixelSize: 11
        }
        MouseArea {
            id: viewModeArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.nextViewMode()
        }
    }

    Rectangle {
        width: 34; height: 26; radius: 7
        color: hiddenArea.containsMouse ? "#262626" : Qt.rgba(0, 0, 0, 0.32)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.04)
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: root.showHiddenFiles ? "◉" : "○"; color: "#ffffff"; font.pixelSize: 11
        }
        MouseArea {
            id: hiddenArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.showHiddenFiles = !root.showHiddenFiles
        }
    }

    Rectangle {
        width: 34; height: 26; radius: 7
        color: searchArea.containsMouse ? "#262626" : Qt.rgba(0, 0, 0, 0.32)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.04)
        Behavior on color { ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: "⌕"; color: "#ffffff"; font.pixelSize: 12
        }
        MouseArea {
            id: searchArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.searchOpen = !root.searchOpen
        }
    }

    Item {
        width: 240 * root.searchReveal; height: 28
        clip: true; opacity: root.searchReveal
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        TextField {
            id: searchField
            anchors.left: parent.left; width: 240; height: 28
            placeholderText: "Search files and folders"; text: root.searchText
            selectByMouse: true
            background: Rectangle {
                radius: 8; color: "#111111"
                border.width: 1; border.color: "#262626"
            }
            color: "#eaeaea"; placeholderTextColor: "#666666"
            onTextChanged: { root.searchText = text; searchDebounce.restart() }
        }
    }
}

Column {
    anchors {
        left: parent.left; bottom: parent.bottom
        leftMargin: 28; bottomMargin: 28
    }
    spacing: 4; z: 2

    Text {
        text: root.baseName(root.displayedPath)
        color: root.clrTextHeader; font.pixelSize: 38
        font.weight: Font.Bold; style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.6)
    }
    Text {
        text: root.displayedPath
        color: Qt.rgba(root.clrText.r, root.clrText.g, root.clrText.b, 0.45)
        font.pixelSize: 12
    }
    Text {
        text: contentLayer.currentCount + " items"
        color: Qt.rgba(root.clrText.r, root.clrText.g, root.clrText.b, 0.45)
        font.pixelSize: 11
    }

    Row {
        spacing: 6; topPadding: 4

        Rectangle {
            width: 80; height: 22; radius: 6
            color: copyPathArea.containsMouse ? "#2a2a2a" : Qt.rgba(0,0,0,0.38)
            border.width: 1; border.color: Qt.rgba(1,1,1,0.07)
            Behavior on color { ColorAnimation { duration: 100 } }
            Row {
                anchors.centerIn: parent; spacing: 4
                Text { text: "⎘"; color: "#aaaaaa"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Copy path"; color: "#aaaaaa"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: copyPathArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.copyToClipboard(root.currentPath)
            }
        }

        Rectangle {
            width: 80; height: 22; radius: 6
            color: termArea.containsMouse ? "#2a2a2a" : Qt.rgba(0,0,0,0.38)
            border.width: 1; border.color: Qt.rgba(1,1,1,0.07)
            Behavior on color { ColorAnimation { duration: 100 } }
            Row {
                anchors.centerIn: parent; spacing: 4
                Text { text: "⬡"; color: "#aaaaaa"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Terminal"; color: "#aaaaaa"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: termArea
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: appHelper.openTerminalAt(root.currentPath)
            }
        }
    }
}
            }

            Item {
                id: contentLayer
                x: 0
                y: hero.height + root.pageShift
                width: parent.width
                height: parent.height - hero.height
                opacity: root.pageOpacity

                property int currentCount: root.viewMode === "list" ? listView.count
                                         : root.viewMode === "horizontal" ? horizontalModeView.count
                                         : gridModeView.count

                Behavior on y {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.clrBg
                }

                // Right-click on empty space
                MouseArea {
                    anchors.fill: parent
                    z: 0
                    acceptedButtons: Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            root.clearSelection()
                            var gp = mapToItem(null, mouse.x, mouse.y)
                            contextMenuOverlay.showAtBackground(gp.x, gp.y)
                        }
                    }
                }

                FolderListModel {
                    id: folderModel
                    folder: root.toFileUrl(root.displayedPath)
                    showDirs: true
                    showFiles: true
                    showDotAndDotDot: false
                    showHidden: root.showHiddenFiles
                    showOnlyReadable: true
                    showDirsFirst: true
                    caseSensitive: false
                }

Component {
    id: fileGridDelegate

    Rectangle {
        id: gridCard
        width: root.viewMode === "horizontal" ? 218 : 164
        height: root.viewMode === "horizontal" ? 132 : 164
        radius: 16
        opacity: (root.isDragging && root.activeDragPaths.indexOf(itemPath) >= 0) ? 0.38 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        color: root.isSelected(index) ? root.clrSel
             : entryArea.containsMouse ? Qt.lighter(root.clrSurface, 1.12) : root.clrSurface
        border.width: root.isSelected(index) ? 1 : isFolderItem ? 0 : 1
        border.color: root.isSelected(index) ? root.clrAccent
                    : isFolderItem ? "transparent" : (entryArea.containsMouse ? Qt.lighter(root.clrBorder, 1.5) : root.clrBorder)
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        property bool searchMode: root.usingSearchResults
        property bool isFolderItem: searchMode ? isDir : fileIsDir
        property bool isImageItem: searchMode ? false : root.isImageFile(fileSuffix)
        property bool isVideoItem: searchMode ? false : root.isVideoFile(fileSuffix)
        property bool isAudioItem: {
            if (searchMode) return false
            var suffix = (fileSuffix || "").toLowerCase()
            return ["mp3", "flac", "m4a", "wav", "ogg", "aac"].indexOf(suffix) !== -1
        }
        property string itemPath: searchMode ? path : filePath
        property url itemUrl: searchMode ? url : fileUrl
        // Safe properties accessible from nested Components
        property string itemSuffix: {
            if (searchMode) {
                var nm = name || ""
                var idx = nm.lastIndexOf(".")
                return idx > 0 ? nm.substring(idx + 1) : ""
            }
            return fileSuffix || ""
        }
        property string itemFileName: searchMode ? (name || "") : (fileName || "")

        Item {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 12
                rightMargin: 12
                topMargin: 12
            }
            height: root.viewMode === "horizontal" ? 66 : 92
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: root.clrIconBg
                opacity: root.iconBgOpacity
                visible: root.iconBgVisible
                border.width: isFolderItem ? 0 : 1
                border.color: root.iconBgVisible ? Qt.rgba(1,1,1,0.06) : "transparent"
            }

            Loader {
                anchors.fill: parent
                active: true
                sourceComponent: isFolderItem ? folderPreview
                                  : isImageItem ? imagePreview
                                  : isVideoItem ? videoPreview
                                  : isAudioItem ? audioPreview
                                  : filePreview
            }
        }

        Column {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 12
                rightMargin: 12
                topMargin: root.viewMode === "horizontal" ? 86 : 118
            }
            spacing: 4

Text {
    width: parent.width
    text: searchMode ? name : fileName
    color: root.isSelected(index) ? root.clrTextSelected :
           entryArea.containsMouse ? root.clrTextHover :
           root.clrText
    font.pixelSize: root.viewMode === "horizontal" ? 11 : 12
    elide: Text.ElideRight
}

Text {
    width: parent.width
    text: isFolderItem ? "Folder" : (isVideoItem ? "Video" : isImageItem ? "Image" : (isAudioItem ? "Audio" : (searchMode ? kind : "File")))
    color: root.isSelected(index) ? Qt.rgba(root.clrTextSelected.r, root.clrTextSelected.g, root.clrTextSelected.b, 0.7) :
           entryArea.containsMouse ? root.clrTextSecondary :
           root.clrTextSecondary
    font.pixelSize: 10
    elide: Text.ElideRight
}

// Show path in search mode
Text {
    width: parent.width
    visible: searchMode
    text: searchMode ? path.replace(root.homePath, "~") : ""
    color: root.clrTextMuted
    font.pixelSize: 9
    elide: Text.ElideLeft
}
        }

        // ── Drag source ───────────────────────────────────────────────────
        // We don't drag the card itself (it's clipped by GridView).
        // Instead we move a root-level ghost Item and attach Drag to it.
        MouseArea {
            id: entryArea
            anchors.fill: parent
            z: 2
            hoverEnabled: true
            cursorShape: root.isDragging ? Qt.DragMoveCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: dragStarted

            property bool dragStarted: false
            property real pressX: 0
            property real pressY: 0

            onPressed: function(mouse) {
                if (mouse.button !== Qt.LeftButton) return
                dragStarted = false
                pressX = mouse.x
                pressY = mouse.y
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) return
                // Always track cursor once dragging
                if (dragStarted) {
                    var sp2 = entryArea.mapToItem(dragGhost.parent, mouse.x, mouse.y)
                    dragGhost.x = sp2.x - dragGhost.width  / 2
                    dragGhost.y = sp2.y - dragGhost.height / 2
                    return
                }
                var dx = mouse.x - pressX, dy = mouse.y - pressY
                if (Math.sqrt(dx*dx + dy*dy) < 10) return
                // Threshold crossed — start native system drag
                var paths = root.getSelectedPaths()
                if (paths.indexOf(itemPath) < 0) paths = [itemPath]
                root.activeDragPaths = paths
                root.isDragging      = true
                dragStarted          = true
                // Native drag blocks until drop/cancel — no Drag.active needed
                appHelper.startNativeDrag(paths, entryArea)
                // Reset after native drag returns
                root.isDragging = false
                root.activeDragPaths = []
                dragStarted = false
            }

            onReleased: function(mouse) {
                if (dragStarted) {
                    root.isDragging = false
                    root.activeDragPaths = []
                    dragStarted = false
                }
            }

            onClicked: function(mouse) {
                if (dragStarted) return
                if (mouse.button === Qt.RightButton) {
                    if (!root.isSelected(index)) {
                        var s = {}; s[index] = itemPath
                        root.selectedIndices = s
                        root.rangeStart = index; root.rangeEnd = -1
                    }
                    var gp = entryArea.mapToItem(null, mouse.x, mouse.y)
                    contextMenuOverlay.showAt(gp.x, gp.y, itemPath, isFolderItem)
                    return
                }
                if (mouse.modifiers & Qt.ControlModifier) {
                    var s2 = Object.assign({}, root.selectedIndices)
                    if (s2[index] !== undefined) delete s2[index]
                    else s2[index] = itemPath
                    root.selectedIndices = s2
                    root.rangeStart = index; root.rangeEnd = -1
                } else if ((mouse.modifiers & Qt.ShiftModifier) && root.rangeStart >= 0) {
                    root.selectedIndices = {}
                    root.rangeEnd = index
                } else {
                    var s3 = {}; s3[index] = itemPath
                    root.selectedIndices = s3
                    root.rangeStart = index; root.rangeEnd = -1
                    if (root.pickerMode) root.pickerLastClickedPath = itemPath
                }
            }
            onDoubleClicked: {
                if (isFolderItem) root.navigateTo(itemPath, true)
                else Qt.openUrlExternally(itemUrl)
            }
        }

        // ── Drop target (folders only) ────────────────────────────────────
        DropArea {
            anchors.fill: parent
            enabled: isFolderItem && root.isDragging
            keys: ["lume/move"]

            onEntered: function(drag) {
                if (root.activeDragPaths.indexOf(itemPath) >= 0)
                    { drag.accepted = false; return }
                drag.accepted = true
            }
            onDropped: function(drop) {
                appHelper.moveItems(
                    root.activeDragPaths.map(function(p){ return "file://"+p }),
                    itemPath)
                root.activeDragPaths = []
                root.isDragging = false
                drop.accept(Qt.MoveAction)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.parent.radius
                color: parent.containsDrag
                    ? Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.22)
                    : "transparent"
                border.width: parent.containsDrag ? 2 : 0
                border.color: root.clrAccent
                Behavior on color { ColorAnimation { duration: 70 } }
                Behavior on border.width { NumberAnimation { duration: 70 } }

                Image {
                    anchors.centerIn: parent
                    width: 52; height: 52
                    source: root.dropFolderIcon
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: parent.parent.containsDrag
                    opacity: 0.95
                }
            }
        }

                        Component {
    id: folderPreview
    Item {
        anchors.fill: parent
        
        Image {
            id: folderIcon
            anchors.fill: parent
            source: "file:///home/mik3/.lumeconf/unicode/folder-fill.png"
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            sourceSize.width: 220
            sourceSize.height: 220
            visible: !root.iconColorize
        }
        
        ColorOverlay {
            anchors.fill: parent
            source: folderIcon
            color: root.clrIcon
            visible: root.iconColorize
            cached: true
        }
    }
}

                        Component {
                            id: imagePreview
                            Image {
                                anchors.fill: parent
                                source: itemUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                cache: true
                                sourceSize.width: 360
                                sourceSize.height: 220
                            }
                        }


                        Component {
                            id: videoPreview
                            Image {
                                anchors.fill: parent
                                source: "image://videoThumb/" + itemPath
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                cache: true
                                sourceSize.width: 360
                                sourceSize.height: 220

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: Qt.rgba(0, 0, 0, 0.08)
                                    visible: status !== Image.Ready
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 54
                                    height: 54
                                    radius: 27
                                    color: Qt.rgba(0, 0, 0, 0.33)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.08)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "▶"
                                        color: "#ffffff"
                                        font.pixelSize: 24
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 22
                                    radius: 10
                                    color: Qt.rgba(0, 0, 0, 0.28)
                                }

                                Text {
                                    anchors {
                                        left: parent.left
                                        leftMargin: 10
                                        bottom: parent.bottom
                                        bottomMargin: 5
                                    }
                                    text: (itemSuffix || "").toUpperCase()
                                    color: Qt.rgba(1, 1, 1, 0.72)
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Component {
    id: audioPreview
    Image {
        anchors.fill: parent
        source: "image://audioThumb/" + itemPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        cache: true
        sourceSize.width: 360
        sourceSize.height: 220
        
        Rectangle {
            anchors.fill: parent
            color: "#151515"
            border.width: 1
            border.color: "#343434"
            visible: parent.status !== Image.Ready
            
            Text {
                anchors.centerIn: parent
                text: "♪"
                color: "#7c6af7"
                font.pixelSize: 48
            }
        }
    }
}
Component {
    id: filePreview
    Item {
        Text {
            anchors.centerIn: parent
            text: {
                var ext = (itemSuffix || "").trim()
                if (ext.length === 0)
                    return "FILE"
                var lastDot = ext.lastIndexOf(".")
                if (lastDot !== -1)
                    ext = ext.substring(lastDot + 1)
                return ext.toUpperCase()
            }
            color: root.iconColorize ? root.clrIcon : "#d7d7d7"
            font.pixelSize: root.viewMode === "horizontal" ? 28 : 26
            font.weight: Font.Bold
        }

        Text {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: 8
                leftMargin: 8
                rightMargin: 8
            }
            horizontalAlignment: Text.AlignHCenter
            text: {
                var name = (itemFileName || "")
                var lastDot = name.lastIndexOf(".")
                if (lastDot !== -1)
                    return name.substring(0, lastDot)
                return name
            }
            color: root.iconColorize ? Qt.rgba(root.clrIcon.r, root.clrIcon.g, root.clrIcon.b, 0.55) : "#7a7a7a"
            font.pixelSize: 9
            elide: Text.ElideMiddle
        }
    }
}
                    }
                }


                GridView {
                    id: gridModeView
                    visible: root.viewMode === "grid"
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 12
                        topMargin: 12
                        rightMargin: 12
                        bottomMargin: 12
                    }
                    cellWidth: 180
                    cellHeight: 176
                    model: root.activeModel
                    clip: true
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    flickDeceleration: 180
                    maximumFlickVelocity: 14000
                    pixelAligned: false
                    interactive: true
                    flow: GridView.LeftToRight

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        interactive: true
                    }

                    delegate: fileGridDelegate
                }

                GridView {
                    id: horizontalModeView
                    visible: root.viewMode === "horizontal"
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: 12
                        topMargin: 12
                        rightMargin: 12
                    }
                    height: Math.min(parent.height - 24, 304)
                    cellWidth: 220
                    cellHeight: 144
                    model: root.activeModel
                    clip: true
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    flickDeceleration: 180
                    maximumFlickVelocity: 14000
                    pixelAligned: false
                    interactive: true
                    flow: GridView.TopToBottom

                    ScrollBar.horizontal: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        interactive: true
                    }

                    delegate: fileGridDelegate
                }

                Item {
                    id: listModeView
                    visible: root.viewMode === "list"
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 12
                        topMargin: 12
                        rightMargin: 12
                        bottomMargin: 12
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 38
                        radius: 12
                        color: root.clrSurface  // Was "#101010"
                        border.width: 1
                        border.color: root.clrSurface  // Was "#101010"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 48
                            anchors.rightMargin: 14
                            spacing: 14

                            Text { Layout.fillWidth: true; text: "Name"; color: "#676767"; font.pixelSize: 11; font.weight: Font.Bold }
                            Text { Layout.preferredWidth: 190; horizontalAlignment: Text.AlignRight; text: "Modified"; color: root.clrTextSecondary; font.pixelSize: 11; font.weight: Font.Bold }
                            Text { Layout.preferredWidth: 92; horizontalAlignment: Text.AlignRight; text: "Size"; color: root.clrTextSecondary; font.pixelSize: 11; font.weight: Font.Bold }
                            Text { Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight; text: "Type"; color: root.clrTextSecondary; font.pixelSize: 11; font.weight: Font.Bold }
                        }
                    }

                    ListView {
                        id: listView
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                            topMargin: 46
                        }
                        model: root.activeModel
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.DragAndOvershootBounds
                        flickDeceleration: 180
                        maximumFlickVelocity: 14000
                        pixelAligned: false
                        interactive: true

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            interactive: true
                        }

                        delegate: fileRowDelegate
                    }
                }

Component {
    id: fileRowDelegate

    Rectangle {
        id: rowCard
        width: ListView.view.width
        height: 58
        radius: 12
        opacity: (root.isDragging && root.activeDragPaths.indexOf(itemPath) >= 0) ? 0.38 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        color: root.isSelected(index) ? root.clrSel
             : rowArea.containsMouse ? Qt.lighter(root.clrSurface, 1.12) : root.clrSurface
        border.width: 1
        border.color: root.isSelected(index) ? root.clrAccent
                    : rowArea.containsMouse ? Qt.lighter(root.clrBorder, 1.5) : root.clrBorder
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        property bool searchMode: root.usingSearchResults
        property bool isFolderItem: searchMode ? isDir : fileIsDir
        property bool isImageItem: searchMode ? false : root.isImageFile(fileSuffix)
        property bool isVideoItem: searchMode ? false : root.isVideoFile(fileSuffix)
        property string itemPath: searchMode ? path : filePath
        property url itemUrl: searchMode ? url : fileUrl
        property string itemName: searchMode ? name : fileName
        property string itemDateText: searchMode
            ? (typeof modified !== "undefined" ? root.formatDate(modified) : "—")
            : root.formatDate(fileModified)
        property string itemSizeText: searchMode
            ? (typeof fileSize !== "undefined" ? root.formatBytes(fileSize) : "—")
            : (isFolderItem ? "—" : root.formatBytes(fileSize))
        property string itemTypeText: searchMode
            ? (typeof kind !== "undefined" && kind ? kind : (isFolderItem ? "Folder" : "File"))
            : (isFolderItem ? "Folder" : ((fileSuffix || "File").toUpperCase()))

        // Define components as properties
property Component folderIconComp: Component {
    Item {
        anchors.fill: parent
        
        Image {
            id: listFolderImage
            anchors.centerIn: parent
            width: 32
            height: 32
            source: "file:///home/mik3/.lumeconf/unicode/folder-fill.png"
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            sourceSize.width: 128
            sourceSize.height: 128
            visible: !root.iconColorize
        }
        
        ColorOverlay {
            anchors.fill: parent
            source: listFolderImage
            color: root.clrIcon
            visible: root.iconColorize
        }
    }
}
        
        property Component imageComp: Component {
            Image {
                anchors.fill: parent
                source: itemUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: true
                sourceSize.width: 96
                sourceSize.height: 96
            }
        }
        
        property Component videoComp: Component {
            Image {
                anchors.fill: parent
                source: "image://videoThumb/" + itemPath
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: true
                sourceSize.width: 96
                sourceSize.height: 96
                
                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.32)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        color: "#ffffff"
                        font.pixelSize: 11
                    }
                }
            }
        }
        
        property Component fileIconComp: Component {
            Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 22
                    radius: 4
                    color: root.clrSurface2
                    border.width: 1
                    border.color: root.clrBorder
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    width: 8
                    height: 4
                    radius: 2
                    color: Qt.lighter(root.clrSurface2, 1.2)
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 18
                    width: 10
                    height: 2
                    radius: 1
                    color: root.clrMuted
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 22
                    width: 10
                    height: 2
                    radius: 1
                    color: root.clrMuted
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            spacing: 12

            Item {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: root.clrSurface2
                    border.width: 1
                    border.color: Qt.lighter(root.clrBorder, 1.1)
                }

                Loader {
                    anchors.fill: parent
                    anchors.margins: 4
                    sourceComponent: isFolderItem ? rowCard.folderIconComp
                                    : isImageItem ? rowCard.imageComp
                                    : isVideoItem ? rowCard.videoComp
                                    : rowCard.fileIconComp
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    width: parent.width
                    text: itemName
                    color: root.isSelected(index) ? root.clrTextSelected :
                           rowArea.containsMouse ? root.clrTextHover :
                           root.clrText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: isFolderItem ? "Folder" : (isVideoItem ? "Video" : isImageItem ? "Image" : (searchMode ? itemTypeText : "File"))
                    color: root.isSelected(index) ? Qt.rgba(root.clrTextSelected.r, root.clrTextSelected.g, root.clrTextSelected.b, 0.7) :
                           rowArea.containsMouse ? root.clrTextSecondary :
                           root.clrTextSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: searchMode
                    text: searchMode ? itemPath.replace(root.homePath, "~") : ""
                    color: root.clrTextMuted
                    font.pixelSize: 9
                    elide: Text.ElideLeft
                }
            }

            Text {
                Layout.preferredWidth: 188
                horizontalAlignment: Text.AlignRight
                text: itemDateText
                color: root.isSelected(index) ? Qt.rgba(root.clrTextSelected.r, root.clrTextSelected.g, root.clrTextSelected.b, 0.7) :
                       rowArea.containsMouse ? root.clrTextSecondary :
                       root.clrTextSecondary
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                Layout.preferredWidth: 92
                horizontalAlignment: Text.AlignRight
                text: itemSizeText
                color: root.isSelected(index) ? Qt.rgba(root.clrTextSelected.r, root.clrTextSelected.g, root.clrTextSelected.b, 0.7) :
                       rowArea.containsMouse ? root.clrTextSecondary :
                       root.clrTextSecondary
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                Layout.preferredWidth: 110
                horizontalAlignment: Text.AlignRight
                text: itemTypeText
                color: root.isSelected(index) ? Qt.rgba(root.clrTextSelected.r, root.clrTextSelected.g, root.clrTextSelected.b, 0.7) :
                       rowArea.containsMouse ? root.clrTextSecondary :
                       root.clrTextSecondary
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            z: 2
            hoverEnabled: true
            cursorShape: root.isDragging ? Qt.DragMoveCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: dragStarted

            property bool dragStarted: false
            property real pressX: 0
            property real pressY: 0

            onPressed: function(mouse) {
                if (mouse.button !== Qt.LeftButton) return
                dragStarted = false
                pressX = mouse.x; pressY = mouse.y
            }

            onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) return
                if (dragStarted) {
                    var sp2 = rowArea.mapToItem(dragGhost.parent, mouse.x, mouse.y)
                    dragGhost.x = sp2.x - dragGhost.width  / 2
                    dragGhost.y = sp2.y - dragGhost.height / 2
                    return
                }
                var dx = mouse.x - pressX, dy = mouse.y - pressY
                if (Math.sqrt(dx*dx + dy*dy) < 10) return
                var paths = root.getSelectedPaths()
                if (paths.indexOf(itemPath) < 0) paths = [itemPath]
                root.activeDragPaths = paths
                root.isDragging      = true
                dragStarted          = true
                appHelper.startNativeDrag(paths, rowArea)
                root.isDragging = false
                root.activeDragPaths = []
                dragStarted = false
            }

            onReleased: function(mouse) {
                if (dragStarted) {
                    root.isDragging = false
                    root.activeDragPaths = []
                    dragStarted = false
                }
            }

            onClicked: function(mouse) {
                if (dragStarted) return
                if (mouse.button === Qt.RightButton) {
                    if (!root.isSelected(index)) {
                        var s = {}; s[index] = itemPath
                        root.selectedIndices = s
                        root.rangeStart = index; root.rangeEnd = -1
                    }
                    contextMenuOverlay.showAt(mouse.x + rowArea.mapToItem(null, 0, 0).x,
                                             mouse.y + rowArea.mapToItem(null, 0, 0).y,
                                             itemPath, isFolderItem)
                    return
                }
                if (mouse.modifiers & Qt.ControlModifier) {
                    var s2 = Object.assign({}, root.selectedIndices)
                    if (s2[index] !== undefined) delete s2[index]
                    else s2[index] = itemPath
                    root.selectedIndices = s2
                    root.rangeStart = index; root.rangeEnd = -1
                } else if ((mouse.modifiers & Qt.ShiftModifier) && root.rangeStart >= 0) {
                    root.selectedIndices = {}; root.rangeEnd = index
                } else {
                    var s3 = {}; s3[index] = itemPath
                    root.selectedIndices = s3
                    root.rangeStart = index; root.rangeEnd = -1
                    if (root.pickerMode) root.pickerLastClickedPath = itemPath
                }
            }
            onDoubleClicked: {
                if (isFolderItem) root.navigateTo(itemPath, true)
                else Qt.openUrlExternally(itemUrl)
            }
        }

        // Drop target for list row folders
        DropArea {
            anchors.fill: parent
            enabled: isFolderItem && root.isDragging
            keys: ["lume/move"]
            onEntered: function(drag) {
                if (root.activeDragPaths.indexOf(itemPath) >= 0)
                    { drag.accepted = false; return }
                drag.accepted = true
            }
            onDropped: function(drop) {
                appHelper.moveItems(
                    root.activeDragPaths.map(function(p){ return "file://"+p }),
                    itemPath)
                root.activeDragPaths = []
                root.isDragging = false
                drop.accept(Qt.MoveAction)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.parent.radius
                color: parent.containsDrag
                    ? Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.22)
                    : "transparent"
                border.width: parent.containsDrag ? 2 : 0
                border.color: root.clrAccent
                Behavior on color { ColorAnimation { duration: 70 } }
                Behavior on border.width { NumberAnimation { duration: 70 } }

                Image {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 }
                    width: 28; height: 28
                    source: root.dropFolderIcon
                    fillMode: Image.PreserveAspectFit
                    smooth: true; asynchronous: true
                    visible: parent.parent.containsDrag
                    opacity: 0.95
                }
            }
        }
    }
}

// ── Search loading indicator ──────────────────────────────────────────────
Item {
    parent: contentLayer
    anchors.fill: parent
    z: 10
    visible: root.usingSearchResults

    // Spinner while searching
    Rectangle {
        id: searchSpinner
        visible: searchModel !== null && searchModel !== undefined && searchModel.isSearching
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: 180; height: 36
        radius: 18
        color: Qt.rgba(root.clrSurface.r, root.clrSurface.g, root.clrSurface.b, 0.92)
        border.width: 1
        border.color: root.clrBorder

        Row {
            anchors.centerIn: parent
            spacing: 10

            // Rotating dot ring
            Canvas {
                id: spinCanvas
                width: 18; height: 18
                anchors.verticalCenter: parent.verticalCenter
                property real angle: 0
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var cx = width/2, cy = height/2, r = 7
                    for (var i = 0; i < 8; i++) {
                        var a = angle + i * (Math.PI * 2 / 8)
                        var alpha = (i + 1) / 8
                        ctx.beginPath()
                        ctx.arc(cx + r * Math.cos(a), cy + r * Math.sin(a), 1.8, 0, Math.PI * 2)
                        ctx.fillStyle = Qt.rgba(root.clrAccent.r, root.clrAccent.g,
                                                root.clrAccent.b, alpha)
                        ctx.fill()
                    }
                }
                Timer {
                    interval: 80
                    running: searchSpinner.visible
                    repeat: true
                    onTriggered: {
                        spinCanvas.angle += Math.PI * 2 / 8
                        spinCanvas.requestPaint()
                    }
                }
            }

            Text {
                text: "Searching…"
                color: root.clrText
                font.pixelSize: 13
                font.family: cfg ? cfg.fontFamily : "Inter"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Empty state — query entered, not searching, zero results
    Column {
        visible: root.usingSearchResults
                 && !(searchModel !== null && searchModel !== undefined && searchModel.isSearching)
                 && contentLayer.currentCount === 0
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "🔍"
            font.pixelSize: 44
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No results for \"" + root.searchText + "\""
            color: root.clrText
            font.pixelSize: 15
            font.family: cfg ? cfg.fontFamily : "Inter"
            font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Try a different search term"
            color: root.clrTextSecondary
            font.pixelSize: 13
            font.family: cfg ? cfg.fontFamily : "Inter"
        }
    }
}

Component.onCompleted: {
    displayedPath = currentPath
    if (typeof searchModel !== "undefined") {
        if (searchModel.setShowHidden) {
            searchModel.setShowHidden(showHiddenFiles)
        }
        if (searchModel.setQuery) {
            searchModel.setQuery("")
        }
    }
}
}
        }
    }
    } // Rectangle (rounded window)

    // ── Root-level drag ghost (follows cursor, escapes GridView clip) ─────
    // This is what Drag.active is attached to — it lives at window level
    // so it's never clipped. DropAreas hit-test against it in scene space.
    Item {
    id: dragGhost
    parent: root.contentItem
    z: 300
    width: 160
    height: 56
    visible: root.isDragging

    Drag.active: false
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.keys: ["lume/move", "text/uri-list"]
    Drag.supportedActions: Qt.MoveAction | Qt.CopyAction | Qt.LinkAction
    Drag.mimeData: {
        "text/uri-list": root.activeDragPaths.map(function(p) {
            return "file://" + p
        }).join("\n")
    }

    // Ghost card visual
    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(root.clrSurface2.r, root.clrSurface2.g, root.clrSurface2.b, 0.92)
        border.width: 1
        border.color: root.clrAccent

        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 14 }
            spacing: 10

            Text {
                text: "✦"
                color: root.clrAccent
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.dragGhostName
                color: root.clrText
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
                width: 110
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

        // Ghost tracks the real mouse via MultiPointTouchArea trick —
        // actually we update x/y from delegate onPositionChanged already.
        // Additionally, update continuously while dragging:
        MouseArea {
            anchors.fill: parent
            enabled: false   // passthrough — ghost never eats mouse events
        }
    }


    // ── Background glow DropArea (current folder, below folder cards) ─────
    DropArea {
        anchors.fill: parent
        z: 50
        keys: ["lume/move", "text/uri-list"]

        onEntered: function(drag) { drag.accepted = true }
        onDropped: function(drop) {
            // Folder DropAreas consume first — this handles background drops
            var srcs = root.activeDragPaths.length > 0
                ? root.activeDragPaths.map(function(p){ return "file://"+p })
                : drop.urls.map(function(u){ return u.toString() })
            var filtered = srcs.filter(function(u){
                return u.replace("file://","") !== root.currentPath
            })
            if (filtered.length > 0)
                appHelper.moveItems(filtered, root.currentPath)
            root.activeDragPaths = []
            root.isDragging = false
            dragGhost.Drag.active = false
            drop.accept(Qt.MoveAction)
        }

        // Subtle full-background glow while any drag is over the window
        Rectangle {
            anchors.fill: parent
            color: parent.containsDrag
                ? Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.06)
                : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            // Accent glow border on the window edge
            border.width: parent.containsDrag ? 2 : 0
            border.color: Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.35)
            radius: 12
        }
    }

// ── Context Menu Overlay ──────────────────────────────────────────────
Item {
    id: contextMenuOverlay
    anchors.fill: parent
    visible: false
    z: 200

    property string targetPath: ""
    property bool   targetIsFolder: false
    property bool   targetIsBackground: false
    property var    currentMenuItems: []
    property var    activeShortcuts: ({})  // Store shortcuts for quick lookup

    function showAt(gx, gy, path, isFolder) {
        targetPath         = path
        targetIsFolder     = isFolder
        targetIsBackground = false
        currentMenuItems = isFolder
            ? (cfg ? cfg.contextMenuFolder : [])
            : (cfg ? cfg.contextMenuFile   : [])
        _show(gx, gy)
    }

    function showAtBackground(gx, gy) {
        targetPath         = root.currentPath
        targetIsFolder     = false
        targetIsBackground = true
        currentMenuItems   = cfg ? cfg.contextMenuBackground : []
        _show(gx, gy)
    }

    function _show(gx, gy) {
        // Build shortcut lookup map
        activeShortcuts = {}
        for (var i = 0; i < currentMenuItems.length; i++) {
            if (currentMenuItems[i].shortcut) {
                activeShortcuts[currentMenuItems[i].shortcut] = i
            }
        }
        var menuH = currentMenuItems.length * 44 + 16
        var menuW = 280
        var px = Math.min(gx, root.width  - menuW - 8)
        var py = Math.min(gy, root.height - menuH - 8)
        menuBox.x = Math.max(8, px)
        menuBox.y = Math.max(8, py)
        visible = true
        menuBox.forceActiveFocus()
    }

    function executeMenuItem(index) {
        if (index >= 0 && index < currentMenuItems.length) {
            visible = false
            var cmd = currentMenuItems[index].command || ""
            if (cmd === "__copy_path__")
                root.copyToClipboard(targetPath)
            else if (cmd === "__paste__")
                appHelper.pasteFiles(root.currentPath)
            else if (cmd === "__refresh__") {
                folderModel.folder = ""
                folderModel.folder = root.toFileUrl(root.currentPath)
            } else if (cmd === "__new_folder__")
                appHelper.createFolder(root.currentPath)
            else
                appHelper.runContextCommand(cmd, targetPath)
        }
    }

    // Handle keyboard shortcuts for menu items
    Keys.onPressed: (event) => {
        // Build shortcut string from key event
        var keyStr = ""
        if (event.modifiers & Qt.ControlModifier) keyStr += "Ctrl+"
        if (event.modifiers & Qt.ShiftModifier) keyStr += "Shift+"
        if (event.modifiers & Qt.AltModifier) keyStr += "Alt+"
        
        // Get key name
        var keyName = ""
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
            keyName = String.fromCharCode(event.key)
        } else if (event.key === Qt.Key_T) {
            keyName = "T"
        } else if (event.key === Qt.Key_C) {
            keyName = "C"
        } else if (event.key === Qt.Key_V) {
            keyName = "V"
        } else if (event.key === Qt.Key_Escape) {
            visible = false
            event.accepted = true
            return
        }
        
        keyStr += keyName
        
        // Check if shortcut matches any menu item
        if (activeShortcuts[keyStr] !== undefined) {
            executeMenuItem(activeShortcuts[keyStr])
            event.accepted = true
        }
    }

    // Dismiss on outside click
    MouseArea {
        anchors.fill: parent
        onClicked: contextMenuOverlay.visible = false
    }

    Rectangle {
        id: menuBox
        width: 280
        radius: cfg ? cfg.radius + 2 : 12
        color: Qt.darker(root.clrSurface2, 1.1)
        border.width: 1
        border.color: root.clrBorder
        height: menuColumn.implicitHeight + 16
        focus: true  // Accept focus for keyboard events

        Column {
            id: menuColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
            }
            spacing: 2
            topPadding: 0

            Repeater {
                model: contextMenuOverlay.currentMenuItems

                Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 40
                    radius: cfg ? cfg.radius - 2 : 8
                    color: itemHover.containsMouse
                           ? Qt.rgba(root.clrAccent.r, root.clrAccent.g, root.clrAccent.b, 0.12)
                           : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: 10

                        // Icon: image path (starts with / or ~) → Image, else → Text emoji
                        Loader {
                            anchors.verticalCenter: parent.verticalCenter
                            width:  18
                            height: 18
                            property string iconVal: modelData.icon || ""
                            sourceComponent: {
                                var ic = iconVal.trim()
                                if (ic.length === 0) return null
                                return (ic.startsWith("/") || ic.startsWith("~/") || ic.startsWith("file://"))
                                       ? imgIcon : txtIcon
                            }

                            Component {
                                id: imgIcon
                                Image {
                                    anchors.fill: parent
                                    source: {
                                        var ic = iconVal.trim()
                                        if (ic.startsWith("~/"))
                                            ic = ic.replace("~/", root.homePath + "/")
                                        return ic.startsWith("file://") ? ic : "file://" + ic
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    asynchronous: true
                                }
                            }
                            Component {
                                id: txtIcon
                                Text {
                                    text: iconVal
                                    color: root.clrAccent
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        // Menu item name
Text {
    text: modelData.name || ""
    color: itemHover.containsMouse ? root.clrTextHover : root.clrText
    font.pixelSize: 13
    anchors.verticalCenter: parent.verticalCenter
}

Text {
    text: modelData.shortcut || ""
    color: itemHover.containsMouse ? root.clrTextSecondary : root.clrTextMuted
    font.pixelSize: 11
    font.family: "monospace"
    anchors.verticalCenter: parent.verticalCenter
    visible: text.length > 0
}
                    }

                    MouseArea {
                        id: itemHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: contextMenuOverlay.executeMenuItem(index)
                    }
                }
            }
        }
    }
}

    // ── Dynamic keyboard shortcuts from config.json ───────────────────────
    // Each entry: { "key": "Ctrl+H", "action": "toggle_hidden" }
    Repeater {
        model: root.cfgShortcuts

        Item {
            Shortcut {
            sequence:  modelData.key    || ""
            context:   Qt.ApplicationShortcut
            onActivated: {
                var action = modelData.action || ""
                switch (action) {
                case "toggle_hidden":
                    root.showHiddenFiles = !root.showHiddenFiles
                    break
                case "toggle_search":
                    root.searchOpen = !root.searchOpen
                    break
                case "focus_path_bar":
                    // emit a signal or set focus — wire to your path bar TextField id
                    if (typeof pathBarField !== "undefined") pathBarField.forceActiveFocus()
                    break
                case "refresh":
                    folderModel.folder = ""
                    folderModel.folder = "file://" + root.currentPath
                    break
                case "go_back":
                    root.goBack()
                    break
                case "go_forward":
                    root.goForward()
                    break
                case "select_all":
                    root.selectAll()
                    break
                case "delete_selected":
                    root.deleteSelected()
                    break
                case "copy_selected":
                    appHelper.copyPaths(root.getSelectedPaths())
                    break
                case "paste":
                    appHelper.pasteFiles(root.currentPath)
                    break
                case "clear_selection":
                    root.clearSelection()
                    if (root.searchOpen) root.searchOpen = false
                    break
                default:
                    break
                }
            }
        }
        } // Item
    }

    // ── DBus picker handlers — called directly from C++ via invokeMethod ──
    function pickerHandleOpen(appId, title, startPath, multiSelect, dirsOnly) {
        root.pickerMode        = true
        root.pickerSaveMode    = false
        root.pickerAppId       = appId
        root.pickerTitle       = title || "Open"
        root.pickerMultiSelect = multiSelect
        root.pickerDirsOnly    = dirsOnly
        root.pickerSelected    = []
        root.clearSelection()
        if (startPath && startPath !== "")
            root.navigateTo(startPath, false)
        root.show()
        root.raise()
        root.requestActivate()
    }

    function pickerHandleSave(appId, title, startPath, suggestedName) {
        root.pickerMode          = true
        root.pickerSaveMode      = true
        root.pickerAppId         = appId
        root.pickerTitle         = title || "Save As"
        root.pickerSuggestedName = suggestedName
        root.pickerTypedName     = suggestedName
        root.pickerMultiSelect   = false
        root.pickerDirsOnly      = false
        root.pickerSelected      = []
        root.clearSelection()
        if (startPath && startPath !== "")
            root.navigateTo(startPath, false)
        root.show()
        root.raise()
        root.requestActivate()
    }

    // ── Picker header bar (top-left, replaces "PLACES" when in picker mode) ──
    // Shown as a floating pill over the sidebar top area
    Rectangle {
        id: pickerHeader
        visible: root.pickerMode
        z: 250
        x: 8
        y: 8
        width: 212
        height: 52
        radius: 12
        color: Qt.rgba(root.clrSurface.r, root.clrSurface.g, root.clrSurface.b, 0.97)
        border.width: 1
        border.color: root.clrBorder

        Row {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 12
            }
            spacing: 10

            // App icon: try to load from /usr/share/pixmaps or themed; fallback to initial letter
            Rectangle {
                width: 32; height: 32; radius: 8
                color: root.clrAccent
                opacity: 0.85

                Text {
                    anchors.centerIn: parent
                    text: root.pickerAppId.length > 0
                          ? root.pickerAppId.charAt(0).toUpperCase()
                          : "?"
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }

                // Try themed icon if we can find it
                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: {
                        var id = root.pickerAppId.toLowerCase()
                        if (id === "") return ""
                        return "file:///usr/share/pixmaps/" + id + ".png"
                    }
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }

            Column {
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: root.pickerAppId || "App"
                    color: root.clrText
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                Text {
                    text: root.pickerTitle
                    color: root.clrTextSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    width: 140
                }
            }
        }
    }

    // ── Picker bottom action bar ──────────────────────────────────────────
    Rectangle {
        id: pickerBar
        visible: root.pickerMode
        z: 250
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 8
            rightMargin: 8
            bottomMargin: 8
        }
        height: 56
        radius: 14
        color: Qt.rgba(root.clrSurface.r, root.clrSurface.g, root.clrSurface.b, 0.97)
        border.width: 1
        border.color: root.clrBorder

        // Blur-ish subtle glow under bar
        layer.enabled: true

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
            }
            spacing: 10

            // Filename input (visible in save mode OR always for path display)
            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: 9
                color: root.clrSurface2
                border.width: 1
                border.color: root.clrBorder

                Row {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 8
                    }
                    spacing: 6

                    Text {
                        text: root.pickerSaveMode ? "Save as:" : "Path:"
                        color: root.clrTextSecondary
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: pickerInput
                        width: parent.width - 62
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.clrText
                        font.pixelSize: 12
                        selectByMouse: true
                        clip: true

                        text: root.pickerSaveMode
                              ? root.pickerTypedName
                              : (root.getSelectedPaths().length > 0
                                 ? root.getSelectedPaths()[root.getSelectedPaths().length - 1]
                                 : root.currentPath)

                        onTextChanged: {
                            if (root.pickerSaveMode)
                                root.pickerTypedName = text
                        }

                        // Read-only in open mode
                        readOnly: !root.pickerSaveMode

                        cursorVisible: root.pickerSaveMode && activeFocus
                    }
                }
            }

            // Cancel button
            Rectangle {
                width: 80; height: 34; radius: 9
                color: cancelPickerArea.containsMouse
                       ? Qt.lighter(root.clrSurface2, 1.3)
                       : root.clrSurface2
                border.width: 1
                border.color: root.clrBorder
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: root.clrTextSecondary
                    font.pixelSize: 13
                }

                MouseArea {
                    id: cancelPickerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickerCancel()
                }
            }

            // Select / Open / Save button
            Rectangle {
                width: 88; height: 34; radius: 9
                color: confirmPickerArea.containsMouse
                       ? Qt.lighter(root.clrAccent, 1.12)
                       : root.clrAccent
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: root.pickerSaveMode ? "Save" : (root.pickerDirsOnly ? "Select" : "Open")
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: confirmPickerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.pickerSaveMode) {
                            var savePath = root.currentPath + "/" + root.pickerTypedName
                            pickerService.emitSelectionMade([savePath])
                            root.pickerMode = false
                            root.clearSelection()
                            Qt.quit()
                        } else {
                            root.pickerConfirm()
                        }
                    }
                }
            }
        }
    }
}
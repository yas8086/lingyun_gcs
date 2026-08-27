import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// 灵云01 飞艇地面站 · Qt Quick 主窗口（一比一复刻 airship-gcs-prototype.html）
// 三层架构：C++ 后端（串口/协议/告警/配置）→ TelemetryBridge 桥接层 → 本 QML 前端。
// 本文件承担：主题 token 体系、左侧导航、顶栏、内容视图切换、底部状态栏、Toast、紧急操作。
ApplicationWindow {
    id: root
    // 保持隐藏，等 main.cpp 的 show()：启动最大化由 C++ 单一路径负责
    // （setGeometry 铺满可用区防首帧小窗闪现 + setWindowState(Maximized) 同步按钮态）。
    // 不要在此再声明 visibility: Window.Maximized——QML 在 engine.load() 时会提前请求一次
    // 最大化，与 C++ 的二次设置互相踩踏，WM 状态位错序导致标题栏按钮初态显示"最大化"、
    // 点一下才变"还原"（真机已复现）。
    visible: false
    title: "灵云01号 飞艇地面站"
    // 窗口 flags：保持 Qt 默认（标题栏含最小化/最大化/关闭三按钮）。
    // 之前移除 WindowMaximizeButtonHint 会在部分 WM 下出现"显示但点不了"的
    // 假最大化按钮；现恢复默认 flags，允许用户正常使用最大化/还原与拖拽调整
    // 窗口大小。

    // ===== 设计 token（对齐原型，浅/深主题 + 强调色 + 密度 + 对比度）=====
    // 主题值启动时从配置恢复（重启自动恢复），变更时写回配置（纳入导入导出）
    property bool dark: bridge ? bridge.configDark() : false
    property string accent: bridge ? bridge.configAccent() : "blue"  // blue|green|orange|purple|teal
    property bool dense: bridge ? bridge.configDense() : false       // 密度：false=舒适 true=密集
    property bool contrast: bridge ? bridge.configContrast() : false // 高对比度
    onDarkChanged: if (bridge) bridge.setConfigDark(dark)
    onDenseChanged: if (bridge) bridge.setConfigDense(dense)
    onContrastChanged: if (bridge) bridge.setConfigContrast(contrast)
    onAccentChanged: if (bridge) bridge.setConfigAccent(accent)

    // 导入配置后按新配置刷新主题
    Connections {
        target: bridge
        function onConfigImported() {
            root.dark = bridge.configDark()
            root.dense = bridge.configDense()
            root.contrast = bridge.configContrast()
            root.accent = bridge.configAccent()
        }
    }


    // 强调色主色
    readonly property var accentPrimary: ({
        blue:  dark ? "#3b82f6" : "#2563eb",
        green: dark ? "#34d399" : "#059669",
        orange:dark ? "#fb923c" : "#ea580c",
        purple:dark ? "#a78bfa" : "#7c3aed",
        teal:  dark ? "#2dd4bf" : "#0d9488"
    })[accent]
    readonly property var accentSoft: ({
        blue:  dark ? "#172a4a" : "#eff6ff",
        green: dark ? "#0b3d2e" : "#ecfdf5",
        orange:dark ? "#3b2008" : "#fff7ed",
        purple:dark ? "#2a1b4a" : "#f5f3ff",
        teal:  dark ? "#0a3a35" : "#f0fdfa"
    })[accent]
    readonly property var accentRing: ({
        blue:  dark ? "rgba(59,130,246,.2)" : "rgba(37,99,235,.15)",
        green: dark ? "rgba(52,211,153,.2)" : "rgba(5,150,105,.15)",
        orange:dark ? "rgba(251,146,60,.2)" : "rgba(234,88,12,.15)",
        purple:dark ? "rgba(167,139,250,.2)" : "rgba(124,58,237,.15)",
        teal:  dark ? "rgba(45,212,191,.2)" : "rgba(13,148,136,.15)"
    })[accent]

    readonly property color colBg:  contrast ? (dark ? "#000000" : "#f2f5fa")
                                           : (dark ? "#0b1220" : "#eef2f7")
    readonly property color colBg2: contrast ? (dark ? "#0a0f1c" : "#e2e8f0")
                                           : (dark ? "#0f172a" : "#e6ebf2")
    readonly property color colCard:  contrast ? (dark ? "#0f172a" : "#ffffff") : (dark ? "#16213a" : "#ffffff")
    readonly property color colCard2: contrast ? (dark ? "#16213a" : "#eef2f7") : (dark ? "#1b2947" : "#f8fafc")
    readonly property color colText:  contrast ? (dark ? "#ffffff" : "#0b1220") : (dark ? "#e7edf6" : "#1e293b")
    readonly property color colText2: contrast ? (dark ? "#cbd5e1" : "#1e293b") : (dark ? "#8aa0bf" : "#64748b")
    readonly property color colLine:  contrast ? (dark ? "#475569" : "#94a3b8") : (dark ? "#22314f" : "#e2e8f0")
    readonly property color colPrimary: root.accentPrimary
    readonly property color colPrimarySoft: root.accentSoft
    readonly property color colOk: dark ? "#22c55e" : "#16a34a"
    readonly property color colOkSoft: dark ? "#0f2a1c" : "#f0fdf4"
    readonly property color colWarn: dark ? "#f59e0b" : "#d97706"
    readonly property color colWarnSoft: dark ? "#2d2410" : "#fffbeb"
    readonly property color colErr: dark ? "#ef4444" : "#dc2626"
    readonly property color colErrSoft: dark ? "#331516" : "#fef2f2"
    readonly property color colOff: dark ? "#5a6a84" : "#94a3b8"

    // 字号尺度：密度切换（原型 fs-display/fs-title/fs-body/fs-caption/fs-num）
    readonly property real fsDisplay: dense ? 25 : 38
    readonly property real fsNum: dense ? 14 : 17
    readonly property real fsTitle: 15
    readonly property real fsBody: 13
    readonly property real fsCaption: 11

    property int currentNav: 0
    property int dataTick: 0
    // 遥测节流标志（onTelemetryChanged 与 tickThrottle 共用，属 root 顶层，非内容区 Item）
    property bool tickPending: false

    // 地图视口状态提升到顶层：MapView 用 Loader 懒加载，切出即销毁、切回重建。
    // 状态存顶层才能跨页面保留（切走再回不重置缩放/中心/图层/跟随），
    // 与 rtcData 的处理思路一致。默认定位：杭州余杭 · 良渚文化村。
    property double mapZoom: 14
    property double mapCenterLon: 120.029
    property double mapCenterLat: 30.365
    property int mapLayer: 0            // 0=街道 1=影像
    property bool mapFollow: true
    // 飞艇模拟遥测（地图页坐标显示/轨迹绘制/跟随定位）
    // 提升到顶层常驻：即使切出地图页，模拟与轨迹累积也在后台持续，
    // 切回可看到完整连续的 A→B 路径（mapTick 驱动地图重绘）。
    property var mapAirPos: ({lon:120.029, lat:30.365})
    property double mapHeading: 0
    property double mapAlt: 150
    property double mapSpeed: 12.5
    property var mapTrack: []            // 轨迹点 [{lon,lat}]
    property var mapHomePos: ({lon:120.029, lat:30.365})
    property double mapDist: 0
    property double mapBearing: 0
    property int mapTick: 0              // 每秒自增，驱动地图页面重绘

    // 实时曲线采样数据（提升到顶层而非 TopoView：TopoView 用 Loader 懒加载，
    // 切出图示页即被销毁。数据放顶层才能跨页面保留，实现"切出再回曲线不重绘"，
    // 且采样 Timer 常驻，无论在哪页都持续采样，保证曲线连续。）
    property var rtcData: ({"v":[], "pv":[], "outp":[], "i":[]})
    property int rtcIdx: 0
    property int rtcTick: 0
    property int rtcMax: 600
    property int rtcWindowPoints: 60   // 曲线时间窗显示点数（500ms 采样：30s=60/1min=120/5min=600），图示页可切换
    property bool rtcPlaying: true

    function fmt(v, dp) { return isNaN(v) ? "--" : Number(v).toFixed(dp); }
    function fmtInt(v) { return isNaN(v) ? "--" : Math.round(v); }
    function isOnline(dev) { return bridge.online(dev); }
    // 模块可见性（决策 #30）：true 表示该模块被隐藏
    function isModuleHidden(key) {
        void root.dataTick
        return bridge.configHiddenModules().indexOf(key) !== -1
    }

    color: colBg

    // 不透明背景层（防驱动透明穿透）
    Rectangle { anchors.fill: parent; color: root.colBg; z: -1 }

    RowLayout {
        spacing: 0
        anchors.fill: parent

        // ----- 左侧导航（72px 图标列）-----
        Rectangle {
            width: 72
            Layout.fillHeight: true
            color: colCard
            border.color: colLine
            ColumnLayout {
                anchors.fill: parent
                spacing: 6
                // Logo（真实飞艇 SVG 图标）
                Rectangle {
                    Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignHCenter
                    radius: 12
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#2563eb" }
                        GradientStop { position: 1; color: "#06b6d4" }
                    }
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qml/img/airship.svg"
                        sourceSize.width: 32; sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                    }
                }
                Repeater {
                    model: [
                        {name:"监控",ic:"📡"},
                        {name:"自检",ic:"✓"},
                        {name:"飞控",ic:"✈"},
                        {name:"摄像头",svg:"qrc:/qml/img/camera-nav.svg"},
                        {name:"图示",ic:"📊"},
                        {name:"设置",ic:"⚙"}
                    ]
                    Rectangle {
                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                        scale: ma_1.pressed ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        width: 64; height: 64; radius: 12
                        color: root.currentNav === index ? root.colPrimarySoft
                             : (ma_1.containsMouse ? root.colCard2 : "transparent")
                        // 激活指示条（原 prototype .nav-item.active::before）
                        Rectangle {
                            visible: root.currentNav === index
                            width: 3; height: 24; radius: 3; color: root.colPrimary
                            anchors.right: parent.right
                            anchors.rightMargin: -6
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            // 图标区：摄像头用 SVG 线稿（对齐 HTML 原型样式），其余用 emoji
                            Item {
                                width: 22; height: 22
                                anchors.horizontalCenter: parent.horizontalCenter
                                Image {
                                    id: navIcImg
                                    anchors.fill: parent
                                    visible: modelData.svg !== undefined
                                    source: modelData.svg ? modelData.svg : ""
                                    fillMode: Image.PreserveAspectFit
                                }
                                Text {
                                    visible: modelData.svg === undefined
                                    text: modelData.ic || ""
                                    font.pixelSize: 22
                                    color: root.currentNav === index ? root.colPrimary : root.colText2
                                }
                                // SVG 图标着色（随激活状态变色，对齐 .nav-item svg 的 stroke:currentColor）
                                MultiEffect {
                                    visible: modelData.svg !== undefined
                                    anchors.fill: parent
                                    source: navIcImg
                                    colorization: 1.0
                                    colorizationColor: root.currentNav === index ? root.colPrimary : root.colText2
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: root.currentNav === index ? root.colPrimary : root.colText2
                            }
                        }
                        MouseArea {
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            id: ma_1
                            anchors.fill: parent
                            onClicked: root.currentNav = index
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // ----- 主区（顶栏 + 内容 + 状态栏）-----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: colBg
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ----- 顶栏 -----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: colCard
                    border.color: colLine
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        Column {
                            Row {
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "灵云01 飞艇地面站"; font.pixelSize: 17; font.bold: true; color: root.colText
                                }
                            }
                            Text {
                                // 统一数据链路状态：串口或 UDP 任一在线即为链路在（B9/B14 联动串口配置）
                                text: { void root.dataTick; bridge.isDataLinkOnline()
                                        ? "电源系统监控 · 数据链路 " + (bridge.isSerialOpen() ? bridge.port() + " " + bridge.baud() : "UDP")
                                        : "电源系统监控 · 链路未连接" }
                                font.pixelSize: 11; color: root.colText2
                            }
                        }
                        Item { Layout.fillWidth: true }
                        // 设备灯（点击弹状态详情，再次点击关闭）
                        Repeater {
                            model: [["bms","BMS"],["mppt1","MPPT"],["dcdc","DCDC"],["backup","备用电源"]]
                            Rectangle {
                                // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                scale: ma_2.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                id: devLamp
                                property string devKey: modelData[0]
                                Layout.preferredHeight: 26; radius: 8
                                Layout.rightMargin: 10
                                implicitWidth: lampLbl.implicitWidth + 22
                                color: root.activeDevPop === modelData[0] ? root.colPrimarySoft : root.colCard2
                                border.color: root.activeDevPop === modelData[0] ? root.colPrimary : root.colLine
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: { void root.dataTick; root.isOnline(modelData[0]) ? root.colOk : root.colOff }
                                    }
                                    Text {
                                        id: lampLbl
                                        text: modelData[1]; font.pixelSize: 12; font.weight: Font.DemiBold
                                        color: { void root.dataTick; root.isOnline(modelData[0]) ? root.colText : root.colOff }
                                    }
                                }
                                MouseArea {
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    id: ma_2
                                    anchors.fill: parent
                                    onClicked: {
                                        if (devPop.opened && root.activeDevPop === modelData[0]) {
                                            root.activeDevPop = ""
                                            devPop.close()
                                        } else {
                                            root.openDevPop(modelData[0], devLamp)
                                        }
                                    }
                                }
                            }
                        }
                        // 密度 / 主题 切换（原型顶栏按钮）
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_1
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: root.dense ? "字体：小" : "字体：大"
                            Layout.rightMargin: 10
                            background: Rectangle {
                                radius: 10; color: root.colCard2; border.color: (hover_1.hovered ? root.colPrimary : root.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.colText2; font.bold: true }
                            onClicked: root.dense = !root.dense
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_2
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: root.dark ? "浅色" : "深色"
                            Layout.rightMargin: 10
                            background: Rectangle {
                                radius: 10; color: root.colCard2; border.color: (hover_2.hovered ? root.colPrimary : root.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.colText2; font.bold: true }
                            onClicked: root.dark = !root.dark
                        }
                    }
                }

                // ----- 内容区（各视图 Loader / 占位）-----
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // 全局刷新节拍：遥测变化驱动 dataTick（所有视图绑定重算），不依赖任一子视图。
                    // 节流 50ms：telemetryChanged 每帧触发，若不节流，串口频率升高时全页数十处
                    // 绑定会每帧全量重算（CPU 开销线性放大）。值已实时写入 bridge，UI 仅 50ms 合并刷新。
                    Timer {
                        id: tickThrottle
                        interval: 50
                        onTriggered: {
                            tickThrottle.stop()
                            if (root.tickPending) {
                                root.tickPending = false
                                root.dataTick++
                            }
                        }
                    }
                    Connections {
                        target: bridge
                        function onTelemetryChanged() {
                            if (!root.tickPending) {
                                root.tickPending = true
                                // 若 timer 未运行则立即刷新并重启节流窗；已运行则等其触发
                                if (!tickThrottle.running) {
                                    root.dataTick++
                                    tickThrottle.start()
                                }
                            }
                        }
                        // 串口开关/配置变更（模块可见性等）也要驱动 dataTick，
                        // 否则 isModuleHidden/serialIsOpen 等依赖 dataTick 的绑定不刷新
                        function onStateChanged() { root.dataTick++ }
                    }

                    // 监控页
                    Loader {
                        active: root.currentNav === 0
                        anchors.fill: parent
                        anchors.margins: 14
                        source: "qrc:/qml/views/MonitorView.qml"
                        onLoaded: {
                            item.themeRoot = root
                            item.showNote.connect(root.showToast)
                        }
                    }
                    // 自检页
                    Loader {
                        active: root.currentNav === 1
                        anchors.fill: parent
                        anchors.margins: 14
                        source: "qrc:/qml/views/SelfCheckView.qml"
                        onLoaded: {
                            item.themeRoot = root
                            item.showNote.connect(root.showToast)
                        }
                    }
                    // 飞控页（内含地图右栏，见 FlightView 布局）
                    Loader {
                        active: root.currentNav === 2
                        anchors.fill: parent
                        anchors.margins: 14
                        source: "qrc:/qml/views/FlightView.qml"
                        onLoaded: { item.themeRoot = root }
                    }
                    // 摄像头监控页（独立模块，复刻原型）
                    Loader {
                        active: root.currentNav === 3
                        anchors.fill: parent
                        anchors.margins: 14
                        source: "qrc:/qml/views/CameraView.qml"
                        onLoaded: {
                            item.themeRoot = root
                            item.showNote.connect(root.showToast)
                        }
                    }
                    // 图示页
                    Loader {
                        active: root.currentNav === 4
                        anchors.fill: parent
                        anchors.margins: 14
                        source: "qrc:/qml/views/TopoView.qml"
                        onLoaded: {
                            item.themeRoot = root
                            item.showNote.connect(root.showToast)
                        }
                    }
                    // 设置页
                    Loader {
                        active: root.currentNav === 5
                        anchors.fill: parent
                        anchors.margins: 14
                        source: "qrc:/qml/views/SettingsView.qml"
                        onLoaded: {
                            item.themeRoot = root
                            item.showNote.connect(root.showToast)
                        }
                    }

                    // 设备状态详情 popover（从点击位置展开，带缩放+淡入动画）
                    Popup {
                        id: devPop
                        width: 360
                        padding: 14
                        modal: false
                        focus: false
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        transformOrigin: Item.Top
                        background: Rectangle { color: root.colCard; border.color: root.colLine; radius: 12 }
                        enter: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; from: 0.6; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                            }
                        }
                        exit: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; from: 1.0; to: 0.6; duration: 150; easing.type: Easing.InCubic }
                                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                            }
                        }
                        onClosed: root.activeDevPop = ""
                        // 打开期间定时刷新数据，保证状态详情实时更新
                        Timer {
                            interval: 500
                            running: devPop.opened
                            repeat: true
                            onTriggered: root.refreshDevPop()
                        }
                        Column {
                            spacing: 8
                            Text {
                                text: root.devPopTitle; font.bold: true; font.pixelSize: 17; color: root.colText
                            }
                            Grid {
                                columns: 2; spacing: 8; columnSpacing: 8
                                Repeater {
                                    model: root.devPopKvs
                                    Rectangle {
                                        width: 158; height: 50; radius: 9; color: root.colCard2
                                        Column {
                                            anchors.centerIn: parent
                                            Text { text: modelData.k; font.pixelSize: 11; color: root.colText2 }
                                            Text { text: modelData.v; font.pixelSize: 17; font.bold: true; font.family: "monospace"; color: root.colText }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 就绪度原因 popover（点击位置下方展开，带缩放+淡入，点击外部关闭）
                    Popup {
                        id: readPop
                        width: 384
                        padding: 14
                        modal: false
                        focus: false
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        // 缩放从顶部中心展开（看起来从就绪度胶囊下方展开）
                        transformOrigin: Item.Top
                        background: Rectangle { color: root.colCard; border.color: root.colLine; radius: 12 }
                        enter: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; from: 0.6; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                            }
                        }
                        exit: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "scale"; from: 1.0; to: 0.6; duration: 150; easing.type: Easing.InCubic }
                                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                            }
                        }
                        Column {
                            spacing: 8
                            Text { text: "整机就绪度 · 原因明细"; font.bold: true; font.pixelSize: 17; color: root.colText }
                            Repeater {
                                model: root.readItems
                                Row {
                                    spacing: 8
                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: modelData.ok ? root.colOk : root.colErr
                                        Text { anchors.centerIn: parent; text: modelData.ok ? "✓" : "✗"; color: "white"; font.pixelSize: 13; font.bold: true }
                                    }
                                    Text { text: modelData.name; font.pixelSize: 14; color: root.colText; width: 180; elide: Text.ElideRight }
                                    Text { text: modelData.val; font.pixelSize: 14; color: root.colText2; font.family: "monospace" }
                                }
                            }
                        }
                    }

                    // Toast 通知容器与卡片组件见文件末尾（对齐原型 .toast-wrap：右上角堆叠）
                }

                // ----- 底部状态栏 -----
                Rectangle {
                    visible: !root.isModuleHidden("statusbar")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    color: colCard
                    border.color: colLine
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 18
                        // 链路
                        Row {
                            visible: !root.isModuleHidden("link")
                            spacing: 6
                            Layout.alignment: Qt.AlignVCenter
                            Rectangle {
                                width: 9; height: 9; radius: 4.5
                                anchors.verticalCenter: parent.verticalCenter
                                // 加 dataTick 依赖：isSerialOpen 是 Q_INVOKABLE 方法调用，
                                // QML 绑定只计算一次不重新求值，必须通过 dataTick 触发刷新
                                color: { void root.dataTick; bridge.isDataLinkOnline() ? root.colOk : root.colOff }
                            }
                            Text {
                                text: { void root.dataTick; bridge.isDataLinkOnline() ? "链路正常" : "链路断开" }
                                font.pixelSize: 12; font.bold: true; font.family: "monospace"
                                anchors.verticalCenter: parent.verticalCenter
                                color: { void root.dataTick; bridge.isDataLinkOnline() ? root.colOk : root.colErr }
                            }
                        }
                        Text { visible: !root.isModuleHidden("rate"); text: "数据率 " + root.fmt(5.0,1) + " Hz"; font.pixelSize: 12; font.family: "monospace"; color: root.colText2; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            visible: !root.isModuleHidden("alarm")
                            Layout.alignment: Qt.AlignVCenter
                            text: { void root.dataTick; "告警 " + bridge.unconfirmedCount() }
                            font.pixelSize: 12; font.bold: true; font.family: "monospace"
                            // B1：color 必须同样依赖 dataTick，否则仅首次求值、出现告警后颜色不刷新
                            color: { void root.dataTick; bridge.unconfirmedCount() > 0 ? root.colErr : root.colOk }
                        }
                        Text {
                            visible: !root.isModuleHidden("uptime")
                            Layout.alignment: Qt.AlignVCenter
                            text: { void root.dataTick; "运行时长 " + root.uptimeStr }
                            font.pixelSize: 12; font.bold: true; font.family: "monospace"
                            color: root.colText
                            // 悬停提示计时起点（从串口打开起）
                            ToolTip.text: "从串口打开开始计时，关闭串口清零"
                            ToolTip.visible: uptimeTipHover.containsMouse
                            ToolTip.delay: 400
                            MouseArea {
                                id: uptimeTipHover
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                        // 最新消息预览
                        Text {
                            text: root.lastMsg
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            elide: Text.ElideRight
                            font.pixelSize: 12; font.family: "monospace"; color: root.colText2
                        }
                        // 本地时间（显式固定高度 + 垂直居中锚定，消除 bold/非 bold 字形基线差）
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: lblTime.width + 6 + clockText.implicitWidth
                            implicitHeight: 20
                            Text {
                                id: lblTime
                                text: "本地时间"
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 12
                                font.family: "monospace"
                                color: root.colText2
                            }
                            Text {
                                id: clockText
                                text: ""
                                anchors.left: lblTime.right
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 12
                                font.bold: true
                                font.family: "monospace"
                                color: root.colText
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== 公共状态：popover / 就绪度明细 / 最新消息 / 运行时长 =====
    property string devPopTitle: ""
    property var devPopKvs: []
    property var readItems: []
    property string lastMsg: "系统就绪"
    property string activeDevPop: ""   // 当前打开的设备详情键（bms/mppt1/dcdc），空=关闭
    property string uptimeStr: "00:00:00"

    function uptimeText() {
        const s = bridge.uptimeSeconds()
        const h = Math.floor(s/3600), m = Math.floor(s%3600/60), ss = s%60
        function pad(n){ return (n<10?"0":"")+n }
        return pad(h)+":"+pad(m)+":"+pad(ss)
    }

    // 刷新设备状态 popover 内容：按当前 activeDevPop 重新读取实时值。
    // 单独抽出供 devPop 打开期间定时调用，保证点开后数据持续更新而非静态快照。
    function refreshDevPop() {
        const dev = root.activeDevPop
        if (!dev) return
        const fields = {
            bms: [["pack_v","总压"],["pack_i","电流"],["max_t","最高温"],["max_v","最高单体"],["diff_v","压差"]],
            mppt1:[["pv_p","光伏功率"],["batt_v","电池电压"],["charge_i","充电电流"],["today","日发电量"],["total","总发电"]],
            dcdc:[["out_v","输出电压"],["out_i","输出电流"],["temp","散热温度"],["in_v","输入电压"],["enabled","使能"]],
            backup:[["pack_v","总压"],["soc","电量"],["diff_v","压差"],["soh","健康度"],["fault","故障码"]]
        }
        const names = {bms:"BMS",mppt1:"MPPT",dcdc:"DCDC",backup:"备用电源"}
        root.devPopTitle = names[dev] + " 状态详情"
        const arr = []
        for (const f of fields[dev]) {
            let v
            if (f[0] === "enabled") v = bridge.value(dev,"enabled")===1 ? "开启" : "关闭"
            else v = root.fmt(bridge.value(dev, f[0]), f[0]==="charge_i"||f[0]==="today"||f[0]==="pack_i" ? 1 : 0)
            arr.push({k:f[1], v:v})
        }
        root.devPopKvs = arr
    }

    function openDevPop(dev, sourceItem) {
        root.activeDevPop = dev
        root.refreshDevPop()
        // 相对窗口定位，水平居中于按钮，紧贴按钮下方 2px，并做屏幕边界钳制防止右侧溢出
        if (sourceItem) {
            var pt = sourceItem.mapToItem(null, 0, sourceItem.height + 2)
            devPop.x = Math.max(8, Math.min(pt.x - devPop.width / 2 + sourceItem.width / 2,
                                            root.width - devPop.width - 8))
            devPop.y = pt.y
        }
        devPop.open()
    }

    function openReadPop(sourceItem) {
        // 就绪度明细：单源消费 C++ readinessDetail()（与 readinessState() 阈值一致，
        // 消除 QML 侧重复硬编码导致的阈值漂移，B4）
        root.readItems = bridge.readinessDetail()
        // 相对窗口定位，水平居中于胶囊，紧贴按钮下方 2px，并做屏幕边界钳制防止右侧溢出
        if (sourceItem) {
            var pt = sourceItem.mapToItem(null, 0, sourceItem.height + 2)
            readPop.x = Math.max(8, Math.min(pt.x - readPop.width / 2 + sourceItem.width / 2,
                                             root.width - readPop.width - 8))
            readPop.y = pt.y
        }
        readPop.open()
    }

    // 应用恢复到前台时重触发曲线同步：Qt 的 ChartView 在窗口不可见时暂停渲染，
    // 恢复后 append 操作不会自动生效，需手动触发 rtcTick 使 chartPanel 重同步。
    onActiveChanged: {
        if (root.active) root.rtcTick++
    }

    // ===== Toast 通知（对齐原型 .toast-wrap/.toast：右上角堆叠，三色卡片 + 滑入滑出）=====
    // 原型：fixed top:64px right:20px；ok 绿 / err 红 / info 蓝（soft 底 + 主色边框文字）；
    // 入场 250ms 弹性滑入，3s 后 200ms 滑出销毁，多条自动纵向堆叠（Column spacing 8px）
    // parent 挂 Overlay 层（弹窗所在层）+ 高 z：保证拉流设置/确认框等 Popup 打开时仍显示在最顶层
    // （Popup 永远高于 contentItem 内普通 Item；卡片无 MouseArea，不拦截弹窗内点击）
    Column {
        id: toastWrap
        parent: Overlay.overlay
        z: 9999
        anchors.top: parent.top
        anchors.topMargin: 64
        anchors.right: parent.right
        anchors.rightMargin: 20
        spacing: 8
    }
    Component {
        id: toastComp
        Item {
            id: toastItem
            property string tMsg: ""
            property string tType: "ok"   // ok | err | info
            readonly property color cMain: tType === "err" ? root.colErr
                                         : tType === "info" ? root.colPrimary : root.colOk
            readonly property color cSoft: tType === "err" ? root.colErrSoft
                                         : tType === "info" ? root.accentSoft : root.colOkSoft
            width: Math.max(220, Math.min(340, toastText.implicitWidth + 28))
            height: toastText.implicitHeight + 20
            opacity: 0
            x: 24
            // 阴影（原型 shadow-3：0 8px 24px rgba(15,23,42,.18)）
            MultiEffect {
                anchors.fill: card
                source: card
                shadowEnabled: true
                shadowColor: "#0f172a"
                shadowOpacity: 0.18
                shadowBlur: 0.3
                shadowVerticalOffset: 8
            }
            Rectangle {
                id: card
                anchors.fill: parent
                radius: 10
                color: toastItem.cSoft
                border.color: toastItem.cMain
                border.width: 1
                Text {
                    id: toastText
                    anchors.centerIn: parent
                    width: Math.min(340 - 28, implicitWidth)   // 超长文本在 340px 卡内换行
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: toastItem.tMsg
                    color: toastItem.cMain
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
            // 入场：右滑入 + 淡入（250ms，cubic-bezier(.2,.9,.3,1.2) 弹性 ≈ OutBack）
            ParallelAnimation {
                id: animIn
                NumberAnimation { target: toastItem; property: "opacity"; to: 1; duration: 250; easing.type: Easing.OutCubic }
                NumberAnimation { target: toastItem; property: "x"; to: 0; duration: 250; easing.type: Easing.OutBack }
            }
            // 出场：右滑出 + 淡出（200ms）后销毁
            SequentialAnimation {
                id: animOut
                ParallelAnimation {
                    NumberAnimation { target: toastItem; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InQuad }
                    NumberAnimation { target: toastItem; property: "x"; to: 24; duration: 200; easing.type: Easing.InQuad }
                }
                ScriptAction { script: toastItem.destroy() }
            }
            Timer { interval: 3000; running: true; onTriggered: animOut.start() }
            Component.onCompleted: animIn.start()
        }
    }

    function showToast(msg, type) {
        toastComp.createObject(toastWrap, { tMsg: String(msg), tType: type || "ok" })
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true;
        onTriggered: {
            clockText.text = new Date().toTimeString().slice(0,8)
            root.uptimeStr = root.uptimeText()
        } }

    // ===== 紧急操作（动作选择 + 滑动确认 + 严重告警，原型演示不下发硬件）=====
    function openEmergency() { emgDlg.open() }
    function execEmergency(kind) {
        bridge.addAlarm("已执行紧急操作：" + kind + "（演示）", "严重", "操作")
        root.lastMsg = "⚠ " + "已执行紧急操作：" + kind
        emgDlg.close()
        emgReset()
        root.showToast("已执行紧急操作：" + kind)
    }
    function emgReset() {
        emgSlide.x = 0
        emgConfirmVisible = false
        emgSelected = -1
    }
    property int emgSelected: -1
    property bool emgConfirmVisible: false
    readonly property var emgActions: ["释放压舱物", "紧急放气", "全机断电"]

    Dialog {
        id: emgDlg
        title: "紧急操作"
        modal: true
        width: 400
        anchors.centerIn: parent
        closePolicy: Popup.CloseOnEscape
        padding: 0
        // 隐藏默认直角标题栏，自定义圆角 header 融入整体圆角
        header: null
        background: Item {
            // 投影
            MultiEffect {
                anchors.fill: parent
                source: bgRect
                shadowEnabled: true
                shadowBlur: 0.6
                shadowColor: root.dark ? "#99000000" : "#33000000"
                shadowVerticalOffset: 10
            }
            // 圆角主体
            Rectangle {
                id: bgRect
                anchors.fill: parent
                radius: 20
                color: root.colCard
                border.color: root.colLine
            }
        }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "scale"; from: 0.85; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "scale"; from: 1.0; to: 0.85; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
            }
        }
        contentItem: ColumnLayout {
            spacing: 0
            // 圆角标题栏（融入弹窗顶部圆角）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 20
                color: root.colErrSoft
                border.color: "transparent"
                // 只圆顶部两角，底部贴合主体
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 20
                    color: root.colErrSoft
                }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 10
                    Text { text: "⚠ 紧急操作"; font.bold: true; font.pixelSize: 15; color: root.colErr }
                    Item { Layout.fillWidth: true }
                    Button {
                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                        scale: pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        HoverHandler {
                            id: hover_3
                            cursorShape: Qt.PointingHandCursor
                        }
                        text: "✕"
                        width: 30; height: 30
                        background: Rectangle {
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            radius: 8; color: "transparent"
                            border.color: "transparent"
                        }
                        contentItem: Text { text: parent.text; color: root.colText2; font.pixelSize: 15; anchors.centerIn: parent }
                        onClicked: emgDlg.close()
                        hoverEnabled: true
                        onHoveredChanged: background.color = hovered ? (root.dark ? "#33ffffff" : "#22000000") : "transparent"
                    }
                }
            }
            // 内容区
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                spacing: 12
                Text {
                    text: "以下操作危险且不可逆，请选择动作并向右滑动确认后执行（原型演示）。"
                    color: root.colText2; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Repeater {
                    model: root.emgActions
                    Rectangle {
                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                        scale: ma_3.pressed ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Layout.fillWidth: true; Layout.preferredHeight: 42; radius: 10
                        color: root.emgSelected === index ? root.colErrSoft : root.colCard2
                        border.color: root.emgSelected === index ? root.colErr : root.colLine
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: root.emgSelected === index ? root.colErr : root.colText
                            font.bold: root.emgSelected === index
                        }
                        MouseArea {
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            id: ma_3
                            anchors.fill: parent
                            onClicked: root.emgSelected = index
                        }
                    }
                }
                // 滑动确认条
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 14
                    color: root.emgSelected < 0 ? root.colCard2 : root.colErrSoft
                    border.color: root.emgSelected < 0 ? root.colLine : root.colErr
                    clip: true
                    // 填充
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: emgSlide.x
                        color: root.colErr; opacity: 0.25
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.emgSelected < 0 ? "请先选择操作" : (root.emgConfirmVisible ? "" : "⟹  向右滑动确认")
                        color: root.colErr; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "✓ 已确认执行（演示）"
                        color: root.colOk; font.bold: true; font.pixelSize: 13
                        visible: root.emgConfirmVisible
                    }
                    Rectangle {
                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                        scale: ma_4.pressed ? 0.96 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        id: emgSlide
                        width: 42; height: 42; radius: 12
                        color: root.emgConfirmVisible ? root.colOk : root.colErr
                        y: 3
                        Text {
                            anchors.centerIn: parent
                            text: root.emgConfirmVisible ? "✓" : "→"
                            color: "white"; font.bold: true; font.pixelSize: 18
                        }
                        MouseArea {
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            id: ma_4
                            anchors.fill: parent
                            drag.target: emgSlide
                            drag.axis: Drag.XAxis
                            drag.minimumX: 0
                            drag.maximumX: emgSlide.parent.width - 48
                            onPositionChanged: {
                                if (drag.active && emgSlide.x > emgSlide.parent.width - 60)
                                    root.emgConfirmVisible = true
                            }
                            onReleased: {
                                if (emgSlide.x > emgSlide.parent.width - 60) {
                                    if (root.emgSelected >= 0)
                                        root.execEmergency(root.emgActions[root.emgSelected])
                                } else {
                                    root.emgReset()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 实时曲线采样（常驻顶层，无论当前在哪页都持续采样，保证曲线连续）
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (!root.rtcPlaying) return   // 暂停时不采样
            const v = bridge.value("bms","pack_v"), pv = bridge.value("mppt1","pv_p")
            const op = bridge.value("dcdc","out_p"), i = bridge.value("bms","pack_i")
            root.rtcData.v.push(isNaN(v)?0:v); root.rtcData.pv.push(isNaN(pv)?0:pv)
            root.rtcData.outp.push(isNaN(op)?0:op); root.rtcData.i.push(isNaN(i)?0:i)
            if (root.rtcData.v.length > root.rtcMax) {
                root.rtcData.v.shift(); root.rtcData.pv.shift()
                root.rtcData.outp.shift(); root.rtcData.i.shift()
            }
            root.rtcIdx++
            root.rtcTick++   // 触发 chartPanel.syncSeries 增量追加
        }
    }

    // 飞艇位置更新（常驻顶层，每秒更新）：与 rtcData 同理，无论当前在哪页都持续累积轨迹。
    // P3：优先使用真实飞控遥测（数传 UDP 含 fc.lon/lat/alt/yaw/gs）——地图箭头/轨迹跟随真实位置；
    //      fc 离线（串口+UDP 均无飞控数据）时回退椭圆模拟，保证无数据时仍可演示。
    // 注：模拟分支仅在"从未收到真实位置"时运行；一旦收到过真实位置，fc 离线则停在最后位置
    // （不跳回模拟，避免演示/作业切换时地图箭头跳变）。
    property bool mapHasRealPos: false
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const fcLon = bridge.value("fc","lon")
            const fcLat = bridge.value("fc","lat")
            const hasReal = !isNaN(fcLon) && !isNaN(fcLat)
            if (hasReal) {
                // 真实遥测：位置/航向/高度/速度全部取 fc
                root.mapAirPos.lon = fcLon
                root.mapAirPos.lat = fcLat
                const yaw = bridge.value("fc","yaw")
                if (!isNaN(yaw)) root.mapHeading = yaw
                const alt = bridge.value("fc","alt")
                if (!isNaN(alt)) root.mapAlt = alt
                const gs = bridge.value("fc","gs")
                if (!isNaN(gs) && gs >= 0) root.mapSpeed = gs
                root.mapHasRealPos = true
            } else if (!root.mapHasRealPos) {
                // 从未收到真实位置：保留原椭圆模拟（演示）
                const t = Date.now() / 1000
                const r = 0.004
                root.mapAirPos.lon = root.mapHomePos.lon + r * Math.cos(t * 0.3)
                root.mapAirPos.lat = root.mapHomePos.lat + r * Math.sin(t * 0.3)
                root.mapHeading = (t * 20) % 360
                root.mapAlt = 150 + 30 * Math.sin(t * 0.2)
                root.mapSpeed = 10 + 3 * Math.sin(t * 0.4)
            }
            // 累积轨迹点
            root.mapTrack.push({lon: root.mapAirPos.lon, lat: root.mapAirPos.lat})
            if (root.mapTrack.length > 500) root.mapTrack.shift()
            // 距离与方位（近似，忽略海拔）
            const dLat = (root.mapAirPos.lat - root.mapHomePos.lat) * 111320
            const dLon = (root.mapAirPos.lon - root.mapHomePos.lon) * 111320 * Math.cos(root.mapHomePos.lat * Math.PI / 180)
            root.mapDist = Math.sqrt(dLat * dLat + dLon * dLon)
            root.mapBearing = (Math.atan2(dLon, dLat) * 180 / Math.PI + 360) % 360
            // 跟随：跟随模式下面板中心点跟随飞艇，否则保持用户视口
            if (root.mapFollow) {
                root.mapCenterLon = root.mapAirPos.lon
                root.mapCenterLat = root.mapAirPos.lat
            }
            root.mapTick++   // 驱动地图页重绘（切出时无订阅，切回仍与最新位置同步）
        }
    }

    // ===== 全局快捷键（与设置页提示一致）=====
    // 1-6 切换视图 · 空格 暂停曲线 · T 主题 · D 密度
    Shortcut { sequence: "1"; onActivated: root.currentNav = 0 }
    Shortcut { sequence: "2"; onActivated: root.currentNav = 1 }
    Shortcut { sequence: "3"; onActivated: root.currentNav = 2 }
    Shortcut { sequence: "4"; onActivated: root.currentNav = 3 }
    Shortcut { sequence: "5"; onActivated: root.currentNav = 4 }
    Shortcut { sequence: "6"; onActivated: root.currentNav = 5 }
    Shortcut {
        sequence: "Space"
        onActivated: root.rtcPlaying = !root.rtcPlaying
    }
    Shortcut {
        sequence: "T"
        onActivated: root.dark = !root.dark
    }
    Shortcut {
        sequence: "D"
        onActivated: root.dense = !root.dense
    }
}

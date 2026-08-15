import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// 摄像头监控（1:1 复刻原型 #view-camera + 设计文档《摄像头页面落地设计》）：
// 动态相机配置（RTSP 拉流设置，JSON 持久化）· tab 多选（FIFO 顶掉）· 四档布局（1/2/4/全）·
// 画面比例 16:9/4:3/1:1/填充 · OSD 叠加 · 悬浮控制 · 截图/录像/重连。视频区域为深色渐变占位。
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)

    // ===== 相机配置（对齐原型 CamConfig，id 主键稳定）=====
    property var camCfg: []          // [{id,name,enable,ip,port,path,user,pass,stream,transport,fps}]
    property var selected: []        // 当前选中（显示）的相机索引集合（多选）
    property string layMode: "1"     // 布局档位：1/2/4/a（全部）
    property string camCfgSel: ""    // 拉流设置当前编辑相机 id
    property int camSeq: 0           // 相机 id 自增序号（删除后不复用）
    property bool osdOn: true        // OSD 叠加开关
    property bool recOn: false       // 录像状态
    property int recStart: 0         // 录像开始时间戳
    property bool connBusy: false    // 重连中
    // 画面比例（对齐原型 camRatio）：16:9 / 4:3 / 1:1 / 填充，点击循环切换
    property var ratios: [["16:9","16:9"],["4:3","4:3"],["1:1","1:1"],["auto","填充"]]
    property int ratioIdx: 0

    // ===== 默认相机配置（对齐原型 CAM_CFG_DEFAULT）=====
    property var camDefault: [
        {id:"cam_0", name:"前视相机", enable:true,  ip:"192.168.1.101", port:554, path:"/live/stream1", user:"admin", pass:"12345", stream:"主码流", transport:"TCP", fps:25},
        {id:"cam_1", name:"后视相机", enable:true,  ip:"192.168.1.102", port:554, path:"/live/stream1", user:"admin", pass:"12345", stream:"主码流", transport:"TCP", fps:25},
        {id:"cam_2", name:"吊舱相机", enable:false, ip:"192.168.1.103", port:554, path:"/live/stream2", user:"admin", pass:"12345", stream:"主码流", transport:"UDP", fps:25},
        {id:"cam_3", name:"地面相机", enable:true,  ip:"192.168.1.104", port:554, path:"/live/stream1", user:"admin", pass:"12345", stream:"主码流", transport:"TCP", fps:25}
    ]

    function toast(msg) { root.showNote(msg) }

    function fmtTs(ts) {
        var d = new Date(ts)
        function p(n) { return n < 10 ? "0" + n : "" + n }
        return d.getFullYear() + "-" + p(d.getMonth()+1) + "-" + p(d.getDate())
             + " " + p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
    }

    // ===== 相机配置工具（对齐原型 JS）=====
    function limitOf(m) {
        return m === "1" ? 1 : m === "2" ? 2 : m === "4" ? 4 : Math.max(1, root.camCfg.length)
    }
    function defaultSelected(m) {
        if (m === "a") return root.camCfg.map(function(_, i) { return i })
        var lim = limitOf(m)
        var arr = []
        for (var k = 0; k < root.camCfg.length && k < lim; k++) arr.push(k)
        return arr
    }
    function camRtspUrl(i) {
        var c = root.camCfg[i]
        if (!c) return ""
        var cred = c.user ? c.user + ":" + c.pass + "@" : ""
        return "rtsp://" + cred + c.ip + ":" + c.port + c.path
    }
    function camRtspUrlMasked(i) {
        var c = root.camCfg[i]
        if (!c) return ""
        var cred = c.user ? c.user + ":*****@" : ""
        return "rtsp://" + cred + c.ip + ":" + c.port + c.path
    }
    // 解析完整 RTSP 地址 → 参数字段（用户名/密码/端口/路径均可省略）
    function parseRtspUrl(str) {
        var m = String(str).match(/^rtsp:\/\/(?:([^:\/@]+)(?::([^@\/]*))?@)?([^:\/\s]+)(?::(\d+))?([^\s]*)?/)
        if (!m) return null
        return {user:m[1]||"", pass:m[2]||"", ip:m[3]||"", port:m[4]?parseInt(m[4]):554, path:m[5]||"/"}
    }
    function camIdxOf(id) {
        for (var i = 0; i < root.camCfg.length; i++)
            if (root.camCfg[i].id === id) return i
        return -1
    }
    // 布局档位对应的网格列数（对齐原型 applyLayout）
    function gridCols() {
        var cnt = root.selected.length || 1
        if (root.layMode === "1") return 1
        if (root.layMode === "2") return 2
        if (root.layMode === "4") return 2
        return Math.max(1, Math.ceil(Math.sqrt(cnt))) // a 档按选中数均分
    }
    // 保存相机配置 + 布局档位
    function saveAll() {
        bridge.saveCameraConfigs(root.camCfg)
        bridge.setCameraLay(root.layMode)
    }

    // ===== 初始化：加载配置 / 布局档位，填充默认选中 =====
    Component.onCompleted: {
        var cfg = bridge.cameraConfigs()
        if (!cfg || cfg.length === 0) {
            root.camCfg = root.camDefault.map(function(c){ return Object.assign({}, c) })
            bridge.saveCameraConfigs(root.camCfg)
        } else {
            root.camCfg = cfg
        }
        // 相机 id 序号（不复用）
        var mx = 0
        for (var i = 0; i < root.camCfg.length; i++) {
            var m = String(root.camCfg[i].id).match(/(\d+)$/)
            if (m) mx = Math.max(mx, parseInt(m[1]))
        }
        root.camSeq = mx + 1
        root.layMode = bridge.cameraLay()
        root.camCfgSel = root.camCfg.length ? root.camCfg[0].id : ""
        root.selected = root.defaultSelected(root.layMode)
        root.renderCfgForm()
    }

    // 状态点呼吸动画（对齐原型 .cam-tag .dot 的 pulse 动画，1.6s 循环）
    component PulseDot: Item {
        property color dotColor: "#22c55e"
        width: 6; height: 6
        Rectangle {
            anchors.centerIn: parent; width: 6; height: 6; radius: 3
            color: parent.dotColor
        }
        Rectangle {
            anchors.centerIn: parent; width: 6; height: 6; radius: 3
            color: "transparent"; border.width: 2; border.color: parent.dotColor
            scale: 1.0
            opacity: 0.7
            SequentialAnimation on scale {
                running: true; loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 3.0; duration: 800 }
                NumberAnimation { from: 3.0; to: 1.0; duration: 0 }
            }
            SequentialAnimation on opacity {
                running: true; loops: Animation.Infinite
                NumberAnimation { from: 0.7; to: 0.0; duration: 800 }
                NumberAnimation { from: 0.0; to: 0.7; duration: 0 }
            }
        }
    }

    // 虚线分隔线（对齐原型 border-top:1px dashed var(--line)，QML Rectangle 不支持虚线，用小段拼接）
    component DashLine: Item {
        id: dashRoot
        property color lineColor: root.themeRoot.colLine
        height: 1
        Row {
            anchors.fill: parent
            spacing: 4
            clip: true
            Repeater {
                model: Math.max(1, Math.ceil(parent.width / 8))
                Rectangle { width: 4; height: 1; color: dashRoot.lineColor }
            }
        }
    }

    // 输入框（对齐原型 .cf-row input：高 33px，padding 8px 10px，border line，radius 8，bg card-2，13px；focus 边框变 primary + ring 光晕）
    component CFInput: TextField {
        id: field
        height: 33
        leftPadding: 10
        rightPadding: 10
        topPadding: 7
        bottomPadding: 7
        font.pixelSize: 13
        color: root.themeRoot.colText
        placeholderTextColor: Qt.rgba(root.themeRoot.colText2.r, root.themeRoot.colText2.g, root.themeRoot.colText2.b, 0.7)
        selectByMouse: true
        background: Rectangle {
            radius: 8
            color: root.themeRoot.colCard2
            border.color: field.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine
            // focus ring（对齐 box-shadow:0 0 0 3px var(--ring)）
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.width: 3
                border.color: root.themeRoot.colPrimary
                opacity: field.activeFocus ? 0.12 : 0
            }
        }
    }

    // 下拉框（对齐原型 .cf-row select：高 35px，padding 8px 10px，border line，radius 8，bg card-2，13px；focus 同输入框）
    component CFSelect: ComboBox {
        id: sel
        height: 35
        leftPadding: 10
        rightPadding: 30
        font.pixelSize: 13
        contentItem: Text {
            text: sel.displayText
            font: sel.font
            color: root.themeRoot.colText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        // 下拉箭头（▾）
        indicator: Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 8
            text: "▾"
            color: root.themeRoot.colText2
            font.pixelSize: 12
        }
        background: Rectangle {
            radius: 8
            color: root.themeRoot.colCard2
            border.color: sel.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.width: 3
                border.color: root.themeRoot.colPrimary
                opacity: sel.activeFocus ? 0.12 : 0
            }
        }
        // 下拉弹出层（白底圆角列表）
        popup: Popup {
            y: sel.height + 4
            width: sel.width
            implicitHeight: Math.min(contentItem.implicitHeight, 200)
            padding: 4
            background: Rectangle {
                color: root.themeRoot.colCard
                radius: 8
                border.color: root.themeRoot.colLine
            }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: sel.popup.visible ? sel.delegateModel : null
                currentIndex: sel.highlightedIndex
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }
        delegate: ItemDelegate {
            width: sel.width - 8
            height: 30
            highlighted: sel.highlightedIndex === index
            background: Rectangle {
                color: highlighted ? root.themeRoot.colPrimarySoft : "transparent"
                radius: 6
            }
            contentItem: Text {
                text: modelData
                color: highlighted ? root.themeRoot.colPrimary : root.themeRoot.colText
                font.pixelSize: 13
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ===== 顶部标题栏（.cam-head）=====
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: 12
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                // 标题 + 摄像机图标
                Row {
                    spacing: 8
                    Text { text: "🎥"; font.pixelSize: 18; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "摄像头监控"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                }
                // 网口状态胶囊（.cam-stat）
                Rectangle {
                    Layout.preferredHeight: 24
                    implicitWidth: statLbl.implicitWidth + 26
                    radius: 999
                    color: root.themeRoot.colOkSoft
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { width: 7; height: 7; radius: 3.5; color: root.themeRoot.colOk; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            id: statLbl
                            text: "网口已连接"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colOk
                        }
                    }
                }
                // 链路说明（原 camMeta 位置，紧邻网口状态：数传网口直连）
                Text {
                    text: "数传网口直连 · 与串口遥测独立并行"
                    font.pixelSize: 11; color: root.themeRoot.colText2
                }
                Item { Layout.fillWidth: true }
                // 配置提醒（RTSP 拉流前提：摄像头与地面站网口同子网 + 固定 IP），置于拉流设置左侧
                Text {
                    text: "⚠ 需将摄像头配置为与地面站同网段的静态 IP"
                    font.pixelSize: 11; color: root.themeRoot.colWarn
                }
                // 拉流设置按钮（.cam-btn #camCfgBtn，齿轮图标）
                Button {
                    text: "⚙ 拉流设置"
                    Layout.preferredHeight: 30
                    background: Rectangle {
                        radius: 8; color: root.themeRoot.colCard2; border.color: (hoverCfg.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    HoverHandler { id: hoverCfg; cursorShape: Qt.PointingHandCursor }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: { root.renderCfgForm(); camCfgDlg.open() }
                }
            }
        }

        // ===== 相机 tab 栏（.cam-tabs，多选 toggle，横向可滚动）=====
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            clip: true
            spacing: 6
            Repeater {
                model: root.camCfg
                Rectangle {
                    id: tabItem
                    property bool tabActive: root.selected.indexOf(index) >= 0
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: tabMa.pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    width: tabLbl.implicitWidth + 28
                    height: 30
                    radius: 8
                    color: tabActive ? root.themeRoot.colPrimary : root.themeRoot.colCard
                    border.color: tabActive ? root.themeRoot.colPrimary : root.themeRoot.colLine
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            // 状态点：启用=绿，停用=灰（对齐原型）
                            color: modelData.enable ? root.themeRoot.colOk : root.themeRoot.colOff
                        }
                        Text {
                            id: tabLbl
                            text: modelData.name
                            font.pixelSize: 12; font.weight: Font.DemiBold
                            color: tabActive ? "#ffffff" : root.themeRoot.colText2
                        }
                    }
                    MouseArea {
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        id: tabMa
                        anchors.fill: parent
                        onClicked: {
                            // tab 多选 toggle：点已选=取消；未选=选中，满上限顶掉最早选中（FIFO）
                            var arr = root.selected.slice()
                            var pos = arr.indexOf(index)
                            if (pos >= 0) {
                                arr.splice(pos, 1)
                                root.selected = arr
                                root.toast("已取消 " + modelData.name)
                            } else {
                                var lim = root.limitOf(root.layMode)
                                if (arr.length >= lim) arr.shift()
                                arr.push(index)
                                root.selected = arr
                                root.toast("已选择 " + modelData.name)
                            }
                        }
                    }
                }
            }
        }

        // ===== 视频舞台（.cam-stage 居中容器 + .cam-grid 网格）=====
        Rectangle {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: root.themeRoot.colCard2
            border.color: root.themeRoot.colLine
            clip: true

            // 全不选时的占位（.cam-empty 虚线框）
            Rectangle {
                visible: root.selected.length === 0
                anchors.centerIn: parent
                width: parent.width - 16; height: parent.height - 16
                radius: 12
                color: root.themeRoot.colCard2
                border.width: 1
                border.color: root.themeRoot.colLine
                Text {
                    anchors.centerIn: parent
                    text: "未选择相机，请点击上方 tab 选择"
                    font.pixelSize: 13; color: root.themeRoot.colText2
                }
            }

            // 网格：整体按所选比例计算尺寸并居中（对齐原型 fitCam，扣除 16px 内边距）
            GridLayout {
                id: grid
                visible: root.selected.length > 0
                property bool fillStage: root.ratios[root.ratioIdx][0] === "auto"
                property real ratio: root.ratios[root.ratioIdx][0] === "16:9" ? 16/9
                                   : root.ratios[root.ratioIdx][0] === "4:3" ? 4/3 : 1
                property real availW: parent.width - 16
                property real availH: parent.height - 16
                width: fillStage ? parent.width : Math.min(availW, availH * ratio)
                height: fillStage ? parent.height : width / ratio
                anchors.centerIn: parent
                columns: root.gridCols()
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    id: camRep
                    model: root.camCfg
                    // 画面格（.cam-view）：只显示选中集中的相机
                    Item {
                        id: viewItem
                        property bool viewOn: root.selected.indexOf(index) >= 0
                        property bool live: modelData.enable
                        property bool viewActive: viewOn && root.layMode === "1" ? true : viewOn && root.selected.length === 1
                        visible: viewOn
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // 按压缩放反馈（对齐原型 .cam-view active ring）
                        scale: viewOn && root.selected.length === 1 && root.layMode !== "a" && root.selected[0] === index ? 1.0 : 1.0

                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            clip: true
                            color: "black"
                            border.width: viewOn && root.selected.length === 1 ? 2 : 1
                            border.color: viewOn && root.selected.length === 1 ? root.themeRoot.colPrimary : root.themeRoot.colLine

                            // 全画面 hover 检测（.cam-view:hover 显示 cam-ov），z 最低不拦截其它交互
                            MouseArea {
                                id: viewHover
                                anchors.fill: parent
                                hoverEnabled: true
                                z: 0
                            }

                            // 视频画面占位（深蓝径向渐变模拟），radius 与外层一致
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#26334d" }
                                    GradientStop { position: 0.55; color: "#0d1524" }
                                    GradientStop { position: 1.0; color: "#060a12" }
                                }
                            }
                            // 相机轮廓 SVG（.cam-pic，白色描边 120px opacity .12）
                            Rectangle {
                                anchors.centerIn: parent
                                width: 120; height: 120
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: "qrc:/qml/img/camera.svg"
                                    fillMode: Image.PreserveAspectFit
                                    opacity: 0.14
                                }
                            }
                            // 占位文字（.cam-no）：启用=画面占位，停用=未启用
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name + " · " + (viewItem.live ? "画面占位" : "未启用")
                                    font.pixelSize: 13; font.weight: Font.DemiBold; color: "#8ba3c2"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: viewItem.live ? "接入网口视频流后实时显示" : "等待拉流设置"
                                    font.pixelSize: 11; color: "#5f718d"
                                }
                            }

                            // 单路标签（.cam-tag 左上角，黑45%底 + 模糊 + 呼吸状态点）
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 10
                                height: 24
                                implicitWidth: tagRow.implicitWidth + 18
                                radius: 6
                                color: Qt.rgba(0,0,0,0.45)
                                Row {
                                    id: tagRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    PulseDot {
                                        anchors.verticalCenter: parent.verticalCenter
                                        dotColor: viewItem.live ? "#16a34a" : "#dc2626"
                                    }
                                    Text {
                                        text: modelData.name + " · " + (viewItem.live ? "LIVE" : "OFFLINE")
                                        font.pixelSize: 11; font.weight: Font.Bold; color: "#ffffff"
                                    }
                                }
                            }

                            // OSD 参数叠加（.cam-osd 右下角，仅启用相机显示）
                            Rectangle {
                                visible: root.osdOn && viewItem.live
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                width: osdCol.implicitWidth + 20
                                height: osdCol.implicitHeight + 12
                                radius: 6
                                color: Qt.rgba(0,0,0,0.4)
                                Column {
                                    id: osdCol
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text { text: "2026-08-14 10:23:45"; font.pixelSize: 11; font.family: "monospace"; color: "#ffffff"; font.weight: Font.Bold }
                                    Text { text: "LAT 30.26715°N    LON 120.15342°E"; font.pixelSize: 11; font.family: "monospace"; color: "#cfe0ff" }
                                    Text { text: "ALT 150.2m    SPD 12.5m/s    HDG 087°"; font.pixelSize: 11; font.family: "monospace"; color: "#cfe0ff" }
                                }
                            }

                            // 悬浮控制（.cam-ov 右上角，hover 才显示：放大 + 截图）
                            Row {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 10
                                spacing: 5
                                opacity: viewHover.containsMouse ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Rectangle {
                                    width: 26; height: 26; radius: 6
                                    color: ovZoomMa.pressed ? root.themeRoot.colPrimary : Qt.rgba(0,0,0,0.5)
                                    Text { anchors.centerIn: parent; text: "⛶"; color: "#ffffff"; font.pixelSize: 12 }
                                    MouseArea {
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        id: ovZoomMa
                                        anchors.fill: parent
                                        onClicked: root.toast("已放大 " + modelData.name + "（占位）")
                                    }
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 6
                                    color: ovShotMa.pressed ? root.themeRoot.colPrimary : Qt.rgba(0,0,0,0.5)
                                    Text { anchors.centerIn: parent; text: "📷"; color: "#ffffff"; font.pixelSize: 12 }
                                    MouseArea {
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        id: ovShotMa
                                        anchors.fill: parent
                                        onClicked: {
                                            var dir = bridge.cameraDir()
                                            var name = "snapshot_" + Date.now() + ".png"
                                            viewItem.grabToImage(function(result) {
                                                if (result.saveToFile("file://" + dir + "/" + name))
                                                    root.toast("已保存截图 " + name)
                                                else
                                                    root.toast("截图保存失败")
                                            })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===== 底部控制条（.cam-bar）=====
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: 12
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                // 截图（.cam-btn #camShot）
                Button {
                    text: "📷 截图"
                    Layout.preferredHeight: 32
                    background: Rectangle { radius: 8; color: root.themeRoot.colCard2; border.color: (hoverShot.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } } }
                    HoverHandler { id: hoverShot; cursorShape: Qt.PointingHandCursor }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: {
                        if (!root.selected.length) { root.toast("请先选择相机"); return }
                        var idx = root.selected[0]
                        var it = camRep.itemAt(idx)
                        if (!it) { root.toast("无可用画面，截图失败"); return }
                        var dir = bridge.cameraDir()
                        var name = "snapshot_" + Date.now() + ".png"
                        it.grabToImage(function(result) {
                            if (result.saveToFile("file://" + dir + "/" + name))
                                root.toast("已保存截图 " + name)
                            else
                                root.toast("截图保存失败")
                        })
                    }
                }
                // 录像（.cam-btn rec，红色脉冲；图标：未录=圆圈+中心点，录制中=白色方块）
                Button {
                    id: recBtn
                    text: root.recOn ? "停止录像" : "录像"
                    Layout.preferredHeight: 32
                    background: Rectangle {
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        radius: 8
                        color: root.recOn ? root.themeRoot.colErr : root.themeRoot.colCard2
                        border.color: root.recOn ? root.themeRoot.colErr : root.themeRoot.colLine
                    }
                    HoverHandler { id: hoverRec; cursorShape: Qt.PointingHandCursor }
                    // contentItem 需暴露 implicitWidth，否则 Button 宽度塌缩与相邻按钮重叠
                    contentItem: Item {
                        anchors.fill: parent
                        implicitWidth: recRow.implicitWidth
                        implicitHeight: recRow.implicitHeight
                        RowLayout {
                            id: recRow
                            anchors.centerIn: parent
                            spacing: 6
                            // 图标：圆圈+中心点（对齐原型 camRec 圆环图标，中心加实心点）
                            Rectangle {
                                width: 12; height: 12
                                radius: root.recOn ? 3 : 6
                                color: root.recOn ? "#ffffff" : "transparent"
                                border.width: root.recOn ? 0 : 2
                                border.color: root.recOn ? "transparent" : root.themeRoot.colText
                                Rectangle {
                                    visible: !root.recOn
                                    anchors.centerIn: parent
                                    width: 4; height: 4; radius: 2
                                    color: root.themeRoot.colText
                                }
                            }
                            Text {
                                text: recBtn.text
                                color: root.recOn ? "#ffffff" : root.themeRoot.colText
                                font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                        }
                    }
                    onClicked: {
                        if (!root.recOn) {
                            root.recOn = true
                            root.recStart = Date.now()
                            bridge.cameraDir()
                            root.toast("开始录像（保存至本地）")
                        } else {
                            root.recOn = false
                            var dur = Math.max(1, Math.round((Date.now() - root.recStart) / 1000))
                            var dir = bridge.cameraDir()
                            var name = "rec_" + Date.now() + ".txt"
                            var camName = root.selected.length ? root.camCfg[root.selected[0]].name : "未选择"
                            var content = "灵云01 摄像头录像会话\n"
                                + "相机：" + camName + "\n"
                                + "开始时间：" + root.fmtTs(root.recStart) + "\n"
                                + "结束时间：" + root.fmtTs(Date.now()) + "\n"
                                + "时长：" + dur + " 秒\n"
                                + "说明：当前为会话占位记录，接入网口视频流后替换为真实视频文件"
                            var ok = bridge.writeTextFile(dir + "/" + name, content)
                            root.toast(ok ? "录像已保存 " + name : "录像保存失败")
                        }
                    }
                }
                // OSD 叠加（.cam-btn on）
                Button {
                    text: "≡ OSD 叠加"
                    Layout.preferredHeight: 32
                    background: Rectangle {
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        radius: 8
                        color: root.osdOn ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                        border.color: root.osdOn ? root.themeRoot.colPrimary : root.themeRoot.colLine
                    }
                    HoverHandler { id: hoverOsd; cursorShape: Qt.PointingHandCursor }
                    contentItem: Text {
                        text: parent.text; color: root.osdOn ? "#ffffff" : root.themeRoot.colText
                        font.pixelSize: 12; font.weight: Font.DemiBold
                        anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        root.osdOn = !root.osdOn
                        root.toast(root.osdOn ? "OSD 叠加已开启" : "OSD 叠加已关闭")
                    }
                }
                // 画面比例切换（.cam-btn #camRatio）
                Button {
                    text: "比例 " + root.ratios[root.ratioIdx][1]
                    Layout.preferredHeight: 32
                    background: Rectangle { radius: 8; color: root.themeRoot.colCard2; border.color: (hoverRatio.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } } }
                    HoverHandler { id: hoverRatio; cursorShape: Qt.PointingHandCursor }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: {
                        root.ratioIdx = (root.ratioIdx + 1) % root.ratios.length
                        root.toast("画面比例：" + root.ratios[root.ratioIdx][1])
                    }
                }
                // 分隔线
                Rectangle { width: 1; height: 20; color: root.themeRoot.colLine }
                // 重连（.cam-btn #camConn，点击后 1.2s 恢复提示）
                Button {
                    text: "↻ 重连"
                    Layout.preferredHeight: 32
                    background: Rectangle {
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        radius: 8
                        color: root.connBusy ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                        border.color: root.connBusy ? root.themeRoot.colPrimary : root.themeRoot.colLine
                    }
                    HoverHandler { id: hoverConn; cursorShape: Qt.PointingHandCursor }
                    contentItem: Text {
                        text: parent.text; color: root.connBusy ? "#ffffff" : root.themeRoot.colText
                        font.pixelSize: 12; font.weight: Font.DemiBold
                        anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        root.connBusy = true
                        root.toast("正在重连网口视频流…")
                        connTimer.restart()
                    }
                    Timer {
                        id: connTimer; interval: 1200
                        onTriggered: { root.connBusy = false; root.toast("网口视频流已恢复") }
                    }
                }
                Rectangle { width: 1; height: 20; color: root.themeRoot.colLine }
                Text {
                    text: "截图/录像保存至本地 · 视频数据来自数传网口"
                    font.pixelSize: 11; color: root.themeRoot.colText2
                }
                Item { Layout.fillWidth: true }

                // 布局切换（.cam-lay：单路/双路/四路/全 四档）
                Row {
                    spacing: 3
                    Repeater {
                        model: [ ["1","1",true], ["2","2",true], ["4","4",true], ["a","全",false] ]
                        Rectangle {
                            property bool layActive: root.layMode === modelData[0]
                            width: modelData[2] ? 26 : 34
                            height: 26; radius: 6
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: layMa.pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            color: layActive ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                            border.color: layActive ? root.themeRoot.colPrimary : root.themeRoot.colLine
                            // 点点图标：四路 2×2 田字；全=文字
                            Grid {
                                anchors.centerIn: parent
                                visible: modelData[2]
                                columns: modelData[0] === "1" ? 1 : 2
                                spacing: 2
                                Repeater {
                                    model: modelData[0] === "1" ? 1 : modelData[0] === "2" ? 2 : modelData[0] === "4" ? 4 : 0
                                    Rectangle {
                                        width: 5; height: 5; radius: 1
                                        color: layActive ? "#ffffff" : root.themeRoot.colText2
                                    }
                                }
                            }
                            Text {
                                visible: !modelData[2]
                                anchors.centerIn: parent
                                text: modelData[1]
                                font.pixelSize: 12; font.weight: Font.Bold
                                color: layActive ? "#ffffff" : root.themeRoot.colText2
                            }
                            MouseArea {
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                id: layMa
                                anchors.fill: parent
                                onClicked: root.setLayMode(modelData[0])
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== 布局档位切换（对齐原型：全=强制全选；其余=裁剪超限+补足到上限）=====
    function setLayMode(m) {
        root.layMode = m
        bridge.setCameraLay(m)
        if (m === "a") {
            root.selected = root.camCfg.map(function(_, i) { return i })
        } else {
            var lim = root.limitOf(m)
            var arr = root.selected.slice()
            while (arr.length > lim) arr.shift()                       // 裁剪超限（保留最早选中）
            for (var k = 0; k < root.camCfg.length && arr.length < lim; k++)
                if (arr.indexOf(k) < 0) arr.push(k)                    // 补足到上限（按序补）
            root.selected = arr
        }
        root.saveAll()
    }

    // ===== 相机拉流设置弹窗（对齐原型 modal 结构：head + body 滚动 + 表单 + cf-actions）=====
    Popup {
        id: camCfgDlg
        modal: true
        anchors.centerIn: parent
        // 对齐 .modal{width:420px;max-width:92vw;max-height:92vh}；阴影 0 4px 16px rgba(15,23,42,.05)
        width: Math.min(420, parent.width * 0.92)
        height: parent.height * 0.92
        padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            color: root.themeRoot.colCard
            radius: 14
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(15/255, 23/255, 42/255, 0.10)
                shadowBlur: 0.5
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 4
            }
        }
        // 弹窗遮罩（对齐原型 rgba(15,23,42,.5) 深蓝黑；QML Qt.rgba 参数为 0-1，需除以 255）
        Overlay.modal: Component { Rectangle { color: Qt.rgba(15/255, 23/255, 42/255, 0.5) } }

        contentItem: ColumnLayout {
            spacing: 0
            // 标题栏（.modal-head：高 50px，padding 14px 18px + 下边框）
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                spacing: 10
                Text { text: "相机拉流设置 · RTSP"; font.bold: true; font.pixelSize: 14; color: root.themeRoot.colText }
                Item { Layout.fillWidth: true }
                // 关闭按钮（.mclose：透明无边框，20px 灰字）
                Button {
                    text: "✕"
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    background: Rectangle { color: "transparent" }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 20; anchors.centerIn: parent }
                    onClicked: camCfgDlg.close()
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine }
            // 内容区（.modal-body：padding 18px，超高时内部滚动，标题固定）
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 18
                Layout.bottomMargin: 18
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: camCfgDlg.width - 36
                    spacing: 12
                    // 相机列表（.camcfg-list）
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: root.camCfg
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 8
                                color: root.themeRoot.colCard2
                                border.color: root.themeRoot.colLine
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 6
                                    spacing: 8
                                    Rectangle {
                                        width: 7; height: 7; radius: 3.5
                                        color: modelData.enable ? root.themeRoot.colOk : root.themeRoot.colOff
                                    }
                                    Text { text: modelData.name; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                        text: modelData.ip ? root.camRtspUrlMasked(index) : "未配置地址"
                                        font.pixelSize: 11; font.family: "monospace"; color: root.themeRoot.colText2
                                    }
                                    Text {
                                        text: modelData.enable ? "已启用" : (modelData.ip ? "已停用" : "未配置")
                                        font.pixelSize: 11
                                        color: modelData.enable ? root.themeRoot.colOk : root.themeRoot.colOff
                                    }
                                    // 删除按钮（.cl-del：hover 红字红底）
                                    Button {
                                        text: "✕"
                                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                        background: Rectangle { radius: 6; color: hoverDel.hovered ? Qt.rgba(220,38,38,0.12) : "transparent" }
                                        HoverHandler { id: hoverDel; cursorShape: Qt.PointingHandCursor }
                                        contentItem: Text { text: parent.text; color: hoverDel.hovered ? root.themeRoot.colErr : root.themeRoot.colText2; anchors.centerIn: parent; font.pixelSize: 13 }
                                        onClicked: root.openDelCam(modelData.id)
                                    }
                                }
                            }
                        }
                        Text {
                            visible: root.camCfg.length === 0
                            text: "尚未配置相机，点击下方「添加相机」新建"
                            font.pixelSize: 12; color: root.themeRoot.colText2
                        }
                    }
                    // 编辑表单（.camcfg-form：flex column gap 14px）
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        // 编辑相机下拉
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "编辑相机"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFSelect {
                                id: cfgCamCombo
                                Layout.fillWidth: true
                                model: root.camCfg.map(function(c){ return c.name })
                                currentIndex: root.camIdxOf(root.camCfgSel)
                                onActivated: { root.camCfgSel = root.camCfg[currentIndex].id; root.renderCfgForm() }
                            }
                        }
                        // 相机名称
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "相机名称"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput {
                                id: cfgNameInput
                                Layout.fillWidth: true
                                placeholderText: "前视相机"
                                onTextChanged: { if (!root.cfgSyncing) root.syncUrlInput() }
                            }
                        }
                        // RTSP 完整地址（粘贴自动解析，对齐原型 label）
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "RTSP地址（粘贴RTSP完整地址，自动解析参数）"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput {
                                id: cfgUrlInput
                                Layout.fillWidth: true
                                placeholderText: "rtsp://用户名:密码@192.168.1.101:554/live/stream1"
                                onTextChanged: {
                                    var p = root.parseRtspUrl(text)
                                    if (p) {
                                        root.cfgSyncing = true
                                        cfgIpInput.text = p.ip
                                        cfgPortInput.text = "" + p.port
                                        cfgPathInput.text = p.path
                                        cfgUserInput.text = p.user
                                        cfgPassInput.text = p.pass
                                        root.cfgSyncing = false
                                    }
                                }
                            }
                        }
                        // 启用该相机（对齐原型：13px 原生方形复选框 + 12px 文字）
                        CheckBox {
                            id: cfgEnableInput
                            text: "启用该相机"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            spacing: 6
                            indicator: Rectangle {
                                implicitWidth: 13; implicitHeight: 13
                                radius: 3
                                border.color: cfgEnableInput.checked ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                border.width: 1
                                color: cfgEnableInput.checked ? root.themeRoot.colPrimary : "transparent"
                                // 白色对勾（简单近似原生 checkbox）
                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: cfgEnableInput.checked
                                    width: 7; height: 7; radius: 1.5; color: "white"
                                }
                            }
                        }
                        // IP / 端口（.cf-row 各自独立一行，对齐原型竖排）
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "IP 地址"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput { id: cfgIpInput; Layout.fillWidth: true; onTextChanged: { if (!root.cfgSyncing) root.syncUrlInput() } }
                        }
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "端口（可空，默认 554）"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput { id: cfgPortInput; Layout.fillWidth: true; onTextChanged: { if (!root.cfgSyncing) root.syncUrlInput() } }
                        }
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "RTSP 路径（可空）"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput { id: cfgPathInput; Layout.fillWidth: true; onTextChanged: { if (!root.cfgSyncing) root.syncUrlInput() } }
                        }
                        // 用户名 / 密码（各自独立一行，对齐原型竖排）
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "用户名（无认证可留空）"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput { id: cfgUserInput; Layout.fillWidth: true; onTextChanged: { if (!root.cfgSyncing) root.syncUrlInput() } }
                        }
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "密码（无认证可留空）"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            CFInput { id: cfgPassInput; Layout.fillWidth: true; echoMode: TextInput.Password; onTextChanged: { if (!root.cfgSyncing) root.syncUrlInput() } }
                        }
                        // 码流 / 传输 / 帧率（.cf-row：label + 三 select 并排 flex:1）
                        ColumnLayout { Layout.fillWidth: true; spacing: 4
                            Text { text: "码流 / 传输 / 帧率"; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                            RowLayout { Layout.fillWidth: true; spacing: 8
                                CFSelect { id: cfgStreamCombo; Layout.fillWidth: true; model: ["主码流","子码流"] }
                                CFSelect { id: cfgTransportCombo; Layout.fillWidth: true; model: ["TCP","UDP"] }
                                CFSelect { id: cfgFpsCombo; Layout.fillWidth: true; model: ["15","20","25","30"] }
                            }
                        }
                    }
                    // 底部操作（.cf-actions：margin-top:10px + 顶部虚线分隔 + padding-top:14px）
                    Column {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 4
                        spacing: 14
                        DashLine { Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            // ＋ 添加相机（.cf-btn.add：绿边框绿字，hover 绿底白字）
                            Button {
                                text: "＋ 添加相机"
                                Layout.preferredHeight: 39
                                Layout.preferredWidth: 110
                                background: Rectangle { radius: 9; color: hoverAdd.hovered ? root.themeRoot.colOk : root.themeRoot.colCard2; border.color: root.themeRoot.colOk
                                    Behavior on color { ColorAnimation { duration: 150 } } }
                                HoverHandler { id: hoverAdd; cursorShape: Qt.PointingHandCursor }
                                contentItem: Text { text: parent.text; color: hoverAdd.hovered ? "#ffffff" : root.themeRoot.colOk; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: root.addCam()
                            }
                            // 清空当前相机（.cf-btn.clear：红边框红字，hover 红底白字）
                            Button {
                                text: "清空当前相机"
                                Layout.preferredHeight: 39
                                Layout.preferredWidth: 110
                                background: Rectangle { radius: 9; color: hoverClear.hovered ? root.themeRoot.colErr : root.themeRoot.colCard2; border.color: root.themeRoot.colErr
                                    Behavior on color { ColorAnimation { duration: 150 } } }
                                HoverHandler { id: hoverClear; cursorShape: Qt.PointingHandCursor }
                                contentItem: Text { text: parent.text; color: hoverClear.hovered ? "#ffffff" : root.themeRoot.colErr; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: root.openClearCam()
                            }
                            Item { Layout.fillWidth: true }
                            // 保存设置（.cf-btn.save：蓝渐变白字，hover 上浮）
                            Button {
                                text: "保存设置"
                                Layout.preferredHeight: 39
                                Layout.preferredWidth: 110
                                scale: hoverSave.pressed ? 1.0 : 1.0
                                background: Rectangle {
                                    radius: 9
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: root.themeRoot.colPrimary }
                                        GradientStop { position: 1.0; color: root.themeRoot.dark ? "#2563eb" : "#1d4ed8" }
                                    }
                                }
                                HoverHandler { id: hoverSave; cursorShape: Qt.PointingHandCursor }
                                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                onClicked: root.saveCfgDlg()
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== 二重确认框（对齐原型 .modal-mask.confirm：width 380px，head + body，叠加在主弹窗之上）=====
    Popup {
        id: confirmDlg
        modal: true
        anchors.centerIn: parent
        width: Math.min(380, parent.width * 0.92)
        padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            radius: 14
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0,0,0,0.35)
                shadowBlur: 0.6
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 18
            }
        }
        // 第二层遮罩更深（对齐原型 rgba(15,23,42,.6)，QML 参数需除以 255）
        Overlay.modal: Component { Rectangle { color: Qt.rgba(15/255, 23/255, 42/255, 0.6) } }
        property string title: ""
        property string bodyText: ""
        property string confirmText: "确认"
        property var onOk: function() {}
        contentItem: ColumnLayout {
            spacing: 0
            // 标题栏（.modal-head：高 50px）
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Text { text: confirmDlg.title; font.bold: true; font.pixelSize: 14; color: root.themeRoot.colText }
                Item { Layout.fillWidth: true }
                Button {
                    text: "✕"
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    background: Rectangle { color: "transparent" }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 20; anchors.centerIn: parent }
                    onClicked: confirmDlg.close()
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine }
            // 主体（.modal-body：padding 18px）
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 18
                Layout.bottomMargin: 18
                spacing: 16
                // 说明文字（对齐原型：13px / line-height 1.7 / 次要提示 12px）
                Text {
                    text: confirmDlg.bodyText
                    color: root.themeRoot.colText
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    textFormat: Text.RichText
                    lineHeight: 1.7
                    lineHeightMode: Text.ProportionalHeight
                }
                // 操作行（对齐原型：padding-top:12px + 虚线分隔 + justify-end）
                Column {
                    Layout.fillWidth: true
                    spacing: 12
                    DashLine { Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: 10
                        // 取消（.cf-btn：白底 line 边框 text 文字，hover 边框/文字变 primary）
                        Button {
                            text: "取消"
                            Layout.preferredHeight: 39
                            Layout.preferredWidth: 100
                            background: Rectangle { radius: 9; color: root.themeRoot.colCard2; border.color: (hoverCancel.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } } }
                            HoverHandler { id: hoverCancel; cursorShape: Qt.PointingHandCursor }
                            contentItem: Text { text: parent.text; color: (hoverCancel.hovered ? root.themeRoot.colPrimary : root.themeRoot.colText); font.pixelSize: 13; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: confirmDlg.close()
                        }
                        // 确认/删除（.cf-btn.clear：红边框红字，hover 红底白字）
                        Button {
                            text: confirmDlg.confirmText
                            Layout.preferredHeight: 39
                            Layout.preferredWidth: 100
                            background: Rectangle { radius: 9; color: hoverOk.hovered ? root.themeRoot.colErr : root.themeRoot.colCard2; border.color: root.themeRoot.colErr
                                Behavior on color { ColorAnimation { duration: 150 } } }
                            HoverHandler { id: hoverOk; cursorShape: Qt.PointingHandCursor }
                            contentItem: Text { text: parent.text; color: hoverOk.hovered ? "#ffffff" : root.themeRoot.colErr; font.pixelSize: 13; font.weight: Font.DemiBold; anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: { var fn = confirmDlg.onOk; confirmDlg.close(); if (fn) fn() }
                        }
                    }
                }
            }
        }
    }

    // ===== 拉流设置弹窗逻辑 =====
    property bool cfgSyncing: false

    // 渲染当前编辑相机的表单
    function renderCfgForm() {
        var i = root.camIdxOf(root.camCfgSel)
        if (i < 0) return
        var c = root.camCfg[i]
        cfgNameInput.text = c.name
        cfgEnableInput.checked = c.enable
        cfgIpInput.text = c.ip
        cfgPortInput.text = "" + c.port
        cfgPathInput.text = c.path
        cfgUserInput.text = c.user
        cfgPassInput.text = c.pass
        cfgStreamCombo.currentIndex = c.stream === "子码流" ? 1 : 0
        cfgTransportCombo.currentIndex = c.transport === "UDP" ? 1 : 0
        var fi = -1
        for (var k = 0; k < cfgFpsCombo.model.length; k++)
            if ("" + cfgFpsCombo.model[k] === "" + c.fps) { fi = k; break }
        cfgFpsCombo.currentIndex = fi >= 0 ? fi : 2
        root.cfgSyncing = true
        root.syncUrlInput()
        root.cfgSyncing = false
    }
    // 同步地址输入框（手动编辑参数 → 反向同步 URL）
    function syncUrlInput() {
        var u = cfgUserInput.text, p = cfgPassInput.text
        var ip = cfgIpInput.text, po = cfgPortInput.text, pa = cfgPathInput.text
        var cred = u ? u + ":" + p + "@" : ""
        cfgUrlInput.text = "rtsp://" + cred + ip + ":" + po + pa
    }
    // 读取当前编辑相机表单
    function readCfgForm() {
        var i = root.camIdxOf(root.camCfgSel)
        if (i < 0) return
        var c = root.camCfg[i]
        c.name = cfgNameInput.text.trim() || c.name
        c.enable = cfgEnableInput.checked
        c.ip = cfgIpInput.text.trim()
        c.port = parseInt(cfgPortInput.text) || 554
        c.path = cfgPathInput.text.trim()
        c.user = cfgUserInput.text.trim()
        c.pass = cfgPassInput.text
        c.stream = cfgStreamCombo.currentText
        c.transport = cfgTransportCombo.currentText
        c.fps = parseInt(cfgFpsCombo.currentText) || 25
    }
    // 添加相机（自动命名，默认停用）
    function addCam() {
        var n = root.camCfg.length + 1
        var nc = {id: "cam_" + (root.camSeq++), name: "新相机" + n, enable: false, ip: "", port: 554,
                  path: "", user: "", pass: "", stream: "主码流", transport: "TCP", fps: 25}
        root.camCfg = root.camCfg.concat([nc])
        root.camCfgSel = nc.id
        root.saveAll()
        root.renderCfgForm()
        root.toast("已添加相机：新相机" + n)
    }
    // 删除相机（确认框）
    function openDelCam(id) {
        var i = root.camIdxOf(id)
        if (i < 0) return
        var nm = root.camCfg[i].name
        confirmDlg.title = "删除相机"
        confirmDlg.bodyText = "确定要删除 <b style=\"color:#dc2626\">" + nm + "</b> 吗？<br><span style=\"color:#94a3b8;font-size:12px\">删除后该相机的拉流配置将被移除，且此操作不可撤销。</span>"
        confirmDlg.confirmText = "删除"
        confirmDlg.onOk = function() { root.removeCam(id) }
        confirmDlg.open()
    }
    function removeCam(id) {
        var i = root.camIdxOf(id)
        if (i < 0) return
        var rm = root.camCfg[i]
        // 修正选中集索引（删除项之后前移）
        var ns = []
        for (var k = 0; k < root.selected.length; k++) {
            var idx = root.selected[k]
            if (idx < i) ns.push(idx)
            else if (idx > i) ns.push(idx - 1)
        }
        root.selected = ns
        root.camCfg = root.camCfg.filter(function(c){ return c.id !== id })
        if (root.camCfgSel === id) {
            var j = i
            if (j >= root.camCfg.length) j = root.camCfg.length - 1
            root.camCfgSel = j >= 0 ? root.camCfg[j].id : ""
        }
        root.saveAll()
        root.renderCfgForm()
        root.toast("已删除" + rm.name)
    }
    // 清空当前相机配置（保留 id/name，确认框）
    function openClearCam() {
        var i = root.camIdxOf(root.camCfgSel)
        if (i < 0) return
        var c = root.camCfg[i]
        confirmDlg.title = "清空相机配置"
        confirmDlg.bodyText = "确定要清空 <b style=\"color:#dc2626\">" + c.name + "</b> 的拉流配置吗？<br><span style=\"color:#94a3b8;font-size:12px\">清空后该相机将停用，地址参数为空，且此操作不可撤销。</span>"
        confirmDlg.confirmText = "清空配置"
        confirmDlg.onOk = function() {
            var c2 = root.camCfg[root.camIdxOf(root.camCfgSel)]
            if (!c2) return
            c2.enable = false; c2.ip = ""; c2.port = 554; c2.path = ""; c2.user = ""; c2.pass = ""
            c2.stream = "主码流"; c2.transport = "TCP"; c2.fps = 25
            root.saveAll()
            root.renderCfgForm()
            root.toast("已清空" + c2.name + "的配置")
        }
        confirmDlg.open()
    }
    // 保存设置
    function saveCfgDlg() {
        root.readCfgForm()
        root.saveAll()
        camCfgDlg.close()
        root.toast("拉流设置已保存")
    }
}

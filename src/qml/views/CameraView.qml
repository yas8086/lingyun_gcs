import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import LingYun.Video 1.0

// 摄像头监控（1:1 复刻原型 #view-camera + 设计文档《摄像头页面落地设计》）：
// 动态相机配置（RTSP 拉流设置，JSON 持久化）· tab 多选（FIFO 顶掉）· 四档布局（1/2/4/全）·
// 画面比例 16:9/4:3/1:1/填充 · OSD 叠加 · 悬浮控制 · 截图/录像/重连。视频区域为深色渐变占位。
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg, string type)

    // ===== 相机配置（对齐原型 CamConfig，id 主键稳定）=====
    property var camCfg: []          // [{id,name,enable,ip,port,path,user,pass,stream,transport,fps}]
    property var selected: []        // 当前选中（显示）的相机索引集合（多选）
    property string layMode: "1"     // 布局档位：1/2/4/a（全部）
    property string camCfgSel: ""    // 拉流设置当前编辑相机 id
    property int camSeq: 0           // 相机 id 自增序号（删除后不复用）
    property bool osdOn: true        // OSD 叠加开关
    property bool recOn: false       // 录像状态
    property real recStart: 0        // 录像开始时间戳（ms；须用 real，int 是 32 位会溢出 Date.now()）
    property int recElapsed: 0       // 已录制秒数（streamWatch 每秒刷新，供 REC 计时显示）
    property var recCamIds: []       // 实际在录的相机 id 集（仅选中且在线出帧的相机）
    property bool connBusy: false    // 重连中
    // 拉流设置草稿：弹窗内一切修改只改草稿，点「保存设置」才写回生效，点 ✕ 关闭即丢弃
    property var cfgDraft: []
    property string cfgDraftSel: ""  // 草稿当前编辑相机 id
    property var cfgSelIds: []       // 打开弹窗时记选中相机 id（保存后按 id 重建 selected）
    // 云台控制焦点相机索引（对齐原型 focusIdx：点击画面格/tab 切换，控制盘跟随）
    property int focusIdx: 0
    property bool ptzFolded: false   // 云台控制盘折叠状态
    // 思翼云台（A2 mini）：持有其相机 id，SDK 会话随页面启动（特征：RTSP 端口 8554）
    property string gimbalCamId: ""
    // 画面比例（对齐原型 camRatio）：16:9 / 4:3 / 1:1 / 填充，点击循环切换
    property var ratios: [["16:9","16:9"],["4:3","4:3"],["1:1","1:1"],["auto","填充"]]
    property int ratioIdx: 0

    // ===== 默认相机配置（对齐原型 CAM_CFG_DEFAULT，ptz=云台相机标记）=====
    // 前视相机 cam_0 为当前真实接入摄像头：rtsp://192.168.144.25:8554/main.264（无认证）
    property var camDefault: [
        {id:"cam_0", name:"前视相机", enable:true,  ptz:true,  ip:"192.168.144.25", port:8554, path:"/main.264", user:"", pass:"", stream:"主码流", transport:"TCP", fps:25},
        {id:"cam_1", name:"后视相机", enable:true,  ptz:false, ip:"192.168.1.102", port:554, path:"/live/stream1", user:"admin", pass:"12345", stream:"主码流", transport:"TCP", fps:25},
        {id:"cam_2", name:"吊舱相机", enable:false, ptz:true,  ip:"192.168.1.103", port:554, path:"/live/stream2", user:"admin", pass:"12345", stream:"主码流", transport:"UDP", fps:25},
        {id:"cam_3", name:"地面相机", enable:true,  ptz:false, ip:"192.168.1.104", port:554, path:"/live/stream1", user:"admin", pass:"12345", stream:"主码流", transport:"TCP", fps:25}
    ]

    function toast(msg, type) { root.showNote(msg, type || "ok") }

    function fmtTs(ts) {
        var d = new Date(ts)
        function p(n) { return n < 10 ? "0" + n : "" + n }
        return d.getFullYear() + "-" + p(d.getMonth()+1) + "-" + p(d.getDate())
             + " " + p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
    }
    // 数值格式化（OSD 叠加用）
    function fmt2(v) { return isNaN(v) ? "--" : Number(v).toFixed(2) }
    function fmt1(v) { return isNaN(v) ? "--" : Number(v).toFixed(1) }
    function fmt0(v) { return isNaN(v) ? "--" : Math.round(v) }
    function fmtDur(s) { // 秒 → mm:ss（超过1小时 → h:mm:ss）
        var t = Math.max(0, Math.floor(s))
        var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60
        function p(n) { return n < 10 ? "0" + n : "" + n }
        return (h > 0 ? h + ":" : "") + p(m) + ":" + p(sec)
    }
    // OSD 本地时钟（由定时器每秒刷新）
    property string osdClock: root.fmtTs(Date.now())
    // 网口连接状态：有线网口物理链路（网线是否插入）决定"网口已连接/未连接"
    property bool netOk: false
    // 任一有线网口（非回环/无线/虚拟网桥）carrier=1 即视为网口已连接
    function netLinkUp() {
        var ifaces = bridge.netInterfaces()
        for (var i = 0; i < ifaces.length; i++) {
            var n = String(ifaces[i].name || "")
            if (n === "lo" || n.indexOf("wl") === 0) continue        // 回环 / 无线网卡
            if (n.indexOf("docker") === 0 || n.indexOf("veth") === 0) continue
            if (n.indexOf("br-") === 0 || n.indexOf("virbr") === 0) continue
            if (ifaces[i].linkUp === true) return true              // 有线网口已插网线
        }
        return false
    }
    // RTSP 流启停管理：仅对"启用且被选中"的相机拉流，未选中/停用即停止（省资源）
    // 注意：用 started 而非 online 判断是否已发起拉流，避免首帧延迟期间每秒重复 teardown 重建
    function manageStreams() {
        if (!root.camCfg || !root.camCfg.length) return
        for (var i = 0; i < root.camCfg.length; i++) {
            var c = root.camCfg[i]
            if (!c) continue
            var s = bridge.videoStream(c.id)
            var active = c.enable && root.selected.indexOf(i) >= 0 && c.ip
            if (active && !s.started && !s.busy) s.start()
            else if (!active && s.started) s.stop()
        }
        root.netOk = root.netLinkUp()
    }
    // 相机数据变更后：同步流 URL（增删改配置后拉流目标可能变化）并刷新启停
    function syncStreams() {
        for (var i = 0; i < root.camCfg.length; i++) {
            var c = root.camCfg[i]
            if (!c) continue
            var s = bridge.videoStream(c.id)
            s.url = c.ip ? root.camRtspUrl(i) : ""
            if (!c.ip) s.stop()
        }
        // 思翼云台 IP 变更时重启 SDK 会话
        var gb = ""
        for (var j = 0; j < root.camCfg.length; j++) {
            var gj = root.camCfg[j]
            if (gj && gj.ip && gj.port === 8554) { gb = gj.id; break }
        }
        if (gb !== root.gimbalCamId) {
            root.gimbalCamId = gb
            if (gb) bridge.startGimbal(root.camCfg[j].ip)
            else bridge.stopGimbal()
        }
        root.manageStreams()
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
    function rtspUrlMaskedIn(arr, i) {   // 草稿版（拉流设置弹窗列表用）
        var c = arr ? arr[i] : null
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
        return root.camIdxIn(root.camCfg, id)
    }
    function camIdxIn(arr, id) {   // 通用：在指定数组中找相机 id 索引
        for (var i = 0; i < (arr ? arr.length : 0); i++)
            if (arr[i].id === id) return i
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
        root.syncStreams()   // 配置变更后同步拉流目标
    }

    // ===== 初始化：加载配置 / 布局档位，填充默认选中 =====
    Component.onCompleted: {
        var cfg = bridge.cameraConfigs()
        if (!cfg || cfg.length === 0) {
            root.camCfg = root.camDefault.map(function(c){ return Object.assign({}, c) })
            bridge.saveCameraConfigs(root.camCfg)
        } else {
            // 旧配置迁移：无 ptz 字段的项按默认配置对应索引补齐（对齐原型迁移逻辑）
            root.camCfg = cfg.map(function(c, i) {
                var o = Object.assign({}, c)
                if (o.ptz === undefined)
                    o.ptz = (root.camDefault[i] && i < root.camDefault.length) ? !!root.camDefault[i].ptz : false
                return o
            })
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
        root.syncStreams()   // 首次拉流（仅选中启用的相机）
        // 识别思翼云台相机（A2 mini，RTSP 端口 8554）并启动 UDP SDK 会话（姿态轮询）
        for (var g = 0; g < root.camCfg.length; g++) {
            var gc = root.camCfg[g]
            if (gc && gc.ip && gc.port === 8554) {
                root.gimbalCamId = gc.id
                bridge.startGimbal(gc.ip)
                break
            }
        }
        // 周期刷新：OSD 时钟 / 网口状态 / 断流后按需补拉
        streamWatch.start()
    }

    Timer {
        id: streamWatch
        interval: 1000
        repeat: true
        onTriggered: {
            root.osdClock = root.fmtTs(Date.now())
            root.netOk = root.netLinkUp()
            root.recElapsed = root.recOn ? Math.floor((Date.now() - root.recStart) / 1000) : 0
            root.manageStreams()   // 断流后重连尝试由 RtspStream 自身退避处理，这里保持启停正确
        }
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
                // 网口状态胶囊（.cam-stat，绑定真实流连接状态）
                Rectangle {
                    Layout.preferredHeight: 24
                    implicitWidth: statLbl.implicitWidth + 26
                    radius: 999
                    color: root.netOk ? root.themeRoot.colOkSoft : root.themeRoot.colErrSoft
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle { width: 7; height: 7; radius: 3.5; color: root.netOk ? root.themeRoot.colOk : root.themeRoot.colErr; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            id: statLbl
                            text: root.netOk ? "网口已连接" : "网口未连接"
                            font.pixelSize: 12; font.weight: Font.DemiBold
                            color: root.netOk ? root.themeRoot.colOk : root.themeRoot.colErr
                        }
                    }
                }
                // 链路说明（原 camMeta 位置，紧邻网口状态：数传网口直连）
                Text {
                    text: "数传网口直连 · 与串口遥测独立并行"
                    font.pixelSize: 11; color: root.themeRoot.colText2
                }
                Item { Layout.fillWidth: true }
                // 配置提醒（RTSP 拉流前提：地面站网口与摄像头同子网 + 静态 IP），置于拉流设置左侧
                Text {
                    text: "⚠ 需为地面站网口增加配置与摄像头同网段的静态 IP"
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
                    onClicked: {
                        // 生成编辑草稿（深拷贝）：弹窗内所有修改只落在草稿上
                        root.cfgDraft = root.camCfg.map(function(c){ return Object.assign({}, c) })
                        root.cfgDraftSel = root.camCfgSel || (root.camCfg.length ? root.camCfg[0].id : "")
                        root.cfgSelIds = root.selected.filter(function(i){ return root.camCfg[i] })
                                                  .map(function(i){ return root.camCfg[i].id })
                        root.renderCfgForm()
                        camCfgDlg.open()
                    }
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
                            // 点击 tab 同时设为云台控制焦点（对齐原型 focusIdx）
                            root.focusIdx = index
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
                            root.manageStreams()   // 选中集变化 → 拉流启停同步
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
                        // 云台焦点格（对齐原型 .cam-view.focus）：选中+启用+云台相机+当前焦点
                        property bool ptzFocus: viewOn && live && modelData.ptz && root.focusIdx === index
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
                            border.width: viewItem.ptzFocus ? 2 : (viewOn && root.selected.length === 1 ? 2 : 1)
                            border.color: viewItem.ptzFocus ? "#ffffff"
                                        : (viewOn && root.selected.length === 1 ? root.themeRoot.colPrimary : root.themeRoot.colLine)

                            // 点击画面格设为云台控制焦点（z 低，不拦截悬浮控制/控制盘点击）
                            MouseArea {
                                anchors.fill: parent
                                z: 0
                                onClicked: if (root.focusIdx !== index) root.focusIdx = index
                            }

                            // 全画面 hover 检测（.cam-view:hover 显示 cam-ov），z 低于焦点点击层，仅探测 hover
                            MouseArea {
                                id: viewHover
                                anchors.fill: parent
                                hoverEnabled: true
                                z: -1
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
                            // RTSP 实时视频（B 方案：GStreamer + QSG 纹理 GPU 上屏）。
                            // 流由 bridge.videoStream(camId) 懒创建，启用的相机按选中状态自动拉流；
                            // 无帧/离线时保持底层渐变占位可见。
                            // 外层 vidClip 启用 layer + 圆角 mask：Rectangle 的 clip 仅按外框矩形
                            // 裁剪、不裁圆角，视频帧直角会在圆角处出界，经 mask 按格子圆角裁剪。
                            Item {
                                id: vidClip
                                anchors.fill: parent
                                visible: viewItem.live && vidSurf.stream && vidSurf.stream.online
                                // 流在线才开 layer（离屏纹理 + mask 采样），离线时零开销
                                layer.enabled: visible
                                layer.effect: MultiEffect {
                                    autoPaddingEnabled: false
                                    maskEnabled: true
                                    maskSource: vidMask
                                }
                                VideoSurface {
                                    id: vidSurf
                                    anchors.fill: parent
                                    stream: viewItem.live ? bridge.videoStream(modelData.id) : null
                                }
                                // 圆角遮罩源：maskSource 必须是 layer.enabled 的纹理源，
                                // visible:false 不参与场景渲染（Qt 官方 MultiEffect 掩码结构）
                                Item {
                                    id: vidMask
                                    width: vidClip.width; height: vidClip.height
                                    layer.enabled: true
                                    visible: false
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 12   // 与画面格外框 radius 一致
                                        color: "white"
                                    }
                                }
                            }
                            // 相机轮廓 SVG（.cam-pic，白色描边 120px opacity .12；流在线时隐藏避免叠在视频上）
                            Rectangle {
                                anchors.centerIn: parent
                                width: 120; height: 120
                                color: "transparent"
                                visible: !(vidSurf.stream && vidSurf.stream.online)
                                Image {
                                    anchors.fill: parent
                                    source: "qrc:/qml/img/camera.svg"
                                    fillMode: Image.PreserveAspectFit
                                    opacity: 0.14
                                }
                            }
                            // 占位文字（.cam-no）：启用=正在接入，停用=未启用（流在线出帧后被视频覆盖，隐藏之）
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: !(vidSurf.stream && vidSurf.stream.online)
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name + " · " + (viewItem.live ? "连接中" : "未启用")
                                    font.pixelSize: 13; font.weight: Font.DemiBold; color: "#8ba3c2"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: viewItem.live ? "正在接入网口视频流…" : "等待拉流设置"
                                    font.pixelSize: 11; color: "#5f718d"
                                }
                            }

                            // 单路标签（.cam-tag 左上角，黑45%底 + 模糊 + 呼吸状态点，绑定真实流状态）
                            Rectangle {
                                id: camTag
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
                                        dotColor: (viewItem.live && vidSurf.stream && vidSurf.stream.online) ? "#16a34a" : "#dc2626"
                                    }
                                    Text {
                                        text: modelData.name + " · " + ((viewItem.live && vidSurf.stream && vidSurf.stream.online) ? "LIVE" : "OFFLINE")
                                        font.pixelSize: 11; font.weight: Font.Bold; color: "#ffffff"
                                    }
                                }
                            }
                            // REC 录制标记（录制中：红点闪烁 + mm:ss 计时，cam-tag 正下方；仅实际在录的相机显示）
                            Rectangle {
                                visible: root.recOn && viewItem.viewOn && root.recCamIds.indexOf(modelData.id) >= 0
                                anchors.top: camTag.bottom
                                anchors.left: camTag.left
                                anchors.topMargin: 6
                                height: 22
                                implicitWidth: recRow2.implicitWidth + 16
                                radius: 6
                                color: Qt.rgba(0,0,0,0.55)
                                Row {
                                    id: recRow2
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 8; height: 8; radius: 4
                                        color: "#ef4444"
                                        // 红点 1s 循环闪烁（录制指示惯例）
                                        SequentialAnimation on opacity {
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 1; to: 0.15; duration: 500 }
                                            NumberAnimation { from: 0.15; to: 1; duration: 500 }
                                        }
                                    }
                                    Text {
                                        text: "REC " + root.fmtDur(root.recElapsed)
                                        font.pixelSize: 11; font.weight: Font.Bold; font.family: "monospace"; color: "#ffffff"
                                    }
                                }
                            }

                            // ===== 云台控制盘（.ptz-panel：焦点格左下角悬浮，可折叠）=====
                            // 对齐原型：头部"云台 · 相机名"+折叠钮；3×3 方向键（8向+红色停止）+ 变倍列；
                            // 按住连续控制（260ms 重复）；真实指令走思翼 SDK（A2 mini 仅俯仰轴生效）
                            Rectangle {
                                id: ptzPanel
                                visible: viewItem.ptzFocus
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                radius: 10
                                color: Qt.rgba(8/255, 14/255, 26/255, 0.74)
                                border.color: Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1
                                implicitWidth: 172
                                implicitHeight: root.ptzFolded ? 26 : ptzBodyCol.implicitHeight + 26
                                // 方向按钮发出指令（yaw,pitch）：A2 mini 仅 pitch 生效；速度 40 中速
                                function move(yaw, pitch) {
                                    if (root.gimbalCamId === modelData.id && bridge.gimbalConnected)
                                        bridge.gimbalCtrlMove(yaw, pitch)
                                }
                                Column {
                                    id: ptzBodyCol
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    spacing: 0

                                    // 头部（.ptz-head）：标题 + 折叠按钮
                                    Item {
                                        width: parent.width
                                        height: 26
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 36
                                            text: "云台 · " + modelData.name
                                            font.pixelSize: 11; font.weight: Font.Bold; color: "#cfe0ff"
                                            elide: Text.ElideRight
                                        }
                                        // 折叠按钮（— / ＋）
                                        Rectangle {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 20; height: 20; radius: 4
                                            color: foldMa.pressed ? Qt.rgba(255,255,255,0.15) : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.ptzFolded ? "＋" : "—"
                                                color: "#8aa0bf"; font.pixelSize: 12
                                            }
                                            MouseArea {
                                                id: foldMa
                                                anchors.fill: parent
                                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.ptzFolded = !root.ptzFolded
                                            }
                                        }
                                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }
                                    }

                                    // 主体（.ptz-body）：方向九宫格 + 变倍列
                                    Row {
                                        visible: !root.ptzFolded
                                        leftPadding: 8; rightPadding: 8
                                        topPadding: 8; bottomPadding: 8
                                        spacing: 8

                                        // 3×3 方向键（.ptz-dir：28×28 格，gap 3）
                                        Grid {
                                            columns: 3
                                            spacing: 3
                                            // 按钮组件：按住连续触发（260ms），松手停止
                                            component PtzBtn: Rectangle {
                                                id: pb
                                                property string glyph: ""
                                                property bool isStop: false
                                                property int mvYaw: 0
                                                property int mvPitch: 0
                                                property bool isMove: true     // false=停止按钮（发 0,0）
                                                width: 28; height: 28; radius: 6
                                                color: ma.pressed
                                                       ? (isStop ? "#dc2626" : root.themeRoot.colPrimary)
                                                       : (isStop ? Qt.rgba(220/255,38/255,38/255,0.25) : Qt.rgba(1,1,1,0.07))
                                                border.width: 1
                                                border.color: ma.pressed
                                                       ? (isStop ? "#dc2626" : root.themeRoot.colPrimary)
                                                       : (isStop ? Qt.rgba(220/255,38/255,38/255,0.5) : Qt.rgba(1,1,1,0.16))
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text { anchors.centerIn: parent; text: pb.glyph; color: "#dbe6ff"; font.pixelSize: isStop ? 10 : 12 }
                                                MouseArea {
                                                    id: ma
                                                    anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onPressed: {
                                                        ptzPanel.move(pb.mvYaw, pb.mvPitch)
                                                        repeatT.restart()
                                                    }
                                                    onReleased: { repeatT.stop(); ptzPanel.move(0, 0) }
                                                    onCanceled: { repeatT.stop(); ptzPanel.move(0, 0) }
                                                    // 按住连续（对齐原型 260ms 间隔）
                                                    Timer {
                                                        id: repeatT
                                                        interval: 260; repeat: true
                                                        onTriggered: ptzPanel.move(pb.mvYaw, pb.mvPitch)
                                                    }
                                                }
                                            }
                                            PtzBtn { glyph: "◤"; mvYaw: -40; mvPitch: 40 }    // 左上
                                            PtzBtn { glyph: "▲"; mvYaw: 0;   mvPitch: 40 }    // 上（俯仰+）
                                            PtzBtn { glyph: "◥"; mvYaw: 40;  mvPitch: 40 }    // 右上
                                            PtzBtn { glyph: "◀"; mvYaw: -40; mvPitch: 0 }     // 左
                                            PtzBtn { glyph: "●"; isStop: true; mvYaw: 0; mvPitch: 0 }  // 停止
                                            PtzBtn { glyph: "▶"; mvYaw: 40;  mvPitch: 0 }     // 右
                                            PtzBtn { glyph: "◣"; mvYaw: -40; mvPitch: -40 }   // 左下
                                            PtzBtn { glyph: "▼"; mvYaw: 0;   mvPitch: -40 }   // 下（俯仰-）
                                            PtzBtn { glyph: "◢"; mvYaw: 40;  mvPitch: -40 }   // 右下
                                        }

                                        // 变倍列（.ptz-zoom）：A2 mini 不支持变倍，点击提示
                                        Column {
                                            spacing: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                width: 28; height: 28; radius: 6
                                                color: zinMa.pressed ? root.themeRoot.colPrimary : Qt.rgba(1,1,1,0.07)
                                                border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                                                Text { anchors.centerIn: parent; text: "＋"; color: "#dbe6ff"; font.pixelSize: 14; font.weight: Font.Bold }
                                                MouseArea {
                                                    id: zinMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toast(modelData.name + " 不支持变倍控制", "err")
                                                }
                                            }
                                            Rectangle {
                                                width: 28; height: 28; radius: 6
                                                color: zoutMa.pressed ? root.themeRoot.colPrimary : Qt.rgba(1,1,1,0.07)
                                                border.width: 1; border.color: Qt.rgba(1,1,1,0.16)
                                                Text { anchors.centerIn: parent; text: "－"; color: "#dbe6ff"; font.pixelSize: 14; font.weight: Font.Bold }
                                                MouseArea {
                                                    id: zoutMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toast(modelData.name + " 不支持变倍控制", "err")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // OSD 参数叠加（.cam-osd 右下角，绑定实时遥测与本地时钟）
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
                                    Text { text: root.osdClock; font.pixelSize: 11; font.family: "monospace"; color: "#ffffff"; font.weight: Font.Bold }
                                    Text { text: root.fmt2(bridge.value("fc","lat")) + "°N    " + root.fmt2(bridge.value("fc","lon")) + "°E"; font.pixelSize: 11; font.family: "monospace"; color: "#cfe0ff" }
                                    Text { text: "ALT " + root.fmt0(bridge.value("fc","alt")) + "m    SPD " + root.fmt1(bridge.value("fc","vx")) + "m/s    HDG " + root.fmt0(bridge.value("fc","yaw")) + "°"; font.pixelSize: 11; font.family: "monospace"; color: "#cfe0ff" }
                                    // 云台俯仰（思翼 SDK 实时回读，A2 mini 仅俯仰轴有效）
                                    Text {
                                        visible: root.gimbalCamId === modelData.id && bridge.gimbalConnected
                                        text: "GIMBAL " + root.fmt1(bridge.gimbalPitch) + "°"
                                        font.pixelSize: 11; font.family: "monospace"; color: "#ffd166"
                                    }
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
                                            if (!(vidSurf.stream && vidSurf.stream.online)) { root.toast("该相机无画面，截图失败", "err"); return }
                                            var dir = bridge.cameraDir()
                                            var name = "snapshot_" + modelData.name + "_" + Date.now() + ".png"
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
                        if (!root.selected.length) { root.toast("请先选择相机", "err"); return }
                        // 仅对"选中且在线出帧"的相机逐路截图（文件名带相机名防覆盖；IIFE 捕获每轮变量防闭包共享）
                        var dir = bridge.cameraDir()
                        var ts = Date.now()
                        var total = 0
                        for (var k = 0; k < root.selected.length; k++) {
                            (function(idx) {
                                var st = bridge.videoStream(root.camCfg[idx].id)
                                if (!st.online) return   // 无画面不截
                                var it = camRep.itemAt(idx)
                                if (!it) return
                                total++
                                var camNm = (root.camCfg[idx] && root.camCfg[idx].name) ? root.camCfg[idx].name : ("cam" + idx)
                                var name = "snapshot_" + camNm + "_" + ts + ".png"
                                it.grabToImage(function(result) {
                                    result.saveToFile("file://" + dir + "/" + name)
                                })
                            })(root.selected[k])
                        }
                        if (!total) { root.toast("选中相机均无画面，无法截图", "err"); return }
                        root.toast("已保存截图（" + total + " 张，见 data/摄像头 目录）")
                    }
                }
                // 录像（.cam-btn rec，红色脉冲；图标：未录=圆圈+中心点，录制中=白色方块）
                // 仅对选中且在线出帧的相机录制；录制中按钮显示实时计时
                Button {
                    id: recBtn
                    text: root.recOn ? ("停止 " + root.fmtDur(root.recElapsed)) : "录像"
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
                            if (!root.selected.length) { root.toast("请先选择相机", "err"); return }
                            // 仅对"选中且在线出帧"的相机并行开录（离线/未出帧的跳过）
                            var okCnt = 0
                            var ids = []
                            for (var k = 0; k < root.selected.length; k++) {
                                var ci = root.camCfg[root.selected[k]]
                                if (!ci || !ci.ip) continue
                                var st = bridge.videoStream(ci.id)
                                if (!st.online) continue   // 无画面不录
                                if (bridge.startCameraRecord(ci.id)) { okCnt++; ids.push(ci.id) }
                            }
                            if (!okCnt) { root.toast("选中相机均无画面，无法录像", "err"); return }
                            root.recCamIds = ids
                            root.recOn = true
                            root.recStart = Date.now()
                            root.recElapsed = 0
                            root.toast("开始录像（" + okCnt + " 路）")
                        } else {
                            root.recOn = false
                            root.recCamIds = []
                            var dur = Math.max(1, Math.round((Date.now() - root.recStart) / 1000))
                            var ok = bridge.stopCameraRecord()
                            root.toast(ok ? ("录像已保存（时长 " + dur + " 秒）") : "录像保存失败", ok ? "ok" : "err")
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
                // 云台控制已迁移为悬浮控制盘（对齐原型 .ptz-panel，跟随焦点相机显示在画面格左下角）
                // 分隔线
                Rectangle { width: 1; height: 20; color: root.themeRoot.colLine }
                // 重连（.cam-btn #camConn：对所有启用且选中的流执行真实 reconnect）
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
                        // 对选中且启用的流逐一真实重连
                        for (var i = 0; i < root.camCfg.length; i++) {
                            var c = root.camCfg[i]
                            if (c.enable && c.ip && root.selected.indexOf(i) >= 0)
                                bridge.videoStream(c.id).reconnect()
                        }
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
        root.manageStreams()   // 选中集变化 → 拉流启停同步
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
                            model: root.cfgDraft
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
                                    // 云台徽章（.cl-ptz：10px 绿边绿字圆角4）
                                    Rectangle {
                                        visible: modelData.ptz === true
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: ptzBadgeText.implicitWidth + 8; height: 16
                                        radius: 4
                                        border.width: 1
                                        border.color: root.themeRoot.colOk
                                        color: "transparent"
                                        Text {
                                            id: ptzBadgeText
                                            anchors.centerIn: parent
                                            text: "云台"
                                            font.pixelSize: 10; font.weight: Font.Bold
                                            color: root.themeRoot.colOk
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                        text: modelData.ip ? root.rtspUrlMaskedIn(root.cfgDraft, index) : "未配置地址"
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
                            visible: root.cfgDraft.length === 0
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
                                Layout.preferredHeight: 35   // 防止被 ColumnLayout 压扁（fillWidth 时 implicitHeight 不生效）
                                model: root.cfgDraft.map(function(c){ return c.name })
                                // 切换编辑对象：先回写前一相机表单（防编辑丢失），再渲染新对象
                                onActivated: {
                                    var prevSel = root.cfgDraftSel
                                    var prevValid = root.camIdxIn(root.cfgDraft, prevSel) >= 0 && root.cfgDraft[currentIndex].id !== prevSel
                                    if (prevValid) root.readCfgForm()
                                    root.cfgDraftSel = root.cfgDraft[currentIndex].id
                                    root.renderCfgForm()
                                }
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
                        // 启用该相机（对齐原型：13px 方形复选框 + 白色对勾 + 12px 文字，完全自绘保证水平对齐）
                        Item {
                            id: cfgEnableBox
                            property bool checked: false
                            implicitHeight: 20
                            implicitWidth: enableRow.implicitWidth
                            Row {
                                id: enableRow
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: 0
                                spacing: 6
                                // 复选框（13px，圆角3，选中蓝底白勾）
                                Rectangle {
                                    id: enableBoxRect
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 13; height: 13; radius: 3
                                    border.width: 1
                                    border.color: cfgEnableBox.checked ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                    color: cfgEnableBox.checked ? root.themeRoot.colPrimary : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    // 白色对勾（Canvas 绘制真实 ✓ 形状）
                                    Canvas {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: cfgEnableBox.checked
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.strokeStyle = "white"
                                            ctx.lineWidth = 1.6
                                            ctx.lineCap = "round"
                                            ctx.lineJoin = "round"
                                            ctx.beginPath()
                                            ctx.moveTo(width * 0.12, height * 0.55)
                                            ctx.lineTo(width * 0.38, height * 0.82)
                                            ctx.lineTo(width * 0.88, height * 0.18)
                                            ctx.stroke()
                                        }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "启用该相机"
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: root.themeRoot.colText
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cfgEnableBox.checked = !cfgEnableBox.checked
                            }
                        }
                        // 云台控制（对齐原型 cfgPtz：该相机支持 PTZ 转动/变倍）
                        Item {
                            id: cfgPtzBox
                            property bool checked: false
                            implicitHeight: 20
                            implicitWidth: ptzEnableRow.implicitWidth
                            Row {
                                id: ptzEnableRow
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 13; height: 13; radius: 3
                                    border.width: 1
                                    border.color: cfgPtzBox.checked ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                    color: cfgPtzBox.checked ? root.themeRoot.colPrimary : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Canvas {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        visible: cfgPtzBox.checked
                                        onVisibleChanged: if (visible) requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.strokeStyle = "white"
                                            ctx.lineWidth = 1.6
                                            ctx.lineCap = "round"
                                            ctx.lineJoin = "round"
                                            ctx.beginPath()
                                            ctx.moveTo(width * 0.12, height * 0.55)
                                            ctx.lineTo(width * 0.38, height * 0.82)
                                            ctx.lineTo(width * 0.88, height * 0.18)
                                            ctx.stroke()
                                        }
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "云台控制（该相机支持 PTZ 转动 / 变倍）"
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: root.themeRoot.colText
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cfgPtzBox.checked = !cfgPtzBox.checked
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
                                CFSelect { id: cfgStreamCombo; Layout.fillWidth: true; Layout.preferredHeight: 35; model: ["主码流","子码流"] }
                                CFSelect { id: cfgTransportCombo; Layout.fillWidth: true; Layout.preferredHeight: 35; model: ["TCP","UDP"] }
                                CFSelect { id: cfgFpsCombo; Layout.fillWidth: true; Layout.preferredHeight: 35; model: ["15","20","25","30"] }
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

    // 渲染当前编辑相机的表单（操作草稿 cfgDraft/cfgDraftSel）
    function renderCfgForm() {
        var i = root.camIdxIn(root.cfgDraft, root.cfgDraftSel)
        if (i < 0) return
        var c = root.cfgDraft[i]
        // 显式同步编辑下拉选中项（绑定在手选后可能失效，命令式保证一致）
        cfgCamCombo.currentIndex = i
        cfgNameInput.text = c.name
        cfgEnableBox.checked = c.enable
        cfgPtzBox.checked = c.ptz === true
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
    // 读取当前编辑相机表单（表单 → 草稿）
    function readCfgForm() {
        var i = root.camIdxIn(root.cfgDraft, root.cfgDraftSel)
        if (i < 0) return
        var c = root.cfgDraft[i]
        c.name = cfgNameInput.text.trim() || c.name
        c.enable = cfgEnableBox.checked
        c.ptz = cfgPtzBox.checked
        c.ip = cfgIpInput.text.trim()
        c.port = parseInt(cfgPortInput.text) || 554
        c.path = cfgPathInput.text.trim()
        c.user = cfgUserInput.text.trim()
        c.pass = cfgPassInput.text
        c.stream = cfgStreamCombo.currentText
        c.transport = cfgTransportCombo.currentText
        c.fps = parseInt(cfgFpsCombo.currentText) || 25
    }
    // 添加相机（操作草稿：自动命名，默认停用；保存设置后才真正生效）
    function addCam() {
        var n = root.cfgDraft.length + 1
        var nc = {id: "cam_" + (root.camSeq++), name: "新相机" + n, enable: false, ptz: false, ip: "", port: 554,
                  path: "", user: "", pass: "", stream: "主码流", transport: "TCP", fps: 25}
        root.cfgDraft = root.cfgDraft.concat([nc])
        root.cfgDraftSel = nc.id
        root.renderCfgForm()
        root.toast("已添加新相机" + n + "（保存设置后生效）", "info")
    }
    // 删除相机（确认框；操作草稿）
    function openDelCam(id) {
        var i = root.camIdxIn(root.cfgDraft, id)
        if (i < 0) return
        var nm = root.cfgDraft[i].name
        confirmDlg.title = "删除相机"
        confirmDlg.bodyText = "确定要删除 <b style=\"color:#dc2626\">" + nm + "</b> 吗？<br><span style=\"color:#94a3b8;font-size:12px\">删除后该相机的拉流配置将被移除，且此操作不可撤销。</span>"
        confirmDlg.confirmText = "删除"
        confirmDlg.onOk = function() { root.removeCam(id) }
        confirmDlg.open()
    }
    function removeCam(id) {
        var i = root.camIdxIn(root.cfgDraft, id)
        if (i < 0) return
        var rm = root.cfgDraft[i]
        // 从选中 id 集合移除（保存后该相机自动退出选中）
        root.cfgSelIds = root.cfgSelIds.filter(function(x){ return x !== id })
        root.cfgDraft = root.cfgDraft.filter(function(c){ return c.id !== id })
        if (root.cfgDraftSel === id) {
            var j = i
            if (j >= root.cfgDraft.length) j = root.cfgDraft.length - 1
            root.cfgDraftSel = j >= 0 ? root.cfgDraft[j].id : ""
        }
        root.renderCfgForm()
        root.toast("已删除" + rm.name + "（保存设置后生效）", "info")
    }
    // 清空当前相机配置（保留 id/name，确认框；操作草稿）
    function openClearCam() {
        var i = root.camIdxIn(root.cfgDraft, root.cfgDraftSel)
        if (i < 0) return
        var c = root.cfgDraft[i]
        confirmDlg.title = "清空相机配置"
        confirmDlg.bodyText = "确定要清空 <b style=\"color:#dc2626\">" + c.name + "</b> 的拉流配置吗？<br><span style=\"color:#94a3b8;font-size:12px\">清空后该相机将停用，地址参数为空，且此操作不可撤销。</span>"
        confirmDlg.confirmText = "清空配置"
        confirmDlg.onOk = function() {
            var c2 = root.cfgDraft[root.camIdxIn(root.cfgDraft, root.cfgDraftSel)]
            if (!c2) return
            c2.enable = false; c2.ip = ""; c2.port = 554; c2.path = ""; c2.user = ""; c2.pass = ""
            c2.stream = "主码流"; c2.transport = "TCP"; c2.fps = 25
            root.renderCfgForm()
            root.toast("已清空" + c2.name + "的配置（保存设置后生效）", "info")
        }
        confirmDlg.open()
    }
    // 保存设置：草稿写回生效（配置持久化 + 拉流同步 + 选中集重建）
    function saveCfgDlg() {
        root.readCfgForm()   // 表单 → 草稿
        // 先停掉已被删除相机的流（不在新配置中的）
        for (var d = 0; d < root.camCfg.length; d++) {
            var oldId = root.camCfg[d].id
            if (root.camIdxIn(root.cfgDraft, oldId) < 0) {
                var ds = bridge.videoStream(oldId)
                if (ds) ds.stop()
            }
        }
        // 草稿 → 正式配置
        root.camCfg = root.cfgDraft.map(function(c){ return Object.assign({}, c) })
        root.camCfgSel = root.cfgDraftSel
        // 按 id 重建选中集（删除的相机自动退出）
        var ns = []
        for (var k = 0; k < root.camCfg.length; k++)
            if (root.cfgSelIds.indexOf(root.camCfg[k].id) >= 0) ns.push(k)
        root.selected = ns.length ? ns : root.defaultSelected(root.layMode)
        // 云台焦点索引越界修正（删除相机后）
        if (root.focusIdx >= root.camCfg.length) root.focusIdx = Math.max(0, root.camCfg.length - 1)
        root.saveAll()
        camCfgDlg.close()
        root.toast("拉流设置已保存")
    }
}

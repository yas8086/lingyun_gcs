import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 监控视图（复刻原型 #view-monitor）：
// 飞艇横幅 → 电源总览 → 设备卡片网格（BMS/MPPT/DCDC/LoRa，含 SOC 环形/字段配置/更多折叠）→ 运行日志
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)

    property bool stripCollapsed: false
    function bridgeReadiness() { void root.themeRoot.dataTick; return bridge.readinessState() }

    function fmt(v, dp) { return isNaN(v) ? "--" : Number(v).toFixed(dp); }
    function fmtInt(v) { return isNaN(v) ? "--" : Math.round(v); }

    // 温度单位换算（决策 #24）：0=℃ 1=℉
    function tempUnit() { return bridge.configTempUnit() === 1 ? "℉" : "℃" }
    function toTemp(c) {
        void root.themeRoot.dataTick
        if (isNaN(c)) return "--"
        return bridge.configTempUnit() === 1 ? (c * 9 / 5 + 32).toFixed(1) : c.toFixed(1)
    }
    // 压力单位换算（决策：协议值为 Pa，按设置换算显示）：0=kPa 1=Pa 2=bar 3=psi
    // 带 dataTick 依赖，设置页修改单位后自动跟随换算
    function presStr(pa) {
        void root.themeRoot.dataTick
        if (isNaN(pa)) return "--"
        switch (bridge.configPressureUnit()) {
            case 1: return Math.round(pa) + " Pa"
            case 2: return (pa / 100000).toFixed(3) + " bar"
            case 3: return (pa / 6894.7573).toFixed(1) + " psi"
            default: return (pa / 1000).toFixed(1) + " kPa"
        }
    }
    // 温度/压力采集模块高度：按节点数与卡片自适应尺寸显式计算，
    // 节点多换行时模块随之增高（ScrollView 滚动兜底），最小 150。
    // 依赖 dataTick + root.width，节点数/窗口宽度变化时自动重算。
    function loraPanelHCalc() {
        void root.themeRoot.dataTick
        const n = root.loraNodes().length
        if (n === 0) return 150
        const cardW = 92, cardH = 70, gap = 6
        const flowW = Math.max(1, root.width - 28)          // 模块内可用宽（margin 14*2）
        const perRow = Math.max(1, Math.floor((flowW + gap) / (cardW + gap)))
        const rows = Math.ceil(n / perRow)
        return Math.max(150, 30 + 8 + rows * cardH + (rows - 1) * gap + 28)
    }
    // 功率单位：W / kW
    function powerUnit() { return "W" }
    function toPower(w) {
        void root.themeRoot.dataTick
        return isNaN(w) ? "--" : Math.round(w)
    }
    function socVal() { void root.themeRoot.dataTick; return bridge.value("bms","soc") }
    // 通用字段显示辅助：读取数值并格式化为字符串（触发 dataTick 依赖）
    function valStr(dev, key, dp, unit) {
        void root.themeRoot.dataTick
        return root.fmt(bridge.value(dev,key), dp) + (unit||"")
    }
    function battStr() { void root.themeRoot.dataTick; return root.fmt(bridge.value("bms","soc"),0) + "%" }
    function bkSoc() { void root.themeRoot.dataTick; return bridge.value("backup","soc") }
    function backupStr(fid, u) {
        void root.themeRoot.dataTick
        if (fid==="fault") return root.fmtInt(bridge.value("backup","fault"))
        if (fid==="soh") return root.fmtInt(bridge.value("backup","soh"))
        return root.fmt(bridge.value("backup", fid), fid==="diff_v"?2:1) + u
    }
    function mpptStr(fid, u) {
        void root.themeRoot.dataTick
        if (fid==="fault_m") return root.fmtInt(bridge.value("mppt","fault"))
        if (fid==="today") return root.fmt(bridge.value("mppt","today"),2)
        return root.fmt(bridge.value("mppt", fid),1) + u
    }
    function dcdcStr(fid, u) {
        void root.themeRoot.dataTick
        if (fid==="fault_d") return root.fmtInt(bridge.value("dcdc","fault"))
        if (fid==="enabled") return bridge.value("dcdc","enabled")===1 ? "开启" : "关闭"
        return root.fmt(bridge.value("dcdc", fid),1) + u
    }

    // ===== 运行日志流（决策 #33 环形 500）=====
    property var logStream: []
    property string logFilter: "all"          // all | alarm
    function addLog(type, msg) {
        const d = new Date().toTimeString().slice(0,8)
        root.logStream.push({type:type, msg:msg, time:d})
        if (root.logStream.length > 500) root.logStream.shift()
        if (root.themeRoot) root.themeRoot.lastMsg = msg
    }
    // 告警：写入日志流（同时记录到 bridge 便于确认/计数）
    function addAlarm(lv, msg, source) {
        const d = new Date().toTimeString().slice(0,8)
        root.logStream.push({type:"alarm", lv:lv, msg:msg, time:d, source:source||"", aid:root.alarmSeq++})
        if (root.logStream.length > 500) root.logStream.shift()
        if (root.themeRoot) root.themeRoot.lastMsg = "⚠ " + msg
        bridge.addAlarm(msg, lv, source)
        root.alarmsChanged()
    }
    property int alarmSeq: 1

    // 时间轴事件（决策：状态栏/操作时间轴）
    property var tlEvents: []
    function recordEvent(lv, msg) {
        root.tlEvents.push({t:Date.now(), lv:lv, msg:msg})
        if (root.tlEvents.length > 80) root.tlEvents.shift()
    }

    // 设备在线状态（含数据新鲜度演示置灰）
    function devOff(dev) {
        void root.themeRoot.dataTick
        return !bridge.online(dev)
    }
    function devBadge(dev) { return root.devOff(dev) ? "离线" : "正常" }

    // 设备卡显示字段可见性（决策：更多字段配置）
    property var fieldVis: {
        "bms":  ["pack_v","pack_i","max_t","max_v","min_v","diff_v"],
        "mppt": ["charge_i","today","fault_m","pv_v","total"],
        "dcdc": ["out_i","temp","fault_d","in_v","enabled"]
    }
    function fieldShown(dev, fid) {
        return root.fieldVis[dev].indexOf(fid) !== -1
    }

    // ===== 电源总览（原型 power-strip）=====
    function psPin()  { void root.themeRoot.dataTick; return root.devOff("mppt") ? 0 : bridge.value("mppt","pv_p") }
    function psPout() { void root.themeRoot.dataTick; return root.devOff("dcdc") ? 0 : bridge.value("dcdc","out_p") }
    function psBatt() { void root.themeRoot.dataTick; return root.devOff("bms") ? 0 : bridge.value("bms","pack_i") }
    function psNet()  { return root.psPin() - root.psPout() }

    // ===== 外层滚动容器（窗口化/小高度时支持鼠标滚轮滑动查看全部模块）=====
    ScrollView {
        id: monScroll
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: monCol
            // 宽度绑定到外层 MonitorView 根 Item（root.width），由上层 Loader 父级
            // Layout.fillWidth 约束，绝对稳定不受内部内容影响。
            width: root.width
            // 高度 = max(内容实际高度, 根 Item 可视高度)
            // 用 root.height 而非 viewport.height：viewport 在某些 Qt 版本下初始化/缩放
            // 时尺寸更新滞后，root 由外层 Loader anchors.fill: parent 约束，值稳定。
            // 内容不够时撑满视口，保证运行日志 fillHeight 能吸掉所有剩余空间贴底；
            // 内容多时取 implicitHeight，由 ScrollView 滚动。
            height: Math.max(implicitHeight, root.height)
            spacing: 12

            // ===== 飞艇横幅（原型 airship-strip）=====
            Rectangle {
                visible: !root.themeRoot.isModuleHidden("strip")
                Layout.fillWidth: true
                // 展开固定高度；收起依内容自适应（只留参数行 + 右侧按钮）
                Layout.preferredHeight: root.stripCollapsed ? stripRow.implicitHeight + 16 : 124
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                RowLayout {
                    id: stripRow
                    anchors.fill: parent
                    anchors.topMargin: 8; anchors.bottomMargin: 8
                    anchors.leftMargin: 20; anchors.rightMargin: 20
                    spacing: 20
                    // 飞艇艺术图（as-art，真实蓝色 SVG）：无背景色，仅图标
                    Rectangle {
                        visible: !root.stripCollapsed
                        Layout.preferredWidth: 156
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignVCenter
                        color: "transparent"
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qml/img/airship-blue.svg"
                            sourceSize.width: 132; sourceSize.height: 60
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                    // 名称 + 信息（as-info）：收起时隐藏名称，参数行始终展示
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        Text { text: "灵云01 · 载重飞艇"; visible: !root.stripCollapsed; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 18 }
                        Row {
                            spacing: 28
                            Text {
                                text: "链路 <b>" + (bridge.isSerialOpen() ? "正常" : "断线") + "</b>"
                                font.pixelSize: 14; color: root.themeRoot.colText2
                                textFormat: Text.RichText
                            }
                            Text {
                                text: "电池电量 <b>" + root.battStr() + "</b>"
                                font.pixelSize: 14; color: root.themeRoot.colText2; textFormat: Text.RichText
                            }
                            Text {
                                text: "舱内温度 <b>" + root.toTemp(bridge.value("bms","max_t")) + " " + root.tempUnit() + "</b>"
                                font.pixelSize: 14; color: root.themeRoot.colText2; textFormat: Text.RichText
                            }
                            Text {
                                text: "舱内气压 <b>—</b>"
                                font.pixelSize: 14; color: root.themeRoot.colText2; textFormat: Text.RichText
                            }
                        }
                    }
                    // 右侧操作区（as-btns）：就绪度 + 紧急操作 + 收起
                    RowLayout {
                        spacing: 10
                        Layout.alignment: Qt.AlignVCenter
                        Rectangle {
                            id: stripReadyPill
                            radius: 11; Layout.preferredHeight: 43
                            implicitWidth: stripReady.implicitWidth + 29
                            color: root.bridgeReadiness() === 1 ? root.themeRoot.colOk
                                 : root.bridgeReadiness() === 2 ? root.themeRoot.colWarn
                                 : root.bridgeReadiness() === 3 ? root.themeRoot.colErr : root.themeRoot.colOff
                            Text {
                                id: stripReady; anchors.centerIn: parent; color: "white"
                                font.pixelSize: 16; font.bold: true
                                text: root.bridgeReadiness() === 0 ? "待自检"
                                     : root.bridgeReadiness() === 1 ? "✓ 就绪可飞"
                                     : root.bridgeReadiness() === 2 ? "⚠ 起飞受限" : "✗ 不可起飞"
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.themeRoot.openReadPop(stripReadyPill) }
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_1
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "紧急操作"
                            Layout.preferredHeight: 43
                            leftPadding: 17; rightPadding: 17; topPadding: 0; bottomPadding: 0
                            background: Rectangle { radius: 11; color: root.themeRoot.colErrSoft; border.color: root.themeRoot.colErr }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colErr; font.bold: true; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: root.themeRoot.openEmergency()
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_2
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: root.stripCollapsed ? "▾ 展开" : "▴ 收起"
                            Layout.preferredHeight: 43
                            leftPadding: 17; rightPadding: 17; topPadding: 0; bottomPadding: 0
                            background: Rectangle {
                                radius: 10; color: root.themeRoot.colCard2; border.color: (hover_2.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.bold: true; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: root.stripCollapsed = !root.stripCollapsed
                        }
                    }
                }
            }

            // ===== 电源总览（原型 power-strip）=====
            Rectangle {
                visible: !root.themeRoot.isModuleHidden("power")
                Layout.fillWidth: true
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    Row {
                        spacing: 14
                        Text { text: "⚡ 电源总览"; font.bold: true; font.pixelSize: 14; color: root.themeRoot.colText }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            Text { text: "光伏 <b>" + Math.round(root.psPin()) + " W</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                            Text { text: "→"; color: root.themeRoot.colPrimary; font.bold: true }
                            Text { text: "电池 <b>" + (root.psBatt()>=0?"+":"") + root.fmt(root.psBatt(),1) + " A</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                            Text { text: "→"; color: root.themeRoot.colPrimary; font.bold: true }
                            Text { text: "DCDC <b>" + Math.round(root.psPout()) + " W</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                            Text { text: "→"; color: root.themeRoot.colPrimary; font.bold: true }
                            Text { text: "负载 <b>" + Math.round(root.psPout()) + " W</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                        }
                    }
                    Grid {
                        columns: root.width > 1500 ? 4 : 2
                        columnSpacing: 8; rowSpacing: 8
                        Layout.fillWidth: true
                        // 输入功率 / 输出功率 / 净充放 / 电量趋势
                        Repeater {
                            model: [
                                {k:"输入功率", v: Math.round(root.psPin()) + " W"},
                                {k:"输出功率", v: Math.round(root.psPout()) + " W"},
                                {k:"净充放功率", v: (root.psNet()>=0?"+":"") + Math.round(root.psNet()) + " W"},
                                {k:"电量趋势", v: root.psNet()>5 ? "充电中" : (root.psNet()<-5 ? "放电中" : "平衡")}
                            ]
                            Rectangle {
                                width: 200; height: 40; radius: 8; color: root.themeRoot.colCard2
                                Column {
                                    anchors.centerIn: parent
                                    Text { text: modelData.k; font.pixelSize: 10; color: root.themeRoot.colText2; anchors.horizontalCenter: parent.horizontalCenter }
                                    Text { text: modelData.v; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText; anchors.horizontalCenter: parent.horizontalCenter }
                                }
                            }
                        }
                    }
                }
            }

            // ===== 设备卡片网格（原型 .main）=====
            GridLayout {
                visible: !root.themeRoot.isModuleHidden("device")
                columns: root.width > 1440 ? 4 : (root.width > 1200 ? 3 : (root.width > 900 ? 2 : 1))
                columnSpacing: 12; rowSpacing: 12
                Layout.fillWidth: true

                // ---- BMS 电池管理 ----
                Rectangle {
                    // 悬停上浮（对齐原型 .card:hover{translateY(-2px)}）
                    transform: Translate { y: devHover1.hovered ? -2 : 0; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                    HoverHandler { id: devHover1 }
                    Layout.fillWidth: true; Layout.preferredHeight: 260
                    radius: 14
                    color: root.themeRoot.colCard
                    border.color: root.themeRoot.colLine
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 8
                        // 卡头
                        RowLayout {
                            Text { text: "BMS 电池管理"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 999; implicitWidth: 40; implicitHeight: 20
                                color: root.devOff("bms") ? "transparent" : root.themeRoot.colOkSoft
                                border.color: root.devOff("bms") ? root.themeRoot.colOff : root.themeRoot.colOk
                                Text {
                                    anchors.centerIn: parent
                                    text: root.devBadge("bms"); font.pixelSize: 11; font.bold: true
                                    color: root.devOff("bms") ? root.themeRoot.colOff : root.themeRoot.colOk
                                }
                            }
                        }
                        // hero：SOC 环形 + 大数字
                        Row {
                            spacing: 14
                            // SOC 环形（Canvas 比父 Rectangle 小，让父 Rectangle 的深色背景透出）
                            Rectangle {
                                width: 74; height: 74
                                color: root.themeRoot.colCard
                                Canvas {
                                    id: bmsRing
                                    anchors.centerIn: parent
                                    width: 68; height: 68
                                    onPaint: {
                                        const ctx = getContext("2d")
                                        void root.themeRoot.dataTick
                                        const soc = bridge.value("bms","soc")
                                        const col = isNaN(soc) ? root.themeRoot.colOff : (soc>50 ? root.themeRoot.colOk : (soc>20 ? root.themeRoot.colWarn : root.themeRoot.colErr))
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.lineWidth = 7
                                        const cx = width/2, cy = height/2, r = 30
                                        // 背景圆环
                                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, 6.283)
                                        ctx.strokeStyle = root.themeRoot.colCard2; ctx.stroke()
                                        // 进度弧形
                                        if (!isNaN(soc) && soc > 0) {
                                            const end = -Math.PI/2 + 6.283 * soc/100
                                            ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI/2, end, false)
                                            ctx.strokeStyle = col; ctx.stroke()
                                        }
                                    }
                                    Connections {
                                        target: root.themeRoot
                                        function onDataTickChanged() { bmsRing.requestPaint() }
                                    }
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: root.fmtInt(root.socVal()) + "%"; font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "荷电状态 SOC"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                            // hero kvs：总压/总电流
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                Column {
                                    width: 88; height: 52; spacing: 2
                                    Text { text: "总压"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                                    Text { text: root.valStr("bms","pack_v",1," V"); font.pixelSize: 22; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
                                }
                                Column {
                                    width: 88; height: 52; spacing: 2
                                    Text { text: "总电流"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                                    Text { text: root.valStr("bms","pack_i",1," A"); font.pixelSize: 22; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
                                }
                            }
                        }
                        // 更多字段
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: [
                                    {fid:"max_t", k:"最高温度", u:" ℃"},
                                    {fid:"max_v", k:"最高单体", u:" V"},
                                    {fid:"min_v", k:"最低单体", u:" V"},
                                    {fid:"diff_v", k:"单体压差", u:" V"}
                                ]
                                Rectangle {
                                    visible: root.fieldShown("bms", modelData.fid)
                                    width: 108; height: 42; radius: 8; color: root.themeRoot.colCard2
                                    Column {
                                        anchors.centerIn: parent
                                        Text { text: modelData.k; font.pixelSize: 10; color: root.themeRoot.colText2 }
                                        Text {
                                            text: root.valStr("bms", modelData.fid, modelData.fid==="diff_v"?2:1, modelData.u)
                                            font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- MPPT 光伏 ----
                Rectangle {
                    // 悬停上浮（对齐原型 .card:hover{translateY(-2px)}）
                    transform: Translate { y: devHover2.hovered ? -2 : 0; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                    HoverHandler { id: devHover2 }
                    Layout.fillWidth: true; Layout.preferredHeight: 260
                    radius: 14
                    color: root.themeRoot.colCard
                    border.color: root.themeRoot.colLine
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 8
                        RowLayout {
                            Text { text: "MPPT 光伏"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 999; implicitWidth: 40; implicitHeight: 20
                                color: root.devOff("mppt") ? "transparent" : root.themeRoot.colOkSoft
                                border.color: root.devOff("mppt") ? root.themeRoot.colOff : root.themeRoot.colOk
                                Text {
                                    anchors.centerIn: parent
                                    text: root.devBadge("mppt"); font.pixelSize: 11; font.bold: true
                                    color: root.devOff("mppt") ? root.themeRoot.colOff : root.themeRoot.colOk
                                }
                            }
                        }
                        Row {
                            spacing: 20
                            Column {
                                Text { text: root.toPower(bridge.value("mppt","pv_p")) + root.powerUnit(); font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "光伏功率"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                            Column {
                                Text { text: root.valStr("mppt","batt_v",1," V"); font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "电池电压"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: [
                                    {fid:"charge_i", k:"充电电流", u:" A"},
                                    {fid:"today", k:"日发电量", u:" kWh"},
                                    {fid:"fault_m", k:"故障码", u:""},
                                    {fid:"pv_v", k:"光伏电压", u:" V"},
                                    {fid:"total", k:"总发电量", u:" kWh"}
                                ]
                                Rectangle {
                                    visible: root.fieldShown("mppt", modelData.fid)
                                    width: 108; height: 42; radius: 8; color: root.themeRoot.colCard2
                                    Column {
                                        anchors.centerIn: parent
                                        Text { text: modelData.k; font.pixelSize: 10; color: root.themeRoot.colText2 }
                                        Text {
                                            text: root.mpptStr(modelData.fid, modelData.u)
                                            font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- DCDC 电源模块 ----
                Rectangle {
                    // 悬停上浮（对齐原型 .card:hover{translateY(-2px)}）
                    transform: Translate { y: devHover3.hovered ? -2 : 0; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                    HoverHandler { id: devHover3 }
                    Layout.fillWidth: true; Layout.preferredHeight: 260
                    radius: 14
                    color: root.themeRoot.colCard
                    border.color: root.themeRoot.colLine
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 8
                        RowLayout {
                            Text { text: "DCDC 电源模块"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 999; implicitWidth: 40; implicitHeight: 20
                                color: root.devOff("dcdc") ? "transparent" : root.themeRoot.colOkSoft
                                border.color: root.devOff("dcdc") ? root.themeRoot.colOff : root.themeRoot.colOk
                                Text {
                                    anchors.centerIn: parent
                                    text: root.devBadge("dcdc"); font.pixelSize: 11; font.bold: true
                                    color: root.devOff("dcdc") ? root.themeRoot.colOff : root.themeRoot.colOk
                                }
                            }
                        }
                        Row {
                            spacing: 20
                            Column {
                                Text { text: root.valStr("dcdc","out_v",1," V"); font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "输出电压"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                            Column {
                                Text { text: root.toPower(bridge.value("dcdc","out_p")) + root.powerUnit(); font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "输出功率"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: [
                                    {fid:"out_i", k:"输出电流", u:" A"},
                                    {fid:"temp", k:"散热温度", u:" ℃"},
                                    {fid:"fault_d", k:"故障码", u:""},
                                    {fid:"in_v", k:"输入电压", u:" V"},
                                    {fid:"enabled", k:"输出使能", u:""}
                                ]
                                Rectangle {
                                    visible: root.fieldShown("dcdc", modelData.fid)
                                    width: 108; height: 42; radius: 8; color: root.themeRoot.colCard2
                                    Column {
                                        anchors.centerIn: parent
                                        Text { text: modelData.k; font.pixelSize: 10; color: root.themeRoot.colText2 }
                                        Text {
                                            text: root.dcdcStr(modelData.fid, modelData.u)
                                            font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- 备用电源（12S 备用 BMS）----
                Rectangle {
                    // 悬停上浮（对齐原型 .card:hover{translateY(-2px)}）
                    transform: Translate { y: devHover4.hovered ? -2 : 0; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                    HoverHandler { id: devHover4 }
                    Layout.fillWidth: true; Layout.preferredHeight: 260
                    radius: 14
                    color: root.themeRoot.colCard
                    border.color: root.themeRoot.colLine
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 8
                        RowLayout {
                            Text { text: "备用电源（12S）"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                radius: 999; implicitWidth: 40; implicitHeight: 20
                                color: root.devOff("backup") ? "transparent" : root.themeRoot.colOkSoft
                                border.color: root.devOff("backup") ? root.themeRoot.colOff : root.themeRoot.colOk
                                Text {
                                    anchors.centerIn: parent
                                    text: root.devBadge("backup"); font.pixelSize: 11; font.bold: true
                                    color: root.devOff("backup") ? root.themeRoot.colOff : root.themeRoot.colOk
                                }
                            }
                        }
                        // 主数值：总压 + SOC
                        Row {
                            spacing: 20
                            Column {
                                Text { text: root.valStr("backup","pack_v",1," V"); font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "电池总压"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                            Column {
                                Text { text: root.fmtInt(root.bkSoc()) + "%"; font.pixelSize: root.themeRoot.fsDisplay; font.bold: true; color: root.themeRoot.colText }
                                Text { text: "荷电状态 SOC"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                            }
                        }
                        // 更多字段
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: [
                                    {fid:"pack_i", k:"总电流", u:" A"},
                                    {fid:"soh", k:"健康度 SOH", u:" %"},
                                    {fid:"max_t", k:"最高温度", u:" ℃"},
                                    {fid:"diff_v", k:"单体压差", u:" V"},
                                    {fid:"fault", k:"故障码", u:""}
                                ]
                                Rectangle {
                                    width: 108; height: 42; radius: 8; color: root.themeRoot.colCard2
                                    Column {
                                        anchors.centerIn: parent
                                        Text { text: modelData.k; font.pixelSize: 10; color: root.themeRoot.colText2 }
                                        Text {
                                            text: root.backupStr(modelData.fid, modelData.u)
                                            font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ===== 温度/压力采集（宽屏，显示在运行日志上方）=====
            Rectangle {
                visible: !root.themeRoot.isModuleHidden("lora")
                Layout.fillWidth: true
                // 模块高度按节点数显式计算（loraPanelHCalc），节点多换行时自动撑起，最小 150
                Layout.preferredHeight: root.loraPanelHCalc()
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                    RowLayout {
                        Text { text: "温度 / 压力采集"; font.bold: true; font.pixelSize: 14; color: root.themeRoot.colText }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            radius: 999; implicitWidth: 40; implicitHeight: 20
                            color: root.devOff("lora") ? "transparent" : root.themeRoot.colOkSoft
                            border.color: root.devOff("lora") ? root.themeRoot.colOff : root.themeRoot.colOk
                            Text {
                                anchors.centerIn: parent
                                text: root.devBadge("lora"); font.pixelSize: 11; font.bold: true
                                color: root.devOff("lora") ? root.themeRoot.colOff : root.themeRoot.colOk
                            }
                        }
                    }
                    // LoRa 节点网格（宽屏横排；节点同时上报温度+压力时一并显示）
                    Flow {
                        id: loraFlow
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.loraNodes()
                            Rectangle {
                                // 宽度随内容自适应，高度统一固定（压力/温度卡片等高，视觉一致）
                                implicitWidth: col.implicitWidth + 16
                                width: implicitWidth
                                height: 60
                                radius: 8
                                color: modelData.alarm !== 0 ? root.themeRoot.colErrSoft : root.themeRoot.colCard2
                                border.color: modelData.alarm !== 0 ? root.themeRoot.colErr : root.themeRoot.colLine
                                Column {
                                    id: col
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 5
                                        Text { text: "#" + modelData.id; font.pixelSize: 10; color: root.themeRoot.colText2; font.weight: Font.DemiBold }
                                        Text {
                                            text: modelData.pressure !== 0 ? "压力" : "温度"
                                            font.pixelSize: 10; font.weight: Font.DemiBold
                                            color: modelData.pressure !== 0 ? root.themeRoot.colOk : root.themeRoot.colPrimary
                                        }
                                    }
                                    // 主值行：压力节点压力+温度同行（温度小字），温度节点仅温度
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 8
                                        Text {
                                            id: mainVal
                                            text: modelData.pressure !== 0
                                                  ? root.presStr(modelData.pressure)
                                                  : root.toTemp(modelData.temp) + " " + root.tempUnit()
                                            font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText
                                        }
                                        // 压力传感器自带温度检测：同行小字显示（间隔由 Row spacing 控制）
                                        Text {
                                            visible: modelData.pressure !== 0 && modelData.temp !== 0
                                            text: "温度 " + root.toTemp(modelData.temp) + root.tempUnit()
                                            font.pixelSize: 11; color: root.themeRoot.colText2
                                            anchors.baseline: mainVal.baseline
                                        }
                                    }
                                    Text {
                                        visible: modelData.alarm !== 0
                                        text: modelData.alarm > 0 ? "超上限" : "超下限"
                                        font.pixelSize: 10; font.bold: true; color: root.themeRoot.colErr
                                    }
                                }
                            }
                        }
                    }
                    // 底部占位项：吸收剩余高度，把标题/内容顶到左上角
                    // （无数据时内容少，若无此项 ColumnLayout 会把内容垂直居中，标题显得居中）
                    Item { Layout.fillHeight: true }
                }
            }

            // ===== 运行日志（原型 logbar，含告警确认）=====
            Rectangle {
                visible: !root.themeRoot.isModuleHidden("log")
                Layout.fillWidth: true
                // fillHeight 让日志卡片吸收剩余空间，全屏时顶到底部；
                // minimumHeight 参与 ColumnLayout implicitHeight 计算（fill 项按
                // 最小高度计入），保证窗口化/内容多时日志卡至少 260 高且可整体滚动。
                Layout.fillHeight: true
                Layout.minimumHeight: 260
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 6
                    RowLayout {
                        Text { text: "运行日志"; font.bold: true; font.pixelSize: 14; color: root.themeRoot.colText }
                        Item { Layout.fillWidth: true }
                        // 筛选
                        Repeater {
                            model: [["all","全部"],["alarm","仅告警"]]
                            Rectangle {
                                // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                scale: ma_1.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                radius: 7; implicitWidth: 50; implicitHeight: 26
                                color: root.logFilter === modelData[0] ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData[1]; font.pixelSize: 12; font.weight: Font.DemiBold
                                    color: root.logFilter === modelData[0] ? "white" : root.themeRoot.colText2
                                }
                                MouseArea {
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    id: ma_1
                                    anchors.fill: parent
                                    onClicked: root.logFilter = modelData[0]
                                }
                            }
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_3
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "清空"
                            background: Rectangle {
                                radius: 7; color: root.themeRoot.colCard2; border.color: (hover_3.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12 }
                            onClicked: { root.logStream = []; root.clearAlarms() }
                        }
                    }
                    // 日志流
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true
                        model: root.filteredLog()
                        spacing: 2
                        delegate: RowLayout {
                            width: ListView.view ? ListView.view.width : parent.width
                            spacing: 8
                            Text { text: modelData.time; color: root.themeRoot.colText2; font.pixelSize: 11 }
                            // 类型标签
                            Text {
                                text: modelData.type === "alarm" ? "[" + modelData.lv + "]" : "[" + modelData.type.toUpperCase() + "]"
                                font.pixelSize: 11; font.bold: true
                                color: modelData.type === "alarm" ? root.themeRoot.colErr : root.logColor(modelData.type)
                            }
                            Text { text: modelData.source !== "" ? "[" + modelData.source + "]" : ""; color: root.themeRoot.colText2; font.pixelSize: 11 }
                            Text { text: modelData.msg; elide: Text.ElideRight; Layout.fillWidth: true; color: root.themeRoot.colText; font.pixelSize: 12 }
                            // 告警确认按钮
                            Rectangle {
                                // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                scale: ma_2.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                visible: modelData.type === "alarm"
                                width: 52; height: 20; radius: 6
                                color: root.themeRoot.colCard2
                                border.color: root.themeRoot.colErr
                                Text {
                                    anchors.centerIn: parent; text: "确认"; font.pixelSize: 11
                                    color: root.themeRoot.colErr
                                }
                                MouseArea {
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    id: ma_2
                                    anchors.fill: parent
                                    onClicked: root.confirmLogAlarm(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function logColor(type) {
        return type==="ok" ? root.themeRoot.colOk
             : type==="warn" ? root.themeRoot.colWarn
             : type==="err" ? root.themeRoot.colErr : root.themeRoot.colPrimary
    }
    function filteredLog() {
        void root.themeRoot.dataTick
        const arr = root.logFilter === "alarm" ? root.logStream.filter(x=>x.type==="alarm") : root.logStream
        return arr.slice().reverse()
    }
    // 告警确认：bridge 层（形参 e 为日志条目，确认全部未确认告警）
    function confirmLogAlarm(e) {
        root.clearAlarms()
    }
    function clearAlarms() {
        bridge.confirmAllAlarms()
        root.alarmsChanged()
    }
    function alarmsChanged() {}

    // 数据源辅助
    function loraNodes() {
        void root.themeRoot.dataTick
        return bridge.loraNodes()
    }

    // 初始化演示日志（首次运行）
    Component.onCompleted: {
        root.addLog("info", "帧解析正常，设备在线")
        root.addLog("ok", "系统就绪")
    }
}

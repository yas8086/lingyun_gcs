import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 飞控视图（落地设计《飞控页面落地设计.md》，对齐 UI 原型）：
// 与地图页合并——右栏 fc-map 复用原 MapView（天地图/OSM 瓦片），左栏 fc-info 是
// 姿态仪表卡 + 电机状态卡，顶栏 fc-bar 为状态徽章（在线/解锁/电池/GPS/告警/模式）。
// 纯展示不控制：数据走 bridge 的 fc 字段（协议 5.5），电机转速/温度为本地模拟。
Item {
    id: root
    property QtObject themeRoot: null

    // ===== 工具函数（数据均带 dataTick 依赖，遥测刷新自动更新）=====
    function fmt(v, dp) { return isNaN(v) ? "--" : Number(v).toFixed(dp); }
    function fcOnline() { void root.themeRoot.dataTick; return bridge.online("fc") }
    function fcVal(key, dp) { void root.themeRoot.dataTick; return root.fmt(bridge.value("fc", key), dp) }
    function fcMode() { void root.themeRoot.dataTick; return bridge.fcStringField("mode") }
    function fcArmed() { void root.themeRoot.dataTick; return bridge.value("fc", "armed") === 1 }
    function fcBattPct() { void root.themeRoot.dataTick; return Math.round(bridge.value("fc", "batt_pct") * 100) }

    // 姿态读数文本：俯仰/横滚带符号、航向一段
    function attLbl() {
        void root.themeRoot.dataTick
        const on = root.fcOnline()
        const fmt1 = v => (v>=0?"+":"") + Number(v).toFixed(1)
        const r = on ? bridge.value("fc","roll") : 0
        const p = on ? bridge.value("fc","pitch") : 0
        const y = on ? bridge.value("fc","yaw") : 0
        return "俯仰 " + fmt1(p) + "° · 横滚 " + fmt1(r) + "° · 航向 " + (isNaN(y)?"0.0":Number(y).toFixed(1)) + "°"
    }

    ColumnLayout {
        id: panel
        anchors.fill: parent
        spacing: 12

        // ===== 顶栏横幅 fc-bar =====
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: 12
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            RowLayout {
                anchors.fill: parent; anchors.margins: 10
                spacing: 12
                // 标题
                Text { text: "✈ 飞控"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                // 在线
                Rectangle {
                    Layout.preferredHeight: 24; radius: 99
                    implicitWidth: onTxt.implicitWidth + 22
                    color: root.fcOnline() ? root.themeRoot.colOkSoft : root.themeRoot.colCard2
                    border.color: root.fcOnline() ? root.themeRoot.colOk : root.themeRoot.colLine
                    Row { anchors.centerIn: parent; spacing: 5
                        Rectangle { width: 7; height: 7; radius: 3.5; anchors.verticalCenter: parent.verticalCenter; color: root.fcOnline() ? root.themeRoot.colOk : root.themeRoot.colText2 }
                        Text { id: onTxt; text: root.fcOnline() ? "在线" : "离线"; font.pixelSize: 12; font.bold: true; color: root.fcOnline() ? root.themeRoot.colOk : root.themeRoot.colText2 }
                    }
                }
                // 解锁
                Rectangle {
                    Layout.preferredHeight: 24; radius: 99
                    implicitWidth: armTxt.implicitWidth + 22
                    color: root.fcArmed() ? root.themeRoot.colOkSoft : root.themeRoot.colCard2
                    border.color: root.fcArmed() ? root.themeRoot.colOk : root.themeRoot.colLine
                    Text {
                        id: armTxt; anchors.centerIn: parent
                        text: root.fcArmed() ? "🔓 已解锁" : "🔒 已锁定"
                        font.pixelSize: 12; font.bold: true
                        color: root.fcArmed() ? root.themeRoot.colOk : root.themeRoot.colText2
                    }
                }
                // 电池
                Rectangle {
                    Layout.preferredHeight: 24; radius: 99
                    implicitWidth: battTxt.implicitWidth + 22
                    color: root.themeRoot.colCard2; border.color: root.themeRoot.colLine
                    Text {
                        id: battTxt; anchors.centerIn: parent
                        text: (root.fcOnline() ? root.fcBattPct() : "--") + "%  " + root.fcVal("batt_v",1) + " V"
                        font.pixelSize: 12; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText
                    }
                }
                // GPS 颗数（本地模拟）
                Rectangle {
                    Layout.preferredHeight: 24; radius: 99
                    implicitWidth: gpsTxt.implicitWidth + 22
                    color: root.themeRoot.colCard2; border.color: root.themeRoot.colLine
                    Text {
                        id: gpsTxt; anchors.centerIn: parent
                        text: "🛰 GPS " + root.gpsSat + " 颗"
                        font.pixelSize: 12; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText2
                    }
                }
                Item { Layout.fillWidth: true }
                // 告警（当前无告警，数值 0 绿）
                Rectangle {
                    Layout.preferredHeight: 24; radius: 99
                    implicitWidth: alarmTxt.implicitWidth + 22
                    color: root.anyHot() ? root.themeRoot.colWarnSoft : root.themeRoot.colOkSoft
                    border.color: root.anyHot() ? root.themeRoot.colWarn : root.themeRoot.colOk
                    Text {
                        id: alarmTxt; anchors.centerIn: parent
                        text: "⚠ 告警 " + (root.anyHot() ? 1 : 0)
                        font.pixelSize: 12; font.bold: true
                        color: root.anyHot() ? root.themeRoot.colWarn : root.themeRoot.colOk
                    }
                }
                // 飞行模式
                Rectangle {
                    Layout.preferredHeight: 24; radius: 99
                    implicitWidth: modeTxt.implicitWidth + 22
                    color: root.themeRoot.colPrimarySoft; border.color: root.themeRoot.colPrimary
                    Text {
                        id: modeTxt; anchors.centerIn: parent
                        text: (root.fcOnline() && root.fcMode() ? root.fcMode() : "—")
                        font.pixelSize: 12; font.bold: true; color: root.themeRoot.colPrimary
                    }
                }
            }
        }

        // ===== 分栏主体 fc-split =====
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ---- 左栏 fc-info（固定宽度，内部滚动）----
            Rectangle {
                Layout.preferredWidth: 280
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                color: "transparent"
                ScrollView {
                    anchors.fill: parent
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        width: parent.width
                        spacing: 10

                        // 姿态仪表卡
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 252
                            radius: 12
                            color: root.themeRoot.colCard
                            border.color: root.themeRoot.colLine
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 12; spacing: 6
                                // 卡片头
                                Row {
                                    spacing: 8
                                    Text { text: "🔄 姿态仪表"; font.bold: true; font.pixelSize: 12; color: root.themeRoot.colText2 }
                                    Text { text: "正常"; font.pixelSize: 11; font.bold: true; color: root.themeRoot.colOk }
                                }
                                // 仪表读数
                                Text {
                                    text: root.attLbl()
                                    font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2; font.family: "monospace"
                                }
                                // 地平仪
                                Canvas {
                                    id: aiCanvas
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        const W = width, H = height, cx = W/2, cy = H/2
                                        const R = Math.min(W, H)/2 - 10
                                        const online = root.fcOnline()
                                        const roll = online ? bridge.value("fc","roll") : 0
                                        const pitch = online ? bridge.value("fc","pitch") : 0
                                        // 外圈
                                        ctx.strokeStyle = root.themeRoot.colLine
                                        ctx.lineWidth = 3
                                        ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI*2); ctx.stroke()
                                        // 裁剪圆
                                        ctx.save()
                                        ctx.beginPath(); ctx.arc(cx, cy, R-2, 0, Math.PI*2); ctx.clip()
                                        // 天空/地面
                                        const rad = roll * Math.PI/180
                                        const pitchPx = (pitch / 30) * R * 0.7
                                        ctx.save()
                                        ctx.translate(cx, cy)
                                        ctx.rotate(rad)
                                        // 天空
                                        ctx.fillStyle = "#4a90d9"
                                        ctx.fillRect(-W, -H, W*2, H*2)
                                        // 地面
                                        ctx.fillStyle = "#b0894f"
                                        ctx.beginPath()
                                        ctx.moveTo(-W, 0); ctx.lineTo(-W, pitchPx); ctx.lineTo(W, pitchPx); ctx.lineTo(W, 0)
                                        ctx.closePath(); ctx.fill()
                                        // 俯仰格线
                                        ctx.strokeStyle = "rgba(255,255,255,0.85)"
                                        ctx.lineWidth = 1.6
                                        for (let a = -15; a <= 15; a += 5) {
                                            const yy = a/30*R*0.7
                                            ctx.beginPath(); ctx.moveTo(-W, yy); ctx.lineTo(W, yy); ctx.stroke()
                                        }
                                        ctx.restore()
                                        ctx.restore()
                                        // 机身十字 + 三角
                                        ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 2.5
                                        ctx.beginPath()
                                        ctx.moveTo(cx - R*0.35, cy); ctx.lineTo(cx - R*0.12, cy); ctx.stroke()
                                        ctx.beginPath()
                                        ctx.moveTo(cx + R*0.12, cy); ctx.lineTo(cx + R*0.35, cy); ctx.stroke()
                                        ctx.strokeStyle = "#ef4444"; ctx.lineWidth = 2.5
                                        ctx.beginPath()
                                        ctx.moveTo(cx, cy - R*0.15); ctx.lineTo(cx, cy); ctx.lineTo(cx - R*0.1, cy + R*0.12)
                                        ctx.moveTo(cx, cy); ctx.lineTo(cx + R*0.1, cy + R*0.12)
                                        ctx.stroke()
                                        ctx.fillStyle = "#ef4444"
                                        ctx.beginPath(); ctx.arc(cx, cy, 4, 0, Math.PI*2); ctx.fill()
                                        // 航向刻度（360/270/090）
                                        ctx.fillStyle = root.themeRoot.colText2
                                        ctx.font = "9px monospace"
                                        ctx.textAlign = "center"
                                        ctx.fillText("360", cx, 16)
                                        ctx.fillText("270", 24, cy+3)
                                        ctx.fillText("090", W-24, cy+3)
                                    }
                                    Connections { target: root.themeRoot; function onDataTickChanged() { aiCanvas.requestPaint() } }
                                }
                            }
                        }

                        // 电机状态卡（默认展开，占满左栏剩余）
                        Rectangle {
                            Layout.fillWidth: true
                            radius: 12
                            color: root.themeRoot.colCard
                            border.color: root.themeRoot.colLine
                            // 高度跟随内容（电机列表总高），否则 ScrollView 内 fillHeight 不生效
                            // 导致卡片塌陷、内容溢出边框（"没被白框包住"）
                            height: motCol.height
                            clip: true
                            Column {
                                id: motCol
                                width: parent.width
                                spacing: 0
                                // 折叠头
                                Rectangle {
                                    width: parent.width; height: 38
                                    color: "transparent"
                                    Row {
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                        spacing: 8
                                        Text { text: "⚙ 电机状态"; font.bold: true; font.pixelSize: 12; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "10 台 · 只读"; font.pixelSize: 10; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mfoldOpen = !root.mfoldOpen }
                                }
                                // 电机列表
                                Column {
                                    visible: root.mfoldOpen
                                    width: parent.width
                                    spacing: 0
                                    Repeater {
                                        model: root.motorGroups()
                                        Column {
                                            width: parent.width
                                            Rectangle {
                                                width: parent.width; height: 20; color: "transparent"
                                                Text { text: modelData.g; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 11; font.bold: true; color: root.themeRoot.colText2 }
                                            }
                                            Repeater {
                                                model: modelData.m
                                                Rectangle {
                                                    width: motCol.width; height: 30; color: "transparent"
                                                    Row {
                                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                                        spacing: 8
                                                        Text { text: modelData.n; width: 88; color: root.themeRoot.colText2; font.pixelSize: 11; font.weight: Font.DemiBold; verticalAlignment: Text.AlignVCenter }
                                                        Rectangle {
                                                            width: parent.width - 88 - 102 - 16; height: 6; anchors.verticalCenter: parent.verticalCenter
                                                            radius: 3; color: root.themeRoot.colCard2
                                                            Rectangle {
                                                                width: Math.max(2, Math.min(parent.width, parent.width * root.motorVal(modelData.i, modelData) / modelData.max))
                                                                height: 6; radius: 3
                                                                color: modelData.c
                                                            }
                                                        }
                                                        Text {
                                                            width: 102; text: root.fmt(Math.round(root.motorVal(modelData.i, modelData)),0) + " rpm   " + Math.round(root.motorTemp(modelData.i, modelData)) + "°C"
                                                            horizontalAlignment: Text.AlignRight; font.pixelSize: 11; font.family: "monospace"; font.bold: true
                                                            color: root.motorTemp(modelData.i, modelData) > 65 ? root.themeRoot.colWarn : root.themeRoot.colText
                                                            verticalAlignment: Text.AlignVCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- 右栏 fc-map：复用现有 MapView + 悬浮元素 ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                clip: true
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                Loader {
                    id: mapLoader
                    anchors.fill: parent
                    active: false
                    source: "qrc:/qml/views/MapView.qml"
                    onLoaded: {
                        item.themeRoot = root.themeRoot
                        item.restoreMapState()
                    }
                }
                // 比例尺 fc-scale（左下角 100m，对齐原型）
                Rectangle {
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    anchors.leftMargin: 16; anchors.bottomMargin: 20
                    width: 90; height: 4; radius: 2
                    color: "transparent"
                    border.color: "transparent"
                    Rectangle {
                        anchors.left: parent.left; anchors.bottom: parent.bottom
                        width: 86; height: 4; radius: 2
                        color: root.themeRoot.colText2
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 4; color: root.themeRoot.colText2
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 4; color: root.themeRoot.colText2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                        text: "100 m"; font.pixelSize: 10; font.weight: Font.DemiBold
                        color: root.themeRoot.colText2
                    }
                }
            }
        }
    }

    // ===== 电机模拟（本地演示数据，真实需机载扩展打包）=====
    property bool mfoldOpen: true
    property int gpsSat: 15
    // 电机 RPM/相位初始值（在 onCompleted 初始化，避免 model 绑定求值中写属性造成循环）
    property var motorArr: [380,362,375,388,1240,1205,1218,1255,1102,1160]
    property var motorPhase: [0,0,0,0,0,0,0,0,0,0]
    // 电机分组：推进4 + 上升4 + 下降2（复制原型 mot 数组），每项含全局下标 i
    // 注意：不依赖 mfoldTick（否则 model 每秒重建 + 与值刷新互相依赖产生绑定循环）；
    // 电机值/温度的刷新由 motorVal/motorTemp 各自依赖 mfoldTick 完成。
    function motorGroups() {
        const names = [
            {n:"推进 · 左前", max:1000, c:root.themeRoot.colPrimary},
            {n:"推进 · 左后", max:1000, c:root.themeRoot.colPrimary},
            {n:"推进 · 右后", max:1000, c:root.themeRoot.colPrimary},
            {n:"推进 · 右前", max:1000, c:root.themeRoot.colPrimary},
            {n:"上升 · 左前", max:2000, c:root.themeRoot.colOk},
            {n:"上升 · 左后", max:2000, c:root.themeRoot.colOk},
            {n:"上升 · 右后", max:2000, c:root.themeRoot.colOk},
            {n:"上升 · 右前", max:2000, c:root.themeRoot.colOk},
            {n:"前下降", max:2000, c:root.themeRoot.colOk},
            {n:"后下降", max:2000, c:root.themeRoot.colOk}
        ]
        const cells = names.map((x, i) => Object.assign({}, x, {i:i}))
        return [ {g:"推进电机", m:cells.slice(0,4)}, {g:"上升电机", m:cells.slice(4,8)}, {g:"下降电机", m:cells.slice(8,10)} ]
    }
    function motorVal(i, cell) {
        void root.mfoldTick
        return root.motorArr[i] !== undefined ? root.motorArr[i] : cell.max
    }
    function motorTemp(i, cell) {
        void root.mfoldTick
        return 40 + i*2.4 + (root.motorArr[i]!==undefined ? Math.round(root.motorArr[i]/100) : 0)
    }
    // 电机温度告警
    function anyHot() {
        void root.mfoldTick
        for (var i=0;i<10;i++){ if (root.motorTemp(i,{})>65) return true }
        return false
    }
    property int mfoldTick: 0
    // 地图右栏延后加载：等 main.qml 注入 themeRoot（本页 onLoaded 设置）后再启用，
    // 否则 MapView 首帧读取 themeRoot 为 null 报 TypeError
    Component.onCompleted: {
        // 随机电机相位（避免全部同步抖动）
        for (var i=0;i<10;i++) root.motorPhase[i] = Math.random()*6.28
        Qt.callLater(function(){ if (mapLoader) mapLoader.active = true })
    }
    // 电机抖动/转速模拟定时器
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            if (root.motorArr.length !== 10) return
            for (var i=0;i<10;i++){
                var phase = root.motorPhase[i] + 0.15
                root.motorPhase[i] = phase
                var base = [380,362,375,388,1240,1205,1218,1255,1102,1160][i]
                var tgt = base + Math.sin(phase)*2000*0.07
                root.motorArr[i] = Math.max(0, root.motorArr[i] + (tgt-root.motorArr[i])*0.2 + (Math.random()-0.5)*20)
            }
            root.gpsSat = 15 + (Math.random()<0.3?1:0)
            root.mfoldTick++
        }
    }
}
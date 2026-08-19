import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// 设置视图（复刻原型 #view-setup）：
// 串口配置 / 告警规则表 / 显示单位 / 界面与主题 / 监控模块可见性 / 状态栏微件
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)

    // 串口打开状态（带 dataTick 依赖：isSerialOpen 是 Q_INVOKABLE 方法调用，
    // QML 绑定只求值一次，须由 dataTick 触发重算，否则按钮文字/颜色不刷新）
    property bool serialIsOpen: { void root.themeRoot.dataTick; return bridge.isSerialOpen() }

    // 串口设备列表（bridge.ports() 是方法调用，QML 绑定只求值一次不自动刷新，
    // 故存为属性，由"刷新"按钮手动重新枚举）
    property var serialPorts: bridge.ports()
    function refreshPorts() {
        const cur = portCombo.editText
        root.serialPorts = bridge.ports()
        portCombo.editText = cur   // 刷新后恢复原选中/输入
        root.showNote(root.serialPorts.length ? "已刷新：检测到 " + root.serialPorts.length + " 个串口设备" : "未检测到串口设备")
    }

    // 告警规则（经 bridge CRUD，持久化到 ground_station.json）
    property var rules: bridge.alarmRules()
    // C++ 侧规则变化时自动刷新（增删/改不丢失）
    Connections {
        target: bridge
        function onRulesChanged() { root.rules = bridge.alarmRules() }
    }

    // ===== 表单控件样式（对齐 HTML 设置页：1px 线框 + 8px 圆角 + 卡片底色 + 等宽 + 主色 focus）=====
    // 下拉选择框（对齐 .set-row select）
    component CSetCombo: ComboBox {
        id: ctrl
        font.pixelSize: 13
        font.family: "monospace"
        implicitWidth: 110
        implicitHeight: 34
        leftPadding: 10
        rightPadding: 28
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            radius: 8
            color: root.themeRoot.colCard
            border.width: 1
            border.color: ctrl.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine
        }
        contentItem: Text {
            text: ctrl.displayText
            color: root.themeRoot.colText
            font: ctrl.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            color: root.themeRoot.colText2
            font.pixelSize: 11
        }
        popup: Popup {
            y: ctrl.height + 2
            width: ctrl.width
            padding: 4
            implicitHeight: contentItem.implicitHeight + 8
            background: Rectangle {
                radius: 8
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
            }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: ctrl.popup.visible ? ctrl.delegateModel : null
                currentIndex: ctrl.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator { }
            }
        }
        delegate: ItemDelegate {
            width: ctrl.popup.width - 8
            height: 30
            highlighted: ctrl.highlightedIndex === index
            contentItem: Text {
                text: modelData !== undefined ? String(modelData) : ""
                color: highlighted ? root.themeRoot.colPrimary : root.themeRoot.colText
                font: ctrl.font
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
            }
            background: Rectangle {
                radius: 6
                color: highlighted ? root.themeRoot.colPrimarySoft : "transparent"
            }
        }
    }
    // 输入框（对齐 .set-row input）
    component CSetField: TextField {
        id: ctrl
        font.pixelSize: 13
        font.family: "monospace"
        implicitHeight: 34
        leftPadding: 10
        rightPadding: 10
        color: root.themeRoot.colText
        placeholderTextColor: root.themeRoot.colText2
        selectByMouse: true
        background: Rectangle {
            radius: 8
            color: root.themeRoot.colCard
            border.width: 1
            border.color: ctrl.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine
        }
    }
    // 勾选按钮（对齐 checkbox：16×16 方框 + 主色对号）
    component CSetCheck: CheckBox {
        id: ctrl
        implicitWidth: 20
        implicitHeight: 20
        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
        scale: pressed ? 0.9 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        indicator: Rectangle {
            width: 18; height: 18
            radius: 5
            border.width: 1
            border.color: ctrl.checked ? root.themeRoot.colPrimary : root.themeRoot.colLine
            color: ctrl.checked ? root.themeRoot.colPrimary : "transparent"
            // 对号用 Canvas 精确居中绘制（Text "✓" 受字体基线影响会视觉偏移）
            Canvas {
                anchors.centerIn: parent
                width: 12; height: 12
                visible: ctrl.checked
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = "white"
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(2, 7); ctx.lineTo(5, 10); ctx.lineTo(10, 3)
                    ctx.stroke()
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: grid.implicitHeight
        clip: true
        // 响应式网格：宽屏 3 列（减小单模块宽度、减少右侧留白），窄屏递减；同列卡片等高
        GridLayout {
            id: grid
            width: parent.width
            columns: parent.width > 1300 ? 3 : (parent.width > 900 ? 2 : 1)
            columnSpacing: 12
            rowSpacing: 12

            // ===== 串口配置 =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 170
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "串口配置"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    RowLayout {
                        spacing: 8
                        Text { text: "串口设备"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        // 串口设备：editable 下拉，自定义闭合框样式（对齐 .set-row select）
                        ComboBox {
                            id: portCombo
                            editable: true
                            Layout.preferredWidth: 220
                            model: root.serialPorts
                            // 可编辑：既可从下拉选标准串口，也可手动输入虚拟串口路径
                            // （如 /tmp/gcs_pty2），便于本地模拟联调。
                            font.pixelSize: 13
                            font.family: "monospace"
                            implicitHeight: 34
                            leftPadding: 10
                            rightPadding: 28
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            background: Rectangle {
                                radius: 8
                                color: root.themeRoot.colCard
                                border.width: 1
                                border.color: portCombo.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine
                            }
                            indicator: Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▾"
                                color: root.themeRoot.colText2
                                font.pixelSize: 11
                            }
                            Component.onCompleted: Qt.callLater(function() {
                                // editable 下 contentItem 为 TextField，统一配色与字体
                                // （callLater：themeRoot 由 Loader.onLoaded 注入，须等注入后再取色）
                                if (contentItem) { contentItem.color = root.themeRoot.colText; contentItem.font = portCombo.font }
                                // 无配置时给平台默认串口（bridge.port() 按平台返回默认值），
                                // 便于首次使用直接点开串口，无需手动输入
                                if (portCombo.editText === "")
                                    portCombo.editText = bridge.port()
                            })
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_serial_refresh
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "刷新"
                            background: Rectangle {
                                radius: 8
                                color: root.themeRoot.colPrimarySoft
                                border.color: root.themeRoot.colPrimary
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.bold: true }
                            onClicked: root.refreshPorts()
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        spacing: 8
                        Text { text: "波特率"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        CSetCombo {
                            id: baudCombo
                            Layout.preferredWidth: 140
                            model: ["115200","57600","38400","9600"]
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_3
                                cursorShape: Qt.PointingHandCursor
                            }
                            // 用 root.serialIsOpen（带 dataTick 依赖）替代 bridge.isSerialOpen()
                            // 直接调用，确保按钮文字/颜色随串口状态实时刷新
                            text: root.serialIsOpen ? "关闭串口" : "打开串口"
                            background: Rectangle {
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                radius: 8
                                color: root.serialIsOpen ? root.themeRoot.colErrSoft : root.themeRoot.colPrimarySoft
                                border.color: root.serialIsOpen ? root.themeRoot.colErr : root.themeRoot.colPrimary
                            }
                            contentItem: Text {
                                text: parent.text
                                color: root.serialIsOpen ? root.themeRoot.colErr : root.themeRoot.colPrimary
                                font.bold: true
                            }
                            onClicked: {
                                if (root.serialIsOpen) {
                                    // 关闭串口二次确认
                                    confirmSerialOff.open()
                                } else {
                                    // editable 下允许手动输入任意路径，空则提示
                                    const port = portCombo.editText.trim()
                                    if (port === "") { root.showNote("未检测到串口设备"); return }
                                    const ok = bridge.openSerial(port, parseInt(baudCombo.currentText))
                                    root.showNote(ok ? "串口已打开：" + port : "串口打开失败：" + bridge.lastSerialError())
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Text { text: "遵循《地面站对接协议》115200 8N1，机载 5Hz 下传"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                    Item { Layout.fillHeight: true }
                }
            }

            // ===== 配置管理（导入/导出）=====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 170
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "配置管理"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    Text { text: "所有设置会在退出时自动保存、下次启动自动恢复。也可导出为配置文件，跨设备快速复用。"; font.pixelSize: 11; color: root.themeRoot.colText2; wrapMode: Text.Wrap }
                    RowLayout {
                        spacing: 8
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_4
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "导出配置"
                            background: Rectangle { radius: 8; color: root.themeRoot.colPrimarySoft; border.color: root.themeRoot.colPrimary }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.bold: true }
                            onClicked: {
                                exportCfgDlg.currentFile = "file://" + bridge.dataDir() + "/地面站配置.json"
                                exportCfgDlg.open()
                            }
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_5
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "导入配置"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_5.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.pixelSize: 12 }
                            onClicked: importCfgDlg.open()
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Text {
                        text: "当前配置：" + bridge.configFilePath()
                        font.pixelSize: 10; color: root.themeRoot.colText2
                        elide: Text.ElideMiddle; Layout.fillWidth: true; wrapMode: Text.NoWrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ===== 地图设置 =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 170
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "地图设置"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    RowLayout {
                        spacing: 8
                        Text { text: "底图源"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        CSetCombo {
                            id: mapSourceCombo
                            model: ["天地图", "OpenStreetMap"]
                            currentIndex: bridge.configMapSource()
                            onActivated: {
                                bridge.setConfigMapSource(index)
                                tileProvider.setMapSource(index)
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        spacing: 8
                        Text { text: "天地图Key"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        CSetField {
                            id: mapKeyField
                            Layout.fillWidth: true
                            text: bridge.configMapKey()
                            placeholderText: "申请天地图密钥后填写（选OSM可留空）"
                            onEditingFinished: {
                                bridge.setConfigMapKey(text.trim())
                                tileProvider.setMapKey(text.trim())
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Text {
                        text: bridge.configMapSource() === 0
                              ? (bridge.configMapKey().length ? "已启用天地图（需联网）" : "天地图需密钥，未填时地图可能无法加载")
                              : "已启用 OpenStreetMap（无需密钥，需联网）"
                        font.pixelSize: 11; color: root.themeRoot.colText2; wrapMode: Text.Wrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ===== 显示单位 =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 170
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "显示单位"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    RowLayout {
                        Text { text: "温度单位"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        CSetCombo {
                            id: tempUnitCombo
                            model: ["摄氏度 ℃", "华氏度 ℉"]
                            currentIndex: bridge.configTempUnit()
                            onActivated: bridge.setConfigTempUnit(index)
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        Text { text: "压力单位"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        CSetCombo {
                            id: pressUnitCombo
                            model: ["kPa", "Pa", "bar", "psi"]
                            currentIndex: bridge.configPressureUnit()
                            onActivated: bridge.setConfigPressureUnit(index)
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ===== 数据记录 =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 170
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "数据记录"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    Text { text: "打开串口后逐帧自动记录原始报文（断电不丢），重新打开串口记录新文件"; font.pixelSize: 11; color: root.themeRoot.colText2; wrapMode: Text.Wrap }
                    RowLayout {
                        spacing: 8
                        CSetCheck {
                            id: recordCb
                            checked: bridge.recordEnabled()
                            // 关闭时需二次确认；开启直接生效
                            onClicked: {
                                if (!checked && bridge.recordEnabled()) {
                                    checked = true                       // 回弹为未改变状态
                                    confirmRecordOff.open()
                                }
                            }
                            onToggled: {
                                if (checked && !bridge.recordEnabled())
                                    bridge.setRecordEnabled(true)
                            }
                        }
                        Text { text: "启用自动记录"; color: root.themeRoot.colText2; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: bridge.isRecording() ? "● 记录中：" + bridge.currentRecordFile() : "○ 未在记录"
                            font.pixelSize: 11; color: bridge.isRecording() ? root.themeRoot.colOk : root.themeRoot.colText2
                            Layout.maximumWidth: 200; wrapMode: Text.Wrap
                        }
                    }
                    RowLayout {
                        spacing: 8
                        Text { text: "保存目录"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                        CSetField {
                            id: recordDirField
                            Layout.fillWidth: true
                            text: bridge.recordDir()
                            placeholderText: "（留空 = 软件目录/data）"
                            onEditingFinished: bridge.setRecordDir(text.trim())
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_10
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "选择目录"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_10.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.pixelSize: 12 }
                            onClicked: {
                                folderDlg.currentFolder = recordDirField.text.length
                                    ? "file://" + recordDirField.text : "file://" + bridge.dataDir()
                                folderDlg.open()
                            }
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_11
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "恢复默认"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_11.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12 }
                            onClicked: { recordDirField.text = ""; bridge.setRecordDir("") }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 270
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                // 内容可滚动（模块高度不足时鼠标滚轮滑动查看，避免文字被裁剪）
                ScrollView {
                    anchors.fill: parent
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        width: parent.width - 32
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Item { height: 16 }   // 顶部留白（对齐原 margins 16）
                        Text { text: "界面与主题"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                        RowLayout {
                            Text { text: "主题"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                            CSetCombo {
                                model: ["浅色", "深色"]
                                currentIndex: root.themeRoot.dark ? 1 : 0
                                onActivated: root.themeRoot.dark = (index === 1)
                            }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Text { text: "字体大小"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                            CSetCombo {
                                model: ["字体大", "字体小"]
                                currentIndex: root.themeRoot.dense ? 1 : 0
                                onActivated: root.themeRoot.dense = (index === 1)
                            }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Text { text: "告警声音"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                            CSetCombo {
                                id: alarmSoundCombo
                                model: ["关闭", "开启"]
                                currentIndex: bridge.configAlarmSound() ? 1 : 0
                                onActivated: bridge.setConfigAlarmSound(index === 1)
                            }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Text { text: "高对比度"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                            CSetCombo {
                                model: ["关闭", "开启"]
                                currentIndex: root.themeRoot.contrast ? 1 : 0
                                onActivated: root.themeRoot.contrast = (index === 1)
                            }
                            Item { Layout.fillWidth: true }
                        }
                        RowLayout {
                            Text { text: "强调色"; color: root.themeRoot.colText2; font.pixelSize: 13; Layout.preferredWidth: 90 }
                            CSetCombo {
                                model: ["蓝色", "绿色", "橙色", "紫色", "青色"]
                                currentIndex: ["blue","green","orange","purple","teal"].indexOf(root.themeRoot.accent)
                                onActivated: root.themeRoot.accent = ["blue","green","orange","purple","teal"][index]
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text { text: "快捷键：1-6 切换视图 · 空格 暂停曲线 · T 主题 · D 密度"; font.pixelSize: 11; color: root.themeRoot.colText2; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        Item { height: 16 }   // 底部留白
                    }
                }
            }

            // ===== 状态栏微件 =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 180
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "状态栏微件"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    Text { text: "取消勾选可隐藏对应状态栏项，选择将持久化"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                    Flow {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 18
                        Repeater {
                            model: [["link","链路"],["rate","数据率"],["alarm","告警"],["uptime","运行时长"]]
                            Row {
                                spacing: 6
                                CSetCheck {
                                    checked: !root.themeRoot.isModuleHidden(modelData[0])
                                    onToggled: bridge.setConfigHiddenModule(modelData[0], !checked)
                                }
                                Text {
                                    text: modelData[1]; color: root.themeRoot.colText2; font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }

            // ===== 监控模块可见性（窄模块，并入第二行）=====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 180
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "监控模块可见性"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    Text { text: "取消勾选即可隐藏对应的监控模块，隐藏后数据仍在后台采集"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                    Flow {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 18
                        Repeater {
                            model: [
                                ["strip","飞艇横幅"],["power","电源总览"],
                                ["mppt_main","主囊 MPPT"],["mppt_sub","副囊 MPPT"],
                                ["bms","102S 主电源"],["backup","12S 备用电源"],
                                ["dcdc","DCDC 电源模块"],["lora","温度/压力采集"],
                                ["log","运行日志"],["statusbar","状态栏"]
                            ]
                            Row {
                                spacing: 6
                                CSetCheck {
                                    checked: !root.themeRoot.isModuleHidden(modelData[0])
                                    onToggled: bridge.setConfigHiddenModule(modelData[0], !checked)
                                }
                                Text {
                                    text: modelData[1]; color: root.themeRoot.colText2; font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }

            // ===== 告警规则（窄模块，并入第二行）=====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 320
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Text { text: "告警规则"; font.bold: true; color: root.themeRoot.colText; font.pixelSize: 14 }
                    Text { text: "规则在每帧遥测中自动求值，满足条件触发告警"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: root.themeRoot.colCard2
                        border.color: root.themeRoot.colLine
                        clip: true
                        ListView {
                            anchors.fill: parent; anchors.margins: 8
                            model: root.rules
                            spacing: 6
                            delegate: Rectangle {
                                width: ListView.view ? ListView.view.width : parent.width
                                height: 44
                                radius: 8
                                color: root.themeRoot.colCard
                                border.color: root.themeRoot.colLine
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    spacing: 10
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText
                                        Layout.preferredWidth: 180; elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.device + "." + modelData.field
                                        font.pixelSize: 11; color: root.themeRoot.colText2; font.family: "monospace"
                                    }
                                    Text {
                                        text: modelData.type === "threshold"
                                            ? (modelData.above ? ">" : "<") + " " + modelData.threshold
                                            : "≠ 0"
                                        font.pixelSize: 11; color: root.themeRoot.colText2
                                    }
                                    Text {
                                        text: ["提示","告警","严重"][modelData.level] || "提示"
                                        font.pixelSize: 11; font.bold: true
                                        color: modelData.level===2 ? root.themeRoot.colErr : (modelData.level===1 ? root.themeRoot.colWarn : root.themeRoot.colText2)
                                    }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                        scale: ma_1.pressed ? 0.96 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                        width: 34; height: 18; radius: 9
                                        color: modelData.enabled ? root.themeRoot.colOk : root.themeRoot.colOff
                                        Rectangle {
                                            width: 14; height: 14; radius: 7; color: "white"
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left; anchors.leftMargin: modelData.enabled ? 18 : 2
                                        }
                                        MouseArea {
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            id: ma_1
                                            anchors.fill: parent
                                            onClicked: root.toggleRule(index)
                                        }
                                    }
                                    Text {
                                        // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                        scale: ma_2.pressed ? 0.96 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                        text: "删除"
                                        font.pixelSize: 11; color: root.themeRoot.colErr
                                        MouseArea {
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            id: ma_2
                                            anchors.fill: parent
                                            onClicked: { bridge.removeAlarmRule(index); root.rules = bridge.alarmRules() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        spacing: 8
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_19
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "＋ 添加规则"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_19.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.pixelSize: 12 }
                            onClicked: root.addRule()
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_20
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "恢复默认"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_20.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12 }
                            onClicked: { bridge.restoreDefaultRules(); root.rules = bridge.alarmRules(); root.showNote("已恢复默认告警规则") }
                        }
                    }
                }
            }
        }
    }

    // 目录选择对话框（调用系统目录选择界面，与图示页导出快照的选择目录一致）
    FolderDialog {
        id: folderDlg
        title: "选择记录保存目录"
        onAccepted: {
            // selectedFolder 返回 file:///... 形式的 URL，须去前缀存真实路径，
            // 否则记录目录非法、且再次打开会拼出 file://file:/// 双重前缀
            const dir = selectedFolder.toString().replace(/^file:\/\//, "")
            recordDirField.text = dir
            bridge.setRecordDir(dir)
        }
    }

    // 导出配置文件（系统保存文件对话框）
    FileDialog {
        id: exportCfgDlg
        title: "导出配置"
        fileMode: FileDialog.SaveFile
        nameFilters: ["配置文件 (*.json)"]
        defaultSuffix: "json"
        onAccepted: {
            const ok = bridge.exportConfig(selectedFile.toString().replace(/^file:\/\//, ""))
            root.showNote(ok ? "配置已导出" : "导出配置失败")
        }
    }

    // 导入配置文件（系统打开文件对话框）
    FileDialog {
        id: importCfgDlg
        title: "导入配置"
        fileMode: FileDialog.OpenFile
        nameFilters: ["配置文件 (*.json)"]
        onAccepted: {
            const ok = bridge.importConfig(selectedFile.toString().replace(/^file:\/\//, ""))
            root.showNote(ok ? "配置已导入并应用" : "导入失败：文件无效或不可读")
        }
    }

    // 配置导入成功后刷新各设置控件（使新配置立即生效）
    Connections {
        target: bridge
        function onConfigImported() {
            root.rules = bridge.alarmRules()
            tempUnitCombo.currentIndex = bridge.configTempUnit()
            alarmSoundCombo.currentIndex = bridge.configAlarmSound() ? 1 : 0
            recordCb.checked = bridge.recordEnabled()
            recordDirField.text = bridge.recordDir()
            // 地图设置与串口设置一并恢复，避免导入后显示与实际不一致
            mapSourceCombo.currentIndex = bridge.configMapSource()
            mapKeyField.text = bridge.configMapKey()
            portCombo.currentIndex = Math.max(0, portCombo.find(bridge.port()))
            baudCombo.currentText = bridge.baud().toString()
        }
    }

    // 关闭串口的二次确认（自定义 Popup：样式与地面站主题一致，按钮行为明确）
    Popup {
        id: confirmSerialOff
        modal: true
        anchors.centerIn: parent
        width: 360
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: root.themeRoot.colCard; border.color: root.themeRoot.colLine; radius: 14 }
        contentItem: ColumnLayout {
            spacing: 12
            Text { text: "关闭串口"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
            Text {
                text: "确定关闭串口吗？关闭后数据将停止接收。"
                color: root.themeRoot.colText2; font.pixelSize: 13; wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 10
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_21
                        cursorShape: Qt.PointingHandCursor
                    }
                    text: "取消"
                    background: Rectangle {
                        radius: 8; color: root.themeRoot.colCard2; border.color: (hover_21.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 13 }
                    onClicked: confirmSerialOff.close()
                }
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_22
                        cursorShape: Qt.PointingHandCursor
                    }
                    text: "确定关闭"
                    background: Rectangle { radius: 8; color: root.themeRoot.colErrSoft; border.color: root.themeRoot.colErr }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colErr; font.pixelSize: 13; font.bold: true }
                    onClicked: {
                        bridge.closeSerial()
                        root.showNote("串口已关闭")
                        confirmSerialOff.close()
                    }
                }
            }
        }
    }

    // 关闭自动记录的二次确认（自定义 Popup，样式与主题一致）
    Popup {
        id: confirmRecordOff
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: root.themeRoot.colCard; border.color: root.themeRoot.colLine; radius: 14 }
        contentItem: ColumnLayout {
            spacing: 12
            Text { text: "关闭自动记录"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
            Text {
                text: "关闭后将不再自动记录遥测原始报文，已记录的文件保留。确定关闭吗？"
                color: root.themeRoot.colText2; font.pixelSize: 13; wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 10
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_23
                        cursorShape: Qt.PointingHandCursor
                    }
                    text: "取消"
                    background: Rectangle {
                        radius: 8; color: root.themeRoot.colCard2; border.color: (hover_23.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 13 }
                    onClicked: confirmRecordOff.close()
                }
                Button {
                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                    scale: pressed ? 0.94 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    HoverHandler {
                        id: hover_24
                        cursorShape: Qt.PointingHandCursor
                    }
                    text: "确定关闭"
                    background: Rectangle { radius: 8; color: root.themeRoot.colErrSoft; border.color: root.themeRoot.colErr }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colErr; font.pixelSize: 13; font.bold: true }
                    onClicked: {
                        bridge.setRecordEnabled(false)
                        recordCb.checked = false
                        root.showNote("已关闭自动记录")
                        confirmRecordOff.close()
                    }
                }
            }
        }
    }

    function addRule() {
        const fields = bridge.alarmRuleFields()
        const f = fields.length ? fields[0] : {key:"dcdc.temp", label:"DCDC 散热温度"}
        const [dev, fid] = f.key.split(".")
        bridge.addAlarmRule({
            device: dev, field: fid, label: f.label,
            type: "threshold", threshold: 45, above: true, enabled: true, level: 2
        })
        root.rules = bridge.alarmRules()
        root.showNote("已添加规则")
    }
    function toggleRule(i) {
        const r = root.rules[i]
        r.enabled = !r.enabled
        bridge.updateAlarmRule(i, r)
        root.rules = bridge.alarmRules()
    }
}

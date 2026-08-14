import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 摄像头监控（复刻原型 #view-camera）：
// 多路相机（前视/后视/吊舱/舱内）· 单路/双路/四路布局切换 · OSD 参数叠加 ·
// 截图 / 录像 / 重连 控制条。视频区域为深色渐变占位，接入网口流后实时显示。
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)

    // ===== 相机数据模型（与原型一一对应）=====
    property var cams: [
        {name:"前视相机", tag:"前视 · LIVE", online:true,  note:"前视相机 · 画面占位\n接入网口视频流后实时显示"},
        {name:"后视相机", tag:"后视 · LIVE", online:true,  note:"后视相机 · 画面占位"},
        {name:"吊舱相机", tag:"吊舱 · OFFLINE", online:false, note:"吊舱相机 · 未连接\n等待网口视频流"},
        {name:"舱内相机", tag:"舱内 · LIVE", online:true,  note:"舱内相机 · 画面占位"}
    ]
    property int curCam: 0        // 当前高亮相机
    property int layout: 1        // 1=单路 2=双路 4=四路
    property bool osdOn: true     // OSD 叠加开关
    property bool recOn: false    // 录像状态
    // 画面比例（对齐原型 camRatio）：16:9 / 4:3 / 1:1 / 填充，点击循环切换
    property var ratios: [["16:9","16:9"],["4:3","4:3"],["1:1","1:1"],["auto","填充"]]
    property int ratioIdx: 0      // 当前比例下标

    function toast(msg) { root.showNote(msg) }

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
                // 连接状态
                Rectangle {
                    Layout.preferredHeight: 22
                    implicitWidth: statLbl.implicitWidth + 22
                    radius: 11
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
                // 视频源信息
                Text {
                    text: "192.168.1.100 · RTSP · 25fps · 1080P"
                    font.pixelSize: 11; font.family: "monospace"; color: root.themeRoot.colText2
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "数传网口直连 · 与串口遥测独立并行"
                    font.pixelSize: 11; color: root.themeRoot.colText2
                }
            }
        }

        // ===== 多路相机切换 tab（.cam-tabs）=====
        Row {
            spacing: 6
            Repeater {
                model: root.cams
                Rectangle {
                    property bool isActive: index === root.curCam
                    id: tabItem
                    width: lbl.implicitWidth + 28
                    height: 30
                    radius: 8
                    color: isActive ? root.themeRoot.colPrimary : root.themeRoot.colCard
                    border.color: isActive ? root.themeRoot.colPrimary : root.themeRoot.colLine
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.online ? root.themeRoot.colOk : root.themeRoot.colErr
                        }
                        Text {
                            id: lbl
                            text: modelData.name
                            font.pixelSize: 12; font.weight: Font.DemiBold
                            color: isActive ? "#ffffff" : root.themeRoot.colText2
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.curCam = index
                            root.toast("已切换至 " + modelData.name)
                        }
                    }
                }
            }
        }

        // ===== 视频网格主体（.cam-stage 舞台容器 + 按比例 grid）=====
        Rectangle {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            // 舞台底色（对齐原型 .cam-stage background:var(--card-2)）
            color: root.themeRoot.colCard2
            border.color: root.themeRoot.colLine
            clip: true

            // 多路网格：网格本身按所选比例计算尺寸并居中（对齐原型 fitCam）
            GridLayout {
                id: grid
                // fillStage=true（比例=填充）时铺满舞台；否则在舞台内保持比例最大填充
                property bool fillStage: root.ratios[root.ratioIdx][0] === "auto"
                property real ratio: root.ratios[root.ratioIdx][0] === "16:9" ? 16/9
                                   : root.ratios[root.ratioIdx][0] === "4:3" ? 4/3 : 1
                width: fillStage ? parent.width : Math.min(parent.width, parent.height * ratio)
                height: fillStage ? parent.height : width / ratio
                anchors.centerIn: parent
                columns: root.layout === 1 ? 1 : 2
                rows: root.layout === 1 ? 1 : (root.layout === 2 ? 1 : 2)
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: root.cams
                    // 单路/双路时只显示前 N 路，四路全显
                    Item {
                        id: viewItem
                        property bool isActive: index === root.curCam
                        visible: root.layout === 4 ? true
                                : root.layout === 2 ? (index < 2)
                                : (index === root.curCam)
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // 视频块（圆角 + 边框 + 高亮）
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            // QML 中 Rectangle 的 clip 默认只按 Item 矩形裁剪，不遵守 radius。
                            // 打开 layer 后整项渲染到离屏 texture 再画出，配合下面的
                            // opacity mask 效果（或统一层后边框圆角自然生效）。
                            // 但更简单可靠的办法是：内部填满父项的 Rectangle 子项也显式
                            // 设置与外层相同的 radius（12px），保证视觉圆角一致。
                            clip: true
                            color: "black"
                            border.width: 1
                            border.color: isActive ? root.themeRoot.colPrimary : root.themeRoot.colLine
                            scale: isActive && root.layout !== 1 ? 1.01 : 1.0

                        // 视频画面占位（深色渐变模拟），radius 与外层一致（clip 不遵守圆角）
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#26334d" }
                                GradientStop { position: 0.55; color: "#0d1524" }
                                GradientStop { position: 1.0; color: "#060a12" }
                            }
                        }
                        // 相机轮廓 SVG
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
                        // 占位文字
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.note.split("\n")[0]
                                font.pixelSize: 13; font.weight: Font.DemiBold; color: "#8ba3c2"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: modelData.note.indexOf("\n") >= 0
                                text: modelData.note.split("\n")[1] || ""
                                font.pixelSize: 11; color: "#5f718d"
                            }
                        }

                        // 单路标签（左上角）
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 10
                            height: 22
                            implicitWidth: tagTxt.implicitWidth + 24
                            radius: 6
                            color: "transparent"
                            border.width: 0
                            Row {
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.online ? root.themeRoot.colOk : root.themeRoot.colErr
                                }
                                Text {
                                    id: tagTxt
                                    text: modelData.tag
                                    font.pixelSize: 11; font.weight: Font.Bold; color: "#ffffff"
                                }
                            }
                        }

                        // OSD 参数叠加（右下角）
                        Rectangle {
                            visible: root.osdOn
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 10
                            width: osdCol.implicitWidth + 20
                            height: osdCol.implicitHeight + 12
                            radius: 6
                            color: Qt.rgba(0,0,0,0.45)
                            Column {
                                id: osdCol
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: "2026-08-14 10:23:45"; font.pixelSize: 11; font.family: "monospace"; color: "#ffffff"; font.weight: Font.Bold }
                                Text {
                                    text: modelData.online
                                          ? (index === 3 ? "TEMP 32.4°C    PRES 101.3kPa"
                                                        : "LAT 30.26715°N    LON 120.15342°E")
                                          : "信号丢失 · 重连中…"
                                    font.pixelSize: 11; font.family: "monospace"
                                    color: modelData.online ? "#cfe0ff" : "#ff9f9f"
                                }
                                Text {
                                    visible: modelData.online && index !== 3
                                    text: "ALT 150.2m    SPD 12.5m/s    HDG 087°"
                                    font.pixelSize: 11; font.family: "monospace"; color: "#cfe0ff"
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

                // 截图
                Button {
                    text: "📷 截图"
                    Layout.preferredHeight: 32
                    background: Rectangle { radius: 8; color: root.themeRoot.colCard2; border.color: root.themeRoot.colLine }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText; font.pixelSize: 12; font.weight: Font.DemiBold }
                    onClicked: root.toast("已保存截图 snapshot_" + Date.now() + ".png")
                }
                // 录像
                Button {
                    text: root.recOn ? "⬛ 停止录像" : "⏺ 录像"
                    Layout.preferredHeight: 32
                    background: Rectangle {
                        radius: 8
                        color: root.recOn ? root.themeRoot.colErr : root.themeRoot.colCard2
                        border.color: root.recOn ? root.themeRoot.colErr : root.themeRoot.colLine
                    }
                    contentItem: Text {
                        text: parent.text; color: root.recOn ? "#ffffff" : root.themeRoot.colText
                        font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    onClicked: {
                        root.recOn = !root.recOn
                        root.toast(root.recOn ? "开始录像（保存至本地）" : "录像已停止")
                    }
                }
                // OSD 叠加
                Button {
                    text: root.osdOn ? "≡ OSD 叠加" : "≡ OSD 叠加"
                    Layout.preferredHeight: 32
                    background: Rectangle {
                        radius: 8
                        color: root.osdOn ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                        border.color: root.osdOn ? root.themeRoot.colPrimary : root.themeRoot.colLine
                    }
                    contentItem: Text {
                        text: parent.text; color: root.osdOn ? "#ffffff" : root.themeRoot.colText
                        font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    onClicked: {
                        root.osdOn = !root.osdOn
                        root.toast(root.osdOn ? "OSD 叠加已开启" : "OSD 叠加已关闭")
                    }
                }
                // 画面比例切换（对齐原型 camRatio：16:9 / 4:3 / 1:1 / 填充 循环）
                Button {
                    text: "比例 " + root.ratios[root.ratioIdx][1]
                    Layout.preferredHeight: 32
                    background: Rectangle { radius: 8; color: root.themeRoot.colCard2; border.color: root.themeRoot.colLine }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText; font.pixelSize: 12; font.weight: Font.DemiBold }
                    onClicked: {
                        root.ratioIdx = (root.ratioIdx + 1) % root.ratios.length
                        root.toast("画面比例：" + root.ratios[root.ratioIdx][1])
                    }
                }
                // 分隔线
                Rectangle { width: 1; height: 20; color: root.themeRoot.colLine }
                // 重连
                Button {
                    text: "↻ 重连"
                    Layout.preferredHeight: 32
                    background: Rectangle { radius: 8; color: root.themeRoot.colCard2; border.color: root.themeRoot.colLine }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colText; font.pixelSize: 12; font.weight: Font.DemiBold }
                    onClicked: root.toast("正在重连网口视频流…")
                }
                Rectangle { width: 1; height: 20; color: root.themeRoot.colLine }
                Text {
                    text: "截图/录像保存至本地 · 视频数据来自数传网口"
                    font.pixelSize: 11; color: root.themeRoot.colText2
                }
                Item { Layout.fillWidth: true }

                // 布局切换（单路/双路/四路，对齐原型 .lay-btn）
                Row {
                    spacing: 4
                    Repeater {
                        model: [1, 2, 4]
                        Rectangle {
                            property bool isLayActive: root.layout === modelData
                            width: 26; height: 26; radius: 6
                            color: isLayActive ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                            border.color: isLayActive ? root.themeRoot.colPrimary : root.themeRoot.colLine
                            // 点点图标：四路呈田字 2×2（对齐原型 .lay-btn[data-lay="4"]），
                            // 单路 1 点居中、双路 2 点横排
                            Grid {
                                anchors.centerIn: parent
                                columns: modelData === 4 ? 2 : modelData
                                rows: modelData === 4 ? 2 : 1
                                spacing: 2
                                Repeater {
                                    model: modelData
                                    Rectangle {
                                        width: 5; height: 5; radius: 1
                                        color: isLayActive ? "#ffffff" : root.themeRoot.colText2
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.layout = modelData
                            }
                        }
                    }
                }
            }
        }
    }
}

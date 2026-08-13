import QtQuick

// 飞控视图（占位，决策 #2 本期占位）：骨架预览卡片
Item {
    id: root
    property QtObject themeRoot: null

    Column {
        anchors.fill: parent
        spacing: 12

        // 标题
        Rectangle {
            width: parent.width
            height: 52
            radius: 12
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            Row {
                anchors.fill: parent; anchors.margins: 16
                spacing: 10
                Text { text: "飞控视图（预留）"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                Text {
                    text: "规划中"; font.pixelSize: 11; font.bold: true; color: root.themeRoot.colWarn
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // 骨架卡片网格
        Grid {
            columns: root.width > 900 ? 2 : 1
            columnSpacing: 12; rowSpacing: 12
            width: parent.width
            Repeater {
                model: [
                    {ic:"◎", tip:"姿态仪表", sub:"横滚 / 俯仰 / 偏航"},
                    {ic:"➤", tip:"位置与航迹", sub:"GPS / 速度 / 航向"},
                    {ic:"∿", tip:"飞行模式", sub:"手动 / 定高 / 任务"},
                    {ic:"▣", tip:"HUD 视频流", sub:"机载相机实时画面"}
                ]
                Rectangle {
                    width: 420; height: 160; radius: 12
                    color: root.themeRoot.colCard
                    border.color: root.themeRoot.colLine
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: modelData.ic; font.pixelSize: 30; color: root.themeRoot.colText2; opacity: 0.5; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: modelData.tip; font.pixelSize: 13; font.weight: Font.DemiBold; color: root.themeRoot.colText; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { text: modelData.sub; font.pixelSize: 11; color: root.themeRoot.colText2; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// 自检视图（复刻原型 #view-check）：起飞前 12 项自检 + 就绪度聚合 + 重新自检
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)

    function fmt(v, dp) { return isNaN(v) ? "--" : Number(v).toFixed(dp); }
    function pass(dev, key, lo, hi) {
        if (!bridge.online(dev)) return false
        const v = bridge.value(dev, key)
        return v > lo && v < hi
    }
    function checks() {
        void root.themeRoot.dataTick
        const list = []
        list.push(root.item("BMS","链路在线", bridge.online("bms"), "在线"))
        list.push(root.item("BMS","总压正常 (360–380V)", root.pass("bms","pack_v",360,380),
            root.fmt(bridge.value("bms","pack_v"),1)+"V"))
        list.push(root.item("BMS","SOC 充足 (>30%)", bridge.online("bms") ? bridge.value("bms","soc") > 30 : false,
            root.fmt(bridge.value("bms","soc"),0)+"%"))
        list.push(root.item("BMS","最高温度 <50℃", bridge.online("bms") ? bridge.value("bms","max_t") < 50 : false,
            root.fmt(bridge.value("bms","max_t"),1)+"℃"))
        list.push(root.item("BMS","单体压差 <0.05V", bridge.online("bms") ? bridge.value("bms","diff_v") < 0.05 : false,
            root.fmt(bridge.value("bms","diff_v"),2)+"V"))
        list.push(root.item("备用","链路在线", bridge.online("backup"), "在线"))
        list.push(root.item("MPPT","链路在线", bridge.online("mppt"), "在线"))
        list.push(root.item("MPPT","光伏电压 20–120V", root.pass("mppt","pv_v",20,120),
            root.fmt(bridge.value("mppt","pv_v"),1)+"V"))
        list.push(root.item("MPPT","充电电流 >0A", bridge.online("mppt") ? bridge.value("mppt","charge_i") > 0 : false,
            root.fmt(bridge.value("mppt","charge_i"),1)+"A"))
        list.push(root.item("DCDC","链路在线", bridge.online("dcdc"), "在线"))
        list.push(root.item("DCDC","输出电压 40–60V", root.pass("dcdc","out_v",40,60),
            root.fmt(bridge.value("dcdc","out_v"),1)+"V"))
        list.push(root.item("DCDC","散热温度 <45℃", bridge.online("dcdc") ? bridge.value("dcdc","temp") < 45 : false,
            root.fmt(bridge.value("dcdc","temp"),1)+"℃"))
        return list
    }
    function item(dev, name, ok, val) { return {dev:dev, name:name, ok:ok, val:val} }

    function allPass() {
        const c = root.checks()
        return c.every(x=>x.ok)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // 标题 + 就绪度
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            radius: 14
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            RowLayout {
                anchors.fill: parent; anchors.margins: 18
                Text { text: "系统自检 · 起飞前检查"; font.bold: true; font.pixelSize: 16; color: root.themeRoot.colText }
                Item { Layout.fillWidth: true }
                Rectangle {
                    radius: 12; height: 34
                    implicitWidth: stateLabel.implicitWidth + 26
                    color: root.allPass() ? root.themeRoot.colOk : root.themeRoot.colErr
                    Text {
                        id: stateLabel; anchors.centerIn: parent; color: "white"; font.bold: true; font.pixelSize: 13
                        text: root.allPass() ? "全部通过" : "有项未通过"
                    }
                }
                Button {
                    text: "重新自检"
                    background: Rectangle { radius: 10; color: root.themeRoot.colPrimarySoft; border.color: root.themeRoot.colPrimary }
                    contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.bold: true }
                    onClicked: {
                        root.themeRoot.dataTick++   // 强制重算一次自检结果
                        root.showNote("自检完成")
                    }
                }
            }
        }

        // 自检列表
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            ListView {
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                spacing: 6
                model: root.checks()
                delegate: Rectangle {
                    width: parent.width
                    height: 46
                    radius: 10
                    color: modelData.ok ? root.themeRoot.colCard2 : root.themeRoot.colErrSoft
                    border.color: modelData.ok ? "transparent" : root.themeRoot.colErr
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 14
                        spacing: 12
                        // 状态圆
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: modelData.ok ? root.themeRoot.colOk : root.themeRoot.colErr
                            Text { anchors.centerIn: parent; text: modelData.ok ? "✓" : "✗"; color: "white"; font.bold: true; font.pixelSize: 13 }
                        }
                        Text { text: modelData.dev; font.pixelSize: 11; font.bold: true; color: root.themeRoot.colText2; width: 48 }
                        Text { text: modelData.name; font.pixelSize: 13; font.weight: Font.DemiBold; color: modelData.ok ? root.themeRoot.colText : root.themeRoot.colErr }
                        Item { Layout.fillWidth: true }
                        Text { text: modelData.val; font.pixelSize: 13; font.family: "monospace"; color: root.themeRoot.colText2 }
                    }
                }
            }
        }
    }
}

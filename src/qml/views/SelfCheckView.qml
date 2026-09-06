import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// 自检视图（1:1 复刻原型 #view-check + 自检 JS L1835-1995）：
// 11 项预置 + 自定义项动态增删 + 三态判定（pass/fail/skip）+ 参数编辑弹窗 + 持久化，
// 引擎为 C++ CheckEngine（context property "checkEngine"），10s 周期重跑在 main.qml 全局 Timer。
// 视觉逐条对齐原型 CSS：.check-panel 单一大卡（圆角 14）包 head(card-2 底)+list；
// 胶囊与按钮组靠右（result margin-left:auto）；.btn=主色底白字 / .btn.ghost=透明底描边；
// 弹窗 .modal 420 卡底圆角 14 + .modal-head(14×18 下边框) + .modal-body(18) +
// .set-group(card-2 圆角 12) 内 .set-row(虚线分隔 label 左控件右 170px 等宽输入)。
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)

    // ===== 编辑弹窗状态 =====
    property string editId: ""          // "" = 新增；否则内置/自定义项 id
    property var editDef: ({})          // 进入弹窗时的条目快照（校验失败回显不丢）
    property string editMode: "single"  // 弹窗内检查方式（联动显隐）

    readonly property bool isNew: editId === ""
    readonly property bool editIsCustom: isNew ? true : (editDef.custom === true)
    property string dlgTitle: ""        // 弹窗标题（不能用 Dialog.title：原生模板会额外画一个标题）

    // ===== 设备/字段可选字典（对用户屏蔽内部协议键：设备下拉固定取值，fid 随设备联动）=====
    // dev 存储值经 CheckEngine::devKeyOf 映射为 bridge 设备键（小写/中文映射）
    readonly property var devModelBase: [
        { label: "BMS", dev: "BMS" },
        { label: "MPPT 1", dev: "MPPT1" },
        { label: "MPPT 2", dev: "MPPT2" },
        { label: "DCDC", dev: "DCDC" },
        { label: "备用电源", dev: "备用电源" },
        { label: "飞控", dev: "飞控" }
    ]
    property var devModel: devModelBase.slice()   // 动态副本：回显历史自定义项的未知 dev 时临时追加
    // fid 字典：label 用户可读名（含 fid），v=存储 fid，u=默认单位（选中自动带出，可改）
    readonly property var fidDict: ({
        "BMS": [
            { label: "总压 (pack_v)", v: "pack_v", u: "V" },
            { label: "电流 (pack_i)", v: "pack_i", u: "A" },
            { label: "SOC (soc)", v: "soc", u: "%" },
            { label: "剩余电量 (rsoc)", v: "rsoc", u: "%" },
            { label: "SOH (soh)", v: "soh", u: "%" },
            { label: "最高单体电压 (max_v)", v: "max_v", u: "V" },
            { label: "最低单体电压 (min_v)", v: "min_v", u: "V" },
            { label: "单体压差 (diff_v)", v: "diff_v", u: "V" },
            { label: "最高温度 (max_t)", v: "max_t", u: "℃" },
            { label: "最低温度 (min_t)", v: "min_t", u: "℃" },
            { label: "平均温度 (avg_t)", v: "avg_t", u: "℃" },
            { label: "单体温差 (diff_t)", v: "diff_t", u: "℃" },
            { label: "正极对地电阻 (riso_p)", v: "riso_p", u: "" },
            { label: "负极对地电阻 (riso_n)", v: "riso_n", u: "" },
            { label: "告警码 (alarm)", v: "alarm", u: "" },
            { label: "故障码1 (fault1)", v: "fault1", u: "" },
            { label: "故障码2 (fault2)", v: "fault2", u: "" },
            { label: "故障码3 (fault3)", v: "fault3", u: "" }
        ],
        "MPPT1": [
            { label: "光伏电压 (pv_v)", v: "pv_v", u: "V" },
            { label: "光伏功率 (pv_p)", v: "pv_p", u: "W" },
            { label: "电池电压 (batt_v)", v: "batt_v", u: "V" },
            { label: "充电电流 (charge_i)", v: "charge_i", u: "A" },
            { label: "环境温度 (air_t)", v: "air_t", u: "℃" },
            { label: "组件温度 (mod_t)", v: "mod_t", u: "℃" },
            { label: "今日发电 (today)", v: "today", u: "" },
            { label: "本月发电 (month)", v: "month", u: "" },
            { label: "累计发电 (total)", v: "total", u: "" },
            { label: "额定电压 (rated_v)", v: "rated_v", u: "V" },
            { label: "额定电流 (rated_i)", v: "rated_i", u: "A" },
            { label: "状态码 (cs)", v: "cs", u: "" },
            { label: "工作模式 (mode)", v: "mode", u: "" },
            { label: "充电使能 (chg_on)", v: "chg_on", u: "" },
            { label: "故障码 (fault)", v: "fault", u: "" }
        ],
        "MPPT2": [
            { label: "光伏电压 (pv_v)", v: "pv_v", u: "V" },
            { label: "光伏功率 (pv_p)", v: "pv_p", u: "W" },
            { label: "电池电压 (batt_v)", v: "batt_v", u: "V" },
            { label: "充电电流 (charge_i)", v: "charge_i", u: "A" },
            { label: "环境温度 (air_t)", v: "air_t", u: "℃" },
            { label: "组件温度 (mod_t)", v: "mod_t", u: "℃" },
            { label: "今日发电 (today)", v: "today", u: "" },
            { label: "本月发电 (month)", v: "month", u: "" },
            { label: "累计发电 (total)", v: "total", u: "" },
            { label: "额定电压 (rated_v)", v: "rated_v", u: "V" },
            { label: "额定电流 (rated_i)", v: "rated_i", u: "A" },
            { label: "状态码 (cs)", v: "cs", u: "" },
            { label: "工作模式 (mode)", v: "mode", u: "" },
            { label: "充电使能 (chg_on)", v: "chg_on", u: "" },
            { label: "故障码 (fault)", v: "fault", u: "" }
        ],
        "DCDC": [
            { label: "输入电压 (in_v)", v: "in_v", u: "V" },
            { label: "输出电压 (out_v)", v: "out_v", u: "V" },
            { label: "输出电流 (out_i)", v: "out_i", u: "A" },
            { label: "输出功率 (out_p)", v: "out_p", u: "W" },
            { label: "温度 (temp)", v: "temp", u: "℃" },
            { label: "故障码 (fault)", v: "fault", u: "" },
            { label: "输出使能 (enabled)", v: "enabled", u: "" }
        ],
        "备用电源": [
            { label: "总压 (pack_v)", v: "pack_v", u: "V" },
            { label: "电流 (pack_i)", v: "pack_i", u: "A" },
            { label: "SOC (soc)", v: "soc", u: "%" },
            { label: "SOH (soh)", v: "soh", u: "%" },
            { label: "最高单体电压 (max_v)", v: "max_v", u: "V" },
            { label: "最低单体电压 (min_v)", v: "min_v", u: "V" },
            { label: "单体压差 (diff_v)", v: "diff_v", u: "V" },
            { label: "最高温度 (max_t)", v: "max_t", u: "℃" },
            { label: "最低温度 (min_t)", v: "min_t", u: "℃" },
            { label: "平均温度 (avg_t)", v: "avg_t", u: "℃" },
            { label: "单体温差 (diff_t)", v: "diff_t", u: "℃" },
            { label: "告警码 (alarm)", v: "alarm", u: "" },
            { label: "故障码 (fault)", v: "fault", u: "" },
            { label: "系统状态 (sys)", v: "sys", u: "" }
        ],
        "飞控": [
            { label: "横滚 (roll)", v: "roll", u: "°" },
            { label: "俯仰 (pitch)", v: "pitch", u: "°" },
            { label: "航向 (yaw)", v: "yaw", u: "°" },
            { label: "高度 (alt)", v: "alt", u: "m" },
            { label: "爬升率 (climb)", v: "climb", u: "m/s" },
            { label: "空速 (airspd)", v: "airspd", u: "m/s" },
            { label: "真空速 (tas)", v: "tas", u: "m/s" },
            { label: "地速 (gs)", v: "gs", u: "m/s" },
            { label: "油门 (thr)", v: "thr", u: "%" },
            { label: "电池电压 (batt_v)", v: "batt_v", u: "V" },
            { label: "电池电量 (batt_pct)", v: "batt_pct", u: "%" },
            { label: "GPS 定位状态 (gps_fix)", v: "gps_fix", u: "" },
            { label: "GPS 卫星数 (gps_sat)", v: "gps_sat", u: "" },
            { label: "GPS 水平精度 (gps_eph)", v: "gps_eph", u: "" },
            { label: "GPS 垂直精度 (gps_epv)", v: "gps_epv", u: "" },
            { label: "EKF 位置 (ekf_pos)", v: "ekf_pos", u: "" },
            { label: "EKF 毛刺 (ekf_glitch)", v: "ekf_glitch", u: "" },
            { label: "EKF 加速度误差 (ekf_accel_err)", v: "ekf_accel_err", u: "" },
            { label: "解锁状态 (armed)", v: "armed", u: "" }
        ]
    })
    property var fidModel: fidDict["BMS"].slice()   // 当前设备的字段选项（随设备联动重建）

    // 当前选中字段的默认单位（单位完全由字段决定，无需用户选择）
    readonly property string curUnit: (fidCombo.currentIndex >= 0 && fidModel[fidCombo.currentIndex])
                                      ? fidModel[fidCombo.currentIndex].u : ""

    // 切换设备：重建字段下拉（单位经 curUnit 绑定自动跟随）
    function onDevActivated(index) {
        const dev = devModel[index] ? devModel[index].dev : ""
        fidModel = (root.fidDict[dev] || []).slice()
        fidCombo.currentIndex = fidModel.length ? 0 : -1
    }

    Component.onCompleted: checkEngine.runAll()   // 进页先跑一轮（引擎全局单例亦在 main.qml 10s 周期跑）

    // 打开编辑弹窗（def 空缺字段用原型 ckAdd 的默认值）
    function openEditor(def) {
        editDef = def
        editId = def.id || ""
        editMode = def.mode || "single"
        dlgTitle = isNew ? "新增自检项" : "自检参数 · " + editDef.dev + " " + editDef.name
        editDlg.open()
    }

    // 保存（校验规则与提示文案逐字对齐原型 ckSave L1947-1978）
    function saveEdit() {
        const m = editMode
        if (m === "single") {
            const s = valInput.text.trim()
            const v = s === "" ? null : parseFloat(s)
            if (v === null || isNaN(v)) {
                root.themeRoot.showToast("请输入有效的阈值数值", "err"); valInput.focus(); return
            }
        } else if (m === "range") {
            const mnS = minInput.text.trim(), mxS = maxInput.text.trim()
            const mn = mnS === "" ? null : parseFloat(mnS)
            const mx = mxS === "" ? null : parseFloat(mxS)
            if (mn === null || isNaN(mn) || mx === null || isNaN(mx)) {
                root.themeRoot.showToast("请输入有效的下限和上限", "err"); return
            }
            if (mn >= mx) {
                root.themeRoot.showToast("下限必须小于上限", "err"); return
            }
        }
        let patch = { en: enChk.checked, mode: m, cmp: cmpCombo.currentValue }
        if (m === "single") patch.val = parseFloat(valInput.text)          // 隐藏字段保持原值不污染
        else if (m === "range") { patch.min = parseFloat(minInput.text); patch.max = parseFloat(maxInput.text) }
        if (editIsCustom) {
            const name = nameInput.text.trim(), dev = devCombo.currentValue || "", fid = fidCombo.currentValue || ""
            if (!name) { root.themeRoot.showToast("请输入项目名称", "err"); nameInput.focus(); return }
            if (!dev)  { root.themeRoot.showToast("请选择设备", "err"); return }
            if (m !== "none" && !fid) { root.themeRoot.showToast("请选择数据字段", "err"); return }
            patch.name = name; patch.dev = dev; patch.fid = fid
            patch.unit = m !== "none" ? root.curUnit : ""   // 单位由字段唯一决定，无需用户选择
        }
        const isNewRec = root.isNew
        if (isNewRec) checkEngine.addItem(patch)
        else checkEngine.setItem(editId, patch)
        editDlg.close()
        root.themeRoot.showToast(isNewRec ? "自检项已添加" : "自检参数已保存")
    }

    // ===== .check-panel 单一大卡片（card 底 + line 边框 + 圆角 14 + clip）=====
    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.themeRoot.colCard
        border.color: root.themeRoot.colLine
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ===== .check-head（card-2 底 + 下边框 + padding 14 18，元素 gap 14）=====
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: root.themeRoot.colCard2
                Rectangle {   // 下边框（原型 border-bottom:1px solid var(--line)）
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 1; color: root.themeRoot.colLine
                }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18
                    spacing: 14
                    Text { text: "系统自检 · 起飞前检查"; font.weight: Font.Bold; font.pixelSize: 16; color: root.themeRoot.colText }
                    Item { Layout.fillWidth: true }   // result 的 margin-left:auto：胶囊与按钮组整体靠右
                    // 结果胶囊（.result：padding 5px 14px 全圆角 15/700；未自检无色）
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        radius: 999
                        implicitWidth: resultLabel.implicitWidth + 28
                        implicitHeight: resultLabel.implicitHeight + 10
                        color: !checkEngine.checkedOnce ? "transparent"
                             : checkEngine.failCount === 0 ? root.themeRoot.colOkSoft : root.themeRoot.colErrSoft
                        border.color: !checkEngine.checkedOnce ? root.themeRoot.colLine : "transparent"
                        Text {
                            id: resultLabel; anchors.centerIn: parent
                            font.weight: Font.Bold; font.pixelSize: root.themeRoot.fsTitle
                            color: checkEngine.failCount === 0 ? root.themeRoot.colOk : root.themeRoot.colErr
                            text: !checkEngine.checkedOnce ? "未自检"
                                 : checkEngine.failCount === 0 ? "全部通过" : "有项未通过"
                        }
                    }
                    // ＋新增自检项（.btn.ghost：透明底 + text-2 字 + line 边框，圆角 10 padding 8 16）
                    Rectangle {
                        id: ckAdd
                        readonly property bool hov: ckAddMa.hovered
                        radius: 10
                        implicitWidth: ckAddLbl.implicitWidth + 32
                        implicitHeight: ckAddLbl.implicitHeight + 16
                        color: "transparent"
                        border.width: 1
                        border.color: hov ? root.themeRoot.colPrimary : root.themeRoot.colLine
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Text { id: ckAddLbl; anchors.centerIn: parent; text: "＋ 新增自检项"; color: root.themeRoot.colText2; font.pixelSize: root.themeRoot.fsBody; font.weight: Font.DemiBold }
                        HoverHandler { id: ckAddMa; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.openEditor({id:"",custom:true,en:true,mode:"single",cmp:"gt",val:0,min:0,max:100,name:"",dev:"",fid:"",unit:""}) }
                    }
                    // 重新自检（.btn：primary 底白字，hover 提亮 1.08）
                    Rectangle {
                        id: recheck
                        readonly property bool hov: recheckMa.hovered
                        radius: 10
                        implicitWidth: recheckLbl.implicitWidth + 32
                        implicitHeight: recheckLbl.implicitHeight + 16
                        color: hov ? Qt.lighter(root.themeRoot.colPrimary, 1.08) : root.themeRoot.colPrimary
                        Text { id: recheckLbl; anchors.centerIn: parent; text: "重新自检"; color: "white"; font.pixelSize: root.themeRoot.fsBody; font.weight: Font.DemiBold }
                        HoverHandler { id: recheckMa; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                checkEngine.runAll()
                                // 手动自检结果记入运行日志（与 main.qml 周期自检的 _lastCheckFails 对齐，避免重复记）
                                root.themeRoot.addLog("info", checkEngine.failCount === 0
                                                      ? "整机自检：全部通过"
                                                      : "整机自检：" + checkEngine.failCount + " 项未通过")
                                root.themeRoot._lastCheckFails = checkEngine.failCount
                            }
                        }
                    }
                }
            }

            // ===== .check-list（padding 14 18，gap 10，滚动）=====
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: listCol.implicitHeight
                ScrollBar.vertical: ScrollBar { }
                ColumnLayout {
                    id: listCol
                    width: parent.width
                    spacing: 10
                    Item { Layout.preferredHeight: 14; Layout.fillWidth: true }   // 上 padding 14
                    Repeater {
                        model: checkEngine.items
                        delegate: Rectangle {
                            required property var modelData
                            readonly property string st: modelData.st || "skip"
                            readonly property bool isSkip: st === "skip"
                            readonly property bool isFail: st === "fail"
                            Layout.fillWidth: true
                            Layout.leftMargin: 18; Layout.rightMargin: 18   // .check-list padding 14px 18px 的左右留白
                            height: 50   // padding 12×2 + 行内最高元素（齿轮按钮 26）
                            radius: 10
                            color: isFail ? root.themeRoot.colErrSoft : root.themeRoot.colCard2
                            border.width: 1
                            border.color: isFail ? root.themeRoot.colErr : root.themeRoot.colLine
                            opacity: isSkip ? 0.72 : 1.0
                            HoverHandler { id: itemMa; cursorShape: Qt.ArrowCursor }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 12
                                // 状态圈 .st（22×22 圆，13/700）
                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: isSkip ? root.themeRoot.colBg2 : (isFail ? root.themeRoot.colErr : root.themeRoot.colOk)
                                    Text { anchors.centerIn: parent; font.weight: Font.Bold; font.pixelSize: root.themeRoot.fsBody; color: isSkip ? root.themeRoot.colText2 : "white"
                                           text: isSkip ? "–" : (isFail ? "✗" : "✓") }
                                }
                                // 设备名 .ci-dev（11/700 text-2 宽 48）
                                Text { text: modelData.dev; font.pixelSize: root.themeRoot.fsCaption; font.weight: Font.Bold; color: root.themeRoot.colText2; Layout.preferredWidth: 48 }
                                // 项目名 .ci-name（flex:1 600，撑满剩余把右侧簇推到行尾；fail 红 / skip text-2）+ skip「已停用」角标
                                Row {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text { text: modelData.name; font.pixelSize: root.themeRoot.fsBody; font.weight: Font.DemiBold
                                           color: isFail ? root.themeRoot.colErr : (isSkip ? root.themeRoot.colText2 : root.themeRoot.colText) }
                                    Rectangle {
                                        visible: isSkip
                                        radius: 5; implicitWidth: offLbl.implicitWidth + 12; implicitHeight: 17
                                        color: root.themeRoot.colBg2
                                        Text { id: offLbl; anchors.centerIn: parent; text: "已停用"; font.pixelSize: 10; font.weight: Font.DemiBold; color: root.themeRoot.colText2 }
                                    }
                                }
                                // 阈值徽章 .ci-th（等宽 11px bg-2 底 padding 2 8 圆角 6；none/skip 不显示）——右侧簇
                                Rectangle {
                                    visible: modelData.mode !== "none" && !isSkip
                                    radius: 6; implicitWidth: thLbl.implicitWidth + 16; implicitHeight: 20
                                    color: root.themeRoot.colBg2
                                    Text { id: thLbl; anchors.centerIn: parent; text: modelData.th || ""; font.family: "monospace"; font.pixelSize: root.themeRoot.fsCaption; color: root.themeRoot.colText2 }
                                }
                                // 当前值 .ci-val（等宽 13 text-2）
                                Text { text: String(modelData.cur); font.family: "monospace"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2 }
                                // 编辑齿轮 .ci-cfg（26×26 圆角 7；默认透明灰字，hover card 底+line 边框+primary）
                                Item {
                                    width: 26; height: 26
                                    Rectangle { anchors.fill: parent; radius: 7; color: gearMa.hovered ? root.themeRoot.colCard : "transparent"; border.width: 1; border.color: gearMa.hovered ? root.themeRoot.colLine : "transparent" }
                                    Image { id: gearImg; visible: false; source: "qrc:/qml/img/check-gear.svg"; sourceSize: Qt.size(14,14) }
                                    MultiEffect {
                                        anchors.centerIn: parent; width: 14; height: 14; source: gearImg
                                        colorization: 1.0
                                        colorizationColor: gearMa.hovered ? root.themeRoot.colPrimary : root.themeRoot.colText2
                                    }
                                    HoverHandler { id: gearMa; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.openEditor(modelData) }
                                }
                                // 删除垃圾桶（仅自定义项；hover 红）
                                Item {
                                    width: 26; height: 26
                                    visible: modelData.custom === true
                                    Rectangle { anchors.fill: parent; radius: 7; color: delMa.hovered ? root.themeRoot.colCard : "transparent"; border.width: 1; border.color: delMa.hovered ? root.themeRoot.colErr : "transparent" }
                                    Image { id: trashImg; visible: false; source: "qrc:/qml/img/check-trash.svg"; sourceSize: Qt.size(14,14) }
                                    MultiEffect {
                                        anchors.centerIn: parent; width: 14; height: 14; source: trashImg
                                        colorization: 1.0
                                        colorizationColor: delMa.hovered ? root.themeRoot.colErr : root.themeRoot.colText2
                                    }
                                    HoverHandler { id: delMa; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: {
                                        checkEngine.removeItem(modelData.id)
                                        root.themeRoot.showToast("已删除自检项：" + modelData.name)
                                    } }
                                }
                                // 阻塞角标 .ci-block（仅 fail：err-soft 底红字 11/700 padding 2 9 圆角 6；原型 innerHTML 末尾=行最右）
                                Rectangle {
                                    visible: isFail
                                    radius: 6; implicitWidth: blockLbl.implicitWidth + 18; implicitHeight: 20
                                    color: root.themeRoot.colErrSoft
                                    Text { id: blockLbl; anchors.centerIn: parent; text: "阻塞起飞"; font.pixelSize: root.themeRoot.fsCaption; font.weight: Font.Bold; color: root.themeRoot.colErr }
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 14; Layout.fillWidth: true }   // 下 padding 14
                }
            }
        }
    }

    // ===== 参数编辑弹窗（.modal：420 卡底圆角 14；head 14×18 下边框；body 18；set-group card-2 圆角 12）=====
    // 遮罩对齐原型 .modal-mask：rgba(15,23,42,.5) 覆盖全窗（含导航/顶栏），弹窗相对全窗居中
    Dialog {
        id: editDlg
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 420
        padding: 0
        closePolicy: Popup.CloseOnEscape   // Esc 可关；点遮罩不关（对齐原型仅 ×/取消/Esc）
        Overlay.modal: Rectangle {
            color: Qt.rgba(15 / 255, 23 / 255, 42 / 255, 0.5)   // 原型 .modal-mask 遮罩色
        }
        background: Rectangle { radius: 14; color: root.themeRoot.colCard; border.color: root.themeRoot.colLine }
        // 打开时从快照回填（对齐原型 openCheckEditor 初始选中态）
        onAboutToShow: {
            const d = root.editDef
            enChk.checked = d.en !== false
            nameInput.text = d.name || ""
            const m = d.mode || "single"
            editMode = m
            modeCombo.currentIndex = m === "none" ? 0 : (m === "single" ? 1 : 2)
            cmpCombo.currentIndex = {gt:0, lt:1, gte:2, lte:3}[d.cmp || "gt"]
            valInput.text = d.val != null ? String(d.val) : ""
            minInput.text = d.min != null ? String(d.min) : ""
            maxInput.text = d.max != null ? String(d.max) : ""
            // 设备下拉回填：历史自定义项的 dev 不在字典时临时追加（保持显示与保存兼容）
            root.devModel = root.devModelBase.slice()
            let di = root.devModel.findIndex(o => o.dev === (d.dev || ""))
            if (di < 0 && d.dev) { root.devModel.push({label: d.dev, dev: d.dev}); di = root.devModel.length - 1 }
            devCombo.model = root.devModel
            devCombo.currentIndex = Math.max(di, 0)
            // 字段下拉随「实际选中的设备」重建（新增时 dev 空 → 用首项 BMS，勿用空键查字典）；
            // 历史 fid 不在字典时临时追加
            const effDev = root.devModel[Math.max(di, 0)].dev
            root.fidModel = (root.fidDict[effDev] || []).slice()
            let fi = root.fidModel.findIndex(o => o.v === (d.fid || ""))
            if (fi < 0 && d.fid) { root.fidModel.push({label: d.fid + "（历史）", v: d.fid, u: ""}); fi = root.fidModel.length - 1 }
            fidCombo.model = root.fidModel
            fidCombo.currentIndex = root.fidModel.length ? Math.max(fi, 0) : -1
        }
        ColumnLayout {
            width: 420   // 显式宽度（padding 0）：避免 parent.width 反推导致的布局循环塌陷
            spacing: 0
            // .modal-head（padding 14 18 + 下边框 + 700 字；× 20px text-2）
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 45
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.themeRoot.colLine }
                    Text { anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: root.dlgTitle; font.bold: true; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText }
                    Rectangle {
                        id: mclose
                        anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        color: mcloseMa.hovered ? root.themeRoot.colCard2 : "transparent"
                        radius: 6
                        Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 20; color: root.themeRoot.colText2 }
                        HoverHandler { id: mcloseMa; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: editDlg.close() }
                    }
                }
            // .modal-body（padding 18）
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                spacing: 0
                // .set-group（card-2 底 + line 边框 + 圆角 12 + padding 14 16，行间 gap 2）
                // 高度由内容撑起（无高度约束=0 高，内部全塌——同电源总览模块教训）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: sgCol.implicitHeight + 28
                    radius: 12
                    color: root.themeRoot.colCard2
                    border.color: root.themeRoot.colLine
                    ColumnLayout {
                        id: sgCol
                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.leftMargin: 16; anchors.rightMargin: 16
                        spacing: 2
                        // .cfg-item（checkbox 行：padding 7 6，勾选框 16 accent primary）
                        CheckBox {
                            id: enChk
                            text: "启用此自检项"
                            font.pixelSize: root.themeRoot.fsBody
                            leftPadding: 6; rightPadding: 6; topPadding: 7; bottomPadding: 7
                            indicator: Rectangle {
                                implicitWidth: 16; implicitHeight: 16
                                x: enChk.leftPadding; y: parent.height / 2 - height / 2
                                radius: 4
                                color: enChk.checked ? root.themeRoot.colPrimary : root.themeRoot.colCard
                                border.width: 1
                                border.color: enChk.checked ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                Text { anchors.centerIn: parent; text: "✓"; font.pixelSize: root.themeRoot.fsCaption; font.bold: true; color: "white"; visible: enChk.checked }
                            }
                            contentItem: Text { text: enChk.text; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText; leftPadding: enChk.indicator.width + 10; verticalAlignment: Text.AlignVCenter }
                        }
                        // —— .set-row 通用行（padding 7 0 + 虚线分隔近似实线 1px；label 13 text-2 左 / 控件右 170px 等宽 card 底圆角 8）——
                        // 自定义项元信息（仅自定义项显示；input width 200px 对齐原型 inline style）
                        ColumnLayout {
                            visible: root.editIsCustom
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "项目名称"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                TextField {
                                    id: nameInput; width: 200; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"; maximumLength: 20
                                    placeholderText: "如：输入电压"
                                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: nameInput.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.editIsCustom
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "设备"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                ComboBox {
                                    id: devCombo
                                    width: 200
                                    topPadding: 6; bottomPadding: 6
                                    font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    textRole: "label"; valueRole: "dev"
                                    model: root.devModel
                                    onActivated: function(i) { root.onDevActivated(i) }
                                    indicator: Text { x: devCombo.width - width - 10; y: devCombo.height / 2 - height / 2; text: "▾"; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2 }
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: devCombo.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                    contentItem: Text { text: devCombo.displayText; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"; color: root.themeRoot.colText; leftPadding: 10; rightPadding: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.editIsCustom
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "数据字段"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                ComboBox {
                                    id: fidCombo
                                    width: 200
                                    topPadding: 6; bottomPadding: 6
                                    font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    textRole: "label"; valueRole: "v"
                                    model: root.fidModel
                                    indicator: Text { x: fidCombo.width - width - 10; y: fidCombo.height / 2 - height / 2; text: "▾"; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2 }
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: fidCombo.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                    contentItem: Text { text: fidCombo.displayText; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"; color: root.themeRoot.colText; leftPadding: 10; rightPadding: 20; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                }
                            }
                        }
                        // 检查方式
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "检查方式"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                ComboBox {
                                    id: modeCombo
                                    width: 170
                                    topPadding: 6; bottomPadding: 6
                                    font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    textRole: "label"; valueRole: "value"
                                    model: [ {label:"无（仅在线）", value:"none"}, {label:"单阈值", value:"single"}, {label:"范围（下限~上限）", value:"range"} ]
                                    onActivated: root.editMode = currentValue
                                    indicator: Text { x: modeCombo.width - width - 10; y: modeCombo.height / 2 - height / 2; text: "▾"; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2 }
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: modeCombo.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                    contentItem: Text { text: modeCombo.displayText; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"; color: root.themeRoot.colText; leftPadding: 10; rightPadding: 20; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        }
                        // 比较符（仅 single）
                        ColumnLayout {
                            visible: root.editMode === "single"
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "比较符"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                ComboBox {
                                    id: cmpCombo
                                    width: 170
                                    topPadding: 6; bottomPadding: 6
                                    font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    textRole: "label"; valueRole: "value"
                                    model: [ {label:"大于 >", value:"gt"}, {label:"小于 <", value:"lt"}, {label:"大于等于 ≥", value:"gte"}, {label:"小于等于 ≤", value:"lte"} ]
                                    indicator: Text { x: cmpCombo.width - width - 10; y: cmpCombo.height / 2 - height / 2; text: "▾"; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2 }
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: cmpCombo.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                    contentItem: Text { text: cmpCombo.displayText; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"; color: root.themeRoot.colText; leftPadding: 10; rightPadding: 20; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        }
                        // 阈值数值（仅 single；宽 170 + 单位后缀 12px text-2）
                        ColumnLayout {
                            visible: root.editMode === "single"
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "阈值数值"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                TextField {
                                    id: valInput; width: 170; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
                                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: valInput.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                }
                                Item { width: 6; height: 1 }
                                Text { text: root.curUnit; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        // 下限（仅 range）
                        ColumnLayout {
                            visible: root.editMode === "range"
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "下限"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                TextField {
                                    id: minInput; width: 170; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
                                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: minInput.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                }
                                Item { width: 6; height: 1 }
                                Text { text: root.curUnit; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        // 上限（仅 range）
                        ColumnLayout {
                            visible: root.editMode === "range"
                            Layout.fillWidth: true
                            spacing: 0
                            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine; opacity: 0.6 }
                            Row {
                                Layout.fillWidth: true; topPadding: 7; bottomPadding: 7
                                Text { text: "上限"; font.pixelSize: root.themeRoot.fsBody; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: 12; height: 1 }
                                TextField {
                                    id: maxInput; width: 170; font.pixelSize: root.themeRoot.fsBody; font.family: "monospace"
                                    validator: DoubleValidator { notation: DoubleValidator.StandardNotation }
                                    leftPadding: 10; rightPadding: 10; topPadding: 6; bottomPadding: 6
                                    background: Rectangle { radius: 8; color: root.themeRoot.colCard; border.width: 1; border.color: maxInput.activeFocus ? root.themeRoot.colPrimary : root.themeRoot.colLine }
                                }
                                Item { width: 6; height: 1 }
                                Text { text: root.curUnit; font.pixelSize: root.themeRoot.fsSmall; color: root.themeRoot.colText2; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
                // footer（右对齐 gap 8 margin-top 14；取消=.btn.ghost / 保存=.btn）
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 14
                    spacing: 8
                    Rectangle {
                        id: ckCancel
                        readonly property bool hov: ckCancelMa.hovered
                        radius: 10
                        implicitWidth: ckCancelLbl.implicitWidth + 32
                        implicitHeight: ckCancelLbl.implicitHeight + 16
                        color: "transparent"
                        border.width: 1
                        border.color: hov ? root.themeRoot.colPrimary : root.themeRoot.colLine
                        Text { id: ckCancelLbl; anchors.centerIn: parent; text: "取消"; color: hov ? root.themeRoot.colPrimary : root.themeRoot.colText2; font.pixelSize: root.themeRoot.fsBody; font.weight: Font.DemiBold }
                        HoverHandler { id: ckCancelMa; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: editDlg.close() }
                    }
                    Rectangle {
                        id: ckSave
                        readonly property bool hov: ckSaveMa.hovered
                        radius: 10
                        implicitWidth: ckSaveLbl.implicitWidth + 32
                        implicitHeight: ckSaveLbl.implicitHeight + 16
                        color: hov ? Qt.lighter(root.themeRoot.colPrimary, 1.08) : root.themeRoot.colPrimary
                        Text { id: ckSaveLbl; anchors.centerIn: parent; text: "保存"; color: "white"; font.pixelSize: root.themeRoot.fsBody; font.weight: Font.DemiBold }
                        HoverHandler { id: ckSaveMa; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.saveEdit() }
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import QtCharts

// 图示视图（复刻原型 #view-topo）：
// 左侧树状层级导航（电源链路 / 温度监测 / 实时曲线），右侧对应面板。
// 温度监测含三 tab：囊体热力图 / 探头数据表 / 探头映射。
Item {
    id: root

    property QtObject themeRoot: null
    signal showNote(string msg)
    signal snapSave(string fileUrl)   // 曲线快照保存请求（fileUrl=用户选择的文件路径）

    property int treeNode: 0        // 0=电源链路 1=温度监测 2=实时曲线

    function snapTs() {
        const d = new Date()
        const p = n => (n < 10 ? "0" + n : n)
        return "" + d.getFullYear() + p(d.getMonth()+1) + p(d.getDate())
             + "_" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds())
    }

    function fmt(v, dp) { return isNaN(v) ? "--" : Number(v).toFixed(dp); }

    // ===== 压力单位换算（配置于设置页：0=kPa 1=Pa 2=bar 3=psi）=====
    function presLabel() {
        void root.themeRoot.dataTick
        return ["kPa","Pa","bar","psi"][bridge.configPressureUnit()] || "kPa"
    }
    // v_kpa：入参为 kPa 数值，按配置单位换算为显示字符串
    function presStr(v_kpa) {
        void root.themeRoot.dataTick
        if (isNaN(v_kpa)) return "--"
        const pa = v_kpa * 1000
        switch (bridge.configPressureUnit()) {
            case 1: return "" + Math.round(pa)            // Pa
            case 2: return (pa/100000).toFixed(3)         // bar
            case 3: return (pa/6894.7573).toFixed(1)      // psi
            default: return (pa/1000).toFixed(1)          // kPa
        }
    }

    // ===== 电源链路拓扑数据 =====
    function tPv()  { void root.themeRoot.dataTick; return root.off("mppt") ? 0 : Math.round(bridge.value("mppt","pv_p")||0) }
    function tPvV() { void root.themeRoot.dataTick; return root.off("mppt") ? 0 : (bridge.value("mppt","pv_v")||0) }
    function tCi()  { void root.themeRoot.dataTick; return root.off("mppt") ? 0 : (bridge.value("mppt","charge_i")||0) }
    function tSoc() { void root.themeRoot.dataTick; return root.off("bms") ? 0 : Math.round(bridge.value("bms","soc")||0) }
    function tPackV(){void root.themeRoot.dataTick; return root.off("bms") ? 0 : (bridge.value("bms","pack_v")||0) }
    function tOut() { void root.themeRoot.dataTick; return root.off("dcdc") ? 0 : Math.round(bridge.value("dcdc","out_p")||0) }
    function tTemp(){ void root.themeRoot.dataTick; return root.off("dcdc") ? 0 : (bridge.value("dcdc","temp")||0) }
    function off(dev) { return !bridge.online(dev) }

    // ===== 温度热力图（四囊体 + 探头映射）=====
    property var envDef: [
        {name:"副囊 · 左", type:"sec", cols:8, rows:12, innerT:22.5, pres:3.2},
        {name:"主囊 · 左", type:"main", cols:9, rows:13, innerT:24.8, pres:3.8},
        {name:"主囊 · 右", type:"main", cols:9, rows:13, innerT:24.6, pres:3.8},
        {name:"副囊 · 右", type:"sec", cols:8, rows:12, innerT:22.8, pres:3.1}
    ]
    property var probes: root.loadProbes()
    property var pvVals: new Object()
    property var pvHist: new Object()
    property var cellIndex: new Object()   // "ei:r:c" -> probe（热力图 O(1) 查表）
    property int mappingRefresh: 0   // 探头映射编辑后自增，强制刷新映射表
    // 探头数据表 · 持久化 model（增量更新核心：数组引用不变，仅 mutate 属性）
    property var probeRowModel: []
    property int _probeModelGen: -1  // 与 mappingRefresh 对齐，判断是否需重建结构

    function loadProbes() {
        const arr = bridge.probeMapping()
        return arr || []   // 空值守卫：首次无映射文件等返回 null 时兜底为空数组
    }
    // 由 probes 重建 cellIndex 查表（在 load/apply 后调用）
    function rebuildCellIndex() {
        const idx = new Object()
        for (const p of root.probes) {
            const key = p.ei + ":" + p.row + ":" + p.col
            idx[key] = p   // 同格多探头时后者覆盖（示意布局，正常不重叠）
        }
        root.cellIndex = idx
    }
    function probeOf(pid) {
        for (const p of root.probes) if (p.pid === pid) return p
        return null
    }
    // 热力图中某囊体某单元格（ei 囊体索引，cols 列数，idx 单元格序号）对应探头的颜色/文字
    function cellColor(ei, cols, idx) {
        void root.themeRoot.dataTick
        const r = Math.floor(idx / cols) + 1
        const c = idx % cols + 1
        const p = root.cellIndex[ei + ":" + r + ":" + c]
        if (p) {
            const v = (root.pvVals && root.pvVals[p.pid] != null) ? root.pvVals[p.pid] : p.base
            return root.pvColor(v)
        }
        return root.themeRoot.colBg2
    }
    function cellText(ei, cols, idx) {
        void root.themeRoot.dataTick
        const r = Math.floor(idx / cols) + 1
        const c = idx % cols + 1
        const p = root.cellIndex[ei + ":" + r + ":" + c]
        if (p) {
            const v = (root.pvVals && root.pvVals[p.pid] != null) ? root.pvVals[p.pid] : p.base
            return String(Math.round(v))
        }
        return ""
    }
    // 返回某单元格对应的探头对象（无探头返回 null）
    function cellProbe(ei, cols, idx) {
        const r = Math.floor(idx / cols) + 1
        const c = idx % cols + 1
        return root.cellIndex[ei + ":" + r + ":" + c] || null
    }
    // 点击探头方块 → 弹窗显示详情
    function showProbeDetail(p) {
        const env = root.envDef[p.ei]
        const v = (root.pvVals && root.pvVals[p.pid] != null) ? root.pvVals[p.pid] : p.base
        const hist = root.pvHist[p.pid] || []
        const hi = hist.length ? Math.max(...hist) : NaN
        const lo = hist.length ? Math.min(...hist) : NaN
        probeDetailPid.text = p.pid + " · " + env.name + " 第" + p.row + "行 第" + p.col + "列"
        probeDetailCur.text = v.toFixed(1) + " ℃"
        probeDetailRange.text = (isNaN(hi)?"—":hi.toFixed(0)) + " / " + (isNaN(lo)?"—":lo.toFixed(0)) + " ℃"
        probeDetail.detailColor = root.pvColor(v)
        probeDetail.open()
    }
    function pvColor(t) {
        if (t < 45) return "#3b82f6"
        if (t < 50) return "#22c55e"
        if (t < 55) return "#eab308"
        if (t < 60) return "#f97316"
        return "#ef4444"
    }
    // 探头数据表行 · 增量更新版本：
    // 结构变化（增删/改映射）时重建数组；数据刷新仅 in-place 更新属性
    function rebuildProbeRows() {
        root._probeModelGen = root.mappingRefresh
        const model = []
        for (const p of root.probes) {
            const env = root.envDef[p.ei]
            model.push({
                pid: p.pid,
                pos: env.name.split("·")[0].trim() + " · " + p.row + "行" + p.col + "列",
                cur: p.base, max: NaN, min: NaN, avg: NaN,
                color: root.pvColor(p.base),
                _ei: p.ei, _row: p.row, _col: p.col, _base: p.base
            })
        }
        root.probeRowModel = model
    }
    function updateProbeRows() {
        // 结构过期 → 先重建
        if (root._probeModelGen !== root.mappingRefresh)
            root.rebuildProbeRows()
        const model = root.probeRowModel
        for (let i = 0; i < model.length; i++) {
            const r = model[i]
            const pid = r.pid
            const v = root.pvVals[pid] != null ? root.pvVals[pid] : r._base
            const hist = root.pvHist[pid] || []
            let mx = NaN, mn = NaN, avg = NaN
            if (hist.length > 0) {
                // 逐元素遍历（比 ...spread 更省内存/GC）
                mx = hist[0]; mn = hist[0]
                let sum = 0
                for (let k = 0; k < hist.length; k++) {
                    const h = hist[k]
                    if (h > mx) mx = h
                    if (h < mn) mn = h
                    sum += h
                }
                avg = sum / hist.length
            }
            // in-place 更新，保持对象引用 → ListView 只刷新绑定属性，不重建 delegate
            r.cur = v
            r.max = mx
            r.min = mn
            r.avg = avg
            r.color = root.pvColor(v)
        }
        root.probeModelPoke = (root.probeModelPoke + 1) % 1000000
    }
    property int probeModelPoke: 0
    function probeCount() { return root.probes.length }
    function probeStats() {
        void root.themeRoot.dataTick
        let mx = -Infinity, sum = 0, alarm = 0, cnt = 0
        for (const p of root.probes) {
            const v = root.pvVals[p.pid]
            if (v != null) { sum += v; cnt++; if (v > mx) mx = v; if (v > 60) alarm++ }
        }
        return {count:cnt, max: mx>-Infinity?mx:NaN, avg: cnt?sum/cnt:NaN, alarm:alarm}
    }
    // ===== 探头映射编辑（原型 applyProbes 逻辑）=====
    function nextPid() {
        let n = 1
        const used = new Set(root.probes.map(p => p.pid))
        while (used.has("T" + (n < 10 ? "0" + n : n))) n++
        return "T" + (n < 10 ? "0" + n : n)
    }
    // 编辑后：持久化 + 刷新映射表 + 重建查表索引 + 通知热力图/长表/宽表重算
    function applyMapping() {
        bridge.saveProbeMapping(root.probes)
        root.rebuildCellIndex()
        root.mappingRefresh++
        root.rebuildProbeRows()   // 结构变化立即重建 probeRowModel
        root.themeRoot.dataTick++
    }
    function addProbe() {
        root.probes.push({pid: root.nextPid(), ei: 0, row: 2, col: 2, base: 45})
        root.applyMapping()
        root.showNote("已添加探头")
    }
    function removeProbe(pid) {
        root.probes = root.probes.filter(p => p.pid !== pid)
        delete root.pvVals[pid]
        delete root.pvHist[pid]
        root.applyMapping()
        root.showNote("已删除探头 " + pid)
    }
    // 颜色 hex → rgba（用于宽表背景半透明）
    function hexRgba(hex, a) {
        return "rgba(" + parseInt(hex.slice(1,3),16) + "," + parseInt(hex.slice(3,5),16) + ","
                     + parseInt(hex.slice(5,7),16) + "," + a + ")"
    }
    // 时间对齐宽表绘制（原型 updateTempWide，60 行 × 探头数）
    function drawTempWide(ctx, W, H) {
        ctx.reset()
        const idxW = 44, timeW = 60, colW = 46, headerH = 30, rowH = 24
        const probes = root.probes
        const n = probes.length
        // 表头
        ctx.fillStyle = root.themeRoot.colCard2
        ctx.fillRect(0, 0, W, headerH)
        ctx.strokeStyle = root.themeRoot.colLine
        ctx.strokeRect(0, 0, W, headerH)
        ctx.fillStyle = root.themeRoot.colText2
        ctx.font = "600 11px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("序", idxW/2, headerH/2)
        ctx.fillText("相对s", idxW + timeW/2, headerH/2)
        for (let c = 0; c < n; c++) ctx.fillText(probes[c].pid, idxW + timeW + c*colW + colW/2, headerH/2)
        // 数据行
        const WIDE_ROWS = 60
        // 每点采样间隔：温度监测 1s/点（与温度采样 Timer interval 一致），相对时间 = 序号 × 间隔
        const ROW_SEC = 1.0
        let minLen = Infinity
        for (const p of probes) minLen = Math.min(minLen, (root.pvHist[p.pid] || []).length)
        if (minLen === Infinity) minLen = 0
        const start = Math.max(0, minLen - WIDE_ROWS)
        for (let i = 0; i < WIDE_ROWS; i++) {
            const idx = start + i
            const y = headerH + i*rowH
            ctx.fillStyle = (i % 2 === 1) ? root.themeRoot.colCard2 : "transparent"
            ctx.fillRect(0, y, W, rowH)
            ctx.font = "10px monospace"
            ctx.fillStyle = root.themeRoot.colText2
            ctx.fillText(idx >= 0 ? String(idx) : "—", idxW/2, y + rowH/2)
            ctx.fillText(idx >= 0 ? (idx*ROW_SEC).toFixed(1) : "—", idxW + timeW/2, y + rowH/2)
            for (let c = 0; c < n; c++) {
                const h = root.pvHist[probes[c].pid] || []
                const v = (idx >= 0 && idx < h.length) ? h[idx] : null
                const x = idxW + timeW + c*colW
                const cx = x + colW/2
                if (v != null) {
                    const col = root.pvColor(v)
                    ctx.fillStyle = root.hexRgba(col, 0.13)
                    ctx.fillRect(x, y, colW, rowH)
                    ctx.fillStyle = col
                    ctx.fillText(v.toFixed(1), cx, y + rowH/2)
                } else {
                    ctx.fillStyle = root.themeRoot.colText2
                    ctx.fillText("—", cx, y + rowH/2)
                }
            }
        }
    }
    // （原始数据由 C++ 层按会话逐帧自动记录，不再在 QML 层导出温度表）

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // 顶部：图示标题 + 面包屑
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: 12
            color: root.themeRoot.colCard
            border.color: root.themeRoot.colLine
            RowLayout {
                anchors.fill: parent; anchors.margins: 16
                Text { text: "图示"; font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText }
                Text {
                    text: ["电源链路","温度监测","实时曲线"][root.treeNode]
                    font.pixelSize: 12; font.weight: Font.DemiBold; color: root.themeRoot.colText2
                }
                Item { Layout.fillWidth: true }
            }
        }

        // 主体：树 + 面板
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // 左侧树状导航
            Rectangle {
                Layout.preferredWidth: root.themeRoot.dense ? 56 : 200
                Layout.fillHeight: true
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                Column {
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 4
                    Text {
                        text: root.themeRoot.dense ? "" : "图示"
                        font.pixelSize: 13; font.bold: true; color: root.themeRoot.colText2
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.letterSpacing: 0.5
                        bottomPadding: 6
                    }
                    // 电源链路
                    Rectangle {
                        width: parent.width; height: 46; radius: 10
                        color: root.treeNode === 0 ? root.themeRoot.colPrimarySoft : "transparent"
                        Row {
                            anchors.centerIn: parent; spacing: 10
                            Text { text: "◎"; font.pixelSize: 16; color: root.treeNode===0 ? root.themeRoot.colPrimary : root.themeRoot.colText2 }
                            Text {
                                text: root.themeRoot.dense ? "" : "电源链路"
                                font.pixelSize: 15; font.weight: Font.DemiBold
                                color: root.treeNode===0 ? root.themeRoot.colPrimary : root.themeRoot.colText2
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.treeNode = 0 }
                    }
                    // 温度监测（子项）
                    Rectangle {
                        width: parent.width; height: 46; radius: 10
                        color: root.treeNode === 1 ? root.themeRoot.colPrimarySoft : "transparent"
                        border.color: root.treeNode === 1 ? root.themeRoot.colPrimary : "transparent"
                        Row {
                            anchors.centerIn: parent; spacing: 10
                            Text { text: "◉"; font.pixelSize: 16; color: root.treeNode===1 ? root.themeRoot.colPrimary : root.themeRoot.colText2 }
                            Text {
                                text: root.themeRoot.dense ? "" : "温度监测"
                                font.pixelSize: 15; font.weight: Font.DemiBold
                                color: root.treeNode===1 ? root.themeRoot.colPrimary : root.themeRoot.colText2
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.treeNode = 1 }
                    }
                    // 实时曲线
                    Rectangle {
                        width: parent.width; height: 46; radius: 10
                        color: root.treeNode === 2 ? root.themeRoot.colPrimarySoft : "transparent"
                        Row {
                            anchors.centerIn: parent; spacing: 10
                            Text { text: "∿"; font.pixelSize: 16; color: root.treeNode===2 ? root.themeRoot.colPrimary : root.themeRoot.colText2 }
                            Text {
                                text: root.themeRoot.dense ? "" : "实时曲线"
                                font.pixelSize: 15; font.weight: Font.DemiBold
                                color: root.treeNode===2 ? root.themeRoot.colPrimary : root.themeRoot.colText2
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.treeNode = 2 }
                    }
                }
            }

            // 右侧面板（与左侧导航同为白色大卡，RowLayout.fillHeight 保证底部对齐）
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: root.themeRoot.colCard
                border.color: root.themeRoot.colLine
                clip: true

                // ===== 电源链路拓扑（Canvas 绘制）=====
                Loader {
                    active: root.treeNode === 0
                    visible: active
                    anchors.fill: parent
                    anchors.margins: 12
                    sourceComponent: powerPanel
                }

                // ===== 温度监测面板 =====
                Loader {
                    active: root.treeNode === 1
                    visible: active
                    anchors.fill: parent
                    anchors.margins: 12
                    sourceComponent: tempPanel
                }

                // ===== 实时曲线面板 =====
                Loader {
                    active: root.treeNode === 2
                    visible: active
                    anchors.fill: parent
                    anchors.margins: 12
                    sourceComponent: chartPanel
                }
            }
        }
    }

    // ===== 电源链路拓扑 =====
    Component {
        id: powerPanel
        Item {
            // 直接放在右侧大卡（colCard）上，不再嵌套重复卡
            Item {
                anchors.fill: parent
                // 图例
                Row {
                    anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 12
                    spacing: 14
                    Repeater {
                        model: [["ok","在线"],["warn","告警"],["off","离线"]]
                        Row {
                            spacing: 6
                            Rectangle { width: 10; height: 10; radius: 5
                                color: modelData[0]==="ok" ? root.themeRoot.colOk
                                     : modelData[0]==="warn" ? root.themeRoot.colWarn : root.themeRoot.colOff }
                            Text { text: modelData[1]; font.pixelSize: 12; color: root.themeRoot.colText2; font.weight: Font.DemiBold }
                        }
                    }
                }
                // 拓扑 Canvas
                Canvas {
                    id: topoCanvas
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const w = width, h = height
                        const cx = w/2
                        // 节点中心（横排 5 个：光伏/MPPT/BMS/DCDC/负载）
                        const nodeW = Math.min(150, w/6)
                        const gap = (w - 5*nodeW) / 6
                        const ys = h/2
                        const xs = []
                        for (let i=0;i<5;i++) xs.push(gap + nodeW*i + nodeW/2)
                        // 连线（流动虚线）
                        ctx.strokeStyle = root.themeRoot.colPrimary
                        ctx.lineWidth = 2.5
                        ctx.setLineDash([8,6])
                        const links = [[xs[0],xs[1]],[xs[1],xs[2]],[xs[2],xs[3]],[xs[3],xs[4]]]
                        for (const l of links) {
                            ctx.beginPath(); ctx.moveTo(l[0], ys); ctx.lineTo(l[1], ys); ctx.stroke()
                        }
                        ctx.setLineDash([])
                        // 节点
                        const nodes = [
                            {x:xs[0], t:"光伏面板", v: root.tPv()+" W", s: root.tPvV().toFixed(1)+" V", off: root.off("mppt")},
                            {x:xs[1], t:"MPPT 控制器", v: root.tCi().toFixed(1)+" A", s:"效率 "+(root.tPv()&&root.tOut()?Math.round(root.tOut()/root.tPv()*100):0)+"%", off: root.off("mppt")},
                            {x:xs[2], t:"电池组 BMS", v: root.tSoc()+"%", s: root.tPackV().toFixed(1)+" V", off: root.off("bms")},
                            {x:xs[3], t:"DCDC 模块", v: root.tOut()+" W", s: root.tTemp().toFixed(1)+" ℃", off: root.off("dcdc")},
                            {x:xs[4], t:"机载负载", v: root.tOut()+" W", s:"在线", off: root.off("dcdc")}
                        ]
                        for (const n of nodes) {
                            const col = n.off ? root.themeRoot.colOff : root.themeRoot.colText
                            const fill = n.off ? root.themeRoot.colBg2 : root.themeRoot.colCard2
                            const stroke = n.off ? root.themeRoot.colOff : root.themeRoot.colLine
                            // 框
                            ctx.beginPath()
                            // 手动圆角矩形（兼容无 roundRect 的 Qt）
                            const bx = n.x-nodeW/2, by = ys-75, bw = nodeW, bh = 150, rr = 12
                            ctx.moveTo(bx+rr, by)
                            ctx.arcTo(bx+bw, by, bx+bw, by+bh, rr)
                            ctx.arcTo(bx+bw, by+bh, bx, by+bh, rr)
                            ctx.arcTo(bx, by+bh, bx, by, rr)
                            ctx.arcTo(bx, by, bx+bw, by, rr)
                            ctx.closePath()
                            ctx.fillStyle = fill; ctx.fill()
                            ctx.strokeStyle = stroke; ctx.lineWidth = 1.5; ctx.stroke()
                            // 标题
                            ctx.fillStyle = n.off ? root.themeRoot.colOff : root.themeRoot.colText2
                            ctx.font = "600 13px sans-serif"
                            ctx.textAlign = "center"
                            ctx.fillText(n.t, n.x, ys-45)
                            // 主值
                            ctx.fillStyle = n.off ? root.themeRoot.colOff : col
                            ctx.font = "700 19px monospace"
                            ctx.fillText(n.v, n.x, ys-8)
                            // 副值
                            ctx.fillStyle = n.off ? root.themeRoot.colOff : root.themeRoot.colText2
                            ctx.font = "12px monospace"
                            ctx.fillText(n.s, n.x, ys+14)
                        }
                    }
                    // 遥测节拍变化时重绘电源拓扑
                    Connections {
                        target: root.themeRoot
                        function onDataTickChanged() { topoCanvas.requestPaint() }
                    }
                }
            }
        }
    }

    // ===== 温度监测面板 =====
    Component {
        id: tempPanel
        Item {
            id: tmpRoot
            property int ttab: 0      // 0=热力图 1=数据表 2=映射
            property int stab: 0      // 数据表子tab：0=指标总览 1=时间对齐
            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                // 子 tab
                Row {
                    spacing: 4
                    Repeater {
                        model: ["光伏热力图","光伏温度表","温度探头映射"]
                        Rectangle {
                            width: 130; height: 38; radius: 8
                            color: tmpRoot.ttab === index ? root.themeRoot.colPrimarySoft : root.themeRoot.colCard2
                            border.color: tmpRoot.ttab === index ? root.themeRoot.colPrimary : root.themeRoot.colLine
                            Text {
                                anchors.centerIn: parent
                                text: modelData; font.pixelSize: 15; font.weight: Font.DemiBold
                                color: tmpRoot.ttab === index ? root.themeRoot.colPrimary : root.themeRoot.colText2
                            }
                            MouseArea { anchors.fill: parent; onClicked: tmpRoot.ttab = index }
                        }
                    }
                }

                // 统计条（灰底卡，放在右侧白色大卡上形成层次）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: root.themeRoot.colCard2
                    border.color: root.themeRoot.colLine
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 14
                        spacing: 18
                        Text { text: "探头 <b>" + root.probeCount() + "</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                        Text { text: "最高 <b>" + (isNaN(root.probeStats().max)?"—":Math.round(root.probeStats().max)+"℃") + "</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                        Text { text: "平均 <b>" + (isNaN(root.probeStats().avg)?"—":Math.round(root.probeStats().avg)+"℃") + "</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                        Text { text: "告警 <b>" + root.probeStats().alarm + "</b>"; font.pixelSize: 12; color: root.probeStats().alarm>0 ? root.themeRoot.colErr : root.themeRoot.colText2; textFormat: Text.RichText }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ===== 热力图（参照 HTML 原型：四囊体并排 + CSS grid 自适应单元格）=====
                ColumnLayout {
                    visible: tmpRoot.ttab === 0
                    Layout.fillWidth: true; Layout.fillHeight: true
                    spacing: 10
                    // 温度色图例
                    Row {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: [["#3b82f6","<45"],["#22c55e","45-50"],["#eab308","50-55"],["#f97316","55-60"],["#ef4444",">60"]]
                            Row {
                                spacing: 4
                                Rectangle { width: 14; height: 14; radius: 3; color: modelData[0] }
                                Text { text: modelData[1]; font.pixelSize: 11; color: root.themeRoot.colText2; font.weight: Font.DemiBold }
                            }
                        }
                    }
                    // 四囊体并排（原型 .env-row flex，主囊 flex:1.18）
                    RowLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        spacing: 10
                        Repeater {
                            model: root.envDef
                            Rectangle {
                                id: envCard
                                property var env: modelData
                                property int envIndex: index
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: env.type === "main" ? 118 : 100
                                Layout.maximumWidth: root.width * 0.34
                                radius: 12
                                color: root.themeRoot.colCard2
                                border.color: root.themeRoot.colLine
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 10
                                    spacing: 6
                                    // 头部：囊体名 + 类型 + 行列（原型 .env-head）
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: env.name; font.bold: true; font.pixelSize: 13; color: root.themeRoot.colText }
                                        Rectangle {
                                            radius: 999; implicitWidth: 40; implicitHeight: 18
                                            color: env.type === "main" ? root.themeRoot.colPrimarySoft : root.themeRoot.colBg2
                                            Text {
                                                anchors.centerIn: parent
                                                text: env.type === "main" ? "主囊" : "副囊"
                                                font.pixelSize: 10; font.bold: true
                                                color: env.type === "main" ? root.themeRoot.colPrimary : root.themeRoot.colText2
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text { text: env.cols + "×" + env.rows; font.pixelSize: 11; font.family: "monospace"; color: root.themeRoot.colText2 }
                                    }
                                    // 内部温度/压力（原型 .env-inner）
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 8; color: root.themeRoot.colCard
                                            Column { anchors.centerIn: parent; spacing: 2
                                                Text { text: "内部温度"; font.pixelSize: 10; color: root.themeRoot.colText2; anchors.horizontalCenter: parent.horizontalCenter }
                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    Text { text: (env.innerT).toFixed(1); font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
                                                    Text { text: "℃"; font.pixelSize: 10; color: root.themeRoot.colText2 }
                                                }
                                            }
                                        }
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 8; color: root.themeRoot.colCard
                                            Column { anchors.centerIn: parent; spacing: 2
                                                Text { text: "内部压力"; font.pixelSize: 10; color: root.themeRoot.colText2; anchors.horizontalCenter: parent.horizontalCenter }
                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    Text { text: root.presStr(env.pres); font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
                                                    Text { text: root.presLabel(); font.pixelSize: 10; color: root.themeRoot.colText2 }
                                                }
                                            }
                                        }
                                    }
                                    // 网格（原型 .env-grid，repeat(cols/rows,1fr) 自适应填满，纵向长方形单元格）
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        color: root.themeRoot.colBg2
                                        radius: 6
                                        clip: true
                                        GridLayout {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            columns: env.cols
                                            rows: env.rows
                                            columnSpacing: 2; rowSpacing: 2
                                            Repeater {
                                                model: env.cols * env.rows
                                                Rectangle {
                                                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                                    scale: ma_1.pressed ? 0.96 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    Layout.preferredWidth: 1; Layout.preferredHeight: 1
                                                    radius: 2
                                                    color: root.cellColor(envCard.envIndex, env.cols, index)
                                                    border.width: root.cellProbe(envCard.envIndex, env.cols, index) ? 1 : 0
                                                    border.color: root.themeRoot.colText
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: root.cellText(envCard.envIndex, env.cols, index)
                                                        font.pixelSize: 13; font.bold: true; color: "white"
                                                        visible: root.cellText(envCard.envIndex, env.cols, index) !== ""
                                                    }
                                                    MouseArea {
                                                        cursorShape: Qt.PointingHandCursor
                                                        id: ma_1
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: {
                                                            var p = root.cellProbe(envCard.envIndex, env.cols, index)
                                                            if (p) root.showProbeDetail(p)
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

                // ===== 数据表（光伏温度表，含子tab：指标总览 / 时间对齐）=====
                ColumnLayout {
                    visible: tmpRoot.ttab === 1
                    Layout.fillWidth: true; Layout.fillHeight: true
                    spacing: 8
                    // 子 tab 切换（原型 .tt-subtabs）
                    RowLayout {
                        spacing: 4
                        Repeater {
                            model: ["指标总览","时间对齐"]
                            Rectangle {
                                // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                scale: ma_2.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                width: 110; height: 32; radius: 8
                                color: tmpRoot.stab === index ? root.themeRoot.colPrimarySoft : root.themeRoot.colCard2
                                border.color: tmpRoot.stab === index ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData; font.pixelSize: 13; font.weight: Font.DemiBold
                                    color: tmpRoot.stab === index ? root.themeRoot.colPrimary : root.themeRoot.colText2
                                }
                                MouseArea {
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    id: ma_2
                                    anchors.fill: parent
                                    onClicked: { tmpRoot.stab = index; if (index === 1) wideCanvas.requestPaint() }
                                }
                            }
                        }
                    }
                    // 指标总览（长表，带表头）
                    Item {
                        visible: tmpRoot.stab === 0
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: root.themeRoot.colCard2
                            border.color: root.themeRoot.colLine
                            clip: true
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0
                                // 表头
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    color: root.themeRoot.colCard2
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12
                                        spacing: 12
                                        Text { text: "探头ID"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 60 }
                                        Text { text: "位置"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 180 }
                                        Text { text: "当前温度"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 90 }
                                        Text { text: "最高"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 70 }
                                        Text { text: "最低"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 70 }
                                        Text { text: "平均"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 70 }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine }
                                // 数据行
                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: (void root.probeModelPoke, root.probeRowModel)
                                    spacing: 0
                                    delegate: Rectangle {
                                        width: ListView.view ? ListView.view.width : parent.width
                                        height: 38
                                        color: index % 2 === 0 ? "transparent" : root.themeRoot.colCard2
                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: 12
                                            spacing: 12
                                            Text { text: modelData.pid; font.pixelSize: 13; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText; Layout.preferredWidth: 60 }
                                            Text { text: modelData.pos; font.pixelSize: 12; color: root.themeRoot.colText; Layout.preferredWidth: 180; elide: Text.ElideRight }
                                            Text { text: modelData.cur.toFixed(1) + "℃"; font.pixelSize: 14; font.bold: true; font.family: "monospace"; color: modelData.color; Layout.preferredWidth: 90 }
                                            Text { text: isNaN(modelData.max)?"—":modelData.max.toFixed(1); font.pixelSize: 12; color: root.themeRoot.colText2; Layout.preferredWidth: 70 }
                                            Text { text: isNaN(modelData.min)?"—":modelData.min.toFixed(1); font.pixelSize: 12; color: root.themeRoot.colText2; Layout.preferredWidth: 70 }
                                            Text { text: isNaN(modelData.avg)?"—":modelData.avg.toFixed(1); font.pixelSize: 12; color: root.themeRoot.colText2; Layout.preferredWidth: 70 }
                                            Item { Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // 时间对齐（宽表：每行一采样点、每列一探头，横向滚动）
                    Item {
                        visible: tmpRoot.stab === 1
                        Layout.fillWidth: true; Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            // 说明：时间列为相对采样时间（每点 1 秒），非系统时间
                            Text {
                                text: "时间列为相对采样时间（每点 1s），从本次打开温度监测起计数，非系统时钟"
                                font.pixelSize: 11; color: root.themeRoot.colText2
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 12
                                color: root.themeRoot.colCard2
                                border.color: root.themeRoot.colLine
                                clip: true
                                Flickable {
                                    anchors.fill: parent
                                    clip: true
                                    contentWidth: wideCanvas.width
                                    contentHeight: wideCanvas.height
                                    Canvas {
                                        id: wideCanvas
                                        width: 44 + 60 + root.probes.length * 46
                                        height: 30 + 60 * 24
                                        onPaint: { const ctx = getContext("2d"); root.drawTempWide(ctx, width, height) }
                                    }
                                }
                            }
                        }
                    }
                }

                // ===== 映射表（温度探头映射，可编辑 + 添加/删除）=====
                Item {
                    visible: tmpRoot.ttab === 2
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8
                        // 统计条 + 按钮（原型 .tt-stat）
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 10
                            color: root.themeRoot.colCard2
                            border.color: root.themeRoot.colLine
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 12
                                spacing: 14
                                Text { text: "探头 <b>" + root.probeCount() + "</b>"; font.pixelSize: 12; color: root.themeRoot.colText2; textFormat: Text.RichText }
                                Text { text: "物理编号保持不变，换板只需改「囊体 / 行 / 列」"; font.pixelSize: 12; color: root.themeRoot.colText2 }
                                Item { Layout.fillWidth: true }
                                Button {
                                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                    scale: pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    HoverHandler {
                                        id: hover_1
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    text: "＋ 添加探头"
                                    background: Rectangle {
                                        radius: 8; color: root.themeRoot.colCard2; border.color: (hover_1.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                    }
                                    contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.pixelSize: 12 }
                                    onClicked: root.addProbe()
                                }
                            }
                        }
                        // 表头
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            color: root.themeRoot.colCard2
                            border.color: root.themeRoot.colLine
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 12
                                spacing: 12
                                Text { text: "探头编号"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 90 }
                                Text { text: "囊体"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 150 }
                                Text { text: "行"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 60 }
                                Text { text: "列"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 60 }
                                Text { text: "基准温度 ℃"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 90 }
                                Text { text: "操作"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 60 }
                                Item { Layout.fillWidth: true }
                            }
                        }
                        // 数据行（可编辑）
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            radius: 12
                            color: root.themeRoot.colCard2
                            border.color: root.themeRoot.colLine
                            clip: true
                            ListView {
                                id: mappingList
                                anchors.fill: parent
                                model: root.probes
                                spacing: 0
                                delegate: Rectangle {
                                    width: ListView.view ? ListView.view.width : parent.width
                                    height: 46
                                    color: index % 2 === 0 ? "transparent" : root.themeRoot.colCard2
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12
                                        spacing: 12
                                        Text { text: modelData.pid; font.pixelSize: 13; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText; Layout.preferredWidth: 90 }
                                        ComboBox {
                                            HoverHandler {
                                                id: hover_2
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                            Layout.preferredWidth: 150
                                            model: root.envDef.map(e => e.name)
                                            currentIndex: modelData.ei
                                            onActivated: { modelData.ei = index; root.applyMapping() }
                                            font.pixelSize: 12
                                        }
                                        TextField {
                                            Layout.preferredWidth: 60
                                            text: modelData.row
                                            validator: IntValidator { bottom: 1; top: root.envDef[modelData.ei].rows }
                                            horizontalAlignment: Text.AlignHCenter
                                            font.pixelSize: 12
                                            onEditingFinished: {
                                                const v = parseInt(text)
                                                if (!isNaN(v)) { modelData.row = Math.max(1, Math.min(v, root.envDef[modelData.ei].rows)); root.applyMapping() }
                                                else text = modelData.row
                                            }
                                        }
                                        TextField {
                                            Layout.preferredWidth: 60
                                            text: modelData.col
                                            validator: IntValidator { bottom: 1; top: root.envDef[modelData.ei].cols }
                                            horizontalAlignment: Text.AlignHCenter
                                            font.pixelSize: 12
                                            onEditingFinished: {
                                                const v = parseInt(text)
                                                if (!isNaN(v)) { modelData.col = Math.max(1, Math.min(v, root.envDef[modelData.ei].cols)); root.applyMapping() }
                                                else text = modelData.col
                                            }
                                        }
                                        TextField {
                                            Layout.preferredWidth: 90
                                            text: modelData.base
                                            validator: IntValidator { bottom: 0; top: 80 }
                                            horizontalAlignment: Text.AlignHCenter
                                            font.pixelSize: 12
                                            onEditingFinished: {
                                                const v = parseInt(text)
                                                if (!isNaN(v)) { modelData.base = v; root.applyMapping() }
                                                else text = modelData.base
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
                                            text: "删除"
                                            Layout.preferredWidth: 60
                                            background: Rectangle { radius: 8; color: root.themeRoot.colErrSoft; border.color: root.themeRoot.colErr }
                                            contentItem: Text { text: parent.text; color: root.themeRoot.colErr; font.pixelSize: 12 }
                                            onClicked: root.removeProbe(modelData.pid)
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }
                            // 映射编辑后强制重建（数组引用变化才触发）
                            Connections {
                                target: root
                                function onMappingRefreshChanged() {
                                    mappingList.model = root.probes.slice()
                                }
                            }
                        }
                    }
                }
            }
            // 时间对齐宽表实时刷新（仅该子页可见时运行，省性能）
            Timer {
                interval: 1000
                running: root.treeNode === 1 && tmpRoot.ttab === 1 && tmpRoot.stab === 1
                repeat: true
                onTriggered: wideCanvas.requestPaint()
            }
        }
    }

    // ===== 实时曲线面板（QtCharts）=====
    Component {
        id: chartPanel
        Item {
            id: chartRoot
            // 曲线数据存于 themeRoot（main.qml 顶层 rtcData/rtcIdx），面板仅做展示与
            // 增量同步。顶层数据在 TopoView 被 Loader 销毁重建时仍保留，
            // 因此切出图示页再回来，曲线历史不丢、且全程持续采样。

            // 将 themeRoot.rtcData 的缺失点增量追加到 series，并同步 X 轴范围。
            // onCompleted 时 count=0，一次性补齐全部历史；此后每次 rtcTick 补一个新点。
            function syncSeries() {
                const R = root.themeRoot
                if (!R) return   // themeRoot 尚未注入（TopoView onLoaded 之前），跳过
                const n = R.rtcData.v.length
                // 顶层已 shift（超窗口上限）时，先移除 series 最前点保持对齐
                while (sVolt.count > n) {
                    sVolt.remove(0); sPv.remove(0); sOutp.remove(0); sI.remove(0)
                }
                const start = sVolt.count
                for (let k = start; k < n; k++) {
                    const x = R.rtcIdx - (n - 1 - k)
                    sVolt.append(x, R.rtcData.v[k])
                    sPv.append(x, R.rtcData.pv[k])
                    sOutp.append(x, R.rtcData.outp[k])
                    sI.append(x, R.rtcData.i[k])
                }
                cx2.min = Math.max(0, R.rtcIdx - R.rtcMax)
                cx2.max = R.rtcIdx
            }
            function clearCharts() {
                sVolt.clear(); sPv.clear(); sOutp.clear(); sI.clear()
                const R = root.themeRoot
                R.rtcData = ({"v":[], "pv":[], "outp":[], "i":[]})
                R.rtcIdx = 0
                cx2.min = 0; cx2.max = R.rtcMax
            }
            // 生成时间戳文件名后缀 YYYYMMDD_HHMMSS
            function ts() {
                const d = new Date()
                const p = n => (n < 10 ? "0" + n : n)
                return "" + d.getFullYear() + p(d.getMonth()+1) + p(d.getDate())
                     + "_" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds())
            }
            function exportSnapshot() {
                // 弹出系统"保存文件"对话框，让用户选择保存位置与文件名（默认 data/曲线快照/）
                snapFileDlg.currentFile = "file://" + bridge.snapshotDir()
                    + "/曲线快照_" + chartRoot.ts() + ".png"
                snapFileDlg.open()
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 8
                // 工具条
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 10
                    color: root.themeRoot.colCard2
                    border.color: root.themeRoot.colLine
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 10
                        spacing: 8
                        Text { text: "实时曲线"; font.bold: true; font.pixelSize: 14; color: root.themeRoot.colText }
                        Text { text: "点击图例可开关参数"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                        Item { Layout.fillWidth: true }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_4
                                cursorShape: Qt.PointingHandCursor
                            }
                            id: pauseBtn
                            text: "⏸ 暂停"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_4.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12 }
                            onClicked: {
                                root.themeRoot.rtcPlaying = !root.themeRoot.rtcPlaying
                                pauseBtn.text = root.themeRoot.rtcPlaying ? "⏸ 暂停" : "▶ 继续"
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
                            text: "清屏"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_5.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12 }
                            onClicked: { chartRoot.clearCharts(); root.showNote("已清屏") }
                        }
                        Button {
                            // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                            scale: pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                            HoverHandler {
                                id: hover_6
                                cursorShape: Qt.PointingHandCursor
                            }
                            text: "导出快照"
                            background: Rectangle {
                                radius: 8; color: root.themeRoot.colCard2; border.color: (hover_6.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.pixelSize: 12 }
                            onClicked: chartRoot.exportSnapshot()
                        }
                    }
                }
                // 图例 + 曲线
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: root.themeRoot.colCard2
                    border.color: root.themeRoot.colLine
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8
                        spacing: 6
                        Row {
                            spacing: 16
                            Repeater {
                                model: [["BMS总压","#2563eb"],["光伏功率","#16a34a"],["输出功率","#f59e0b"],["总电流","#06b6d4"]]
                                Row {
                                    spacing: 6
                                    Rectangle { width: 14; height: 3; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: modelData[1] }
                                    Text { text: modelData[0]; font.pixelSize: 12; color: root.themeRoot.colText2; font.weight: Font.DemiBold }
                                }
                            }
                        }
                        ChartView {
                            id: chartView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            antialiasing: true
                            backgroundColor: "transparent"
                            legend.visible: false
                            ValueAxis { id: cx2; min: 0; max: 100; labelFormat: "%d"; titleText: "采样点" }
                            ValueAxis { id: cy2; min: 0; max: 700; titleText: "数值" }
                            LineSeries { id: sVolt; name: "BMS总压"; axisX: cx2; axisY: cy2; color: "#2563eb"; width: 2 }
                            LineSeries { id: sPv; name: "光伏功率"; axisX: cx2; axisY: cy2; color: "#16a34a"; width: 2 }
                            LineSeries { id: sOutp; name: "输出功率"; axisX: cx2; axisY: cy2; color: "#f59e0b"; width: 2 }
                            LineSeries { id: sI; name: "总电流"; axisX: cx2; axisY: cy2; color: "#06b6d4"; width: 2 }
                        }
                    }
                }
            }
            // 采样由 main.qml 顶层 Timer 常驻驱动（无论在哪页都持续采样）；
            // 面板监听 themeRoot.rtcTick 增量追加，并在重建时补齐既有历史。
            Connections {
                target: root.themeRoot
                function onRtcTickChanged() { chartRoot.syncSeries() }
            }
            Component.onCompleted: chartRoot.syncSeries()
            // 监听快照保存请求，导出当前曲线图片（白色背景）
            Connections {
                target: root
                function onSnapSave(fileUrl) {
                    // 用户选择的文件路径（去掉 file:// 前缀，补齐 .png 后缀）
                    let path = fileUrl.toString().replace(/^file:\/\//, "")
                    if (!/\.png$/i.test(path)) path += ".png"
                    const savedBg = chartView.backgroundColor
                    chartView.backgroundColor = "white"
                    chartView.grabToImage(function(result) {
                        chartView.backgroundColor = savedBg
                        const ok = result.saveToFile(path)
                        root.showNote(ok ? "已导出快照：" + path : "导出失败")
                    })
                }
            }
        }
    }

    // ===== 探头详情弹窗（点击热力图方块弹出）=====
    Popup {
        id: probeDetail
        property color detailColor: "#3b82f6"
        anchors.centerIn: parent
        width: 340
        padding: 16
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: root.themeRoot.colCard; border.color: root.themeRoot.colLine; radius: 14 }
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
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Text {
                id: probeDetailPid
                font.bold: true; font.pixelSize: 15; color: root.themeRoot.colText
                Layout.fillWidth: true; wrapMode: Text.Wrap
            }
            Row {
                spacing: 16
                Column { spacing: 4; width: 100
                    Text { text: "当前温度"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                    Text { id: probeDetailCur; font.pixelSize: 22; font.bold: true; font.family: "monospace"; color: probeDetail.detailColor }
                }
                Column { spacing: 4; width: 120
                    Text { text: "区间(高/低)"; font.pixelSize: 11; color: root.themeRoot.colText2 }
                    Text { id: probeDetailRange; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.themeRoot.colLine }
            Text {
                text: "提示：探头物理编号保持不变，位置在「探头映射」页可调整，换板不换编号历史数据连续。"
                font.pixelSize: 11; color: root.themeRoot.colText2
                Layout.fillWidth: true; wrapMode: Text.Wrap
            }
            Button {
                // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                scale: pressed ? 0.94 : 1.0
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                HoverHandler {
                    id: hover_7
                    cursorShape: Qt.PointingHandCursor
                }
                text: "关闭"
                Layout.alignment: Qt.AlignRight
                background: Rectangle {
                    radius: 8; color: root.themeRoot.colCard2; border.color: (hover_7.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }
                contentItem: Text { text: parent.text; color: root.themeRoot.colText2; font.pixelSize: 12 }
                onClicked: probeDetail.close()
            }
        }
    }

    // 曲线快照导出：调用系统"保存文件"对话框（导出的是文件，非目录选择）
    FileDialog {
        id: snapFileDlg
        title: "导出曲线快照"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG 图片 (*.png)"]
        defaultSuffix: "png"
        onAccepted: root.snapSave(selectedFile)
    }

    // 初始化：加载探头映射后重建查表索引 + 初始化探头行 model
    Component.onCompleted: {
        root.rebuildCellIndex()
        root.rebuildProbeRows()
    }

    // 周期刷新：温度探头数值演化 + 曲线数据采样（仅温度监测/实时曲线页需要）
    Timer {
        interval: 1000
        running: root.treeNode !== 0
        repeat: true
        onTriggered: {
            // 温度探头：在基准附近小幅波动，并维护历史（环形 180）
            for (const p of root.probes) {
                const k = p.pid
                const base = root.pvVals[k] != null ? root.pvVals[k] : p.base
                const next = base + (Math.random()-0.5)*0.7
                root.pvVals[k] = next
                const h = root.pvHist[k] || []
                h.push(next)
                if (h.length > 180) h.shift()
                root.pvHist[k] = h
            }
            // 探头数据表 · 增量更新（in-place，不重建 delegate）
            root.updateProbeRows()
            root.themeRoot.dataTick++
        }
    }
}

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
    function tPv()  { void root.themeRoot.dataTick; return root.off("mppt1") ? 0 : Math.round(bridge.value("mppt1","pv_p")||0) }
    function tPvV() { void root.themeRoot.dataTick; return root.off("mppt1") ? 0 : (bridge.value("mppt1","pv_v")||0) }
    function tCi()  { void root.themeRoot.dataTick; return root.off("mppt1") ? 0 : (bridge.value("mppt1","charge_i")||0) }
    function tSoc() { void root.themeRoot.dataTick; return root.off("bms") ? 0 : Math.round(bridge.value("bms","soc")||0) }
    function tPackV(){void root.themeRoot.dataTick; return root.off("bms") ? 0 : (bridge.value("bms","pack_v")||0) }
    function tOut() { void root.themeRoot.dataTick; return root.off("dcdc") ? 0 : Math.round(bridge.value("dcdc","out_p")||0) }
    function tTemp(){ void root.themeRoot.dataTick; return root.off("dcdc") ? 0 : (bridge.value("dcdc","temp")||0) }
    function off(dev) { return !bridge.online(dev) }
    // 电源链路完整数据（对齐原型 updateTopo）：真实字段 + 模拟派生（12S/电机/效率），MPPT1/MPPT2 均对接真实设备
    function topoData() {
        void root.themeRoot.dataTick
        const now = Date.now()
        const pvM  = root.off("mppt1") ? 0 : Math.round(bridge.value("mppt1","pv_p")||0)
        const pvMv = root.off("mppt1") ? 0 : (bridge.value("mppt1","pv_v")||0)
        const c1   = root.off("mppt1") ? 0 : (bridge.value("mppt1","charge_i")||0)
        // 光伏副囊/MPPT2（mppt2 真实数据）
        const pvS  = root.off("mppt2") ? 0 : Math.round(bridge.value("mppt2","pv_p")||0)
        const pvSv = root.off("mppt2") ? 0 : (bridge.value("mppt2","pv_v")||0)
        const c2   = root.off("mppt2") ? 0 : (bridge.value("mppt2","charge_i")||0)
        const pv   = pvM + pvS
        const soc  = root.off("bms") ? 0 : (bridge.value("bms","soc")||0)
        const packv= root.off("bms") ? 0 : (bridge.value("bms","pack_v")||0)
        const packi= root.off("bms") ? 0 : (bridge.value("bms","pack_i")||0)
        const op   = root.off("dcdc") ? 0 : Math.round(bridge.value("dcdc","out_p")||0)
        const outv = root.off("dcdc") ? 0 : (bridge.value("dcdc","out_v")||0)
        const temp = root.off("dcdc") ? 0 : (bridge.value("dcdc","temp")||0)
        // MPPT 转换效率 / 12S 备用锂电（原型模拟）
        const eff = 92 + Math.round(Math.sin(now/12000)*3)
        const bkSoc = Math.round(86 + Math.sin(now/8000)*3)
        const bkV   = 44 + Math.sin(now/7000)*0.8
        // 第一级混动（MPPT1+MPPT2 并联 + 102S）
        const motTot = Math.round(pv*0.45 + 120)
        const mot1   = Math.round(motTot/4)
        const bus1Load = motTot + op
        const bat1   = Math.round(pv - bus1Load)   // >0 富余充电 / <0 放电补足
        // 第二级混动（DCDC + 12S）
        const smTot = Math.round(op*0.5)
        const sm1   = Math.round(smTot/6)
        const load48= Math.max(0, op - smTot)
        const dcdcCap = 320
        const bat2  = Math.round(dcdcCap - op)
        // 电机转速（原型模拟）
        const rpmMot = Math.round(280 + mot1*0.6 + Math.sin(now/6000)*25)
        const rpmUp  = Math.round(1800 + Math.sin(now/7000)*80)
        const rpmDn  = Math.round(1200 + Math.sin(now/8000)*60)
        return {pvM,pvMv,pvS,pvSv,c1,c2,pv,soc,packv,packi,op,outv,temp,eff,bkSoc,bkV,
                motTot,mot1,bus1Load,bat1,smTot,sm1,load48,dcdcCap,bat2,rpmMot,rpmUp,rpmDn}
    }
    // 电源链路节点悬停详情（对齐原型 tpTitle，\n 换行多行提示）
    function topoHover(id) {
        const d = root.topoData()
        switch (id) {
            case "pv1": return "光伏主囊\n功率 " + d.pvM + " W\n电压 " + d.pvMv.toFixed(1) + " V\n向 MPPT 1 供电"
            case "pv2": return "光伏副囊\n功率 " + d.pvS + " W\n电压 " + d.pvSv.toFixed(1) + " V\n向 MPPT 2 供电"
            case "mppt1": return "MPPT 1\n光伏输入 " + d.pvM + " W\n充电电流 " + d.c1.toFixed(1) + " A\n转换效率 " + d.eff + "%"
            case "mppt2": return "MPPT 2\n光伏输入 " + d.pvS + " W\n充电电流 " + d.c2.toFixed(1) + " A\n转换效率 " + d.eff + "%"
            case "bms": return "102S 主电池组\n荷电状态 SOC " + Math.round(d.soc) + "%\n总压 " + d.packv.toFixed(1) + " V\n总电流 " + d.packi.toFixed(1) + " A"
            case "mot1": case "mot2": case "mot3": case "mot4": {
                const name = ["左前","左后","右后","右前"][parseInt(id.slice(3),10)-1]
                return "推进电机 · " + name + "\n功率 " + d.mot1 + " W\n转速 " + Math.round(d.rpmMot) + " rpm"
            }
            case "dcdc": return "DCDC 模块\n输出功率 " + d.op + " W\n输出电压 " + d.outv.toFixed(1) + " V\n散热温度 " + d.temp.toFixed(1) + " ℃"
            case "bk": return "12S 备用锂电\n荷电状态 " + d.bkSoc + "%\n电压 " + d.bkV.toFixed(1) + " V\n与 DCDC 构成 48V 混动"
            case "s1": return "左前上升电机\n转速 " + Math.round(d.rpmUp) + " rpm\n由 48V 母线供电"
            case "s2": return "左后上升电机\n转速 " + Math.round(d.rpmUp) + " rpm\n由 48V 母线供电"
            case "s3": return "前下降电机\n转速 " + Math.round(d.rpmDn) + " rpm\n由 48V 母线供电"
            case "load": return "其他载荷\n功率 " + d.load48 + " W\n48V 弱电负载"
            case "s4": return "后下降电机\n转速 " + Math.round(d.rpmDn) + " rpm\n由 48V 母线供电"
            case "s5": return "右后上升电机\n转速 " + Math.round(d.rpmUp) + " rpm\n由 48V 母线供电"
            case "s6": return "右前上升电机\n转速 " + Math.round(d.rpmUp) + " rpm\n由 48V 母线供电"
        }
        return ""
    }

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
    property real lastSampleTs: 0    // 最近一次温度采样时刻（时间对齐表本地时间基准）
    property var probeLive: new Object()  // pid -> bool（本轮采样拿到实机温度）
    property real envPresPa: NaN         // LoRa 压力节点实时均值（Pa），无压力节点为 NaN
    property var cellIndex: new Object()   // "ei:r:c" -> probe（热力图 O(1) 查表）
    property int mappingRefresh: 0   // 探头映射编辑后自增，强制刷新映射表
    property int _diagTs: 0          // 临时诊断：上次打印 [TopoDiag] 日志的时间戳
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
    // 仅"本轮拿到实机温度"（probeLive）的格子显示热力色与数值；无实机数据的格子显示背景色
    // 空白，不再用基准 base 值（如 45℃）冒充真实温度
    function cellColor(ei, cols, idx) {
        void root.themeRoot.dataTick
        const r = Math.floor(idx / cols) + 1
        const c = idx % cols + 1
        const p = root.cellIndex[ei + ":" + r + ":" + c]
        if (p && root.probeLive[p.pid] === true && root.pvVals[p.pid] != null)
            return root.pvColor(root.pvVals[p.pid])
        return root.themeRoot.colBg2
    }
    function cellText(ei, cols, idx) {
        void root.themeRoot.dataTick
        const r = Math.floor(idx / cols) + 1
        const c = idx % cols + 1
        const p = root.cellIndex[ei + ":" + r + ":" + c]
        if (p && root.probeLive[p.pid] === true && root.pvVals[p.pid] != null)
            return String(Math.round(root.pvVals[p.pid]))
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
        const v = (root.probeLive[p.pid] === true && root.pvVals[p.pid] != null) ? root.pvVals[p.pid] : p.base
        const hist = root.pvHist[p.pid] || []
        const hi = hist.length ? Math.max(...hist) : NaN
        const lo = hist.length ? Math.min(...hist) : NaN
        probeDetailPid.text = p.pid + " · " + env.name + " 第" + p.row + "行 第" + p.col + "列"
        probeDetailCur.text = v.toFixed(1) + " ℃"
        probeDetailRange.text = (isNaN(hi)?"—":hi.toFixed(0)) + " / " + (isNaN(lo)?"—":lo.toFixed(0)) + " ℃"
        probeDetailSrc.text = root.probeLive[p.pid]
            ? "数据来源：实机采集（LoRa 节点 " + String(p.pid).replace(/^T/i, "") + " 在线）"
            : "数据来源：基准值（节点离线或未绑定，基准 " + p.base + "℃）"
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
        // themeRoot 可能尚未注入（Component.onCompleted 时），空守卫避免 null 访问
        const idleColor = root.themeRoot ? root.themeRoot.colText2 : "#888888"
        for (const p of root.probes) {
            const env = root.envDef[p.ei]
            model.push({
                pid: p.pid,
                pos: env.name.split("·")[0].trim() + " · " + p.row + "行" + p.col + "列",
                cur: NaN, max: NaN, min: NaN, avg: NaN,
                color: idleColor,
                live: root.probeLive[p.pid] === true,
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
            const v = (root.probeLive[pid] === true && root.pvVals[pid] != null) ? root.pvVals[pid] : NaN
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
            r.color = !isNaN(v) ? root.pvColor(v) : root.themeRoot.colText2
            r.live = root.probeLive[pid] === true
        }
        root.probeModelPoke = (root.probeModelPoke + 1) % 1000000
    }
    property int probeModelPoke: 0
    function probeCount() { return root.probes.length }
    function probeStats() {
        void root.themeRoot.dataTick
        let mx = -Infinity, sum = 0, alarm = 0, cnt = 0
        for (const p of root.probes) {
            if (root.probeLive[p.pid] !== true || root.pvVals[p.pid] == null) continue
            const v = root.pvVals[p.pid]
            sum += v; cnt++; if (v > mx) mx = v; if (v > 60) alarm++
        }
        return {count:cnt, max: mx>-Infinity?mx:NaN, avg: cnt?sum/cnt:NaN, alarm:alarm}
    }
    // 囊体内部温度（实机）：该囊体在线探头的实时均值；无实机数据回退 envDef 静态基准
    function envInnerT(ei) {
        void root.themeRoot.dataTick
        let sum = 0, cnt = 0
        for (const p of root.probes) {
            if (p.ei !== ei) continue
            if (root.probeLive[p.pid] && root.pvVals[p.pid] != null) { sum += root.pvVals[p.pid]; cnt++ }
        }
        return cnt > 0 ? sum / cnt : root.envDef[ei].innerT
    }
    // 囊体内部压力（实机）：LoRa 压力节点实时均值（Pa→kPa）；无压力节点回退 envDef 静态基准
    function envPresKpa(ei) {
        void root.themeRoot.dataTick
        return !isNaN(root.envPresPa) ? root.envPresPa / 1000 : root.envDef[ei].pres
    }
    // ===== 探头映射编辑（原型 applyProbes 逻辑）=====
    // 注意：delegate 中 modelData 是数组元素的私有拷贝（JS Array 不支持写回），
    // 所有编辑必须经 root 层函数按 pid 定位修改 root.probes 原对象，再 applyMapping。
    function setProbeEi(pid, ei) {
        const p = root.probeOf(pid)
        if (!p) return
        p.ei = ei
        // 对齐原型：切换囊体后行/列钳制到新囊体范围，避免越界从热力图消失
        const env = root.envDef[ei]
        if (p.row > env.rows) p.row = env.rows
        if (p.col > env.cols) p.col = env.cols
        root.applyMapping()
    }
    function setProbeNum(pid, field, v, lo, hi) {
        const p = root.probeOf(pid)
        if (!p || isNaN(v)) return
        p[field] = Math.max(lo, Math.min(v, hi))
        root.applyMapping()
    }
    function renameProbe(oldPid, newText) {
        let t = String(newText).trim().toUpperCase()
        if (t.indexOf("T") !== 0) t = "T" + t
        const num = parseInt(t.replace(/^T/, ""), 10)
        if (isNaN(num) || num < 1 || num > 99) { root.showNote("编号需为 T+节点号（1-99）"); return false }
        t = "T" + (num < 10 ? "0" + num : "" + num)   // 统一两位格式，与默认 T01~T44 一致
        if (t === oldPid) return true
        if (root.probeOf(t)) { root.showNote("编号 " + t + " 已存在，需唯一"); return false }
        const p = root.probeOf(oldPid)
        if (!p) return false
        p.pid = t
        // 运行时数据迁移到新编号
        if (root.pvVals[oldPid] != null) { root.pvVals[t] = root.pvVals[oldPid]; delete root.pvVals[oldPid] }
        if (root.pvHist[oldPid] != null) { root.pvHist[t] = root.pvHist[oldPid]; delete root.pvHist[oldPid] }
        if (root.probeLive[oldPid] !== undefined) { root.probeLive[t] = root.probeLive[oldPid]; delete root.probeLive[oldPid] }
        root.applyMapping()
        return true
    }
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
    // 从实机同步：按 LoRa 在线温度节点对齐探头列表（pid=T+节点id，两位补零与默认布局一致）。
    // 已有探头保留位置；缺失的添加（铺到主囊·左）；无实机对应的移除。
    function syncFromLora() {
        const lora = bridge.loraNodes()
        const temps = []
        for (const n of lora) if (n.isTemp) temps.push(n)
        if (!temps.length) { root.showNote("未检测到实机温度节点，请检查采集链路"); return }
        // pid 统一两位补零（T01~T44），与 defaultProbeMapping 的 rightJustified(2,'0') 对齐，
        // 否则 "T1" 与已有 "T01" 匹配失败，会导致全部探头被误删重建、布局丢失
        const pad = id => "T" + String(id).padStart(2, "0")
        const want = new Set(temps.map(n => pad(n.id)))
        let removed = 0
        root.probes = root.probes.filter(p => {
            if (want.has(p.pid)) return true
            removed++
            delete root.pvVals[p.pid]
            delete root.pvHist[p.pid]
            return false
        })
        let added = 0
        for (const n of temps) {
            const pid = pad(n.id)
            if (root.probeOf(pid)) continue
            // 新探头依次铺到主囊·左（ei=1，9列×13行），从第2行2列起每行3个
            const seq = root.probes.filter(p => p.ei === 1).length
            root.probes.push({
                pid: pid, ei: 1,
                row: Math.min(2 + Math.floor(seq / 3), root.envDef[1].rows),
                col: Math.min(2 + (seq % 3), root.envDef[1].cols),
                base: 45
            })
            added++
        }
        root.applyMapping()
        root.showNote("已同步实机节点：保留 " + (temps.length - added) + " · 新增 " + added + " · 移除 " + removed)
    }
    // 恢复默认探头布局（对齐原型 mpReset），同时清空运行时数据
    function resetProbesDefault() {
        bridge.resetProbeMapping()
        root.probes = root.loadProbes()
        root.pvVals = new Object()
        root.pvHist = new Object()
        root.probeLive = new Object()
        root.applyMapping()
        root.showNote("已恢复探头默认布局")
    }
    // 颜色 hex → rgba（用于宽表背景半透明）
    function hexRgba(hex, a) {
        return "rgba(" + parseInt(hex.slice(1,3),16) + "," + parseInt(hex.slice(3,5),16) + ","
                     + parseInt(hex.slice(5,7),16) + "," + a + ")"
    }
    // 时间戳 → 本地 HH:mm:ss（时间对齐表时间列用）
    function fmtClock(ts) {
        const d = new Date(ts)
        const p = n => (n < 10 ? "0" + n : n)
        return p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
    }
    // 时间对齐宽表绘制（原型 updateTempWide，60 行 × 探头数）
    function drawTempWide(ctx, W, H) {
        ctx.reset()
        const idxW = 44, timeW = 70, colW = 46, headerH = 30, rowH = 24
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
        ctx.fillText("时间", idxW + timeW/2, headerH/2)
        for (let c = 0; c < n; c++) ctx.fillText(probes[c].pid, idxW + timeW + c*colW + colW/2, headerH/2)
        // 数据行
        const WIDE_ROWS = 60
        // 每点采样间隔：温度监测 1s/点（与温度采样 Timer interval 一致）；
        // 时间列为本地时间：由最近采样时刻反推（最新点=lastSampleTs，向前每行 -1s）
        const ROW_MS = 1000
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
            const tOk = idx >= 0 && idx < minLen && root.lastSampleTs > 0
            ctx.fillText(tOk ? root.fmtClock(root.lastSampleTs - (minLen - 1 - idx) * ROW_MS) : "—",
                         idxW + timeW/2, y + rowH/2)
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

    // ===== 电源链路拓扑（对齐原型：两域五五分 + 双母线 + 18 节点 + 连线动画 + 缩放 + 悬停）=====
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
                // 拓扑 Canvas（逻辑坐标 1200×820，缩放映射铺满，对齐原型 relayoutTopo）
                Canvas {
                    id: topoCanvas
                    anchors.fill: parent
                    anchors.topMargin: 44   // 给顶部图例留位
                    // ---- 缩放映射状态 ----
                    property real _sx: 1
                    property real _sy: 1
                    property real _sc: 1
                    property real _hvH: 0    // 高压域高
                    property real _wvH: 0    // 弱电域高
                    property real _offY: 0   // 弱电域起始 y
                    property real flowOff: 0   // 普通线流动偏移（像素）
                    property real flowOffBi: 0 // 双向线流动偏移
                    property string hoverId: ""    // 悬停节点 id
                    property string hoverText: ""  // 悬停详情文本

                    // 虚线流动动画（对齐原型 @keyframes flow 1s / flow-bi 1.2s）
                    Timer {
                        interval: 50; repeat: true; running: topoCanvas.visible
                        onTriggered: {
                            topoCanvas.flowOff = (topoCanvas.flowOff + 0.7) % 14
                            topoCanvas.flowOffBi = (topoCanvas.flowOffBi + 0.333) % 8
                            topoCanvas.requestPaint()
                        }
                    }

                    // 重排：两域五五分 + 各轴独立等比（对应原型 relayoutTopo）
                    function relayout() {
                        const W = topoCanvas.width, H = topoCanvas.height
                        const m = 10, gap = 5
                        const availH = H - 2*m - gap
                        topoCanvas._hvH = Math.round(availH/2)
                        topoCanvas._wvH = availH - topoCanvas._hvH
                        topoCanvas._offY = m + topoCanvas._hvH + gap
                        topoCanvas._sx = (W - 2*m) / 1180
                        topoCanvas._sy = (H - 2*m - gap) / 800
                        topoCanvas._sc = Math.max(0.3, Math.min(topoCanvas._sx, topoCanvas._sy))
                    }
                    function mx(bx) { return 10 + (bx-10)*topoCanvas._sx }
                    function my(by) { return by<=408 ? 10+(by-10)/398*topoCanvas._hvH : topoCanvas._offY + (by-413)/397*topoCanvas._wvH }
                    function cw(v) { return v * topoCanvas._sc }
                    function cfs(v) { return Math.max(8, Math.round(v * topoCanvas._sc)) }

                    onWidthChanged: { relayout(); requestPaint() }
                    onHeightChanged: { relayout(); requestPaint() }
                    Component.onCompleted: relayout()

                    // 节点逻辑表 [id, 中心x, 中心y, 宽, 高]（对齐原型 TOPO_BASE.nodes）
                    readonly property var _nodes: [
                        {id:"pv1", x:150, y:95, w:150, h:90}, {id:"pv2", x:1050, y:95, w:150, h:90},
                        {id:"mppt1", x:375, y:95, w:150, h:90}, {id:"mppt2", x:825, y:95, w:150, h:90},
                        {id:"bms", x:600, y:95, w:150, h:90},
                        {id:"mot1", x:86, y:323, w:150, h:90}, {id:"mot2", x:429, y:323, w:150, h:90},
                        {id:"mot3", x:771, y:323, w:150, h:90}, {id:"mot4", x:1114, y:323, w:150, h:90},
                        {id:"dcdc", x:515, y:498, w:150, h:90}, {id:"bk", x:685, y:498, w:150, h:90},
                        {id:"s1", x:121, y:725, w:140, h:90}, {id:"s2", x:279, y:725, w:140, h:90},
                        {id:"s3", x:437, y:725, w:140, h:90}, {id:"load", x:600, y:725, w:150, h:90},
                        {id:"s4", x:763, y:725, w:140, h:90}, {id:"s5", x:921, y:725, w:140, h:90},
                        {id:"s6", x:1079, y:725, w:140, h:90}
                    ]
                    // 连线逻辑表 [id,x1,y1,x2,y2, 标注x,标注y, bi双向]（对齐原型 links）
                    readonly property var _links: [
                        {id:"l1a", x1:225,y1:95,x2:300,y2:95, tx:263,ty:90, bi:false},
                        {id:"l1b", x1:975,y1:95,x2:900,y2:95, tx:938,ty:90, bi:false},
                        {id:"l2a", x1:375,y1:140,x2:375,y2:209, tx:380,ty:175, bi:false},
                        {id:"lb1", x1:600,y1:140,x2:600,y2:209, tx:605,ty:175, bi:true},
                        {id:"l2b", x1:825,y1:140,x2:825,y2:209, tx:830,ty:175, bi:false},
                        {id:"l3a", x1:86,y1:209,x2:86,y2:278, tx:91,ty:244, bi:false},
                        {id:"l3b", x1:429,y1:209,x2:429,y2:278, tx:434,ty:244, bi:false},
                        {id:"l3c", x1:771,y1:209,x2:771,y2:278, tx:776,ty:244, bi:false},
                        {id:"l3d", x1:1114,y1:209,x2:1114,y2:278, tx:1119,ty:244, bi:false},
                        {id:"l4", x1:515,y1:209,x2:515,y2:453, tx:520,ty:331, bi:false},
                        {id:"l5", x1:515,y1:543,x2:515,y2:611, tx:520,ty:577, bi:false},
                        {id:"lb2", x1:685,y1:543,x2:685,y2:611, tx:690,ty:577, bi:true},
                        {id:"l6a", x1:121,y1:611,x2:121,y2:680, tx:126,ty:646, bi:false},
                        {id:"l6b", x1:279,y1:611,x2:279,y2:680, tx:284,ty:646, bi:false},
                        {id:"l6c", x1:437,y1:611,x2:437,y2:680, tx:442,ty:646, bi:false},
                        {id:"l7", x1:600,y1:611,x2:600,y2:680, tx:605,ty:646, bi:false},
                        {id:"l6d", x1:763,y1:611,x2:763,y2:680, tx:768,ty:646, bi:false},
                        {id:"l6e", x1:921,y1:611,x2:921,y2:680, tx:926,ty:646, bi:false},
                        {id:"l6f", x1:1079,y1:611,x2:1079,y2:680, tx:1084,ty:646, bi:false}
                    ]
                    // 母线连接点 x 与 y（对齐原型 busJ/busY）
                    readonly property var _bus1J: [86,375,429,515,600,771,825,1114]
                    readonly property var _bus2J: [121,279,437,515,600,685,763,921,1079]
                    readonly property real _bus1Y: 209
                    readonly property real _bus2Y: 611
                    // 手动圆角矩形路径（兼容无 roundRect 的 Qt）
                    function rrect(ctx, x, y, w, h, r) {
                        ctx.beginPath()
                        ctx.moveTo(x+r, y)
                        ctx.arcTo(x+w, y, x+w, y+h, r)
                        ctx.arcTo(x+w, y+h, x, y+h, r)
                        ctx.arcTo(x, y+h, x, y, r)
                        ctx.arcTo(x, y, x+w, y, r)
                        ctx.closePath()
                    }
                    // 简化图标绘制（对齐原型 node-ic，16px 描边）
                    function drawIcon(ctx, type, cx, cy, s) {
                        ctx.save()
                        ctx.strokeStyle = ctx.strokeStyle
                        ctx.lineWidth = Math.max(1.2, 1.8*s)
                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                        ctx.beginPath()
                        if (type === "sun") {
                            ctx.arc(cx, cy, 5*s, 0, Math.PI*2)
                            for (let i=0;i<8;i++) { const a=i*Math.PI/4; ctx.moveTo(cx+7*s*Math.cos(a), cy+7*s*Math.sin(a)); ctx.lineTo(cx+9*s*Math.cos(a), cy+9*s*Math.sin(a)) }
                        } else if (type === "bolt") {
                            ctx.moveTo(cx+3*s, cy-8*s); ctx.lineTo(cx-4*s, cy+1*s); ctx.lineTo(cx-1*s, cy+1*s); ctx.lineTo(cx-3*s, cy+8*s); ctx.lineTo(cx+4*s, cy-1*s); ctx.lineTo(cx+1*s, cy-1*s)
                        } else if (type === "bat") {
                            ctx.rect(cx-8*s, cy-7*s, 16*s, 14*s)
                            ctx.moveTo(cx+8*s, cy-4*s); ctx.lineTo(cx+10*s, cy-4*s); ctx.lineTo(cx+10*s, cy+4*s); ctx.lineTo(cx+8*s, cy+4*s)
                            ctx.moveTo(cx-4*s, cy-4*s); ctx.lineTo(cx-4*s, cy+0); ctx.moveTo(cx, cy-3*s); ctx.lineTo(cx, cy+1*s); ctx.moveTo(cx+4*s, cy-4*s); ctx.lineTo(cx+4*s, cy+0)
                        } else if (type === "mH") { // 推进电机（水平箭头）
                            ctx.arc(cx, cy, 7*s, 0, Math.PI*2)
                            ctx.moveTo(cx+2*s, cy-4*s); ctx.lineTo(cx+9*s, cy); ctx.lineTo(cx+2*s, cy+4*s); ctx.moveTo(cx+6*s, cy-2*s); ctx.lineTo(cx+9*s, cy); ctx.lineTo(cx+6*s, cy+2*s)
                        } else if (type === "mV") { // 上升电机（上下箭头）
                            ctx.arc(cx, cy, 7*s, 0, Math.PI*2)
                            ctx.moveTo(cx-4*s, cy+2*s); ctx.lineTo(cx, cy-9*s); ctx.lineTo(cx+4*s, cy+2*s); ctx.moveTo(cx-2*s, cy+7*s); ctx.lineTo(cx, cy+9*s); ctx.lineTo(cx+2*s, cy+7*s)
                        } else if (type === "mD") { // 下降电机
                            ctx.arc(cx, cy, 7*s, 0, Math.PI*2)
                            ctx.moveTo(cx-4*s, cy-2*s); ctx.lineTo(cx, cy+9*s); ctx.lineTo(cx+4*s, cy-2*s); ctx.moveTo(cx-2*s, cy-7*s); ctx.lineTo(cx, cy-9*s); ctx.lineTo(cx+2*s, cy-7*s)
                        } else if (type === "gear") { // 其他载荷
                            ctx.arc(cx, cy, 8*s, 0, Math.PI*2)
                            for (let i=0;i<6;i++) { const a=i*Math.PI/3; ctx.moveTo(cx+8*s*Math.cos(a), cy+8*s*Math.sin(a)); ctx.lineTo(cx+10*s*Math.cos(a), cy+10*s*Math.sin(a)) }
                        }
                        ctx.stroke()
                        ctx.restore()
                    }
                    // 悬停命中检测：鼠标相对坐标 → 节点 id
                    function updateHover(mxPos, myPos) {
                        for (const n of topoCanvas._nodes) {
                            const x0 = topoCanvas.mx(n.x - n.w/2), y0 = topoCanvas.my(n.y - n.h/2)
                            const w = n.w*topoCanvas._sc, h = n.h*topoCanvas._sc
                            if (mxPos>=x0 && mxPos<=x0+w && myPos>=y0 && myPos<=y0+h) {
                                if (topoCanvas.hoverId !== n.id) {
                                    topoCanvas.hoverId = n.id
                                    topoCanvas.hoverText = root.topoHover(n.id)
                                }
                                return
                            }
                        }
                        if (topoCanvas.hoverId !== "") { topoCanvas.hoverId = ""; topoCanvas.hoverText = "" }
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const T = root.themeRoot
                        const D = root.topoData()
                        const dcdcOff = root.off("dcdc"), bmsOff = root.off("bms"), mpptOff = root.off("mppt1")
                        const sc = topoCanvas._sc

                        // ===== 两域灰框（五五分 + 四边距 10px + 虚线框 + 标题）=====
                        ctx.setLineDash([6*sc, 5*sc])
                        ctx.lineWidth = 1.5*sc
                        ctx.fillStyle = T.colCard2
                        ctx.strokeStyle = T.colLine
                        // 高压域
                        topoCanvas.rrect(ctx, topoCanvas.mx(10), topoCanvas.my(10), (topoCanvas.width-20), topoCanvas._hvH, 8)
                        ctx.fill(); ctx.stroke()
                        ctx.setLineDash([])
                        ctx.fillStyle = T.colText2
                        ctx.font = "700 " + topoCanvas.cfs(13) + "px sans-serif"
                        ctx.textAlign = "left"; ctx.textBaseline = "alphabetic"
                        ctx.fillText("高压直流域", topoCanvas.mx(26), topoCanvas.my(34))
                        // 弱电域（注意：上文标题已把 fillStyle 设为文字色，填充前必须重置回卡片底色）
                        ctx.setLineDash([6*sc, 5*sc])
                        ctx.fillStyle = T.colCard2
                        topoCanvas.rrect(ctx, topoCanvas.mx(10), topoCanvas._offY, (topoCanvas.width-20), topoCanvas._wvH, 8)
                        ctx.fill(); ctx.stroke()
                        ctx.setLineDash([])
                        ctx.fillText("48V 弱电域", topoCanvas.mx(26), topoCanvas.my(437))

                        // ===== 母线带（粗线 + 连接圆点 + 标签）=====
                        // 必须先于连线绘制：连线箭头指向母线连接点，后画的 joint 会盖住箭头
                        // （对齐原型 SVG：zone → bus/joint → links → nodes）
                        function bus(y, js, tag, tagX, tagY) {
                            ctx.strokeStyle = T.colPrimary
                            ctx.lineWidth = Math.max(2, 5*sc)
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(topoCanvas.mx(js[0]), topoCanvas.my(y))
                            ctx.lineTo(topoCanvas.mx(js[js.length-1]), topoCanvas.my(y))
                            ctx.stroke()
                            for (const jx of js) {
                                const px = topoCanvas.mx(jx), py = topoCanvas.my(y)
                                ctx.beginPath(); ctx.arc(px, py, Math.max(3, 6*sc), 0, Math.PI*2)
                                ctx.fillStyle = T.colCard; ctx.fill()
                                ctx.strokeStyle = T.colPrimary; ctx.lineWidth = Math.max(1.5, 3*sc); ctx.stroke()
                            }
                            ctx.fillStyle = T.colText2
                            ctx.font = "700 " + topoCanvas.cfs(12) + "px sans-serif"
                            ctx.textAlign = "left"
                            ctx.fillText(tag, topoCanvas.mx(tagX), topoCanvas.my(tagY))
                        }
                        bus(topoCanvas._bus1Y, topoCanvas._bus1J,
                            "第一级母线 · " + Math.round(D.packv) + "V · 负载 " + D.bus1Load + "W", 110, 201)
                        bus(topoCanvas._bus2Y, topoCanvas._bus2J,
                            "第二级母线 · 48V · 负载 " + D.op + "W", 140, 603)

                        // ===== 连线（虚线 + 流动 + 箭头 + 标注；离线置灰停动画）=====
                        // 线状态（对齐原型 updateTopo 离线联动）
                        function linkOff(f) {
                            if (dcdcOff && (f==="l4"||f==="l5"||/^l6[a-f]$/.test(f)||f==="l7"||f==="lb2")) return true
                            if (bmsOff && f==="lb1") return true
                            if (mpptOff && (f==="l1a"||f==="l1b"||f==="l2a"||f==="l2b")) return true
                            return false
                        }
                        // 连线标注值（对齐原型 updateTopo）
                        function linkVal(f, d) {
                            if (f==="l1a") return d.pvM+" W"
                            if (f==="l1b") return d.pvS+" W"
                            if (f==="l2a") return d.c1.toFixed(1)+" A"
                            if (f==="l2b") return d.c2.toFixed(1)+" A"
                            if (/^l3[a-d]$/.test(f)) return (d.mot1/(d.packv||1)).toFixed(1)+" A"
                            if (f==="l4") return (d.op/(d.packv||1)).toFixed(1)+" A"
                            if (f==="l5") return (d.op/48).toFixed(1)+" A"
                            if (/^l6[a-f]$/.test(f)) return (d.sm1/48).toFixed(1)+" A"
                            if (f==="l7") return (d.load48/48).toFixed(1)+" A"
                            return ""
                        }
                        // 双向线充放电标注（对齐原型 setBatFlow）
                        function batFlow(batP, volts) {
                            const cur = Math.abs(batP)/(volts||1)
                            return batP>=0 ? "充电 "+cur.toFixed(1)+" A" : "放电 "+cur.toFixed(1)+" A"
                        }
                        // 双向线流动反向（放电 reverse）
                        const lb1Rev = D.bat1 < 0, lb2Rev = D.bat2 < 0
                        const biDir = {lb1: lb1Rev, lb2: lb2Rev}

                        for (const l of topoCanvas._links) {
                            const off = linkOff(l.id)
                            const col = off ? T.colOff : T.colPrimary
                            const x1 = topoCanvas.mx(l.x1), y1 = topoCanvas.my(l.y1)
                            const x2 = topoCanvas.mx(l.x2), y2 = topoCanvas.my(l.y2)
                            const wl = Math.max(1.5, 2.5*sc)
                            ctx.strokeStyle = col
                            ctx.lineWidth = wl
                            ctx.lineCap = "round"
                            // 虚线：普通 8 6 / 双向 4 4；离线不流动
                            if (l.bi) { ctx.setLineDash([4*sc, 4*sc]) } else { ctx.setLineDash([8*sc, 6*sc]) }
                            if (!off) {
                                const offpx = l.bi ? topoCanvas.flowOffBi : topoCanvas.flowOff
                                ctx.lineDashOffset = (l.bi && biDir[l.id]) ? offpx : -offpx
                            }
                            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
                            ctx.setLineDash([]); ctx.lineDashOffset = 0
                            // 标注（箭头统一在 onPaint 末尾最上层绘制，避免被母线/节点遮挡）
                            let txt = ""
                            let tcol = T.colText2
                            if (l.bi) {
                                const dV = l.id==="lb1" ? D.bat1 : D.bat2
                                const dVt = l.id==="lb1" ? (D.packv||1) : 48
                                txt = batFlow(dV, dVt)
                                tcol = dV>=0 ? T.colOk : T.colErr   // 充电绿 / 放电红（对齐 .charge/.discharge）
                                if (off) tcol = T.colOff
                            } else {
                                txt = linkVal(l.id, D)
                                tcol = off ? T.colOff : T.colText2
                            }
                            ctx.fillStyle = tcol
                            ctx.font = "600 " + topoCanvas.cfs(12) + "px monospace"
                            ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
                            ctx.fillText(txt, topoCanvas.mx(l.tx), topoCanvas.my(l.ty))
                        }

                        // ===== 节点卡（框 + 图标 + 标题 + 主值 + 副值；告警黄框 / 离线置灰）=====
                        // 节点离线规则（对齐原型 updateTopo）
                        function nodeOff(id) {
                            if (dcdcOff && (id==="dcdc"||id==="bk"||/^s\d$/.test(id)||id==="load")) return true
                            if (bmsOff && id==="bms") return true
                            if (mpptOff && (id==="mppt1"||id==="mppt2")) return true
                            return false
                        }
                        // 节点内容（对齐原型 updateTopo）
                        function nodeVal(id, d) {
                            switch (id) {
                                case "pv1": return {v: d.pvM+" W", s: d.pvMv.toFixed(1)+" V", ic:"sun"}
                                case "pv2": return {v: d.pvS+" W", s: d.pvSv.toFixed(1)+" V", ic:"sun"}
                                case "mppt1": return {v: d.c1.toFixed(1)+" A", s:"效率 "+d.eff+"%", ic:"bolt"}
                                case "mppt2": return {v: d.c2.toFixed(1)+" A", s:"效率 "+d.eff+"%", ic:"bolt"}
                                case "bms": return {v: Math.round(d.soc)+"%", s: d.packv.toFixed(1)+" V", ic:"bat"}
                                case "dcdc": return {v: d.op+" W", s: d.temp.toFixed(1)+" ℃", ic:"bolt"}
                                case "bk": return {v: d.bkSoc+"%", s: d.bkV.toFixed(1)+" V", ic:"bat"}
                                case "mot1": case "mot2": case "mot3": case "mot4": return {v: d.rpmMot+" rpm", s:"在线", ic:"mH"}
                                case "s1": case "s2": case "s5": case "s6": return {v: d.rpmUp+" rpm", s:"在线", ic:"mV"}
                                case "s3": case "s4": return {v: d.rpmDn+" rpm", s:"在线", ic:"mD"}
                                case "load": return {v: d.load48+" W", s:"在线", ic:"gear"}
                            }
                            return {v:"", s:"", ic:""}
                        }
                        // 节点告警规则（对齐原型 updateTopo）
                        function nodeWarn(id, d) {
                            if (dcdcOff && (id==="dcdc"||/^s\d$/.test(id))) return false
                            if (id==="dcdc") return d.temp > 43
                            if (id==="bms") return d.soc < 20
                            if (id==="mppt1"||id==="mppt2") return d.eff < 90
                            if (/^mot[1-4]$/.test(id)) return d.rpmMot > 520
                            if (/^(s1|s2|s5|s6)$/.test(id)) return d.rpmUp > 2200
                            if (/^(s3|s4)$/.test(id)) return d.rpmDn > 1500
                            return false
                        }
                        for (const n of topoCanvas._nodes) {
                            const off = nodeOff(n.id)
                            const warn = nodeWarn(n.id, D)
                            const cv = nodeVal(n.id, D)
                            const cx = topoCanvas.mx(n.x), cy = topoCanvas.my(n.y)
                            const bx = cx - n.w/2*sc, by = cy - n.h/2*sc
                            const bw = n.w*sc, bh = n.h*sc
                            // 框
                            topoCanvas.rrect(ctx, bx, by, bw, bh, 12*sc)
                            ctx.fillStyle = off ? T.colBg2 : T.colCard2
                            ctx.fill()
                            ctx.lineWidth = Math.max(1.5, 1.5*sc)
                            ctx.strokeStyle = warn ? T.colWarn : (off ? T.colOff : T.colLine)
                            ctx.stroke()
                            // 图标（卡内左上，16px 描边，对齐 node-ic）
                            ctx.strokeStyle = off ? T.colOff : T.colPrimary
                            topoCanvas.drawIcon(ctx, cv.ic, cx - (n.w/2-20)*sc, cy - n.h/2*sc + 20*sc, sc)
                            // 标题
                            ctx.fillStyle = off ? T.colOff : T.colText2
                            ctx.font = "600 " + topoCanvas.cfs(13) + "px sans-serif"
                            ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
                            ctx.fillText(n.id==="load" ? "其他载荷" : n.id==="bms" ? "102S 主电池组" : n.id==="dcdc" ? "DCDC 模块" : n.id==="bk" ? "12S 备用锂电"
                                        : n.id==="pv1" ? "光伏主囊" : n.id==="pv2" ? "光伏副囊" : n.id==="mppt1" ? "MPPT 1" : n.id==="mppt2" ? "MPPT 2"
                                        : n.id==="mot1" ? "推进电机 · 左前" : n.id==="mot2" ? "推进电机 · 左后" : n.id==="mot3" ? "推进电机 · 右后" : n.id==="mot4" ? "推进电机 · 右前"
                                        : n.id==="s1" ? "左前上升电机" : n.id==="s2" ? "左后上升电机" : n.id==="s3" ? "前下降电机" : n.id==="s4" ? "后下降电机" : n.id==="s5" ? "右后上升电机" : "右前上升电机",
                                cx, cy - 8*sc)
                            // 主值
                            ctx.fillStyle = off ? T.colOff : T.colText
                            ctx.font = "700 " + topoCanvas.cfs(19) + "px monospace"
                            ctx.fillText(cv.v, cx, cy + 15*sc)
                            // 副值
                            ctx.fillStyle = off ? T.colOff : T.colText2
                            ctx.font = topoCanvas.cfs(12) + "px monospace"
                            ctx.fillText(cv.s, cx, cy + 33*sc)
                        }

                        // ===== 箭头统一绘制（最上层，保证不被母线/节点遮挡）=====
                        for (const l of topoCanvas._links) {
                            const off = linkOff(l.id)
                            const col = off ? T.colOff : T.colPrimary
                            const x1 = topoCanvas.mx(l.x1), y1 = topoCanvas.my(l.y1)
                            const x2 = topoCanvas.mx(l.x2), y2 = topoCanvas.my(l.y2)
                            const ang = Math.atan2(y2-y1, x2-x1)
                            const as = Math.max(3, 6*sc)
                            ctx.save()
                            ctx.fillStyle = col
                            // 双向线两端箭头；单向线终点箭头
                            const ends = l.bi ? [[x1,y1],[x2,y2]] : [[x2,y2]]
                            for (const e of ends) {
                                ctx.save()
                                ctx.translate(e[0], e[1]); ctx.rotate(ang)
                                ctx.beginPath(); ctx.moveTo(as, 0); ctx.lineTo(-as*0.6, -as*0.6); ctx.lineTo(-as*0.6, as*0.6); ctx.closePath(); ctx.fill()
                                ctx.restore()
                            }
                            ctx.restore()
                        }
                    }
                    // 遥测节拍变化时重绘电源拓扑
                    Connections {
                        target: root.themeRoot
                        function onDataTickChanged() { topoCanvas.requestPaint() }
                    }
                }
                // 悬停命中层（命中检测 → 显示节点详情）
                MouseArea {
                    id: topoHover
                    anchors.fill: topoCanvas
                    hoverEnabled: true
                    cursorShape: topoCanvas.hoverId !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPositionChanged: topoCanvas.updateHover(mouseX, mouseY)
                    onExited: { topoCanvas.hoverId = ""; topoCanvas.hoverText = "" }
                }
                ToolTip {
                    id: topoTip
                    delay: 300
                    timeout: 4000
                    // topoCanvas 相对外层有 44px 顶部偏移，ToolTip 坐标相对外层需补偿
                    x: topoHover.mouseX + 14
                    y: topoHover.mouseY + 44 + 14
                    text: topoCanvas.hoverText
                    visible: topoCanvas.hoverText !== ""
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
                                                    Text { text: (root.envInnerT(envCard.envIndex)).toFixed(1); font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
                                                    Text { text: "℃"; font.pixelSize: 10; color: root.themeRoot.colText2 }
                                                }
                                            }
                                        }
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 8; color: root.themeRoot.colCard
                                            Column { anchors.centerIn: parent; spacing: 2
                                                Text { text: "内部压力"; font.pixelSize: 10; color: root.themeRoot.colText2; anchors.horizontalCenter: parent.horizontalCenter }
                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    Text { text: root.presStr(root.envPresKpa(envCard.envIndex)); font.pixelSize: 15; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText }
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
                                                    id: cellRect
                                                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                                    scale: ma_1.pressed ? 0.96 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    Layout.preferredWidth: 1; Layout.preferredHeight: 1
                                                    radius: 3
                                                    property bool hasProbe: root.cellProbe(envCard.envIndex, env.cols, index) !== null
                                                    property bool live: hasProbe && root.probeLive[cellProbe?.pid ?? ""] === true
                                                    property var cellProbe: root.cellProbe(envCard.envIndex, env.cols, index)
                                                    // 填充色：live=热力色；hasProbe 无数据=浅灰卡底；无探头=完全透明（跟随 Bg2 不突显）
                                                    color: {
                                                        if (live) return root.cellColor(envCard.envIndex, env.cols, index)
                                                        if (hasProbe) return root.themeRoot.colCard2   // 白/深卡底：比 Bg2 更"实"，一眼看出有占位
                                                        return root.cellColor(envCard.envIndex, env.cols, index)   // 即 Bg2，和完全空单元格一致
                                                    }
                                                    // 边框：live 用细黑实描边配合热力色；无数据但有探头用中灰实线（对比度足够，不依赖 colLine）；
                                                    //       无探头=无边框，保持网格隐形
                                                    border.width: (hasProbe || live) ? 1 : 0
                                                    border.color: live ? root.themeRoot.colText
                                                        : root.themeRoot.colText2   // 中灰：light=#64748b / dark=#8aa0bf，和任何背景都拉开 2+ 档对比度

                                                    Text {
                                                        id: cellTextItem
                                                        anchors.centerIn: parent
                                                        text: root.cellText(envCard.envIndex, env.cols, index)
                                                        font.pixelSize: 13; font.bold: true; color: "white"
                                                        visible: text !== ""
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "--"
                                                        visible: cellRect.hasProbe && !cellRect.live
                                                        font.pixelSize: 13
                                                        font.bold: false
                                                        // 占位符比边框浅一档：轻感但可读，不抢"有数据"的热力数字注意力
                                                        color: root.themeRoot.colText2
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
                                            Row {
                                                Layout.preferredWidth: 60
                                                spacing: 6
                                                // 实机状态点：绿=实机在线，灰=离线/基准值（poke 驱动每秒刷新）
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 7; height: 7; radius: 4
                                                    color: { void root.probeModelPoke; return modelData.live ? root.themeRoot.colOk : root.themeRoot.colText2 }
                                                    opacity: { void root.probeModelPoke; return modelData.live ? 1 : 0.45 }
                                                }
                                                Text { text: modelData.pid; font.pixelSize: 13; font.bold: true; font.family: "monospace"; color: root.themeRoot.colText; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                            Text { text: modelData.pos; font.pixelSize: 12; color: root.themeRoot.colText; Layout.preferredWidth: 180; elide: Text.ElideRight }
                                            Text {
                                                font.pixelSize: 14; font.bold: true; font.family: "monospace"; color: modelData.color; Layout.preferredWidth: 90
                                                text: {
                                                    void root.probeModelPoke
                                                    return isNaN(modelData.cur) ? "--" : modelData.cur.toFixed(1) + "℃"
                                                }
                                            }
                                            Text {
                                                font.pixelSize: 12; color: root.themeRoot.colText2; Layout.preferredWidth: 70
                                                text: {
                                                    void root.probeModelPoke
                                                    return isNaN(modelData.max) ? "—" : modelData.max.toFixed(1)
                                                }
                                            }
                                            Text {
                                                font.pixelSize: 12; color: root.themeRoot.colText2; Layout.preferredWidth: 70
                                                text: {
                                                    void root.probeModelPoke
                                                    return isNaN(modelData.min) ? "—" : modelData.min.toFixed(1)
                                                }
                                            }
                                            Text {
                                                font.pixelSize: 12; color: root.themeRoot.colText2; Layout.preferredWidth: 70
                                                text: {
                                                    void root.probeModelPoke
                                                    return isNaN(modelData.avg) ? "—" : modelData.avg.toFixed(1)
                                                }
                                            }
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
                            // 说明：时间列为采样时刻的本地时间（每点 1 秒）
                            Text {
                                text: "时间列为采样时刻的本地时间（每点 1s），最新一行即最近一次采样"
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
                                        width: 44 + 70 + root.probes.length * 46
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
                                        id: hover_sync
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    text: "⇄ 从实机同步"
                                    background: Rectangle {
                                        radius: 8; color: root.themeRoot.colCard2
                                        border.color: (hover_sync.hovered ? root.themeRoot.colPrimary : root.themeRoot.colLine)
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                    }
                                    contentItem: Text { text: parent.text; color: root.themeRoot.colPrimary; font.pixelSize: 12 }
                                    onClicked: root.syncFromLora()
                                }
                                Button {
                                    // 按压缩放反馈（对齐原型 :active{scale(.94)}）
                                    scale: pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    HoverHandler {
                                        id: hover_reset
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    text: "恢复默认"
                                    background: Rectangle {
                                        radius: 8; color: root.themeRoot.colCard2
                                        border.color: (hover_reset.hovered ? root.themeRoot.colWarn : root.themeRoot.colLine)
                                        Behavior on border.color { ColorAnimation { duration: 150 } }
                                    }
                                    contentItem: Text { text: parent.text; color: root.themeRoot.colWarn; font.pixelSize: 12 }
                                    onClicked: root.resetProbesDefault()
                                }
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
                                Text { text: "实机状态"; font.pixelSize: 12; font.bold: true; color: root.themeRoot.colText2; Layout.preferredWidth: 110 }
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
                                        // 探头编号可编辑：编号即实机节点号（T1~T99），改编号=换绑实机节点
                                        TextField {
                                            Layout.preferredWidth: 90
                                            text: modelData.pid
                                            font.pixelSize: 12; font.bold: true; font.family: "monospace"
                                            horizontalAlignment: Text.AlignHCenter
                                            validator: RegularExpressionValidator { regularExpression: /[Tt]?\d{1,2}/ }
                                            onEditingFinished: {
                                                if (!root.renameProbe(modelData.pid, text))
                                                    text = modelData.pid
                                            }
                                        }
                                        // 实机状态：绿点+实时温度=实机在线；灰=离线（显示基准值）
                                        Row {
                                            Layout.preferredWidth: 110
                                            spacing: 6
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 7; height: 7; radius: 4
                                                color: { void root.themeRoot.dataTick; return root.probeLive[modelData.pid] ? root.themeRoot.colOk : root.themeRoot.colText2 }
                                                opacity: { void root.themeRoot.dataTick; return root.probeLive[modelData.pid] ? 1 : 0.45 }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: {
                                                    void root.themeRoot.dataTick
                                                    return root.probeLive[modelData.pid] && root.pvVals[modelData.pid] != null
                                                           ? root.pvVals[modelData.pid].toFixed(1) + "℃"
                                                           : "离线 · 基准"
                                                }
                                                font.pixelSize: 12; color: { void root.themeRoot.dataTick; return root.probeLive[modelData.pid] ? root.themeRoot.colOk : root.themeRoot.colText2 }
                                            }
                                        }
                                        ComboBox {
                                            HoverHandler {
                                                id: hover_2
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                            Layout.preferredWidth: 150
                                            model: root.envDef.map(e => e.name)
                                            currentIndex: modelData.ei
                                            onActivated: root.setProbeEi(modelData.pid, index)
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
                                                if (!isNaN(v)) root.setProbeNum(modelData.pid, "row", v, 1, root.envDef[modelData.ei].rows)
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
                                                if (!isNaN(v)) root.setProbeNum(modelData.pid, "col", v, 1, root.envDef[modelData.ei].cols)
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
                                                if (!isNaN(v)) root.setProbeNum(modelData.pid, "base", v, 0, 80)
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

            // 时间窗档位：最近 30s/1min/5min（500ms 采样 → 60/120/600 点）
            property var winOpts: [["30s",60],["1min",120],["5min",600]]
            property int winIdx: 0
            // 阈值参考线（对齐原型 bandVal/bandOn；每系列按自身范围映射一条系列色线）
            property real bandVal: 45
            property bool bandOn: false
            // 图例/端点标签的最新真实值（归一化只用于绘制，读数始终显示真实值）
            property var latest: ({v:NaN, pv:NaN, outp:NaN, i:NaN})
            // 端点标签：归一化 y（防重叠后）+ 文字 + 系列色，index 顺序 [v,pv,outp,i]
            property var tipNorm: [0.5, 0.5, 0.5, 0.5]
            property var tipTxt: ["", "", "", ""]
            // 左侧区间色标：每条可见曲线窗口内真实 min~max（如 367.1~368.4V），中间值按高度比例估算
            property var rangeTxt: ["", "", "", ""]
            property var tipColor: ["#2563eb", "#16a34a", "#f59e0b", "#06b6d4"]
            property var tipUnit: ["V", "W", "W", "A"]
            // 归一化绘制的上下留边（曲线不贴边框）
            readonly property real nLo: 0.06
            readonly property real nHi: 0.94

            // 真实值 → 图例/端点文字（如 367.2V / 600W / 5.2A）
            function fmtTip(i, v) {
                return isNaN(v) ? "--" : v.toFixed(i === 1 || i === 2 ? 0 : 1) + tipUnit[i]
            }
            // 窗口内真实区间 → 左侧色标文字（如 367.1~368.4V）
            function fmtRange(i, mn, mx) {
                const dp = (i === 1 || i === 2) ? 0 : 1
                return mn.toFixed(dp) + "~" + mx.toFixed(dp) + tipUnit[i]
            }

            // 将 themeRoot.rtcData 的缺失点增量追加到 series，并同步 X 轴范围与阈值线。
            // 纵轴方案（对齐原型）：每条曲线按窗口内自身 min/max 归一化到 [nLo,nHi] 满幅
            // 绘制，Y 轴隐藏刻度；读数走图例值 + 端点标签（真实值）。
            // 窗口滑动会改变各系列 min/max（归一化基准漂移），故每次全量重建
            //（≤40 点 × 4 系列，500ms 一次，开销可忽略）。
            function syncSeries() {
                const R = root.themeRoot
                if (!R) return   // themeRoot 尚未注入（TopoView onLoaded 之前），跳过
                const n = R.rtcData.v.length
                const keep = Math.min(n, R.rtcWindowPoints)
                const startIdx = n - keep   // 顶层数据中"最近窗口"的起始下标
                const sers = [sVolt, sPv, sOutp, sI]
                const keys = ["v", "pv", "outp", "i"]
                // 1) 各系列窗口内真实 min/max
                const stats = []
                for (let s = 0; s < 4; s++) {
                    const d = R.rtcData[keys[s]]
                    let mn = Infinity, mx = -Infinity
                    for (let k = startIdx; k < n; k++) {
                        const v = d[k]
                        if (v < mn) mn = v
                        if (v > mx) mx = v
                    }
                    if (!isFinite(mn)) { mn = 0; mx = 1 }
                    if (mx - mn < 1e-9) { mx = mn + 1 }   // 平线时给 1 范围
                    stats.push({mn: mn, mx: mx})
                }
                // 2) 全量重建（归一化满幅）
                for (let s = 0; s < 4; s++) {
                    const ser = sers[s], d = R.rtcData[keys[s]], st = stats[s]
                    ser.clear()
                    for (let k = startIdx; k < n; k++) {
                        const x = R.rtcIdx - (n - 1 - k)
                        const y = chartRoot.nLo + (chartRoot.nHi - chartRoot.nLo) * (d[k] - st.mn) / (st.mx - st.mn)
                        ser.append(x, y)
                    }
                }
                cx2.min = Math.max(0, R.rtcIdx - R.rtcWindowPoints)
                cx2.max = Math.max(R.rtcWindowPoints, R.rtcIdx)
                // 3) 图例最新真实值 + 左侧区间色标（可见曲线的窗口内真实 min~max）
                chartRoot.latest = {
                    v: n ? R.rtcData.v[n-1] : NaN,
                    pv: n ? R.rtcData.pv[n-1] : NaN,
                    outp: n ? R.rtcData.outp[n-1] : NaN,
                    i: n ? R.rtcData.i[n-1] : NaN
                }
                for (let s = 0; s < 4; s++) {
                    chartRoot.rangeTxt[s] = (sers[s].visible && n > 1)
                            ? chartRoot.fmtRange(s, stats[s].mn, stats[s].mx) : ""
                }
                // 4) 端点标签：归一化 y + 简单防重叠（可见系列按 y 排序，最小间距 0.07）
                const tips = []
                for (let s = 0; s < 4; s++) {
                    const ser = sers[s]
                    if (!ser.count || !ser.visible) { tips.push({s: s, y: NaN}); continue }
                    tips.push({s: s, y: ser.at(ser.count - 1).y})
                }
                const vis = tips.filter(t => !isNaN(t.y)).sort((a, b) => a.y - b.y)
                let prevY = -1
                for (const t of vis) {
                    if (prevY >= 0 && t.y - prevY < 0.07) t.y = prevY + 0.07
                    if (t.y > 1.0) t.y = 1.0
                    prevY = t.y
                }
                for (const t of tips) {
                    chartRoot.tipNorm[t.s] = isNaN(t.y) ? 0.5 : t.y
                    chartRoot.tipTxt[t.s] = isNaN(t.y) ? "" : chartRoot.fmtTip(t.s, chartRoot.latest[keys[t.s]])
                }
                // 5) 阈值线：每系列一条（系列色），bandVal 落在该系列真实范围内才画
                const bands = [sBandV, sBandPv, sBandOutp, sBandI]
                for (let s = 0; s < 4; s++) {
                    const b = bands[s], st = stats[s]
                    b.clear()
                    if (chartRoot.bandOn && n > 1
                        && chartRoot.bandVal >= st.mn && chartRoot.bandVal <= st.mx) {
                        const y = chartRoot.nLo + (chartRoot.nHi - chartRoot.nLo)
                                 * (chartRoot.bandVal - st.mn) / (st.mx - st.mn)
                        b.append(cx2.min, y)
                        b.append(cx2.max, y)
                    }
                }
            }
            // 切换时间窗档位：从顶层数据按新窗口重建
            function applyWindow(idx) {
                chartRoot.winIdx = idx
                const R = root.themeRoot
                if (!R) return
                R.rtcWindowPoints = chartRoot.winOpts[idx][1]
                chartRoot.syncSeries()
            }
            // 图例点击开关对应曲线（对齐原型"点击图例可开关参数"），并重算端点标签
            function legendToggle(idx, on) {
                const arr = [sVolt, sPv, sOutp, sI]
                if (idx >= 0 && idx < arr.length) arr[idx].visible = on
                chartRoot.syncSeries()
            }
            function clearCharts() {
                const R = root.themeRoot
                R.rtcData = ({"v":[], "pv":[], "outp":[], "i":[]})
                R.rtcIdx = 0
                chartRoot.syncSeries()
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
                        // 时间窗三档（对齐原型 chartWin：最近 20s/10s/5s）
                        Row {
                            spacing: 3
                            Repeater {
                                model: chartRoot.winOpts
                                Rectangle {
                                    property bool winActive: chartRoot.winIdx === index
                                    width: 44; height: 26; radius: 6
                                    scale: winMa.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    color: winActive ? root.themeRoot.colPrimary : root.themeRoot.colCard2
                                    border.color: winActive ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData[0]
                                        font.pixelSize: 11; font.weight: Font.Bold
                                        color: winActive ? "#ffffff" : root.themeRoot.colText2
                                    }
                                    MouseArea {
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        id: winMa
                                        anchors.fill: parent
                                        onClicked: chartRoot.applyWindow(index)
                                    }
                                }
                            }
                        }
                        // 阈值参考线：数值输入 + 开关（对齐原型 bandVal/bandOn）
                        Rectangle {
                            Layout.preferredHeight: 26
                            implicitWidth: bandRow.implicitWidth + 12
                            radius: 6
                            color: root.themeRoot.colCard2
                            border.color: root.themeRoot.colLine
                            Row {
                                id: bandRow
                                anchors.centerIn: parent
                                spacing: 4
                                TextField {
                                    width: 44; height: 20
                                    horizontalAlignment: TextInput.AlignHCenter
                                    font.pixelSize: 11; font.family: "monospace"
                                    color: root.themeRoot.colText
                                    text: "" + chartRoot.bandVal
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    background: Rectangle { radius: 4; color: root.themeRoot.colCard; border.color: root.themeRoot.colLine }
                                    onEditingFinished: {
                                        const v = parseInt(text)
                                        if (!isNaN(v)) chartRoot.bandVal = v
                                        chartRoot.syncSeries()
                                    }
                                }
                                Text {
                                    text: "阈值线"
                                    anchors.verticalCenter: parent.verticalCenter   // 与 20px 高的输入框/按钮基线齐平
                                    font.pixelSize: 11; font.weight: Font.DemiBold; color: root.themeRoot.colText2
                                }
                                Button {
                                    text: chartRoot.bandOn ? "开" : "关"
                                    width: 24; height: 20
                                    padding: 0   // 去掉默认内边距，contentItem 精确填满 24×20，字必居中
                                    scale: pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                                    background: Rectangle {
                                        radius: 4
                                        color: chartRoot.bandOn ? root.themeRoot.colPrimary : root.themeRoot.colCard
                                        border.color: chartRoot.bandOn ? root.themeRoot.colPrimary : root.themeRoot.colLine
                                    }
                                    contentItem: Text {
                                        text: parent.text
                                        anchors.fill: parent                       // fill + 双向对齐，不受 implicit 尺寸影响
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        color: chartRoot.bandOn ? "#ffffff" : root.themeRoot.colText2
                                        font.pixelSize: 11; font.weight: Font.DemiBold
                                    }
                                    onClicked: {
                                        chartRoot.bandOn = !chartRoot.bandOn
                                        chartRoot.syncSeries()
                                    }
                                }
                            }
                        }
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
                                model: [["BMS总压","#2563eb",0],["光伏功率","#16a34a",1],["输出功率","#f59e0b",2],["总电流","#06b6d4",3]]
                                // 图例项：名称 + 最新真实值，点击开关对应曲线（对齐原型"点击图例可开关参数"）
                                Row {
                                    id: legRow
                                    property bool legOn: true
                                    spacing: 6
                                    opacity: legOn ? 1.0 : 0.35
                                    // Row(positioner) 子项禁用 anchors.fill：MouseArea 会致
                                    // "Row will not function" 图例整行失效；改用 Handler
                                    //（非可视、不占位、自动覆盖父项，无需 anchors）
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            legRow.legOn = !legRow.legOn
                                            chartRoot.legendToggle(modelData[2], legRow.legOn)
                                        }
                                    }
                                    Rectangle { width: 14; height: 3; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: modelData[1] }
                                    Text { text: modelData[0]; font.pixelSize: 12; color: root.themeRoot.colText2; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chartRoot.fmtTip(modelData[2], chartRoot.latest[["v","pv","outp","i"][modelData[2]]])
                                        font.pixelSize: 11; font.bold: true; font.family: "monospace"; color: modelData[1]
                                    }
                                }
                            }
                        }
                        // 图表 + 端点标签层（ChartView default property 是 series，非序列子项须放外层）
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ChartView {
                                id: chartView
                                anchors.fill: parent
                                antialiasing: true
                                backgroundColor: "transparent"
                                legend.visible: false
                                // Y 轴归一化 0~1：隐藏刻度（读数走图例值+端点标签），保留网格线
                                ValueAxis { id: cx2; min: 0; max: 100; labelFormat: "%d"; titleText: "采样点" }
                                ValueAxis { id: cy2; min: 0; max: 1; labelsVisible: false; titleText: "" }
                                LineSeries { id: sVolt; name: "BMS总压"; axisX: cx2; axisY: cy2; color: "#2563eb"; width: 2 }
                                LineSeries { id: sPv; name: "光伏功率"; axisX: cx2; axisY: cy2; color: "#16a34a"; width: 2 }
                                LineSeries { id: sOutp; name: "输出功率"; axisX: cx2; axisY: cy2; color: "#f59e0b"; width: 2 }
                                LineSeries { id: sI; name: "总电流"; axisX: cx2; axisY: cy2; color: "#06b6d4"; width: 2 }
                                // 阈值参考线：每系列一条系列色线（阈值落在该系列真实范围内才画），默认关
                                LineSeries { id: sBandV; axisX: cx2; axisY: cy2; color: sVolt.color; width: 1; opacity: 0.55 }
                                LineSeries { id: sBandPv; axisX: cx2; axisY: cy2; color: sPv.color; width: 1; opacity: 0.55 }
                                LineSeries { id: sBandOutp; axisX: cx2; axisY: cy2; color: sOutp.color; width: 1; opacity: 0.55 }
                                LineSeries { id: sBandI; axisX: cx2; axisY: cy2; color: sI.color; width: 1; opacity: 0.55 }
                            }
                            // 左侧区间色标：每条可见曲线窗口内真实 min~max（系列色，半透明底）。
                            // 归一化满幅后各曲线峰(最小值)在上、谷(最大值)在下同高，
                            // 逐点贴标必然重叠，故集中为通道标尺式列表，中间值按高度比例估算。
                            Column {
                                x: chartView.plotArea.x + 6
                                y: chartView.plotArea.y + 6
                                spacing: 2
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        required property int index
                                        visible: chartRoot.rangeTxt[index] !== ""
                                        width: rangeText.implicitWidth + 12
                                        height: 17
                                        radius: 4
                                        color: Qt.rgba(0, 0, 0, 0.4)
                                        Text {
                                            id: rangeText
                                            anchors.centerIn: parent
                                            text: chartRoot.rangeTxt[index]
                                            color: chartRoot.tipColor[index]
                                            font.pixelSize: 10; font.bold: true; font.family: "monospace"
                                        }
                                    }
                                }
                            }
                            // 端点标签层：曲线右端显示最新真实值（系列色，防重叠摆位由 syncSeries 计算）
                            Repeater {
                                model: 4
                                Text {
                                    required property int index
                                    text: chartRoot.tipTxt[index]
                                    visible: text !== ""
                                    color: chartRoot.tipColor[index]
                                    font.pixelSize: 11; font.bold: true; font.family: "monospace"
                                    x: chartView.plotArea.x + chartView.plotArea.width - width - 8
                                    y: chartView.plotArea.y + (1 - chartRoot.tipNorm[index]) * chartView.plotArea.height - height / 2
                                    z: 5
                                }
                            }
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
            Component.onCompleted: {
                // 重建（Loader 懒加载销毁重建）后按顶层实际窗口点数恢复档位选中态，
                // 否则 UI 显示 30s 但 syncSeries 仍按上次的 rtcWindowPoints（如 600）渲染
                const pts = root.themeRoot ? root.themeRoot.rtcWindowPoints : 60
                for (let i = 0; i < chartRoot.winOpts.length; i++) {
                    if (chartRoot.winOpts[i][1] === pts) { chartRoot.winIdx = i; break }
                }
                chartRoot.syncSeries()
            }
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
            Text {
                id: probeDetailSrc
                font.pixelSize: 11; color: root.themeRoot.colText2
                Layout.fillWidth: true; wrapMode: Text.Wrap
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
            root.lastSampleTs = Date.now()   // 时间对齐表本地时间基准（每秒更新）
            const lora = bridge.loraNodes()
            // === 临时诊断日志（每 5 秒一条）：排查热力图方块 45℃ 基准问题，问题解决后移除 ===
            if (Date.now() - root._diagTs > 5000) {
                root._diagTs = Date.now()
                const loraD = []
                for (const n of lora) loraD.push("id=" + n.id + " t=" + n.temp + " hasT=" + (n.hasTemp !== undefined ? n.hasTemp : "NOFIELD") + " p=" + n.pressure + " isT=" + n.isTemp)
                const probeD = []
                for (const p of root.probes) probeD.push("pid=" + p.pid + " ei=" + p.ei + " base=" + p.base + " live=" + (root.probeLive[p.pid] === true))
                console.log("[TopoDiag] loraN=" + lora.length + " [" + loraD.join(" | ") + "]")
                console.log("[TopoDiag] probeN=" + root.probes.length + " [" + probeD.join(" | ") + "]")
            }
            // === 临时诊断日志结束 ===
            const loraMap = new Object()
            let presSum = 0, presCnt = 0
            for (const n of lora) {
                loraMap["" + n.id] = n
                loraMap[n.id] = n
                if (n.pressure > 0) { presSum += n.pressure; presCnt++ }   // 压力节点（Pa）
            }
            root.envPresPa = presCnt > 0 ? presSum / presCnt : NaN
            for (const p of root.probes) {
                const k = p.pid
                // pid 形如 T01/T1 → 数字节点 id（parseInt 去掉前导零再查表）
                const num = parseInt(String(k).replace(/^T/i, ""), 10)
                const node = (!isNaN(num) && (loraMap[String(num)] || loraMap[num])) || loraMap[k]
                const real = node && node.hasTemp ? node.temp : NaN
                const got = !isNaN(real)
                root.probeLive[k] = got   // 本轮是否拿到实机温度
                if (got) {
                    // 有真实数据才写入值/历史；无数据不写 base（避免基准假值混入统计与显示）
                    root.pvVals[k] = real
                    const h = root.pvHist[k] || []
                    h.push(real)
                    if (h.length > 180) h.shift()
                    root.pvHist[k] = h
                }
            }
            // 探头数据表 · 增量更新（in-place，不重建 delegate）
            root.updateProbeRows()
            root.themeRoot.dataTick++
        }
    }
}

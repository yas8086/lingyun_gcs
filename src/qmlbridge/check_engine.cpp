// 自检引擎实现（对齐原型 JS 逐条）：见头文件说明。
// 持久化：AppConfigLocation/check_config.json（全量条目数组，含 custom 标记），
// 加载合并策略与原型 loadCheckCfg 逐条一致。

#include "qmlbridge/check_engine.h"
#include "qmlbridge/telemetry_bridge.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>
#include <cmath>

namespace lgs {

namespace {

// 内置 11 项预置定义（对齐原型 CHECK_DEFS L1838-1850 逐字段一致）
QVariantList defaultDefs() {
    return QVariantList{
        QVariantMap{{"id","bms_online"},{"dev","BMS"},{"name","链路在线"},{"fid",""},{"unit",""},{"mode","none"},{"cmp","gt"},{"min",QVariant()},{"max",QVariant()},{"val",QVariant()},{"en",true}},
        QVariantMap{{"id","bms_packv"},{"dev","BMS"},{"name","总压正常"},{"fid","pack_v"},{"unit","V"},{"mode","range"},{"cmp","gt"},{"min",360},{"max",380},{"val",QVariant()},{"en",true}},
        QVariantMap{{"id","bms_soc"},{"dev","BMS"},{"name","SOC 充足"},{"fid","soc"},{"unit","%"},{"mode","single"},{"cmp","gt"},{"min",QVariant()},{"max",QVariant()},{"val",30},{"en",true}},
        QVariantMap{{"id","bms_maxt"},{"dev","BMS"},{"name","最高温度"},{"fid","max_t"},{"unit","℃"},{"mode","single"},{"cmp","lt"},{"min",QVariant()},{"max",QVariant()},{"val",50},{"en",true}},
        QVariantMap{{"id","bms_diffv"},{"dev","BMS"},{"name","单体压差"},{"fid","diff_v"},{"unit","V"},{"mode","single"},{"cmp","lte"},{"min",QVariant()},{"max",QVariant()},{"val",0.05},{"en",true}},
        QVariantMap{{"id","mppt_online"},{"dev","MPPT"},{"name","链路在线"},{"fid",""},{"unit",""},{"mode","none"},{"cmp","gt"},{"min",QVariant()},{"max",QVariant()},{"val",QVariant()},{"en",true}},
        QVariantMap{{"id","mppt_pvv"},{"dev","MPPT"},{"name","光伏电压"},{"fid","pv_v"},{"unit","V"},{"mode","range"},{"cmp","gt"},{"min",20},{"max",120},{"val",QVariant()},{"en",true}},
        QVariantMap{{"id","mppt_chargei"},{"dev","MPPT"},{"name","充电电流"},{"fid","charge_i"},{"unit","A"},{"mode","single"},{"cmp","gt"},{"min",QVariant()},{"max",QVariant()},{"val",0},{"en",true}},
        QVariantMap{{"id","dcdc_online"},{"dev","DCDC"},{"name","链路在线"},{"fid",""},{"unit",""},{"mode","none"},{"cmp","gt"},{"min",QVariant()},{"max",QVariant()},{"val",QVariant()},{"en",true}},
        QVariantMap{{"id","dcdc_outv"},{"dev","DCDC"},{"name","输出电压"},{"fid","out_v"},{"unit","V"},{"mode","range"},{"cmp","gt"},{"min",40},{"max",60},{"val",QVariant()},{"en",true}},
        QVariantMap{{"id","dcdc_temp"},{"dev","DCDC"},{"name","散热温度"},{"fid","temp"},{"unit","℃"},{"mode","single"},{"cmp","lt"},{"min",QVariant()},{"max",QVariant()},{"val",45},{"en",true}},
    };
}

QString checkCfgPath() {
    return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
           + QStringLiteral("/check_config.json");
}

} // namespace

CheckEngine::CheckEngine(TelemetryBridge *bridge, QObject *parent)
    : QObject(parent), bridge_(bridge) {
    loadCfg();
}

void CheckEngine::loadCfg() {
    items_ = defaultDefs();
    QFile f(checkCfgPath());
    if (!f.open(QIODevice::ReadOnly))
        return;   // 首次启动无文件：纯默认
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (doc.isNull() || !doc.isArray())
        return;
    const QJsonArray arr = doc.array();
    QVariantList saved;
    for (const auto &v : arr) {
        const QJsonObject o = v.toObject();
        QVariantMap m = o.toVariantMap();
        m["custom"] = m.value("custom", false);
        saved.append(m);
    }
    // 内置项：按 id 覆盖用户改动（取不到的字段回落默认——新版本增删内置项自动兼容）
    QVariantList merged;
    const auto defaults = defaultDefs();
    for (const auto &d : defaults) {
        QVariantMap def = d.toMap();
        const QString id = def.value("id").toString();
        for (const auto &sv : saved) {
            const QVariantMap sm = sv.toMap();
            if (sm.value("id").toString() == id) {
                for (auto it = sm.begin(); it != sm.end(); ++it)
                    def[it.key()] = it.value();
                break;
            }
        }
        merged.append(def);
    }
    // 自定义项：不在内置定义中的保存条目，补默认字段后追加尾部（custom:true）
    for (const auto &sv : saved) {
        const QVariantMap sm = sv.toMap();
        const QString id = sm.value("id").toString();
        const bool builtin = std::any_of(defaults.begin(), defaults.end(),
            [&](const QVariant &d) { return d.toMap().value("id").toString() == id; });
        if (!builtin && !id.isEmpty()) {
            QVariantMap def{{"dev","自定义"},{"name","未命名"},{"fid",""},{"unit",""},
                            {"mode","single"},{"cmp","gt"},{"min",QVariant()},{"max",QVariant()},
                            {"val",QVariant()},{"en",true}};
            for (auto it = sm.begin(); it != sm.end(); ++it)
                def[it.key()] = it.value();
            def["custom"] = true;
            merged.append(def);
        }
    }
    items_ = merged;
}

QString CheckEngine::devKeyOf(const QString &dev) const {
    // 内置 MPPT 特例映射主 MPPT（mppt1 为就绪必要项，与旧 bridge 就绪度口径一致）；
    // 自定义项按原型约定取 dev 文本小写整串作设备键
    if (dev == QLatin1String("MPPT"))
        return QStringLiteral("mppt1");
    return dev.toLower();
}

QVariantMap CheckEngine::eval(const QVariantMap &def) const {
    const bool en = def.value("en").toBool();
    if (!en)
        return QVariantMap{{"ok", QVariant()},{"val", QStringLiteral("已停用")}};
    const QString mode = def.value("mode").toString();
    if (mode == QLatin1String("none"))
        return QVariantMap{{"ok", bridge_->online(devKeyOf(def.value("dev").toString()))},
                           {"val", QStringLiteral("在线")}};
    const double v = bridge_->value(devKeyOf(def.value("dev").toString()),
                                    def.value("fid").toString());
    if (std::isnan(v))
        return QVariantMap{{"ok", false},{"val", QStringLiteral("—")}};
    QVariantMap r{{"val", fmtVal(def, v)}};
    if (mode == QLatin1String("range")) {
        const double mn = def.value("min").toDouble();
        const double mx = def.value("max").toDouble();
        r["ok"] = v > mn && v < mx;   // 开区间（对齐原型）
    } else {
        const double th = def.value("val").toDouble();
        const QString cmp = def.value("cmp").toString();
        bool hit = false;
        if (cmp == QLatin1String("gt")) hit = v > th;
        else if (cmp == QLatin1String("gte")) hit = v >= th;
        else if (cmp == QLatin1String("lte")) hit = v <= th;
        else hit = v < th;   // lt
        r["ok"] = hit;
    }
    return r;
}

QString CheckEngine::fmtVal(const QVariantMap &def, double v) const {
    const QString unit = def.value("unit").toString();
    if (unit == QLatin1String("%"))
        return QString::number(std::lround(v)) + unit;
    if (unit == QLatin1String("V") && std::abs(v) < 1)
        return QString::number(v, 'f', 2) + unit;
    return QString::number(v, 'f', 1) + unit;
}

QString CheckEngine::thText(const QVariantMap &def) const {
    const QString mode = def.value("mode").toString();
    if (mode == QLatin1String("none"))
        return QString();
    const QString unit = def.value("unit").toString();
    if (mode == QLatin1String("range"))
        return QStringLiteral("%1~%2%3")
            .arg(def.value("min").toString(), def.value("max").toString(), unit);
    const QString cmp = def.value("cmp").toString();
    const QString sym = cmp == QLatin1String("gt") ? QStringLiteral(">")
                        : cmp == QLatin1String("lt") ? QStringLiteral("<")
                        : cmp == QLatin1String("gte") ? QStringLiteral("≥")
                        : QStringLiteral("≤");
    return sym + def.value("val").toString() + unit;
}

void CheckEngine::runAll() {
    // 对齐原型 runCheck：逐项判定 → 三态渲染字段注入 items_ 副本 → 聚合就绪度。
    // 全部项停用时 checkState 为空 → 就绪度回"待自检"（对齐原型 updateReadiness 首分支）。
    QVariantList rendered;
    QVariantList state;
    int fails = 0;
    int enabled = 0;
    for (const auto &iv : items_) {
        QVariantMap def = iv.toMap();
        const QVariantMap r = eval(def);
        const bool en = def.value("en").toBool();
        if (!en) {
            // skip 态：不参与就绪度统计
            def["st"] = QStringLiteral("skip");
            def["cur"] = r.value("val");
            def["th"] = QString();
        } else {
            ++enabled;
            const bool ok = r.value("ok").toBool();
            if (!ok)
                ++fails;
            state.append(QVariantMap{{"dev", def.value("dev")},
                                     {"name", def.value("name")},
                                     {"pass", ok},
                                     {"val", r.value("val")}});
            def["st"] = ok ? QStringLiteral("pass") : QStringLiteral("fail");
            def["cur"] = r.value("val");
            def["th"] = thText(def);
        }
        rendered.append(def);
    }
    items_ = rendered;
    checkState_ = state;
    failCount_ = fails;
    checkedOnce_ = true;
    readyLevel_ = enabled == 0 ? 0 : (fails == 0 ? 1 : (fails <= 1 ? 2 : 3));
    emit itemsChanged();
    emit readinessChanged();
}

void CheckEngine::saveCfg() {
    // 剥离运行期渲染字段（st/cur/th）——只持久化配置本身，
    // 否则旧一轮的运行结果会随 JSON 载入污染下轮配置（数据卫生）。
    QVariantList clean;
    clean.reserve(items_.size());
    for (const auto &iv : items_) {
        QVariantMap def = iv.toMap();
        def.remove(QStringLiteral("st"));
        def.remove(QStringLiteral("cur"));
        def.remove(QStringLiteral("th"));
        clean.append(def);
    }
    const QString path = checkCfgPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QJsonArray arr = QJsonArray::fromVariantList(clean);
    QTextStream out(&f);
    out.setGenerateByteOrderMark(true);   // BOM，便于 Windows 记事本（与 temp_probes.json 一致）
    out << QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    out.flush();
    f.close();
}

void CheckEngine::setItem(const QString &id, const QVariantMap &patch) {
    for (int i = 0; i < items_.size(); ++i) {
        QVariantMap def = items_[i].toMap();
        if (def.value("id").toString() != id)
            continue;
        // 仅写 patch 内字段（single/range 切换时隐藏字段保持原值，不被 0 污染）
        for (auto it = patch.begin(); it != patch.end(); ++it)
            def[it.key()] = it.value();
        items_[i] = def;
        saveCfg();
        runAll();   // 保存立即整页重跑（对齐原型 ckSave→runCheck）
        return;
    }
}

QString CheckEngine::addItem(const QVariantMap &def) {
    QVariantMap m = def;
    QString id = QStringLiteral("ck_%1").arg(QDateTime::currentMSecsSinceEpoch());
    while (std::any_of(items_.begin(), items_.end(), [&](const QVariant &v) {
               return v.toMap().value("id").toString() == id; }))
        id += QLatin1Char('x');   // 碰撞尾缀加 x（对齐原型）
    m["id"] = id;
    m["custom"] = true;
    items_.append(m);
    saveCfg();
    runAll();
    return id;
}

void CheckEngine::removeItem(const QString &id) {
    for (int i = 0; i < items_.size(); ++i) {
        const QVariantMap def = items_[i].toMap();
        if (def.value("id").toString() == id && def.value("custom").toBool()) {
            items_.removeAt(i);
            saveCfg();
            runAll();
            return;
        }
    }
}

} // namespace lgs

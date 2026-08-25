// 桥接层 · 规则与映射领域：告警规则 CRUD、温度探头映射、设备字段配置、CSV 导出。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include <QFile>
#include <QTextStream>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>

namespace lgs {

// 温度探头映射文件路径（决策 #27，B8：跨 rules/config 拆分共用，配置导入导出需合并该文件）
QString probesFilePath() {
    return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
           + QStringLiteral("/temp_probes.json");
}

namespace {
AlarmRule ruleFromMap(const QVariantMap &m) {
    AlarmRule r;
    r.id = m.value("id").toString();
    r.device = m.value("device").toString();
    r.field = m.value("field").toString();
    r.label = m.value("label").toString();
    r.type = (m.value("type").toString() == "threshold") ? AlarmRule::Threshold
                                                         : AlarmRule::Fault;
    r.threshold = m.value("threshold").toDouble();
    r.above = m.contains("above") ? m.value("above").toBool() : true;
    r.enabled = m.contains("enabled") ? m.value("enabled").toBool() : true;
    const int lv = m.value("level").toInt();
    r.level = (lv == 2) ? AlarmEvent::Critical
              : (lv == 1) ? AlarmEvent::Warn : AlarmEvent::Info;
    return r;
}
} // namespace

// ---- 告警规则 CRUD（决策 #15/#31）----
QVariant TelemetryBridge::alarmRules() const {
    QVariantList list;
    if (!config_) return list;
    QVector<AlarmRule> rules = config_->loadAlarmRules(
        engine_ ? engine_->defaultRules() : QVector<AlarmRule>());
    for (const auto &r : rules) {
        QVariantMap m;
        m["id"] = r.id;
        m["device"] = r.device;
        m["field"] = r.field;
        m["label"] = r.label;
        m["type"] = (r.type == AlarmRule::Threshold) ? "threshold" : "fault";
        m["threshold"] = r.threshold;
        m["above"] = r.above;
        m["enabled"] = r.enabled;
        m["level"] = static_cast<int>(r.level); // 0 Info /1 Warn /2 Critical
        list.append(m);
    }
    return list;
}

QVariant TelemetryBridge::alarmRuleFields() const {
    QVariantList list;
    const auto add = [&list](const QString &dev, const QString &fid,
                             const QString &label) {
        QVariantMap m;
        m["key"] = dev + "." + fid;
        m["label"] = label;
        list.append(m);
    };
    add("bms", "pack_v", "BMS 总压");
    add("bms", "max_t", "BMS 最高温度");
    add("bms", "soc", "BMS SOC");
    add("bms", "diff_v", "BMS 单体压差");
    add("bms", "alarm", "BMS 告警位");
    add("backup", "pack_v", "备用电源总压");
    add("backup", "soc", "备用电源 SOC");
    add("backup", "fault", "备用电源故障码");
    add("mppt1", "pv_p", "MPPT1 光伏功率");
    add("mppt1", "pv_v", "MPPT1 光伏电压");
    add("mppt1", "charge_i", "MPPT1 充电电流");
    add("mppt1", "fault", "MPPT1 故障码");
    add("mppt2", "pv_p", "MPPT2 光伏功率");
    add("mppt2", "pv_v", "MPPT2 光伏电压");
    add("mppt2", "charge_i", "MPPT2 充电电流");
    add("mppt2", "fault", "MPPT2 故障码");
    add("dcdc", "out_p", "DCDC 输出功率");
    add("dcdc", "out_v", "DCDC 输出电压");
    add("dcdc", "temp", "DCDC 散热温度");
    add("dcdc", "fault", "DCDC 故障码");
    return list;
}

void TelemetryBridge::addAlarmRule(const QVariant &rule) {
    if (!config_) return;
    auto rules = config_->loadAlarmRules(
        engine_ ? engine_->defaultRules() : QVector<AlarmRule>());
    AlarmRule r = ruleFromMap(rule.toMap());
    if (r.id.isEmpty()) {
        // 取现有最大编号 +1，避免删除中间规则后复用旧 id 造成主键重复
        int maxId = 0;
        for (const auto &ex : rules) {
            if (ex.id.startsWith(QLatin1String("rule_"))) {
                bool ok = false;
                const int n = ex.id.mid(5).toInt(&ok);
                if (ok && n > maxId) maxId = n;
            }
        }
        r.id = QString("rule_%1").arg(maxId + 1);
    }
    if (r.label.isEmpty())
        r.label = r.device + "." + r.field;
    rules.push_back(r);
    config_->saveAlarmRules(rules);
    if (engine_) engine_->setRules(rules);
    emit rulesChanged();
}

void TelemetryBridge::updateAlarmRule(int i, const QVariant &rule) {
    if (!config_) return;
    auto rules = config_->loadAlarmRules(
        engine_ ? engine_->defaultRules() : QVector<AlarmRule>());
    if (i < 0 || i >= rules.size()) return;
    const QVariantMap m = rule.toMap();
    AlarmRule r = ruleFromMap(m);
    // 保留原 id，避免规则状态错乱
    r.id = rules[i].id;
    rules[i] = r;
    config_->saveAlarmRules(rules);
    if (engine_) engine_->setRules(rules);
    emit rulesChanged();
}

void TelemetryBridge::removeAlarmRule(int i) {
    if (!config_) return;
    auto rules = config_->loadAlarmRules(
        engine_ ? engine_->defaultRules() : QVector<AlarmRule>());
    if (i < 0 || i >= rules.size()) return;
    rules.remove(i);
    config_->saveAlarmRules(rules);
    if (engine_) engine_->setRules(rules);
    emit rulesChanged();
}

void TelemetryBridge::restoreDefaultRules() {
    if (!config_) return;
    const QVector<AlarmRule> defs = engine_ ? engine_->defaultRules()
                                            : QVector<AlarmRule>();
    config_->saveAlarmRules(defs);
    if (engine_) engine_->setRules(defs);
    emit rulesChanged();
}

// ---- 温度探头映射（决策 #27）----
QVariant TelemetryBridge::defaultProbeMapping() const {
    // 与原型默认布局一致：PVSENS [囊体,行,列,基准℃]
    const QVector<QVector<int>> base = {
        {0,2,2,46},{0,2,7,45},{0,5,3,52},{0,5,6,50},{0,6,5,51},{0,8,2,44},{0,8,7,43},{0,11,3,47},{0,11,6,46},
        {1,2,2,49},{1,2,8,48},{1,4,5,55},{1,5,7,53},{1,6,5,58},{1,7,5,61},{1,7,6,59},{1,8,5,57},{1,9,5,54},{1,11,2,48},{1,11,8,47},{1,12,5,52},{1,13,2,47},{1,13,8,46},
        {2,2,2,49},{2,2,8,48},{2,4,5,55},{2,5,7,53},{2,6,5,58},{2,7,5,61},{2,7,6,59},{2,8,5,57},{2,9,5,54},{2,11,2,48},{2,11,8,47},{2,12,5,52},{2,13,2,47},{2,13,8,46},
        {3,2,2,46},{3,2,7,45},{3,5,3,52},{3,5,6,50},{3,6,5,51},{3,8,2,44},{3,8,7,43},{3,11,3,47},{3,11,6,46}
    };
    QVariantList list;
    for (int i = 0; i < base.size(); ++i) {
        QVariantMap m;
        m["pid"] = QStringLiteral("T%1")
                       .arg(QString::number(i + 1).rightJustified(2, QLatin1Char('0')));
        m["ei"] = base[i][0];
        m["row"] = base[i][1];
        m["col"] = base[i][2];
        m["base"] = base[i][3];
        list.append(m);
    }
    return list;
}

QVariant TelemetryBridge::probeMapping() const {
    QFile f(probesFilePath());
    if (!f.open(QIODevice::ReadOnly))
        return defaultProbeMapping();
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isArray())
        return defaultProbeMapping();
    const QJsonArray arr = doc.array();
    if (arr.isEmpty())
        return defaultProbeMapping();
    QVariantList list;
    for (const auto &v : arr) {
        const QJsonObject o = v.toObject();
        QVariantMap m;
        m["pid"] = o.value("pid").toString();
        m["ei"] = o.value("ei").toInt();
        m["row"] = o.value("row").toInt();
        m["col"] = o.value("col").toInt();
        m["base"] = o.value("base").toDouble();
        list.append(m);
    }
    return list;
}

void TelemetryBridge::saveProbeMapping(const QVariant &list) {
    QJsonArray arr;
    for (const auto &v : list.toList()) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o["pid"] = m.value("pid").toString();
        o["ei"] = m.value("ei").toInt();
        o["row"] = m.value("row").toInt();
        o["col"] = m.value("col").toInt();
        o["base"] = m.value("base").toDouble();
        arr.append(o);
    }
    const QString path = probesFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    QTextStream out(&f);
    out.setGenerateByteOrderMark(true);
    out << QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    out.flush();
    f.close();
}

void TelemetryBridge::resetProbeMapping() {
    saveProbeMapping(defaultProbeMapping());
}

// ---- 温度历史与通用文本导出（决策 #28）----
int TelemetryBridge::exportTempCsv(const QString &path) const {
    if (path.isEmpty() || loraHistory_.isEmpty())
        return -1;
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return -1;
    QTextStream out(&f);
    out.setGenerateByteOrderMark(true); // BOM，便于 Windows
    // 收集所有出现过的 pid 列（按第一轮顺序）
    QStringList ids;
    for (const auto &m : loraHistory_)
        for (auto it = m.constBegin(); it != m.constEnd(); ++it)
            if (!ids.contains(it.key()))
                ids << it.key();
    out << "采样序号";
    for (const auto &id : ids)
        out << QLatin1Char(',') << id;
    out << QLatin1Char('\n');
    for (int i = 0; i < loraHistory_.size(); ++i) {
        const auto &round = loraHistory_[i];
        out << (i + 1);
        for (const auto &id : ids)
            out << QLatin1Char(',') << round.value(id).toDouble();
        out << QLatin1Char('\n');
    }
    out.flush();
    f.close();
    return loraHistory_.size();
}

bool TelemetryBridge::writeTextFile(const QString &path, const QString &content) const {
    if (path.isEmpty())
        return false;
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    QTextStream out(&f);
    out.setGenerateByteOrderMark(true); // BOM，便于 Windows
    out << content;
    out.flush();
    f.close();
    return true;
}

} // namespace lgs
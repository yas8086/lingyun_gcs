#include "qmlbridge/telemetry_bridge.h"
#include "comms/serial_manager.h"
#include "core/config_manager.h"
#include <QStringList>
#include <QTime>
#include <QFile>
#include <QTextStream>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>
#include <QCoreApplication>
#include <limits>

namespace lgs {

TelemetryBridge::TelemetryBridge(QObject *parent) : QObject(parent) {
    uptime_.start();
    uptimeStarted_ = true;
    recordEnabled_ = true;
}

void TelemetryBridge::onTelemetry(const lgs::TelemetryData &data) {
    last_ = data;
    // 维护温度历史（决策 #28）：仅记录有节点的轮次，环形上限 200
    if (data.lora && !data.lora->nodes.empty()) {
        QVariantMap round;
        const auto &nodes = data.lora->nodes;
        for (const auto &s : nodes) {
            // 列名用 Txx（pid 主键），与 QWidget 版对齐
            const QString key = QStringLiteral("T%1")
                                    .arg(QString::number(s.id).rightJustified(2, QLatin1Char('0')));
            round[key] = s.temp != 0.0 ? s.temp : s.pressure;
        }
        loraHistory_.append(round);
        if (loraHistory_.size() > 200)
            loraHistory_.removeFirst();
    }
    emit telemetryChanged();
}

void TelemetryBridge::setLinkOnline(bool online) {
    if (linkOnline_ != online) {
        linkOnline_ = online;
        emit linkChanged(online);
    }
}

void TelemetryBridge::setSerialManager(SerialManager *serial) { serial_ = serial; }
void TelemetryBridge::setConfigManager(ConfigManager *config) {
    config_ = config;
    if (config_)
        recordEnabled_ = config_->recordEnabled();
}
void TelemetryBridge::setAlarmEngine(AlarmEngine *engine) { engine_ = engine; }
QStringList TelemetryBridge::ports() const {
    return serial_ ? serial_->availablePorts() : QStringList();
}
bool TelemetryBridge::openSerial(const QString &port, int baud) {
    const bool ok = serial_ && serial_->open(port, baud);
    if (ok) {
        stopRecording();
        startRecording();
    }
    return ok;
}
void TelemetryBridge::closeSerial() {
    stopRecording();
    if (serial_) serial_->close();
}
bool TelemetryBridge::isSerialOpen() const { return serial_ && serial_->isOpen(); }

bool TelemetryBridge::online(const QString &device) const {
    if (device == "bms") return last_.bms.has_value();
    if (device == "backup") return last_.backup.has_value();
    if (device == "mppt") return last_.mppt.has_value();
    if (device == "dcdc") return last_.dcdc.has_value();
    if (device == "lora") return last_.lora.has_value();
    return false;
}

double TelemetryBridge::value(const QString &device, const QString &key) const {
    const double nan = std::numeric_limits<double>::quiet_NaN();
    if (device == "bms" && last_.bms) {
        const auto &b = *last_.bms;
        if (key == "pack_v") return b.pack_v;
        if (key == "pack_i") return b.pack_i;
        if (key == "soc") return b.soc;
        if (key == "rsoc") return b.rsoc;
        if (key == "max_v") return b.max_v;
        if (key == "min_v") return b.min_v;
        if (key == "diff_v") return b.diff_v;
        if (key == "max_t") return b.max_t;
        if (key == "min_t") return b.min_t;
        if (key == "avg_t") return b.avg_t;
        if (key == "diff_t") return b.diff_t;
        if (key == "riso_p") return b.riso_p;
        if (key == "riso_n") return b.riso_n;
        if (key == "alarm") return b.alarm;
    } else if (device == "backup" && last_.backup) {
        const auto &b = *last_.backup;
        if (key == "pack_v") return b.pack_v;
        if (key == "pack_i") return b.pack_i;
        if (key == "soc") return b.soc;
        if (key == "soh") return b.soh;
        if (key == "max_v") return b.max_v;
        if (key == "min_v") return b.min_v;
        if (key == "diff_v") return b.diff_v;
        if (key == "max_t") return b.max_t;
        if (key == "min_t") return b.min_t;
        if (key == "avg_t") return b.avg_t;
        if (key == "diff_t") return b.diff_t;
        if (key == "alarm") return b.alarm;
        if (key == "fault") return b.fault;
        if (key == "sys") return b.sys;
    } else if (device == "mppt" && last_.mppt) {
        const auto &m = *last_.mppt;
        if (key == "pv_v") return m.pv_v;
        if (key == "pv_p") return m.pv_p;
        if (key == "batt_v") return m.batt_v;
        if (key == "charge_i") return m.charge_i;
        if (key == "today") return m.today;
        if (key == "total") return m.total;
        if (key == "fault") return m.fault;
    } else if (device == "dcdc" && last_.dcdc) {
        const auto &d = *last_.dcdc;
        if (key == "in_v") return d.in_v;
        if (key == "out_v") return d.out_v;
        if (key == "out_i") return d.out_i;
        if (key == "out_p") return d.out_p;
        if (key == "temp") return d.temp;
        if (key == "fault") return d.fault;
        if (key == "enabled") return d.enabled ? 1 : 0;
    }
    return nan;
}

int TelemetryBridge::readinessState() const {
    const bool any = last_.bms.has_value() || last_.mppt.has_value() ||
                     last_.dcdc.has_value();
    if (!any)
        return 0; // 待自检
    int fails = 0;
    if (last_.bms) {
        if (last_.bms->pack_v <= 360 || last_.bms->pack_v >= 380) ++fails;
        if (last_.bms->soc <= 30) ++fails;
        if (last_.bms->max_t >= 50) ++fails;
        if (last_.bms->diff_v >= 0.05) ++fails;
    } else ++fails;
    if (last_.mppt) {
        if (last_.mppt->pv_v <= 20 || last_.mppt->pv_v >= 120) ++fails;
        if (last_.mppt->charge_i <= 0) ++fails;
    } else ++fails;
    if (last_.dcdc) {
        if (last_.dcdc->out_v <= 40 || last_.dcdc->out_v >= 60) ++fails;
        if (last_.dcdc->temp >= 45) ++fails;
    } else ++fails;
    if (fails == 0) return 1;
    if (fails <= 1) return 2;
    return 3;
}

void TelemetryBridge::addAlarm(const QString &msg, const QString &level,
                               const QString &source) {
    QVariantMap entry;
    entry["time"] = QTime::currentTime().toString("HH:mm:ss");
    entry["level"] = level;
    entry["source"] = source;
    entry["content"] = msg;
    entry["state"] = QStringLiteral("未确认");
    alarmList_.push_front(entry); // 最新在前
    ++unconfirmed_;
    // 环形上限（决策 #33）：告警 200 条
    while (alarmList_.size() > 200) {
        alarmList_.pop_back();
    }
    emit alarmsChanged();
}

QVariant TelemetryBridge::alarms() const {
    QVariantList list;
    list.reserve(alarmList_.size());
    for (const auto &m : alarmList_)
        list.append(m);
    return list;
}

void TelemetryBridge::confirmAlarm(int i) {
    if (i < 0 || i >= alarmList_.size())
        return;
    if (alarmList_[i].value("state").toString() == QStringLiteral("未确认")) {
        alarmList_[i]["state"] = QStringLiteral("已确认");
        --unconfirmed_;
        emit alarmsChanged();
    }
}

void TelemetryBridge::confirmAllAlarms() {
    for (auto &m : alarmList_)
        m["state"] = QStringLiteral("已确认");
    unconfirmed_ = 0;
    emit alarmsChanged();
}

int TelemetryBridge::unconfirmedCount() const { return unconfirmed_; }

QString TelemetryBridge::loraSummary() const {
    if (!last_.lora || last_.lora->nodes.empty())
        return QStringLiteral("无在线节点");
    QStringList rows;
    for (const auto &s : last_.lora->nodes) {
        QString line;
        if (s.temp != 0.0)
            line = QStringLiteral("#%1 %2℃").arg(s.id).arg(s.temp, 0, 'f', 1);
        else
            line = QStringLiteral("#%1 %2Pa").arg(s.id).arg(s.pressure, 0, 'f', 0);
        if (s.alarm != 0)
            line += s.alarm > 0 ? QStringLiteral(" ⚠超上限")
                                : QStringLiteral(" ⚠超下限");
        rows << line;
    }
    return rows.join(QStringLiteral("\n"));
}

QVariant TelemetryBridge::loraNodes() const {
    QVariantList list;
    if (!last_.lora)
        return list;
    for (const auto &s : last_.lora->nodes) {
        QVariantMap m;
        m["id"] = s.id;
        m["temp"] = s.temp;
        m["pressure"] = s.pressure;
        m["alarm"] = s.alarm;
        m["isTemp"] = s.temp != 0.0;
        list.append(m);
    }
    return list;
}

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

QString TelemetryBridge::dataDir() const {
    const QString dir = QCoreApplication::applicationDirPath() + QStringLiteral("/data");
    QDir().mkpath(dir);
    return dir;
}

QString TelemetryBridge::snapshotDir() const {
    const QString dir = dataDir() + QStringLiteral("/曲线快照");
    QDir().mkpath(dir);
    return dir;
}

// ---- 数据自动记录（逐帧原始报文落盘，断电安全）----
bool TelemetryBridge::recordEnabled() const {
    return recordEnabled_;
}
void TelemetryBridge::setRecordEnabled(bool on) {
    recordEnabled_ = on;
    if (config_) config_->setRecordEnabled(on);
    // 关闭时立即停止，开启时不自动开始（待下次打开串口）
    if (!on) stopRecording();
}
QString TelemetryBridge::recordDir() const {
    return config_ ? config_->recordDir() : QString();
}
void TelemetryBridge::setRecordDir(const QString &dir) {
    if (config_) config_->setRecordDir(dir);
}
bool TelemetryBridge::isRecording() const { return recordFile_.isOpen(); }
QString TelemetryBridge::currentRecordFile() const { return recordPath_; }

void TelemetryBridge::startRecording() {
    if (recordFile_.isOpen())
        recordFile_.close();
    recordPath_.clear();
    if (!recordEnabled() || !serial_ || !serial_->isOpen())
        return;
    // 目录：优先用户配置，否则软件目录/data
    QString dir = recordDir();
    if (dir.isEmpty())
        dir = dataDir();
    QDir().mkpath(dir);
    // 文件名：打开串口时间，如 telemetry_20260813_143025.csv
    const QString ts = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
    recordPath_ = dir + QStringLiteral("/telemetry_") + ts + QStringLiteral(".csv");
    recordFile_.setFileName(recordPath_);
    if (!recordFile_.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    const QByteArray header = QByteArray("\xEF\xBB\xBF") // UTF-8 BOM
        + "# 灵云01 地面站遥测原始记录\n"
        + "# 开始时间: " + QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss").toUtf8() + "\n"
        + "# 格式: 每行一帧原始报文（AA55 帧头 + JSON），utf-8\n";
    recordFile_.write(header);
    recordFile_.flush();
}
void TelemetryBridge::stopRecording() {
    if (recordFile_.isOpen())
        recordFile_.close();
    recordPath_.clear();
}
void TelemetryBridge::onRawFrame(const QByteArray &frame) {
    if (!recordFile_.isOpen())
        return;
    recordFile_.write(frame);
    recordFile_.flush(); // 每帧 flush，断电不丢
}

int TelemetryBridge::configTempUnit() const {
    return config_ ? config_->temperatureUnit() : 0;
}
void TelemetryBridge::setConfigTempUnit(int unit) {
    if (config_) config_->setTemperatureUnit(unit);
}
bool TelemetryBridge::configAlarmSound() const {
    return config_ ? config_->alarmSoundEnabled() : false;
}
void TelemetryBridge::setConfigAlarmSound(bool on) {
    if (config_) config_->setAlarmSoundEnabled(on);
}
int TelemetryBridge::configChartWindowSecs() const {
    return config_ ? config_->chartWindowSecs() : 20;
}
void TelemetryBridge::setConfigChartWindowSecs(int secs) {
    if (config_) config_->setChartWindowSecs(secs);
}
QVariant TelemetryBridge::configHiddenModules() const {
    QVariantList list;
    if (config_) {
        const auto hidden = config_->hiddenModules();
        for (const auto &k : hidden)
            list.append(k);
    }
    return list;
}
void TelemetryBridge::setConfigHiddenModule(const QString &key, bool hidden) {
    if (!config_) return;
    QSet<QString> set = config_->hiddenModules();
    if (hidden) set.insert(key);
    else set.remove(key);
    config_->setHiddenModules(set);
}

// ---- 配置导入导出（决策：跨设备快速配置）----
QString TelemetryBridge::configFilePath() const {
    return config_ ? config_->filePath() : QString();
}

bool TelemetryBridge::exportConfig(const QString &path) const {
    if (!config_ || path.isEmpty()) return false;
    QFile src(config_->filePath());
    if (!src.open(QIODevice::ReadOnly))
        return false;
    const QByteArray data = src.readAll();
    src.close();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile dst(path);
    if (!dst.open(QIODevice::WriteOnly))
        return false;
    dst.write(data);
    dst.close();
    return true;
}

bool TelemetryBridge::importConfig(const QString &path) {
    if (!config_ || path.isEmpty()) return false;
    QFile src(path);
    if (!src.open(QIODevice::ReadOnly))
        return false;
    const QByteArray data = src.readAll();
    src.close();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return false;
    // 写回当前配置文件（含 BOM，便于 Windows 记事本打开）
    QDir().mkpath(QFileInfo(config_->filePath()).absolutePath());
    QFile dst(config_->filePath());
    if (!dst.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    QTextStream out(&dst);
    out.setGenerateByteOrderMark(true);
    out << QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
    out.flush();
    dst.close();
    // 重载运行时状态并通知前端刷新
    recordEnabled_ = config_->recordEnabled();
    emit configImported();
    return true;
}

bool TelemetryBridge::configDark() const {
    return config_ ? config_->darkTheme() : false;
}
void TelemetryBridge::setConfigDark(bool dark) {
    if (config_) config_->setDarkTheme(dark);
}
bool TelemetryBridge::configDense() const {
    return config_ ? config_->denseTheme() : false;
}
void TelemetryBridge::setConfigDense(bool dense) {
    if (config_) config_->setDenseTheme(dense);
}
bool TelemetryBridge::configContrast() const {
    return config_ ? config_->contrastTheme() : false;
}
void TelemetryBridge::setConfigContrast(bool contrast) {
    if (config_) config_->setContrastTheme(contrast);
}
QString TelemetryBridge::configAccent() const {
    return config_ ? config_->accentTheme() : QStringLiteral("blue");
}
void TelemetryBridge::setConfigAccent(const QString &accent) {
    if (config_) config_->setAccentTheme(accent);
}

int TelemetryBridge::configMapSource() const {
    return config_ ? config_->mapSource() : 1;
}
void TelemetryBridge::setConfigMapSource(int source) {
    if (config_) config_->setMapSource(source);
}
QString TelemetryBridge::configMapKey() const {
    return config_ ? config_->mapKey() : QString();
}
void TelemetryBridge::setConfigMapKey(const QString &key) {
    if (config_) config_->setMapKey(key);
}

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
    add("mppt", "pv_p", "MPPT 光伏功率");
    add("mppt", "pv_v", "MPPT 光伏电压");
    add("mppt", "charge_i", "MPPT 充电电流");
    add("mppt", "fault", "MPPT 故障码");
    add("dcdc", "out_p", "DCDC 输出功率");
    add("dcdc", "out_v", "DCDC 输出电压");
    add("dcdc", "temp", "DCDC 散热温度");
    add("dcdc", "fault", "DCDC 故障码");
    return list;
}

static AlarmRule ruleFromMap(const QVariantMap &m) {
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
static QString probesFilePath() {
    return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation)
           + QStringLiteral("/temp_probes.json");
}

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

// ---- 设备卡显示字段配置（原型：更多字段可勾选隐藏）----
QStringList TelemetryBridge::fieldConfig(const QString &device) const {
    // 运行时由 QML 维护缓存，这里仅提供默认全部字段
    QStringList def;
    if (device == "bms")
        def = {"pack_v", "pack_i", "max_t", "max_v", "min_v", "diff_v"};
    else if (device == "mppt")
        def = {"charge_i", "today", "fault_m", "pv_v", "total"};
    else if (device == "dcdc")
        def = {"out_i", "temp", "fault_d", "in_v", "enabled"};
    return def;
}

void TelemetryBridge::setFieldConfig(const QString &device, const QVariant &list) {
    // 字段配置为纯前端展示状态，由 QML 侧按需持久化到 ConfigManager；此处空实现保持接口一致
    Q_UNUSED(device); Q_UNUSED(list);
}

// ---- 运行时长 ----
int TelemetryBridge::uptimeSeconds() const {
    return uptimeStarted_ ? static_cast<int>(uptime_.elapsed() / 1000) : 0;
}

} // namespace lgs
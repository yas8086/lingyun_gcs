#include "core/config_manager.h"
#include <QFile>
#include <QTextStream>
#include <QJsonDocument>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>
#include <QCoreApplication>
#include <optional>

namespace lgs {

namespace {

// 在 JSON 配置目录下读写（含 BOM，便于 Windows 记事本打开）
QString configDir() {
    return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
}

QJsonObject readFile(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QByteArray raw = f.readAll();
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
    return err.error == QJsonParseError::NoError && doc.isObject()
               ? doc.object() : QJsonObject();
}

void writeFile(const QString &path, const QJsonObject &obj) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning("ConfigManager: 写入配置失败 %s: %s", qPrintable(path),
                 qPrintable(f.errorString()));
        return;
    }
    QTextStream out(&f);
    out.setGenerateByteOrderMark(true); // 含 BOM
    out << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    out.flush();
}

// 解析单条规则；id/device/field 缺失或为空的非法规则返回空 optional，调用方忽略
std::optional<AlarmRule> ruleFromJson(const QJsonObject &o) {
    AlarmRule r;
    r.id = o.value(QLatin1String("id")).toString();
    r.device = o.value(QLatin1String("device")).toString();
    r.field = o.value(QLatin1String("field")).toString();
    if (r.id.isEmpty() || r.device.isEmpty() || r.field.isEmpty())
        return std::nullopt; // 非法规则
    r.label = o.value(QLatin1String("label")).toString();
    r.type = (o.value(QLatin1String("type")).toString() == "threshold")
                 ? AlarmRule::Threshold : AlarmRule::Fault;
    r.threshold = o.value(QLatin1String("threshold")).toDouble();
    r.above = o.value(QLatin1String("above")).toBool(true);
    r.enabled = o.value(QLatin1String("enabled")).toBool(true);
    const int lv = o.value(QLatin1String("level")).toInt();
    r.level = (lv == 2) ? AlarmEvent::Critical
              : (lv == 1) ? AlarmEvent::Warn : AlarmEvent::Info;
    return r;
}

QJsonObject ruleToJson(const AlarmRule &r) {
    QJsonObject o;
    o["id"] = r.id;
    o["device"] = r.device;
    o["field"] = r.field;
    o["label"] = r.label;
    o["type"] = (r.type == AlarmRule::Threshold) ? "threshold" : "fault";
    o["threshold"] = r.threshold;
    o["above"] = r.above;
    o["enabled"] = r.enabled;
    o["level"] = static_cast<int>(r.level);
    return o;
}

} // namespace

ConfigManager::ConfigManager() {
    filePath_ = configDir() + QLatin1String("/ground_station.json");
    root_ = readFile(filePath_); // 一次性读入内存缓存
}

QString ConfigManager::filePath() const { return filePath_; }

void ConfigManager::reload() { root_ = readFile(filePath_); }
void ConfigManager::flush() { writeFile(filePath_, root_); }

QJsonValue ConfigManager::value(const char *key, const QJsonValue &def) const {
    const QJsonValue v = root_.value(QLatin1String(key));
    return v.isUndefined() ? def : v;
}

void ConfigManager::set(const char *key, const QJsonValue &v) {
    root_.insert(QLatin1String(key), v);
    flush(); // 即时落盘，保证 setter 语义（配置需持久化）
}

QString ConfigManager::port() const {
    const QString p = value("port").toString();
    if (!p.isEmpty())
        return p;
    // 无配置时按平台给合理默认串口：Linux 常见数传为 /dev/ttyUSB0，Windows 为 COM3
#ifdef Q_OS_WIN
    return QStringLiteral("COM3");
#else
    return QStringLiteral("/dev/ttyUSB0");
#endif
}

qint32 ConfigManager::baud() const {
    return value("baud", 115200).toInt(115200);
}

void ConfigManager::setPort(const QString &p) { set("port", p); }
void ConfigManager::setBaud(qint32 b) { set("baud", b); }

void ConfigManager::saveWindowGeometry(const QByteArray &geo) {
    set("window_geometry", QString::fromLatin1(geo.toBase64()));
}

QByteArray ConfigManager::windowGeometry() const {
    const QString s = value("window_geometry").toString();
    return s.isEmpty() ? QByteArray() : QByteArray::fromBase64(s.toLatin1());
}

QVector<AlarmRule> ConfigManager::loadAlarmRules(
    const QVector<AlarmRule> &defaults) const {
    // 键不存在（首次运行/未配置）时回退默认规则；键存在但为空数组时返回空集，
    // 允许用户保存"无规则"状态。
    if (!root_.contains(QLatin1String("alarm_rules")))
        return defaults;
    const QJsonArray arr = root_.value(QLatin1String("alarm_rules")).toArray();
    if (arr.isEmpty())
        return {};
    QVector<AlarmRule> rules;
    rules.reserve(arr.size());
    for (const auto &v : arr) {
        const auto r = ruleFromJson(v.toObject());
        if (r)
            rules.push_back(*r); // 非法规则跳过
    }
    return rules;
}

void ConfigManager::saveAlarmRules(const QVector<AlarmRule> &rules) {
    QJsonArray arr;
    for (const auto &r : rules)
        arr.append(ruleToJson(r));
    set("alarm_rules", arr);
}

int ConfigManager::temperatureUnit() const {
    const int v = value("temp_unit", 0).toInt(0);
    return (v == 0 || v == 1) ? v : 0; // 非法值回退默认
}
void ConfigManager::setTemperatureUnit(int unit) { set("temp_unit", unit); }

int ConfigManager::pressureUnit() const {
    const int v = value("pressure_unit", 1).toInt(1);
    return (v >= 0 && v <= 3) ? v : 1; // 0=kPa 1=Pa 2=bar 3=psi，默认 Pa，非法回退 Pa
}
void ConfigManager::setPressureUnit(int unit) { set("pressure_unit", unit); }

int ConfigManager::chartWindowSecs() const {
    const int v = value("chart_window", 20).toInt(20);
    return (v == 10 || v == 20 || v == 30) ? v : 20; // 合法取值集合，非法回退
}
void ConfigManager::setChartWindowSecs(int secs) { set("chart_window", secs); }

QSet<QString> ConfigManager::hiddenModules() const {
    const QJsonArray arr = value("hidden_modules").toArray();
    QSet<QString> hidden;
    for (const auto &v : arr)
        hidden.insert(v.toString());
    return hidden;
}
void ConfigManager::setHiddenModules(const QSet<QString> &hidden) {
    QJsonArray arr;
    const QStringList keys = hidden.values();
    for (const auto &k : keys)
        arr.append(k);
    set("hidden_modules", arr);
}

bool ConfigManager::recordEnabled() const {
    return value("record_enabled", true).toBool(true);
}
void ConfigManager::setRecordEnabled(bool on) { set("record_enabled", on); }
QString ConfigManager::recordDir() const {
    return value("record_dir").toString();
}
void ConfigManager::setRecordDir(const QString &dir) { set("record_dir", dir); }

bool ConfigManager::darkTheme() const {
    return value("theme_dark", false).toBool(false);
}
void ConfigManager::setDarkTheme(bool dark) { set("theme_dark", dark); }
bool ConfigManager::denseTheme() const {
    return value("theme_dense", false).toBool(false);
}
void ConfigManager::setDenseTheme(bool dense) { set("theme_dense", dense); }
bool ConfigManager::contrastTheme() const {
    return value("theme_contrast", false).toBool(false);
}
void ConfigManager::setContrastTheme(bool contrast) { set("theme_contrast", contrast); }
QString ConfigManager::accentTheme() const {
    return value("theme_accent", "blue").toString("blue");
}
void ConfigManager::setAccentTheme(const QString &accent) { set("theme_accent", accent); }

int ConfigManager::mapSource() const {
    const int v = value("map_source", 1).toInt(1);
    return (v == 0 || v == 1) ? v : 1; // 0天地图 1OSM，非法回退 OSM
}
void ConfigManager::setMapSource(int source) { set("map_source", source); }
QString ConfigManager::mapKey() const { return value("map_key").toString(); }
void ConfigManager::setMapKey(const QString &key) { set("map_key", key); }

// ---- 相机拉流配置（RTSP 相机列表 + 布局档位）----
QJsonArray ConfigManager::cameraConfigs() const {
    return value("camera_configs").toArray();
}
void ConfigManager::setCameraConfigs(const QJsonArray &arr) { set("camera_configs", arr); }
QString ConfigManager::cameraLay() const {
    const QString v = value("camera_lay").toString();
    return (v == "1" || v == "2" || v == "4" || v == "a") ? v : "1";
}
void ConfigManager::setCameraLay(const QString &lay) { set("camera_lay", lay); }

// ---- 数传网口 UDP 数据源（协议 2.1）----
bool ConfigManager::udpEnabled() const {
    return value("udp_enabled", true).toBool(true); // 默认开启（机载默认双发）
}
void ConfigManager::setUdpEnabled(bool on) { set("udp_enabled", on); }
quint16 ConfigManager::udpPort() const {
    const int v = value("udp_port", 20000).toInt(20000);
    return quint16(qBound(1, v, 65535));
}
void ConfigManager::setUdpPort(quint16 port) { set("udp_port", int(port)); }

// 保留 alarmSoundEnabled 访问（header 有声明）
bool ConfigManager::alarmSoundEnabled() const {
    return value("alarm_sound", false).toBool(false);
}
void ConfigManager::setAlarmSoundEnabled(bool on) { set("alarm_sound", on); }

} // namespace lgs
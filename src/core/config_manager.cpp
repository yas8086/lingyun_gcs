#include "core/config_manager.h"
#include <QFile>
#include <QTextStream>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>
#include <QCoreApplication>

namespace lgs {

namespace {

// 在 JSON 配置目录下读写（含 BOM，便于 Windows 记事本打开）
QString configDir() {
    const QString base = QStandardPaths::writableLocation(
        QStandardPaths::AppConfigLocation);
    return base;
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
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return;
    QTextStream out(&f);
    out.setGenerateByteOrderMark(true); // 含 BOM
    out << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    out.flush();
}

AlarmRule ruleFromJson(const QJsonObject &o) {
    AlarmRule r;
    r.id = o.value(QLatin1String("id")).toString();
    r.device = o.value(QLatin1String("device")).toString();
    r.field = o.value(QLatin1String("field")).toString();
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
}

QString ConfigManager::filePath() const { return filePath_; }

QString ConfigManager::port() const {
    return readFile(filePath_).value(QLatin1String("port")).toString();
}

qint32 ConfigManager::baud() const {
    return readFile(filePath_).value(QLatin1String("baud")).toInt(115200);
}

void ConfigManager::setPort(const QString &p) {
    QJsonObject o = readFile(filePath_);
    o["port"] = p;
    writeFile(filePath_, o);
}

void ConfigManager::setBaud(qint32 b) {
    QJsonObject o = readFile(filePath_);
    o["baud"] = b;
    writeFile(filePath_, o);
}

void ConfigManager::saveWindowGeometry(const QByteArray &geo) {
    QJsonObject o = readFile(filePath_);
    o["window_geometry"] = QString::fromLatin1(geo.toBase64());
    writeFile(filePath_, o);
}

QByteArray ConfigManager::windowGeometry() const {
    const QString s = readFile(filePath_)
                          .value(QLatin1String("window_geometry")).toString();
    if (s.isEmpty())
        return {};
    return QByteArray::fromBase64(s.toLatin1());
}

QVector<AlarmRule> ConfigManager::loadAlarmRules(
    const QVector<AlarmRule> &defaults) const {
    const QJsonArray arr = readFile(filePath_).value(QLatin1String("alarm_rules"))
                               .toArray();
    if (arr.isEmpty())
        return defaults;
    QVector<AlarmRule> rules;
    rules.reserve(arr.size());
    for (const auto &v : arr)
        rules.push_back(ruleFromJson(v.toObject()));
    return rules;
}

void ConfigManager::saveAlarmRules(const QVector<AlarmRule> &rules) {
    QJsonObject o = readFile(filePath_);
    QJsonArray arr;
    for (const auto &r : rules)
        arr.append(ruleToJson(r));
    o["alarm_rules"] = arr;
    writeFile(filePath_, o);
}

int ConfigManager::temperatureUnit() const {
    return readFile(filePath_).value(QLatin1String("temp_unit")).toInt(0);
}
void ConfigManager::setTemperatureUnit(int unit) {
    QJsonObject o = readFile(filePath_);
    o["temp_unit"] = unit;
    writeFile(filePath_, o);
}
bool ConfigManager::alarmSoundEnabled() const {
    return readFile(filePath_).value(QLatin1String("alarm_sound")).toBool(false);
}
void ConfigManager::setAlarmSoundEnabled(bool on) {
    QJsonObject o = readFile(filePath_);
    o["alarm_sound"] = on;
    writeFile(filePath_, o);
}
int ConfigManager::chartWindowSecs() const {
    return readFile(filePath_).value(QLatin1String("chart_window")).toInt(20);
}
void ConfigManager::setChartWindowSecs(int secs) {
    QJsonObject o = readFile(filePath_);
    o["chart_window"] = secs;
    writeFile(filePath_, o);
}

QSet<QString> ConfigManager::hiddenModules() const {
    const QJsonArray arr = readFile(filePath_).value(QLatin1String("hidden_modules"))
                               .toArray();
    QSet<QString> hidden;
    for (const auto &v : arr)
        hidden.insert(v.toString());
    return hidden;
}
void ConfigManager::setHiddenModules(const QSet<QString> &hidden) {
    QJsonObject o = readFile(filePath_);
    QJsonArray arr;
    const QStringList keys = hidden.values();
    for (const auto &k : keys)
        arr.append(k);
    o["hidden_modules"] = arr;
    writeFile(filePath_, o);
}

bool ConfigManager::recordEnabled() const {
    return readFile(filePath_).value(QLatin1String("record_enabled")).toBool(true);
}
void ConfigManager::setRecordEnabled(bool on) {
    QJsonObject o = readFile(filePath_);
    o["record_enabled"] = on;
    writeFile(filePath_, o);
}
QString ConfigManager::recordDir() const {
    return readFile(filePath_).value(QLatin1String("record_dir")).toString();
}
void ConfigManager::setRecordDir(const QString &dir) {
    QJsonObject o = readFile(filePath_);
    o["record_dir"] = dir;
    writeFile(filePath_, o);
}

bool ConfigManager::darkTheme() const {
    return readFile(filePath_).value(QLatin1String("theme_dark")).toBool(false);
}
void ConfigManager::setDarkTheme(bool dark) {
    QJsonObject o = readFile(filePath_);
    o["theme_dark"] = dark;
    writeFile(filePath_, o);
}
bool ConfigManager::denseTheme() const {
    return readFile(filePath_).value(QLatin1String("theme_dense")).toBool(false);
}
void ConfigManager::setDenseTheme(bool dense) {
    QJsonObject o = readFile(filePath_);
    o["theme_dense"] = dense;
    writeFile(filePath_, o);
}
bool ConfigManager::contrastTheme() const {
    return readFile(filePath_).value(QLatin1String("theme_contrast")).toBool(false);
}
void ConfigManager::setContrastTheme(bool contrast) {
    QJsonObject o = readFile(filePath_);
    o["theme_contrast"] = contrast;
    writeFile(filePath_, o);
}
QString ConfigManager::accentTheme() const {
    return readFile(filePath_).value(QLatin1String("theme_accent")).toString("blue");
}
void ConfigManager::setAccentTheme(const QString &accent) {
    QJsonObject o = readFile(filePath_);
    o["theme_accent"] = accent;
    writeFile(filePath_, o);
}

int ConfigManager::mapSource() const {
    return readFile(filePath_).value(QLatin1String("map_source")).toInt(1);
}
void ConfigManager::setMapSource(int source) {
    QJsonObject o = readFile(filePath_);
    o["map_source"] = source;
    writeFile(filePath_, o);
}
QString ConfigManager::mapKey() const {
    return readFile(filePath_).value(QLatin1String("map_key")).toString();
}
void ConfigManager::setMapKey(const QString &key) {
    QJsonObject o = readFile(filePath_);
    o["map_key"] = key;
    writeFile(filePath_, o);
}

} // namespace lgs
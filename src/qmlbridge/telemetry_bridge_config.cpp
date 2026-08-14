// 桥接层 · 配置领域（config_photo 拆分）：界面偏好、主题、地图、配置导入导出。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include <QSet>
#include <QFile>
#include <QTextStream>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDir>
#include <QFileInfo>

namespace lgs {

QString TelemetryBridge::port() const {
    return config_ ? config_->port() : QString();
}
int TelemetryBridge::baud() const {
    return config_ ? config_->baud() : 115200;
}

int TelemetryBridge::configTempUnit() const {
    return config_ ? config_->temperatureUnit() : 0;
}
void TelemetryBridge::setConfigTempUnit(int unit) {
    if (config_) config_->setTemperatureUnit(unit);
}
int TelemetryBridge::configPressureUnit() const {
    return config_ ? config_->pressureUnit() : 0;
}
void TelemetryBridge::setConfigPressureUnit(int unit) {
    if (config_) config_->setPressureUnit(unit);
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
    // 导入后重载内存缓存，使后续 getter 读到新配置
    config_->reload();
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

} // namespace lgs
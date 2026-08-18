// 桥接层 · 配置领域（config_photo 拆分）：界面偏好、主题、地图、配置导入导出。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include "video/siyi_sdk_client.h"
#include "video/rtsp_stream.h"
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
    // 通知前端刷新（各模块 visible 依赖 dataTick 重算，否则勾选不生效）
    emit stateChanged();
}

// ---- 相机拉流配置（RTSP 相机列表 + 布局档位，经 ConfigManager JSON 持久化）----
QVariantList TelemetryBridge::cameraConfigs() const {
    QVariantList list;
    if (!config_) return list;
    const QJsonArray arr = config_->cameraConfigs();
    for (const auto &v : arr) {
        const QJsonObject o = v.toObject();
        QVariantMap m;
        m["id"] = o.value("id").toString();
        m["name"] = o.value("name").toString();
        m["enable"] = o.value("enable").toBool(false);
        m["ip"] = o.value("ip").toString();
        m["port"] = o.value("port").toInt(554);
        m["path"] = o.value("path").toString();
        m["user"] = o.value("user").toString();
        m["pass"] = o.value("pass").toString();
        m["stream"] = o.value("stream").toString();
        m["transport"] = o.value("transport").toString();
        m["fps"] = o.value("fps").toInt(25);
        list.append(m);
    }
    return list;
}
void TelemetryBridge::saveCameraConfigs(const QVariant &list) {
    if (!config_) return;
    QJsonArray arr;
    const QVariantList ls = list.toList();
    for (const auto &v : ls) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o["id"] = m.value("id").toString();
        o["name"] = m.value("name").toString();
        o["enable"] = m.value("enable").toBool();
        o["ip"] = m.value("ip").toString();
        o["port"] = m.contains("port") ? m.value("port").toInt() : 554;
        o["path"] = m.value("path").toString();
        o["user"] = m.value("user").toString();
        o["pass"] = m.value("pass").toString();
        o["stream"] = m.value("stream").toString();
        o["transport"] = m.value("transport").toString();
        o["fps"] = m.contains("fps") ? m.value("fps").toInt() : 25;
        arr.append(o);
    }
    config_->setCameraConfigs(arr);
    // 通知前端刷新（摄像头页 tab/网格等依赖 stateChanged 重算）
    emit stateChanged();
}
QString TelemetryBridge::cameraLay() const {
    return config_ ? config_->cameraLay() : QStringLiteral("1");
}
void TelemetryBridge::setCameraLay(const QString &lay) {
    if (config_) config_->setCameraLay(lay);
}
QObject *TelemetryBridge::videoStream(const QString &camId) {
    // 懒创建：同 id 复用同一流实例，随桥接层销毁
    auto it = streams_.find(camId);
    if (it != streams_.end())
        return it.value();
    auto *s = new RtspStream(this);
    // 从相机配置取 RTSP url
    if (config_) {
        const QJsonArray arr = config_->cameraConfigs();
        for (const auto &v : arr) {
            const QJsonObject o = v.toObject();
            if (o.value("id").toString() == camId) {
                const QString ip = o.value("ip").toString();
                const int port = o.value("port").toInt(554);
                const QString path = o.value("path").toString();
                const QString user = o.value("user").toString();
                const QString pass = o.value("pass").toString();
                if (!ip.isEmpty()) {
                    const QString cred = user.isEmpty() ? QString() : (user + ":" + pass + "@");
                    s->setUrl(QStringLiteral("rtsp://%1%2:%3%4").arg(cred, ip).arg(port).arg(path));
                }
                break;
            }
        }
    }
    streams_.insert(camId, s);
    return s;
}

// ---- 思翼云台 SDK（A2 mini）----
void TelemetryBridge::startGimbal(const QString &ip) {
    if (ip.isEmpty())
        return;
    if (!gimbal_) {
        gimbal_ = new SiyiSdkClient(this);
        // 转发客户端信号到桥接层 NOTIFY（Q_PROPERTY 绑定刷新）
        connect(gimbal_, &SiyiSdkClient::connectedChanged,
                this, &TelemetryBridge::gimbalConnectedChanged);
        connect(gimbal_, &SiyiSdkClient::attitudeChanged,
                this, &TelemetryBridge::gimbalAttitudeChanged);
    }
    gimbal_->start(ip, 37260);
}

void TelemetryBridge::stopGimbal() {
    if (gimbal_)
        gimbal_->stop();
}

void TelemetryBridge::gimbalPitchCtrl(int speed) {
    if (gimbal_)
        gimbal_->ctrlPitch(speed);
}

void TelemetryBridge::gimbalCenter() {
    if (gimbal_)
        gimbal_->center();
}

bool TelemetryBridge::gimbalConnected() const {
    return gimbal_ && gimbal_->connected();
}

double TelemetryBridge::gimbalPitch() const {
    return gimbal_ ? gimbal_->pitch() : 0.0;
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
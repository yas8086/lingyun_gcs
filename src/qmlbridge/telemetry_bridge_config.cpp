// 桥接层 · 配置领域（config_photo 拆分）：界面偏好、主题、地图、配置导入导出。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include "comms/udp_link_source.h"
#include "video/siyi_sdk_client.h"
#include "video/skydroid_sdk_client.h"
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
        m["gimbal"] = o.value("gimbal").toString();   // 云台协议类型："" / siyi / skydroid
        m["ptz"] = o.value("ptz").toBool(false);      // 兼容旧逻辑：是否支持云台控制
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
        o["gimbal"] = m.value("gimbal").toString();
        o["ptz"] = m.value("ptz").toBool();
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

void TelemetryBridge::releaseStream(const QString &camId) {
    // P2-5：删除相机时同步清理该相机的"选错云台"标记，避免 id 复用误带旧状态
    skyWrongIds_.remove(camId);
    auto it = streams_.find(camId);
    if (it == streams_.end())
        return;
    RtspStream *s = it.value();
    streams_.erase(it);
    if (s) {
        s->stop();
        s->deleteLater(); // 停流后由事件循环安全销毁，避免立即删除导致排队信号打到已销毁对象
    }
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

void TelemetryBridge::gimbalCtrlMove(int yaw, int pitch) {
    if (gimbal_)
        gimbal_->ctrlMove(yaw, pitch);
}

void TelemetryBridge::gimbalCenter() {
    if (gimbal_)
        gimbal_->center();
}

void TelemetryBridge::gimbalSetPitchAngle(double pitchDeg) {
    if (gimbal_)
        gimbal_->setPitchAngle(pitchDeg);
}

// ---- 云卓云台相机（C14PRO，UDP 5000 文本协议）----
void TelemetryBridge::startSkyGimbal(const QString &ip) {
    if (ip.isEmpty())
        return;
    skyGimbalTargetIp_ = ip;   // 记录会话主 IP（供无参版本查询默认使用）
    if (!skyGimbal_) {
        skyGimbal_ = new SkydroidSdkClient(this);
        // P1-2：云卓 SDK 的连接状态（start/stop）与思翼的 gimbalConnected 语义无关，
        // 不应转发到 gimbalConnectedChanged（避免云卓启停触发思翼属性的无效重算）；
        // 云卓设备存在与否由 probeFinished → skyGimbalDeviceOkChanged 通道驱动。
        connect(skyGimbal_, &SkydroidSdkClient::probeFinished,
                this, &TelemetryBridge::skyGimbalDeviceOkChanged);
        // 姿态回读 / 激光测距结果转发给 QML（协议 v1.1.5 GAA/GAC/SLR）
        connect(skyGimbal_, &SkydroidSdkClient::attitudeChanged,
                this, &TelemetryBridge::skyGimbalAttitudeChanged);
        connect(skyGimbal_, &SkydroidSdkClient::rangingChanged,
                this, &TelemetryBridge::skyGimbalRangingChanged);
    }
    skyGimbal_->start(ip, 5000);
}

void TelemetryBridge::stopSkyGimbal() {
    if (skyGimbal_)
        skyGimbal_->stop();
    skyGimbalTargetIp_.clear();
}

void TelemetryBridge::skyGimbalCtrlMove(const QString &ip, int yaw, int pitch) {
    if (skyGimbal_)
        skyGimbal_->ctrlMove(ip, yaw, pitch);
}

void TelemetryBridge::skyGimbalCenter(const QString &ip) {
    // 一键回中（RCSDK AKey.MID → #TPUG2wPTZ05）
    if (skyGimbal_)
        skyGimbal_->center(ip);
}

void TelemetryBridge::skyGimbalZoom(const QString &ip, int dir) {
    if (skyGimbal_)
        skyGimbal_->zoom(ip, dir);
}

void TelemetryBridge::skyGimbalSetLens(const QString &ip, int lens) {
    if (!skyGimbal_)
        return;
    if (lens == 1)
        skyGimbal_->setTeleLens(ip);
    else
        skyGimbal_->setWideLens(ip);
}

void TelemetryBridge::skyGimbalShot(const QString &ip) {
    if (skyGimbal_)
        skyGimbal_->takePicture(ip);
}

void TelemetryBridge::skyGimbalRecord(const QString &ip, bool on) {
    if (!skyGimbal_)
        return;
    if (on)
        skyGimbal_->startRecordVideo(ip);
    else
        skyGimbal_->stopRecordVideo(ip);
}

void TelemetryBridge::skyGimbalSetAttitudeReport(const QString &ip, bool on) {
    if (skyGimbal_)
        skyGimbal_->setAttitudeReport(ip, on);
}

void TelemetryBridge::skyGimbalRequestRanging(const QString &ip) {
    if (skyGimbal_)
        skyGimbal_->requestRanging(ip);
}

bool TelemetryBridge::skyGimbalDevicePresent() const {
    // 未启动会话视为不存在（无设备可控制）；启动后返回探测结果
    return skyGimbal_ && skyGimbal_->devicePresent();
}

bool TelemetryBridge::skyGimbalPortClosed() const {
    // 探测到"IP 在线但 5000 端口无云卓服务"→ 确为非云卓设备（选错云台）；
    // 设备没通电/没联网（仅超时无响应）时 portClosed=false，用于区分"选错云台"与"设备离线"
    return skyGimbal_ && skyGimbal_->portClosed();
}

bool TelemetryBridge::skyGimbalAttitudeAlive() const {
    // 兼容 Q_PROPERTY 绑定：无参版本查"会话主 skyGimbalIp"对应的状态（全局单值语义，保持向后兼容）
    if (!skyGimbal_ || skyGimbalTargetIp_.isEmpty()) return false;
    return skyGimbal_->attitudeAlive(skyGimbalTargetIp_);
}

double TelemetryBridge::skyGimbalYaw() const {
    if (!skyGimbal_ || skyGimbalTargetIp_.isEmpty()) return 0.0;
    return skyGimbal_->yaw(skyGimbalTargetIp_);
}

double TelemetryBridge::skyGimbalPitch() const {
    if (!skyGimbal_ || skyGimbalTargetIp_.isEmpty()) return 0.0;
    return skyGimbal_->pitch(skyGimbalTargetIp_);
}

double TelemetryBridge::skyGimbalRoll() const {
    if (!skyGimbal_ || skyGimbalTargetIp_.isEmpty()) return 0.0;
    return skyGimbal_->roll(skyGimbalTargetIp_);
}

double TelemetryBridge::skyGimbalRanging() const {
    if (!skyGimbal_ || skyGimbalTargetIp_.isEmpty()) return 0.0;
    return skyGimbal_->ranging(skyGimbalTargetIp_);
}

bool TelemetryBridge::gimbalConnected() const {
    return gimbal_ && gimbal_->connected();
}

bool TelemetryBridge::siyiGimbalPortClosed() const {
    // 探测到"IP 在线但 37260 端口无思翼服务"→ 确为非思翼设备（选错云台）；
    // 设备没通电/没联网（仅超时无响应）时 portClosed=false，用于区分"选错云台"与"设备离线"
    return gimbal_ && gimbal_->portClosed();
}

double TelemetryBridge::gimbalPitch() const {
    return gimbal_ ? gimbal_->pitch() : 0.0;
}

// ---- 云卓 C14PRO：按 IP 查询姿态/测距（支持多相机独立判断）----
bool TelemetryBridge::skyGimbalAttitudeAliveOf(const QString &ip)
{
    return skyGimbal_ && skyGimbal_->attitudeAlive(ip);
}
double TelemetryBridge::skyGimbalYawOf(const QString &ip)
{
    return skyGimbal_ ? skyGimbal_->yaw(ip) : 0.0;
}
double TelemetryBridge::skyGimbalPitchOf(const QString &ip)
{
    return skyGimbal_ ? skyGimbal_->pitch(ip) : 0.0;
}
double TelemetryBridge::skyGimbalRollOf(const QString &ip)
{
    return skyGimbal_ ? skyGimbal_->roll(ip) : 0.0;
}
double TelemetryBridge::skyGimbalRangingOf(const QString &ip)
{
    return skyGimbal_ ? skyGimbal_->ranging(ip) : 0.0;
}
bool TelemetryBridge::skyGimbalProtocolAliveOf(const QString &ip)
{
    return skyGimbal_ && skyGimbal_->protocolAlive(ip);
}
// ---- 云卓"选错云台类型"标记（按 camId 存，跨页面持久化，CameraView 切页销毁也不丢失）----
void TelemetryBridge::markSkyGimbalWrong(const QString &camId, bool wrong)
{
    if (camId.isEmpty()) return;
    auto it = skyWrongIds_.find(camId);
    bool cur = (it != skyWrongIds_.end()) ? it.value() : false;
    if (cur == wrong) return;
    if (wrong) skyWrongIds_[camId] = true;
    else if (it != skyWrongIds_.end()) skyWrongIds_.erase(it);
    emit skyGimbalWrongChanged(camId);
    emit stateChanged();   // 驱动前端绑定重算（页面上的红字提示等）
}
bool TelemetryBridge::isSkyGimbalWrong(const QString &camId)
{
    if (camId.isEmpty()) return false;
    auto it = skyWrongIds_.constFind(camId);
    return it != skyWrongIds_.constEnd() && it.value();
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
    // B8：把温度探头映射（temp_probes.json）合并进导出包（tempProbes 键），
    // 否则跨设备导入配置会丢失探头布局，需手动重建
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    QJsonObject obj = (err.error == QJsonParseError::NoError && doc.isObject())
                          ? doc.object()
                          : QJsonObject();
    QFile pf(probesFilePath());
    if (pf.open(QIODevice::ReadOnly)) {
        const QJsonDocument pdoc = QJsonDocument::fromJson(pf.readAll());
        pf.close();
        if (pdoc.isArray())
            obj[QLatin1String("tempProbes")] = pdoc.array();
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile dst(path);
    if (!dst.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    QTextStream out(&dst);
    out.setGenerateByteOrderMark(true); // BOM，便于 Windows
    out << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    out.flush();
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
    // B8：导入包含探头映射（tempProbes 数组）时一并写回 temp_probes.json，跨设备迁移不丢
    const QJsonValue tp = doc.object().value(QLatin1String("tempProbes"));
    if (tp.isArray() && !tp.toArray().isEmpty())
        saveProbeMapping(tp.toArray().toVariantList());
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

// ---- 数传网口 UDP 数据源（协议 2.1）----
void TelemetryBridge::setUdpLinkSource(UdpLinkSource *udp) {
    udp_ = udp;
}
void TelemetryBridge::onUdpLinkOnline(bool online) {
    if (udpOnline_ != online) {
        udpOnline_ = online;
        onDataLinkActive(serialOpen_ || udpOnline_); // UDP 状态变化 → 任一数据源评估（记录/运行时）
        emit stateChanged(); // 驱动前端刷新链路状态
    }
}
bool TelemetryBridge::configUdpEnabled() const {
    return config_ ? config_->udpEnabled() : true;
}
void TelemetryBridge::setConfigUdpEnabled(bool on) {
    if (config_) config_->setUdpEnabled(on);
    applyUdpConfig(); // 即时启停
}
int TelemetryBridge::configUdpPort() const {
    return config_ ? int(config_->udpPort()) : 20000;
}
void TelemetryBridge::setConfigUdpPort(int port) {
    if (config_) config_->setUdpPort(quint16(qBound(1, port, 65535)));
    applyUdpConfig(); // 端口改动即时重启监听
}
void TelemetryBridge::applyUdpConfig() {
    const bool on = config_ ? config_->udpEnabled() : false;
    if (!udp_)
        return;
    if (on && !udp_->isRunning())
        udp_->start(config_ ? config_->udpPort() : 20000);
    else if (!on && udp_->isRunning())
        udp_->stop();
}
bool TelemetryBridge::isUdpLinkOpen() const {
    return udp_ && udp_->isRunning();
}

} // namespace lgs
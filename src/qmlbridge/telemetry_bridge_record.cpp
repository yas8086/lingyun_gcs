// 桥接层 · 数据记录领域：逐帧原始报文自动落盘、目录管理。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include "comms/serial_manager.h"
#include "video/rtsp_recorder.h"
#include <QDir>
#include <QDateTime>
#include <QCoreApplication>
#include <QMetaObject>
#include <QJsonArray>
#include <QJsonObject>

namespace lgs {

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

QString TelemetryBridge::cameraDir() const {
    // 摄像头截图/录像按天归档：data/摄像头/yyyy-MM-dd
    const QString dir = dataDir() + QStringLiteral("/摄像头")
        + QDateTime::currentDateTime().toString("/yyyy-MM-dd");
    QDir().mkpath(dir);
    return dir;
}

QString TelemetryBridge::startCameraRecord(const QString &camId) {
    // 该相机已在录：幂等返回当前文件名
    if (recorders_.contains(camId) && recorders_.value(camId)->recording())
        return recorders_.value(camId)->fileName();

    // 从相机配置拼 RTSP url（与 videoStream 相同规则）
    if (!config_)
        return QString();
    const QJsonArray arr = config_->cameraConfigs();
    QString ip, path, user, pass;
    int port = 554;
    bool found = false;
    for (const auto &v : arr) {
        const QJsonObject o = v.toObject();
        if (o.value("id").toString() == camId) {
            ip = o.value("ip").toString();
            port = o.contains("port") ? o.value("port").toInt() : 554;
            path = o.value("path").toString();
            user = o.value("user").toString();
            pass = o.value("pass").toString();
            found = true;
            break;
        }
    }
    if (!found || ip.isEmpty())
        return QString();
    const QString cred = user.isEmpty() ? QString() : (user + ":" + pass + "@");
    const QString url = QStringLiteral("rtsp://%1%2:%3%4")
                            .arg(cred, ip).arg(port).arg(path);

    RtspRecorder *rec = recorders_.value(camId, nullptr);
    if (!rec) {
        rec = new RtspRecorder(this);
        recorders_.insert(camId, rec);
    }
    const QString name = QStringLiteral("rec_%1_%2.mkv")
                             .arg(camId).arg(QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss"));
    if (!rec->start(url, cameraDir() + "/" + name))
        return QString();
    // 维护跨页录像运行时状态（CameraView 切出销毁后依据此恢复）
    if (!camCamIds_.contains(camId))
        camCamIds_.append(camId);
    camRecOn_ = true;
    if (camRecStart_ == 0)
        camRecStart_ = QDateTime::currentMSecsSinceEpoch();
    return name;
}

bool TelemetryBridge::stopCameraRecord() {
    bool any = false;
    for (auto it = recorders_.begin(); it != recorders_.end(); ++it) {
        if (it.value()->recording()) {
            it.value()->stop();
            any = true;
        }
    }
    // 释放全部录制器对象（next frame 前 stop() 已完成异步收尾入队）。
    // 原实现 recorders_ 只增不减：反复开关录像会在哈希表累积已停止的
    // RtspRecorder 对象（长期运行资源泄漏）。录制器 stop 后不再可复用，
    // 下次 startCameraRecord 会重建新实例。
    for (auto it = recorders_.begin(); it != recorders_.end(); ++it)
        it.value()->deleteLater();
    recorders_.clear();
    // 无论是否有路已录，都复位运行时状态（切页后 UI 依据此值恢复）
    camCamIds_.clear();
    camRecOn_ = false;
    camRecStart_ = 0;
    return any;
}

QVariantList TelemetryBridge::cameraRecordingCams() const {
    QVariantList list;
    for (const QString &id : camCamIds_)
        list.append(id);
    return list;
}

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
    if (!recordEnabled() || !serial_)
        return;
    // serial_ 在工作线程，需跨线程投递 isOpen（不能直接调用）
    bool serialOpen = false;
    QMetaObject::invokeMethod(serial_, "isOpen", Qt::BlockingQueuedConnection,
                              Q_RETURN_ARG(bool, serialOpen));
    if (!serialOpen)
        return;
    // 目录：优先用户配置，否则软件目录/data
    QString dir = recordDir();
    if (dir.isEmpty())
        dir = dataDir();
    QDir().mkpath(dir);
    // 文件名：打开串口时间（含毫秒，避免同秒重开覆盖）telemetry_20260813_143025_123.csv
    const QString ts = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz");
    recordPath_ = dir + QStringLiteral("/telemetry_") + ts + QStringLiteral(".csv");
    recordFile_.setFileName(recordPath_);
    // 二进制写入：逐帧原始报文需保持字节一致，Text 模式在 Windows 会把 \n 转 \r\n
    if (!recordFile_.open(QIODevice::WriteOnly))
        return;
    const QByteArray header = QByteArray("\xEF\xBB\xBF") // UTF-8 BOM
        + "# 灵云01 地面站遥测原始记录\n"
        + "# 开始时间: " + QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss").toUtf8() + "\n"
        + "# 格式: 每行一帧原始报文（AA55 帧头 + JSON），utf-8\n";
    recordFile_.write(header);
    flushTimer_.start(); // 定时批量落盘
}
void TelemetryBridge::stopRecording() {
    flushTimer_.stop();
    if (recordFile_.isOpen())
        recordFile_.flush(); // 停止前落盘残留数据
    if (recordFile_.isOpen())
        recordFile_.close();
    recordPath_.clear();
}
void TelemetryBridge::onRawFrame(const QByteArray &frame) {
    if (!recordFile_.isOpen())
        return;
    recordFile_.write(frame); // 由 flushTimer_ 定时落盘，避免阻塞 GUI 线程
}

} // namespace lgs
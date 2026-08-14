// 桥接层 · 数据记录领域：逐帧原始报文自动落盘、目录管理。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include "comms/serial_manager.h"
#include <QDir>
#include <QDateTime>
#include <QCoreApplication>
#include <QMetaObject>

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
#pragma once
#include <QObject>
#include <QSerialPort>
#include <QStringList>
#include <QTimer>
#include <QElapsedTimer>
#include <memory>
#include "model/telemetry_data.h"

namespace lgs {

class FrameParser;

class SerialManager : public QObject {
    Q_OBJECT
public:
    explicit SerialManager(QObject *parent = nullptr);
    ~SerialManager() override;

    Q_INVOKABLE bool open(const QString &port, qint32 baud);
    Q_INVOKABLE void close();
    Q_INVOKABLE bool isOpen() const;
    Q_INVOKABLE QString errorString() const;
    Q_INVOKABLE QString lastOpenError() const;  // 最近一次 open 失败的具体原因
    Q_INVOKABLE QStringList availablePorts() const;

    // 链路超时看门狗（决策：弥补机载侧重连期间地面站无感知的盲区）：
    // 超过该时间未收到任何帧内数据则判定链路停滞，置离线。
    void setLinkTimeoutMs(int ms);

signals:
    void telemetryReceived(const lgs::TelemetryData &data);
    void rawFrameReceived(const QByteArray &frame);  // 完整原始帧（AA55 帧头 + JSON）
    void linkStatusChanged(bool connected);
    void errorOccurred(const QString &msg);

private slots:
    void onReadyRead();
    void onError(QSerialPort::SerialPortError err);
    void onLinkWatchdog();

private:
    // serial_/watchdog_ 必须为 SerialManager 的 child（new Xxx(this)），
    // moveToThread 会递归迁移 child 的 thread affinity。
    // 若用值成员，其 affinity 停留在构造线程（主线程），
    // 工作线程内 open/onReadyRead 直接操作将构成跨线程 UB。
    QSerialPort *serial_ = nullptr;
    std::unique_ptr<FrameParser> parser_;
    QTimer *watchdog_ = nullptr;   // 链路超时看门狗
    QElapsedTimer rxClock_;    // 距上次收到帧的时间源
    bool linkOnline_ = false;  // 当前链路在线状态（避免看门狗重复置离线）
    int linkTimeoutMs_ = 3000; // 默认 3s，与协议离线判定一致
    QString lastOpenError_;    // 最近一次 open 失败的具体原因（供 QML 透出）
};

} // namespace lgs

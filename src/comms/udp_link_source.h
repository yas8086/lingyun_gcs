#pragma once
#include <QObject>
#include <QUdpSocket>
#include <QElapsedTimer>
#include <QTimer>
#include <memory>
#include "model/telemetry_data.h"
#include "comms/frame_parser.h"

namespace lgs {

// 数传网口 UDP 接收源（协议 2.1：机载 link_node 向地面站 UDP 端口定向单播下传，
// 帧格式与串口一致 AA 55 [JSON]\n，默认端口 20000）。
// 与 SerialManager 职责对等：监听 UDP → 复用 FrameParser 定帧 + json_decoder 解码 →
// 产出 telemetryReceived/rawFrameReceived，供 DataBus 统一分发。
// UDP readyRead 为非阻塞事件驱动，在主线程运行即可（无需独立线程）。
class UdpLinkSource : public QObject {
    Q_OBJECT
public:
    explicit UdpLinkSource(QObject *parent = nullptr);

    bool start(quint16 port);
    void stop();
    bool isRunning() const { return sock_ && sock_->state() == QAbstractSocket::BoundState; }
    quint16 port() const { return port_; }

    // 链路超时看门狗（与串口一致，默认 3s）：超时未收到帧判定链路离线
    void setLinkTimeoutMs(int ms);

signals:
    void telemetryReceived(const lgs::TelemetryData &data);
    void rawFrameReceived(const QByteArray &frame);   // 完整原始帧（AA55 + JSON）
    void linkStatusChanged(bool online);
    void errorOccurred(const QString &msg);

private slots:
    void onReadyRead();
    void onWatchdog();

private:
    QUdpSocket *sock_ = nullptr;
    std::unique_ptr<FrameParser> parser_;
    QTimer *watchdog_ = nullptr;
    QElapsedTimer rxClock_;
    bool online_ = false;
    quint16 port_ = 0;
    int timeoutMs_ = 3000;
};

} // namespace lgs
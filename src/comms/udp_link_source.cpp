#include "comms/udp_link_source.h"
#include "comms/json_decoder.h"

namespace lgs {

UdpLinkSource::UdpLinkSource(QObject *parent)
    : QObject(parent)
    , sock_(new QUdpSocket(this))
    , parser_(std::make_unique<FrameParser>())
    , watchdog_(new QTimer(this)) {
    connect(sock_, &QUdpSocket::readyRead, this, &UdpLinkSource::onReadyRead);
    watchdog_->setInterval(500);
    watchdog_->setSingleShot(false);
    connect(watchdog_, &QTimer::timeout, this, &UdpLinkSource::onWatchdog);
}

bool UdpLinkSource::start(quint16 port) {
    stop(); // 重新绑定前先清理旧状态
    parser_ = std::make_unique<FrameParser>(); // 清空旧缓冲
    if (!sock_->bind(QHostAddress::AnyIPv4, port,
                     QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        emit errorOccurred(QStringLiteral("UDP 监听端口 %1 绑定失败：%2")
                               .arg(port).arg(sock_->errorString()));
        return false;
    }
    port_ = sock_->localPort(); // 实际绑定端口（传入 0 时由系统分配，测试/联调用）
    online_ = true;
    rxClock_.start();
    watchdog_->start();
    emit linkStatusChanged(true);
    return true;
}

void UdpLinkSource::stop() {
    watchdog_->stop();
    online_ = false;
    if (sock_->state() == QAbstractSocket::BoundState)
        sock_->close();
    emit linkStatusChanged(false);
}

void UdpLinkSource::setLinkTimeoutMs(int ms) {
    timeoutMs_ = qMax(200, ms);
}

void UdpLinkSource::onReadyRead() {
    while (sock_->hasPendingDatagrams()) {
        QByteArray buf;
        buf.resize(int(sock_->pendingDatagramSize()));
        if (buf.isEmpty())
            continue;
        sock_->readDatagram(buf.data(), buf.size());
        parser_->push(buf);
    }
    QByteArray json;
    bool gotFrame = false;
    while (parser_->takeFrame(json)) {
        gotFrame = true;
        // 保留完整原始帧（AA55 + JSON + \n）供回放/复现（与串口格式一致）
        emit rawFrameReceived(kFrameHead + json + "\n");
        TelemetryData data;
        if (decodeJson(json, data))
            emit telemetryReceived(data);
    }
    if (gotFrame) {
        rxClock_.restart(); // 收到有效帧即重置超时计时
        if (!online_) {
            online_ = true;
            emit linkStatusChanged(true); // 链路恢复
        }
    }
}

void UdpLinkSource::onWatchdog() {
    if (!isRunning() || !online_)
        return;
    if (rxClock_.elapsed() >= timeoutMs_) {
        online_ = false;
        emit linkStatusChanged(false); // 长时间无数据，链路停滞，置离线
    }
}

} // namespace lgs
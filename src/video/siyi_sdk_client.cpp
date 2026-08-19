#include "video/siyi_sdk_client.h"

#include <QDebug>

namespace lgs {

// 帧字段偏移
enum FrameField {
    OFF_STX = 0,      // 2B
    OFF_CTRL = 2,     // 1B
    OFF_LEN = 3,      // 2B LE
    OFF_SEQ = 5,      // 2B LE
    OFF_CMD = 7,      // 1B
    OFF_DATA = 8,
};

SiyiSdkClient::SiyiSdkClient(QObject *parent)
    : QObject(parent)
{
    sock_ = new QUdpSocket(this);
    connect(sock_, &QUdpSocket::readyRead, this, &SiyiSdkClient::onReadyRead);

    poll_ = new QTimer(this);
    poll_->setInterval(200);
    connect(poll_, &QTimer::timeout, this, &SiyiSdkClient::pollAttitude);

    alive_ = new QTimer(this);
    alive_->setSingleShot(true);
    alive_->setInterval(800);
    connect(alive_, &QTimer::timeout, this, [this]() { setConnected(false); });
}

void SiyiSdkClient::start(const QString &ip, quint16 port)
{
    stop();
    target_ = QHostAddress(ip);
    port_ = port;
    if (target_.isNull()) {
        qWarning() << "[SiyiSdk] 无效 IP:" << ip;
        return;
    }
    if (!sock_->bind(QHostAddress::AnyIPv4, 0, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        // 绑定失败（端口/权限等）：静默重试会表现为"永远连不上"且无提示，必须显式告警
        qWarning() << "[SiyiSdk] UDP 绑定失败:" << sock_->errorString();
        setConnected(false);
        return;
    }
    poll_->start();
    qInfo() << "[SiyiSdk] 会话启动 →" << ip << ":" << port;
}

void SiyiSdkClient::stop()
{
    poll_->stop();
    alive_->stop();
    if (sock_->state() == QAbstractSocket::BoundState)
        sock_->close();
    setConnected(false);
}

quint16 SiyiSdkClient::crc16(const char *data, int len)
{
    // CRC16-XMODEM：poly 0x1021，init 0（与手册示例报文验证一致）
    quint16 crc = 0;
    for (int i = 0; i < len; ++i) {
        crc ^= quint8(data[i]) << 8;
        for (int b = 0; b < 8; ++b) {
            if (crc & 0x8000)
                crc = quint16((crc << 1) ^ 0x1021);
            else
                crc = quint16(crc << 1);
        }
    }
    return crc;
}

void SiyiSdkClient::send(quint8 cmd, const QByteArray &data)
{
    if (target_.isNull() || sock_->state() != QAbstractSocket::BoundState)
        return;
    // 组帧：55 66 | 01 | len LE | seq LE | cmd | data | crc LE
    QByteArray f;
    f.reserve(OFF_DATA + data.size() + 2);
    f.append(char(0x55)); f.append(char(0x66));           // STX
    f.append(char(0x01));                                 // CTRL=need_ack
    const quint16 len = quint16(data.size());
    f.append(char(len & 0xFF)); f.append(char(len >> 8)); // Data_len LE
    f.append(char(seq_ & 0xFF)); f.append(char(seq_ >> 8));
    f.append(char(cmd));
    f.append(data);
    const quint16 crc = crc16(f.constData(), f.size());
    f.append(char(crc & 0xFF)); f.append(char(crc >> 8)); // CRC LE
    seq_++;
    sock_->writeDatagram(f, target_, port_);
}

void SiyiSdkClient::pollAttitude()
{
    send(0x0D, QByteArray());
}

void SiyiSdkClient::ctrlMove(int yaw, int pitch)
{
    const int y = qBound(-100, yaw, 100);
    const int p = qBound(-100, pitch, 100);
    // 0x07：turn_yaw(int8) + turn_pitch(int8) + reserved(uint8)
    QByteArray d;
    d.append(char(qint8(y)));
    d.append(char(qint8(p)));
    d.append(char(0));
    send(0x07, d);
}

void SiyiSdkClient::center()
{
    QByteArray d;
    d.append(char(1));   // center_pos=1 触发回中
    send(0x08, d);
}

void SiyiSdkClient::onReadyRead()
{
    while (sock_->hasPendingDatagrams()) {
        QByteArray buf;
        buf.resize(int(sock_->pendingDatagramSize()));
        sock_->readDatagram(buf.data(), buf.size());
        parseAck(buf);
    }
}

void SiyiSdkClient::parseAck(const QByteArray &f)
{
    // 最短 ACK：头 8B + CRC 2B = 10B
    if (f.size() < OFF_DATA + 2)
        return;
    if (quint8(f[OFF_STX]) != 0x55 || quint8(f[OFF_STX + 1]) != 0x66)
        return;
    if (!(quint8(f[OFF_CTRL]) & 0x02))   // 非 ack 包
        return;
    const int dataLen = quint8(f[OFF_LEN]) | (quint8(f[OFF_LEN + 1]) << 8);
    if (f.size() < OFF_DATA + dataLen + 2)
        return;
    // CRC 校验（覆盖帧头到 DATA 末尾）
    const quint16 calc = crc16(f.constData(), OFF_DATA + dataLen);
    const quint16 recv = quint8(f[OFF_DATA + dataLen]) | (quint8(f[OFF_DATA + dataLen + 1]) << 8);
    if (calc != recv)
        return;

    const quint8 cmd = quint8(f[OFF_CMD]);
    if (cmd == 0x0D && dataLen >= 12) {
        // 姿态：6×int16 LE，÷10 为实际角度
        auto rd16 = [&](int off) -> qint16 {
            return qint16(quint16(quint8(f[OFF_DATA + off]))
                          | (quint16(quint8(f[OFF_DATA + off + 1])) << 8));
        };
        yaw_ = rd16(0) / 10.0;
        pitch_ = rd16(2) / 10.0;
        roll_ = rd16(4) / 10.0;
        emit attitudeChanged();
    }
    setConnected(true);
    alive_->start();   // 有合法 ACK：保活
}

void SiyiSdkClient::setConnected(bool on)
{
    if (connected_ == on)
        return;
    connected_ = on;
    emit connectedChanged();
}

} // namespace lgs

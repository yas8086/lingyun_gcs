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

    probeSock_ = new QUdpSocket(this);
    // 探测 socket：ICMP 端口不可达 → ConnectionRefusedError（目标端口无服务）
    connect(probeSock_, &QUdpSocket::errorOccurred,
            this, &SiyiSdkClient::onProbeError);
    connect(probeSock_, &QUdpSocket::readyRead,
            this, &SiyiSdkClient::onProbeReply);
    probeTimer_.setSingleShot(true);
    probeTimer_.setInterval(1500);   // 1.5s 内无 ICMP 错误/回包 → 视为设备没通电/没联网
    connect(&probeTimer_, &QTimer::timeout, this, &SiyiSdkClient::onProbeTimeout);

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
    probeDevice();
    qInfo() << "[SiyiSdk] 会话启动 →" << ip << ":" << port;
}

void SiyiSdkClient::stop()
{
    poll_->stop();
    alive_->stop();
    probeTimer_.stop();
    if (probeSock_->state() == QAbstractSocket::BoundState
        || probeSock_->state() == QAbstractSocket::ConnectedState)
        probeSock_->close();
    if (sock_->state() == QAbstractSocket::BoundState)
        sock_->close();
    portClosed_ = false;   // 重置：下次 start 重新探测（区分"选错云台"vs"设备没通电"）
    // P2-3：清零姿态值并通知，避免 QML 离线后仍显示残留旧角度
    if (pitch_ != 0 || yaw_ != 0 || roll_ != 0) {
        pitch_ = yaw_ = roll_ = 0;
        emit attitudeChanged();
    }
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

QByteArray SiyiSdkClient::buildFrame(quint8 cmd, const QByteArray &data)
{
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
    return f;
}

void SiyiSdkClient::send(quint8 cmd, const QByteArray &data)
{
    if (target_.isNull() || sock_->state() != QAbstractSocket::BoundState)
        return;
    sock_->writeDatagram(buildFrame(cmd, data), target_, port_);
}

void SiyiSdkClient::pollAttitude()
{
    send(0x0D, QByteArray());
}

void SiyiSdkClient::ctrlMove(int yaw, int pitch)
{
    const int y = qBound(-100, yaw, 100);
    const int p = qBound(-100, pitch, 100);
    // 0x07：turn_yaw(int8) + turn_pitch(int8)——严格 2 字节数据（与手册示例
    // 报文 55 66 01 02 00 00 00 07 64 64 3d cf 一致；多余的保留字节会导致
    // A2 mini 固件解析异常：松手发 0 后云台不停止反而自动回中往下照）
    QByteArray d;
    d.append(char(qint8(y)));
    d.append(char(qint8(p)));
    send(0x07, d);
}

void SiyiSdkClient::center()
{
    QByteArray d;
    d.append(char(1));   // center_pos=1 触发回中
    send(0x08, d);
}

void SiyiSdkClient::setPitchAngle(double pitchDeg)
{
    // 0x0E 设置云台控制角度：yaw(int16 LE) + pitch(int16 LE)，值为 角度×10（精度 0.1°）
    // A2 mini 仅 pitch 有效（范围 -90.0~+25.0），yaw 不支持，填 0。
    const int yaw10 = 0;
    const int pitch10 = qBound(-900, qRound(pitchDeg * 10.0), 250);   // -90.0~+25.0 → -900~250
    QByteArray d;
    d.append(char(yaw10 & 0xFF)); d.append(char((yaw10 >> 8) & 0xFF));
    d.append(char(pitch10 & 0xFF)); d.append(char((pitch10 >> 8) & 0xFF));
    send(0x0E, d);
    qInfo() << "[SiyiSdk] 设置俯仰角度:" << pitchDeg << "° (0x0E pitch10=" << pitch10 << ")";
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

// 设备探测：向目标 IP:37260 发一条无害命令（0x0D 查询姿态），监听 ICMP 端口不可达。
// 若目标端口无思翼服务（如误配为思翼的云卓相机，其控制端口为 5000），系统返回 ICMP
// Port Unreachable → QUdpSocket errorOccurred(ConnectionRefusedError)。
// 注意：Linux 下 UDP 必须 connectToHost 后，内核才把 ICMP 错误上报给应用（未 connect 的 sendto 默认丢弃）。
void SiyiSdkClient::probeDevice()
{
    if (target_.isNull())
        return;
    if (probeSock_->state() != QAbstractSocket::UnconnectedState)
        probeSock_->abort();
    // UDP connect 是即时的（无需握手），此后 write 发送并能在 ICMP 错误时触发 errorOccurred
    probeSock_->connectToHost(target_, port_);
    portClosed_ = false;
    // 先经主 socket 发一条 0x0D 姿态查询（真思翼回 ACK → parseAck → setConnected(true)），
    // 再用探测 socket 发一次（无监听服务时内核回 ICMP port unreachable → onProbeError 判选错；
    // 设备没通电/没联网 → 无回包无 ICMP → onProbeTimeout，不判选错）。
    send(0x0D, QByteArray());
    probeSock_->write(buildFrame(0x0D, QByteArray()));
    probeTimer_.start();
}

void SiyiSdkClient::onProbeError(QAbstractSocket::SocketError err)
{
    // 仅 ICMP 端口不可达判定为非思翼设备；其余错误忽略（交给超时兜底）
    if (err != QAbstractSocket::ConnectionRefusedError)
        return;
    probeTimer_.stop();
    portClosed_ = true;   // 明确"设备 IP 在线但 37260 端口无思翼服务"→ 可用作"选错云台类型"判据
    qWarning() << "[SiyiSdk] 设备探测：目标" << target_.toString() << ":" << port_
               << "端口无服务（非思翼设备？请检查云台类型配置）";
    emit probeFinished();
}

void SiyiSdkClient::onProbeReply()
{
    // 目标 37260 端口有 UDP 响应 → 思翼设备存在（真思翼会回 ACK）。
    // 注意：Linux 上 ICMP port unreachable 可能表现为 readyRead（read 就绪）而非 errorOccurred，
    // 此时 readDatagram 返回 -1/ECONNREFUSED 且无有效数据 → 应视为"端口无服务"而非"有响应"
    bool gotData = false;
    while (probeSock_->hasPendingDatagrams()) {
        QByteArray d;
        d.resize(int(probeSock_->pendingDatagramSize()));
        const qint64 n = probeSock_->readDatagram(d.data(), d.size());
        if (n < 0) { gotData = false; break; }
        gotData = true;
    }
    probeTimer_.stop();
    if (!gotData) {
        // ICMP port unreachable（无实际数据）→ 端口无思翼服务 → 判"选错云台"
        portClosed_ = true;
        qWarning() << "[SiyiSdk] 设备探测：目标" << target_.toString() << ":" << port_
                   << "端口无服务（非思翼设备？请检查云台类型配置）";
    } else {
        qInfo() << "[SiyiSdk] 设备探测：目标有响应，确认思翼设备在线";
    }
    emit probeFinished();
}

void SiyiSdkClient::onProbeTimeout()
{
    // 1.5s 无回包也无 ICMP 错误：多为设备没通电/没联网（IP 无响应）
    // → 不判"选错云台"（portClosed_ 保持 false），由上层提示检查供电/网络
    qInfo() << "[SiyiSdk] 设备探测：超时无响应（设备可能未通电/未联网）";
    emit probeFinished();
}

} // namespace lgs

#include "video/skydroid_sdk_client.h"

#include <QDebug>

namespace lgs {

SkydroidSdkClient::SkydroidSdkClient(QObject *parent)
    : QObject(parent)
{
    sock_ = new QUdpSocket(this);
    probeSock_ = new QUdpSocket(this);
    // 探测 socket：ICMP 端口不可达 → ConnectionRefusedError（目标端口无服务）
    connect(probeSock_, &QUdpSocket::errorOccurred,
            this, &SkydroidSdkClient::onProbeError);
    connect(probeSock_, &QUdpSocket::readyRead,
            this, &SkydroidSdkClient::onProbeReply);
    probeTimer_.setSingleShot(true);
    probeTimer_.setInterval(1500);   // 1.5s 内无 ICMP 错误即视为设备存在
    connect(&probeTimer_, &QTimer::timeout,
            this, &SkydroidSdkClient::onProbeTimeout);
    // 主 socket 收包：解析云卓回包（GAC 姿态帧 / SLR 测距帧）
    connect(sock_, &QUdpSocket::readyRead,
            this, &SkydroidSdkClient::onReadyRead);
}

void SkydroidSdkClient::start(const QString &ip, quint16 port)
{
    stop();
    target_ = QHostAddress(ip);
    port_ = port;
    if (target_.isNull()) {
        qWarning() << "[SkydroidSdk] 无效 IP:" << ip;
        return;
    }
    if (!sock_->bind(QHostAddress::AnyIPv4, 0, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qWarning() << "[SkydroidSdk] UDP 绑定失败:" << sock_->errorString();
        return;
    }
    started_ = true;
    qInfo() << "[SkydroidSdk] 会话启动 →" << ip << ":" << port;
    emit connectedChanged();
    probeDevice();
}

void SkydroidSdkClient::stop()
{
    probeTimer_.stop();
    // 关闭已使能的姿态主动回读（在 socket 关闭前发送 GAA00），避免设备持续空耗推送
    for (const QString &ip : gaaEnabledIps_)
        sendText(ip, buildCmdHex("#TPUG2wGAA", "00"));
    gaaEnabledIps_.clear();
    if (probeSock_->state() == QAbstractSocket::BoundState
        || probeSock_->state() == QAbstractSocket::ConnectedState)
        probeSock_->close();
    if (sock_->state() == QAbstractSocket::BoundState)
        sock_->close();
    started_ = false;
    devicePresent_ = false;   // 下次 start 重新探测（探测完成前视为不存在，由结果决定）
    gotReply_ = false;
    states_.clear();         // 清空所有 IP 的姿态/测距状态
    knownIps_.clear();       // 清空已发送过命令的 IP 集合（避免跨会话旧 IP 残留影响归属判断）
    emit connectedChanged();
}

// ---- 按 IP 查询姿态/测距状态（头文件已声明，此处补实现）----
bool SkydroidSdkClient::attitudeAlive(const QString &ip) const
{
    auto it = states_.constFind(ip);
    return it != states_.constEnd() && it.value().alive;
}
double SkydroidSdkClient::yaw(const QString &ip) const
{
    auto it = states_.constFind(ip);
    return it != states_.constEnd() ? it.value().yaw : 0.0;
}
double SkydroidSdkClient::pitch(const QString &ip) const
{
    auto it = states_.constFind(ip);
    return it != states_.constEnd() ? it.value().pitch : 0.0;
}
double SkydroidSdkClient::roll(const QString &ip) const
{
    auto it = states_.constFind(ip);
    return it != states_.constEnd() ? it.value().roll : 0.0;
}
double SkydroidSdkClient::ranging(const QString &ip) const
{
    auto it = states_.constFind(ip);
    return it != states_.constEnd() ? it.value().ranging : 0.0;
}
bool SkydroidSdkClient::protocolAlive(const QString &ip) const
{
    auto it = states_.constFind(ip);
    return it != states_.constEnd() && it.value().protoAlive;
}

// 设备探测：向目标 IP:5000 发一条无害命令（GSY00 停止转动），
// 监听 ICMP 端口不可达。若目标端口无服务（如误配为云卓的思翼相机，其控制端口为 37260），
// 系统返回 ICMP Port Unreachable → QUdpSocket errorOccurred(ConnectionRefusedError)。
// 注意：Linux 下 UDP 必须 connectToHost 后，内核才把 ICMP 错误上报给应用（未 connect 的 sendto 默认丢弃）。
void SkydroidSdkClient::probeDevice()
{
    if (!started_ || target_.isNull())
        return;
    if (probeSock_->state() != QAbstractSocket::UnconnectedState)
        probeSock_->abort();
    // UDP connect 是即时的（无需握手），此后 write 发送并能在 ICMP 错误时触发 errorOccurred
    probeSock_->connectToHost(target_, port_);
    gotReply_ = false;       // 本轮探测尚未收到回包
    devicePresent_ = true;   // 探测期间乐观默认（结果由 onProbeReply/onProbeError/onProbeTimeout 最终确定）
    const QString probe = buildCmdHex("#TPUG2wGSY", "00");   // 航向停止（无害）
    qInfo() << "[SkydroidSdk] 设备探测 TX:" << probe;
    probeSock_->write(probe.toUtf8());
    // 同时用主 socket 发一次探测命令：若目标是真云卓，其回包（#TP 前缀）会进入
    // onReadyRead→parseReply，置 protocolAlive（"确为云卓设备"的最可靠判据）。
    // 思翼等设备 5000 无云卓服务，即使有杂散 UDP 回包也不含 #TP → protoAlive 保持 false。
    sendText(target_.toString(), probe);
    probeTimer_.start();
}

void SkydroidSdkClient::onProbeError(QAbstractSocket::SocketError err)
{
    // 仅 ICMP 端口不可达判定为非云卓设备；其余错误忽略（交给超时兜底）
    if (err != QAbstractSocket::ConnectionRefusedError)
        return;
    probeTimer_.stop();
    devicePresent_ = false;
    qWarning() << "[SkydroidSdk] 设备探测：目标" << target_.toString() << ":" << port_
               << "端口无服务（非云卓设备？请检查云台类型配置）";
    emit probeFinished();
}

void SkydroidSdkClient::onProbeReply()
{
    // 目标 5000 端口有 UDP 响应 → 存在云卓设备（真云卓控制服务会回包）
    while (probeSock_->hasPendingDatagrams())
        probeSock_->readDatagram(nullptr, 0);
    probeTimer_.stop();
    gotReply_ = true;
    devicePresent_ = true;
    qInfo() << "[SkydroidSdk] 设备探测：目标有响应，确认云卓设备在线";
    emit probeFinished();
}

void SkydroidSdkClient::onProbeTimeout()
{
    // 1.5s 无回包也无 ICMP 错误：按"是否收到回包"判定。
    // 真云卓 5000 有控制服务会回包 → 存在；思翼等嵌入式设备 5000 无服务可能不回 ICMP → 无回包 → 不存在。
    devicePresent_ = gotReply_;
    qInfo() << "[SkydroidSdk] 设备探测：超时无错误，收到回包=" << gotReply_
            << "→" << (devicePresent_ ? "设备存在" : "设备不存在（非云卓？）");
    emit probeFinished();
}

// CRC：对「前缀+数据」逐字符 ASCII 累加和 & 0xFF，转大写 2 位 HEX
static QString crcOf(const QString &body)
{
    int sum = 0;
    for (const QChar &c : body)
        sum = (sum + c.unicode()) & 0xFF;
    return QStringLiteral("%1").arg(sum, 2, 16, QLatin1Char('0')).toUpper();
}

QString SkydroidSdkClient::buildCmd(const char *prefix, int dataByte)
{
    // 数据位：有符号 int8 的 2 位大写 HEX（如 +100→64 / -100→9C / 0→00）
    const int v = qBound(-128, dataByte, 127);
    return buildCmdHex(prefix, QStringLiteral("%1").arg(v & 0xFF, 2, 16, QLatin1Char('0')).toUpper().toLatin1().constData());
}

QString SkydroidSdkClient::buildCmdHex(const char *prefix, const char *dataHex)
{
    const QString body = QString::fromLatin1(prefix) + QString::fromLatin1(dataHex);
    return body + crcOf(body);
}

void SkydroidSdkClient::sendText(const QString &ip, const QString &cmd)
{
    if (!started_ || sock_->state() != QAbstractSocket::BoundState)
        return;
    const QHostAddress dest(ip);
    if (dest.isNull())
        return;
    knownIps_.insert(ip);   // 记录已发送过命令的相机 IP，用于回包归属判断
    qDebug() << "[SkydroidSdk] TX:" << cmd << "→" << ip;
    sock_->writeDatagram(cmd.toUtf8(), dest, port_);
}

void SkydroidSdkClient::ctrlYaw(const QString &ip, int speed)
{
    sendText(ip, buildCmd("#TPUG2wGSY", speed));
}

void SkydroidSdkClient::ctrlPitch(const QString &ip, int speed)
{
    sendText(ip, buildCmd("#TPUG2wGSP", speed));
}

void SkydroidSdkClient::ctrlMove(const QString &ip, int yaw, int pitch)
{
    ctrlYaw(ip, yaw);
    ctrlPitch(ip, pitch);
}

void SkydroidSdkClient::center(const QString &ip)
{
    // 一键回中（RCSDK SkydroidGimbalControlCore.akey(AKey.MID) → #TPUG2wPTZ05）
    sendText(ip, buildCmdHex("#TPUG2wPTZ", "05"));
}

void SkydroidSdkClient::zoom(const QString &ip, int dir)
{
    // 变焦（RCSDK TopCameraCore.addZoomRatios/subtractZoomRatios）：0A 放大 / 0B 缩小
    sendText(ip, buildCmdHex("#TPUD2wDZM", dir > 0 ? "0A" : "0B"));
}

void SkydroidSdkClient::setTeleLens(const QString &ip)
{
    // 长焦镜头（RCSDK ZoomForLens.TELEPHOTO_LENS → #TPUD2wDZM0C）
    sendText(ip, buildCmdHex("#TPUD2wDZM", "0C"));
}

void SkydroidSdkClient::setWideLens(const QString &ip)
{
    // 广角镜头（RCSDK ZoomForLens.WIDE_LENS → #TPUD2wDZM0D）
    sendText(ip, buildCmdHex("#TPUD2wDZM", "0D"));
}

void SkydroidSdkClient::takePicture(const QString &ip)
{
    sendText(ip, buildCmdHex("#TPUD2wCAP", "01"));
}

void SkydroidSdkClient::startRecordVideo(const QString &ip)
{
    sendText(ip, buildCmdHex("#TPUD2wREC", "01"));
}

void SkydroidSdkClient::stopRecordVideo(const QString &ip)
{
    sendText(ip, buildCmdHex("#TPUD2wREC", "00"));
}

// 姿态回读开关：#TPUG2wGAA<01=1Hz / 00=关闭>（协议 v1.1.5 3.3.2）
void SkydroidSdkClient::setAttitudeReport(const QString &ip, bool on)
{
    states_[ip].alive = false;   // 重新使能时重置该 IP 的存活标记
    if (on) gaaEnabledIps_.insert(ip);
    else gaaEnabledIps_.remove(ip);
    sendText(ip, buildCmdHex("#TPUG2wGAA", on ? "01" : "00"));
    qInfo() << "[SkydroidSdk] 姿态回读" << (on ? "使能(1Hz)" : "关闭") << "→" << ip;
}

// 单次激光测距：#TPUD2rSLR00（回包 #TPUD4rSLR X0X1X2X3 CC，分米）
void SkydroidSdkClient::requestRanging(const QString &ip)
{
    sendText(ip, buildCmdHex("#TPUD2rSLR", "00"));
}

// 主 socket 收包：读取全部 datagram，尝试解析云卓回包
void SkydroidSdkClient::onReadyRead()
{
    while (sock_->hasPendingDatagrams()) {
        QByteArray buf;
        buf.resize(int(sock_->pendingDatagramSize()));
        QHostAddress sender;
        quint16 senderPort = 0;
        sock_->readDatagram(buf.data(), buf.size(), &sender, &senderPort);
        // 回包来源 IP 归属：已向该 IP 发过命令（knownIps_ 含该 IP）说明该相机确实在应答，
        // 则按来源 IP 记录（多相机各自独立存储）；仅当 sender 为空或来源 IP 未知
        // （如设备多网卡/路由导致回包源 IP 与配置 IP 不同）时才兜底到会话主目标 target_。
        QString key = sender.toString();
        if (sender.isNull() || (key.isEmpty() ? false : !knownIps_.contains(key)))
            key = target_.toString();
        parseReply(key, QString::fromLatin1(buf));
    }
}

// 解析云卓回包（纯文本 ASCII），来源 IP 用于区分多相机：
//   姿态帧  #TPUGCrGAC Y0Y1Y2Y3 P0P1P2P3 R0R1R2R3 CC
//   测距帧  #TPUD4rSLR  X0X1X2X3 CC
// 注意：实测回包前缀可能是小写 "#tp"（如 #tpUGCrGAC00AD...），所有关键字匹配一律不区分大小写。
void SkydroidSdkClient::parseReply(const QString &ip, const QString &s)
{
    const QString t = s.trimmed();
    // 收到含 #TP（大小写均可）前缀的帧 → 该 IP 确为云卓设备（协议级应答，最可靠判据）。
    // 注意：必须在 GAC/SLR 具体解析之前置位，ACK 等其它回包同样算数。
    if (t.startsWith(QLatin1String("#TP"), Qt::CaseInsensitive)) {
        // P1-4：CRC 校验——帧尾 2 字符为 CRC（对「前缀+数据」ASCII 累加和 & 0xFF），
        // 不一致说明 UDP 丢/错字节，丢弃整帧，避免姿态/测距静默失真。
        if (t.length() >= 4) {
            const QString body = t.left(t.length() - 2);
            const QString recvCrc = t.right(2);
            if (crcOf(body).compare(recvCrc, Qt::CaseInsensitive) != 0) {
                qWarning() << "[SkydroidSdk] 回包 CRC 校验失败，丢弃:" << t;
                return;
            }
        }
        IpState &st0 = states_[ip];
        if (!st0.protoAlive) {
            st0.protoAlive = true;
            qInfo() << "[SkydroidSdk] 确认云卓设备回包（protoAlive=true）来自" << ip << ":" << t;
            emit attitudeChanged();   // 驱动 QML 端"设备确认"状态刷新
        }
    }
    // --- GAC 姿态帧：yaw/pitch/roll 各 4 字符十六进制有符号，0.01° ---
    if (t.contains("GAC", Qt::CaseInsensitive)) {
        // P0-1：4 位十六进制为 16 位有符号（如 "EC78" = -5000 = -50.00°），
        // 必须做符号扩展，否则负角度会解析成巨大正数（60536 → 605.36°）。
        auto rdAngle = [](const QString &hex) -> double {
            bool ok = false;
            const quint16 u = static_cast<quint16>(hex.toUInt(&ok, 16));
            if (!ok || hex.length() != 4)
                return 0.0;
            const qint16 v = static_cast<qint16>(u);   // 16 位有符号扩展
            return v / 100.0;                          // 0.01° → °
        };
        // 提取 Y/P/R 段：从 "GAC" 后取 12 字符（Y4 P4 R4）
        const int idx = t.indexOf("GAC", 0, Qt::CaseInsensitive);
        const QString rest = t.mid(idx + 3).trimmed();
        if (rest.length() >= 12) {
            IpState &st = states_[ip];
            st.yaw   = rdAngle(rest.mid(0, 4));
            st.pitch = rdAngle(rest.mid(4, 4));
            st.roll  = rdAngle(rest.mid(8, 4));
            st.alive = true;
            emit attitudeChanged();
            return;   // P2-2：return 仅在成功解析后执行；rest 不足时继续往下，避免吞掉 SLR
        }
    }
    // --- SLR 测距结果帧：#TPDU2rSLR XXXX CC ---
    // 真机实测回包为 2r 格式（如 #TPDU2rSLR0018BE，数据段 0018 = 24 分米 = 2.4m），
    // 而非协议文档中的 4r 格式——按实测格式解析，不再限定 4r 标识。
    // 帧结构：前缀 #TPDU2rSLR(10) + 数据 4 位 hex(4) + CRC(2) = 共 16 字符（SLR 后剩 6 字符）。
    // 过滤命令确认等数据段不足 4 hex 的帧（rest 长度 < 6）；数据 >0 才更新（0=无有效测距值）。
    if (t.contains("SLR", Qt::CaseInsensitive)) {
        const int idx = t.indexOf("SLR", 0, Qt::CaseInsensitive);
        const QString rest = t.mid(idx + 3).trimmed();
        if (rest.length() >= 6) {
            bool ok = false;
            const int dm = rest.left(4).toInt(&ok, 16);
            if (ok && dm > 0) {
                IpState &st = states_[ip];
                st.ranging = dm / 10.0;           // 分米 → 米
                qInfo() << "[SkydroidSdk] 测距结果" << (dm / 10.0) << "m（来自" << ip << ":" << t << "）";
            }
            emit rangingChanged();
        }
    }
}

} // namespace lgs

#include "video/skydroid_sdk_client.h"

#include <QDebug>

namespace lgs {

SkydroidSdkClient::SkydroidSdkClient(QObject *parent)
    : QObject(parent)
{
    sock_ = new QUdpSocket(this);
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
}

void SkydroidSdkClient::stop()
{
    if (sock_->state() == QAbstractSocket::BoundState)
        sock_->close();
    started_ = false;
    emit connectedChanged();
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

void SkydroidSdkClient::sendText(const QString &cmd)
{
    if (!started_ || target_.isNull() || sock_->state() != QAbstractSocket::BoundState)
        return;
    qDebug() << "[SkydroidSdk] TX:" << cmd;
    sock_->writeDatagram(cmd.toUtf8(), target_, port_);
}

void SkydroidSdkClient::ctrlYaw(int speed)
{
    sendText(buildCmd("#TPUG2wGSY", speed));
}

void SkydroidSdkClient::ctrlPitch(int speed)
{
    sendText(buildCmd("#TPUG2wGSP", speed));
}

void SkydroidSdkClient::ctrlMove(int yaw, int pitch)
{
    ctrlYaw(yaw);
    ctrlPitch(pitch);
}

void SkydroidSdkClient::center()
{
    // 一键回中（RCSDK SkydroidGimbalControlCore.akey(AKey.MID) → #TPUG2wPTZ05）
    sendText(buildCmdHex("#TPUG2wPTZ", "05"));
}

void SkydroidSdkClient::zoom(int dir)
{
    // 变焦（RCSDK TopCameraCore.addZoomRatios/subtractZoomRatios）：0A 放大 / 0B 缩小
    sendText(buildCmdHex("#TPUD2wDZM", dir > 0 ? "0A" : "0B"));
}

void SkydroidSdkClient::setTeleLens()
{
    // 长焦镜头（RCSDK ZoomForLens.TELEPHOTO_LENS → #TPUD2wDZM0C）
    sendText(buildCmdHex("#TPUD2wDZM", "0C"));
}

void SkydroidSdkClient::setWideLens()
{
    // 广角镜头（RCSDK ZoomForLens.WIDE_LENS → #TPUD2wDZM0D）
    sendText(buildCmdHex("#TPUD2wDZM", "0D"));
}

void SkydroidSdkClient::takePicture()
{
    sendText(buildCmdHex("#TPUD2wCAP", "01"));
}

void SkydroidSdkClient::startRecordVideo()
{
    sendText(buildCmdHex("#TPUD2wREC", "01"));
}

void SkydroidSdkClient::stopRecordVideo()
{
    sendText(buildCmdHex("#TPUD2wREC", "00"));
}

} // namespace lgs

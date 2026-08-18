#pragma once

#include <QObject>
#include <QHostAddress>
#include <QUdpSocket>
#include <QTimer>

namespace lgs {

// 思翼云台相机 SDK 客户端（A2 mini）。
// 协议：UDP 目标端口 37260；帧 = 55 66 | CTRL(1) | Data_len(2 LE) | SEQ(2 LE)
//       | CMD_ID(1) | DATA(n) | CRC16-XMODEM(2 LE)。
// 发送 CTRL=0x01（need_ack）；ACK 帧 CTRL=0x02。
// 已用手册两条示例报文验证 CRC16-XMODEM 与官方一致。
// 命令：0x0D 查询姿态（ACK 12B：yaw/pitch/roll/三轴角速度 int16 LE，÷10 为度）；
//       0x07 云台转向（turn_yaw/turn_pitch int8，-100~100，松手发 0）；
//       0x08 一键回中（center_pos=1）。A2 mini 仅俯仰轴有效。
class SiyiSdkClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(double pitch READ pitch NOTIFY attitudeChanged)   // 俯仰角（度）
    Q_PROPERTY(double yaw READ yaw NOTIFY attitudeChanged)       // 转向角（度，A2 mini 无效）
    Q_PROPERTY(double roll READ roll NOTIFY attitudeChanged)     // 横滚角（度，A2 mini 无效）
public:
    explicit SiyiSdkClient(QObject *parent = nullptr);

    // 开始会话：绑定本地随机端口，200ms 周期轮询姿态
    void start(const QString &ip, quint16 port = 37260);
    void stop();
    bool connected() const { return connected_; }
    double pitch() const { return pitch_; }
    double yaw() const { return yaw_; }
    double roll() const { return roll_; }

public slots:
    // 云台转向：speed -100~100（A2 mini 仅俯仰生效），松手发 0 停止
    void ctrlPitch(int speed);
    // 一键回中
    void center();

signals:
    void connectedChanged();
    void attitudeChanged();

private:
    void pollAttitude();                    // 发送 0x0D
    void send(quint8 cmd, const QByteArray &data);
    void onReadyRead();
    void parseAck(const QByteArray &f);
    void setConnected(bool on);

    static quint16 crc16(const char *data, int len);

    QUdpSocket *sock_ = nullptr;
    QTimer *poll_ = nullptr;       // 姿态轮询（200ms）
    QTimer *alive_ = nullptr;      // 800ms 无 ACK 判离线
    QHostAddress target_;
    quint16 port_ = 37260;
    quint16 seq_ = 0;
    bool connected_ = false;
    double pitch_ = 0, yaw_ = 0, roll_ = 0;
};

} // namespace lgs

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
// 设备探测：与云卓 SDK 相同的 ICMP 端口探测——目标 IP 在线但 37260 端口无思翼
// 服务（如云卓误配思翼）→ portClosed=true 判"选错云台"；仅超时无响应（没通电/没联网）
// → portClosed=false，与"选错"区分（见 portClosed() 注释）。
class SiyiSdkClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(double pitch READ pitch NOTIFY attitudeChanged)   // 俯仰角（度）
    Q_PROPERTY(double yaw READ yaw NOTIFY attitudeChanged)       // 转向角（度，A2 mini 无效）
    Q_PROPERTY(double roll READ roll NOTIFY attitudeChanged)     // 横滚角（度，A2 mini 无效）
public:
    explicit SiyiSdkClient(QObject *parent = nullptr);

    // 开始会话：绑定本地随机端口，200ms 周期轮询姿态，并启动 ICMP 端口探测
    void start(const QString &ip, quint16 port = 37260);
    void stop();
    bool connected() const { return connected_; }
    double pitch() const { return pitch_; }
    double yaw() const { return yaw_; }
    double roll() const { return roll_; }
    // 探测结论：true=设备 IP 在线但 37260 端口无思翼 UDP 服务（ICMP port unreachable）
    // → 确为"非思翼设备/选错云台"；false=已连接或有回包、或仅超时无响应（可能没通电/没联网）。
    // 与 connected 区别：本方法只响应"端口明确无服务"，不把"设备没通电"误判为选错云台
    bool portClosed() const { return portClosed_; }

public slots:
    // 云台转向（0x07）：yaw/pitch 各 -100~100（A2 mini 仅俯仰轴生效），松手发 0 停止
    void ctrlMove(int yaw, int pitch);
    // 一键回中（0x08）：触发默认回中（俯仰 0°）
    void center();
    // 设置云台俯仰角度（0x0E）：A2 mini 仅 pitch 有效，yaw 忽略；
    // pitchDeg 单位度，范围 -90.0~+25.0，精度 0.1°。用于自定义回中俯仰角。
    // 注：该命令实际是"设置目标角度"而非"回中"，但 ACK 返回的是当前角度而非新设角度值
    void setPitchAngle(double pitchDeg);

signals:
    void connectedChanged();
    void attitudeChanged();
    void probeFinished();    // 设备探测结束（ICMP 端口无服务 / 有响应 / 超时）

private:
    void pollAttitude();                    // 发送 0x0D
    QByteArray buildFrame(quint8 cmd, const QByteArray &data);   // 组帧（55 66 头 + CRC）
    void send(quint8 cmd, const QByteArray &data);
    void onReadyRead();
    void parseAck(const QByteArray &f);
    void setConnected(bool on);
    void probeDevice();                     // ICMP 端口探测（区分"选错云台"vs"没通电"）
    void onProbeError(QAbstractSocket::SocketError err);
    void onProbeReply();
    void onProbeTimeout();

    static quint16 crc16(const char *data, int len);

    QUdpSocket *sock_ = nullptr;
    QUdpSocket *probeSock_ = nullptr;      // 探测 socket（connectToHost 后 ICMP 错误可达）
    QTimer *poll_ = nullptr;       // 姿态轮询（200ms）
    QTimer *alive_ = nullptr;      // 800ms 无 ACK 判离线
    QTimer probeTimer_;            // 探测超时（1.5s 无 ICMP 错误/回包 → 视为设备没通电）
    QHostAddress target_;
    quint16 port_ = 37260;
    quint16 seq_ = 0;
    bool connected_ = false;
    bool portClosed_ = false;      // 探测到 ICMP port unreachable（IP 在线但端口无思翼服务）
    double pitch_ = 0, yaw_ = 0, roll_ = 0;
};

} // namespace lgs

#pragma once

#include <QObject>
#include <QHostAddress>
#include <QUdpSocket>
#include <QTimer>
#include <QHash>
#include <QSet>

namespace lgs {

// 云卓 C14PRO 云台相机 UDP 控制客户端。
// 协议（依据《云卓云台相机协议 v1.1.5》+ RCSDK COMMON，真机验证）：
//   纯文本 ASCII 命令，目标端口 5000；结构 = 前缀 + 数据 + CRC(2 位 HEX)
//   CRC = sum(ASCII(前缀+数据)) & 0xFF，转大写 2 位 HEX
// 控制命令（前缀 #TPUG2w / #TPUD2w）：
//   #TPUG2wGSY<速> 航向速度控制 / #TPUG2wGSP<速> 俯仰速度控制
//   #TPUG2wPTZ05   回中 / #TPUD2wCAP01 拍照 / #TPUD2wREC01|00 录像
//   #TPUD2wDZM0A|0B 变焦放大/缩小 / 0C|0D 长焦/广角镜头
//   #TPUD2rSLR00   单次激光测距（读回 X0X1X2X3，单位分米，5~1000 → 0.5~100m）
// 姿态回读（v1.1.5 协议确认支持，纠正"云卓无姿态回读"的旧结论）：
//   #TPUG2wGAA<Hz> 使能云台姿态主动送出（01~64=1~100Hz，00=关闭）
//   接收 #TPUGCrGAC Y0Y1Y2Y3 P0P1P2P3 R0R1R2R3 CC（yaw/pitch/roll，0.01°，
//   十六进制有符号字符，如 EC78 = -5000 = -50.00°）
//
// 按 IP 独立状态：支持多个相机配置成 skydroid 时各自向自己的 IP 发送命令，
// 姿态回读/测距结果按「来源 IP」分别记录（attitudeAlive(ip)/yaw(ip)/ranging(ip) 等），
// 从而能按相机判断"是否真的回读到姿态"——回读不到即提示可能选错云台类型。
class SkydroidSdkClient : public QObject {
    Q_OBJECT
public:
    explicit SkydroidSdkClient(QObject *parent = nullptr);

    // 开始会话：绑定本地随机端口，目标 C14PRO IP:5000，并启动设备探测
    void start(const QString &ip, quint16 port = 5000);
    void stop();
    // 目标 IP:5000 是否确认存在云卓设备（true=确认在线或未确认；false=确认端口无服务）
    bool devicePresent() const { return devicePresent_; }
    // 探测结论：设备 IP 在线但 5000 端口无云卓 UDP 服务（收到 ICMP port unreachable）
    // → 确为"非云卓设备"（选错云台类型）。用于与"设备没通电/未联网"（仅超时无响应，portClosed=false）区分。
    bool portClosed() const { return portClosed_; }
    // 当前绑定端口是否可发送（start 已成功）
    bool started() const { return started_; }

    // —— 按相机 IP 查询姿态回读/测距状态 ——
    // 最近是否收到过该 IP 的姿态回读帧（true=真实应答；false=未应答→可能选错云台类型）
    bool attitudeAlive(const QString &ip) const;
    double yaw(const QString &ip) const;
    double pitch(const QString &ip) const;
    double roll(const QString &ip) const;
    double ranging(const QString &ip) const;
    // 该 IP 是否收到过云卓协议帧（#TP 前缀回包：GAC 姿态 / SLR 测距 / ACK 等）。
    // 这是"目标确为云卓设备"的最可靠判据——思翼等设备即使 5000 端口有杂散 UDP
    // 回包，也不会回含 #TP 前缀的云卓协议帧。
    bool protocolAlive(const QString &ip) const;

public slots:
    // 云台速度控制（-100~100）：ip=目标相机 IP；yaw 航向 / pitch 俯仰，传 0 停止
    void ctrlMove(const QString &ip, int yaw, int pitch);
    void ctrlYaw(const QString &ip, int speed);
    void ctrlPitch(const QString &ip, int speed);
    // 一键回中（#TPUG2wPTZ05，RCSDK AKey.MID）
    void center(const QString &ip);
    // 变焦：ip=目标相机 IP；+1 放大（#TPUD2wDZM0A）/-1 缩小（#TPUD2wDZM0B）
    void zoom(const QString &ip, int dir);
    void zoomIn(const QString &ip) { zoom(ip, 1); }
    void zoomOut(const QString &ip) { zoom(ip, -1); }
    // 长短焦镜头切换：#TPUD2wDZM0C 长焦 / 0D 广角（C14PRO 100 倍混合变焦=短焦 59x+长焦 41x）
    void setTeleLens(const QString &ip);
    void setWideLens(const QString &ip);
    // 相机动作（ip=目标相机 IP）
    void takePicture(const QString &ip);
    void startRecordVideo(const QString &ip);
    void stopRecordVideo(const QString &ip);
    // 姿态回读开关（#TPUG2wGAA）：on=true 使能该 IP 主动送出（1Hz），false 关闭
    void setAttitudeReport(const QString &ip, bool on);
    // 单次激光测距（#TPUD2rSLR00）：该 IP 的距离存 ranging(ip) 并发 rangingChanged
    void requestRanging(const QString &ip);

signals:
    void connectedChanged();
    // 设备探测完成：QML 可据此刷新"未检测到云卓设备"提示
    void probeFinished();
    void attitudeChanged();        // 收到某 IP 云台姿态帧（按 IP 更新，QML 按 ip 查询）
    void rangingChanged();         // 收到某 IP 激光测距结果

private slots:
    void onProbeError(QAbstractSocket::SocketError err);
    void onProbeReply();
    void onProbeTimeout();
    void onReadyRead();            // 主 socket 收包（姿态帧/测距回包等，按来源 IP 更新）

private:
    // 单 IP 姿态/测距状态
    struct IpState {
        bool alive = false;      // 收到过 GAC 姿态帧
        bool protoAlive = false; // 收到过云卓协议帧（#TP 前缀：GAC/SLR/ACK）
        double yaw = 0, pitch = 0, roll = 0;
        double ranging = 0;      // 米
    };
    // 构造完整命令：前缀 + 数据(2位HEX) + CRC（校验覆盖前缀+数据）
    static QString buildCmd(const char *prefix, int dataByte);
    static QString buildCmdHex(const char *prefix, const char *dataHex);
    // 发送文本命令到指定 IP:port（UDP）
    void sendText(const QString &ip, const QString &cmd);
    // 启动设备探测（发无害 GSY00，监听 ICMP 端口不可达）
    void probeDevice();
    // 解析云卓回包（GAC 姿态帧 / SLR 测距帧），来源 IP 记录到 states_
    void parseReply(const QString &ip, const QString &s);

    QUdpSocket *sock_ = nullptr;
    QUdpSocket *probeSock_ = nullptr;   // 独立探测 socket（隔离，不影响主发送）
    QTimer probeTimer_;
    QHostAddress target_;
    quint16 port_ = 5000;
    bool started_ = false;
    // 设备探测结果：
    //   - 收到任何 UDP 回包 → gotReply_=true, devicePresent_=true（真云卓 5000 有控制服务，会响应命令）
    //   - ICMP 端口不可达 → devicePresent_=false（目标 5000 无服务）
    //   - 超时无回包无 ICMP → devicePresent_=gotReply_（思翼等嵌入式设备可能不回 ICMP，
    //     只能靠"是否回包"区分：真云卓回包=存在，思翼 5000 无服务=无回包=不存在）
    // 注：devicePresent_ 不乐观默认 true——超时无回包按"设备不存在"处理，才能识别思翼误配云卓。
    bool devicePresent_ = false;
    bool gotReply_ = false;
    bool portClosed_ = false;  // 探测到 ICMP port unreachable（IP 在线但端口无云卓服务），与"设备没通电"区分
    QHash<QString, IpState> states_;   // 按 IP 独立的姿态/测距状态
    QSet<QString> knownIps_;           // 已发送过命令的相机 IP 集合，用于回包归属判断
    QSet<QString> gaaEnabledIps_;      // 已使能姿态回读（GAA01）的 IP，stop 时发送 GAA00 关闭
};

} // namespace lgs

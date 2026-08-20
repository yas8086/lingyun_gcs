#pragma once

#include <QObject>
#include <QHostAddress>
#include <QUdpSocket>

namespace lgs {

// 云卓 C14PRO 云台相机 UDP 控制客户端。
// 协议（依据 RCSDK COMMON/C10PRO 协议层，真机验证通过）：
//   纯文本 ASCII 命令，目标端口 5000；结构 = 前缀 + 数据(2 位 HEX) + CRC(2 位 HEX)
//   CRC = sum(ASCII(前缀+数据)) & 0xFF，转大写 2 位 HEX
// 命令（RCSDK demo 与真机均已验证）：
//   #TPUG2wGSY<速> 航向速度控制（速=有符号 int8 的 2 位大写 HEX，+100→64 / -100→9C / 停止→00）
//   #TPUG2wGSP<速> 俯仰速度控制
//   #TPUD2wCAP01   拍照
//   #TPUD2wREC01 / REC00  开始/停止录像
class SkydroidSdkClient : public QObject {
    Q_OBJECT
public:
    explicit SkydroidSdkClient(QObject *parent = nullptr);

    // 开始会话：绑定本地随机端口，目标 C14PRO IP:5000
    void start(const QString &ip, quint16 port = 5000);
    void stop();

public slots:
    // 云台速度控制（-100~100）：yaw 航向 / pitch 俯仰，传 0 停止
    void ctrlMove(int yaw, int pitch);
    void ctrlYaw(int speed);
    void ctrlPitch(int speed);
    // 一键回中（#TPUG2wPTZ05，RCSDK AKey.MID）
    void center();
    // 变焦：+1 放大（#TPUD2wDZM0A）/-1 缩小（#TPUD2wDZM0B）
    void zoom(int dir);
    void zoomIn() { zoom(1); }
    void zoomOut() { zoom(-1); }
    // 长短焦镜头切换：#TPUD2wDZM0C 长焦 / 0D 广角（C14PRO 100 倍混合变焦=短焦 59x+长焦 41x）
    void setTeleLens();
    void setWideLens();
    // 相机动作
    void takePicture();
    void startRecordVideo();
    void stopRecordVideo();

signals:
    void connectedChanged();

private:
    // 构造完整命令：前缀 + 数据(2位HEX) + CRC（校验覆盖前缀+数据）
    static QString buildCmd(const char *prefix, int dataByte);
    static QString buildCmdHex(const char *prefix, const char *dataHex);
    // 发送文本命令（UDP 目标 5000）
    void sendText(const QString &cmd);

    QUdpSocket *sock_ = nullptr;
    QHostAddress target_;
    quint16 port_ = 5000;
    bool started_ = false;
};

} // namespace lgs

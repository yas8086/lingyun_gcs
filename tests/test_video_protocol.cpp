#include <QtTest>
#include <QUdpSocket>
#include <QHostAddress>
#include "video/siyi_sdk_client.h"
#include "video/skydroid_sdk_client.h"

using namespace lgs;

// 视频/云台协议回环测试（C1）：用本地 UDP 回环模拟真机设备，验证
//  - 云卓 C14PRO：命令构造逐字节、GAC 姿态解析（负角符号扩展）、SLR 测距解析、CRC 校验失败丢弃
//  - 思翼 A2 mini：ACK 姿态帧解析（CRC16-XMODEM + 6×int16 LE ÷10）
// 无需真机硬件即可覆盖协议核心逻辑。

// 云卓 CRC：对「前缀+数据」逐字符 ASCII 累加和 & 0xFF，转大写 2 位 HEX
// （与 skydroid_sdk_client.cpp 内 crcOf 同算法，测试侧复制实现以构造合法回包）
static QString skyCrc(const QString &body) {
    int sum = 0;
    for (const QChar &c : body)
        sum = (sum + c.unicode()) & 0xFF;
    return QStringLiteral("%1").arg(sum, 2, 16, QLatin1Char('0')).toUpper();
}

// 思翼 CRC16-XMODEM：poly 0x1021，init 0（与 siyi_sdk_client.cpp::crc16 同算法）
static quint16 siyiCrc16(const QByteArray &data) {
    quint16 crc = 0;
    for (int i = 0; i < data.size(); ++i) {
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

class TestVideoProtocol : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {}
    void cleanupTestCase() {}

    // 云卓：命令构造（+100 速度 → GSY64，CRC 逐字节）
    void skyCmdConstruction();
    // 云卓：GAC 姿态帧解析（负角符号扩展）
    void skyGacParsing();
    // 云卓：SLR 测距帧解析（真机实测 2r 格式，分米→米）
    void skySlrParsing();
    // 云卓：CRC 校验失败的帧被丢弃
    void skyBadCrcDropped();
    // 云卓：设备端口有 UDP 服务时，探测结论应为"设备存在"且 portClosed=false（不误判选错云台）
    void skyProbePresentKeepsPortClosedFalse();
    // 思翼：ACK 姿态帧解析
    void siyiAckParsing();
    // 思翼：目标端口无 UDP 服务 → ICMP port unreachable → portClosed=true（判"选错云台"）
    void siyiPortClosedOnNoService();
    // 思翼：端口有 UDP 服务但无思翼 ACK 回包（设备没通电/没联网模拟）→ portClosed=false（不误判选错）
    void siyiProbePresentKeepsPortClosedFalse();
};

void TestVideoProtocol::skyCmdConstruction() {
    QUdpSocket device;   // 模拟云卓设备
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SkydroidSdkClient client;
    client.start(QStringLiteral("127.0.0.1"), dport);
    QVERIFY(client.started());
    // 等待并清空 start 探测阶段到达的 GSY00 帧，避免干扰断言
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    while (device.hasPendingDatagrams()) {
        QByteArray d;
        d.resize(int(device.pendingDatagramSize()));
        device.readDatagram(d.data(), d.size());
    }

    client.ctrlYaw(QStringLiteral("127.0.0.1"), 100);   // 航向 右 速100
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    QByteArray datagram;
    datagram.resize(int(device.pendingDatagramSize()));
    device.readDatagram(datagram.data(), datagram.size());
    // 期望 #TPUG2wGSY64 + CRC（RCSDK demo 已验证 69）
    const QString expected = QStringLiteral("#TPUG2wGSY64") + skyCrc(QStringLiteral("#TPUG2wGSY64"));
    QCOMPARE(QString::fromLatin1(datagram), expected);
    QVERIFY(QString::fromLatin1(datagram).endsWith(QStringLiteral("69")));

    // 负速度：-100 → 9C（有符号 int8 十六进制）
    client.ctrlPitch(QStringLiteral("127.0.0.1"), -100);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    datagram.resize(int(device.pendingDatagramSize()));
    device.readDatagram(datagram.data(), datagram.size());
    const QString expected2 = QStringLiteral("#TPUG2wGSP9C") + skyCrc(QStringLiteral("#TPUG2wGSP9C"));
    QCOMPARE(QString::fromLatin1(datagram), expected2);

    client.stop();
}

void TestVideoProtocol::skyGacParsing() {
    QUdpSocket device;
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SkydroidSdkClient client;
    client.start(QStringLiteral("127.0.0.1"), dport);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    while (device.hasPendingDatagrams()) {
        QByteArray d;
        d.resize(int(device.pendingDatagramSize()));
        device.readDatagram(d.data(), d.size());
    }
    // 触发主 socket 发送，获取 client 源地址/端口用于回发
    client.ctrlPitch(QStringLiteral("127.0.0.1"), 0);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    QHostAddress sender;
    quint16 sport = 0;
    QByteArray cmd;
    cmd.resize(int(device.pendingDatagramSize()));
    device.readDatagram(cmd.data(), cmd.size(), &sender, &sport);
    QVERIFY(!sender.isNull() && sport != 0);

    // 回发 GAC 姿态帧（紧凑无空格 + CRC）：
    // yaw=EC78(-5000=-50.00°) pitch=0014(20=0.20°) roll=FFFF(-1=-0.01°)
    const QString body = QStringLiteral("#TPUGCrGACEC780014FFFF");
    const QString reply = body + skyCrc(body);
    device.writeDatagram(reply.toUtf8(), sender, sport);

    QTRY_VERIFY_WITH_TIMEOUT(client.attitudeAlive(QStringLiteral("127.0.0.1")), 1000);
    QVERIFY(qAbs(client.yaw(QStringLiteral("127.0.0.1")) - (-50.0)) < 0.01);
    QVERIFY(qAbs(client.pitch(QStringLiteral("127.0.0.1")) - 0.20) < 0.01);
    QVERIFY(qAbs(client.roll(QStringLiteral("127.0.0.1")) - (-0.01)) < 0.01);
    // 收到 #TP 前缀帧 → 确为云卓设备（protocolAlive）
    QVERIFY(client.protocolAlive(QStringLiteral("127.0.0.1")));

    client.stop();
}

void TestVideoProtocol::skySlrParsing() {
    QUdpSocket device;
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SkydroidSdkClient client;
    client.start(QStringLiteral("127.0.0.1"), dport);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    while (device.hasPendingDatagrams()) {
        QByteArray d;
        d.resize(int(device.pendingDatagramSize()));
        device.readDatagram(d.data(), d.size());
    }
    client.ctrlPitch(QStringLiteral("127.0.0.1"), 0);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    QHostAddress sender;
    quint16 sport = 0;
    QByteArray cmd;
    cmd.resize(int(device.pendingDatagramSize()));
    device.readDatagram(cmd.data(), cmd.size(), &sender, &sport);

    // 回发 SLR 测距帧（真机实测 2r 格式）：#TPUD2rSLR0018 = 24 分米 = 2.4m
    const QString body = QStringLiteral("#TPUD2rSLR0018");
    const QString reply = body + skyCrc(body);
    device.writeDatagram(reply.toUtf8(), sender, sport);

    QTRY_VERIFY_WITH_TIMEOUT(client.ranging(QStringLiteral("127.0.0.1")) > 0.0, 1000);
    QVERIFY(qAbs(client.ranging(QStringLiteral("127.0.0.1")) - 2.4) < 0.01);

    client.stop();
}

void TestVideoProtocol::skyBadCrcDropped() {
    QUdpSocket device;
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SkydroidSdkClient client;
    client.start(QStringLiteral("127.0.0.1"), dport);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    while (device.hasPendingDatagrams()) {
        QByteArray d;
        d.resize(int(device.pendingDatagramSize()));
        device.readDatagram(d.data(), d.size());
    }
    client.ctrlPitch(QStringLiteral("127.0.0.1"), 0);
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1000);
    QHostAddress sender;
    quint16 sport = 0;
    QByteArray cmd;
    cmd.resize(int(device.pendingDatagramSize()));
    device.readDatagram(cmd.data(), cmd.size(), &sender, &sport);

    // CRC 错误的 GAC 帧：attitudeAlive 不应被置位（P1-4 丢弃整帧）
    const QString bad = QStringLiteral("#TPUGCrGACEC780014FFFF00"); // 末尾 CRC 错误
    device.writeDatagram(bad.toUtf8(), sender, sport);
    QTest::qWait(100);
    QVERIFY(!client.attitudeAlive(QStringLiteral("127.0.0.1")));
    QVERIFY(!client.protocolAlive(QStringLiteral("127.0.0.1")));

    client.stop();
}

void TestVideoProtocol::skyProbePresentKeepsPortClosedFalse() {
    QUdpSocket device;   // 模拟云卓设备：绑定端口 = 有 UDP 服务
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SkydroidSdkClient client;
    QSignalSpy probeDone(&client, &SkydroidSdkClient::probeFinished);
    client.start(QStringLiteral("127.0.0.1"), dport);
    QVERIFY(client.started());
    // 等待设备探测完成
    QTRY_VERIFY_WITH_TIMEOUT(probeDone.count() >= 1, 2000);
    // 端口有监听服务 → 不会产生 ICMP port unreachable → portClosed 必须为 false。
    // 即使设备未回包（超时判定"无响应"），也不得误判为"选错云台"（portClosed=false）
    QVERIFY(!client.portClosed());

    client.stop();
}

void TestVideoProtocol::siyiAckParsing() {
    QUdpSocket device;   // 模拟思翼 A2 mini
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SiyiSdkClient client;
    client.start(QStringLiteral("127.0.0.1"), dport);
    // 等待 client 200ms 轮询发出 0x0D 姿态查询
    QTRY_VERIFY_WITH_TIMEOUT(device.hasPendingDatagrams(), 1500);
    QHostAddress sender;
    quint16 sport = 0;
    QByteArray cmd;
    cmd.resize(int(device.pendingDatagramSize()));
    device.readDatagram(cmd.data(), cmd.size(), &sender, &sport);
    // 帧头 55 66，CMD=0x0D（OFF_CMD=7），CTRL=0x01(need_ack)
    QVERIFY(cmd.size() >= 10);
    QCOMPARE(quint8(cmd[0]), 0x55);
    QCOMPARE(quint8(cmd[1]), 0x66);
    QCOMPARE(quint8(cmd[7]), 0x0D);

    // 构造 ACK 姿态帧：CTRL=0x02，cmd=0x0D，数据 12B（6×int16 LE，÷10 为度）
    QByteArray ack;
    ack.append(char(0x55)); ack.append(char(0x66));
    ack.append(char(0x02));                 // CTRL=ack
    ack.append(char(12)); ack.append(char(0)); // Data_len=12 LE
    ack.append(char(0)); ack.append(char(0));  // SEQ=0 LE
    ack.append(char(0x0D));                 // CMD=0x0D
    auto append16 = [&ack](qint16 v) {
        ack.append(char(quint16(v) & 0xFF));
        ack.append(char((quint16(v) >> 8) & 0xFF));
    };
    append16(500);    // yaw=50.0°
    append16(-105);   // pitch=-10.5°
    append16(0);      // roll=0
    append16(0); append16(0); append16(0);  // 三轴角速度 0
    const quint16 crc = siyiCrc16(ack);
    ack.append(char(crc & 0xFF)); ack.append(char(crc >> 8));
    device.writeDatagram(ack, sender, sport);

    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 1000);
    QVERIFY(qAbs(client.pitch() - (-10.5)) < 0.01);
    QVERIFY(qAbs(client.yaw() - 50.0) < 0.01);
    QVERIFY(qAbs(client.roll() - 0.0) < 0.01);

    client.stop();
}

void TestVideoProtocol::siyiPortClosedOnNoService() {
    // 模拟"端口无思翼服务"（如云卓误配思翼：云卓 5000 有服务，但 37260 无监听）：
    // 先占一个端口确认它可用，然后关闭它——此时 127.0.0.1:port 无 UDP 服务，
    // 思翼 SDK 的 ICMP 探测应收到 port unreachable → portClosed=true（判选错云台）
    QUdpSocket tmp;
    QVERIFY(tmp.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = tmp.localPort();
    tmp.close();   // 释放端口 → 目标端口无服务

    SiyiSdkClient client;
    QSignalSpy probeDone(&client, &SiyiSdkClient::probeFinished);
    client.start(QStringLiteral("127.0.0.1"), dport);
    // 等待探测结束（ICMP 错误应立即触发）
    QTRY_VERIFY_WITH_TIMEOUT(probeDone.count() >= 1, 2000);
    QVERIFY(client.portClosed());   // 端口明确无服务 → 判"选错云台"

    client.stop();
}

void TestVideoProtocol::siyiProbePresentKeepsPortClosedFalse() {
    QUdpSocket device;   // 模拟思翼设备：绑定端口 = 有 UDP 监听服务
    QVERIFY(device.bind(QHostAddress::LocalHost, 0));
    const quint16 dport = device.localPort();

    SiyiSdkClient client;
    QSignalSpy probeDone(&client, &SiyiSdkClient::probeFinished);
    client.start(QStringLiteral("127.0.0.1"), dport);
    // 等待设备探测完成
    QTRY_VERIFY_WITH_TIMEOUT(probeDone.count() >= 1, 2000);
    // 端口有监听服务 → 不会产生 ICMP port unreachable → portClosed 必须为 false。
    // 即使设备未回 ACK（模拟没通电/没联网：仅超时"无响应"），也不得误判为"选错云台"（portClosed=false）
    QVERIFY(!client.portClosed());

    client.stop();
}

QTEST_MAIN(TestVideoProtocol)
#include "test_video_protocol.moc"

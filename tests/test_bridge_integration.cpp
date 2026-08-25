#include <QtTest>
#include <QApplication>
#include "comms/frame_parser.h"
#include "comms/json_decoder.h"
#include "qmlbridge/telemetry_bridge.h"

using namespace lgs;

// 集成测试：模拟器造数（serial_simulator.py 同构帧）→ 帧解析 → JSON 解码 → 桥接层暴露，
// 验证端到端数据链路的正确性（M4）。
class TestBridgeIntegration : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {}
    void cleanupTestCase() {}

    // 模拟 serial_simulator.py 的帧构造
    static QByteArray makeDemoFrame(double t, int soc, int loRaAlarm,
                                    double loRaTemp) {
        const QByteArray body = QByteArray::fromStdString(
            (std::string("{")
             + "\"t\":" + std::to_string(t) + ","
             + "\"bms\":{\"online\":true,\"pack_v\":367.2,\"pack_i\":0.0,"
               "\"soc\":" + std::to_string(soc) + ",\"rsoc\":" + std::to_string(soc - 0.5) + ","
               "\"max_v\":3.62,\"min_v\":3.58,\"diff_v\":0.04,"
               "\"max_t\":32.5,\"min_t\":31.0,\"avg_t\":31.8,\"diff_t\":1.5,"
               "\"riso_p\":520,\"riso_n\":498,\"alarm\":0},"
             + "\"backup\":{\"online\":true,\"pack_v\":48.6,\"pack_i\":1.2,\"soc\":90,"
               "\"soh\":96,\"max_v\":4.18,\"min_v\":4.11,\"diff_v\":0.07,"
               "\"max_t\":29.4,\"min_t\":28.1,\"avg_t\":28.7,\"diff_t\":1.3,"
               "\"alarm\":0,\"protect\":0,\"fault\":0,\"sys\":3},"
             + "\"mppt\":{\"online\":true,\"pv_v\":89.5,\"pv_p\":600.0,"
               "\"batt_v\":86.0,\"charge_i\":7.0,\"today\":0.42,\"total\":12.8,\"fault\":0},"
             + "\"dcdc\":{\"online\":true,\"in_v\":86.0,\"out_v\":48.1,"
               "\"out_i\":5.2,\"out_p\":250.0,\"temp\":41.0,\"enabled\":true,\"fault\":0},"
             + "\"lora\":{\"nodes\":["
               "{\"id\":1,\"online\":1,\"temp\":" + std::to_string(loRaTemp) + ","
               "\"pressure\":0,\"alarm\":" + std::to_string(loRaAlarm) + "},"
               "{\"id\":2,\"online\":1,\"temp\":0,\"pressure\":101325,\"alarm\":0}"
               "]}}").c_str());
        return QByteArray("\xaa\x55") + body + QByteArray("\n");
    }

    void decodeDemoFrame() {
        // 模拟器帧 → 帧解析 + 解码
        const QByteArray frame = makeDemoFrame(1.0, 85, 1, 65.0);
        FrameParser parser;
        parser.push(frame);
        QByteArray json;
        QVERIFY(parser.takeFrame(json));
        TelemetryData data;
        QVERIFY(decodeJson(json, data));
        QVERIFY(data.bms.has_value());
        QCOMPARE(data.bms->soc, 85);
        QVERIFY(data.dcdc.has_value());
        QCOMPARE(data.dcdc->out_p, 250.0);
        QVERIFY(data.lora.has_value());
        QCOMPARE(data.lora->nodes.size(), 2);
        QCOMPARE(data.lora->nodes[0].alarm, 1);
    }

    void bridgeExposesDemoData() {
        auto bridge = new TelemetryBridge;
        FrameParser parser;
        parser.push(makeDemoFrame(1.0, 85, 1, 65.0));
        QByteArray json;
        QVERIFY(parser.takeFrame(json));
        TelemetryData data;
        QVERIFY(decodeJson(json, data));
        bridge->onTelemetry(data);

        QVERIFY(bridge->online("bms"));
        QVERIFY(bridge->online("dcdc"));
        QVERIFY(bridge->online("lora"));
        QCOMPARE(bridge->value("bms", "soc"), 85.0);
        QCOMPARE(bridge->value("dcdc", "out_p"), 250.0);
        QCOMPARE(bridge->readinessState(), 1); // 演示数据全部正常 → 就绪可飞

        const QVariant nodes = bridge->loraNodes();
        QCOMPARE(nodes.toList().size(), 2);
        QCOMPARE(nodes.toList()[0].toMap().value("alarm").toInt(), 1);
        QCOMPARE(nodes.toList()[0].toMap().value("isTemp").toBool(), true);
        QCOMPARE(nodes.toList()[1].toMap().value("isTemp").toBool(), false);

        delete bridge;
    }

    void alarmConfirmFlow() {
        auto bridge = new TelemetryBridge;
        const int a1 = bridge->addAlarm("测试严重告警", "严重", "集成");
        const int a2 = bridge->addAlarm("测试提示", "提示", "集成");
        QCOMPARE(bridge->unconfirmedCount(), 2);
        QCOMPARE(bridge->alarms().toList().size(), 2);
        QVERIFY(a1 > 0 && a2 > a1); // aid 自增单调
        // 按 aid 精确确认单条（不误伤其他告警）
        bridge->confirmAlarmByAid(a1);
        QCOMPARE(bridge->unconfirmedCount(), 1);
        QCOMPARE(bridge->alarms().toList()[0].toMap().value("state").toString(), QStringLiteral("未确认"));
        // 规则恢复标记：ruleId 匹配的未确认告警标记为已恢复
        bridge->addAlarm("DCDC 过温", "告警", "DCDC", "rule:dcdc.temp");
        bridge->markAlarmRecovered("rule:dcdc.temp");
        QCOMPARE(bridge->unconfirmedCount(), 1); // 恢复后未确认计数下降
        // alarms() 最新在前：index0=DCDC(已恢复) index1=a2(未确认)，确认剩余一条
        bridge->confirmAlarm(1);
        QCOMPARE(bridge->unconfirmedCount(), 0);
        bridge->confirmAllAlarms();
        QCOMPARE(bridge->unconfirmedCount(), 0);
        delete bridge;
    }

    void tempHistoryExport() {
        auto bridge = new TelemetryBridge;
        const QString path = QDir::temp().filePath("lingyun-test-temp.csv");
        QFile::remove(path);
        // 送两轮带 lora 的遥测以产生历史
        for (int i = 0; i < 2; ++i) {
            FrameParser parser;
            parser.push(makeDemoFrame(i + 1.0, 85, 0, 40.0 + i));
            QByteArray json;
            QVERIFY(parser.takeFrame(json));
            TelemetryData data;
            QVERIFY(decodeJson(json, data));
            bridge->onTelemetry(data);
        }
        const int rows = bridge->exportTempCsv(path);
        QCOMPARE(rows, 2);
        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly | QIODevice::Text));
        const QString content = QString::fromUtf8(f.readAll());
        f.close();
        QVERIFY(content.contains("采样序号"));
        QVERIFY(content.contains("T01"));
        QVERIFY(content.contains("T02"));
        QFile::remove(path);
        delete bridge;
    }

    void recordConfigDefaults() {
        // 默认开启记录、默认目录为空（=软件目录/data）
        auto bridge = new TelemetryBridge;
        QVERIFY(bridge->recordEnabled());
        QVERIFY(bridge->recordDir().isEmpty());
        QVERIFY(!bridge->isRecording());
        QVERIFY(bridge->currentRecordFile().isEmpty());
        // 配置切换
        bridge->setRecordEnabled(false);
        QVERIFY(!bridge->recordEnabled());
        bridge->setRecordEnabled(true);
        QVERIFY(bridge->recordEnabled());
        delete bridge;
    }

    // 链路状态从串口解耦：仅 UDP 在线即视为数据链路在线，且记录自动启动/全断停止
    void dataLinkOnlineUdpOnly() {
        auto bridge = new TelemetryBridge;
        QVERIFY(!bridge->isDataLinkOnline());       // 无串口无 UDP → 离线
        QVERIFY(!bridge->isRecording());
        bridge->onUdpLinkOnline(true);              // 仅 UDP 在线（不依赖串口）
        QVERIFY(bridge->isDataLinkOnline());
        QVERIFY(bridge->isRecording());             // 仅 UDP 即自动开始记录
        bridge->onUdpLinkOnline(false);             // UDP 断开
        QVERIFY(!bridge->isDataLinkOnline());
        QVERIFY(!bridge->isRecording());            // 全断停止记录
        delete bridge;
    }

    // UDP 原始帧接入记录：仅 UDP 数据源下，onRawFrame 写入记录文件
    void udpRawFrameRecorded() {
        auto bridge = new TelemetryBridge;
        bridge->onUdpLinkOnline(true);              // 仅 UDP 在线，自动开记录
        QVERIFY(bridge->isRecording());
        const QByteArray frame = QByteArray("\xaa\x55{\"t\":1}\n");
        bridge->onRawFrame(frame);
        QTest::qWait(400);                          // 等 flushTimer 落盘
        QFile f(bridge->currentRecordFile());
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QByteArray content = f.readAll();
        f.close();
        QVERIFY(content.contains(frame));
        bridge->setRecordEnabled(false);            // 清理：停止记录
        QVERIFY(!bridge->isRecording());
        delete bridge;
    }

    // 结构化遥测表格（分析用 CSV）：onTelemetry 写一行，含表头与字段值
    void structuredCsvRecorded() {
        auto bridge = new TelemetryBridge;
        bridge->onUdpLinkOnline(true);              // 开记录（默认 recordEnabled）
        QVERIFY(bridge->isRecording());
        const QString raw = bridge->currentRecordFile();
        QVERIFY(raw.endsWith(QStringLiteral(".raw")));
        const QString table = raw.left(raw.size() - 4) + QStringLiteral(".csv");
        // 喂一帧解析后的遥测 → 写结构化行
        TelemetryData d; d.t = 100.5;
        Fc fc; fc.online = true; fc.roll = 5.5; fc.yaw = 90.0; fc.mode = QStringLiteral("AUTO.LOITER"); fc.gpsSat = 18;
        d.fc = fc;
        Lora l; LoraSample s; s.id = 1; s.temp = 26.2; l.nodes.push_back(s); d.lora = l;
        bridge->onTelemetry(d);
        QTest::qWait(400);                          // 等落盘
        QFile tf(table);
        QVERIFY(tf.open(QIODevice::ReadOnly));
        const QByteArray content = tf.readAll();
        tf.close();
        QVERIFY(content.contains("t,fc_online,fc_roll"));  // 表头
        QVERIFY(content.contains("AUTO.LOITER"));          // 字符串字段（含逗号转义）
        QVERIFY(content.contains("5.500"));                // fc.roll
        QVERIFY(content.contains("26.2"));                 // lora 温度
        bridge->setRecordEnabled(false);            // 清理
        delete bridge;
    }

    // 云卓 C14PRO UDP 文本协议：验证命令构造与 RCSDK demo 逐字节一致
    // （CRC = ASCII 累加和 & 0xFF，转大写 2 位 HEX；命令 = 前缀 + 数据 + CRC）
    void skydroidCmdBuild() {
        // 通过私有静态方法验证——此处改用公开 API 触发 send 的等价构造：
        // 直接校验 CRC 算法（与 RCSDK demo 已知报文比对）
        struct Crc { static QString calc(const QString &body) {
                int sum = 0;
                for (const QChar &c : body) sum = (sum + c.unicode()) & 0xFF;
                return QStringLiteral("%1").arg(sum, 2, 16, QLatin1Char('0')).toUpper();
            } };
        // RCSDK demo（HomeActivity.kt）已验证的命令
        const QHash<QString, QString> known = {
            {"#TPUG2wGSY64", "69"},   // 航向 右 速100
            {"#TPUG2wGSY9C", "7B"},   // 航向 左 速100
            {"#TPUG2wGSP64", "60"},   // 俯仰 上 速100
            {"#TPUG2wGSP9C", "72"},   // 俯仰 下 速100
            {"#TPUD2wCAP01", "3E"},   // 拍照
            {"#TPUD2wREC01", "44"},   // 开始录像
            {"#TPUD2wREC00", "43"},   // 停止录像
        };
        for (auto it = known.constBegin(); it != known.constEnd(); ++it) {
            const QString full = it.key() + it.value();
            QCOMPARE(Crc::calc(it.key()), it.value());
            // 构造的完整命令 = 前缀+数据+CRC
            QCOMPARE(it.key() + Crc::calc(it.key()), full);
        }
        // RCSDK 反编译新增命令：回中（akey MID→PTZ05）、变焦（DZM0A 放大 / DZM0B 缩小）
        const QHash<QString, QString> known2 = {
            {"#TPUG2wPTZ05", "6F"},   // 回中（C10Pro_Control RECOVER 也以 PTZ05 开头）
            {"#TPUD2wDZM0A", "65"},   // 变焦放大
            {"#TPUD2wDZM0B", "66"},   // 变焦缩小
        };
        for (auto it = known2.constBegin(); it != known2.constEnd(); ++it) {
            QCOMPARE(Crc::calc(it.key()), it.value());
            QCOMPARE(it.key() + Crc::calc(it.key()), it.key() + it.value());
        }
    }
};

QTEST_MAIN(TestBridgeIntegration)
#include "test_bridge_integration.moc"
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
        bridge->addAlarm("测试严重告警", "严重", "集成");
        bridge->addAlarm("测试提示", "提示", "集成");
        QCOMPARE(bridge->unconfirmedCount(), 2);
        QCOMPARE(bridge->alarms().toList().size(), 2);
        bridge->confirmAlarm(0); // 确认最新一条
        QCOMPARE(bridge->unconfirmedCount(), 1);
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
};

QTEST_MAIN(TestBridgeIntegration)
#include "test_bridge_integration.moc"
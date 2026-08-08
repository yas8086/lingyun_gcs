#include <QtTest>
#include "comms/json_decoder.h"

using namespace lgs;

class TestJsonDecoder : public QObject {
    Q_OBJECT
private slots:
    void decodesFullFrame() {
        TelemetryData d;
        const QByteArray json =
            "{\"t\":1785928200.123,"
            "\"bms\":{\"online\":true,\"pack_v\":367.2,\"pack_i\":0.0,\"soc\":85,"
            "\"max_v\":3.62,\"min_v\":3.58,\"diff_v\":0.04,\"max_t\":32.5,\"alarm\":0},"
            "\"mppt\":{\"online\":true,\"pv_v\":89.5,\"pv_p\":600.0,\"batt_v\":86.0,"
            "\"charge_i\":7.0,\"today\":0.42,\"total\":12.8,\"fault\":0},"
            "\"dcdc\":{\"online\":true,\"in_v\":86.0,\"out_v\":48.1,\"out_i\":5.2,"
            "\"out_p\":250.0,\"temp\":41.0,\"enabled\":true,\"fault\":0}}";
        QVERIFY(decodeJson(json, d));
        QVERIFY(d.bms.has_value());
        QCOMPARE(d.bms->soc, 85);
        QCOMPARE(d.bms->alarm, 0);
        QVERIFY(d.mppt.has_value());
        QCOMPARE(d.mppt->pv_p, 600.0);
        QVERIFY(d.dcdc.has_value());
        QVERIFY(d.dcdc->enabled);
    }

    void decodesLoraNodes() {
        TelemetryData d;
        const QByteArray json =
            "{\"t\":1785928200.123,"
            "\"lora\":{\"nodes\":["
            "{\"id\":1,\"online\":1,\"temp\":25.4,\"pressure\":0,\"alarm\":0},"
            "{\"id\":2,\"online\":1,\"temp\":0,\"pressure\":101325,\"alarm\":0}"
            "]}}";
        QVERIFY(decodeJson(json, d));
        QVERIFY(d.lora.has_value());
        QCOMPARE(static_cast<int>(d.lora->nodes.size()), 2);
        // 温度节点
        QCOMPARE(d.lora->nodes[0].id, 1);
        QVERIFY(d.lora->nodes[0].online);
        QCOMPARE(d.lora->nodes[0].temp, 25.4);
        QCOMPARE(d.lora->nodes[0].pressure, 0.0);
        QCOMPARE(d.lora->nodes[0].alarm, 0);
        // 压力节点
        QCOMPARE(d.lora->nodes[1].id, 2);
        QCOMPARE(d.lora->nodes[1].pressure, 101325.0);
        QCOMPARE(d.lora->nodes[1].temp, 0.0);
    }

    void decodesEmptyLoraNodes() {
        // lora 存在但 nodes 为空数组：收到过采样但本轮无在线节点
        TelemetryData d;
        const QByteArray json = "{\"t\":1.0,\"lora\":{\"nodes\":[]}}";
        QVERIFY(decodeJson(json, d));
        QVERIFY(d.lora.has_value());
        QCOMPARE(static_cast<int>(d.lora->nodes.size()), 0);
    }

    void missingDeviceMeansOffline() {
        TelemetryData d;
        const QByteArray json = "{\"t\":1.0}";
        QVERIFY(decodeJson(json, d));
        QVERIFY(!d.bms.has_value());
        QVERIFY(!d.mppt.has_value());
        QVERIFY(!d.dcdc.has_value());
    }

    void rejectsInvalidJson() {
        TelemetryData d;
        QVERIFY(!decodeJson("{invalid", d));
    }
};

QTEST_MAIN(TestJsonDecoder)
#include "test_json_decoder.moc"

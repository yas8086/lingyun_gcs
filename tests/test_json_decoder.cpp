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

    void decodesBackupAndExtendedBms() {
        TelemetryData d;
        const QByteArray json =
            "{\"t\":1785928200.123,"
            "\"bms\":{\"online\":true,\"soc\":85,\"rsoc\":84.5,\"max_t\":32.5,"
            "\"min_t\":31.0,\"avg_t\":31.8,\"diff_t\":1.5,\"riso_p\":520,\"riso_n\":498},"
            "\"backup\":{\"online\":true,\"pack_v\":48.6,\"pack_i\":1.2,\"soc\":90,"
            "\"soh\":96,\"max_t\":29.4,\"avg_t\":28.7,\"alarm\":0,\"protect\":0,"
            "\"fault\":0,\"sys\":3}}";
        QVERIFY(decodeJson(json, d));
        // BMS 扩展字段
        QVERIFY(d.bms.has_value());
        QCOMPARE(d.bms->rsoc, 84.5);
        QCOMPARE(d.bms->avg_t, 31.8);
        QCOMPARE(d.bms->diff_t, 1.5);
        QCOMPARE(d.bms->riso_p, 520);
        // backup 设备
        QVERIFY(d.backup.has_value());
        QCOMPARE(d.backup->soc, 90);
        QCOMPARE(d.backup->soh, 96);
        QCOMPARE(d.backup->sys, 3);
        QVERIFY(!d.mppt.has_value());
    }

    void nullValueTreatedAsInvalid() {
        // 协议：NaN/Inf 序列化为 null，应视为无效值而非强转 0
        TelemetryData d;
        const QByteArray json =
            "{\"t\":1.0,\"bms\":{\"online\":true,\"soc\":85,\"pack_v\":null,"
            "\"max_t\":null}}";
        QVERIFY(decodeJson(json, d));
        QVERIFY(d.bms.has_value());
        QCOMPARE(d.bms->soc, 85);          // 有效字段保留
        QCOMPARE(d.bms->pack_v, 0.0);      // null 字段保持默认值
        QCOMPARE(d.bms->max_t, 0.0);
    }

    void decodesFc() {
        // fc 仅 4G 链路出现；解析后应正确填充
        TelemetryData d;
        const QByteArray json =
            "{\"t\":1785928200.123,"
            "\"fc\":{\"online\":true,\"roll\":1.5,\"pitch\":-2.0,\"yaw\":45.0,"
            "\"lat\":31.230400,\"lon\":121.473701,\"alt\":120.5,"
            "\"vx\":1.0,\"vy\":2.0,\"vz\":0.0,\"mode\":\"AUTO.LOITER\","
            "\"armed\":true,\"batt_v\":24.0,\"batt_pct\":0.85}}";
        QVERIFY(decodeJson(json, d));
        QVERIFY(d.fc.has_value());
        QCOMPARE(d.fc->online, true);
        QCOMPARE(d.fc->roll, 1.5);
        QCOMPARE(d.fc->lat, 31.230400);
        QCOMPARE(d.fc->mode, QString("AUTO.LOITER"));
        QCOMPARE(d.fc->armed, true);
        QCOMPARE(d.fc->batt_pct, 0.85);
    }
};

QTEST_MAIN(TestJsonDecoder)
#include "test_json_decoder.moc"

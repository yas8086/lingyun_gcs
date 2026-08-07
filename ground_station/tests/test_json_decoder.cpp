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

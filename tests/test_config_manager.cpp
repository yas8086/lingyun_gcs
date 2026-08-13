#include <QtTest>
#include <QStandardPaths>
#include "core/config_manager.h"

using namespace lgs;

class TestConfigManager : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {
        // 将可写配置路径隔离到测试目录，避免污染真实配置
        QStandardPaths::setTestModeEnabled(true);
    }

    void defaults() {
        // 清理残留配置，确保读到真正的默认值（默认波特率 115200）
        QFile::remove(QStandardPaths::writableLocation(
                          QStandardPaths::AppConfigLocation)
                      + "/ground_station.json");
        ConfigManager c;
        QCOMPARE(c.baud(), 115200);
        QCOMPARE(c.temperatureUnit(), 0);
        QVERIFY(!c.alarmSoundEnabled());
        QCOMPARE(c.chartWindowSecs(), 20);
        QVERIFY(c.hiddenModules().isEmpty());
        QVERIFY(c.recordEnabled());       // 默认开启自动记录
        QVERIFY(c.recordDir().isEmpty()); // 默认空 = 软件目录/data
    }

    void roundtrip() {
        ConfigManager c;
        c.setPort("COM3");
        c.setBaud(9600);
        c.setTemperatureUnit(1);
        c.setAlarmSoundEnabled(true);
        c.setChartWindowSecs(10);
        c.setHiddenModules({"chart", "log"});
        c.setRecordEnabled(false);
        c.setRecordDir("/tmp/my_records");

        ConfigManager d;
        QCOMPARE(d.port(), QString("COM3"));
        QCOMPARE(d.baud(), 9600);
        QCOMPARE(d.temperatureUnit(), 1);
        QVERIFY(d.alarmSoundEnabled());
        QCOMPARE(d.chartWindowSecs(), 10);
        QVERIFY(d.hiddenModules().contains("chart"));
        QVERIFY(d.hiddenModules().contains("log"));
        QVERIFY(!d.recordEnabled());
        QCOMPARE(d.recordDir(), QString("/tmp/my_records"));
    }

    void alarmRulesDefaultWhenMissing() {
        ConfigManager c;
        QVector<AlarmRule> defs;
        AlarmRule r;
        r.id = "a";
        defs.append(r);
        QCOMPARE(c.loadAlarmRules(defs).size(), 1);
    }

    void alarmRulesPersist() {
        ConfigManager c;
        QVector<AlarmRule> rules;
        AlarmRule r;
        r.id = "rule1";
        r.device = "bms";
        r.field = "soc";
        r.type = AlarmRule::Threshold;
        r.threshold = 30.0;
        r.above = false;
        r.level = AlarmEvent::Warn;
        rules.append(r);
        c.saveAlarmRules(rules);

        ConfigManager d;
        const auto loaded = d.loadAlarmRules({});
        QCOMPARE(loaded.size(), 1);
        QCOMPARE(loaded[0].id, QString("rule1"));
        QCOMPARE(loaded[0].device, QString("bms"));
        QCOMPARE(loaded[0].threshold, 30.0);
        QCOMPARE(loaded[0].type, AlarmRule::Threshold);
    }

    void windowGeometryRoundtrip() {
        ConfigManager c;
        const QByteArray geo = QByteArray::fromBase64("aGVsbG8=");
        c.saveWindowGeometry(geo);
        ConfigManager d;
        QCOMPARE(d.windowGeometry(), geo);
    }
};

QTEST_GUILESS_MAIN(TestConfigManager)
#include "test_config_manager.moc"
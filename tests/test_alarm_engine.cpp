#include <QtTest>
#include <QSignalSpy>
#include <QMetaType>
#include "core/alarm_engine.h"

using namespace lgs;

Q_DECLARE_METATYPE(lgs::AlarmEvent)

class TestAlarmEngine : public QObject {
    Q_OBJECT
private slots:
    void faultRuleTriggersAndClears() {
        AlarmEngine eng;
        QSignalSpy trig(&eng, &AlarmEngine::alarmTriggered);
        QSignalSpy clr(&eng, &AlarmEngine::alarmCleared);

        TelemetryData d;
        d.bms = Bms{};
        d.bms->online = true;
        d.bms->soc = 85; // 避免触发默认低电量规则
        d.bms->alarm = 1; // 故障
        eng.onTelemetry(d);
        QCOMPARE(trig.count(), 1);
        const AlarmEvent e = trig.at(0).at(0).value<AlarmEvent>();
        QCOMPARE(e.id, QString("rule:bms_alarm"));
        QCOMPARE(e.level, AlarmEvent::Warn);

        // 归零 → 清除
        d.bms->alarm = 0;
        eng.onTelemetry(d);
        QCOMPARE(clr.count(), 1);
        QCOMPARE(clr.at(0).at(0).toString(), QString("rule:bms_alarm"));
    }

    void thresholdOverTriggers() {
        AlarmEngine eng;
        QSignalSpy trig(&eng, &AlarmEngine::alarmTriggered);
        TelemetryData d;
        d.dcdc = Dcdc{};
        d.dcdc->online = true;
        d.dcdc->temp = 45.0; // > 43 默认阈值
        eng.onTelemetry(d);
        QCOMPARE(trig.count(), 1);
        QCOMPARE(trig.at(0).at(0).value<AlarmEvent>().id, QString("rule:dcdc_overtemp"));
    }

    void thresholdUnderTriggers() {
        AlarmEngine eng;
        QSignalSpy trig(&eng, &AlarmEngine::alarmTriggered);
        TelemetryData d;
        d.bms = Bms{};
        d.bms->online = true;
        d.bms->soc = 10; // < 20 默认阈值
        eng.onTelemetry(d);
        QVERIFY(trig.count() >= 1);
    }

    void customRuleEvaluated() {
        AlarmEngine eng;
        QSignalSpy trig(&eng, &AlarmEngine::alarmTriggered);
        AlarmRule r;
        r.id = "custom_soc";
        r.type = AlarmRule::Threshold;
        r.device = "bms";
        r.field = "soc";
        r.threshold = 50.0;
        r.above = false; // < 50 触发
        r.level = AlarmEvent::Critical;
        r.label = "自定义低电量";
        eng.setRules({r});

        TelemetryData d;
        d.bms = Bms{};
        d.bms->online = true;
        d.bms->soc = 30;
        eng.onTelemetry(d);
        QCOMPARE(trig.count(), 1);
        const AlarmEvent e = trig.at(0).at(0).value<AlarmEvent>();
        QCOMPARE(e.id, QString("rule:custom_soc"));
        QCOMPARE(e.level, AlarmEvent::Critical);
    }

    void offlineTimeoutAlarm() {
        AlarmEngine eng;
        eng.setOfflineTimeoutMs(50);
        QSignalSpy trig(&eng, &AlarmEngine::alarmTriggered);
        TelemetryData d;
        d.bms = Bms{};
        d.bms->online = true;
        eng.onTelemetry(d);
        // 不再上报 bms，等待 scanOffline 触发
        QVERIFY(trig.wait(1500));
        bool found = false;
        for (const auto &args : trig) {
            if (args.at(0).value<AlarmEvent>().id == "offline:bms")
                found = true;
        }
        QVERIFY(found);
    }

    void soundToggleNoCrash() {
        AlarmEngine eng;
        eng.setSoundEnabled(false);
        QVERIFY(!eng.soundEnabled());
        eng.setSoundEnabled(true);
        QVERIFY(eng.soundEnabled());
        // 开启声音后触发告警不崩溃
        TelemetryData d;
        d.dcdc = Dcdc{};
        d.dcdc->online = true;
        d.dcdc->temp = 99;
        eng.onTelemetry(d);
        QVERIFY(true);
    }
};

QTEST_MAIN(TestAlarmEngine)
#include "test_alarm_engine.moc"
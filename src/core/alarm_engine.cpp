#include "core/alarm_engine.h"

namespace lgs {

AlarmEngine::AlarmEngine(QObject *parent) : QObject(parent) {
    if (!clockStarted_) {
        clock_.start();
        clockStarted_ = true;
    }
}

void AlarmEngine::setOfflineTimeoutMs(int ms) {
    offlineTimeoutMs_ = ms;
}

void AlarmEngine::updateDevice(const QString &id, bool present) {
    if (present) {
        lastSeen_[id] = clock_.elapsed();
        if (alarmActive_.value(id, false)) {
            alarmActive_[id] = false;
            emit alarmCleared(id);
        }
    } else {
        // 设备从帧中消失：记录当前，交由超时判定触发离线告警
        lastSeen_[id] = lastSeen_.value(id, clock_.elapsed());
    }
}

void AlarmEngine::onTelemetry(const lgs::TelemetryData &data) {
    const qint64 now = clock_.elapsed();

    // 更新每个设备最近一次出现时间
    updateDevice("bms", data.bms.has_value());
    updateDevice("mppt", data.mppt.has_value());
    updateDevice("dcdc", data.dcdc.has_value());

    // 设备告警位检查
    if (data.bms && data.bms->alarm != 0) {
        const QString id = "bms:alarm";
        if (!alarmActive_.value(id, false)) {
            alarmActive_[id] = true;
            AlarmEvent e;
            e.id = id;
            e.level = data.bms->alarm >= 2 ? AlarmEvent::Critical : AlarmEvent::Warn;
            e.kind = AlarmEvent::DeviceAlarm;
            e.message = QString("BMS 告警级别 %1").arg(data.bms->alarm);
            emit alarmTriggered(e);
        }
    }

    // 超时离线检查
    const QStringList ids = {"bms", "mppt", "dcdc"};
    for (const auto &id : ids) {
        if (lastSeen_.contains(id) && now - lastSeen_[id] >= offlineTimeoutMs_) {
            const QString offId = id + ":offline";
            if (!alarmActive_.value(offId, false)) {
                alarmActive_[offId] = true;
                AlarmEvent e;
                e.id = offId;
                e.level = AlarmEvent::Warn;
                e.kind = AlarmEvent::Offline;
                e.message = QString("%1 设备离线").arg(id.toUpper());
                emit alarmTriggered(e);
            }
        }
    }
}

} // namespace lgs

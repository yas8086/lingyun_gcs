#include "core/alarm_engine.h"

namespace lgs {

AlarmEngine::AlarmEngine(QObject *parent) : QObject(parent) {
    if (!clockStarted_) {
        clock_.start();
        clockStarted_ = true;
    }
    // 独立定时巡检，保证链路整段断连（onTelemetry 不再被调用）时仍能触发离线告警
    timer_.setInterval(500);
    connect(&timer_, &QTimer::timeout, this, &AlarmEngine::scanOffline);
    timer_.start();
}

void AlarmEngine::setOfflineTimeoutMs(int ms) {
    offlineTimeoutMs_ = ms;
}

void AlarmEngine::updateDevice(const QString &id, bool present) {
    if (present) {
        lastSeen_[id] = clock_.elapsed();
        // 设备恢复在线：清除对应离线告警
        const QString offId = id + ":offline";
        if (alarmActive_.value(offId, false)) {
            alarmActive_[offId] = false;
            emit alarmCleared(offId);
        }
    } else {
        // 设备从帧中消失：记录当前，交由超时判定触发离线告警
        lastSeen_[id] = lastSeen_.value(id, clock_.elapsed());
    }
}

void AlarmEngine::onTelemetry(const lgs::TelemetryData &data) {
    // 更新每个设备最近一次出现时间
    updateDevice("bms", data.bms.has_value());
    updateDevice("mppt", data.mppt.has_value());
    updateDevice("dcdc", data.dcdc.has_value());

    // 设备告警位检查
    if (data.bms) {
        const QString id = "bms:alarm";
        if (data.bms->alarm != 0) {
            if (!alarmActive_.value(id, false)) {
                alarmActive_[id] = true;
                AlarmEvent e;
                e.id = id;
                e.level = data.bms->alarm >= 2 ? AlarmEvent::Critical : AlarmEvent::Warn;
                e.kind = AlarmEvent::DeviceAlarm;
                e.message = QString("BMS 告警级别 %1").arg(data.bms->alarm);
                emit alarmTriggered(e);
            }
        } else {
            // 告警位归零：清除 BMS 告警
            if (alarmActive_.value(id, false)) {
                alarmActive_[id] = false;
                emit alarmCleared(id);
            }
        }
    }
}

void AlarmEngine::scanOffline() {
    // 设备超时离线检测；由独立定时器周期触发，链路断连时也能工作
    const qint64 now = clock_.elapsed();
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

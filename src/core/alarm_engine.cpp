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
    // lora 特殊：机载收到过采样即持续存在（nodes 可为空数组）
    updateDevice("lora", data.lora.has_value());

    // 告警位/故障位检查：非 0 触发，归零清除
    auto checkFault = [this](const QString &id, int fault, const QString &devName) {
        if (fault != 0) {
            if (!alarmActive_.value(id, false)) {
                alarmActive_[id] = true;
                AlarmEvent e;
                e.id = id;
                e.level = fault >= 2 ? AlarmEvent::Critical : AlarmEvent::Warn;
                e.kind = AlarmEvent::DeviceAlarm;
                e.message = QString("%1 告警级别 %2").arg(devName).arg(fault);
                emit alarmTriggered(e);
            }
        } else {
            // 告警位归零：清除对应告警
            if (alarmActive_.value(id, false)) {
                alarmActive_[id] = false;
                emit alarmCleared(id);
            }
        }
    };

    if (data.bms)
        checkFault("bms:alarm", data.bms->alarm, "BMS");
    if (data.mppt)
        checkFault("mppt:fault", data.mppt->fault, "MPPT");
    if (data.dcdc)
        checkFault("dcdc:fault", data.dcdc->fault, "DCDC");

    // LoRa 节点级告警位：0 正常 / 1 超上限 / -1 超下限（仅温度节点有效）
    if (data.lora) {
        for (const auto &s : data.lora->nodes) {
            // 文档：alarm 仅温度节点有效（压力节点恒 0）。节点类型按协议
            // 约定以 temp/pressure 判断，温度节点 temp != 0
            if (s.temp == 0.0)
                continue;
            const QString nid = QString("lora:node%1:alarm").arg(s.id);
            if (s.alarm != 0) {
                if (!alarmActive_.value(nid, false)) {
                    alarmActive_[nid] = true;
                    AlarmEvent e;
                    e.id = nid;
                    e.level = AlarmEvent::Warn; // 温度越限按告警处理，非严重
                    e.kind = AlarmEvent::DeviceAlarm;
                    e.message = QString("LoRa 节点 %1 %2")
                                    .arg(s.id)
                                    .arg(s.alarm > 0 ? "超上限" : "超下限");
                    emit alarmTriggered(e);
                }
            } else if (alarmActive_.value(nid, false)) {
                alarmActive_[nid] = false;
                emit alarmCleared(nid);
            }
        }
    }
}

void AlarmEngine::scanOffline() {
    // 设备超时离线检测；由独立定时器周期触发，链路断连时也能工作
    const qint64 now = clock_.elapsed();
    const QStringList ids = {"bms", "mppt", "dcdc", "lora"};
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

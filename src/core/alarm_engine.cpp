#include "core/alarm_engine.h"
#include <QApplication>

namespace lgs {

namespace {
// 设备键 -> 显示标签
QString deviceLabel(const QString &id) {
    if (id == "bms") return "BMS";
    if (id == "backup") return "备用BMS";
    if (id == "mppt1" || id == "mppt2") return "MPPT";
    if (id == "dcdc") return "DCDC";
    if (id == "lora") return "LoRa";
    return id.toUpper();
}
} // namespace

std::optional<double> ruleValue(const QString &device, const QString &field,
                                const lgs::TelemetryData &data) {
    // MPPT 字段取值（协议 5.3）：主/副分支共用同一套字段清单
    const auto mpptValue = [&field](const lgs::Mppt &m) -> std::optional<double> {
        if (field == "pv_v") return m.pv_v;
        if (field == "pv_p") return m.pv_p;
        if (field == "batt_v") return m.batt_v;
        if (field == "charge_i") return m.charge_i;
        if (field == "today") return m.today;
        if (field == "month") return m.month;
        if (field == "total") return m.total;
        if (field == "rated_v") return m.rated_v;
        if (field == "rated_i") return m.rated_i;
        if (field == "air_t") return m.air_t;
        if (field == "mod_t") return m.mod_t;
        if (field == "cs") return m.cs;
        if (field == "mode") return m.mode;
        if (field == "chg_on") return m.chg_on ? 1.0 : 0.0;
        if (field == "fault") return m.fault;
        return std::nullopt;
    };
    if (device == "bms" && data.bms) {
        const auto &b = *data.bms;
        if (field == "pack_v") return b.pack_v;
        if (field == "pack_i") return b.pack_i;
        if (field == "soc") return b.soc;
        if (field == "rsoc") return b.rsoc;
        if (field == "max_v") return b.max_v;
        if (field == "min_v") return b.min_v;
        if (field == "diff_v") return b.diff_v;
        if (field == "max_t") return b.max_t;
        if (field == "min_t") return b.min_t;
        if (field == "avg_t") return b.avg_t;
        if (field == "diff_t") return b.diff_t;
        if (field == "riso_p") return b.riso_p;
        if (field == "riso_n") return b.riso_n;
        if (field == "alarm") return b.alarm;
    } else if (device == "backup" && data.backup) {
        const auto &b = *data.backup;
        if (field == "pack_v") return b.pack_v;
        if (field == "pack_i") return b.pack_i;
        if (field == "soc") return b.soc;
        if (field == "soh") return b.soh;
        if (field == "max_v") return b.max_v;
        if (field == "min_v") return b.min_v;
        if (field == "diff_v") return b.diff_v;
        if (field == "max_t") return b.max_t;
        if (field == "min_t") return b.min_t;
        if (field == "avg_t") return b.avg_t;
        if (field == "diff_t") return b.diff_t;
        if (field == "alarm") return b.alarm;
        if (field == "protect") return b.protect;
        if (field == "fault") return b.fault;
        if (field == "sys") return b.sys;
    } else if (device == "mppt1" && data.mppt1) {
        return mpptValue(*data.mppt1);
    } else if (device == "mppt2" && data.mppt2) {
        return mpptValue(*data.mppt2);
    } else if (device == "dcdc" && data.dcdc) {
        const auto &d = *data.dcdc;
        if (field == "in_v") return d.in_v;
        if (field == "out_v") return d.out_v;
        if (field == "out_i") return d.out_i;
        if (field == "out_p") return d.out_p;
        if (field == "temp") return d.temp;
        if (field == "fault") return d.fault;
    }
    return std::nullopt;
}

AlarmEngine::AlarmEngine(QObject *parent) : QObject(parent) {
    clock_.start(); // 启动运行计时（设备离线判定基准，B13：移除无效的 clockStarted_ 防呆）
    // 独立定时巡检，保证链路整段断连（onTelemetry 不再被调用）时仍能触发离线告警
    timer_.setInterval(500);
    connect(&timer_, &QTimer::timeout, this, &AlarmEngine::scanOffline);
    timer_.start();

    // 默认规则（决策 #15 将硬编码规则收敛为规则引擎的默认规则）
    AlarmRule r;
    r.type = AlarmRule::Fault; r.device = "bms"; r.field = "alarm";
    r.level = AlarmEvent::Warn; r.label = "BMS 告警位"; r.id = "bms_alarm"; defaults_.push_back(r);
    r.device = "backup"; r.field = "fault"; r.id = "backup_fault";
    r.level = AlarmEvent::Critical; r.label = "备用电源故障"; defaults_.push_back(r);
    r.device = "backup"; r.field = "alarm"; r.id = "backup_alarm";
    r.level = AlarmEvent::Warn; r.label = "备用电源告警"; defaults_.push_back(r);
    r.device = "mppt1"; r.field = "fault"; r.id = "mppt1_fault";
    r.level = AlarmEvent::Warn; r.label = "MPPT 故障"; defaults_.push_back(r);
    r.device = "dcdc"; r.field = "fault"; r.id = "dcdc_fault";
    r.level = AlarmEvent::Warn; r.label = "DCDC 故障"; defaults_.push_back(r);

    AlarmRule t;
    t.type = AlarmRule::Threshold; t.device = "dcdc"; t.field = "temp";
    t.threshold = 43.0; t.above = true; t.level = AlarmEvent::Warn; t.label = "DCDC 过温";
    t.id = "dcdc_overtemp"; defaults_.push_back(t);
    t.device = "bms"; t.field = "max_t"; t.threshold = 55.0; t.above = true;
    t.level = AlarmEvent::Critical; t.label = "BMS 过温"; t.id = "bms_overtemp"; defaults_.push_back(t);
    t.device = "bms"; t.field = "soc"; t.threshold = 20.0; t.above = false;
    t.level = AlarmEvent::Warn; t.label = "BMS 电量低"; t.id = "bms_low_soc"; defaults_.push_back(t);
    t.device = "backup"; t.field = "soc"; t.threshold = 20.0; t.above = false;
    t.level = AlarmEvent::Warn; t.label = "备用电源电量低"; t.id = "backup_low_soc"; defaults_.push_back(t);

    rules_ = defaults_;
}

void AlarmEngine::setOfflineTimeoutMs(int ms) {
    offlineTimeoutMs_ = ms;
}

void AlarmEngine::setSoundEnabled(bool on) { soundOn_ = on; }
bool AlarmEngine::soundEnabled() const { return soundOn_; }

void AlarmEngine::playSound() {
    if (soundOn_)
        QApplication::beep();
}

void AlarmEngine::setRules(const QVector<AlarmRule> &rules) {
    rules_ = rules;
    // 清空失效规则的活动状态，避免残留，并逐个通知前端清除，保证 UI 与引擎一致
    for (auto it = alarmActive_.begin(); it != alarmActive_.end();) {
        if (it.key().startsWith("rule:")) {
            emit alarmCleared(it.key());
            it = alarmActive_.erase(it);
        } else {
            ++it;
        }
    }
}

QVector<AlarmRule> AlarmEngine::rules() const { return rules_; }
const QVector<AlarmRule> &AlarmEngine::defaultRules() const { return defaults_; }

void AlarmEngine::updateDevice(const QString &id, bool present) {
    if (present) {
        lastSeen_[id] = clock_.elapsed();
        // 设备恢复在线：清除对应离线告警
        const QString offId = "offline:" + id;
        if (alarmActive_.value(offId, false)) {
            alarmActive_[offId] = false;
            emit alarmCleared(offId);
        }
    } else {
        // 设备从帧中消失。仅当该设备曾在线（lastSeen_ 已有记录）时才保留其
        // 最后在线时刻，交由 scanOffline 超时判定触发离线告警。
        // 设备"从未上线"（lastSeen_ 无 key）时不得写入/刷新，否则每次收帧都会
        // 重置其计时，导致永不告警；整段断连时还会把它误报为曾经在线设备的离线。
        // （lastSeen_ 已有该设备时无需任何操作：最后在线时刻保持不变）
    }
}

void AlarmEngine::onTelemetry(const lgs::TelemetryData &data) {
    updateDevice("bms", data.bms.has_value());
    updateDevice("backup", data.backup.has_value());
    updateDevice("mppt1", data.mppt1.has_value());
    updateDevice("mppt2", data.mppt2.has_value());
    updateDevice("dcdc", data.dcdc.has_value());
    // lora 特殊：机载收到过采样即持续存在（nodes 可为空数组）
    updateDevice("lora", data.lora.has_value());

    evalRules(data);

    // LoRa 节点级告警位：0 正常 / 1 超上限 / -1 超下限（仅温度节点有效）
    // 维护本轮活跃节点 id 集合，处理节点从帧中消失（离线）时清除残留告警
    QSet<int> activeNodeIds;
    if (data.lora) {
        for (const auto &s : data.lora->nodes) {
            activeNodeIds.insert(s.id);
            // B6：以 pressure!=0 判定压力节点（pressure 恒非 0）——原 temp==0 判定会把
            // 真实温度恰为 0℃ 的温度节点误判为压力节点而跳过告警检查（0 是合法温度）
            if (s.pressure != 0.0) // 压力节点：无告警位，跳过
                continue;
            const QString nid = QString("lora:node%1:alarm").arg(s.id);
            if (s.alarm != 0) {
                if (!alarmActive_.value(nid, false)) {
                    alarmActive_[nid] = true;
                    AlarmEvent e;
                    e.id = nid;
                    e.level = AlarmEvent::Warn;
                    e.kind = AlarmEvent::Rule;
                    e.source = "LoRa";
                    e.message = QString("LoRa 节点 %1 %2")
                                    .arg(s.id)
                                    .arg(s.alarm > 0 ? "超上限" : "超下限");
                    playSound();
                    emit alarmTriggered(e);
                }
            } else if (alarmActive_.value(nid, false)) {
                alarmActive_[nid] = false;
                emit alarmCleared(nid);
            }
        }
    }
    // 上一轮活跃但本轮消失的节点：清除其告警，避免告警永不恢复
    for (auto it = activeLoraNodes_.begin(); it != activeLoraNodes_.end();) {
        if (!activeNodeIds.contains(*it)) {
            const QString nid = QString("lora:node%1:alarm").arg(*it);
            if (alarmActive_.value(nid, false)) {
                alarmActive_[nid] = false;
                emit alarmCleared(nid);
            }
            it = activeLoraNodes_.erase(it);
        } else {
            ++it;
        }
    }
    activeLoraNodes_ = activeNodeIds;
}

void AlarmEngine::evalRules(const lgs::TelemetryData &data) {
    for (const auto &rule : rules_) {
        if (!rule.enabled)
            continue;
        const auto v = ruleValue(rule.device, rule.field, data);
        if (!v)
            continue; // 设备离线或字段不可用，不评估（离线由 scanOffline 处理）

        const QString rid = "rule:" + rule.id;
        bool hit = false;
        if (rule.type == AlarmRule::Fault) {
            hit = (v.value() != 0.0);
        } else {
            hit = rule.above ? (v.value() > rule.threshold)
                             : (v.value() < rule.threshold);
        }

        if (hit) {
            // 仅 BMS `alarm` 为三级语义（0 正常/1 故障/2 严重），≥2 升级为严重；
            // 其余 fault/alarm 均为 32 位位标志，做数值 ≥2 升级会造成误判，故不升级。
            AlarmEvent::Level lv = rule.level;
            if (rule.type == AlarmRule::Fault && rule.device == "bms" &&
                rule.field == "alarm" && v.value() >= 2.0)
                lv = AlarmEvent::Critical;
            if (!alarmActive_.value(rid, false)) {
                alarmActive_[rid] = true;
                AlarmEvent e;
                e.id = rid;
                e.level = lv;
                e.kind = AlarmEvent::Rule;
                e.source = deviceLabel(rule.device);
                e.message = rule.label + QString("（%1=%2）")
                                .arg(rule.field).arg(v.value());
                playSound();
                emit alarmTriggered(e);
            }
        } else if (alarmActive_.value(rid, false)) {
            alarmActive_[rid] = false;
            emit alarmCleared(rid);
        }
    }
}

void AlarmEngine::scanOffline() {
    const qint64 now = clock_.elapsed();
    const QStringList ids = {"bms", "backup", "mppt1", "mppt2", "dcdc", "lora"};
    for (const auto &id : ids) {
        if (lastSeen_.contains(id) && now - lastSeen_[id] >= offlineTimeoutMs_) {
            const QString offId = "offline:" + id;
            if (!alarmActive_.value(offId, false)) {
                alarmActive_[offId] = true;
                AlarmEvent e;
                e.id = offId;
                e.level = AlarmEvent::Warn;
                e.kind = AlarmEvent::Offline;
                e.source = "链路";
                e.message = deviceLabel(id) + " 设备离线";
                playSound();
                emit alarmTriggered(e);
            }
        }
    }
}

} // namespace lgs
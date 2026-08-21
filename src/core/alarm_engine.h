#pragma once
#include <QObject>
#include <QString>
#include <QElapsedTimer>
#include <QMap>
#include <QSet>
#include <QTimer>
#include <QVector>
#include <optional>
#include "model/telemetry_data.h"

namespace lgs {

struct AlarmEvent {
    enum Level { Info, Warn, Critical };
    enum Kind { Offline, Rule };
    QString id;
    Level level = Info;
    Kind kind = Rule;
    QString source;   // 告警来源：设备标签（BMS/备用BMS/MPPT/DCDC/LoRa/链路）
    QString message;
};

// 告警规则：告警架构单一来源（决策 #15 收敛、#16 故障码接入）。
// Fault 规则：字段值 != 0 即触发（alarm/fault 位标志）。
// Threshold 规则：数值与阈值比较触发。
struct AlarmRule {
    enum Type { Fault, Threshold };
    QString id;          // 唯一规则 id
    Type type = Fault;
    QString device;      // 设备键：bms / backup / mppt / dcdc / lora
    QString field;       // 字段名（Fault 用 alarm/fault 等标志位）
    double threshold = 0.0; // 仅 Threshold
    bool above = true;   // true: value>threshold；false: value<threshold（仅 Threshold）
    AlarmEvent::Level level = AlarmEvent::Warn;
    bool enabled = true;
    QString label;       // 人性化标签，如 "DCDC 过温"
};

class AlarmEngine : public QObject {
    Q_OBJECT
public:
    explicit AlarmEngine(QObject *parent = nullptr);

    void setOfflineTimeoutMs(int ms);
    void onTelemetry(const lgs::TelemetryData &data);

    // 告警声音通知（决策 #19）：默认关闭，需用户确认后开启
    void setSoundEnabled(bool on);
    bool soundEnabled() const;

    // 规则引擎：默认规则 + 可配置
    void setRules(const QVector<AlarmRule> &rules);
    QVector<AlarmRule> rules() const;
    const QVector<AlarmRule> &defaultRules() const;

signals:
    void alarmTriggered(const lgs::AlarmEvent &e);
    void alarmCleared(const QString &id);

private:
    void updateDevice(const QString &id, bool present);
    void evalRules(const lgs::TelemetryData &data);
    void scanOffline(); // 定时巡检设备超时离线（链路断连时仍能触发）
    void playSound();

    int offlineTimeoutMs_ = 3000;
    bool soundOn_ = false;
    QElapsedTimer clock_;
    QTimer timer_;
    QMap<QString, qint64> lastSeen_; // device id -> ms
    QMap<QString, bool> alarmActive_; // rule id -> active
    QSet<int> activeLoraNodes_;      // 当前帧活跃的 LoRa 节点 id
    QVector<AlarmRule> rules_;
    QVector<AlarmRule> defaults_;
};

// 按 device.field 从遥测中取数值；不存在或无效返回空
std::optional<double> ruleValue(const QString &device, const QString &field,
                                const lgs::TelemetryData &data);

} // namespace lgs

Q_DECLARE_METATYPE(lgs::AlarmEvent)
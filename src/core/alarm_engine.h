#pragma once
#include <QObject>
#include <QString>
#include <QElapsedTimer>
#include <QMap>
#include <QTimer>
#include "model/telemetry_data.h"

namespace lgs {

struct AlarmEvent {
    enum Level { Info, Warn, Critical };
    enum Kind { Offline, DeviceAlarm };
    QString id;
    Level level = Info;
    Kind kind = DeviceAlarm;
    QString message;
};

class AlarmEngine : public QObject {
    Q_OBJECT
public:
    explicit AlarmEngine(QObject *parent = nullptr);

    void setOfflineTimeoutMs(int ms);
    void onTelemetry(const lgs::TelemetryData &data);

signals:
    void alarmTriggered(const lgs::AlarmEvent &e);
    void alarmCleared(const QString &id);

private:
    void updateDevice(const QString &id, bool present);
    void scanOffline(); // 定时巡检设备超时离线（链路断连时仍能触发）

    int offlineTimeoutMs_ = 3000;
    QElapsedTimer clock_;
    bool clockStarted_ = false;
    QTimer timer_;
    QMap<QString, qint64> lastSeen_; // device id -> ms
    QMap<QString, bool> alarmActive_; // id -> active
};

} // namespace lgs

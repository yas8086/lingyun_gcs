#pragma once
#include <QObject>
#include <QString>
#include <QElapsedTimer>
#include <QMap>
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

    int offlineTimeoutMs_ = 3000;
    QElapsedTimer clock_;
    bool clockStarted_ = false;
    QMap<QString, qint64> lastSeen_; // device id -> ms
    QMap<QString, bool> alarmActive_; // id -> active
};

} // namespace lgs

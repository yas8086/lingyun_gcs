#pragma once
#include <QObject>
#include <QString>
#include <QVector>
#include <QTimer>
#include "model/telemetry_data.h"

namespace lgs {

// 读取录制 CSV，按时间戳节奏重放为 TelemetryData
class ReplayEngine : public QObject {
    Q_OBJECT
public:
    explicit ReplayEngine(QObject *parent = nullptr);

    bool load(const QString &filePath);
    void start();
    void stop();
    void setSpeed(double x);

signals:
    void replayed(const lgs::TelemetryData &data);
    void finished();

private:
    void tick();

    QVector<lgs::TelemetryData> frames_;
    QVector<qint64> deltasMs_;
    int idx_ = 0;
    double speed_ = 1.0;
    QTimer timer_;
    qint64 lastTsMs_ = 0;
};

} // namespace lgs

#pragma once
#include <QObject>
#include <QString>
#include <QVector>
#include <QTimer>
#include <QElapsedTimer>
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
    QVector<qint64> deltasMs_;  // 相邻两帧间的时间间隔(ms)
    int idx_ = 0;               // 下一待输出帧下标
    double speed_ = 1.0;
    QTimer timer_;
    QElapsedTimer elapsed_;     // 播放起算的真实时钟
    qint64 accMs_ = 0;          // 已回放的累计逻辑时长(ms)
};

} // namespace lgs

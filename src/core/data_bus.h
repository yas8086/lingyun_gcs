#pragma once
#include <QObject>
#include "model/telemetry_data.h"

namespace lgs {

// 遥测数据中转总线：解耦生产者(SerialManager)与消费者(UI/Alarm/Recorder)
class DataBus : public QObject {
    Q_OBJECT
public:
    explicit DataBus(QObject *parent = nullptr);
    void publish(const lgs::TelemetryData &data);

signals:
    void telemetryReady(const lgs::TelemetryData &data);
};

} // namespace lgs

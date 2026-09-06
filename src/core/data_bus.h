#pragma once
#include <QObject>
#include "model/telemetry_data.h"

namespace lgs {

// 遥测数据中转总线：解耦生产者(SerialManager/UdpLinkSource)与消费者(UI/Alarm/Recorder)
// 双链路冗余去重：串口+网口同帧双发，在汇聚点按机载时间戳 t 判重（50ms 容差），
// 仅放行更新的帧；下游（CSV/温度历史/告警/回放）不再见到同帧双份。
class DataBus : public QObject {
    Q_OBJECT
public:
    explicit DataBus(QObject *parent = nullptr);
    void publish(const lgs::TelemetryData &data);

signals:
    void telemetryReady(const lgs::TelemetryData &data);

private:
    double lastT_ = -1.0;   // 最近一次放行帧的机载时间戳（秒）；<0 表示尚未建立基准
    int staleCount_ = 0;    // 连续丢弃计数（机载时钟跳变时的强制恢复保护）
};

} // namespace lgs

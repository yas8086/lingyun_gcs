#pragma once
#include <QWidget>
#include "model/telemetry_data.h"

class QGroupBox;
class QLabel;

namespace lgs {

// 中部设备卡片区：BMS/MPPT/DCDC/LoRa 四张卡片实时数值
class DevicePanel : public QWidget {
    Q_OBJECT
public:
    explicit DevicePanel(QWidget *parent = nullptr);

    void updateData(const lgs::TelemetryData &data);

private:
    struct Card {
        QGroupBox *box = nullptr;
        QLabel *status = nullptr;   // 在线/离线 + 状态色
        QLabel *lines = nullptr;    // 字段多行文本
    };
    void buildBmsCard();
    void buildMpptCard();
    void buildDcdcCard();
    void buildLoraCard();

    Card bms_;
    Card mppt_;
    Card dcdc_;
    Card lora_;
};

} // namespace lgs

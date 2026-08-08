#pragma once
#include <QWidget>

class QLabel;

namespace lgs {

// 顶部状态栏：链路状态灯、四设备在线灯、时钟
class StatusBar : public QWidget {
    Q_OBJECT
public:
    enum DeviceId { Bms, Mppt, Dcdc, Lora };
    explicit StatusBar(QWidget *parent = nullptr);

    void updateLink(bool connected);
    void updateDevice(DeviceId id, bool online);
    void setClock(const QString &text);

private:
    QLabel *makeLed(const QString &name);

    QLabel *linkLed_;
    QLabel *bmsLed_;
    QLabel *mpptLed_;
    QLabel *dcdcLed_;
    QLabel *loraLed_;
    QLabel *clock_;
};

} // namespace lgs

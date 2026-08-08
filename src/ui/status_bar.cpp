#include "ui/status_bar.h"
#include <QHBoxLayout>
#include <QLabel>

namespace lgs {

StatusBar::StatusBar(QWidget *parent) : QWidget(parent) {
    auto *lay = new QHBoxLayout(this);
    lay->setContentsMargins(8, 4, 8, 4);
    linkLed_ = makeLed("链路");
    bmsLed_ = makeLed("BMS");
    mpptLed_ = makeLed("MPPT");
    dcdcLed_ = makeLed("DCDC");
    loraLed_ = makeLed("LoRa");
    clock_ = new QLabel("--:--:--", this);
    for (auto *w : {linkLed_, bmsLed_, mpptLed_, dcdcLed_, loraLed_})
        lay->addWidget(w);
    lay->addStretch();
    lay->addWidget(clock_);
}

QLabel *StatusBar::makeLed(const QString &name) {
    auto *lbl = new QLabel(name + " ●", this);
    lbl->setStyleSheet("color: gray;");
    return lbl;
}

void StatusBar::updateLink(bool connected) {
    linkLed_->setStyleSheet(connected ? "color: green;" : "color: gray;");
}

void StatusBar::updateDevice(DeviceId id, bool online) {
    QLabel *led = nullptr;
    switch (id) {
    case Bms:  led = bmsLed_;  break;
    case Mppt: led = mpptLed_; break;
    case Dcdc: led = dcdcLed_; break;
    case Lora: led = loraLed_; break;
    }
    led->setStyleSheet(online ? "color: green;" : "color: gray;");
}

void StatusBar::setClock(const QString &text) {
    clock_->setText(text);
}

} // namespace lgs

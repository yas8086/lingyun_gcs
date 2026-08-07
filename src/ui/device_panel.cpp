#include "ui/device_panel.h"
#include <QGroupBox>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QString>

namespace lgs {

DevicePanel::DevicePanel(QWidget *parent) : QWidget(parent) {
    auto *lay = new QHBoxLayout(this);
    buildBmsCard();
    buildMpptCard();
    buildDcdcCard();
    for (auto *box : {bms_.box, mppt_.box, dcdc_.box})
        lay->addWidget(box);
}

void DevicePanel::buildBmsCard() {
    bms_.box = new QGroupBox("BMS 电池", this);
    auto *lay = new QVBoxLayout(bms_.box);
    bms_.status = new QLabel(bms_.box);
    bms_.lines = new QLabel(bms_.box);
    bms_.lines->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    lay->addWidget(bms_.status);
    lay->addWidget(bms_.lines);
}

void DevicePanel::buildMpptCard() {
    mppt_.box = new QGroupBox("MPPT 光伏", this);
    auto *lay = new QVBoxLayout(mppt_.box);
    mppt_.status = new QLabel(mppt_.box);
    mppt_.lines = new QLabel(mppt_.box);
    mppt_.lines->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    lay->addWidget(mppt_.status);
    lay->addWidget(mppt_.lines);
}

void DevicePanel::buildDcdcCard() {
    dcdc_.box = new QGroupBox("DCDC 电源", this);
    auto *lay = new QVBoxLayout(dcdc_.box);
    dcdc_.status = new QLabel(dcdc_.box);
    dcdc_.lines = new QLabel(dcdc_.box);
    dcdc_.lines->setAlignment(Qt::AlignTop | Qt::AlignLeft);
    lay->addWidget(dcdc_.status);
    lay->addWidget(dcdc_.lines);
}

static void applyStatus(QGroupBox *box, QLabel *status, bool online,
                        const QString &on, const QString &off) {
    box->setStyleSheet(online ? "QGroupBox { border: 1px solid green; }"
                              : "QGroupBox { border: 1px solid gray; }");
    status->setText(online ? on : off);
    status->setStyleSheet(online ? "color: green;" : "color: gray;");
}

void DevicePanel::updateData(const lgs::TelemetryData &data) {
    if (data.bms) {
        applyStatus(bms_.box, bms_.status, data.bms->online,
                    "在线", "离线");
        bms_.lines->setText(
            QString("总压 %1 V\n电流 %2 A\nSOC %3%%\n压差 %4 V\n"
                    "最高温 %5 ℃\n告警 %6")
                .arg(data.bms->pack_v, 0, 'f', 1)
                .arg(data.bms->pack_i, 0, 'f', 1)
                .arg(data.bms->soc)
                .arg(data.bms->diff_v, 0, 'f', 2)
                .arg(data.bms->max_t, 0, 'f', 1)
                .arg(data.bms->alarm));
    } else {
        applyStatus(bms_.box, bms_.status, false, "在线", "离线");
        bms_.lines->clear();
    }

    if (data.mppt) {
        applyStatus(mppt_.box, mppt_.status, data.mppt->online, "在线", "离线");
        mppt_.lines->setText(
            QString("光伏 %1 V / %2 W\n电池 %3 V\n充电 %4 A\n"
                    "日发电 %5 kWh\n总发电 %6 kWh\n故障 %7")
                .arg(data.mppt->pv_v, 0, 'f', 1)
                .arg(data.mppt->pv_p, 0, 'f', 0)
                .arg(data.mppt->batt_v, 0, 'f', 1)
                .arg(data.mppt->charge_i, 0, 'f', 1)
                .arg(data.mppt->today, 0, 'f', 2)
                .arg(data.mppt->total, 0, 'f', 2)
                .arg(data.mppt->fault));
    } else {
        applyStatus(mppt_.box, mppt_.status, false, "在线", "离线");
        mppt_.lines->clear();
    }

    if (data.dcdc) {
        applyStatus(dcdc_.box, dcdc_.status, data.dcdc->online, "在线", "离线");
        dcdc_.lines->setText(
            QString("输入 %1 V\n输出 %2 V / %3 A\n功率 %4 W\n"
                    "温度 %5 ℃\n使能 %6\n故障 %7")
                .arg(data.dcdc->in_v, 0, 'f', 1)
                .arg(data.dcdc->out_v, 0, 'f', 1)
                .arg(data.dcdc->out_i, 0, 'f', 1)
                .arg(data.dcdc->out_p, 0, 'f', 0)
                .arg(data.dcdc->temp, 0, 'f', 1)
                .arg(data.dcdc->enabled ? "开" : "关")
                .arg(data.dcdc->fault));
    } else {
        applyStatus(dcdc_.box, dcdc_.status, false, "在线", "离线");
        dcdc_.lines->clear();
    }
}

} // namespace lgs

#include "core/recorder.h"
#include <QDateTime>

namespace lgs {

Recorder::Recorder(QObject *parent) : QObject(parent) {}

Recorder::~Recorder() {
    stop();
}

bool Recorder::start(const QString &filePath) {
    file_.setFileName(filePath);
    if (!file_.open(QIODevice::WriteOnly | QIODevice::Text)) {
        emit errorOccurred("无法打开记录文件: " + filePath);
        return false;
    }
    stream_.setDevice(&file_);
    headerWritten_ = false;
    return true;
}

void Recorder::stop() {
    if (file_.isOpen()) {
        stream_.flush();
        file_.close();
    }
}

bool Recorder::isRecording() const {
    return file_.isOpen();
}

QString Recorder::defaultFileName() {
    return "telemetry_" +
           QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss") + ".csv";
}

void Recorder::onTelemetry(const lgs::TelemetryData &data) {
    if (!file_.isOpen())
        return;

    if (!headerWritten_) {
        stream_ << "t,bms_online,bms_pack_v,bms_pack_i,bms_soc,"
                   "bms_max_v,bms_min_v,bms_diff_v,bms_max_t,bms_alarm,"
                   "mppt_online,mppt_pv_v,mppt_pv_p,mppt_batt_v,mppt_charge_i,"
                   "mppt_today,mppt_total,mppt_fault,"
                   "dcdc_online,dcdc_in_v,dcdc_out_v,dcdc_out_i,dcdc_out_p,"
                   "dcdc_temp,dcdc_enabled,dcdc_fault\n";
        headerWritten_ = true;
    }

    auto f2 = [](double v) { return QString::number(v, 'f', 3); };
    auto i = [](int v) { return QString::number(v); };

    QString line;
    line += f2(data.t) + ",";
    line += (data.bms ? (data.bms->online ? "1" : "0") : QString()) + ",";
    line += (data.bms ? f2(data.bms->pack_v) : QString()) + ",";
    line += (data.bms ? f2(data.bms->pack_i) : QString()) + ",";
    line += (data.bms ? i(data.bms->soc) : QString()) + ",";
    line += (data.bms ? f2(data.bms->max_v) : QString()) + ",";
    line += (data.bms ? f2(data.bms->min_v) : QString()) + ",";
    line += (data.bms ? f2(data.bms->diff_v) : QString()) + ",";
    line += (data.bms ? f2(data.bms->max_t) : QString()) + ",";
    line += (data.bms ? i(data.bms->alarm) : QString()) + ",";
    line += (data.mppt ? (data.mppt->online ? "1" : "0") : QString()) + ",";
    line += (data.mppt ? f2(data.mppt->pv_v) : QString()) + ",";
    line += (data.mppt ? f2(data.mppt->pv_p) : QString()) + ",";
    line += (data.mppt ? f2(data.mppt->batt_v) : QString()) + ",";
    line += (data.mppt ? f2(data.mppt->charge_i) : QString()) + ",";
    line += (data.mppt ? f2(data.mppt->today) : QString()) + ",";
    line += (data.mppt ? f2(data.mppt->total) : QString()) + ",";
    line += (data.mppt ? i(data.mppt->fault) : QString()) + ",";
    line += (data.dcdc ? (data.dcdc->online ? "1" : "0") : QString()) + ",";
    line += (data.dcdc ? f2(data.dcdc->in_v) : QString()) + ",";
    line += (data.dcdc ? f2(data.dcdc->out_v) : QString()) + ",";
    line += (data.dcdc ? f2(data.dcdc->out_i) : QString()) + ",";
    line += (data.dcdc ? f2(data.dcdc->out_p) : QString()) + ",";
    line += (data.dcdc ? f2(data.dcdc->temp) : QString()) + ",";
    line += (data.dcdc ? (data.dcdc->enabled ? "1" : "0") : QString()) + ",";
    line += (data.dcdc ? i(data.dcdc->fault) : QString());
    stream_ << line << "\n";
    stream_.flush();
}

} // namespace lgs

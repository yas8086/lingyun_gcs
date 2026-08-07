#include "core/data_bus.h"

namespace lgs {

DataBus::DataBus(QObject *parent) : QObject(parent) {}

void DataBus::publish(const lgs::TelemetryData &data) {
    emit telemetryReady(data);
}

} // namespace lgs

#pragma once
#include <QByteArray>
#include "model/telemetry_data.h"

namespace lgs {

// 将单帧 JSON 文本解析为 TelemetryData；成功返回 true
bool decodeJson(const QByteArray &json, TelemetryData &out);

} // namespace lgs

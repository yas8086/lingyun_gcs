#include "core/data_bus.h"

#include <cmath>

namespace lgs {

namespace {
// 连续丢弃上限：机载时钟回拨/NTP 跳变时 t 长期不前进，为防遥测卡死，
// 连续丢弃到该数目后强制放行当前帧并重置判重基准
constexpr int kMaxStaleDrop = 10;
// 同帧判定容差：容忍机载两条下发路径独立打时间戳的毫秒级偏差。
// 需满足 帧间隔 >> 容差（5Hz=200ms、10Hz=100ms 均安全；若帧间隔 ≤ 2×容差会误杀相邻真实帧）
constexpr double kDupToleranceSec = 0.05;
}

DataBus::DataBus(QObject *parent) : QObject(parent) {}

void DataBus::publish(const lgs::TelemetryData &data) {
    // 双链路冗余去重（L39 串口 + L33 网口同帧双发）：判重规则——
    //   t <= lastT_ + 容差 → 同帧双到（|Δt|≤容差，含严格相等）或乱序旧帧（<），丢弃；
    //   t >  lastT_ + 容差 → 真实新帧，放行并更新基准。
    // 重复/旧帧不发布：CSV 记录、温度历史宽表、告警评估、曲线采样全部只见到唯一一帧。
    // 原始报文记录（onRawFrame）在链路层各自落盘，保留双份用于链路诊断，不在此去重。
    // 已知边界（前提被打破时）：
    //   ① t 时间戳粒度 ≥ 帧间隔 → 真实帧被过杀（stale 保护 10 帧后放 1 帧，不会卡死）；
    //   ② t 缺失（≤0/NaN）→ 跳过去重直通，无法判重；
    //   ③ 多时钟源设备接入 → 需协议层带链路/设备标识后再裁决，当前单机载不涉及。
    if (data.t > 0.0 && !std::isnan(data.t)) {
        if (data.t <= lastT_ + kDupToleranceSec) {
            if (++staleCount_ < kMaxStaleDrop)
                return;
            // 连续丢弃过多：时钟异常，接受当前帧重置基准（避免遥测永久卡死）
        }
        lastT_ = data.t;
        staleCount_ = 0;
    }
    emit telemetryReady(data);
}

} // namespace lgs

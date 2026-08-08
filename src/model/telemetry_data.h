#pragma once
#include <optional>
#include <vector>

namespace lgs {

// 锂电池 BMS 状态
struct Bms {
    bool online = false;
    double pack_v = 0.0;   // 电池包总压 V
    double pack_i = 0.0;   // 总电流 A（充电为正）
    int soc = 0;           // 荷电状态 %
    double max_v = 0.0;    // 最高单体电压 V
    double min_v = 0.0;    // 最低单体电压 V
    double diff_v = 0.0;   // 单体压差 V
    double max_t = 0.0;    // 最高单体温度 ℃
    int alarm = 0;         // 0 正常 / 1 故障 / 2 严重
};

// MPPT 光伏控制器状态
struct Mppt {
    bool online = false;
    double pv_v = 0.0;     // 光伏电压 V
    double pv_p = 0.0;     // 光伏功率 W
    double batt_v = 0.0;   // 电池电压 V
    double charge_i = 0.0; // 充电电流 A
    double today = 0.0;    // 日发电量 kWh
    double total = 0.0;    // 总发电量 kWh
    int fault = 0;         // 故障状态位
};

// DCDC 电源模块状态
struct Dcdc {
    bool online = false;
    double in_v = 0.0;     // 输入电压 V
    double out_v = 0.0;    // 输出电压 V
    double out_i = 0.0;    // 输出电流 A
    double out_p = 0.0;    // 输出功率 W
    double temp = 0.0;     // 散热器温度 ℃
    bool enabled = false;  // 输出是否开启
    int fault = 0;         // 故障状态字节
};

// LoRa 采集节点（温度或压力二选一）
struct LoraSample {
    int id = 0;
    bool online = true;     // 被打包即在线
    double temp = 0.0;      // ℃；压力节点为 0
    double pressure = 0.0;  // Pa；温度节点为 0
    int alarm = 0;          // 0 正常 / 1 超上限 / -1 超下限（仅温度节点）
};

// LoRa 集中器本轮采样结果；nodes 为空表示本轮无在线节点
struct Lora {
    std::vector<LoraSample> nodes;
};

// 一帧完整遥测；std::optional 表示该设备离线/未出现在帧中
struct TelemetryData {
    double t = 0.0;
    std::optional<Bms> bms;
    std::optional<Mppt> mppt;
    std::optional<Dcdc> dcdc;
    // lora 特殊：机载收到过一轮采样即存在（nodes 可为空数组），
    // 与 bms/mppt/dcdc 的"离线键消失"语义不同
    std::optional<Lora> lora;
};

} // namespace lgs

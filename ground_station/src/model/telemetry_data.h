#pragma once
#include <optional>

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

// 一帧完整遥测；std::optional 表示该设备离线/未出现在帧中
struct TelemetryData {
    double t = 0.0;
    std::optional<Bms> bms;
    std::optional<Mppt> mppt;
    std::optional<Dcdc> dcdc;
};

} // namespace lgs

#pragma once
#include <QString>
#include <QMetaType>
#include <optional>
#include <vector>

namespace lgs {

// 锂电池 BMS 状态（102 串三元锂）
struct Bms {
    bool online = false;
    double pack_v = 0.0;   // 电池包总压 V
    double pack_i = 0.0;   // 总电流 A（充电为正）
    int soc = 0;           // 荷电状态 %
    double rsoc = 0.0;     // 真实 SOC %
    double max_v = 0.0;    // 最高单体电压 V
    double min_v = 0.0;    // 最低单体电压 V
    double diff_v = 0.0;   // 单体压差 V
    double max_t = 0.0;    // 最高单体温度 ℃
    double min_t = 0.0;    // 最低单体温度 ℃
    double avg_t = 0.0;    // 平均单体温度 ℃
    double diff_t = 0.0;   // 单体温差 ℃
    int riso_p = 0;        // 正极绝缘电阻 kΩ
    int riso_n = 0;        // 负极绝缘电阻 kΩ
    int alarm = 0;         // 0 正常 / 1 故障 / 2 严重
    double soh = 0.0;      // 健康状态 %（协议 5.1）
    int fault1 = 0;        // 一级故障/告警字（协议 5.1，32 位）
    int fault2 = 0;        // 二级故障/告警字
    int fault3 = 0;        // 三级故障/告警字
};

// 备用电源 BMS 状态（12S 备用电池，串口协议）
struct BackupBms {
    bool online = false;
    double pack_v = 0.0;   // 电池包总压 V
    double pack_i = 0.0;   // 总电流 A（充电为正）
    int soc = 0;           // 荷电状态 %
    int soh = 0;           // 健康状态 %
    double max_v = 0.0;    // 最高单体电压 V
    double min_v = 0.0;    // 最低单体电压 V
    double diff_v = 0.0;   // 单体压差 V
    double max_t = 0.0;    // 最高单体温度 ℃
    double min_t = 0.0;    // 最低单体温度 ℃
    double avg_t = 0.0;    // 平均单体温度 ℃
    double diff_t = 0.0;   // 单体温差 ℃
    int alarm = 0;         // 告警标志位（32 位）
    int protect = 0;       // 保护标志位（32 位）
    int fault = 0;         // 故障标志位（32 位）
    int sys = 0;           // 系统状态字（32 位）
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

// 飞控 FC 状态（协议 5.5，数传 UDP 与 4G 均含）
struct Fc {
    bool online = false;
    double roll = 0.0;    // 横滚角 deg
    double pitch = 0.0;   // 俯仰角 deg
    double yaw = 0.0;     // 偏航角 deg
    double lat = 0.0;     // 纬度 deg
    double lon = 0.0;     // 经度 deg
    double alt = 0.0;     // 相对起飞点高度 m
    double vx = 0.0;      // 东向速度 m/s (ENU)
    double vy = 0.0;      // 北向速度 m/s (ENU)
    double vz = 0.0;      // 天向速度 m/s (ENU)
    QString mode;         // 飞行模式
    bool armed = false;   // 是否解锁
    double batt_v = 0.0;  // 电池电压 V
    double batt_pct = 0.0;// 剩余电量 (0~1)
    // 协议 5.5 扩展：
    double hdg = 0.0;     // 航向角 deg（VfrHud compass_hdg，0~360）
    double airspd = 0.0;  // 空速 m/s
    double tas = 0.0;     // 真空速 m/s
    double gs = 0.0;      // 地速 m/s
    double climb = 0.0;   // 垂直爬升率 m/s
    double thr = 0.0;     // 油门 %（0~100）
    // EKF 估计器健康
    bool ekfPos = false;      // 位置锁定（GPS 失效）
    bool ekfGlitch = false;   // GPS 毛刺
    bool ekfAccelErr = false; // 加速度计错误
    // GPS 原始数据
    int gpsFix = 0;      // 0=无 1=NO_FIX 2=2D 3=3D 4=DGPS 5/6=RTK
    int gpsSat = 0;      // 卫星数（255=未知）
    int gpsEph = 0;      // 水平精度 HDOP
    int gpsEpv = 0;      // 垂直精度 VDOP
    // ESC 电调遥测（DroneCAN/回传时有遥测电调数 n>0；PWM 供电为 0）
    int escN = 0;                 // 有遥测电调数
    std::vector<double> escRpm;   // 定长 [10]
    std::vector<double> escV;     // 定长 [10]
    std::vector<double> escI;     // 定长 [10]
    std::vector<double> escTmp;   // 定长 [10]
};

// 一帧完整遥测；std::optional 表示该设备离线/未出现在帧中
struct TelemetryData {
    double t = 0.0;
    std::optional<Bms> bms;
    std::optional<BackupBms> backup;
    std::optional<Mppt> mppt;
    std::optional<Dcdc> dcdc;
    std::optional<Fc> fc;   // 仅 4G 链路
    // lora 特殊：机载收到过一轮采样即存在（nodes 可为空数组），
    // 与 bms/mppt/dcdc 的"离线键消失"语义不同
    std::optional<Lora> lora;
};

} // namespace lgs

Q_DECLARE_METATYPE(lgs::TelemetryData)

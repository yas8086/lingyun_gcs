#!/usr/bin/env python3
"""灵云01 地面站 · 场景化模拟遥测数据流

按《地面站对接协议》向指定串口周期发送 AA55 JSON 帧。
相比基础版，本工具提供周期性「场景剧本」，用于在本地验证新版 QML UI 的：
  1. 实时数据刷新（数值持续小范围波动）
  2. 告警触发逻辑（DCDC 过温 / BMS 过温 / 故障码 / 设备离线）
  3. 状态栏告警计数 / 运行日志 / 整机就绪度联动

用法:
    python3 serial_simulator.py <设备> [波特率=115200] [频率Hz=5]
    # 先创建虚拟串口对（两个端点），一个给模拟器写，一个给地面站读:
    socat -d -d pty,raw,echo=0,link=/tmp/gcs_pty pty,raw,echo=0,link=/tmp/gcs_pty2
    # 然后: python3 serial_simulator.py /tmp/gcs_pty     （或 /dev/pts/N 之一）
    # 地面站在「设置」页选择 /tmp/gcs_pty2 打开串口即可。

场景剧本（60s 周期，随模拟时间取模）：
    [0,60)     全程        : pack_v / 光伏 / 输出 持续小幅波动 → 实时刷新
    [10,13)    每60s        : BMS alarm=2（严重故障码）→ 故障码告警
    [20,23)    每60s        : DCDC 散热温度 45~47℃ → 触发 DCDC 过温(>43)
    [35,38)    每60s        : BMS 最高温度 56~60℃ → 触发 BMS 过温(>55, 严重)
    [45,48)    每60s        : DCDC 离线（帧中键消失）→ 数据超时离线告警 + 卡片置灰
    子节奏     每20s [12,14): LoRa 节点1 超上限 → LoRa 告警
"""

import json
import sys
import time
import serial


def in_window(t, start, end, period):
    """t 处于以 period 为周期、[start,end) 的时间窗内（t 为秒）"""
    return start <= (t % period) < end


def make_frame(t, soc):
    """根据模拟时刻 t 构造一帧遥测。t 单位秒。"""
    period = 60

    # ---- BMS 基础量（小幅波动，验证实时刷新）----
    pack_v = 367.2 + 0.4 * _sin(t, 0.5)
    pack_i = 0.0 + 1.0 * _sin(t, 0.3)
    max_v = 3.62 + 0.02 * _sin(t, 0.4)
    diff_v = max(0.03, 0.04 + 0.01 * _sin(t, 0.2))
    bms_alarm = 2 if in_window(t, 10, 13, period) else 0
    # BMS 最高温度：过温窗口内 56~60，其余 31~34
    bms_max_t = (56.0 + 4.0 * _sin(t, 0.8)) if in_window(t, 35, 38, period) \
        else (32.5 + 1.5 * _sin(t, 0.4))

    # ---- 备用电源 ----
    backup = {
        "online": True, "pack_v": 48.6 + 0.3 * _sin(t, 0.4),
        "pack_i": 1.2 + 0.3 * _sin(t, 0.2), "soc": 90, "soh": 96,
        "max_v": 4.18, "min_v": 4.11, "diff_v": 0.07,
        "max_t": 29.4, "min_t": 28.1, "avg_t": 28.7, "diff_t": 1.3,
        "alarm": 0, "protect": 0, "fault": 0, "sys": 3,
    }

    # ---- MPPT ----
    mppt = {
        "online": True, "pv_v": 89.5 + 1.5 * _sin(t, 0.5),
        "pv_p": 600.0 + 30.0 * _sin(t, 0.7),
        "batt_v": 86.0 + 0.5 * _sin(t, 0.4),
        "charge_i": 7.0 + 1.0 * _sin(t, 0.3),
        "today": 0.42, "total": 12.8, "fault": 0,
    }

    # ---- DCDC（过温窗口 + 离线窗口）----
    dcdc_offline = in_window(t, 45, 48, period)
    if dcdc_offline:
        # 离线：帧中不出现 dcdc 键，由地面站离线判定触发告警
        dcdc = None
    else:
        dcdc_temp = (45.0 + 2.0 * _sin(t, 1.0)) if in_window(t, 20, 23, period) \
            else (41.0 + 1.5 * _sin(t, 0.5))
        out_i = 5.2 + 0.5 * _sin(t, 0.3)
        dcdc = {
            "online": True, "in_v": 86.0 + 0.5 * _sin(t, 0.3),
            "out_v": 48.1 + 0.3 * _sin(t, 0.4),
            "out_i": out_i, "out_p": 48.1 * out_i,
            "temp": dcdc_temp, "enabled": True, "fault": 0,
        }

    # ---- LoRa（每 20s 中 12~14s 节点1 超上限）----
    lo_alarm = 1 if in_window(t, 12, 14, 20) else 0
    lora_temp1 = 65.0 if lo_alarm else 25.4 + 1.0 * _sin(t, 0.6)
    lora = {
        "nodes": [
            {"id": 1, "online": 1, "temp": lora_temp1, "pressure": 0,
             "alarm": lo_alarm},
            {"id": 2, "online": 1, "temp": 0, "pressure": 101325, "alarm": 0},
        ]
    }

    payload = {
        "t": t,
        "bms": {
            "online": True, "pack_v": pack_v, "pack_i": pack_i,
            "soc": soc, "rsoc": soc - 0.5, "max_v": max_v, "min_v": 3.58,
            "diff_v": diff_v, "max_t": bms_max_t, "min_t": 31.0,
            "avg_t": 31.8, "diff_t": 1.5, "riso_p": 520, "riso_n": 498,
            "alarm": bms_alarm,
        },
        "backup": backup,
        "mppt": mppt,
        "lora": lora,
    }
    if dcdc is not None:
        payload["dcdc"] = dcdc

    body = json.dumps(payload, separators=(",", ":"))
    return b"\xaa\x55" + body.encode() + b"\n"


def _sin(t, freq_hz):
    import math
    return math.sin(2 * math.pi * freq_hz * t)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    port = sys.argv[1]
    baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
    hz = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    ser = serial.Serial(port, baud, timeout=0.1)
    t0 = time.time()
    soc = 85
    dt = 1.0 / hz
    print(f"发送到 {port} @ {baud}，{hz} Hz（场景化遥测流）")
    print("场景: 实时波动 · BMS故障码·DCDC过温·BMS过温·DCDC离线 · LoRa超上限")
    try:
        i = 0
        while True:
            t = t0 + i * dt
            frame = make_frame(t, soc)
            ser.write(frame)
            soc = (soc + 1) % 101
            i += 1
            # 按绝对时间点对齐，避免固定 sleep 累积漂移
            time.sleep(max(0.0, t0 + i * dt - time.time()))
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()


if __name__ == "__main__":
    main()

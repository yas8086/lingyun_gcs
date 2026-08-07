#!/usr/bin/env python3
"""按《地面站对接协议》向指定串口周期发送模拟遥测 JSON。
用法: python3 serial_simulator.py <设备> [波特率=115200] [频率Hz=5]
可用 socat 创建虚拟串口对: socat -d -d pty,raw,echo=0 pty,raw,echo=0
"""
import json
import sys
import time
import serial


def make_frame(t, soc):
    payload = {
        "t": t,
        "bms": {"online": True, "pack_v": 367.2, "pack_i": 0.0,
                "soc": soc, "max_v": 3.62, "min_v": 3.58,
                "diff_v": 0.04, "max_t": 32.5, "alarm": 0},
        "mppt": {"online": True, "pv_v": 89.5, "pv_p": 600.0,
                 "batt_v": 86.0, "charge_i": 7.0,
                 "today": 0.42, "total": 12.8, "fault": 0},
        "dcdc": {"online": True, "in_v": 86.0, "out_v": 48.1,
                 "out_i": 5.2, "out_p": 250.0,
                 "temp": 41.0, "enabled": True, "fault": 0},
    }
    body = json.dumps(payload, separators=(",", ":"))
    return b"\xaa\x55" + body.encode() + b"\n"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    port = sys.argv[1]
    baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200
    hz = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    ser = serial.Serial(port, baud, timeout=0.1)
    t = time.time()
    soc = 85
    print(f"发送到 {port} @ {baud}，{hz} Hz")
    try:
        while True:
            frame = make_frame(t, soc)
            ser.write(frame)
            soc = (soc + 1) % 101
            t += 1.0 / hz
            # 按绝对时间点对齐，避免固定 sleep 累积漂移
            time.sleep(max(0.0, t - time.time()))
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()


if __name__ == "__main__":
    main()

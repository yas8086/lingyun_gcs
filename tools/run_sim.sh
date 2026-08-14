#!/usr/bin/env bash
# 灵云01 地面站 · 本地模拟遥测一键启动
#
# 用途：创建虚拟串口对，运行场景化遥测模拟器，供地面站连接查看
#      实时数据刷新、实时曲线绘制、告警联动等效果。
#
# 用法:
#   ./tools/run_sim.sh            # 创建虚拟串口并启动模拟器
#   ./tools/run_sim.sh --stop     # 停止模拟器与虚拟串口
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTY_GCS="/tmp/gcs_pty"      # 模拟器写入端
PTY_GCS2="/tmp/gcs_pty2"    # 地面站读取端（在设置页选择此路径打开）
PID_FILE="/tmp/gcs_sim.pid"
SOCAT_PID_FILE="/tmp/gcs_socat.pid"

stop_all() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    if [ -f "$SOCAT_PID_FILE" ]; then
        kill "$(cat "$SOCAT_PID_FILE")" 2>/dev/null || true
        rm -f "$SOCAT_PID_FILE"
    fi
    pkill -f "socat .*gcs_pty" 2>/dev/null || true
    rm -f "$PTY_GCS" "$PTY_GCS2"
}

if [ "${1:-}" = "--stop" ]; then
    stop_all
    echo "已停止模拟器与虚拟串口"
    exit 0
fi

# 清理残留后创建虚拟串口对。
# 注意：socat 必须 setsid + nohup 脱离会话后台运行——若直接 & 后台，
# 父 shell/终端退出时会向其发送 SIGHUP 将其杀死，导致 /tmp/gcs_pty*
# 变成指向已消失 pts 的悬空链接，地面站打开时报 "No such file or directory"。
stop_all
setsid nohup socat -d -d pty,raw,echo=0,link="$PTY_GCS" pty,raw,echo=0,link="$PTY_GCS2" \
    >/dev/null 2>&1 < /dev/null &
echo $! > "$SOCAT_PID_FILE"
sleep 1
if [ ! -e "$PTY_GCS" ] || [ ! -e "$PTY_GCS2" ]; then
    echo "创建虚拟串口失败：请确认 socat 已安装" >&2
    exit 1
fi

# 启动场景化模拟器（写端，5Hz 与地面站采样/刷新节奏匹配）
setsid nohup python3 "$SCRIPT_DIR/serial_simulator.py" "$PTY_GCS" 115200 5 \
    >/tmp/gcs_sim.log 2>&1 < /dev/null &
echo $! > "$PID_FILE"
sleep 0.5

echo "======================================================"
echo " 模拟遥测已启动  ✅"
echo "  模拟器写入端 : $PTY_GCS"
echo "  地面站读取端 : $PTY_GCS2"
echo ""
echo "  请在地面站「设置」→ 串口，选择: $PTY_GCS2"
echo "  波特率 115200，打开后即可看到实时曲线波动。"
echo ""
echo "  查看模拟器日志 : cat /tmp/gcs_sim.log"
echo "  停止           : ./tools/run_sim.sh --stop"
echo "======================================================"
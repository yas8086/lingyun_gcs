#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
云卓 C14PRO 云台 UDP 控制测试脚本（复刻 RCSDK COMMON/C10Pro 协议层）
====================================================================
协议依据：云卓 RCSDK（gitee.com/skydroid/rcsdk-demo）PayloadType.COMMON / C10PRO，
         以及《云卓云台相机协议 v1.1.5》。

- 传输：UDP，目标端口 5000（C14PRO 手册视频地址为 192.168.144.108:554，控制同网段）
- 命令：纯文本 ASCII，结构 = 前缀 + 数据(2 位 HEX) + CRC(2 位 HEX)
- CRC ：对「前缀+数据」逐字符 ASCII 累加求和 & 0xFF，转大写 2 位 HEX

示例（RCSDK demo 已验证）：
    #TPUG2wGSY6469   航向 右，速度 0x64(100)
    #TPUG2wGSY9C7B   航向 左，速度 0x9C(-100)
    #TPUG2wGSP6460   俯仰 上，速度 0x64(100)
    #TPUG2wGSP9C72   俯仰 下，速度 0x9C(-100)
    #TPUD2wCAP013E   拍照
    #TPUD2wREC0144   开始录像
    #TPUD2wREC0043   停止录像

用法：
    python3 c14pro_udp_test.py --ip 192.168.144.108 [--port 5000] [--cmd GSY64] [--interactive]
    python3 c14pro_udp_test.py --ip 192.168.144.108 --interactive   # 交互式菜单
"""
import argparse
import socket
import sys
import time


def crc(cmd: str) -> str:
    """云卓协议校验：字符串 ASCII 累加和 & 0xFF → 大写 2 位 HEX"""
    return format(sum(ord(c) for c in cmd) & 0xFF, "02X").upper()


def build_cmd(prefix: str, data_hex: str) -> str:
    """构造完整命令：前缀 + 数据 + CRC（校验覆盖前缀+数据）"""
    body = prefix + data_hex
    return body + crc(body)


# 前缀表（数据位为 2 位 HEX，如速度 / 开关状态）
PREFIX = {
    "GSY": "#TPUG2wGSY",   # 航向速度控制（0x64=+100 右，0x9C=-100 左）
    "GSP": "#TPUG2wGSP",   # 俯仰速度控制（0x64=+100 上，0x9C=-100 下）
    "CAP": "#TPUD2wCAP",   # 相机动作（0x01=拍照）
    "REC": "#TPUD2wREC",   # 录像（0x01=开始 0x00=停止）
    "DZM": "#TPUD2wDZM",   # 变焦（0x0A=放大 0x0B=缩小，RCSDK addZoomRatios/subtractZoomRatios）
    "PTZ": "#TPUG2wPTZ",   # 云台动作（0x05=回中，RCSDK AKey.MID；0x01=朝上 0x02=朝下 0x03=朝左 0x04=朝右）
    "SLR": "#TPUD2rSLR",   # 单次激光测距（0x00 触发；回包 #TPUD4rSLR X0X1X2X3 CC，数据=分米）
    "GAA": "#TPUG2wGAA",   # 姿态回读开关（0x01=1Hz 主动送出 / 0x00=关闭；回包 #TPUGCrGAC ...）
}


class C14ProController:
    def __init__(self, ip: str, port: int = 5000, timeout: float = 1.0):
        self.ip = ip
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout)

    def send(self, cmd: str, label: str = "", recv_count: int = 1) -> str:
        """发送 UDP 文本命令，返回接收到的响应（可能为空）。
        recv_count>1：连续接收多个回包（测距/姿态等命令可能先回确认帧，稍后回结果帧）"""
        data = cmd.encode("utf-8")
        self.sock.sendto(data, (self.ip, self.port))
        print(f"[TX] {cmd}  {label}")
        got = ""
        for _ in range(recv_count):
            try:
                resp, addr = self.sock.recvfrom(1024)
                text = resp.decode("utf-8", errors="replace")
                print(f"[RX] {text}")
                if not got:
                    got = text
            except socket.timeout:
                print("     (无响应/超时)")
                break
        return got

    def close(self):
        self.sock.close()


def interactive(ctrl: C14ProController):
    menu = [
        ("航向 → 右（速100）", build_cmd(PREFIX["GSY"], "64")),
        ("航向 → 左（速100）", build_cmd(PREFIX["GSY"], "9C")),
        ("俯仰 → 上（速100）", build_cmd(PREFIX["GSP"], "64")),
        ("俯仰 → 下（速100）", build_cmd(PREFIX["GSP"], "9C")),
        ("停止航向/俯仰", build_cmd(PREFIX["GSY"], "00")),
        ("回中", build_cmd(PREFIX["PTZ"], "05")),
        ("变焦 → 放大", build_cmd(PREFIX["DZM"], "0A")),
        ("变焦 → 缩小", build_cmd(PREFIX["DZM"], "0B")),
        ("拍照", build_cmd(PREFIX["CAP"], "01")),
        ("开始录像", build_cmd(PREFIX["REC"], "01")),
        ("停止录像", build_cmd(PREFIX["REC"], "00")),
        ("激光测距", build_cmd(PREFIX["SLR"], "00")),
        ("使能姿态回读1Hz", build_cmd(PREFIX["GAA"], "01")),
        ("关闭姿态回读", build_cmd(PREFIX["GAA"], "00")),
    ]
    while True:
        print("\n===== C14PRO UDP 控制 =====")
        for i, (desc, _) in enumerate(menu, 1):
            print(f"  {i}. {desc}")
        print("  0. 退出")
        try:
            choice = input("请选择: ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if choice == "0":
            break
        if choice.isdigit() and 1 <= int(choice) <= len(menu):
            desc, cmd = menu[int(choice) - 1]
            # 激光测距：可能先回确认帧、稍后回测距结果帧，多收几个回包
            if desc == "激光测距":
                ctrl.send(cmd, desc, recv_count=4)
            else:
                ctrl.send(cmd, desc)
        else:
            print("无效选择")


def main():
    ap = argparse.ArgumentParser(description="云卓 C14PRO UDP 云台控制测试")
    ap.add_argument("--ip", default="192.168.144.108", help="C14PRO 网口 IP")
    ap.add_argument("--port", type=int, default=5000, help="UDP 控制端口（默认 5000）")
    ap.add_argument("--cmd", help="自定义命令体，如 GSY64 / GSP64 / CAP01 / REC01 / REC00")
    ap.add_argument("--interactive", action="store_true", help="交互式菜单")
    args = ap.parse_args()

    ctrl = C14ProController(args.ip, args.port)
    print(f"连接 {args.ip}:{args.port} (UDP)")

    if args.cmd:
        # 支持 "GSY64" 或 "#TPUG2wGSY6469" 两种输入
        raw = args.cmd.strip()
        if raw.startswith("#"):
            full = raw
        else:
            # 尝试按前缀+数据解析
            for key, prefix in PREFIX.items():
                if raw.startswith(key):
                    full = build_cmd(prefix, raw[len(key):])
                    break
            else:
                print(f"无法识别命令: {raw}，请用 GSY64/GSP64/CAP01/REC01/REC00 或完整 #TP... 命令")
                sys.exit(1)
        ctrl.send(full, args.cmd)
    elif args.interactive:
        interactive(ctrl)
    else:
        # 默认发送一组演示指令
        for desc, cmd in [
            ("航向 → 右（速100）", build_cmd(PREFIX["GSY"], "64")),
            ("停止", build_cmd(PREFIX["GSY"], "00")),
            ("俯仰 → 下（速100）", build_cmd(PREFIX["GSP"], "9C")),
            ("停止", build_cmd(PREFIX["GSP"], "00")),
        ]:
            ctrl.send(cmd, desc)
            time.sleep(0.3)
    ctrl.close()


if __name__ == "__main__":
    main()

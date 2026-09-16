#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
siyi_set_ip.py —— 思翼云台相机 SDK 改 IP 工具（协议 CMD 0x82）

依据《SIYI A2 mini User Manual v1.2》3.3.2 SDK Communication Commands：
  帧格式: 55 66 | CTRL | LEN(L,H) | SEQ(L,H) | CMD | DATA | CRC16(L,H)
  DATA  : 新IP(4字节小端) + 子网掩码(4) + 网关(4)，共 12 字节
  CRC16 : CCITT 多项式 X^16+X^12+X^5+1（0x1021），初值 0x0000，从帧头算至 DATA 末尾
  ACK   : CTRL=0x02，DATA=01 即 Success（需断电重启设备后生效）

用法:
  python3 tools/siyi_set_ip.py <设备当前IP> <新IP> [掩码] [网关]
示例（把出厂 .25 的相机改为 .27）:
  python3 tools/siyi_set_ip.py 192.168.144.25 192.168.144.27

⚠ 注意事项:
  1. 必须单独直连操作——同网段已有其他思翼相机时（如 A2 mini 占用 .25），
     新相机出厂同为 .25 会 IP 冲突，UDP 命令只会到达 ARP 表中那一台，
     可能改错设备。操作前把其他相机断电，或用网线直连电脑。
  2. ACK Success 后必须给相机断电重启，新 IP 才生效。
  3. 掩码/网关通常保持默认: 255.255.255.0 / 192.168.144.1
  4. 端口 37260 为思翼 SDK 控制口（UDP），与 RTSP 拉流口(8554)无关。
"""
import socket
import sys


def crc16(buf: bytes, init: int = 0x0000) -> int:
    """CRC16-CCITT：多项式 0x1021，初值 0x0000，无反射。"""
    crc = init
    for b in buf:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def ip_le(s: str) -> bytes:
    """点分十进制 → 4 字节小端（a.b.c.d → d.c.b.a）。"""
    return bytes(int(x) for x in s.split("."))[::-1]


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    dev, new_ip = sys.argv[1], sys.argv[2]
    mask = sys.argv[3] if len(sys.argv) > 3 else "255.255.255.0"
    gw = sys.argv[4] if len(sys.argv) > 4 else "192.168.144.1"

    data = ip_le(new_ip) + ip_le(mask) + ip_le(gw)
    frame = bytes([0x55, 0x66, 0x01, 0x0C, 0x00, 0x00, 0x00, 0x82]) + data
    frame += crc16(frame).to_bytes(2, "little")
    print("发送:", frame.hex(" "))

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    s.sendto(frame, (dev, 37260))
    try:
        ack = s.recv(1024)
        print("ACK :", ack.hex(" "))
        # ACK 帧: 55 66 02 01 00 <seq> 82 <result> <crc>
        # result=01 Success / 00 Failed
        ok = len(ack) >= 10 and ack[7] == 0x82 and ack[8] == 0x01
        print("结果:", "✓ 成功——请给相机断电重启使新 IP 生效" if ok else "✗ 设备返回失败")
    except socket.timeout:
        print("无应答（设备离线 / 不支持 0x82 / IP 冲突环境）")


if __name__ == "__main__":
    main()

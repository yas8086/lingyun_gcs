#pragma once
#include <QByteArray>

namespace lgs {

// 协议最大帧长（帧头 2 字节 + JSON + 帧尾 \n）字节数。
// 超过该长度仍未出现帧尾时判定为脏数据，丢弃缓冲，防止无界增长导致 OOM。
inline constexpr int kMaxFrameBytes = 4096;

// 帧头魔数（协议：0xAA 0x55），解析与回放共用，避免两处硬编码不一致
inline const QByteArray kFrameHead = QByteArray("\xAA\x55");

// 字节流分帧器：扫描 0xAA 0x55 帧头，至 \n 截取 JSON 文本
class FrameParser {
public:
    void push(const QByteArray &data);   // 追加新收到的字节
    bool takeFrame(QByteArray &outJson); // 取出下一完整帧的 JSON，返回是否成功

private:
    QByteArray buffer_;
};

} // namespace lgs

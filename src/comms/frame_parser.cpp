#include "comms/frame_parser.h"

namespace lgs {

void FrameParser::push(const QByteArray &data) {
    buffer_.append(data);
}

bool FrameParser::takeFrame(QByteArray &outJson) {
    // 寻找帧头
    int head = buffer_.indexOf(kFrameHead);
    if (head < 0) {
        // 无帧头：仅当末字节可能是下一帧头首字节 0xAA 时保留（跨包半帧头），否则清空
        const bool keep = !buffer_.isEmpty() && buffer_.at(buffer_.size() - 1) == '\xAA';
        buffer_.clear();
        if (keep)
            buffer_.append('\xAA');
        return false;
    }
    if (head > 0) {
        // 丢弃帧头前的杂散字节
        buffer_.remove(0, head);
    }
    // 寻找帧尾 \n
    int tail = buffer_.indexOf('\n', 2);
    if (tail < 0) {
        // 帧未收完整。若已超过协议最大帧长仍无帧尾，判定为脏数据（帧头后无 \n），
        // 丢弃至下一个帧头，防止缓冲无界增长导致 OOM。
        if (buffer_.size() > kMaxFrameBytes) {
            const int next = buffer_.indexOf(kFrameHead, 2);
            if (next < 0)
                buffer_.clear();
            else
                buffer_.remove(0, next);
        }
        return false;
    }
    // 截取 JSON（位于 0xAA 0x55 之后、\n 之前）
    outJson = buffer_.mid(2, tail - 2);
    buffer_.remove(0, tail + 1);
    return true;
}

} // namespace lgs

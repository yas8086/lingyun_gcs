#include "comms/frame_parser.h"

namespace lgs {

void FrameParser::push(const QByteArray &data) {
    buffer_.append(data);
}

bool FrameParser::takeFrame(QByteArray &outJson) {
    for (;;) {
        // 寻找帧头
        int head = buffer_.indexOf("\xAA\x55");
        if (head < 0) {
            // 无帧头：仅保留可能跨包的最后 1 字节，其余丢弃，避免缓冲区无限增长
            buffer_.truncate(buffer_.size() > 1 ? 1 : buffer_.size());
            return false;
        }
        if (head > 0) {
            // 丢弃帧头前的杂散字节
            buffer_.remove(0, head);
        }
        // 寻找帧尾 \n
        int tail = buffer_.indexOf('\n', 2);
        if (tail < 0) {
            return false; // 帧未收完整，等待更多数据
        }
        // 截取 JSON（位于 0xAA 0x55 之后、\n 之前）
        outJson = buffer_.mid(2, tail - 2);
        buffer_.remove(0, tail + 1);
        return true;
    }
}

} // namespace lgs

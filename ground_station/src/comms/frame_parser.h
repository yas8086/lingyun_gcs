#pragma once
#include <QByteArray>

namespace lgs {

// 字节流分帧器：扫描 0xAA 0x55 帧头，至 \n 截取 JSON 文本
class FrameParser {
public:
    void push(const QByteArray &data);   // 追加新收到的字节
    bool takeFrame(QByteArray &outJson); // 取出下一完整帧的 JSON，返回是否成功

private:
    QByteArray buffer_;
};

} // namespace lgs

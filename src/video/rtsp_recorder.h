#pragma once

#include <QObject>
#include <QString>
#include <gst/gst.h>

namespace lgs {

// RTSP 原始流录制：rtspsrc → parsebin（自动 depay+parse，不解码）→ matroskamux → filesink
// 编码流原样写入 MKV（H.264/H.265 不转码，CPU 开销极低），VLC/ffplay 可直接播放。
// stop() 先发 EOS 让 mux 写完索引再置 NULL，保证文件完整可拖动。
class RtspRecorder : public QObject {
    Q_OBJECT
public:
    explicit RtspRecorder(QObject *parent = nullptr);
    ~RtspRecorder() override;

    // 开始录制（url：RTSP 地址；filePath：输出 .mkv 完整路径）。失败返回 false。
    bool start(const QString &url, const QString &filePath);
    // 停止并收尾文件（发 EOS + 限时等待，最多约 3s）
    void stop();
    bool recording() const { return pipeline_ != nullptr; }
    QString fileName() const { return fileName_; }   // 当前输出文件名（未录制为空）

private:
    // rtspsrc/parsebin 的动态 pad 链接：user_data 为下游元素
    static void onPadAdded(GstElement *elem, GstPad *pad, gpointer user_data);
    // 总线消息（仅日志：录制错误不自动重连，由用户重新发起）
    static GstBusSyncReply onBusSync(GstBus *bus, GstMessage *msg, gpointer user_data);

    GstElement *pipeline_ = nullptr;
    QString fileName_;
};

} // namespace lgs

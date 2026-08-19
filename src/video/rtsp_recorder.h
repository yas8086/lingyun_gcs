#pragma once

#include <QObject>
#include <QString>
#include <QTimer>
#include <gst/gst.h>

namespace lgs {

// RTSP 原始流录制：rtspsrc → parsebin（自动 depay+parse，不解码）→ matroskamux → filesink
// 编码流原样写入 MKV（H.264/H.265 不转码，CPU 开销极低），VLC/ffplay 可直接播放。
// stop() 先发 EOS 让 mux 写完索引再置 NULL，保证文件完整可拖动。
// 收尾采用异步（QTimer 轮询 bus）：避免原同步等待（最长 3s）阻塞 GUI 线程。
class RtspRecorder : public QObject {
    Q_OBJECT
public:
    explicit RtspRecorder(QObject *parent = nullptr);
    ~RtspRecorder() override;

    // 开始录制（url：RTSP 地址；filePath：输出 .mkv 完整路径）。失败返回 false。
    bool start(const QString &url, const QString &filePath);
    // 停止并收尾文件（发 EOS + 异步等待 mux 写完索引，不阻塞调用线程）
    void stop();
    bool recording() const { return pipeline_ != nullptr; }
    QString fileName() const { return fileName_; }   // 当前输出文件名（未录制为空）

private:
    // rtspsrc/parsebin 的动态 pad 链接：user_data 为下游元素
    static void onPadAdded(GstElement *elem, GstPad *pad, gpointer user_data);
    // 总线消息（仅日志：录制错误不自动重连，由用户重新发起）
    static GstBusSyncReply onBusSync(GstBus *bus, GstMessage *msg, gpointer user_data);
    // 异步收尾轮询：非阻塞取 EOS/ERROR 消息，收到或超时 3s 后完成释放
    void pollFinalize();
    // 同步完成收尾（释放 bus/pipeline）
    void finishFinalize();

    GstElement *pipeline_ = nullptr;
    QString fileName_;
    GstBus *pendingBus_ = nullptr;   // stop 后等待收尾的 bus（所有权归本类）
    QTimer *finalizeTimer_ = nullptr; // 收尾轮询
    qint64 finalizeStartUs_ = 0;      // 开始收尾时刻（µs），用于 3s 超时兜底
    bool finalizing_ = false;         // 正在收尾（避免重复 stop）
};

} // namespace lgs

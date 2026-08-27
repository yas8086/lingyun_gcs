#pragma once

#include <QObject>
#include <QString>
#include <QTimer>
#include <atomic>
#include <gst/gst.h>

namespace lgs {

// RTSP 原始流录制：rtspsrc → parsebin（自动 depay+parse，不解码）→ matroskamux → filesink
// 编码流原样写入 MKV（H.264/H.265 不转码，CPU 开销极低），VLC/ffplay 可直接播放。
// stop() 先发 EOS 让 mux 写完索引再置 NULL，保证文件完整可拖动。
// 收尾采用异步（QTimer 轮询 bus）：避免原同步等待（最长 3s）阻塞 GUI 线程。
// 录像起点关键帧对齐（2026-08-27）：录制连接从码流当前位置接入，起始段常落在
// P 帧中间（无 IDR/SPS/PPS 参考基准），部分相机（如云卓 C14PRO）对第二路连接
// 不主动发关键帧 → 文件开头灰屏花屏。修复：parsebin→mux 视频 pad 挂 buffer probe，
// 丢弃非关键帧直到首个 IDR 放行（思翼/云卓通吃，红外长 IDR 间隔同样有效）。
class RtspRecorder : public QObject {
    Q_OBJECT
public:
    explicit RtspRecorder(QObject *parent = nullptr);
    ~RtspRecorder() override;

    // 开始录制（url：RTSP 地址；filePath：输出 .mkv 完整路径）。失败返回 false。
    bool start(const QString &url, const QString &filePath);
    // 停止并收尾文件（发 EOS + 异步等待 mux 写完索引，不阻塞调用线程）
    void stop();
    // 收尾完成（EOS 写完索引或 3s 超时兜底）：停止方收到该信号后再 deleteLater，
    // 避免过早析构中断 matroskamux 写文件尾与索引（否则 .mkv 不可拖/不可播）。
    Q_SIGNAL void finalized();
    bool recording() const { return pipeline_ != nullptr; }
    QString fileName() const { return fileName_; }   // 当前输出文件名（未录制为空）

private:
    // rtspsrc/parsebin 的动态 pad 链接：user_data 为下游元素
    static void onPadAdded(GstElement *elem, GstPad *pad, gpointer user_data);
    // 关键帧门卫：parsebin→mux 视频 pad probe，首个关键帧（非 DELTA_UNIT）前丢帧
    static GstPadProbeReturn onKeyProbe(GstPad *pad, GstPadProbeInfo *info, gpointer user_data);
    // parsebin 自动创建 h264parse/h265parse 时注入 config-interval=-1：
    // 云卓 C14PRO 的 HEVC 流内周期重发 VPS/SPS/PPS，h265parse 默认剥掉带内参数集，
    // 而 mkv 的 CodecPrivate 只在开头写一次 → 中途参数集丢失 → 持续花屏
    // （真机实测 POC 参考错误 40→1）。-1 = 每个关键帧前带内补发参数集，思翼 H.264 同样受益。
    static void onChildAdded(GstBin *bin, GstElement *child, gpointer user_data);
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
    std::atomic<bool> keySeen_{false}; // 已放行首个关键帧（probe 流程线程读写）
};

} // namespace lgs

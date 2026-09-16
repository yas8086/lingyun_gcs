#pragma once

#include <QObject>
#include <QImage>
#include <QMutex>
#include <QThread>
#include <atomic>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>

namespace lgs {

// RTSP 视频流拉流（B 方案：GStreamer 管道 + appsink 取帧，转为 QImage）
// 每路相机一个 RtspStream 实例；帧到达时发 frameChanged（跨线程 Queued），
// QML 侧 VideoSurface 监听该信号刷新纹理上屏。断流自动带退避重连。
//
// 线程模型（关键）：GStreamer 的 gst_element_set_state 会在**调用线程**同步完成
// 到 PAUSED 的切换——对 rtspsrc 即 TCP 连接 + RTSP DESCRIBE/SETUP 握手，
// 目标离线时最长阻塞 tcp-timeout（默认 20s）。因此管道的构建/销毁全部在
// 专用 worker 线程（worker_/workerCtx_）串行执行，GUI 线程只投递命令并
// 即时更新 started/busy 标志，界面永不因连接超时而冻结。
class RtspStream : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool started READ started NOTIFY startedChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
public:
    explicit RtspStream(QObject *parent = nullptr);
    ~RtspStream() override;

    QString url() const;
    void setUrl(const QString &u);
    bool online() const;
    bool busy() const;
    bool started() const;
    // 最近一次拉流失败原因（如 DNS 解析失败 / 连接拒绝 / 认证失败 / 超时 / 插件缺失）
    QString lastError() const { return lastError_; }

    // 拉流控制（QML 调用；实际管道操作投递到 worker 线程）
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void reconnect();

    // 最新一帧（GUI 线程读取，内部加锁）
    QImage lastFrame() const;

signals:
    void urlChanged();
    void onlineChanged();
    void busyChanged();
    void startedChanged();
    void frameChanged();
    void lastErrorChanged();

private:
    static GstFlowReturn onNewSample(GstAppSink *sink, gpointer user_data);
    static GstBusSyncReply onBusSync(GstBus *bus, GstMessage *msg, gpointer user_data);
    static void onPadAdded(GstElement *elem, GstPad *pad, gpointer user_data);
    void onSample(GstAppSink *sink);
    void setOnline(bool on);
    void setStarted(bool on);
    // 设置最近错误原因并广播（跨线程安全：由 bus 回调排队到主线程）
    void setLastError(const QString &e);
    void teardown();          // 仅 worker 线程执行（析构兜底除外）
    void scheduleReconnect();
    // 管道生命周期（worker 线程执行；finishStart 排回 GUI 更新标志）
    void doStart();
    void doStop();
    void finishStart(bool ok);

    QString url_;              // urlMutex_ 保护（GUI 写 / worker 读）
    QMutex urlMutex_;
    // GST streaming 线程写 / Qt 主线程读 的状态，必须原子化避免数据竞争（UB）
    std::atomic<bool> online_{false};
    bool busy_ = false;        // 仅 GUI 线程访问（start/stop 投递置位，finishStart 复位）
    std::atomic<bool> started_{false};
    GstElement *pipeline_ = nullptr;   // 仅 worker 线程访问（析构兜底时线程已停）
    GstElement *sink_ = nullptr;       // 同上
    mutable QMutex mutex_;
    QImage lastFrame_;
    std::atomic<qint64> lastSampleUs_{0};   // 最近帧时间戳（µs），用于超时看门狗
    std::atomic<qint64> startUs_{0};        // 开始连接时刻（µs），用于首帧超时检测
    QTimer *watchdog_ = nullptr;
    QTimer *reconnect_ = nullptr;
    int reconnectAttempt_ = 0;
    QString lastError_;          // 最近拉流失败原因（主线程写读）
    // 管道操作 worker：串行队列，消除 GUI 线程的握手阻塞
    QThread *worker_ = nullptr;
    QObject *workerCtx_ = nullptr;     // 空壳锚点，queued lambda 在 worker 线程执行
};

} // namespace lgs

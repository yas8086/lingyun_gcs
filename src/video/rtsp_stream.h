#pragma once

#include <QObject>
#include <QImage>
#include <QMutex>
#include <atomic>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>

namespace lgs {

// RTSP 视频流拉流（B 方案：GStreamer 管道 + appsink 取帧，转为 QImage）
// 每路相机一个 RtspStream 实例；帧到达时发 frameChanged（跨线程 Queued），
// QML 侧 VideoSurface 监听该信号刷新纹理上屏。断流自动带退避重连。
class RtspStream : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool started READ started NOTIFY startedChanged)
public:
    explicit RtspStream(QObject *parent = nullptr);
    ~RtspStream() override;

    QString url() const;
    void setUrl(const QString &u);
    bool online() const;
    bool busy() const;
    bool started() const;

    // 拉流控制（QML 调用）
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

private:
    static GstFlowReturn onNewSample(GstAppSink *sink, gpointer user_data);
    static GstBusSyncReply onBusSync(GstBus *bus, GstMessage *msg, gpointer user_data);
    static void onPadAdded(GstElement *elem, GstPad *pad, gpointer user_data);
    void onSample(GstAppSink *sink);
    void setOnline(bool on);
    void setStarted(bool on);
    void teardown();
    void scheduleReconnect();

    QString url_;
    // GST streaming 线程写 / Qt 主线程读 的状态，必须原子化避免数据竞争（UB）
    std::atomic<bool> online_{false};
    bool busy_ = false;        // 仅主线程访问（start/stop 均为 GUI 线程调用）
    std::atomic<bool> started_{false};
    GstElement *pipeline_ = nullptr;
    GstElement *sink_ = nullptr;
    mutable QMutex mutex_;
    QImage lastFrame_;
    std::atomic<qint64> lastSampleUs_{0};   // 最近帧时间戳（µs），用于超时看门狗
    std::atomic<qint64> startUs_{0};        // start() 成功时刻（µs），用于首帧超时检测
    QTimer *watchdog_ = nullptr;
    QTimer *reconnect_ = nullptr;
    int reconnectAttempt_ = 0;
};

} // namespace lgs

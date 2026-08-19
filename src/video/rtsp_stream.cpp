#include "video/rtsp_stream.h"

#include <QTimer>
#include <QDebug>
#include <gst/gst.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>

namespace lgs {

RtspStream::RtspStream(QObject *parent)
    : QObject(parent)
{
    // 超时看门狗：1s 巡检；在线后 3s 无帧视为断流；发起拉流后 8s 无首帧视为连接失败
    watchdog_ = new QTimer(this);
    watchdog_->setInterval(1000);
    connect(watchdog_, &QTimer::timeout, this, [this]() {
        const qint64 now = gst_util_get_timestamp() / 1000;
        if (online_.load() && lastSampleUs_.load() > 0 && (now - lastSampleUs_.load()) > 3000000)
            scheduleReconnect();
        else if (started_.load() && !online_.load() && startUs_.load() > 0 && (now - startUs_.load()) > 8000000)
            scheduleReconnect();   // 连接被拒/并发路数占满等场景（bus 会先报错，此为兜底）
    });
    watchdog_->start();

    // 重连：指数退避（2s 起步，上限 10s）
    reconnect_ = new QTimer(this);
    reconnect_->setSingleShot(true);
    connect(reconnect_, &QTimer::timeout, this, [this]() {
        if (url_.isEmpty()) return;
        start();
    });
}

RtspStream::~RtspStream()
{
    teardown();
}

QString RtspStream::url() const { return url_; }

void RtspStream::setUrl(const QString &u)
{
    if (url_ == u) return;
    url_ = u;
    qWarning() << "[RtspStream] setUrl:" << u;
    emit urlChanged();
}

bool RtspStream::online() const { return online_.load(); }

bool RtspStream::busy() const { return busy_; }

bool RtspStream::started() const { return started_.load(); }

void RtspStream::setStarted(bool on)
{
    if (started_.load() == on) return;
    started_.store(on);
    emit startedChanged();
}

QImage RtspStream::lastFrame() const
{
    QMutexLocker lock(&mutex_);
    return lastFrame_;
}

void RtspStream::start()
{
    if (busy_) return;
    if (url_.isEmpty()) {
        setOnline(false);
        return;
    }
    teardown();
    busy_ = true;
    emit busyChanged();
    qWarning() << "[RtspStream] start, url =" << url_;

    // 程序化构建管道：rtspsrc → decodebin → videoconvert → RGBA → appsink
    // 改用 g_object_set 直接设置 location：gst_parse_launch 对 URL 特殊字符
    // （://、用户名密码等）存在字符串解析陷阱，曾导致 location 未生效、
    // rtspsrc 报 "No valid RTSP URL was provided"
    pipeline_ = gst_pipeline_new("pipeline");
    GstElement *src = gst_element_factory_make("rtspsrc", "src");
    GstElement *dec = gst_element_factory_make("decodebin", "dec");
    GstElement *conv = gst_element_factory_make("videoconvert", "conv");
    GstElement *flt = gst_element_factory_make("capsfilter", "flt");
    GstElement *sink = gst_element_factory_make("appsink", "sink");
    if (!pipeline_ || !src || !dec || !conv || !flt || !sink) {
        qWarning() << "[RtspStream] Element 创建失败（缺少 GStreamer 插件？）";
        if (pipeline_) { gst_object_unref(pipeline_); pipeline_ = nullptr; }
        if (src) gst_object_unref(src);
        if (dec) gst_object_unref(dec);
        if (conv) gst_object_unref(conv);
        if (flt) gst_object_unref(flt);
        if (sink) gst_object_unref(sink);
        busy_ = false;
        emit busyChanged();
        setOnline(false);
        setStarted(false);
        scheduleReconnect();
        return;
    }

    // protocols: 4 == GST_RTSP_LOWER_TRANS_TCP（仅 RTSP over TCP interleaved）
    g_object_set(src,
                 "location", url_.toUtf8().constData(),
                 "protocols", static_cast<guint>(4),
                 "latency", static_cast<guint>(200),
                 nullptr);

    GstCaps *caps = gst_caps_new_simple("video/x-raw",
                                        "format", G_TYPE_STRING, "RGBA",
                                        nullptr);
    g_object_set(flt, "caps", caps, nullptr);
    gst_caps_unref(caps);

    gst_app_sink_set_max_buffers(GST_APP_SINK(sink), 1);
    gst_app_sink_set_drop(GST_APP_SINK(sink), TRUE);
    gst_app_sink_set_emit_signals(GST_APP_SINK(sink), FALSE);
    GstAppSinkCallbacks cb = {};
    cb.new_sample = RtspStream::onNewSample;
    gst_app_sink_set_callbacks(GST_APP_SINK(sink), &cb, this, nullptr);

    gst_bin_add_many(GST_BIN(pipeline_), src, dec, conv, flt, sink, nullptr);
    if (!gst_element_link_many(conv, flt, sink, nullptr)) {
        qWarning() << "[RtspStream] 静态链接失败（videoconvert→capsfilter→appsink）";
        gst_element_set_state(pipeline_, GST_STATE_NULL);
        gst_object_unref(pipeline_);
        pipeline_ = nullptr;
        busy_ = false;
        emit busyChanged();
        setOnline(false);
        setStarted(false);
        scheduleReconnect();
        return;
    }

    // 动态 pad：rtspsrc 与 decodebin 的 src pad 运行时才出现，回调中按 caps 链接
    g_signal_connect(src, "pad-added", G_CALLBACK(RtspStream::onPadAdded), dec);
    g_signal_connect(dec, "pad-added", G_CALLBACK(RtspStream::onPadAdded), conv);

    sink_ = sink;   // 元素所有权归 pipeline，teardown 随管道释放

    // 通过 GstBus 同步 handler 监听错误/EOS。
    // 注意：GstPipeline 上没有 "error"/"eos" GObject 信号（g_signal_connect 会报 CRITICAL），
    // 错误信息以总线消息形式传递，必须用 bus handler 接收，否则失败时无日志、不重连。
    GstBus *bus = gst_element_get_bus(pipeline_);
    if (bus) {
        gst_bus_set_sync_handler(bus, &RtspStream::onBusSync, this, nullptr);
        gst_object_unref(bus);
    }

    const GstStateChangeReturn ret = gst_element_set_state(pipeline_, GST_STATE_PLAYING);
    if (ret == GST_STATE_CHANGE_FAILURE) {
        qWarning() << "[RtspStream] 启动失败:" << url_;
        teardown();
        busy_ = false;
        emit busyChanged();
        setOnline(false);
        setStarted(false);
        scheduleReconnect();
        return;
    }

    setStarted(true);
    startUs_.store(gst_util_get_timestamp() / 1000);
    busy_ = false;
    emit busyChanged();
    reconnectAttempt_ = 0;
    lastSampleUs_.store(0);
}

void RtspStream::stop()
{
    reconnect_->stop();
    teardown();
    setOnline(false);
    setStarted(false);
}

void RtspStream::reconnect()
{
    stop();
    start();
}

void RtspStream::teardown()
{
    if (pipeline_) {
        // 先解除 bus 同步 handler，避免销毁期间消息回调打到半死的对象上
        GstBus *bus = gst_element_get_bus(pipeline_);
        if (bus) {
            gst_bus_set_sync_handler(bus, nullptr, nullptr, nullptr);
            gst_object_unref(bus);
        }
        gst_element_set_state(pipeline_, GST_STATE_NULL);
        gst_object_unref(pipeline_);   // 释放全部子元素（含 appsink）
        pipeline_ = nullptr;
    }
    sink_ = nullptr;   // 元素所有权在 pipeline，随管道释放
    QMutexLocker lock(&mutex_);
    lastFrame_ = QImage();
}

void RtspStream::setOnline(bool on)
{
    if (online_.load() == on) return;
    online_.store(on);
    emit onlineChanged();
}

void RtspStream::scheduleReconnect()
{
    setOnline(false);
    setStarted(false);
    if (url_.isEmpty()) return;
    reconnect_->stop();
    // 指数退避：2s 起步、上限 10s。重连次数封顶到 4 再移位，
    // 避免 reconnectAttempt_ 无限递增导致 1 << n 对 int 溢出（UB）。
    const int attempt = qMin(reconnectAttempt_, 4);
    reconnect_->setInterval(qBound(2000, 2000 * (1 << attempt), 10000));
    reconnectAttempt_++;
    reconnect_->start();
}

// 动态 pad 链接：rtspsrc/decodebin 的 src pad 运行时出现，仅链接视频 pad。
// 注意 caps 判断要区分两种来源：
// - rtspsrc 的 pad caps 为 application/x-rtp，媒体类型在 "media" 字段（"video"/"audio"）
// - decodebin 的 pad caps 为解码后的实际类型（video/x-raw 等），结构名即 video/ 前缀
void RtspStream::onPadAdded(GstElement *, GstPad *newPad, gpointer user_data)
{
    auto *next = static_cast<GstElement *>(user_data);

    GstCaps *caps = gst_pad_get_current_caps(newPad);
    if (!caps)
        caps = gst_pad_query_caps(newPad, nullptr);
    bool isVideo = false;
    if (caps) {
        const GstStructure *s = gst_caps_get_structure(caps, 0);
        if (s) {
            const gchar *name = gst_structure_get_name(s);
            if (g_str_has_prefix(name, "application/x-rtp")) {
                const gchar *media = gst_structure_get_string(s, "media");
                isVideo = (media && g_strcmp0(media, "video") == 0);
            } else {
                isVideo = g_str_has_prefix(name, "video/");
            }
        }
        gst_caps_unref(caps);
    }
    if (!isVideo)
        return;

    GstPad *sinkPad = gst_element_get_static_pad(next, "sink");
    if (!sinkPad)
        return;
    if (gst_pad_is_linked(sinkPad)) {
        gst_object_unref(sinkPad);
        return;
    }
    if (GST_PAD_LINK_FAILED(gst_pad_link(newPad, sinkPad)))
        qWarning() << "[RtspStream] 动态 pad 链接失败";
    gst_object_unref(sinkPad);
}

GstFlowReturn RtspStream::onNewSample(GstAppSink *sink, gpointer user_data)
{
    auto *self = static_cast<RtspStream *>(user_data);
    self->onSample(sink);
    return GST_FLOW_OK;
}

void RtspStream::onSample(GstAppSink *sink)
{
    GstSample *sample = gst_app_sink_pull_sample(GST_APP_SINK(sink));
    if (!sample)
        return;

    GstCaps *caps = gst_sample_get_caps(sample);
    GstBuffer *buf = gst_sample_get_buffer(sample);
    GstVideoInfo info;
    if (caps && buf && gst_video_info_from_caps(&info, caps)) {
        GstVideoFrame frame;
        if (gst_video_frame_map(&frame, &info, buf, GST_MAP_READ)) {
            QImage img(reinterpret_cast<const uchar *>(GST_VIDEO_FRAME_PLANE_DATA(&frame, 0)),
                       info.width, info.height,
                       GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0),
                       QImage::Format_RGBA8888);
            {
                QMutexLocker lock(&mutex_);
                lastFrame_ = img.copy();
            }
            lastSampleUs_.store(gst_util_get_timestamp() / 1000);
            gst_video_frame_unmap(&frame);
            if (!online_.load())
                setOnline(true);
            // 在 GST 线程发信号，QML Connections 默认 AutoConnection 会排队到 GUI 线程
            emit frameChanged();
        }
    }
    gst_sample_unref(sample);
}

// 总线同步回调：在 GStreamer streaming 线程执行，仅做日志与排队投递，
// QTimer 等必须在对象所属线程（Qt 主线程）操作，故用 QueuedConnection 切回去
GstBusSyncReply RtspStream::onBusSync(GstBus *, GstMessage *msg, gpointer user_data)
{
    auto *self = static_cast<RtspStream *>(user_data);
    if (!self || !msg)
        return GST_BUS_PASS;
    switch (GST_MESSAGE_TYPE(msg)) {
    case GST_MESSAGE_ERROR: {
        GError *err = nullptr;
        gchar *dbg = nullptr;
        gst_message_parse_error(msg, &err, &dbg);
        qWarning() << "[RtspStream] 管道错误:" << (err ? err->message : "unknown")
                   << "|" << (dbg ? dbg : "");
        if (err)
            g_error_free(err);
        if (dbg)
            g_free(dbg);
        QMetaObject::invokeMethod(self, [self]() { self->scheduleReconnect(); },
                                  Qt::QueuedConnection);
        break;
    }
    case GST_MESSAGE_EOS:
        qWarning() << "[RtspStream] 流结束(EOS)";
        QMetaObject::invokeMethod(self, [self]() { self->scheduleReconnect(); },
                                  Qt::QueuedConnection);
        break;
    default:
        break;
    }
    return GST_BUS_PASS;
}

} // namespace lgs

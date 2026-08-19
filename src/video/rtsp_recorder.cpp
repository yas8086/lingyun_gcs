#include "video/rtsp_recorder.h"

#include <QDebug>
#include <QFileInfo>

namespace lgs {

RtspRecorder::RtspRecorder(QObject *parent)
    : QObject(parent)
{
    // 收尾轮询：50ms 一拍，非阻塞检查 bus 上的 EOS/ERROR 消息
    finalizeTimer_ = new QTimer(this);
    finalizeTimer_->setInterval(50);
    connect(finalizeTimer_, &QTimer::timeout, this, &RtspRecorder::pollFinalize);
}

RtspRecorder::~RtspRecorder()
{
    // 析构时若有未完成的收尾（pendingBus_/pipeline_ 仍在），同步完成释放，
    // 避免 timer 随父对象销毁而停止后遗留 GStreamer 资源。
    if (finalizeTimer_->isActive())
        finalizeTimer_->stop();
    finishFinalize();
}

bool RtspRecorder::start(const QString &url, const QString &filePath)
{
    // 若上一次 stop 的收尾尚未完成（异步进行中），此处先同步完成释放，
    // 否则下方 pipeline_ 重新赋值会覆盖旧指针导致 GStreamer 资源泄漏。
    if (finalizing_)
        finishFinalize();
    stop();
    if (url.isEmpty() || filePath.isEmpty())
        return false;
    fileName_ = QFileInfo(filePath).fileName();

    // 程序化构建（与 RtspStream 同思路）：g_object_set 直接设置 location，
    // 避免 gst_parse_launch 对 URL 的字符串解析陷阱。
    pipeline_ = gst_pipeline_new("recpipe");
    GstElement *src = gst_element_factory_make("rtspsrc", "rsrc");
    GstElement *parse = gst_element_factory_make("parsebin", "rparse");
    GstElement *mux = gst_element_factory_make("matroskamux", "rmux");
    GstElement *sink = gst_element_factory_make("filesink", "rfsink");
    if (!pipeline_ || !src || !parse || !mux || !sink) {
        qWarning() << "[RtspRecorder] 元素创建失败（缺少 GStreamer 插件？）";
        if (pipeline_) { gst_object_unref(pipeline_); pipeline_ = nullptr; }
        if (src) gst_object_unref(src);
        if (parse) gst_object_unref(parse);
        if (mux) gst_object_unref(mux);
        if (sink) gst_object_unref(sink);
        return false;
    }

    // protocols: 4 == GST_RTSP_LOWER_TRANS_TCP（仅 RTSP over TCP interleaved）
    g_object_set(src,
                 "location", url.toUtf8().constData(),
                 "protocols", static_cast<guint>(4),
                 "latency", static_cast<guint>(200),
                 nullptr);
    g_object_set(sink, "location", filePath.toUtf8().constData(), nullptr);

    gst_bin_add_many(GST_BIN(pipeline_), src, parse, mux, sink, nullptr);
    // matroskamux src pad 为 always，可与 filesink 静态链接
    if (!gst_element_link(mux, sink)) {
        qWarning() << "[RtspRecorder] 静态链接失败（matroskamux→filesink）";
        gst_object_unref(pipeline_);   // bin 销毁时释放全部子元素
        pipeline_ = nullptr;
        return false;
    }

    // 动态 pad：rtspsrc→parsebin（pad 直接链 parsebin 静态 sink pad），
    // parsebin→mux（向 mux 请求 video_%u pad）
    g_signal_connect(src, "pad-added", G_CALLBACK(RtspRecorder::onPadAdded), parse);
    g_signal_connect(parse, "pad-added", G_CALLBACK(RtspRecorder::onPadAdded), mux);

    GstBus *bus = gst_element_get_bus(pipeline_);
    if (bus) {
        gst_bus_set_sync_handler(bus, &RtspRecorder::onBusSync, this, nullptr);
        gst_object_unref(bus);
    }

    if (gst_element_set_state(pipeline_, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        qWarning() << "[RtspRecorder] 启动失败:" << url;
        // 先摘 bus handler 再销毁
        GstBus *b = gst_element_get_bus(pipeline_);
        if (b) { gst_bus_set_sync_handler(b, nullptr, nullptr, nullptr); gst_object_unref(b); }
        gst_element_set_state(pipeline_, GST_STATE_NULL);
        gst_object_unref(pipeline_);
        pipeline_ = nullptr;
        return false;
    }
    qInfo() << "[RtspRecorder] 录制中:" << filePath;
    return true;
}

void RtspRecorder::stop()
{
    if (!pipeline_)
        return;
    // 摘除 bus handler，避免销毁期间消息回调打到半死的对象上
    GstBus *bus = gst_element_get_bus(pipeline_);
    if (bus)
        gst_bus_set_sync_handler(bus, nullptr, nullptr, nullptr);

    // 发 EOS：matroskamux 收到 EOS 才写文件尾与索引（否则文件不可拖动甚至不可播）
    gst_element_send_event(pipeline_, gst_event_new_eos());

    if (bus) {
        // 异步收尾：保存 bus 引用交给 pollFinalize 轮询，EOS/ERROR 或超时后释放。
        // 原实现 gst_bus_timed_pop_filtered(3s) 会同步阻塞 GUI 线程最多 3 秒。
        if (finalizing_ && pendingBus_) {
            // 上一次 stop 的收尾尚未完成：丢弃旧 bus，本次优先处理新 EOS
            gst_object_unref(pendingBus_);
        }
        pendingBus_ = bus;
        finalizing_ = true;
        finalizeStartUs_ = gst_util_get_timestamp() / 1000;
        finalizeTimer_->start();
    } else {
        // 无 bus：直接释放
        finishFinalize();
    }
}

void RtspRecorder::pollFinalize()
{
    if (!pendingBus_ || !pipeline_)
    {
        finishFinalize();
        return;
    }
    // 非阻塞取 EOS/ERROR 消息（timeout=0 立即返回）；matroskamux 写完索引后
    // 管道自然走到 EOS，此处仅等待该消息落总线。
    GstMessage *msg = gst_bus_timed_pop_filtered(
        pendingBus_, 0,
        static_cast<GstMessageType>(GST_MESSAGE_EOS | GST_MESSAGE_ERROR));
    const bool got = (msg != nullptr);
    if (msg)
        gst_message_unref(msg);
    const bool timeout = (gst_util_get_timestamp() / 1000 - finalizeStartUs_) > 3000000;
    if (got || timeout)
        finishFinalize();
}

void RtspRecorder::finishFinalize()
{
    finalizeTimer_->stop();
    if (pendingBus_) {
        gst_object_unref(pendingBus_);
        pendingBus_ = nullptr;
    }
    if (pipeline_) {
        gst_element_set_state(pipeline_, GST_STATE_NULL);
        gst_object_unref(pipeline_);
        pipeline_ = nullptr;
    }
    finalizing_ = false;
    qInfo() << "[RtspRecorder] 录制已停止，文件已收尾:" << fileName_;
}

void RtspRecorder::onPadAdded(GstElement *, GstPad *newPad, gpointer user_data)
{
    auto *next = static_cast<GstElement *>(user_data);

    // 视频判定（与 RtspStream 一致）：rtp caps 看 media 字段，编码 caps 看 video/ 前缀
    GstCaps *caps = gst_pad_get_current_caps(newPad);
    if (!caps)
        caps = gst_pad_query_caps(newPad, nullptr);
    if (!caps)
        return;
    bool isVideo = false;
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
    if (!isVideo)
        return;

    // parsebin 的 sink 是静态 pad；matroskamux 需请求 video_%u pad（返回引用归 mux 所有，无需 unref）
    GstPad *sinkPad = gst_element_get_static_pad(next, "sink");
    bool borrowed = false;
    if (!sinkPad) {
        sinkPad = gst_element_request_pad_simple(next, "video_%u");
        borrowed = true;
    }
    if (!sinkPad)
        return;
    if (gst_pad_is_linked(sinkPad)) {
        if (!borrowed)
            gst_object_unref(sinkPad);
        return;
    }
    if (GST_PAD_LINK_FAILED(gst_pad_link(newPad, sinkPad)))
        qWarning() << "[RtspRecorder] 动态 pad 链接失败";
    if (!borrowed)
        gst_object_unref(sinkPad);
}

GstBusSyncReply RtspRecorder::onBusSync(GstBus *, GstMessage *msg, gpointer)
{
    if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
        GError *err = nullptr;
        gchar *dbg = nullptr;
        gst_message_parse_error(msg, &err, &dbg);
        qWarning() << "[RtspRecorder] 管道错误:" << (err ? err->message : "unknown")
                   << "|" << (dbg ? dbg : "");
        if (err)
            g_error_free(err);
        if (dbg)
            g_free(dbg);
    }
    return GST_BUS_PASS;
}

} // namespace lgs

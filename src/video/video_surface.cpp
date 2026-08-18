#include "video/video_surface.h"
#include "video/rtsp_stream.h"

#include <QPainter>

namespace lgs {

VideoSurface::VideoSurface(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    // 默认 RenderTarget = Image（FBO 纹理），fillColor 透明
    setAntialiasing(false);
}

RtspStream *VideoSurface::stream() const { return stream_; }

void VideoSurface::setStream(RtspStream *s)
{
    if (stream_ == s)
        return;
    if (stream_)
        disconnect(stream_, nullptr, this, nullptr);
    stream_ = s;
    if (stream_) {
        // 帧到达（GST 线程 emit）→ Queued 到 GUI 线程 → 调度重绘
        connect(stream_, &RtspStream::frameChanged, this,
                [this]() { update(); }, Qt::QueuedConnection);
    }
    emit streamChanged();
    update();
}

void VideoSurface::paint(QPainter *painter)
{
    if (!stream_ || !painter)
        return;
    const QImage img = stream_->lastFrame();
    if (img.isNull())
        return;
    // 保持画面比例居中（类似 CSS object-fit: contain）
    const QRectF r = boundingRect();
    if (r.width() <= 0 || r.height() <= 0)
        return;
    const qreal scale = qMin(r.width() / img.width(), r.height() / img.height());
    const qreal w = img.width() * scale;
    const qreal h = img.height() * scale;
    const QRectF target(r.x() + (r.width() - w) / 2, r.y() + (r.height() - h) / 2, w, h);
    painter->drawImage(target, img);
}

} // namespace lgs

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

bool VideoSurface::flip180() const { return flip180_; }

void VideoSurface::setFlip180(bool f)
{
    if (flip180_ == f)
        return;
    flip180_ = f;
    emit flip180Changed();
    update();
}

void VideoSurface::paint(QPainter *painter)
{
    if (!stream_ || !painter)
        return;
    const QImage img = stream_->lastFrame();
    if (img.isNull())
        return;
    // 防御性：极端情况下上游可能产生 0 尺寸 QImage，避免除零
    if (img.width() <= 0 || img.height() <= 0)
        return;
    // 保持画面比例居中（类似 CSS object-fit: contain）
    const QRectF r = boundingRect();
    if (r.width() <= 0 || r.height() <= 0)
        return;
    const qreal scale = qMin(r.width() / img.width(), r.height() / img.height());
    const qreal w = img.width() * scale;
    const qreal h = img.height() * scale;
    QRectF target(r.x() + (r.width() - w) / 2, r.y() + (r.height() - h) / 2, w, h);
    // 画面旋转 180°（倒装相机，如思翼 FPV A）：绕视口中心旋转后矩形不变，
    // OSD 等 QML 叠加层在 surface 之上不受影响
    if (flip180_) {
        painter->save();
        painter->translate(r.center());
        painter->rotate(180);
        painter->translate(-r.center());
    }
    painter->drawImage(target, img);
    if (flip180_)
        painter->restore();
}

} // namespace lgs

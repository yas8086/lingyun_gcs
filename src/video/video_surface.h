#pragma once

#include <QQuickPaintedItem>

namespace lgs {

class RtspStream;

// 视频上屏面（B 方案）：QQuickPaintedItem + QPainter 绘制 QImage，
// 纹理上传与渲染线程同步全部由 Qt 内部处理。
// 曾尝试自定义 QSGSimpleTextureNode 方案，在 setTexture 处稳定段错误
// （场景图内部状态竞态），回归 QQuickPaintedItem 稳定优先。
class VideoSurface : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(RtspStream *stream READ stream WRITE setStream NOTIFY streamChanged)
    QML_ELEMENT
public:
    explicit VideoSurface(QQuickItem *parent = nullptr);

    RtspStream *stream() const;
    void setStream(RtspStream *s);

    void paint(QPainter *painter) override;

signals:
    void streamChanged();

private:
    RtspStream *stream_ = nullptr;
};

} // namespace lgs

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
    Q_PROPERTY(bool flip180 READ flip180 WRITE setFlip180 NOTIFY flip180Changed)
    QML_ELEMENT
public:
    explicit VideoSurface(QQuickItem *parent = nullptr);

    RtspStream *stream() const;
    void setStream(RtspStream *s);

    bool flip180() const;
    void setFlip180(bool f);

    void paint(QPainter *painter) override;

signals:
    void streamChanged();
    void flip180Changed();

private:
    RtspStream *stream_ = nullptr;
    bool flip180_ = false;
};

} // namespace lgs

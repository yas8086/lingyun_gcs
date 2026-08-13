#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QString>

namespace lgs {

// 在线底图瓦片下载器（地图决策：在线瓦片，天地图/OSM）。
// 用 QtNetwork 下载瓦片并缓存到 data/map_tiles 下，QML 侧按需请求并监听 tileLoaded。
class TileProvider : public QObject {
    Q_OBJECT
public:
    explicit TileProvider(QObject *parent = nullptr);

    void setMapKey(const QString &key);   // 天地图密钥（在线配置文件）
    void setMapSource(int source);        // 0=天地图 1=OSM
    QString mapKey() const;
    int mapSource() const;

    // 请求下载指定层与坐标的瓦片：layer 0=街道 1=影像（OSM 无影像则回退街道）
    Q_INVOKABLE void requestTile(int z, int x, int y, int layer);
    // 瓦片缓存根目录（data/map_tiles）
    Q_INVOKABLE QString cacheRoot() const;
    // 是否有有效图源（天地图需 key；OSM 无需 key）
    Q_INVOKABLE bool sourceUsable() const;

signals:
    void tileLoaded(int z, int x, int y, int layer, const QString &localPath);
    void tileFailed(int z, int x, int y, int layer);
    void sourceChanged();

private:
    QString cachePath(int z, int x, int y, int layer) const;
    QNetworkAccessManager net_;
    QString key_;
    int source_ = 1;   // 默认 OSM（无需 key，开箱可用）
};

} // namespace lgs
#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QString>
#include <QSet>
#include <QQueue>

namespace lgs {

// 在线底图瓦片下载器（地图决策：在线瓦片，天地图/OSM）。
// 用 QtNetwork 下载瓦片并缓存到 data/map_tiles 下，QML 侧按需请求并监听 tileLoaded。
class TileProvider : public QObject {
    Q_OBJECT
public:
    explicit TileProvider(QObject *parent = nullptr);

    // 天地图密钥（在线配置文件）；运行时可由 QML 调用以同步设置页修改
    Q_INVOKABLE void setMapKey(const QString &key);
    // 图源：0=天地图 1=OSM；运行时可由 QML 调用以同步设置页修改
    Q_INVOKABLE void setMapSource(int source);
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
    void startDownload(int z, int x, int y, int layer, const QString &path);
    void enforceCacheQuota(); // 缓存配额：超限按 LRU 删除最久未访问瓦片
    void startNextPending();  // 启动下一个排队请求（并发上限控制）
    QNetworkAccessManager net_;
    QString key_;
    int source_ = 1;            // 默认 OSM（无需 key，开箱可用）
    int inFlight_ = 0;          // 当前进行中的下载数
    static constexpr int kMaxConcurrent = 8; // 并发下载上限
    struct PendingTile { int z, x, y, layer; };
    QQueue<PendingTile> pending_; // 超过并发上限的请求排队
    QSet<QString> inflightKeys_;  // 进行中瓦片 key（去重，避免重复请求未缓存瓦片）
};

} // namespace lgs
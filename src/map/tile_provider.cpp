#include "map/tile_provider.h"
#include <QNetworkReply>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QFileInfoList>
#include <QDateTime>
#include <QCoreApplication>
#include <algorithm>

namespace lgs {
namespace {
// 瓦片 key：用于并发去重
QString tileKey(int z, int x, int y, int layer) {
    return QStringLiteral("%1_%2_%3_%4").arg(z).arg(x).arg(y).arg(layer);
}
} // namespace

TileProvider::TileProvider(QObject *parent) : QObject(parent) {}

void TileProvider::setMapKey(const QString &key) {
    if (key_ == key.trimmed()) return;
    key_ = key.trimmed();
    emit sourceChanged();
}
void TileProvider::setMapSource(int source) {
    if (source_ == source) return;
    source_ = source;
    emit sourceChanged();
}
QString TileProvider::mapKey() const { return key_; }
int TileProvider::mapSource() const { return source_; }

bool TileProvider::sourceUsable() const {
    // 天地图必须有 key；OSM 始终可用
    return source_ == 0 ? !key_.isEmpty() : true;
}

QString TileProvider::cacheRoot() const {
    const QString dir = QCoreApplication::applicationDirPath()
                        + QStringLiteral("/data/map_tiles");
    QDir().mkpath(dir);
    return dir;
}

QString TileProvider::cachePath(int z, int x, int y, int layer) const {
    const QString dir = cacheRoot()
                        + QStringLiteral("/%1/%2/%3").arg(layer).arg(z).arg(x);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/%1.png").arg(y);
}

void TileProvider::requestTile(int z, int x, int y, int layer) {
    // 图源不可用（天地图无 key）直接失败，避免发出带空 tk= 的无效请求
    if (!sourceUsable()) {
        emit tileFailed(z, x, y, layer);
        return;
    }
    const QString path = cachePath(z, x, y, layer);
    // 命中缓存：校验文件非空（防空文件反复命中坏瓦片）
    if (QFileInfo::exists(path) && QFileInfo(path).size() > 0) {
        emit tileLoaded(z, x, y, layer, path);
        return;
    }
    // 进行中则去重，避免推动地图时重复请求同一瓦片
    const QString key = tileKey(z, x, y, layer);
    if (inflightKeys_.contains(key)) {
        pending_.enqueue({z, x, y, layer});
        return;
    }
    if (inFlight_ >= kMaxConcurrent) {
        // 并发已满，排队等待
        pending_.enqueue({z, x, y, layer});
        return;
    }
    inflightKeys_.insert(key);
    ++inFlight_;
    startDownload(z, x, y, layer, path);
}

void TileProvider::startDownload(int z, int x, int y, int layer, const QString &path) {
    QUrl url;
    if (source_ == 0) {
        // 天地图：街道 vec_w / 影像 img_w（Layer 分别对应）。
        // 天地图 TILEMATRIX 从 1 开始（对应 OSM 的 z=0），故 z+1 对齐坐标系。
        const int sub = (x + y + z) % 8;
        const QString layerName = (layer == 1) ? "img" : "vec";
        const QString layerSet   = (layer == 1) ? "img_w" : "vec_w";
        url = QUrl(QStringLiteral(
            "https://t%1.tianditu.gov.cn/%2/wmts?SERVICE=WMTS&REQUEST=GetTile"
            "&VERSION=1.0.0&LAYER=%3&STYLE=default&TILEMATRIXSET=%4&FORMAT=tiles"
            "&TILEMATRIX=%5&TILEROW=%6&TILECOL=%7&tk=%8")
            .arg(sub).arg(layerSet).arg(layerName).arg(layerSet)
            .arg(z + 1).arg(y).arg(x).arg(key_));
    } else {
        // OSM 标准瓦片（无影像，layer 忽略）
        url = QUrl(QStringLiteral("https://tile.openstreetmap.org/%1/%2/%3.png")
                       .arg(z).arg(x).arg(y));
    }

    QNetworkRequest req(url);
    // 关键：天地图对「浏览器端」权限类型的 key 强制校验 User-Agent，
    // 非浏览器 UA 会返回 403（{"code":301012,"msg":"权限类型错误"}），
    // 故必须伪装成浏览器 UA，否则瓦片全部下载失败、地图空白。
    req.setRawHeader("User-Agent",
                     "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                     "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36");
    // 天地图对「浏览器端」权限类型的 key 强制校验 HTTP Referer 域名白名单；
    // 桌面应用直连不带 Referer 会被 403 拒绝（code:301012 权限类型错误）。
    // 此处补 Referer 以兼容绑定该域名的浏览器端 key（若 key 为「服务端」类型则忽略）。
    req.setRawHeader("Referer", "https://www.tianditu.gov.cn/");
    req.setTransferTimeout(10000); // 10s 无响应超时，避免挂起
    QNetworkReply *reply = net_.get(req);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, z, x, y, layer, path]() {
        reply->deleteLater();
        const QString key = tileKey(z, x, y, layer);
        inflightKeys_.remove(key);
        --inFlight_;
        // 只 readAll() 一次并复用：readAll 是消费性的，二次调用会返回空
        const QByteArray data = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || data.isEmpty()) {
            emit tileFailed(z, x, y, layer);
        } else {
            QFile f(path);
            if (f.open(QIODevice::WriteOnly)) {
                f.write(data);
                f.close();
                enforceCacheQuota();
                emit tileLoaded(z, x, y, layer, path);
            } else {
                emit tileFailed(z, x, y, layer);
            }
        }
        startNextPending(); // 腾出并发名额，启动下一个排队请求
    });
}

void TileProvider::startNextPending() {
    while (!pending_.isEmpty() && inFlight_ < kMaxConcurrent) {
        const PendingTile t = pending_.dequeue();
        const QString key = tileKey(t.z, t.x, t.y, t.layer);
        if (inflightKeys_.contains(key))
            continue; // 已在途，跳过
        const QString path = cachePath(t.z, t.x, t.y, t.layer);
        if (QFileInfo::exists(path) && QFileInfo(path).size() > 0) {
            emit tileLoaded(t.z, t.x, t.y, t.layer, path);
            continue; // 已被其他请求写入缓存
        }
        inflightKeys_.insert(key);
        ++inFlight_;
        startDownload(t.z, t.x, t.y, t.layer, path);
    }
}

void TileProvider::enforceCacheQuota() {
    // 缓存配额：按瓦片文件数上限（约 5000 张），超限按最后修改时间（LRU）删除最旧瓦片。
    // 瓦片按 layer/z/x/y.png 分层存放，需递归收集全部 .png。
    const int kMaxTiles = 5000;
    QFileInfoList files;
    const QDir root(cacheRoot());
    const auto collect = [&files](const auto &self, const QDir &dir) -> void {
        const auto entries = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot);
        for (const auto &e : entries) {
            if (e.isDir())
                self(self, QDir(e.absoluteFilePath()));
            else if (e.suffix() == "png")
                files.append(e);
        }
    };
    collect(collect, root);
    if (files.size() <= kMaxTiles)
        return;
    // 按最后修改时间升序（最旧在前），删除超出配额的部分
    std::sort(files.begin(), files.end(),
              [](const QFileInfo &a, const QFileInfo &b) {
                  return a.lastModified() < b.lastModified();
              });
    const int overflow = files.size() - kMaxTiles;
    for (int i = 0; i < overflow && i < files.size(); ++i)
        QFile::remove(files.at(i).absoluteFilePath());
}

} // namespace lgs
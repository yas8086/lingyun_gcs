#include "map/tile_provider.h"
#include <QNetworkReply>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QCoreApplication>

namespace lgs {

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
    const QString path = cachePath(z, x, y, layer);
    if (QFileInfo::exists(path)) {
        emit tileLoaded(z, x, y, layer, path);
        return;
    }

    QUrl url;
    if (source_ == 0) {
        // 天地图：街道 vec_w / 影像 img_w（Layer 分别对应）
        const int sub = (x + y + z) % 8;
        const QString layerName = (layer == 1) ? "img" : "vec";
        const QString layerSet   = (layer == 1) ? "img_w" : "vec_w";
        url = QUrl(QStringLiteral(
            "https://t%1.tianditu.gov.cn/%2/wmts?SERVICE=WMTS&REQUEST=GetTile"
            "&VERSION=1.0.0&LAYER=%3&STYLE=default&TILEMATRIXSET=%4&FORMAT=tiles"
            "&TILEMATRIX=%5&TILEROW=%6&TILECOL=%7&tk=%8")
            .arg(sub).arg(layerSet).arg(layerName).arg(layerSet)
            .arg(z).arg(y).arg(x).arg(key_));
    } else {
        // OSM 标准瓦片（无影像，layer 忽略）
        url = QUrl(QStringLiteral("https://tile.openstreetmap.org/%1/%2/%3.png")
                       .arg(z).arg(x).arg(y));
    }

    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "LingYunGroundStation/1.0");
    QNetworkReply *reply = net_.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, z, x, y, layer, path]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            emit tileFailed(z, x, y, layer);
            return;
        }
        const QByteArray data = reply->readAll();
        if (data.isEmpty()) {
            emit tileFailed(z, x, y, layer);
            return;
        }
        QFile f(path);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(data);
            f.close();
            emit tileLoaded(z, x, y, layer, path);
        } else {
            emit tileFailed(z, x, y, layer);
        }
    });
}

} // namespace lgs
#pragma once
#include <QString>
#include <QByteArray>

namespace lgs {

// 用 QSettings 持久化串口与界面设置
class ConfigManager {
public:
    ConfigManager();

    QString port() const;
    qint32 baud() const;
    void setPort(const QString &p);
    void setBaud(qint32 b);

    void saveWindowGeometry(const QByteArray &geo);
    QByteArray windowGeometry() const;

private:
    QString org_ = "LingYun";
    QString app_ = "GroundStation";
};

} // namespace lgs

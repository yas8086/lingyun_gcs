#include "core/config_manager.h"
#include <QSettings>
#include <QCoreApplication>

namespace lgs {

ConfigManager::ConfigManager() {
    QCoreApplication::setOrganizationName(org_);
    QCoreApplication::setApplicationName(app_);
}

QString ConfigManager::port() const {
    QSettings s;
    return s.value("serial/port", QString()).toString();
}

qint32 ConfigManager::baud() const {
    QSettings s;
    return s.value("serial/baud", 115200).toInt();
}

void ConfigManager::setPort(const QString &p) {
    QSettings s;
    s.setValue("serial/port", p);
}

void ConfigManager::setBaud(qint32 b) {
    QSettings s;
    s.setValue("serial/baud", b);
}

void ConfigManager::saveWindowGeometry(const QByteArray &geo) {
    QSettings s;
    s.setValue("window/geometry", geo);
}

QByteArray ConfigManager::windowGeometry() const {
    QSettings s;
    return s.value("window/geometry").toByteArray();
}

} // namespace lgs

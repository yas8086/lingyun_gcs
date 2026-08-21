#include <QtTest>
#include <QSignalSpy>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include "core/data_bus.h"
#include "core/alarm_engine.h"
#include "map/tile_provider.h"
#include "comms/serial_manager.h"

using namespace lgs;

// 核心辅助模块单测（C2）：数据总线发布、瓦片缓存命中/图源可用性/缓存路径、串口失败路径。
// 全部无头可运行（QCoreApplication），不依赖真实串口/网络。

class TestCoreAux : public QObject {
    Q_OBJECT
private slots:
    void initTestCase() {
        qRegisterMetaType<lgs::TelemetryData>("lgs::TelemetryData");
    }
    void cleanupTestCase() {}

    // ---- DataBus ----
    void dataBusPublishes();

    // ---- TileProvider ----
    void tileSourceUsable();
    void tileCachePathStructure();
    void tileCacheHitEmitsLoaded();
    void tileUnusableSourceFails();

    // ---- SerialManager ----
    void serialOpenMissingPortFails();
    void serialEnumeratesPorts();
};

void TestCoreAux::dataBusPublishes() {
    DataBus bus;
    QSignalSpy spy(&bus, &DataBus::telemetryReady);
    TelemetryData d;
    d.t = 12.5;
    bus.publish(d);
    QCOMPARE(spy.count(), 1);
    const TelemetryData got = qvariant_cast<TelemetryData>(spy.at(0).at(0));
    QCOMPARE(got.t, 12.5);
}

void TestCoreAux::tileSourceUsable() {
    TileProvider tp;
    tp.setMapSource(0);                       // 天地图
    QVERIFY(!tp.sourceUsable());              // 无 key 不可用
    tp.setMapKey(QStringLiteral("test-key"));
    QVERIFY(tp.sourceUsable());
    tp.setMapSource(1);                       // OSM 始终可用
    QVERIFY(tp.sourceUsable());
}

void TestCoreAux::tileCachePathStructure() {
    TileProvider tp;
    tp.setMapSource(0);
    // cacheRoot 为公开接口：返回应用目录下 data/map_tiles 并确保目录可创建
    const QString root = tp.cacheRoot();
    QDir().mkpath(root);
    QVERIFY(QDir(root).exists());
}

void TestCoreAux::tileCacheHitEmitsLoaded() {
    TileProvider tp;
    tp.setMapSource(1);   // OSM
    // 缓存路径 = <cacheRoot>/<source>/<layer>/<z>/<x>/<y>.png（source=1, layer=0, z=1, x=1, y=1）
    const QString path = tp.cacheRoot() + QStringLiteral("/1/0/1/1/1.png");
    QDir().mkpath(QFileInfo(path).absolutePath());
    {
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("fake-png");
        f.close();
    }
    QSignalSpy loaded(&tp, &TileProvider::tileLoaded);
    tp.requestTile(1, 1, 1, 0);
    QCOMPARE(loaded.count(), 1);
    QCOMPARE(loaded.at(0).at(4).toString(), path);
    QFile::remove(path);
}

void TestCoreAux::tileUnusableSourceFails() {
    TileProvider tp;
    tp.setMapSource(0);   // 天地图但无 key
    QSignalSpy failed(&tp, &TileProvider::tileFailed);
    tp.requestTile(1, 1, 1, 0);
    QCOMPARE(failed.count(), 1);   // 不可用图源直接失败，不发出无效请求
}

void TestCoreAux::serialOpenMissingPortFails() {
    SerialManager sm;
    QSignalSpy errSpy(&sm, &SerialManager::errorOccurred);
#ifdef Q_OS_WIN
    const QString bogus = QStringLiteral("COM999");
#else
    const QString bogus = QStringLiteral("/dev/gcs_nonexistent_test_port");
#endif
    QVERIFY(!sm.open(bogus, 115200));
    QVERIFY(!sm.isOpen());
    QVERIFY(errSpy.count() >= 1);   // open 失败会广播 errorOccurred（透出原因）
    sm.close();                      // 幂等清理，不崩
}

void TestCoreAux::serialEnumeratesPorts() {
    SerialManager sm;
    // 至少不崩溃；有串口时返回非空（无设备环境允许为空列表）
    const QStringList ports = sm.availablePorts();
    Q_UNUSED(ports);
    // 链路看门狗超时设置应生效且不崩
    sm.setLinkTimeoutMs(100);   // 低于下限钳制
    sm.setLinkTimeoutMs(5000);
    sm.close();
}

QTEST_MAIN(TestCoreAux)
#include "test_core_aux.moc"

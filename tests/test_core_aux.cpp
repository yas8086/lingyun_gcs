#include <QtTest>
#include <QSignalSpy>
#include <QUdpSocket>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include "core/data_bus.h"
#include "core/alarm_engine.h"
#include "map/tile_provider.h"
#include "comms/serial_manager.h"
#include "comms/udp_link_source.h"

using namespace lgs;

// 核心辅助模块单测（C2）：数据总线发布、瓦片缓存命中/图源可用性、串口失败路径、UDP 网口源回环。
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

    // ---- UdpLinkSource（数传网口 UDP，本地回环）----
    void udpReceivesDemoFrame();
    void udpLifecycleIdempotent();
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

void TestCoreAux::udpReceivesDemoFrame() {
    // 绑一个空端口作为"机载发送端"，向 UdpLinkSource 监听端口发 AA55 JSON\n 帧
    QUdpSocket sender;
    QVERIFY(sender.bind(QHostAddress::LocalHost, 0));

    UdpLinkSource udpSrc;
    QSignalSpy rxSpy(&udpSrc, &UdpLinkSource::telemetryReceived);
    QSignalSpy rawSpy(&udpSrc, &UdpLinkSource::rawFrameReceived);
    QSignalSpy onSpy(&udpSrc, &UdpLinkSource::linkStatusChanged);
    // 系统分配监听端口（start(0)），避免固定端口被占用/复用问题
    QVERIFY(udpSrc.start(0));
    const quint16 port = quint16(udpSrc.port());
    QVERIFY(port != 0);
    qDebug() << "UDP test listening on" << port;

    // 发送一帧（含 bms 与 fc 扩展字段，验证解码覆盖）
    const QByteArray frame = QByteArray("\xaa\x55")
        + "{ \"t\": 100.5,"
          "\"bms\":{\"online\":true,\"pack_v\":367.2,\"soc\":85,\"soh\":95,\"fault1\":2},"
          "\"fc\":{\"online\":true,\"roll\":5.5,\"pitch\":2.0,\"yaw\":90.0,"
          "\"hdg\":120.0,\"gs\":9.8,\"thr\":50.0,"
          "\"gps\":{\"fix\":6,\"sat\":18,\"eph\":50,\"epv\":80},"
          "\"esc\":{\"n\":10,\"rpm\":[3200,3100,3000,2900,2800,2700,2600,2500,2400,2300],"
          "\"v\":[48.1,0,0,0,0,0,0,0,0,0],\"i\":[12.5,0,0,0,0,0,0,0,0,0],\"tmp\":[35,0,0,0,0,0,0,0,0,0]}}"
          "}"
        + QByteArray("\n");
    const qint64 sent = sender.writeDatagram(frame, QHostAddress::LocalHost, port);
    QVERIFY(sent > 0);
    QTRY_VERIFY_WITH_TIMEOUT(rxSpy.count() >= 1, 2000);
    QCOMPARE(rxSpy.count(), 1);
    const TelemetryData d = qvariant_cast<TelemetryData>(rxSpy.at(0).at(0));
    QVERIFY(d.bms.has_value());
    QCOMPARE(d.bms->soh, 95.0);
    QCOMPARE(d.bms->fault1, 2);
    QVERIFY(d.fc.has_value());
    QCOMPARE(d.fc->hdg, 120.0);
    QCOMPARE(d.fc->gs, 9.8);
    QCOMPARE(d.fc->gpsSat, 18);
    QCOMPARE(d.fc->escN, 10);
    QCOMPARE(d.fc->escRpm[0], 3200.0);

    // 收到帧 → 链路应置在线
    QVERIFY(onSpy.count() >= 1);
    QVERIFY(onSpy.last().at(0).toBool());
    // 原始帧（AA55+JSON+\n）也广播
    QVERIFY(rawSpy.count() >= 1);
    udpSrc.stop();
}

void TestCoreAux::udpLifecycleIdempotent() {
    // start → stop → 再 start 幂等，结束 stop 清理，验证生命周期不崩且链路状态正确复位
    UdpLinkSource udpSrc;
    QSignalSpy onSpy(&udpSrc, &UdpLinkSource::linkStatusChanged);

    QVERIFY(udpSrc.start(0));
    QVERIFY(udpSrc.isRunning());
    QVERIFY(udpSrc.port() != 0);
    QVERIFY(onSpy.last().at(0).toBool());   // 启动 → 在线
    udpSrc.stop();
    QVERIFY(!udpSrc.isRunning());
    QVERIFY(!onSpy.last().at(0).toBool());  // 停止 → 离线
    // 再启动（系统重新分配端口）
    QVERIFY(udpSrc.start(0));
    QVERIFY(udpSrc.isRunning());
    QVERIFY(onSpy.last().at(0).toBool());
    udpSrc.stop();
}

QTEST_MAIN(TestCoreAux)
#include "test_core_aux.moc"

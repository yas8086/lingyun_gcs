#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>
#include <QTime>
#include <QThread>
#include <QMetaObject>
#include "comms/serial_manager.h"
#include "core/data_bus.h"
#include "core/alarm_engine.h"
#include "core/config_manager.h"
#include "map/tile_provider.h"
#include "qmlbridge/telemetry_bridge.h"

// QML 版地面站入口：保留 C++ 后端（串口/总线/告警），QML 复刻原型视觉。
// 用 QApplication（而非 QGuiApplication）：QtCharts 内部依赖 QWidgetTextControl。
int main(int argc, char *argv[]) {
    // 必须在 QApplication 构造之前设置：
    // 1. QSG_RENDER_LOOP=basic —— 强制 Qt Quick 在主线程渲染，
    //    避免 Intel Iris Xe + Mesa 驱动下 threaded 渲染线程死锁
    //    （症状：窗口显示创建瞬间屏幕残留像素、拖动窗口内容冻结不更新）。
    // 2. 默认禁用 alpha 缓冲区，确保窗口背景始终不透明。
    qputenv("QSG_RENDER_LOOP", "basic");
    QQuickWindow::setDefaultAlphaBuffer(false);

    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName("LingYun");
    QCoreApplication::setApplicationName("GroundStationQml");

    // 注册自定义元类型，支持跨线程 QueuedConnection
    qRegisterMetaType<lgs::TelemetryData>("lgs::TelemetryData");
    qRegisterMetaType<lgs::AlarmEvent>("lgs::AlarmEvent");

    // 串口 IO 工作线程：SerialManager 整体迁入，避免 QSerialPort 阻塞 GUI 线程
    auto *serialThread = new QThread(&app);
    auto *serial = new lgs::SerialManager();
    serial->moveToThread(serialThread);
    QObject::connect(serialThread, &QThread::finished, serial, &QObject::deleteLater);
    serialThread->start();

    lgs::DataBus bus;
    lgs::AlarmEngine alarm;
    lgs::ConfigManager config;
    lgs::TelemetryBridge bridge;
    lgs::TileProvider tileProvider;
    tileProvider.setMapSource(config.mapSource());
    tileProvider.setMapKey(config.mapKey());

    bridge.setSerialManager(serial);
    bridge.setConfigManager(&config);
    bridge.setAlarmEngine(&alarm);

    // SerialManager 跨线程信号：强制 QueuedConnection
    QObject::connect(serial, &lgs::SerialManager::telemetryReceived,
                     &bus, &lgs::DataBus::publish, Qt::QueuedConnection);
    QObject::connect(&bus, &lgs::DataBus::telemetryReady,
                     &bridge, &lgs::TelemetryBridge::onTelemetry);
    // 告警引擎同一份遥测喂入：评估规则告警 + 维护设备在线时刻（离线告警依赖）
    QObject::connect(&bus, &lgs::DataBus::telemetryReady,
                     &alarm, &lgs::AlarmEngine::onTelemetry);
    QObject::connect(serial, &lgs::SerialManager::linkStatusChanged,
                     &bridge, &lgs::TelemetryBridge::setLinkOnline, Qt::QueuedConnection);
    // 逐帧原始报文 → bridge 自动记录（断电安全落盘）
    QObject::connect(serial, &lgs::SerialManager::rawFrameReceived,
                     &bridge, &lgs::TelemetryBridge::onRawFrame, Qt::QueuedConnection);
    QObject::connect(serial, &lgs::SerialManager::errorOccurred,
                     &bridge, [&bridge](const QString &msg) {
        bridge.addAlarm(msg, "严重", "链路");
    }, Qt::QueuedConnection);
    QObject::connect(&alarm, &lgs::AlarmEngine::alarmTriggered,
                     &bridge, [&bridge](const lgs::AlarmEvent &e) {
        const QString lv = e.level == lgs::AlarmEvent::Critical ? "严重"
                           : e.level == lgs::AlarmEvent::Warn ? "告警" : "提示";
        bridge.addAlarm(e.message, lv, e.source);
    });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty("tileProvider", &tileProvider);
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    // 显式确保根窗口背景色不透明
    if (auto *win = qobject_cast<QQuickWindow*>(engine.rootObjects().first())) {
        win->setColor(QColor("#eef2f7"));
        // 窗口初始为隐藏（QML visible:false），直接以最大化状态显示，避免小窗口闪现。
        win->showMaximized();
        // 等最大化过渡完成后，依据屏幕工作区与装饰框高度推导客户端固定尺寸：
        // X11 下最大化窗口的 size() 返回的是"恢复尺寸"而非当前显示尺寸，须用
        // frameGeometry 与 geometry 的差值（顶栏装饰高度）补偿 availableSize。
        QTimer::singleShot(400, win, [win]() {
            const int topBorder = win->frameGeometry().height() - win->geometry().height();
            QSize fixed = win->screen()->availableSize();
            fixed.setHeight(fixed.height() - topBorder);
            win->setMinimumSize(fixed);
            win->setMaximumSize(fixed);
        });
    }

    const int rc = app.exec();

    // 退出清理：先在串口线程内关闭端口，再退出线程
    bridge.closeSerial();
    serialThread->quit();
    serialThread->wait(2000);

    return rc;
}

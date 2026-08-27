#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QScreen>
#include <QTime>
#include <QThread>
#include <QTimer>
#include <QMetaObject>
#include "comms/serial_manager.h"
#include "comms/udp_link_source.h"
#include "core/data_bus.h"
#include "core/alarm_engine.h"
#include "core/config_manager.h"
#include "map/tile_provider.h"
#include "qmlbridge/telemetry_bridge.h"
#include "video/rtsp_stream.h"
#include "video/video_surface.h"

// QML 版地面站入口：保留 C++ 后端（串口/总线/告警），QML 复刻原型视觉。
// 用 QApplication（而非 QGuiApplication）：QtCharts 内部依赖 QWidgetTextControl。
int main(int argc, char *argv[]) {
    // 必须在 QApplication 构造之前设置：
#ifdef Q_OS_LINUX
    // 1. QSG_RENDER_LOOP=basic —— 强制 Qt Quick 在主线程渲染，
    //    避免 Intel Iris Xe + Mesa 驱动下 threaded 渲染线程死锁
    //    （症状：窗口显示创建瞬间屏幕残留像素、拖动窗口内容冻结不更新）。
    //    Windows 使用默认 threaded 渲染（更流畅），故仅对 Linux 生效。
    qputenv("QSG_RENDER_LOOP", "basic");
#endif
    // 2. 默认禁用 alpha 缓冲区，确保窗口背景始终不透明。
    QQuickWindow::setDefaultAlphaBuffer(false);

    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName("LingYun");
    QCoreApplication::setApplicationName("GroundStationQml");

#ifdef Q_OS_WIN
    // GStreamer 自包含部署：运行库与插件随 exe 打包到同级目录（见 packaging/pack_win.bat），
    // 目标机无需安装 GStreamer。必须在 gst_init 之前设置：
    //  - GST_PLUGIN_PATH：指定自带插件目录（exe 同级 gstreamer-1.0/）；
    //  - GST_PLUGIN_SYSTEM_PATH：隔离系统 GStreamer，避免现场机器版本冲突；
    //  - GST_PLUGIN_SCANNER：指定随包的插件扫描器（首次运行注册插件需要）。
    const QString exeDir = QCoreApplication::applicationDirPath();
    qputenv("GST_PLUGIN_PATH", (exeDir + QStringLiteral("/gstreamer-1.0")).toLocal8Bit());
    qputenv("GST_PLUGIN_SYSTEM_PATH", (exeDir + QStringLiteral("/gstreamer-1.0")).toLocal8Bit());
    qputenv("GST_PLUGIN_SCANNER", (exeDir + QStringLiteral("/gst-plugin-scanner.exe")).toLocal8Bit());
#endif

    // GStreamer 初始化（RTSP 拉流，B 方案）；仅需一次
    gst_init(nullptr, nullptr);

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
    // 数传网口 UDP 数据源（协议 2.1，机载串口+UDP 双发冗余）：按配置启用，走总线统一分发
    lgs::UdpLinkSource udp;

    bridge.setSerialManager(serial);
    bridge.setConfigManager(&config);
    bridge.setAlarmEngine(&alarm);
    bridge.setUdpLinkSource(&udp);

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
    // 数传网口 UDP：与串口同一帧双源，统一接入总线；链路状态同步到 bridge
    QObject::connect(&udp, &lgs::UdpLinkSource::telemetryReceived,
                     &bus, &lgs::DataBus::publish);
    QObject::connect(&udp, &lgs::UdpLinkSource::linkStatusChanged,
                     &bridge, &lgs::TelemetryBridge::onUdpLinkOnline);
    // UDP 原始帧同样进入自动记录（仅 UDP 收数时遥测报文也能落盘）
    QObject::connect(&udp, &lgs::UdpLinkSource::rawFrameReceived,
                     &bridge, &lgs::TelemetryBridge::onRawFrame);
    QObject::connect(serial, &lgs::SerialManager::errorOccurred,
                     &bridge, [&bridge](const QString &msg) {
        bridge.addAlarm(msg, "严重", "链路");
        // B3：ResourceError（拔线等）同步 serialOpen_ 缓存，避免 UI 链路灯失真
        bridge.markSerialGone();
    }, Qt::QueuedConnection);
    QObject::connect(&alarm, &lgs::AlarmEngine::alarmTriggered,
                     &bridge, [&bridge](const lgs::AlarmEvent &e) {
        const QString lv = e.level == lgs::AlarmEvent::Critical ? "严重"
                           : e.level == lgs::AlarmEvent::Warn ? "告警" : "提示";
        // 携带规则 id（AlarmEvent.id）供规则恢复时（alarmCleared）自动标记"已恢复"
        bridge.addAlarm(e.message, lv, e.source, e.id);
    });
    // 规则/设备恢复 → bridge 标记对应告警"已恢复"（未确认计数下降，恢复语义反映到 UI）
    QObject::connect(&alarm, &lgs::AlarmEngine::alarmCleared,
                     &bridge, &lgs::TelemetryBridge::markAlarmRecovered);

    // 依配置启动 UDP 监听（默认开启）。必须在上述对 udp 的所有 connect 建立之后调用——
    // 否则 UdpLinkSource::start() 的首次 linkStatusChanged(true) 会被丢失（信号在连接前发出），
    // 导致 udpOnline_ 恒为 false、isDataLinkOnline() 误判离线（显示"断线"）。
    bridge.applyUdpConfig();

    QQmlApplicationEngine engine;
    // 摄像头 RTSP 视频渲染（B 方案）：注册自定义 QML 类型
    qmlRegisterType<lgs::VideoSurface>("LingYun.Video", 1, 0, "VideoSurface");
    qmlRegisterUncreatableType<lgs::RtspStream>("LingYun.Video", 1, 0, "RtspStream",
        QStringLiteral("RtspStream 通过 bridge.videoStream(camId) 获取"));
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty("tileProvider", &tileProvider);
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    // 显式确保根窗口背景色不透明
    if (auto *win = qobject_cast<QQuickWindow*>(engine.rootObjects().first())) {
        win->setColor(QColor("#eef2f7"));
        // 启动最大化（X11 + GNOME/Mutter 真机定案）：
        // ① 先铺满可用区（QML visible:false 初始无几何，不铺满会在 map 首帧闪现小窗）——
        //    Normal 态窗口几何即全屏，最大化瞬间只有圆角消失，无大小跳变；
        // ② show() 后事件循环启动（窗口完全 mapped）再请求最大化。
        //    真机证据：首帧窗口带圆角=实际是 Normal 大窗而非最大化（用户观察证实），
        //    map 前预置状态 / show 后同步连发状态消息都会被 Mutter 吞掉或错序；
        //    而 mapped 之后经 QTimer(0) 请求最大化，与用户手点标题栏按钮走完全
        //    相同的 _NET_WM_STATE 消息路径，按钮状态必然同步为"还原"。
        win->setGeometry(win->screen()->availableGeometry());
        win->show();
        // 延迟最大化：社区共识（Qt Forum/runebook/CSDN 同问题帖）——0ms 在事件循环
        // 第一拍触发时，X server 的 map/reparent 通知尚未走完、WM（Mutter）还没
        // 注册完窗口，最大化请求会被静默吞掉（表现为 Normal 大窗 + 按钮"最大化"）。
        // 100ms 是多平台验证的稳定延迟；铺满几何保证此间视觉与最大化一致。
        QTimer::singleShot(100, win, [win] { win->setWindowState(Qt::WindowMaximized); });
        // 注意：不再 setMinimumSize/setMaximumSize 锁定尺寸。
        // 固定像素尺寸在换不同分辨率屏幕时会导致显示异常（过大/过小/留边）。
        // 窗口保持最大化状态即可由 WM 自动适配任意分辨率；用户可通过标题栏
        // 最大化/还原按钮或拖拽调整窗口大小，QML 内容在 ScrollView 中可滚动。
    }

    const int rc = app.exec();

    // 退出清理：先用 BlockingQueued 同步关闭串口（确保 close 在 quit 前完成，
    // 避免 Queued 投递的事件因线程退出来不及处理、串口保持打开到进程退出），
    // 再退出串口线程。
    if (serial) {
        QMetaObject::invokeMethod(serial, "close", Qt::BlockingQueuedConnection);
    }
    serialThread->quit();
    serialThread->wait(2000);

    return rc;
}

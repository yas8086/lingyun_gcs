#include "ui/main_window.h"
#include "comms/serial_manager.h"
#include "core/data_bus.h"
#include "core/alarm_engine.h"
#include "core/recorder.h"
#include "core/replay_engine.h"
#include "core/config_manager.h"
#include "ui/status_bar.h"
#include "ui/device_panel.h"
#include "ui/chart_widget.h"
#include "ui/alarm_panel.h"
#include "ui/log_panel.h"
#include "ui/replay_panel.h"
#include "ui/serial_config_dialog.h"

#include <QTabWidget>
#include <QTimer>
#include <QToolBar>
#include <QAction>
#include <QFileDialog>
#include <QTime>
#include <QMessageBox>
#include <QVBoxLayout>

namespace lgs {

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    config_ = new ConfigManager();
    serial_ = new SerialManager(this);
    bus_ = new DataBus(this);
    alarm_ = new AlarmEngine(this);
    recorder_ = new Recorder(this);
    replay_ = new ReplayEngine(this);

    setupUi();
    wire();

    const QByteArray geo = config_->windowGeometry();
    if (!geo.isEmpty())
        restoreGeometry(geo);
}

MainWindow::~MainWindow() {
    config_->saveWindowGeometry(saveGeometry());
    recorder_->stop();
}

void MainWindow::setupUi() {
    setWindowTitle("灵云01号 飞艇地面站");

    auto *toolbar = addToolBar("工具栏");
    toolbar->setMovable(false);
    auto *actSerial = toolbar->addAction("串口配置");
    connect(actSerial, &QAction::triggered, this, &MainWindow::onConfigSerial);
    auto *actRecStart = toolbar->addAction("开始记录");
    connect(actRecStart, &QAction::triggered, this, &MainWindow::onStartRecording);
    auto *actRecStop = toolbar->addAction("停止记录");
    connect(actRecStop, &QAction::triggered, this, &MainWindow::onStopRecording);

    auto *central = new QWidget(this);
    auto *lay = new QVBoxLayout(central);

    statusBar_ = new StatusBar(central);
    devicePanel_ = new DevicePanel(central);
    chart_ = new ChartWidget(central);
    alarmPanel_ = new AlarmPanel(central);
    logPanel_ = new LogPanel(central);
    replayPanel_ = new ReplayPanel(central);

    tabs_ = new QTabWidget(central);
    tabs_->addTab(chart_, "实时曲线");
    tabs_->addTab(alarmPanel_, "告警");
    tabs_->addTab(logPanel_, "日志");
    tabs_->addTab(replayPanel_, "回放");

    lay->addWidget(statusBar_);
    lay->addWidget(devicePanel_);
    lay->addWidget(tabs_, 1);
    setCentralWidget(central);

    clockTimer_ = new QTimer(this);
    clockTimer_->setInterval(1000);
    connect(clockTimer_, &QTimer::timeout, this, &MainWindow::onClockTick);
    clockTimer_->start();
}

void MainWindow::wire() {
    connect(serial_, &SerialManager::telemetryReceived, this, &MainWindow::onTelemetry);
    connect(serial_, &SerialManager::linkStatusChanged, this,
            [this](bool c) { statusBar_->updateLink(c); });
    connect(serial_, &SerialManager::errorOccurred, this,
            [this](const QString &m) { logPanel_->append("链路错误: " + m); });

    connect(bus_, &DataBus::telemetryReady, devicePanel_, &DevicePanel::updateData);
    connect(bus_, &DataBus::telemetryReady, alarm_, &AlarmEngine::onTelemetry);
    connect(bus_, &DataBus::telemetryReady, recorder_, &Recorder::onTelemetry);
    connect(bus_, &DataBus::telemetryReady, chart_, &ChartWidget::onTelemetry);

    connect(alarm_, &AlarmEngine::alarmTriggered, alarmPanel_, &AlarmPanel::onAlarm);
    connect(alarm_, &AlarmEngine::alarmTriggered, this,
            [this](const lgs::AlarmEvent &e) { logPanel_->append("告警: " + e.message); });
    connect(alarm_, &AlarmEngine::alarmCleared, alarmPanel_, &AlarmPanel::onCleared);

    connect(replayPanel_, &ReplayPanel::fileSelected, this, &MainWindow::onReplayFile);
    connect(replayPanel_, &ReplayPanel::startReplay, replay_, &ReplayEngine::start);
    connect(replayPanel_, &ReplayPanel::stopReplay, replay_, &ReplayEngine::stop);
    connect(replayPanel_, &ReplayPanel::speedChanged, replay_, &ReplayEngine::setSpeed);
    connect(replay_, &ReplayEngine::replayed, chart_, &ChartWidget::onTelemetry);
    connect(replay_, &ReplayEngine::replayed, devicePanel_, &DevicePanel::updateData);
}

void MainWindow::onConfigSerial() {
    const auto r = SerialConfigDialog::getResult(
        this, serial_->availablePorts(), config_->port(), config_->baud());
    if (!r.ok)
        return;
    config_->setPort(r.port);
    config_->setBaud(r.baud);
    if (serial_->open(r.port, r.baud)) {
        logPanel_->append(QString("已打开串口 %1 @ %2").arg(r.port).arg(r.baud));
    } else {
        QMessageBox::warning(this, "串口", "打开失败: " + serial_->errorString());
    }
}

void MainWindow::onTelemetry(const lgs::TelemetryData &data) {
    bus_->publish(data);
}

void MainWindow::onAlarm(const lgs::AlarmEvent &e) {
    Q_UNUSED(e);
}

void MainWindow::onAlarmCleared(const QString &id) {
    Q_UNUSED(id);
}

void MainWindow::onClockTick() {
    statusBar_->setClock(QTime::currentTime().toString("HH:mm:ss"));
}

void MainWindow::onStartRecording() {
    if (recorder_->isRecording())
        return;
    const QString path = QFileDialog::getSaveFileName(
        this, "保存记录", Recorder::defaultFileName(), "CSV (*.csv)");
    if (path.isEmpty())
        return;
    if (recorder_->start(path))
        logPanel_->append("开始记录: " + path);
}

void MainWindow::onStopRecording() {
    recorder_->stop();
    logPanel_->append("停止记录");
}

void MainWindow::onReplayFile(const QString &path) {
    if (replay_->load(path))
        logPanel_->append("已加载回放: " + path);
    else
        logPanel_->append("回放文件加载失败: " + path);
}

} // namespace lgs

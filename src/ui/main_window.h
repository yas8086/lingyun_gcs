#pragma once
#include <QMainWindow>
#include "model/telemetry_data.h"
#include "core/alarm_engine.h"

class QTabWidget;
class QTimer;

namespace lgs {

class SerialManager;
class DataBus;
class AlarmEngine;
class Recorder;
class ReplayEngine;
class ConfigManager;
class StatusBar;
class DevicePanel;
class ChartWidget;
class AlarmPanel;
class LogPanel;
class ReplayPanel;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

private slots:
    void onConfigSerial();
    void onTelemetry(const lgs::TelemetryData &data);
    void onClockTick();
    void onStartRecording();
    void onStopRecording();
    void onReplayFile(const QString &path);

private:
    void setupUi();
    void wire();

    SerialManager *serial_ = nullptr;
    DataBus *bus_ = nullptr;
    AlarmEngine *alarm_ = nullptr;
    Recorder *recorder_ = nullptr;
    ReplayEngine *replay_ = nullptr;
    ConfigManager *config_ = nullptr;

    StatusBar *statusBar_ = nullptr;
    DevicePanel *devicePanel_ = nullptr;
    ChartWidget *chart_ = nullptr;
    AlarmPanel *alarmPanel_ = nullptr;
    LogPanel *logPanel_ = nullptr;
    ReplayPanel *replayPanel_ = nullptr;
    QTabWidget *tabs_ = nullptr;
    QTimer *clockTimer_ = nullptr;
};

} // namespace lgs

#pragma once
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>
#include <QList>
#include <QVector>
#include <QHash>
#include <QElapsedTimer>
#include <QTimer>
#include <QFile>
#include <QByteArray>
#include <QDateTime>
#include "model/telemetry_data.h"
#include "core/alarm_engine.h"

namespace lgs {

class SerialManager;
class ConfigManager;
class AlarmEngine;
class RtspStream;
class RtspRecorder;
class SiyiSdkClient;

// 桥接层：把 C++ 后端（遥测/链路/就绪度/告警/串口/配置）暴露给 QML 前端。
// 采用 context 属性注入，QML 通过 Q_INVOKABLE 方法与信号交互。
class TelemetryBridge : public QObject {
    Q_OBJECT
    // 思翼云台（A2 mini UDP SDK）：连接状态与俯仰角（度）实时暴露给 QML
    Q_PROPERTY(bool gimbalConnected READ gimbalConnected NOTIFY gimbalConnectedChanged)
    Q_PROPERTY(double gimbalPitch READ gimbalPitch NOTIFY gimbalAttitudeChanged)
public:
    explicit TelemetryBridge(QObject *parent = nullptr);

    void onTelemetry(const lgs::TelemetryData &data);
    void setLinkOnline(bool online);
    void setSerialManager(SerialManager *serial);
    void setConfigManager(ConfigManager *config);
    void setAlarmEngine(AlarmEngine *engine);

    // 串口控制
    Q_INVOKABLE QStringList ports() const;
    Q_INVOKABLE bool openSerial(const QString &port, int baud);
    Q_INVOKABLE void closeSerial();
    Q_INVOKABLE bool isSerialOpen() const;
    Q_INVOKABLE QString lastSerialError() const;  // 最近一次 openSerial 失败的具体原因
    // 串口配置（用于导入配置后刷新下拉框）
    Q_INVOKABLE QString port() const;
    Q_INVOKABLE int baud() const;

    // 设备在线状态
    Q_INVOKABLE bool online(const QString &device) const;
    // 读取设备字段数值；设备离线或字段不存在返回 NaN
    Q_INVOKABLE double value(const QString &device, const QString &key) const;
    // 就绪度状态：0 待自检 / 1 就绪可飞 / 2 起飞受限 / 3 不可起飞
    Q_INVOKABLE int readinessState() const;
    // LoRa 节点概要（多行文本）
    Q_INVOKABLE QString loraSummary() const;
    // LoRa 节点结构化数据：QVariantList<QVariantMap{id,temp,pressure,alarm,isTemp}>
    Q_INVOKABLE QVariant loraNodes() const;
    // 温度历史导出（决策 #28，落盘 CSV 含 BOM）：返回导出行数，失败返回 -1
    Q_INVOKABLE int exportTempCsv(const QString &path) const;
    // 通用文本写入（实时曲线导出 CSV/快照/报告用）：成功返回 true
    Q_INVOKABLE bool writeTextFile(const QString &path, const QString &content) const;
    // 软件所在目录根目录下的 data 文件夹路径（不存在则创建）
    Q_INVOKABLE QString dataDir() const;
    // 曲线快照目录：data/曲线快照（不存在则创建）
    Q_INVOKABLE QString snapshotDir() const;
    // 摄像头截图/录像目录：data/摄像头/当前日期（按天分文件夹，不存在则创建）
    Q_INVOKABLE QString cameraDir() const;
    // 数据自动记录配置（决策：逐帧原始报文落盘）
    Q_INVOKABLE bool recordEnabled() const;
    Q_INVOKABLE void setRecordEnabled(bool on);
    Q_INVOKABLE QString recordDir() const;
    Q_INVOKABLE void setRecordDir(const QString &dir);
    Q_INVOKABLE bool isRecording() const;           // 当前是否正在写记录文件
    Q_INVOKABLE QString currentRecordFile() const;  // 当前记录文件完整路径（无则空）
    // 记录原始帧（由 SerialManager::rawFrameReceived 触发）
    void onRawFrame(const QByteArray &frame);

    // 配置访问（决策 #24/#29/#30）：偏好经 ConfigManager JSON 持久化
    Q_INVOKABLE int configTempUnit() const;              // 0=℃ 1=℉
    Q_INVOKABLE void setConfigTempUnit(int unit);
    Q_INVOKABLE int configPressureUnit() const;           // 0=kPa 1=Pa 2=bar 3=psi
    Q_INVOKABLE void setConfigPressureUnit(int unit);
    Q_INVOKABLE bool configAlarmSound() const;           // 告警声音开关（默认关）
    Q_INVOKABLE void setConfigAlarmSound(bool on);
    Q_INVOKABLE int configChartWindowSecs() const;       // 10/20/30
    Q_INVOKABLE void setConfigChartWindowSecs(int secs);
    Q_INVOKABLE QVariant configHiddenModules() const;    // 隐藏模块键集合
    Q_INVOKABLE void setConfigHiddenModule(const QString &key, bool hidden);
    // 配置导入导出（决策：跨设备快速配置）：整体 JSON 文件
    Q_INVOKABLE QString configFilePath() const;          // 当前配置文件路径
    Q_INVOKABLE bool exportConfig(const QString &path) const;   // 导出配置到 path
    Q_INVOKABLE bool importConfig(const QString &path);         // 从 path 导入并应用
    // 界面主题（决策：深色/浅色、密度、高对比度、强调色）——纳入重启恢复与导入导出
    Q_INVOKABLE bool configDark() const;
    Q_INVOKABLE void setConfigDark(bool dark);
    Q_INVOKABLE bool configDense() const;
    Q_INVOKABLE void setConfigDense(bool dense);
    Q_INVOKABLE bool configContrast() const;
    Q_INVOKABLE void setConfigContrast(bool contrast);
    Q_INVOKABLE QString configAccent() const;
    Q_INVOKABLE void setConfigAccent(const QString &accent);
    // 地图配置（决策：在线瓦片天地图/OSM）：图源(0天地图 1OSM)与密钥
    Q_INVOKABLE int configMapSource() const;
    Q_INVOKABLE void setConfigMapSource(int source);
    Q_INVOKABLE QString configMapKey() const;
    Q_INVOKABLE void setConfigMapKey(const QString &key);

    // 相机拉流配置（RTSP）：QVariantList<QVariantMap{id,name,enable,ip,port,path,user,pass,stream,transport,fps}>
    Q_INVOKABLE QVariantList cameraConfigs() const;
    Q_INVOKABLE void saveCameraConfigs(const QVariant &list);
    // 摄像头布局档位：1/2/4/a（全部），JSON 持久化
    Q_INVOKABLE QString cameraLay() const;
    Q_INVOKABLE void setCameraLay(const QString &lay);
    // RTSP 视频流（B 方案：GStreamer）：按相机 id 获取（不存在则创建），url 取自相机配置
    Q_INVOKABLE QObject *videoStream(const QString &camId);
    // 摄像头录像：真实录制（rtspsrc→parsebin→matroskamux 零转码存 .mkv，按天归档）
    // 多路并行：按相机 id 各建录制器。返回文件名（空=失败，如相机未配置地址；
    // 该相机已在录则返回当前文件名）；stopCameraRecord 停止全部在录并返回是否有路停止
    Q_INVOKABLE QString startCameraRecord(const QString &camId);
    Q_INVOKABLE bool stopCameraRecord();
    // 思翼云台控制（A2 mini，UDP 37260）：startGimbal(ip) 启动会话并 200ms 轮询姿态；
    // gimbalCtrlMove(yaw,pitch) 组合速度控制 -100~100（A2 mini 仅俯仰轴生效，松手发 0,0）；
    // gimbalCenter 一键回中
    Q_INVOKABLE void startGimbal(const QString &ip);
    Q_INVOKABLE void stopGimbal();
    Q_INVOKABLE void gimbalCtrlMove(int yaw, int pitch);
    Q_INVOKABLE void gimbalCenter();
    bool gimbalConnected() const;
    double gimbalPitch() const;
    // 网络接口状态（网口链路检测）：QVariantList<QVariantMap{name,ip,mac,linkUp,isUp}>
    // linkUp 为物理链路状态（Linux 读 /sys/class/net/*/carrier，即网线是否连接）
    Q_INVOKABLE QVariant netInterfaces() const;

    // 告警列表与确认（决策 #20）
    void addAlarm(const QString &msg, const QString &level, const QString &source);
    Q_INVOKABLE QVariant alarms() const;          // 返回 QVariantList<QVariantMap>
    Q_INVOKABLE void confirmAlarm(int i);
    Q_INVOKABLE void confirmAllAlarms();
    Q_INVOKABLE int unconfirmedCount() const;

    // 告警规则（决策 #15/#31）：经 ConfigManager JSON 持久化并应用到 AlarmEngine
    Q_INVOKABLE QVariant alarmRules() const;              // QVariantList<QVariantMap>
    Q_INVOKABLE QVariant alarmRuleFields() const;         // 可选字段 [device.field, 标签]
    Q_INVOKABLE void addAlarmRule(const QVariant &rule);  // rule: {device,field,op,val,lv,enabled,label}
    Q_INVOKABLE void updateAlarmRule(int i, const QVariant &rule);
    Q_INVOKABLE void removeAlarmRule(int i);
    Q_INVOKABLE void restoreDefaultRules();

    // 温度探头映射（决策 #27）：持久化到 temp_probes.json（pid/囊体/行/列/基准）
    Q_INVOKABLE QVariant probeMapping() const;            // QVariantList<QVariantMap{pid,ei,row,col,base}>
    Q_INVOKABLE void saveProbeMapping(const QVariant &list);
    Q_INVOKABLE QVariant defaultProbeMapping() const;
    Q_INVOKABLE void resetProbeMapping();                 // 恢复默认布局（写回默认并持久化）

    // 设备卡显示字段配置（决策 #？）：每设备可见字段 key 列表
    Q_INVOKABLE QStringList fieldConfig(const QString &device) const;
    Q_INVOKABLE void setFieldConfig(const QString &device, const QVariant &list);

    // 运行时长（决策：状态栏）
    Q_INVOKABLE int uptimeSeconds() const;

    // 通用日志/事件流（运行日志 + 时间轴）由 QML 侧维护，这里提供启动时刻供计算

signals:
    void telemetryChanged();                 // 有新遥测
    void linkChanged(bool online);
    void stateChanged();                     // 串口开关 / 配置变更（模块可见性等），前端据此刷新 UI
    void alarmRaised(const QString &msg, const QString &level);
    void alarmsChanged();                    // 告警列表/计数变化
    void rulesChanged();                     // 告警规则变化
    void configImported();                   // 配置导入成功，前端需刷新各设置控件
    void gimbalConnectedChanged();
    void gimbalAttitudeChanged();

private:
    lgs::TelemetryData last_;
    void startRecording();
    void stopRecording();
    bool linkOnline_ = false;
    SerialManager *serial_ = nullptr;
    ConfigManager *config_ = nullptr;
    AlarmEngine *engine_ = nullptr;
    QHash<QString, RtspStream *> streams_;   // 相机 id → RTSP 流（懒创建，随桥接层销毁）
    QHash<QString, RtspRecorder *> recorders_;  // 相机 id → 录制器（多路并行，随桥接层销毁）
    SiyiSdkClient *gimbal_ = nullptr;        // 思翼云台 SDK 客户端（随桥接层销毁）
    QString lastSerialError_;  // 最近一次 openSerial 失败的具体原因（供 QML 透出）
    QList<QVariantMap> alarmList_;
    int unconfirmed_ = 0;
    // 温度历史（决策 #28）：每轮 LoRa 节点采样，环形上限 200 轮
    QList<QVariantMap> loraHistory_;
    QElapsedTimer uptime_;
    bool uptimeStarted_ = false;
    // 数据自动记录
    QFile recordFile_;
    QString recordPath_;
    QTimer flushTimer_;   // 定时批量落盘，避免每帧 flush 阻塞 GUI 线程
    bool recordEnabled_ = true; // 运行时开关状态（初始化取自 config，默认开）
};

} // namespace lgs
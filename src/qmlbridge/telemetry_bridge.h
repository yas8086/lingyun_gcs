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
class SkydroidSdkClient;

// 桥接层：把 C++ 后端（遥测/链路/就绪度/告警/串口/配置）暴露给 QML 前端。
// 采用 context 属性注入，QML 通过 Q_INVOKABLE 方法与信号交互。
class TelemetryBridge : public QObject {
    Q_OBJECT
    // 思翼云台（A2 mini UDP SDK）：连接状态与俯仰角（度）实时暴露给 QML
    Q_PROPERTY(bool gimbalConnected READ gimbalConnected NOTIFY gimbalConnectedChanged)
    Q_PROPERTY(double gimbalPitch READ gimbalPitch NOTIFY gimbalAttitudeChanged)
    // 云卓云台（C14PRO UDP 5000）：设备探测结果（false=IP:5000 无服务，多为误配）
    Q_PROPERTY(bool skyGimbalDeviceOk READ skyGimbalDevicePresent NOTIFY skyGimbalDeviceOkChanged)
    // 云卓云台姿态回读（协议 v1.1.5 GAA/GAC）：yaw/pitch/roll 度 + 是否收到过姿态帧
    Q_PROPERTY(double skyGimbalYaw READ skyGimbalYaw NOTIFY skyGimbalAttitudeChanged)
    Q_PROPERTY(double skyGimbalPitch READ skyGimbalPitch NOTIFY skyGimbalAttitudeChanged)
    Q_PROPERTY(double skyGimbalRoll READ skyGimbalRoll NOTIFY skyGimbalAttitudeChanged)
    Q_PROPERTY(bool skyGimbalAttitudeAlive READ skyGimbalAttitudeAlive NOTIFY skyGimbalAttitudeChanged)
    // 云卓激光测距（协议 v1.1.5 SLR）：最近一次单次测距结果（米）
    Q_PROPERTY(double skyGimbalRanging READ skyGimbalRanging NOTIFY skyGimbalRangingChanged)
public:
    explicit TelemetryBridge(QObject *parent = nullptr);

    void onTelemetry(const lgs::TelemetryData &data);
    void setLinkOnline(bool online);
    void setSerialManager(SerialManager *serial);
    void setConfigManager(ConfigManager *config);
    void setAlarmEngine(AlarmEngine *engine);
    // B3：串口异常（ResourceError 拔线等）时同步缓存状态，避免 isSerialOpen 长期跨线程阻塞
    void markSerialGone();

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
    // 飞控字符串字段（mode 飞行模式）：离线返回空串
    Q_INVOKABLE QString fcStringField(const QString &key) const;
    // 就绪度状态：0 待自检 / 1 就绪可飞 / 2 起飞受限 / 3 不可起飞
    Q_INVOKABLE int readinessState() const;
    // 就绪度明细（B4：与 readinessState() 阈值单一来源，QML 弹窗单源消费，避免阈值漂移）：
    // QVariantList<QVariantMap{name, ok, val}>
    Q_INVOKABLE QVariant readinessDetail() const;
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
    // 释放指定相机的 RTSP 流对象（停流并从缓存移除，相机配置删除时调用，
    // 避免 streams_ 只增不减导致对象与 QTimer 累积）
    Q_INVOKABLE void releaseStream(const QString &camId);
    // 摄像头录像：真实录制（rtspsrc→parsebin→matroskamux 零转码存 .mkv，按天归档）
    // 多路并行：按相机 id 各建录制器。返回文件名（空=失败，如相机未配置地址；
    // 该相机已在录则返回当前文件名）；stopCameraRecord 停止全部在录并返回是否有路停止
    Q_INVOKABLE QString startCameraRecord(const QString &camId);
    Q_INVOKABLE bool stopCameraRecord();
    // 录像运行时状态提升到 bridge（录制器随桥接层跨页面存活）：
    // CameraView 用 Loader 懒加载，切出即销毁；录像状态/计时若放页面则切回丢失，
    // 导致 UI 无法正确显示"仍在录制"。故由 bridge 统一维护供任意页面读写。
    Q_INVOKABLE bool cameraRecording() const { return camRecOn_; }
    Q_INVOKABLE QVariantList cameraRecordingCams() const;  // 当前在录相机 id 列表
    Q_INVOKABLE qint64 cameraRecStart() const { return camRecStart_; }  // 开始时间戳(ms)
    // 思翼云台控制（A2 mini，UDP 37260）：startGimbal(ip) 启动会话并 200ms 轮询姿态；
    // gimbalCtrlMove(yaw,pitch) 组合速度控制 -100~100（A2 mini 仅俯仰轴生效，松手发 0,0）；
    // gimbalCenter 一键回中；gimbalSetPitchAngle(deg) 设置俯仰目标角度（0x0E，自定义回中角）
    Q_INVOKABLE void startGimbal(const QString &ip);
    Q_INVOKABLE void stopGimbal();
    Q_INVOKABLE void gimbalCtrlMove(int yaw, int pitch);
    Q_INVOKABLE void gimbalCenter();
    Q_INVOKABLE void gimbalSetPitchAngle(double pitchDeg);   // 单位度，A2 mini 范围 -90~+25
    bool gimbalConnected() const;
    double gimbalPitch() const;
    // 云卓云台相机（C14PRO，UDP 5000 文本协议）控制：
    // startSkyGimbal(ip) 启动会话；skyGimbalCtrlMove(ip,yaw,pitch) 速度控制 -100~100；
    // skyGimbalCenter(ip) 一键回中；skyGimbalZoom(ip,dir) 变焦 ±1；skyGimbalShot(ip) 拍照；skyGimbalRecord(ip,on) 录像开关
    // 注：各方法均带 ip 目标参数——支持多个相机配置成 skydroid 时各自向自己的 IP 发送
    Q_INVOKABLE void startSkyGimbal(const QString &ip);
    Q_INVOKABLE void stopSkyGimbal();
    Q_INVOKABLE void skyGimbalCtrlMove(const QString &ip, int yaw, int pitch);
    Q_INVOKABLE void skyGimbalCenter(const QString &ip);
    Q_INVOKABLE void skyGimbalZoom(const QString &ip, int dir);
    Q_INVOKABLE void skyGimbalSetLens(const QString &ip, int lens);   // 0=广角 1=长焦
    Q_INVOKABLE void skyGimbalShot(const QString &ip);
    Q_INVOKABLE void skyGimbalRecord(const QString &ip, bool on);
    // 云卓姿态回读（GAA/GAC）：on=true 使能主动送出（1Hz）
    Q_INVOKABLE void skyGimbalSetAttitudeReport(const QString &ip, bool on);
    // 云卓单次激光测距（SLR）：结果经 skyGimbalRanging 属性读取
    Q_INVOKABLE void skyGimbalRequestRanging(const QString &ip);
    // 目标 IP:5000 是否确认存在云卓设备（false=探测到端口无服务，如思翼相机误配为云卓）
    // 探测在 startSkyGimbal 时异步进行，返回 true 表示在线或尚未确认
    Q_INVOKABLE bool skyGimbalDevicePresent() const;
    // 云卓姿态/测距读取（全局单值版本，兼容 Q_PROPERTY 绑定）
    bool skyGimbalAttitudeAlive() const;
    double skyGimbalYaw() const;
    double skyGimbalPitch() const;
    double skyGimbalRoll() const;
    double skyGimbalRanging() const;
    // 云卓姿态/测距读取（按相机 IP 查询，支持多 skydroid 相机独立判断）。
    // 注意：方法名必须与上面的 Q_PROPERTY 属性名不同（QML 同名时解析为属性而非函数）——
    // 带参版本统一加 "Of" 后缀，QML 侧用 bridge.skyGimbalYawOf(ip) 等调用
    Q_INVOKABLE bool skyGimbalAttitudeAliveOf(const QString &ip);
    Q_INVOKABLE double skyGimbalYawOf(const QString &ip);
    Q_INVOKABLE double skyGimbalPitchOf(const QString &ip);
    Q_INVOKABLE double skyGimbalRollOf(const QString &ip);
    Q_INVOKABLE double skyGimbalRangingOf(const QString &ip);
    // 该 IP 是否收到过云卓协议帧（#TP 前缀）："确为云卓设备"的最可靠判据
    Q_INVOKABLE bool skyGimbalProtocolAliveOf(const QString &ip);
    // 云卓云台"选错类型"标记（按 camId 存，跨页面持久化；
    //   true=思翼等相机被误配为 skydroid，姿态回读超时无应答即判定选错；
    //   切换到正确云台类型或真实收到姿态帧时需清除）
    Q_INVOKABLE void markSkyGimbalWrong(const QString &camId, bool wrong);
    Q_INVOKABLE bool isSkyGimbalWrong(const QString &camId);
    // 网络接口状态（网口链路检测）：QVariantList<QVariantMap{name,ip,mac,linkUp,isUp}>
    // linkUp 为物理链路状态：Windows 查 OperStatus，Linux 读 /sys/class/net/*/carrier
    Q_INVOKABLE QVariant netInterfaces() const;

    // 告警列表与确认（决策 #20）
    // addAlarm 返回该条告警的自增 aid，QML 侧据此精确确认单条（而非误调"确认全部"）。
    // ruleId 为告警规则 id（AlarmEngine 的 AlarmEvent.id）：规则恢复时据此定位并标记"已恢复"
    int addAlarm(const QString &msg, const QString &level, const QString &source,
                 const QString &ruleId = QString());
    Q_INVOKABLE QVariant alarms() const;          // 返回 QVariantList<QVariantMap>
    Q_INVOKABLE void confirmAlarm(int i);
    Q_INVOKABLE void confirmAlarmByAid(int aid);  // 按 aid 确认单条
    Q_INVOKABLE void confirmAllAlarms();
    Q_INVOKABLE int unconfirmedCount() const;
    // 规则恢复：AlarmEngine::alarmCleared 触发时调用，将该规则未确认告警标记"已恢复"
    void markAlarmRecovered(const QString &ruleId);

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

    // 运行时长（决策：状态栏）
    Q_INVOKABLE int uptimeSeconds() const;

    // 通用日志/事件流（运行日志 + 时间轴）由 QML 侧维护，这里提供启动时刻供计算

signals:
    void telemetryChanged();                 // 有新遥测
    void linkChanged(bool online);
    void stateChanged();                     // 串口开关 / 配置变更（模块可见性等），前端据此刷新 UI
    void alarmsChanged();                    // 告警列表/计数变化
    void rulesChanged();                     // 告警规则变化
    void configImported();                   // 配置导入成功，前端需刷新各设置控件
    void gimbalConnectedChanged();
    void gimbalAttitudeChanged();
    void skyGimbalDeviceOkChanged();   // 云卓设备探测完成（在线 / 端口无服务）
    void skyGimbalAttitudeChanged();   // 云卓姿态回读更新（yaw/pitch/roll/存活）
    void skyGimbalRangingChanged();    // 云卓激光测距结果更新
    void skyGimbalWrongChanged(const QString &camId);  // 某相机"选错云台类型"标记变化

private:
    lgs::TelemetryData last_;
    void startRecording();
    void stopRecording();
    void onRecorderFinalized();   // 录制器收尾完成（EOS 写完）后移除并释放
    bool linkOnline_ = false;
    bool serialOpen_ = false;     // B3：串口打开状态缓存（避免 isSerialOpen 高频跨线程阻塞）
    SerialManager *serial_ = nullptr;
    ConfigManager *config_ = nullptr;
    AlarmEngine *engine_ = nullptr;
    QHash<QString, RtspStream *> streams_;   // 相机 id → RTSP 流（懒创建，随桥接层销毁）
    QHash<QString, RtspRecorder *> recorders_;  // 相机 id → 录制器（多路并行，随桥接层销毁）
    QStringList camCamIds_;                   // 当前在录相机 id 集（跨页保留）
    bool camRecOn_ = false;                   // 当前是否正在录像（跨页保留）
    qint64 camRecStart_ = 0;                  // 录像开始时间戳(ms)，跨页保留
    SiyiSdkClient *gimbal_ = nullptr;        // 思翼云台 SDK 客户端（随桥接层销毁）
    SkydroidSdkClient *skyGimbal_ = nullptr; // 云卓 C14PRO 云台 SDK 客户端（随桥接层销毁）
    QString skyGimbalTargetIp_;              // 云卓 SDK 会话的主目标IP（无参版本查询默认用该IP）
    QHash<QString, bool> skyWrongIds_;       // 云卓"选错云台类型"标记（camId→bool，跨页持久化）
    QString lastSerialError_;  // 最近一次 openSerial 失败的具体原因（供 QML 透出）
    QList<QVariantMap> alarmList_;
    int unconfirmed_ = 0;
    int alarmSeq_ = 0;   // 告警自增 aid（QML 侧单条确认据此定位）
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

// 温度探头映射文件路径（决策 #27）：供 rules/config 两个拆分部共用（配置导入导出需合并该文件，B8）
QString probesFilePath();

} // namespace lgs
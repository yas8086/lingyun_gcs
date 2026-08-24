#pragma once
#include <QString>
#include <QByteArray>
#include <QVector>
#include <QSet>
#include <QJsonObject>
#include <QJsonArray>
#include "core/alarm_engine.h"

namespace lgs {

// 模块可见性键（决策 #30）。与 MainWindow 中各模块一一对应。
namespace ModuleKey {
inline const char *const Device  = "device";   // 监控设备卡
inline const char *const Chart   = "chart";    // 实时曲线
inline const char *const Alarm   = "alarm";    // 告警
inline const char *const Log     = "log";      // 日志
inline const char *const Replay  = "replay";   // 回放
inline const char *const Temp    = "temp";     // 温度
inline const char *const Readiness = "readiness"; // 就绪度
inline const char *const StatusBar = "statusbar"; // 状态栏
} // namespace ModuleKey

// 用 JSON 文件持久化串口、界面与告警规则配置（决策 #7：JSON 含 BOM，便于 Windows）
class ConfigManager {
public:
    ConfigManager();

    QString port() const;
    qint32 baud() const;
    void setPort(const QString &p);
    void setBaud(qint32 b);

    void saveWindowGeometry(const QByteArray &geo);
    QByteArray windowGeometry() const;

    // 告警规则持久化；入参为默认规则，用于文件缺失时回退
    QVector<AlarmRule> loadAlarmRules(const QVector<AlarmRule> &defaults) const;
    void saveAlarmRules(const QVector<AlarmRule> &rules);

    // 用户偏好（决策 #24/#29）：温度单位(0=℃ 1=℉)、告警声音开关、曲线窗口秒数
    int temperatureUnit() const;             // 0=℃ 1=℉
    void setTemperatureUnit(int unit);
    int pressureUnit() const;                // 压力单位 0=kPa 1=Pa 2=bar 3=psi
    void setPressureUnit(int unit);
    bool alarmSoundEnabled() const;          // 默认关闭（决策 #19）
    void setAlarmSoundEnabled(bool on);
    int chartWindowSecs() const;             // 10/20/30（B10：注释与实现合法集合对齐）
    void setChartWindowSecs(int secs);

    // 模块可见性（决策 #30）：默认全可见；返回"被隐藏"的模块键集合
    QSet<QString> hiddenModules() const;
    void setHiddenModules(const QSet<QString> &hidden);

    // 数据自动记录（逐帧原始报文落盘）：开关（默认开）+ 保存目录（默认空=软件目录/data）
    bool recordEnabled() const;
    void setRecordEnabled(bool on);
    QString recordDir() const;
    void setRecordDir(const QString &dir);

    // 界面主题（决策：深色/浅色、密度、高对比度、强调色）——纳入重启恢复与导入导出
    bool darkTheme() const;                 // 深色
    void setDarkTheme(bool dark);
    bool denseTheme() const;                // 密集布局
    void setDenseTheme(bool dense);
    bool contrastTheme() const;             // 高对比度
    void setContrastTheme(bool contrast);
    QString accentTheme() const;            // blue|green|orange|purple|teal
    void setAccentTheme(const QString &accent);

    // 地图（决策：在线瓦片天地图/OSM）：图源(0天地图 1OSM)与天地图密钥
    int mapSource() const;
    void setMapSource(int source);
    QString mapKey() const;
    void setMapKey(const QString &key);

    // 相机拉流配置（RTSP 相机列表，JSON 数组）+ 布局档位（1/2/4/a）
    QJsonArray cameraConfigs() const;
    void setCameraConfigs(const QJsonArray &arr);
    QString cameraLay() const;
    void setCameraLay(const QString &lay);

    // 数传网口 UDP 数据源（协议 2.1）：启用开关 + 本地监听端口（默认 20000，机载定向单播）
    bool udpEnabled() const;
    void setUdpEnabled(bool on);
    quint16 udpPort() const;
    void setUdpPort(quint16 port);

    QString filePath() const;
    // 重载：重新从磁盘读取配置到内存缓存（导入配置后调用，避免前端读到旧值）
    void reload();
    // 落盘：将内存缓存写回磁盘（setter 已即时落盘，此法供批量/导入场景使用）
    void flush();

private:
    // 按 key 读取内存字段；文件缺失时给默认值
    QJsonValue value(const char *key, const QJsonValue &def = {}) const;
    // 修改内存字段并落盘
    void set(const char *key, const QJsonValue &v);

    QString filePath_;
    QJsonObject root_; // 内存缓存，构造时一次性读入，避免每次 getter 重复磁盘 IO
};

} // namespace lgs
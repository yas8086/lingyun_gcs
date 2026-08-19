#include "qmlbridge/telemetry_bridge.h"
#include "comms/serial_manager.h"
#include "core/config_manager.h"
#include <QTime>
#include <QMetaObject>
#include <QSerialPortInfo>
#include <QDir>
#include <QFile>
#include <QNetworkInterface>
#include <QAbstractSocket>
#include <limits>
#ifdef Q_OS_WIN
// Windows 网口物理链路检测依赖 IP Helper API（GetAdaptersAddresses 查 OperStatus）
#include <winsock2.h>   // 必须最先包含，先于 windows.h
#include <windows.h>
#include <iphlpapi.h>
#endif

namespace lgs {

// 桥接层核心领域：构造、遥测、链路、串口、设备取值/就绪度、LoRa、告警列表、运行时长。
// 配置领域、告警规则/探头映射、数据记录 已按领域拆分至
// telemetry_bridge_config.cpp / telemetry_bridge_rules.cpp / telemetry_bridge_record.cpp。

TelemetryBridge::TelemetryBridge(QObject *parent) : QObject(parent) {
    // 运行时长：初始不启动，待串口打开时才开始计时（uptimeStarted_ = true）
    uptimeStarted_ = false;
    // 记录默认开启（与 config_manager 默认一致，测试契约 recordConfigDefaults）
    recordEnabled_ = true;
    // 定时批量落盘（250ms），避免每帧 flush 阻塞 GUI 线程
    flushTimer_.setInterval(250);
    flushTimer_.setSingleShot(false);
    connect(&flushTimer_, &QTimer::timeout, this, [this] {
        if (recordFile_.isOpen())
            recordFile_.flush();
    });
}

void TelemetryBridge::onTelemetry(const lgs::TelemetryData &data) {
    last_ = data;
    // 维护温度历史（决策 #28）：仅记录有节点的轮次，环形上限 200
    if (data.lora && !data.lora->nodes.empty()) {
        QVariantMap round;
        const auto &nodes = data.lora->nodes;
        for (const auto &s : nodes) {
            // 列名用 Txx（pid 主键），与 QWidget 版对齐
            const QString key = QStringLiteral("T%1")
                                    .arg(QString::number(s.id).rightJustified(2, QLatin1Char('0')));
            round[key] = s.temp != 0.0 ? s.temp : s.pressure;
        }
        loraHistory_.append(round);
        if (loraHistory_.size() > 200)
            loraHistory_.removeFirst();
    }
    emit telemetryChanged();
}

void TelemetryBridge::setLinkOnline(bool online) {
    if (linkOnline_ != online) {
        linkOnline_ = online;
        emit linkChanged(online);
    }
}

void TelemetryBridge::setSerialManager(SerialManager *serial) { serial_ = serial; }
void TelemetryBridge::setConfigManager(ConfigManager *config) {
    config_ = config;
    if (config_)
        recordEnabled_ = config_->recordEnabled();
}
void TelemetryBridge::setAlarmEngine(AlarmEngine *engine) { engine_ = engine; }
QStringList TelemetryBridge::ports() const {
    // QSerialPortInfo::availablePorts 本身线程安全，无需跨线程调用
    QStringList list;
    const auto infos = QSerialPortInfo::availablePorts();
    for (const auto &info : infos)
        list << info.portName();
#ifndef Q_OS_WIN
    // 追加虚拟串口（如 socat 创建的 /tmp/gcs_pty*）：QSerialPortInfo 只枚举
    // /dev 下标准串口，不识别 /tmp 下的符号链接，此处手动补上便于本地模拟联调。
    // Windows 下无 /tmp，联调用 com0com 等虚拟串口对工具，会自动出现在 COM 列表，无需此处补全。
    const auto entries = QDir("/tmp").entryList(QStringList() << "gcs_pty*",
                                                QDir::AllEntries | QDir::NoDotAndDotDot,
                                                QDir::Name);
    for (const auto &e : entries) {
        const QString path = "/tmp/" + e;
        if (!list.contains(path))
            list << path;
    }
#endif
    return list;
}
bool TelemetryBridge::openSerial(const QString &port, int baud) {
    if (!serial_) return false;
    // 跨线程同步调用 SerialManager::open（BlockingQueuedConnection）
    bool ok = false;
    QMetaObject::invokeMethod(serial_, "open", Qt::BlockingQueuedConnection,
                              Q_RETURN_ARG(bool, ok),
                              Q_ARG(QString, port),
                              Q_ARG(qint32, qint32(baud)));
    if (ok) {
        lastSerialError_.clear();
        stopRecording();
        startRecording();
        // 运行时长：从串口打开开始计时（决策：而非程序启动）
        uptime_.restart();
        uptimeStarted_ = true;
    } else {
        // 透出具体失败原因（锁冲突/权限/设备不存在等），供 QML 提示
        QString err;
        QMetaObject::invokeMethod(serial_, "lastOpenError", Qt::BlockingQueuedConnection,
                                  Q_RETURN_ARG(QString, err));
        lastSerialError_ = err.isEmpty() ? QStringLiteral("未知错误") : err;
    }
    // 通知前端刷新串口状态（按钮文字/颜色/状态栏链路），否则切页后才更新
    emit stateChanged();
    return ok;
}
QString TelemetryBridge::lastSerialError() const {
    return lastSerialError_;
}
void TelemetryBridge::closeSerial() {
    stopRecording();
    // 串口关闭：停止运行时长计时（再次打开会从 0 重新开始）
    uptimeStarted_ = false;
    if (!serial_) return;
    // 跨线程异步调用 SerialManager::close（QueuedConnection）
    QMetaObject::invokeMethod(serial_, "close", Qt::QueuedConnection);
    // 通知前端刷新串口状态（按钮文字/颜色/状态栏链路）
    emit stateChanged();
}
bool TelemetryBridge::isSerialOpen() const {
    if (!serial_) return false;
    bool open = false;
    QMetaObject::invokeMethod(serial_, "isOpen", Qt::BlockingQueuedConnection,
                              Q_RETURN_ARG(bool, open));
    return open;
}

bool TelemetryBridge::online(const QString &device) const {
    if (device == "bms") return last_.bms.has_value();
    if (device == "backup") return last_.backup.has_value();
    if (device == "mppt") return last_.mppt.has_value();
    if (device == "dcdc") return last_.dcdc.has_value();
    if (device == "lora") return last_.lora.has_value();
    if (device == "fc") return last_.fc.has_value();
    return false;
}

QString TelemetryBridge::fcStringField(const QString &key) const {
    if (!last_.fc) return QString();
    const auto &f = *last_.fc;
    if (key == "mode") return f.mode;
    return QString();
}

double TelemetryBridge::value(const QString &device, const QString &key) const {
    const double nan = std::numeric_limits<double>::quiet_NaN();
    if (device == "bms" && last_.bms) {
        const auto &b = *last_.bms;
        if (key == "pack_v") return b.pack_v;
        if (key == "pack_i") return b.pack_i;
        if (key == "soc") return b.soc;
        if (key == "rsoc") return b.rsoc;
        if (key == "max_v") return b.max_v;
        if (key == "min_v") return b.min_v;
        if (key == "diff_v") return b.diff_v;
        if (key == "max_t") return b.max_t;
        if (key == "min_t") return b.min_t;
        if (key == "avg_t") return b.avg_t;
        if (key == "diff_t") return b.diff_t;
        if (key == "riso_p") return b.riso_p;
        if (key == "riso_n") return b.riso_n;
        if (key == "alarm") return b.alarm;
    } else if (device == "backup" && last_.backup) {
        const auto &b = *last_.backup;
        if (key == "pack_v") return b.pack_v;
        if (key == "pack_i") return b.pack_i;
        if (key == "soc") return b.soc;
        if (key == "soh") return b.soh;
        if (key == "max_v") return b.max_v;
        if (key == "min_v") return b.min_v;
        if (key == "diff_v") return b.diff_v;
        if (key == "max_t") return b.max_t;
        if (key == "min_t") return b.min_t;
        if (key == "avg_t") return b.avg_t;
        if (key == "diff_t") return b.diff_t;
        if (key == "alarm") return b.alarm;
        if (key == "fault") return b.fault;
        if (key == "sys") return b.sys;
    } else if (device == "mppt" && last_.mppt) {
        const auto &m = *last_.mppt;
        if (key == "pv_v") return m.pv_v;
        if (key == "pv_p") return m.pv_p;
        if (key == "batt_v") return m.batt_v;
        if (key == "charge_i") return m.charge_i;
        if (key == "today") return m.today;
        if (key == "total") return m.total;
        if (key == "fault") return m.fault;
    } else if (device == "dcdc" && last_.dcdc) {
        const auto &d = *last_.dcdc;
        if (key == "in_v") return d.in_v;
        if (key == "out_v") return d.out_v;
        if (key == "out_i") return d.out_i;
        if (key == "out_p") return d.out_p;
        if (key == "temp") return d.temp;
        if (key == "fault") return d.fault;
        if (key == "enabled") return d.enabled ? 1 : 0;
    } else if (device == "fc" && last_.fc) {
        const auto &f = *last_.fc;
        if (key == "roll") return f.roll;
        if (key == "pitch") return f.pitch;
        if (key == "yaw") return f.yaw;
        if (key == "lat") return f.lat;
        if (key == "lon") return f.lon;
        if (key == "alt") return f.alt;
        if (key == "vx") return f.vx;
        if (key == "vy") return f.vy;
        if (key == "vz") return f.vz;
        if (key == "batt_v") return f.batt_v;
        if (key == "batt_pct") return f.batt_pct;
        if (key == "armed") return f.armed ? 1 : 0;
    }
    return nan;
}

int TelemetryBridge::readinessState() const {
    const bool any = last_.bms.has_value() || last_.mppt.has_value() ||
                     last_.dcdc.has_value();
    if (!any)
        return 0; // 待自检
    int fails = 0;
    if (last_.bms) {
        if (last_.bms->pack_v <= 360 || last_.bms->pack_v >= 380) ++fails;
        if (last_.bms->soc <= 30) ++fails;
        if (last_.bms->max_t >= 50) ++fails;
        if (last_.bms->diff_v >= 0.05) ++fails;
    } else ++fails;
    if (last_.mppt) {
        if (last_.mppt->pv_v <= 20 || last_.mppt->pv_v >= 120) ++fails;
        if (last_.mppt->charge_i <= 0) ++fails;
    } else ++fails;
    if (last_.dcdc) {
        if (last_.dcdc->out_v <= 40 || last_.dcdc->out_v >= 60) ++fails;
        if (last_.dcdc->temp >= 45) ++fails;
    } else ++fails;
    if (fails == 0) return 1;
    if (fails <= 1) return 2;
    return 3;
}

int TelemetryBridge::addAlarm(const QString &msg, const QString &level,
                              const QString &source, const QString &ruleId) {
    QVariantMap entry;
    entry["time"] = QTime::currentTime().toString("HH:mm:ss");
    entry["level"] = level;
    entry["source"] = source;
    entry["content"] = msg;
    entry["state"] = QStringLiteral("未确认");
    entry["aid"] = ++alarmSeq_;   // 自增 aid：供 QML 按 id 精确确认单条
    if (!ruleId.isEmpty())
        entry["ruleId"] = ruleId; // 规则恢复时按此定位
    alarmList_.push_front(entry); // 最新在前
    ++unconfirmed_;
    // 环形上限（决策 #33）：告警 200 条
    while (alarmList_.size() > 200) {
        alarmList_.pop_back();
    }
    emit alarmsChanged();
    return alarmSeq_;
}

QVariant TelemetryBridge::alarms() const {
    QVariantList list;
    list.reserve(alarmList_.size());
    for (const auto &m : alarmList_)
        list.append(m);
    return list;
}

void TelemetryBridge::confirmAlarm(int i) {
    if (i < 0 || i >= alarmList_.size())
        return;
    if (alarmList_[i].value("state").toString() == QStringLiteral("未确认")) {
        alarmList_[i]["state"] = QStringLiteral("已确认");
        --unconfirmed_;
        emit alarmsChanged();
    }
}

void TelemetryBridge::confirmAlarmByAid(int aid) {
    for (int i = 0; i < alarmList_.size(); ++i) {
        if (alarmList_[i].value("aid").toInt() == aid
            && alarmList_[i].value("state").toString() == QStringLiteral("未确认")) {
            alarmList_[i]["state"] = QStringLiteral("已确认");
            --unconfirmed_;
            emit alarmsChanged();
            return;
        }
    }
}

void TelemetryBridge::markAlarmRecovered(const QString &ruleId) {
    if (ruleId.isEmpty())
        return;
    // 规则/设备恢复：将对应规则的未确认告警标记为"已恢复"（等价于自动确认），
    // 使恢复语义反映到 UI（未确认计数下降），避免告警只增不减永远滞留
    for (auto &m : alarmList_) {
        if (m.value("ruleId").toString() == ruleId
            && m.value("state").toString() == QStringLiteral("未确认")) {
            m["state"] = QStringLiteral("已恢复");
            --unconfirmed_;
        }
    }
    emit alarmsChanged();
}

void TelemetryBridge::confirmAllAlarms() {
    for (auto &m : alarmList_)
        m["state"] = QStringLiteral("已确认");
    unconfirmed_ = 0;
    emit alarmsChanged();
}

int TelemetryBridge::unconfirmedCount() const { return unconfirmed_; }

QString TelemetryBridge::loraSummary() const {
    if (!last_.lora || last_.lora->nodes.empty())
        return QStringLiteral("无在线节点");
    // 压力单位（配置于设置页）：0=kPa 1=Pa 2=bar 3=psi
    const int pu = config_ ? config_->pressureUnit() : 0;
    QStringList rows;
    for (const auto &s : last_.lora->nodes) {
        QString line;
        if (s.temp != 0.0)
            line = QStringLiteral("#%1 %2℃").arg(s.id).arg(s.temp, 0, 'f', 1);
        else {
            QString suffix;
            double val = 0.0;
            switch (pu) {
            case 1: val = s.pressure; suffix = QStringLiteral("Pa"); break;
            case 2: val = s.pressure / 100000.0; suffix = QStringLiteral("bar"); break;
            case 3: val = s.pressure / 6894.7573; suffix = QStringLiteral("psi"); break;
            default: val = s.pressure / 1000.0; suffix = QStringLiteral("kPa"); break;
            }
            line = QStringLiteral("#%1 %2%3").arg(s.id)
                       .arg(val, 0, 'f', (pu == 1 ? 0 : 2)).arg(suffix);
        }
        if (s.alarm != 0)
            line += s.alarm > 0 ? QStringLiteral(" ⚠超上限")
                                : QStringLiteral(" ⚠超下限");
        rows << line;
    }
    return rows.join(QStringLiteral("\n"));
}

QVariant TelemetryBridge::loraNodes() const {
    QVariantList list;
    if (!last_.lora)
        return list;
    for (const auto &s : last_.lora->nodes) {
        QVariantMap m;
        m["id"] = s.id;
        m["temp"] = s.temp;
        m["pressure"] = s.pressure;
        m["alarm"] = s.alarm;
        m["isTemp"] = s.temp != 0.0;
        list.append(m);
    }
    return list;
}

// ---- 运行时长 ----
int TelemetryBridge::uptimeSeconds() const {
    return uptimeStarted_ ? static_cast<int>(uptime_.elapsed() / 1000) : 0;
}

// ---- 网络接口状态（网口链路检测）----
// 返回 QVariantList<QVariantMap{name,ip,mac,linkUp,isUp}>。
// linkUp 为物理链路状态（网线是否插入）：
//  - Windows：GetAdaptersAddresses 查适配器 OperStatus（IfOperStatusUp=已连接）；
//  - Linux：读 /sys/class/net/<iface>/carrier（1=已插，0=未插/断开）；
// 无法获取（如回环/虚拟网卡）时为 null。
QVariant TelemetryBridge::netInterfaces() const {
    QVariantList list;
#ifdef Q_OS_WIN
    // 预取 物理地址(MAC) → 链路状态(OperStatus) 映射，供下方按 MAC 匹配
    // （QNetworkInterface::allInterfaces 的 name 与 IP Helper 的 AdapterName 编码不一致，
    //   用稳定的 MAC 关联最可靠）
    QHash<QString, bool> macLinkUp;
    ULONG bufLen = 0;
    const ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
    ::GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, nullptr, &bufLen);
    if (bufLen > 0) {
        QByteArray buf(int(bufLen), Qt::Uninitialized);
        auto *addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES *>(buf.data());
        if (::GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, addrs, &bufLen) == NO_ERROR) {
            for (auto *p = addrs; p; p = p->Next) {
                QString mac;
                for (ULONG i = 0; i < p->PhysicalAddressLength; ++i) {
                    mac += QStringLiteral("%1").arg(p->PhysicalAddress[i], 2, 16, QLatin1Char('0')).toUpper();
                    if (i + 1 < p->PhysicalAddressLength)
                        mac += QLatin1Char(':');
                }
                if (!mac.isEmpty())
                    macLinkUp[mac] = (p->OperStatus == IfOperStatusUp);
            }
        }
    }
#endif
    const auto ifaces = QNetworkInterface::allInterfaces();
    for (const auto &iface : ifaces) {
        if (iface.flags() & QNetworkInterface::IsLoopBack)
            continue; // 跳过回环接口
        QVariantMap m;
        m["name"] = iface.name();
        m["mac"] = iface.hardwareAddress();
        m["isUp"] = bool(iface.flags() & QNetworkInterface::IsUp);
        // 取首个 IPv4 地址（IP 与链路状态无关，仅信息展示用）
        QString ip;
        const auto entries = iface.addressEntries();
        for (const auto &e : entries) {
            if (e.ip().protocol() == QAbstractSocket::IPv4Protocol) {
                ip = e.ip().toString();
                break;
            }
        }
        m["ip"] = ip;
        // 物理链路状态：Windows 用 IP Helper API，Linux 读 carrier 文件
#ifdef Q_OS_WIN
        // 统一转大写再匹配：Qt hardwareAddress() 与 IP Helper 的 MAC 大小写格式未必一致
        m["linkUp"] = macLinkUp.value(iface.hardwareAddress().toUpper(), false);
#else
        bool readable = false;
        bool linkUp = false;
        QFile f(QStringLiteral("/sys/class/net/%1/carrier").arg(iface.name()));
        if (f.open(QIODevice::ReadOnly)) {
            readable = true;
            linkUp = (f.readAll().trimmed() == "1");
            f.close();
        }
        m["linkUp"] = readable ? QVariant(linkUp) : QVariant();
#endif
        list.append(m);
    }
    return list;
}

} // namespace lgs
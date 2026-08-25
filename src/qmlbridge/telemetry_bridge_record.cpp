// 桥接层 · 数据记录领域：逐帧原始报文自动落盘、目录管理。
// 保留 `bridge` 前缀与 QML 调用不变，仅按源码组织拆分。
#include "qmlbridge/telemetry_bridge.h"
#include "core/config_manager.h"
#include "comms/serial_manager.h"
#include "video/rtsp_recorder.h"
#include <QDir>
#include <QDateTime>
#include <QTextStream>
#include <QCoreApplication>
#include <QMetaObject>
#include <QJsonArray>
#include <QJsonObject>
#include <cmath>

namespace lgs {

QString TelemetryBridge::dataDir() const {
    const QString dir = QCoreApplication::applicationDirPath() + QStringLiteral("/data");
    QDir().mkpath(dir);
    return dir;
}

QString TelemetryBridge::snapshotDir() const {
    const QString dir = dataDir() + QStringLiteral("/曲线快照");
    QDir().mkpath(dir);
    return dir;
}

QString TelemetryBridge::cameraDir() const {
    // 摄像头截图/录像按天归档：data/摄像头/yyyy-MM-dd
    const QString dir = dataDir() + QStringLiteral("/摄像头")
        + QDateTime::currentDateTime().toString("/yyyy-MM-dd");
    QDir().mkpath(dir);
    return dir;
}

QString TelemetryBridge::startCameraRecord(const QString &camId) {
    // 该相机已在录：幂等返回当前文件名
    if (recorders_.contains(camId) && recorders_.value(camId)->recording())
        return recorders_.value(camId)->fileName();

    // 从相机配置拼 RTSP url（与 videoStream 相同规则）
    if (!config_)
        return QString();
    const QJsonArray arr = config_->cameraConfigs();
    QString ip, path, user, pass;
    int port = 554;
    bool found = false;
    for (const auto &v : arr) {
        const QJsonObject o = v.toObject();
        if (o.value("id").toString() == camId) {
            ip = o.value("ip").toString();
            port = o.contains("port") ? o.value("port").toInt() : 554;
            path = o.value("path").toString();
            user = o.value("user").toString();
            pass = o.value("pass").toString();
            found = true;
            break;
        }
    }
    if (!found || ip.isEmpty())
        return QString();
    const QString cred = user.isEmpty() ? QString() : (user + ":" + pass + "@");
    const QString url = QStringLiteral("rtsp://%1%2:%3%4")
                            .arg(cred, ip).arg(port).arg(path);

    RtspRecorder *rec = recorders_.value(camId, nullptr);
    if (!rec) {
        rec = new RtspRecorder(this);
        // P0-3：收尾完成（finalized 信号）后再释放，避免过早 deleteLater 中断 EOS 写索引
        connect(rec, &RtspRecorder::finalized, this, &TelemetryBridge::onRecorderFinalized);
        recorders_.insert(camId, rec);
    }
    const QString name = QStringLiteral("rec_%1_%2.mkv")
                             .arg(camId).arg(QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss"));
    if (!rec->start(url, cameraDir() + "/" + name)) {
        // P2-6：启动失败（如拉流地址无效），移除并释放，避免死对象驻留 recorders_
        recorders_.remove(camId);
        rec->deleteLater();
        return QString();
    }
    // 维护跨页录像运行时状态（CameraView 切出销毁后依据此恢复）
    if (!camCamIds_.contains(camId))
        camCamIds_.append(camId);
    camRecOn_ = true;
    if (camRecStart_ == 0)
        camRecStart_ = QDateTime::currentMSecsSinceEpoch();
    return name;
}

bool TelemetryBridge::stopCameraRecord() {
    bool any = false;
    QStringList toRemove;
    for (auto it = recorders_.begin(); it != recorders_.end(); ++it) {
        RtspRecorder *rec = it.value();
        if (rec->recording()) {
            // P0-3：异步收尾（发 EOS + 等 mux 写完索引），finalized 时
            // onRecorderFinalized 从 recorders_ 移除并 deleteLater——不在此过早销毁，
            // 否则析构会强制中断收尾导致 .mkv 文件尾索引缺失（不可拖/不可播）。
            rec->stop();
            any = true;
        } else {
            // 未在录（启动失败或已收尾）：立即移除+释放
            toRemove.append(it.key());
            rec->deleteLater();
        }
    }
    for (const QString &id : toRemove)
        recorders_.remove(id);
    // 无论是否有路已录，都复位运行时状态（切页后 UI 依据此值恢复）
    camCamIds_.clear();
    camRecOn_ = false;
    camRecStart_ = 0;
    return any;
}

// P0-3：录制器收尾完成（EOS/mux 索引已写完）后安全释放
void TelemetryBridge::onRecorderFinalized() {
    auto *rec = qobject_cast<RtspRecorder *>(sender());
    if (!rec) return;
    for (auto it = recorders_.begin(); it != recorders_.end(); ++it) {
        if (it.value() == rec) {
            recorders_.erase(it);
            break;
        }
    }
    rec->deleteLater();
}

QVariantList TelemetryBridge::cameraRecordingCams() const {
    QVariantList list;
    for (const QString &id : camCamIds_)
        list.append(id);
    return list;
}

bool TelemetryBridge::recordEnabled() const {
    return recordEnabled_;
}
void TelemetryBridge::setRecordEnabled(bool on) {
    recordEnabled_ = on;
    if (config_) config_->setRecordEnabled(on);
    if (on)
        onDataLinkActive(serialOpen_ || udpOnline_); // 开启且任一数据源在线 → 立即启动
    else
        stopRecording(); // 关闭必然停止
}
QString TelemetryBridge::recordDir() const {
    return config_ ? config_->recordDir() : QString();
}
void TelemetryBridge::setRecordDir(const QString &dir) {
    if (config_) config_->setRecordDir(dir);
}
bool TelemetryBridge::isRecording() const { return recordFile_.isOpen(); }
QString TelemetryBridge::currentRecordFile() const { return recordPath_; }

void TelemetryBridge::startRecording() {
    if (recordFile_.isOpen())
        return; // 幂等：已在录则跳过（原逻辑达常关重开，改为任一数据源在线时由 onDataLinkActive 统一调用）
    recordPath_.clear();
    tablePath_.clear();
    if (!recordEnabled())
        return;
    // 目录：优先用户配置；否则按天归档到 data/原始数据/yyyy-MM-dd/（同一天同一文件夹）
    QString dir = recordDir();
    if (dir.isEmpty())
        dir = dataDir() + QStringLiteral("/原始数据/")
             + QDateTime::currentDateTime().date().toString("yyyy-MM-dd");
    QDir().mkpath(dir);
    // 文件名：打开数据源时间（含毫秒，避免同秒重开覆盖）
    const QString ts = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz");
    // ① 原始帧（回放用）：AA55 + JSON 逐帧，字节级一致
    recordPath_ = dir + QStringLiteral("/telemetry_") + ts + QStringLiteral(".raw");
    recordFile_.setFileName(recordPath_);
    if (!recordFile_.open(QIODevice::WriteOnly))
        return;
    const QByteArray header = QByteArray("\xEF\xBB\xBF") // UTF-8 BOM
        + "# 灵云01 地面站遥测原始记录\n"
        + "# 开始时间: " + QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss").toUtf8() + "\n"
        + "# 格式: 每行一帧原始报文（AA55 帧头 + JSON），utf-8\n";
    recordFile_.write(header);
    // ② 结构化表格（分析用 CSV）：固定列，详见 recordStructured
    tablePath_ = dir + QStringLiteral("/telemetry_") + ts + QStringLiteral(".csv");
    tableFile_.setFileName(tablePath_);
    if (tableFile_.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&tableFile_);
        out.setGenerateByteOrderMark(true);
        out << "t,fc_online,fc_roll,fc_pitch,fc_yaw,fc_lat,fc_lon,fc_alt,fc_mode,fc_armed,"
               "fc_hdg,fc_gs,fc_climb,fc_thr,fc_batt_v,fc_batt_pct,fc_gps_fix,fc_gps_sat,"
               "bms_pack_v,bms_pack_i,bms_soc,bms_max_t,bms_alarm,"
               "mppt1_pv_v,mppt1_pv_p,mppt1_charge_i,mppt1_fault,mppt1_month,mppt1_rated_v,mppt1_air_t,mppt1_mod_t,mppt1_cs,mppt1_mode,mppt1_chg_on,"
               "mppt2_pv_v,mppt2_pv_p,mppt2_charge_i,mppt2_fault,mppt2_month,mppt2_rated_v,mppt2_air_t,mppt2_mod_t,mppt2_cs,mppt2_mode,mppt2_chg_on,"
               "dcdc_out_v,dcdc_out_i,dcdc_out_p,dcdc_temp,dcdc_fault,"
               "backup_pack_v,backup_soc,backup_alarm,"
               "lora_count,lora_temps,lora_pressures,lora_alarms\n";
    }
    flushTimer_.start(); // 定时批量落盘
}
void TelemetryBridge::stopRecording() {
    flushTimer_.stop();
    if (recordFile_.isOpen())
        recordFile_.flush();   // 停止前落盘残留数据
    if (recordFile_.isOpen())
        recordFile_.close();
    if (tableFile_.isOpen())
        tableFile_.flush();
    if (tableFile_.isOpen())
        tableFile_.close();
    recordPath_.clear();
    tablePath_.clear();
}
void TelemetryBridge::onRawFrame(const QByteArray &frame) {
    if (!recordFile_.isOpen())
        return;
    recordFile_.write(frame); // 由 flushTimer_ 定时落盘，避免阻塞 GUI 线程
}

// 结构化遥测表格：每收到一帧解析后的 TelemetryData 写一行（固定列，方便 Excel/脚本分析）。
// 离线设备 / 缺失字段留空；LoRa 节点用紧凑文本列（不随节点数改变表结构）。
void TelemetryBridge::recordStructured(const lgs::TelemetryData &data) {
    if (!tableFile_.isOpen())
        return;
    QTextStream out(&tableFile_);
    const auto nm = [](double v, int dp) {
        return std::isnan(v) ? QString() : QString::number(v, 'f', dp);
    };
    const auto bm = [](bool b) { return b ? QStringLiteral("1") : QString(); };
    const auto qs = [](const QString &s) {
        // CSV 转义：含逗号/换行/引号时用双引号包裹
        if (s.contains(QLatin1Char(',')) || s.contains(QLatin1Char('"')) || s.contains(QLatin1Char('\n')))
            return QLatin1Char('"') + QString(s).replace(QLatin1Char('"'), QStringLiteral("\"\"") )+ QLatin1Char('"');
        return s;
    };
    QStringList col;
    col << nm(data.t, 3);
    // fc（17 列）
    if (data.fc) {
        const auto &f = *data.fc;
        col << "1" << nm(f.roll,3) << nm(f.pitch,3) << nm(f.yaw,1)
            << nm(f.lat,6) << nm(f.lon,6) << nm(f.alt,1) << qs(f.mode) << bm(f.armed)
            << nm(f.hdg,1) << nm(f.gs,2) << nm(f.climb,3) << nm(f.thr,1)
            << nm(f.batt_v,1) << nm(f.batt_pct,3) << QString::number(f.gpsFix) << QString::number(f.gpsSat);
    } else {
        col << QStringList(17, QString());
    }
    // bms（5）+ mppt1/mppt2（各 11）+ dcdc（5）+ backup（3）列
    if (data.bms) {
        const auto &b = *data.bms;
        col << nm(b.pack_v,1) << nm(b.pack_i,2) << QString::number(b.soc) << nm(b.max_t,1) << QString::number(b.alarm);
    } else col << QStringList(5, QString());
    // mppt1（主 MPPT，11 列）
    if (data.mppt1) {
        const auto &m = *data.mppt1;
        col << nm(m.pv_v,1) << nm(m.pv_p,1) << nm(m.charge_i,2) << QString::number(m.fault)
            << nm(m.month,2) << nm(m.rated_v,1) << nm(m.air_t,1) << nm(m.mod_t,1)
            << QString::number(m.cs) << QString::number(m.mode) << bm(m.chg_on);
    } else col << QStringList(11, QString());
    // mppt2（副 MPPT，11 列；单机部署时离线留空）
    if (data.mppt2) {
        const auto &m = *data.mppt2;
        col << nm(m.pv_v,1) << nm(m.pv_p,1) << nm(m.charge_i,2) << QString::number(m.fault)
            << nm(m.month,2) << nm(m.rated_v,1) << nm(m.air_t,1) << nm(m.mod_t,1)
            << QString::number(m.cs) << QString::number(m.mode) << bm(m.chg_on);
    } else col << QStringList(11, QString());
    if (data.dcdc) {
        const auto &d = *data.dcdc;
        col << nm(d.out_v,2) << nm(d.out_i,2) << nm(d.out_p,1) << nm(d.temp,1) << QString::number(d.fault);
    } else col << QStringList(5, QString());
    if (data.backup) {
        const auto &b = *data.backup;
        col << nm(b.pack_v,1) << QString::number(b.soc) << QString::number(b.alarm);
    } else col << QStringList(3, QString());
    // lora（4 列：count + 紧凑文本）
    if (data.lora && !data.lora->nodes.empty()) {
        QStringList tps, prs, aas;
        for (const auto &s : data.lora->nodes) {
            tps << QString::number(s.id) + QLatin1Char(':') + nm(s.temp,1);
            prs << QString::number(s.id) + QLatin1Char(':') + nm(s.pressure,1);
            aas << QString::number(s.id) + QLatin1Char(':') + QString::number(s.alarm);
        }
        col << QString::number(data.lora->nodes.size())
            << tps.join(QLatin1Char(' ')) << prs.join(QLatin1Char(' ')) << aas.join(QLatin1Char(' '));
    } else {
        col << "" << "" << "" << "";
    }
    out << col.join(QLatin1Char(',')) << QLatin1Char('\n');
}

} // namespace lgs
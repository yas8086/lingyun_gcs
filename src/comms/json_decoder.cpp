#include "comms/json_decoder.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QJsonArray>

namespace lgs {

// 协议要求：机载对 NaN/Inf 输出 JSON null，地面站须接受 null 视为无效值，
// 勿强转 0 误导显示。以下助手在值有效（非 null）时才写入字段，否则保留默认值。
static bool readDouble(const QJsonObject &o, const char *key, double &out) {
    const QJsonValue v = o.value(QLatin1String(key));
    if (v.isNull() || !v.isDouble())
        return false;
    out = v.toDouble();
    return true;
}
static int readInt(const QJsonObject &o, const char *key, int &out) {
    const QJsonValue v = o.value(QLatin1String(key));
    if (v.isNull() || !v.isDouble())
        return false;
    const double d = v.toDouble();
    // 容忍整数域字段收到小数（如 3.9）：四舍五入而非静默截断丢精度
    // 超出 int 可表示范围时钳制，避免 qRound(超大 double) 对 int 溢出（UB）
    if (d >= 2147483647.0) {
        out = 2147483647;
    } else if (d <= -2147483648.0) {
        out = -2147483648;
    } else {
        out = qRound(d);
    }
    return true;
}
static bool readBool(const QJsonObject &o, const char *key, bool &out) {
    const QJsonValue v = o.value(QLatin1String(key));
    if (v.isNull() || !v.isBool())
        return false;
    out = v.toBool();
    return true;
}
static bool readString(const QJsonObject &o, const char *key, QString &out) {
    const QJsonValue v = o.value(QLatin1String(key));
    if (v.isNull() || !v.isString())
        return false;
    out = v.toString();
    return true;
}

static Bms parseBms(const QJsonObject &o) {
    Bms b;
    readBool(o, "online", b.online);
    readDouble(o, "pack_v", b.pack_v);
    readDouble(o, "pack_i", b.pack_i);
    readInt(o, "soc", b.soc);
    readDouble(o, "rsoc", b.rsoc);
    readDouble(o, "max_v", b.max_v);
    readDouble(o, "min_v", b.min_v);
    readDouble(o, "diff_v", b.diff_v);
    readDouble(o, "max_t", b.max_t);
    readDouble(o, "min_t", b.min_t);
    readDouble(o, "avg_t", b.avg_t);
    readDouble(o, "diff_t", b.diff_t);
    readInt(o, "riso_p", b.riso_p);
    readInt(o, "riso_n", b.riso_n);
    readInt(o, "alarm", b.alarm);
    // 协议 5.1 扩展：soh / fault1/2/3
    readDouble(o, "soh", b.soh);
    readInt(o, "fault1", b.fault1);
    readInt(o, "fault2", b.fault2);
    readInt(o, "fault3", b.fault3);
    return b;
}

static BackupBms parseBackup(const QJsonObject &o) {
    BackupBms b;
    readBool(o, "online", b.online);
    readDouble(o, "pack_v", b.pack_v);
    readDouble(o, "pack_i", b.pack_i);
    readInt(o, "soc", b.soc);
    readInt(o, "soh", b.soh);
    readDouble(o, "max_v", b.max_v);
    readDouble(o, "min_v", b.min_v);
    readDouble(o, "diff_v", b.diff_v);
    readDouble(o, "max_t", b.max_t);
    readDouble(o, "min_t", b.min_t);
    readDouble(o, "avg_t", b.avg_t);
    readDouble(o, "diff_t", b.diff_t);
    readInt(o, "alarm", b.alarm);
    readInt(o, "protect", b.protect);
    readInt(o, "fault", b.fault);
    readInt(o, "sys", b.sys);
    return b;
}

static Mppt parseMppt(const QJsonObject &o) {
    Mppt m;
    readBool(o, "online", m.online);
    readDouble(o, "pv_v", m.pv_v);
    readDouble(o, "pv_p", m.pv_p);
    readDouble(o, "batt_v", m.batt_v);
    readDouble(o, "charge_i", m.charge_i);
    readDouble(o, "today", m.today);
    readDouble(o, "total", m.total);
    readInt(o, "fault", m.fault);
    return m;
}

static Dcdc parseDcdc(const QJsonObject &o) {
    Dcdc d;
    readBool(o, "online", d.online);
    readDouble(o, "in_v", d.in_v);
    readDouble(o, "out_v", d.out_v);
    readDouble(o, "out_i", d.out_i);
    readDouble(o, "out_p", d.out_p);
    readDouble(o, "temp", d.temp);
    readBool(o, "enabled", d.enabled);
    readInt(o, "fault", d.fault);
    return d;
}

static Fc parseFc(const QJsonObject &o) {
    Fc f;
    readBool(o, "online", f.online);
    readDouble(o, "roll", f.roll);
    readDouble(o, "pitch", f.pitch);
    readDouble(o, "yaw", f.yaw);
    readDouble(o, "lat", f.lat);
    readDouble(o, "lon", f.lon);
    readDouble(o, "alt", f.alt);
    readDouble(o, "vx", f.vx);
    readDouble(o, "vy", f.vy);
    readDouble(o, "vz", f.vz);
    readString(o, "mode", f.mode);
    readBool(o, "armed", f.armed);
    readDouble(o, "batt_v", f.batt_v);
    readDouble(o, "batt_pct", f.batt_pct);
    // 协议 5.5 扩展开量字段
    readDouble(o, "hdg", f.hdg);
    readDouble(o, "airspd", f.airspd);
    readDouble(o, "tas", f.tas);
    readDouble(o, "gs", f.gs);
    readDouble(o, "climb", f.climb);
    readDouble(o, "thr", f.thr);
    // EKF 估计器健康（子对象 ekf）
    const QJsonObject ekf = o.value(QLatin1String("ekf")).toObject();
    readBool(ekf, "const_pos", f.ekfPos);
    readBool(ekf, "glitch", f.ekfGlitch);
    readBool(ekf, "accel_err", f.ekfAccelErr);
    // GPS 原始数据（子对象 gps）
    const QJsonObject gps = o.value(QLatin1String("gps")).toObject();
    readInt(gps, "fix", f.gpsFix);
    readInt(gps, "sat", f.gpsSat);
    readInt(gps, "eph", f.gpsEph);
    readInt(gps, "epv", f.gpsEpv);
    // ESC 电调遥测（子对象 esc，数组定长 10，缺失置 0）
    const QJsonObject esc = o.value(QLatin1String("esc")).toObject();
    readInt(esc, "n", f.escN);
    f.escRpm.resize(10); f.escV.resize(10); f.escI.resize(10); f.escTmp.resize(10);
    const auto readArr = [&esc](const char *key, std::vector<double> &dst) {
        const QJsonArray arr = esc.value(QLatin1String(key)).toArray();
        for (int i = 0; i < 10; ++i)
            if (i < arr.size() && arr[i].isDouble())
                dst[static_cast<size_t>(i)] = arr[i].toDouble();
    };
    readArr("rpm", f.escRpm);
    readArr("v", f.escV);
    readArr("i", f.escI);
    readArr("tmp", f.escTmp);
    return f;
}

static Lora parseLora(const QJsonObject &o) {
    Lora l;
    const QJsonArray arr = o.value(QLatin1String("nodes")).toArray();
    l.nodes.reserve(static_cast<size_t>(arr.size()));
    for (const auto &v : arr) {
        const QJsonObject node = v.toObject();
        LoraSample s;
        // 与其余 parse* 一致：缺失字段保留默认，null 视为无效不覆盖。
        // online 恒为 1（仅在线节点被打包），无需解析。
        readInt(node, "id", s.id);
        readDouble(node, "temp", s.temp);
        readDouble(node, "pressure", s.pressure);
        readInt(node, "alarm", s.alarm);
        l.nodes.push_back(s);
    }
    return l;
}

bool decodeJson(const QByteArray &json, TelemetryData &out) {
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return false;

    const QJsonObject root = doc.object();
    out.t = root.value(QLatin1String("t")).toDouble();
    if (root.contains(QLatin1String("bms")))
        out.bms = parseBms(root.value(QLatin1String("bms")).toObject());
    if (root.contains(QLatin1String("backup")))
        out.backup = parseBackup(root.value(QLatin1String("backup")).toObject());
    if (root.contains(QLatin1String("mppt")))
        out.mppt = parseMppt(root.value(QLatin1String("mppt")).toObject());
    if (root.contains(QLatin1String("dcdc")))
        out.dcdc = parseDcdc(root.value(QLatin1String("dcdc")).toObject());
    if (root.contains(QLatin1String("fc")))
        out.fc = parseFc(root.value(QLatin1String("fc")).toObject());
    // lora 存在条件与 bms/mppt/dcdc 不同：收到过采样即存在（nodes 可为空数组）
    if (root.contains(QLatin1String("lora")))
        out.lora = parseLora(root.value(QLatin1String("lora")).toObject());
    return true;
}

} // namespace lgs
#include "comms/json_decoder.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>

namespace lgs {

static double toDouble(const QJsonObject &o, const char *key) {
    return o.value(QLatin1String(key)).toDouble();
}
static int toInt(const QJsonObject &o, const char *key) {
    return o.value(QLatin1String(key)).toInt();
}
static bool toBool(const QJsonObject &o, const char *key) {
    return o.value(QLatin1String(key)).toBool();
}

static Bms parseBms(const QJsonObject &o) {
    Bms b;
    b.online = toBool(o, "online");
    b.pack_v = toDouble(o, "pack_v");
    b.pack_i = toDouble(o, "pack_i");
    b.soc = toInt(o, "soc");
    b.max_v = toDouble(o, "max_v");
    b.min_v = toDouble(o, "min_v");
    b.diff_v = toDouble(o, "diff_v");
    b.max_t = toDouble(o, "max_t");
    b.alarm = toInt(o, "alarm");
    return b;
}

static Mppt parseMppt(const QJsonObject &o) {
    Mppt m;
    m.online = toBool(o, "online");
    m.pv_v = toDouble(o, "pv_v");
    m.pv_p = toDouble(o, "pv_p");
    m.batt_v = toDouble(o, "batt_v");
    m.charge_i = toDouble(o, "charge_i");
    m.today = toDouble(o, "today");
    m.total = toDouble(o, "total");
    m.fault = toInt(o, "fault");
    return m;
}

static Dcdc parseDcdc(const QJsonObject &o) {
    Dcdc d;
    d.online = toBool(o, "online");
    d.in_v = toDouble(o, "in_v");
    d.out_v = toDouble(o, "out_v");
    d.out_i = toDouble(o, "out_i");
    d.out_p = toDouble(o, "out_p");
    d.temp = toDouble(o, "temp");
    d.enabled = toBool(o, "enabled");
    d.fault = toInt(o, "fault");
    return d;
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
    if (root.contains(QLatin1String("mppt")))
        out.mppt = parseMppt(root.value(QLatin1String("mppt")).toObject());
    if (root.contains(QLatin1String("dcdc")))
        out.dcdc = parseDcdc(root.value(QLatin1String("dcdc")).toObject());
    return true;
}

} // namespace lgs

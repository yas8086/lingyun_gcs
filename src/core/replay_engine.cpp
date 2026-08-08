#include "core/replay_engine.h"
#include <QFile>
#include <QTextStream>

namespace lgs {

namespace {

// 返回 cols 中下标 idx 处的单元格是否为非空
bool colNonEmpty(const QStringList &cols, int idx) {
    return idx < cols.size() && !cols[idx].trimmed().isEmpty();
}

double colD(const QStringList &cols, int idx) {
    return (idx < cols.size()) ? cols[idx].toDouble() : 0.0;
}

int colI(const QStringList &cols, int idx) {
    return (idx < cols.size()) ? cols[idx].toInt() : 0;
}

bool colB(const QStringList &cols, int idx) {
    return (idx < cols.size()) ? (cols[idx].trimmed() == "1") : false;
}

// 判断某段列区间（[begin, end]）内是否有任一非空值，用于判定设备是否出现在帧中
bool anyNonEmpty(const QStringList &cols, int begin, int end) {
    for (int c = begin; c <= end && c < cols.size(); ++c) {
        if (!cols[c].trimmed().isEmpty())
            return true;
    }
    return false;
}

} // namespace

ReplayEngine::ReplayEngine(QObject *parent) : QObject(parent) {
    connect(&timer_, &QTimer::timeout, this, &ReplayEngine::tick);
}

bool ReplayEngine::load(const QString &filePath) {
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QTextStream in(&f);
    in.readLine(); // 跳过表头

    frames_.clear();
    deltasMs_.clear();
    double prevT = 0.0;
    bool first = true;
    while (!in.atEnd()) {
        const QStringList cols = in.readLine().split(',');
        if (cols.isEmpty())
            continue;

        lgs::TelemetryData d;
        d.t = cols[0].toDouble();

        // 列布局与 Recorder 写入一致：
        //   0:t, 1-9:bms(online,pack_v,pack_i,soc,max_v,min_v,diff_v,max_t,alarm)
        //   10-17:mppt(online,pv_v,pv_p,batt_v,charge_i,today,total,fault)
        //   18-25:dcdc(online,in_v,out_v,out_i,out_p,temp,enabled,fault)
        if (anyNonEmpty(cols, 1, 9)) {
            lgs::Bms b;
            b.online  = colB(cols, 1);
            b.pack_v  = colD(cols, 2);
            b.pack_i  = colD(cols, 3);
            b.soc     = colI(cols, 4);
            b.max_v   = colD(cols, 5);
            b.min_v   = colD(cols, 6);
            b.diff_v  = colD(cols, 7);
            b.max_t   = colD(cols, 8);
            b.alarm   = colI(cols, 9);
            d.bms = b;
        }
        if (anyNonEmpty(cols, 10, 17)) {
            lgs::Mppt m;
            m.online   = colB(cols, 10);
            m.pv_v     = colD(cols, 11);
            m.pv_p     = colD(cols, 12);
            m.batt_v   = colD(cols, 13);
            m.charge_i = colD(cols, 14);
            m.today    = colD(cols, 15);
            m.total    = colD(cols, 16);
            m.fault    = colI(cols, 17);
            d.mppt = m;
        }
        if (anyNonEmpty(cols, 18, 25)) {
            lgs::Dcdc dc;
            dc.online = colB(cols, 18);
            dc.in_v   = colD(cols, 19);
            dc.out_v  = colD(cols, 20);
            dc.out_i  = colD(cols, 21);
            dc.out_p  = colD(cols, 22);
            dc.temp   = colD(cols, 23);
            dc.enabled= colB(cols, 24);
            dc.fault  = colI(cols, 25);
            d.dcdc = dc;
        }

        if (first) {
            first = false;
            prevT = d.t;
        }
        // 相邻两帧时间间隔；首帧间隔置 0 以便立即输出
        qint64 delta = first ? 0 : static_cast<qint64>((d.t - prevT) * 1000.0);
        if (delta < 0)
            delta = 0;
        deltasMs_.append(delta);
        prevT = d.t;
        frames_.append(d);
    }
    f.close();
    return !frames_.isEmpty();
}

void ReplayEngine::start() {
    if (frames_.isEmpty())
        return;
    idx_ = 0;
    accMs_ = 0;
    elapsed_.start();
    timer_.start(10); // 10ms 轮询粒度，按真实时钟累计推进
}

void ReplayEngine::stop() {
    timer_.stop();
}

void ReplayEngine::setSpeed(double x) {
    speed_ = x > 0.0 ? x : 1.0;
}

bool ReplayEngine::isLoaded() const {
    return !frames_.isEmpty();
}

void ReplayEngine::tick() {
    // 已按速度缩放的逻辑播放时长（ms）
    const qint64 logicMs = static_cast<qint64>(elapsed_.elapsed() * speed_);
    // 输出所有"到点"的帧，保持原始时间戳节奏
    while (idx_ < frames_.size() && accMs_ + deltasMs_[idx_] <= logicMs) {
        accMs_ += deltasMs_[idx_];
        emit replayed(frames_[idx_]);
        idx_++;
    }
    if (idx_ >= frames_.size()) {
        timer_.stop();
        emit finished();
    }
}

} // namespace lgs

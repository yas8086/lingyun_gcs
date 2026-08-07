#include "core/replay_engine.h"
#include <QFile>
#include <QTextStream>

namespace lgs {

ReplayEngine::ReplayEngine(QObject *parent) : QObject(parent) {
    connect(&timer_, &QTimer::timeout, this, &ReplayEngine::tick);
}

bool ReplayEngine::load(const QString &filePath) {
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    QTextStream in(&f);
    QString header = in.readLine(); // 跳过表头
    Q_UNUSED(header);

    frames_.clear();
    deltasMs_.clear();
    double prevT = 0.0;
    bool first = true;
    while (!in.atEnd()) {
        const QStringList cols = in.readLine().split(',');
        if (cols.size() < 1)
            continue;
        lgs::TelemetryData d;
        d.t = cols[0].toDouble();
        if (first) {
            first = false;
            prevT = d.t;
        }
        deltasMs_.append(static_cast<qint64>((d.t - prevT) * 1000.0));
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
    lastTsMs_ = deltasMs_.value(0, 0);
    timer_.start(1); // 1ms 粒度轮询
}

void ReplayEngine::stop() {
    timer_.stop();
}

void ReplayEngine::setSpeed(double x) {
    speed_ = x > 0.0 ? x : 1.0;
}

void ReplayEngine::tick() {
    if (idx_ >= frames_.size()) {
        timer_.stop();
        emit finished();
        return;
    }
    // 简化：按 50ms 步进推进，达到累计时间即输出
    const qint64 step = static_cast<qint64>(50.0 / speed_);
    lastTsMs_ += step;
    emit replayed(frames_[idx_]);
    idx_++;
}

} // namespace lgs

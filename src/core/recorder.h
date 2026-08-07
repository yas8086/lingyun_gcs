#pragma once
#include <QObject>
#include <QString>
#include <QFile>
#include <QTextStream>
#include "model/telemetry_data.h"

namespace lgs {

// 将遥测追加写入 CSV，便于事后回放与分析
class Recorder : public QObject {
    Q_OBJECT
public:
    explicit Recorder(QObject *parent = nullptr);
    ~Recorder() override;

    bool start(const QString &filePath);
    void stop();
    bool isRecording() const;
    static QString defaultFileName();
    void onTelemetry(const lgs::TelemetryData &data);

signals:
    void errorOccurred(const QString &msg);

private:
    QFile file_;
    QTextStream stream_;
    bool headerWritten_ = false;
};

} // namespace lgs

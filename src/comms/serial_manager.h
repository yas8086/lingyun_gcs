#pragma once
#include <QObject>
#include <QSerialPort>
#include <QStringList>
#include "model/telemetry_data.h"

namespace lgs {

class FrameParser;

class SerialManager : public QObject {
    Q_OBJECT
public:
    explicit SerialManager(QObject *parent = nullptr);
    ~SerialManager() override;

    bool open(const QString &port, qint32 baud);
    void close();
    bool isOpen() const;
    QString errorString() const;
    QStringList availablePorts() const;

signals:
    void telemetryReceived(const lgs::TelemetryData &data);
    void linkStatusChanged(bool connected);
    void errorOccurred(const QString &msg);

private slots:
    void onReadyRead();
    void onError(QSerialPort::SerialPortError err);

private:
    QSerialPort serial_;
    FrameParser *parser_;
};

} // namespace lgs

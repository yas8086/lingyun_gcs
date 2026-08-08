#include "comms/serial_manager.h"
#include "comms/frame_parser.h"
#include "comms/json_decoder.h"
#include <QSerialPortInfo>

namespace lgs {

SerialManager::SerialManager(QObject *parent)
    : QObject(parent), parser_(new FrameParser) {
    connect(&serial_, &QSerialPort::readyRead, this, &SerialManager::onReadyRead);
    connect(&serial_, &QSerialPort::errorOccurred, this, &SerialManager::onError);
}

SerialManager::~SerialManager() {
    close();
    delete parser_;
}

bool SerialManager::open(const QString &port, qint32 baud) {
    if (serial_.isOpen())
        this->close(); // 触发 linkStatusChanged(false)，避免状态灯失真
    delete parser_;
    parser_ = new FrameParser; // 重新打开时清空旧缓冲
    serial_.setPortName(port);
    serial_.setBaudRate(baud);
    serial_.setDataBits(QSerialPort::Data8);
    serial_.setParity(QSerialPort::NoParity);
    serial_.setStopBits(QSerialPort::OneStop);
    serial_.setFlowControl(QSerialPort::NoFlowControl);
    if (!serial_.open(QIODevice::ReadOnly)) {
        emit errorOccurred(serial_.errorString());
        return false;
    }
    emit linkStatusChanged(true);
    return true;
}

void SerialManager::close() {
    if (serial_.isOpen()) {
        serial_.close();
        emit linkStatusChanged(false);
    }
}

bool SerialManager::isOpen() const {
    return serial_.isOpen();
}

QString SerialManager::errorString() const {
    return serial_.errorString();
}

QStringList SerialManager::availablePorts() const {
    QStringList ports;
    const auto infos = QSerialPortInfo::availablePorts();
    for (const auto &info : infos)
        ports << info.portName();
    return ports;
}

void SerialManager::onReadyRead() {
    parser_->push(serial_.readAll());
    QByteArray json;
    while (parser_->takeFrame(json)) {
        TelemetryData data;
        if (decodeJson(json, data))
            emit telemetryReceived(data);
    }
}

void SerialManager::onError(QSerialPort::SerialPortError err) {
    if (err == QSerialPort::ResourceError) {
        emit errorOccurred(serial_.errorString());
        emit linkStatusChanged(false);
    }
}

} // namespace lgs

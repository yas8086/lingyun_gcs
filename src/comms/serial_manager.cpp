#include "comms/serial_manager.h"
#include "comms/frame_parser.h"
#include "comms/json_decoder.h"
#include <QSerialPortInfo>

namespace lgs {

SerialManager::SerialManager(QObject *parent)
    : QObject(parent)
    , serial_(new QSerialPort(this))          // child：随 moveToThread 递归迁移
    , parser_(std::make_unique<FrameParser>())
    , watchdog_(new QTimer(this)) {           // child：同上
    connect(serial_, &QSerialPort::readyRead, this, &SerialManager::onReadyRead);
    connect(serial_, &QSerialPort::errorOccurred, this, &SerialManager::onError);
    // 链路超时看门狗：周期检查，超时未收到数据判定链路停滞
    watchdog_->setInterval(500);
    watchdog_->setSingleShot(false);
    connect(watchdog_, &QTimer::timeout, this, &SerialManager::onLinkWatchdog);
    // ResourceError 自动重连：2s 周期尝试重新 open 同一端口（见 onError）
    reopenTimer_ = new QTimer(this);
    reopenTimer_->setInterval(2000);
    reopenTimer_->setSingleShot(false);
    connect(reopenTimer_, &QTimer::timeout, this, &SerialManager::tryReopen);
}

SerialManager::~SerialManager() {
    close();
}

bool SerialManager::open(const QString &port, qint32 baud) {
    reopenTimer_->stop(); // 手动打开时取消自动重连
    if (serial_->isOpen())
        this->close(); // 触发 linkStatusChanged(false)，避免状态灯失真
    parser_ = std::make_unique<FrameParser>(); // 重新打开时清空旧缓冲
    serial_->setPortName(port);
    serial_->setBaudRate(baud);
    serial_->setDataBits(QSerialPort::Data8);
    serial_->setParity(QSerialPort::NoParity);
    serial_->setStopBits(QSerialPort::OneStop);
    serial_->setFlowControl(QSerialPort::NoFlowControl);
    if (!serial_->open(QIODevice::ReadOnly)) {
        // 记录失败原因（含 QSerialPort 锁冲突/权限/设备不存在等），供 QML 透出
        lastOpenError_ = serial_->errorString();
        emit errorOccurred(lastOpenError_);
        return false;
    }
    lastOpenError_.clear();
    reopenPort_ = port;      // 记录当前端口，供 ResourceError 自动重连复用
    reopenBaud_ = baud;
    linkOnline_ = true;
    rxClock_.start();
    watchdog_->start();
    emit linkStatusChanged(true);
    return true;
}

void SerialManager::close() {
    reopenTimer_->stop(); // 手动关闭后不再自动重连
    watchdog_->stop();
    linkOnline_ = false;
    if (serial_->isOpen()) {
        serial_->close();
        emit linkStatusChanged(false);
    }
}

void SerialManager::setLinkTimeoutMs(int ms) {
    linkTimeoutMs_ = qMax(200, ms);
}

bool SerialManager::isOpen() const {
    return serial_->isOpen();
}

QString SerialManager::errorString() const {
    return serial_->errorString();
}

QString SerialManager::lastOpenError() const {
    return lastOpenError_;
}

QStringList SerialManager::availablePorts() const {
    QStringList ports;
    const auto infos = QSerialPortInfo::availablePorts();
    for (const auto &info : infos)
        ports << info.portName();
    return ports;
}

void SerialManager::onReadyRead() {
    parser_->push(serial_->readAll());
    QByteArray json;
    bool gotFrame = false;
    while (parser_->takeFrame(json)) {
        gotFrame = true;
        // 记录完整原始帧：AA55 帧头 + JSON + 换行（保留原始报文用于回放/复现）
        emit rawFrameReceived(kFrameHead + json + "\n");
        TelemetryData data;
        if (decodeJson(json, data))
            emit telemetryReceived(data);
    }
    if (gotFrame) {
        rxClock_.restart(); // 收到有效帧即重置超时计时
        if (!linkOnline_) {
            linkOnline_ = true;
            emit linkStatusChanged(true); // 链路恢复
        }
    }
}

void SerialManager::onError(QSerialPort::SerialPortError err) {
    if (err == QSerialPort::NoError)
        return;
    // 统一记录日志；断开类错误额外置离线
    qWarning("SerialManager: 串口错误 %d: %s", int(err),
             qPrintable(serial_->errorString()));
    if (err == QSerialPort::ResourceError) {
        emit errorOccurred(serial_->errorString());
        emit linkStatusChanged(false);
        // ResourceError（设备拔出/锁冲突）：关闭失效句柄，等待端口恢复后自动重连。
        // Qt 的 QSerialPort 在此错误后内部句柄已失效，必须 close 才能重新 open。
        if (serial_->isOpen())
            serial_->close();
        if (!reopenPort_.isEmpty())
            reopenTimer_->start(); // 2s 后尝试重新 open
    }
}

// ResourceError 自动重连：周期尝试重新打开同一端口，成功则停止重试
void SerialManager::tryReopen() {
    if (serial_->isOpen()) {
        reopenTimer_->stop();
        return;
    }
    qWarning("SerialManager: 尝试自动重连 %s", qPrintable(reopenPort_));
    if (open(reopenPort_, reopenBaud_)) {
        reopenTimer_->stop(); // open() 内已 stop，此处为保险
    }
}

void SerialManager::onLinkWatchdog() {
    if (!serial_->isOpen() || !linkOnline_)
        return;
    if (rxClock_.elapsed() >= linkTimeoutMs_) {
        linkOnline_ = false;
        emit linkStatusChanged(false); // 长时间无数据，链路停滞，置离线
    }
}

} // namespace lgs

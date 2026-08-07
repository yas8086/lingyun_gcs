#include "ui/serial_config_dialog.h"
#include <QComboBox>
#include <QFormLayout>
#include <QDialogButtonBox>

namespace lgs {

SerialConfigDialog::SerialConfigDialog(const QStringList &ports,
                                       const QString &curPort, qint32 curBaud,
                                       QWidget *parent)
    : QDialog(parent) {
    setWindowTitle("串口配置");
    auto *form = new QFormLayout(this);

    portBox_ = new QComboBox(this);
    portBox_->addItems(ports);
    if (!curPort.isEmpty()) {
        const int idx = ports.indexOf(curPort);
        if (idx >= 0)
            portBox_->setCurrentIndex(idx);
    }
    baudBox_ = new QComboBox(this);
    for (const auto b : {9600, 19200, 38400, 57600, 115200, 230400})
        baudBox_->addItem(QString::number(b), b);
    const int baudIdx = baudBox_->findData(curBaud);
    if (baudIdx >= 0)
        baudBox_->setCurrentIndex(baudIdx);

    form->addRow("端口", portBox_);
    form->addRow("波特率", baudBox_);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    form->addRow(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
}

SerialConfigDialog::Result SerialConfigDialog::getResult(
    QWidget *parent, const QStringList &ports, const QString &curPort, qint32 curBaud) {
    SerialConfigDialog dlg(ports, curPort, curBaud, parent);
    Result r;
    if (dlg.exec() != QDialog::Accepted)
        return r;
    r.ok = true;
    r.port = dlg.portBox_->currentText();
    r.baud = dlg.baudBox_->currentData().toInt();
    return r;
}

} // namespace lgs

#pragma once
#include <QDialog>
#include <QString>

class QComboBox;

namespace lgs {

class SerialConfigDialog : public QDialog {
    Q_OBJECT
public:
    struct Result { bool ok = false; QString port; qint32 baud = 115200; };

    SerialConfigDialog(const QStringList &ports, const QString &curPort,
                       qint32 curBaud, QWidget *parent = nullptr);

    static Result getResult(QWidget *parent, const QStringList &ports,
                            const QString &curPort, qint32 curBaud);

private:
    QComboBox *portBox_ = nullptr;
    QComboBox *baudBox_ = nullptr;
};

} // namespace lgs

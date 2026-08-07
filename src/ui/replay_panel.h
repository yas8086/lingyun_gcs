#pragma once
#include <QWidget>
#include <QString>

class QLineEdit;

namespace lgs {

class ReplayPanel : public QWidget {
    Q_OBJECT
public:
    explicit ReplayPanel(QWidget *parent = nullptr);

signals:
    void fileSelected(const QString &path);
    void startReplay();
    void stopReplay();
    void speedChanged(double x);

private:
    void chooseFile();

    QLineEdit *pathEdit_ = nullptr;
};

} // namespace lgs

#pragma once
#include <QWidget>

class QPlainTextEdit;

namespace lgs {

class LogPanel : public QWidget {
    Q_OBJECT
public:
    explicit LogPanel(QWidget *parent = nullptr);
    void append(const QString &msg);

private:
    QPlainTextEdit *view_ = nullptr;
};

} // namespace lgs

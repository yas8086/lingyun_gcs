#include "ui/log_panel.h"
#include <QPlainTextEdit>
#include <QVBoxLayout>
#include <QDateTime>

namespace lgs {

LogPanel::LogPanel(QWidget *parent) : QWidget(parent) {
    auto *lay = new QVBoxLayout(this);
    view_ = new QPlainTextEdit(this);
    view_->setReadOnly(true);
    lay->addWidget(view_);
}

void LogPanel::append(const QString &msg) {
    view_->appendPlainText(
        QDateTime::currentDateTime().toString("HH:mm:ss") + " " + msg);
}

} // namespace lgs

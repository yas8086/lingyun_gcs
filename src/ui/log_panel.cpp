#include "ui/log_panel.h"
#include <QPlainTextEdit>
#include <QVBoxLayout>
#include <QDateTime>
#include <QTextDocument>

namespace lgs {

LogPanel::LogPanel(QWidget *parent) : QWidget(parent) {
    auto *lay = new QVBoxLayout(this);
    view_ = new QPlainTextEdit(this);
    view_->setReadOnly(true);
    // 限制日志最大条数，防止长时间运行内存无限增长
    view_->document()->setMaximumBlockCount(10000);
    lay->addWidget(view_);
}

void LogPanel::append(const QString &msg) {
    view_->appendPlainText(
        QDateTime::currentDateTime().toString("HH:mm:ss") + " " + msg);
}

} // namespace lgs

#include "ui/alarm_panel.h"
#include <QTableWidget>
#include <QVBoxLayout>
#include <QHeaderView>
#include <QTime>

namespace lgs {

AlarmPanel::AlarmPanel(QWidget *parent) : QWidget(parent) {
    auto *lay = new QVBoxLayout(this);
    table_ = new QTableWidget(0, 3, this);
    table_->setHorizontalHeaderLabels({"时间", "级别", "内容"});
    table_->horizontalHeader()->setStretchLastSection(true);
    lay->addWidget(table_);
}

void AlarmPanel::onAlarm(const lgs::AlarmEvent &e) {
    const int row = table_->rowCount();
    table_->insertRow(row);
    auto levelText = [](lgs::AlarmEvent::Level l) {
        return l == lgs::AlarmEvent::Critical ? "严重"
               : l == lgs::AlarmEvent::Warn ? "告警" : "提示";
    };
    table_->setItem(row, 0, new QTableWidgetItem(QTime::currentTime().toString("HH:mm:ss")));
    table_->setItem(row, 1, new QTableWidgetItem(levelText(e.level)));
    table_->setItem(row, 2, new QTableWidgetItem(e.message));
}

void AlarmPanel::onCleared(const QString &id) {
    Q_UNUSED(id); // 简化：不做行级清除
}

} // namespace lgs

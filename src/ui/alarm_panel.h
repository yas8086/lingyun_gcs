#pragma once
#include <QWidget>
#include "core/alarm_engine.h"

class QTableWidget;

namespace lgs {

class AlarmPanel : public QWidget {
    Q_OBJECT
public:
    explicit AlarmPanel(QWidget *parent = nullptr);
    void onAlarm(const lgs::AlarmEvent &e);
    void onCleared(const QString &id);

private:
    QTableWidget *table_ = nullptr;
};

} // namespace lgs

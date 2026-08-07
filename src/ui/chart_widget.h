#pragma once
#include <QWidget>
#include <QStringList>
#include "model/telemetry_data.h"

class QComboBox;
class QCustomPlot;

namespace lgs {

// QCustomPlot 实时曲线：可选择监控参数
class ChartWidget : public QWidget {
    Q_OBJECT
public:
    explicit ChartWidget(QWidget *parent = nullptr);

    void onTelemetry(const lgs::TelemetryData &data);

private:
    double valueOf(int idx, const lgs::TelemetryData &d) const;
    void refresh();

    QCustomPlot *plot_ = nullptr;
    QComboBox *paramBox_ = nullptr;
    QStringList paramNames_;
    QVector<QVector<double>> x_;
    QVector<QVector<double>> y_;
    int window_ = 600; // 保留最近 600 点
};

} // namespace lgs

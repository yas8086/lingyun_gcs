#include "ui/chart_widget.h"
#include "qcustomplot.h"
#include <QVBoxLayout>
#include <QComboBox>
#include <QHBoxLayout>
#include <QLabel>

namespace lgs {

ChartWidget::ChartWidget(QWidget *parent) : QWidget(parent) {
    auto *lay = new QVBoxLayout(this);

    auto *top = new QHBoxLayout;
    top->addWidget(new QLabel("参数:", this));
    paramBox_ = new QComboBox(this);
    paramNames_ = {"BMS SOC(%)", "BMS 总压(V)", "MPPT 功率(W)",
                   "DCDC 输出功率(W)", "DCDC 温度(℃)"};
    paramBox_->addItems(paramNames_);
    top->addWidget(paramBox_);
    top->addStretch();
    lay->addLayout(top);

    plot_ = new QCustomPlot(this);
    plot_->addGraph();
    plot_->graph(0)->setPen(QPen(Qt::blue));
    plot_->xAxis->setLabel("采样点");
    plot_->yAxis->setLabel(paramNames_.first());
    plot_->rescaleAxes();
    lay->addWidget(plot_);

    x_.resize(paramNames_.size());
    y_.resize(paramNames_.size());

    connect(paramBox_, &QComboBox::currentIndexChanged,
            this, &ChartWidget::refresh);
}

double ChartWidget::valueOf(int idx, const lgs::TelemetryData &d) const {
    switch (idx) {
    case 0: return d.bms ? d.bms->soc : 0.0;
    case 1: return d.bms ? d.bms->pack_v : 0.0;
    case 2: return d.mppt ? d.mppt->pv_p : 0.0;
    case 3: return d.dcdc ? d.dcdc->out_p : 0.0;
    case 4: return d.dcdc ? d.dcdc->temp : 0.0;
    default: return 0.0;
    }
}

void ChartWidget::onTelemetry(const lgs::TelemetryData &data) {
    static int counter = 0;
    for (int i = 0; i < paramNames_.size(); ++i) {
        x_[i].append(counter);
        y_[i].append(valueOf(i, data));
        if (x_[i].size() > window_)
            x_[i].remove(0, x_[i].size() - window_);
        if (y_[i].size() > window_)
            y_[i].remove(0, y_[i].size() - window_);
    }
    counter++;
    refresh();
}

void ChartWidget::refresh() {
    if (!plot_)
        return;
    const int idx = paramBox_->currentIndex();
    plot_->graph(0)->setData(x_[idx], y_[idx]);
    plot_->yAxis->setLabel(paramNames_.at(idx));
    plot_->rescaleAxes();
    plot_->replot();
}

} // namespace lgs

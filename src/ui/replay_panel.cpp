#include "ui/replay_panel.h"
#include <QPushButton>
#include <QHBoxLayout>
#include <QFileDialog>
#include <QLineEdit>
#include <QDoubleSpinBox>
#include <QLabel>

namespace lgs {

ReplayPanel::ReplayPanel(QWidget *parent) : QWidget(parent) {
    auto *lay = new QHBoxLayout(this);

    pathEdit_ = new QLineEdit(this);
    pathEdit_->setReadOnly(true);
    auto *pickBtn = new QPushButton("选择CSV", this);
    auto *startBtn = new QPushButton("开始", this);
    auto *stopBtn = new QPushButton("停止", this);
    auto *speedSpin = new QDoubleSpinBox(this);
    speedSpin->setRange(0.1, 10.0);
    speedSpin->setValue(1.0);
    speedSpin->setSuffix("x");

    lay->addWidget(pathEdit_, 1);
    lay->addWidget(pickBtn);
    lay->addWidget(startBtn);
    lay->addWidget(stopBtn);
    lay->addWidget(new QLabel("速度:", this));
    lay->addWidget(speedSpin);

    connect(pickBtn, &QPushButton::clicked, this, &ReplayPanel::chooseFile);
    connect(startBtn, &QPushButton::clicked, this, &ReplayPanel::startReplay);
    connect(stopBtn, &QPushButton::clicked, this, &ReplayPanel::stopReplay);
    connect(speedSpin, QOverload<double>::of(&QDoubleSpinBox::valueChanged),
            this, &ReplayPanel::speedChanged);
}

void ReplayPanel::chooseFile() {
    const QString path = QFileDialog::getOpenFileName(this, "选择CSV记录", QString(), "CSV (*.csv)");
    if (!path.isEmpty()) {
        pathEdit_->setText(path);
        emit fileSelected(path);
    }
}

} // namespace lgs

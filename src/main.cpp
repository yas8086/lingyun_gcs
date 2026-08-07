#include <QApplication>
#include "ui/main_window.h"

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QCoreApplication::setOrganizationName("LingYun");
    QCoreApplication::setApplicationName("GroundStation");

    lgs::MainWindow w;
    w.show();
    return app.exec();
}

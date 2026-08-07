#include <QApplication>
#include <QMessageBox>

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QMessageBox::information(nullptr, "地面站",
                             "灵云01号飞艇地面站（脚手架阶段）");
    return app.exec();
}

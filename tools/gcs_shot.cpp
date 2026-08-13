#include <QGuiApplication>
#include <QScreen>
#include <QPixmap>
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QScreen *s = QGuiApplication::primaryScreen();
    QPixmap pm = s->grabWindow(0);
    pm.save("/home/hex/LINGYUN/Projects/lingyun_gcs/tools/gcs_shot.png");
    return 0;
}
#include <QtTest>
#include "comms/frame_parser.h"

using namespace lgs;

class TestFrameParser : public QObject {
    Q_OBJECT
private slots:
    void parsesSingleFrame() {
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("\xAA\x55{\"t\":1}\n", 10));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":1}"));
    }

    void handlesFragmented() {
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("\xAA\x55{\"t\"", 6));
        QVERIFY(!p.takeFrame(json));
        p.push(QByteArray(":2}\n", 4));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":2}"));
    }

    void discardsGarbageBeforeHeader() {
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("xxxx\xAA\x55{\"t\":3}\n", 14));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":3}"));
    }

    void parsesTwoFrames() {
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("\xAA\x55{\"t\":1}\n\xAA\x55{\"t\":2}\n", 20));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":1}"));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":2}"));
    }
};

QTEST_MAIN(TestFrameParser)
#include "test_frame_parser.moc"

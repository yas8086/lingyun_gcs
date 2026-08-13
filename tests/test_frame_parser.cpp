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

    void noTailMeansIncomplete() {
        // 无帧尾 \n：帧未收完，不应取出
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("\xAA\x55{\"t\":3}"));
        QVERIFY(!p.takeFrame(json));
        // 补上帧尾后应能取出
        p.push(QByteArray("\n", 1));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":3}"));
    }

    void emptyJsonFrame() {
        // 帧头后立即换行：空 JSON
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("\xAA\x55\n", 3));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray(""));
    }

    void garbageBetweenFrames() {
        // 两帧之间夹杂杂散字节，应丢弃并继续正确取帧
        FrameParser p;
        QByteArray json;
        p.push(QByteArray("\xAA\x55{\"t\":1}\nxx\xAA\x55{\"t\":2}\n", 22));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":1}"));
        QVERIFY(p.takeFrame(json));
        QCOMPARE(json, QByteArray("{\"t\":2}"));
    }

    void emptyInput() {
        FrameParser p;
        QByteArray json;
        p.push(QByteArray());
        QVERIFY(!p.takeFrame(json));
    }
};

QTEST_MAIN(TestFrameParser)
#include "test_frame_parser.moc"

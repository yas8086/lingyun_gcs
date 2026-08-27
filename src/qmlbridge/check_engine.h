#pragma once

// 自检引擎（对齐原型 airship-gcs-prototype.html 自检模块 JS ≈ L1835-2010）：
// 11 项预置 + 自定义项动态增删 + 三态判定（pass/fail/skip）+ 参数可编辑持久化，
// 聚合整机就绪度（0 失败=就绪可飞 / 1=受限 / ≥2=不可起飞）供监控页横幅与明细浮层。
// 设计依据：docs/ui-prototype/自检页面落地设计.md（§4 数据模型 / §5 编辑校验 / §6 聚合）。
// 取值走 TelemetryBridge 实时值（NaN→fail 显示"—"，数据缺失也是失败）。

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>

namespace lgs {

class TelemetryBridge;

class CheckEngine : public QObject {
    Q_OBJECT
    // 全量条目（内置 11 + 自定义项，含运行结果 st/val/custh 等渲染字段）
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    // 就绪度：0 待自检 / 1 就绪可飞 / 2 起飞受限 / 3 不可起飞（语义与旧 bridge.readinessState 一致）
    Q_PROPERTY(int readyLevel READ readyLevel NOTIFY readinessChanged)
    // 最近一轮启用项失败数
    Q_PROPERTY(int failCount READ failCount NOTIFY readinessChanged)
    // 是否已跑过至少一轮（"待自检"态判定）
    Q_PROPERTY(bool checkedOnce READ checkedOnce NOTIFY readinessChanged)

public:
    explicit CheckEngine(TelemetryBridge *bridge, QObject *parent = nullptr);

    QVariantList items() const { return items_; }
    int readyLevel() const { return readyLevel_; }
    int failCount() const { return failCount_; }
    bool checkedOnce() const { return checkedOnce_; }

    // 跑一轮全部检查项（判定 + 渲染字段刷新 + 就绪度聚合 + itemsChanged/readinessChanged）
    Q_INVOKABLE void runAll();
    // 最近一轮启用项结果（明细浮层消费）：[{dev,name,pass,val}]
    Q_INVOKABLE QVariantList checkState() const { return checkState_; }
    // 编辑保存：按 id 定位写入 patch（仅写 patch 内字段，隐藏字段不污染——对齐原型 ckSave）
    Q_INVOKABLE void setItem(const QString &id, const QVariantMap &patch);
    // 新增自定义项：生成 ck_+时间戳唯一 id，追加列表尾部，返回新 id
    Q_INVOKABLE QString addItem(const QVariantMap &def);
    // 删除自定义项（仅 custom 项可删，内置项忽略）
    Q_INVOKABLE void removeItem(const QString &id);
    // 阈值徽章文本（对齐原型 ckThText：range "min~max unit" / single "符号 val unit" / none 空）
    Q_INVOKABLE QString thText(const QVariantMap &def) const;
    // 当前值格式化（对齐原型 ckFmt：%取整 / V且|v|<1 两位小数 / 其余一位小数+单位）
    Q_INVOKABLE QString fmtVal(const QVariantMap &def, double v) const;

signals:
    void itemsChanged();
    void readinessChanged();

private:
    // 加载合并（对齐原型 loadCheckCfg）：内置逐 id 用存储覆盖；未知识 id 追加为自定义项
    void loadCfg();
    void saveCfg();
    // 单项判定（对齐原型 ckEval）：返回 {ok(bool/null=skip), val(显示文本)}
    QVariantMap eval(const QVariantMap &def) const;
    // 设备显示名 → bridge 设备键（内置 MPPT→mppt1；自定义取 dev 小写）
    QString devKeyOf(const QString &dev) const;

    TelemetryBridge *bridge_;
    QVariantList items_;        // 配置条目（defs 含 custom 标记）
    QVariantList checkState_;   // 最近一轮启用项结果 {dev,name,pass,val}（明细浮层消费）
    int readyLevel_ = 0;
    int failCount_ = 0;
    bool checkedOnce_ = false;
};

} // namespace lgs

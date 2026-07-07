# M4-5 货币换算展示设计

日期：2026-07-07

## 背景

M4-5 承接 `docs/tcg-card/05-plan/dev-plan.md` 的「货币换算展示」任务。当前 Home 内部已有临时 USD/CNY/JPY 换算，Collection 仍固定 USD。PRD 要求默认 USD，切换货币后金额字段跟随换算，百分比不随货币变化。

## 方案

采用 Flutter 本地 shared currency 工具和 mock rates：

- 新增 `apps/flutter-app/lib/shared/currency/currency.dart`，集中定义支持币种、mock rates、金额格式化和全局选中币种 provider。
- Home 移除本地汇率和符号分支，改为读取 shared provider。
- Collection 读取同一 shared provider，金额汇总和列表价格跟随 Home 的货币选择。
- CardDetail 尚未进入 M5 实现，本任务只提供共享工具，后续 M5 直接复用，不提前创建页面。

## 范围

交付内容：

- 支持 PRD 币种：USD、EUR、JPY、GBP、CAD、AUD、NZD、SGD。
- 金额默认保留两位小数、使用千分位。
- 负数金额保持负号在货币符号之前。
- 缺失金额显示 `--`。
- 隐藏金额仍显示统一隐藏文案。
- Home / Collection 使用同一当前币种。
- 百分比保持 M4-4 的原始 USD/previous 公式结果，不随币种变化。

非目标：

- 不接真实第三方汇率提供方。
- 不修改 Workers API、schema、migration、wrangler 或 drizzle 配置。
- 不修改 `docs/tcg-card/**`。
- 不实现 CardDetail。
- 不实现 M4-6 loading/failure、M4-7 Toast、M7/admin。

## 验收

- `currency_test.dart` 覆盖 mock rates、金额格式、缺失值、负数、隐藏金额。
- Home controller/widget 测试证明 EUR 等 PRD 币种可选，金额换算且百分比不变。
- Collection controller/widget 测试证明读取同一币种并换算总值和列表金额。
- 全量 Flutter 测试、`flutter analyze`、format check 通过。

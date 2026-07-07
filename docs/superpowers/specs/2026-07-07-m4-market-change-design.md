# M4-4 涨跌算法设计

日期：2026-07-07

## 背景

本设计承接 `docs/tcg-card/05-plan/dev-plan.md` 中的 M4-4「涨跌算法实现」。M4-1 Home、M4-2 Collection、M4-3 Search 已有 mock 展示，但涨跌百分比目前分散在各模块本地字段或 formatter 中。M4-4 的目标是把公式和降级口径统一到 Flutter 本地共享工具，并让现有三个页面使用同一套算法。

本轮约束：

- 不修改 `docs/tcg-card/**`。
- 不修改 Workers schema、migration、`wrangler.toml` 或 `drizzle.config.ts`。
- 不修改 `apps/admin-web`、Admin API 或 M7 范围。
- 不接真实第三方数据，不改缓存和接口。
- 不做货币换算展示，M4-5 单独处理。

## 推荐方案

可选方案：

1. 继续在各页面存储并展示预计算百分比。
   - 优点：改动最少。
   - 缺点：无法证明 `global-rules.md` 公式已实现，也容易继续出现一位/两位小数不一致。

2. 在后端数据代理层计算涨跌并返回给 Flutter。
   - 优点：未来真实数据更集中。
   - 缺点：本任务会牵涉 Workers API 与第三方数据口径，超出 M4 Flutter 页面阶段。

3. 在 Flutter 新增共享 market change 工具，mock 数据提供当前价和周期起点价，页面统一调用工具展示。
   - 优点：能以 TDD 验证公式、降级、数量口径和格式化；改动局部，后续真实 API 只需提供同等字段。
   - 缺点：暂时仍是客户端 mock 计算。

采用方案 3。

## 范围

M4-4 交付内容：

1. 新增 Flutter 共享工具 `apps/flutter-app/lib/shared/market/market_change.dart`。
2. 提供单卡涨跌计算：`(current - previous) / previous * 100%`。
3. 提供 Collection Item 当前价值与涨跌金额计算：当前价值 = 当前市场价 × quantity；涨跌金额 = (当前价 - previous) × quantity；百分比仍按单张价格计算。
4. 处理降级：
   - 当前价缺失、0、负数：价格/金额展示 `--`，百分比展示 `-/-`。
   - 周期起点价缺失、0、负数：涨跌金额展示 `--`，百分比展示 `-/-`。
5. 百分比展示默认 2 位小数。
6. 绝对值小于 `0.01%` 且不为 0 时展示 `<0.01%` 或 `-<0.01%`。
7. Home、Collection、Search 当前 mock 数据改为提供 previous 价格/价值，并统一调用该工具。

## 非目标

- 不接真实价格序列 API。
- 不实现 7D/3M/6M UI 切换。
- 不实现 M4-5 货币换算。
- 不实现 M5 CardDetail Price Tab。
- 不实现 M4-6 加载/失败状态或 M4-7 Toast。
- 不改任何后台或数据库文件。

## 模块结构

新增：

- `apps/flutter-app/lib/shared/market/market_change.dart`
- `apps/flutter-app/test/market_change_test.dart`

修改：

- `apps/flutter-app/lib/features/home/home_models.dart`
- `apps/flutter-app/lib/features/home/home_repository.dart`
- `apps/flutter-app/lib/features/home/home_controller.dart`
- `apps/flutter-app/lib/features/home/home_page.dart`
- `apps/flutter-app/test/home_controller_test.dart`
- `apps/flutter-app/test/widget/home_page_test.dart`
- `apps/flutter-app/lib/features/collection/collection_models.dart`
- `apps/flutter-app/lib/features/collection/collection_repository.dart`
- `apps/flutter-app/lib/features/collection/collection_controller.dart`
- `apps/flutter-app/test/collection_controller_test.dart`
- `apps/flutter-app/test/widget/collection_page_test.dart`
- `apps/flutter-app/lib/features/search/search_models.dart`
- `apps/flutter-app/lib/features/search/search_repository.dart`
- `apps/flutter-app/test/search_controller_test.dart`
- `apps/flutter-app/test/widget/search_page_test.dart`

## 数据模型调整

Home：

- `HomePortfolio` 增加 `previous30dValueUsd`。
- `HomeHighlightCard` 和 `TrendingCard` 增加 `previousPriceUsd`。
- `HomeState.changeAmountText` 和 `changePercentText` 由共享工具派生。

Collection：

- `CollectionItem` 将 `change30dPercent` 替换为 `previous30dPriceUsd`。
- `CollectionState` 用共享工具计算 `CollectionViewItem.changeText`。

Search：

- `SearchCard` 将 `change30dPercent` 替换为 `previous30dPriceUsd`。
- `SearchCard.changeText` 用共享工具计算。

## 测试策略

按 TDD 推进：

- 先为 `MarketChange` 写公式、降级、微小涨跌和 quantity 测试。
- 再更新 Home controller/widget 测试，证明 Home 从 previous 值计算涨跌。
- 再更新 Collection/Search 测试，证明百分比统一为两位小数和降级口径。
- 最后跑 affected tests、全量 `dart run melos run test`、`flutter analyze`、格式检查。

## 验收

M4-4 完成时应满足：

- `market_change_test.dart` 覆盖公式、除零、负价、缺价、微小涨跌、quantity 口径。
- Home 30D 金额和百分比由当前值与 previous 值计算。
- Collection/Search 的 30D Change 统一两位小数。
- 缺价/缺 previous 的卡展示 `--` 与 `-/-`。
- 不触碰 `docs/tcg-card/**`、Workers schema/migrations/config、Admin/M7。
- Flutter 测试、分析和格式检查通过。

## 冲突与边界选择

- `global-rules.md` 提到 7D、30D、3M、6M 等周期，但当前 Home/Collection/Search 已实现界面只展示 30D 或既有 mock 周期；本任务实现通用 current/previous 公式，不新增周期 UI。
- Search 只展示百分比，不展示涨跌金额；工具会支持金额，但 Search UI 仍只用百分比。
- Home 当前总资产为 0 的完整图表口径后续可继续完善；本任务先覆盖除零和展示降级，不扩展图表行为。

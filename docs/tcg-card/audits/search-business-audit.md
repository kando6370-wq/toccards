# Search 业务审计

## 0. 文档说明

- 分析范围：Flutter Search 页面、Card Data/Portfolio API、Workers 卡牌与系列路由、生产 D1 返回。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`；本地视觉对照为 `source-tcg-card-docs/ui/search/`。
- 产品规则：`00-product/modules/search.md` 与 `source-tcg-card-docs/search.md`。
- 证据口径：只采用可执行代码、自动化测试、生产 API 和部署结果；不以进度文档的完成标记为证据。
- 审计日期：2026-07-17。

## 1. 业务总览与主线

Search 的闭环是：加载真实卡牌目录和当前文件夹资产状态 -> 按 Game 浏览或分别搜索 Cards/Sets -> 打开 Card Detail，或快捷加入当前 Portfolio/Wishlist -> Collection、Home 与 Card Detail 消费同一份服务端资产状态。

| 模块 | 真实接口 | 当前结论 |
|---|---|---|
| Cards 默认列表 | `GET /cards/trending` | 真实 D1 数据 |
| Cards 浏览/搜索 | `GET /cards/search?q=&game=` | 真实 D1 数据，服务端按 Game 精确过滤 |
| Sets 浏览/搜索 | `GET /sets/search?q=&game=` | 按 `game + set_code` 聚合并返回全库卡数 |
| Qty/Collected | `GET /portfolio/items`、Portfolio CRUD | 当前文件夹真实资产 |
| Wishlist | `GET /wishlist`、Wishlist CRUD | owner 级真实数据 |

## 2. 用户身份与数据隔离

游客和登录用户均可读取公开卡牌目录；Qty、Collected、Wishlist 和快捷写入必须携带当前匿名或用户会话。Workers 按 owner 校验 Portfolio/Wishlist，Flutter 页面可见性不是权限边界。未认证的资产请求返回 401。

## 3. 核心业务流程

1. Search 加载 Trending，使用第一条真实卡牌的 Game 查询默认 Sets。
2. Cards 与 Sets 各自保留搜索词和查询失败状态；切换 Tab 不覆盖或阻塞另一 Tab。
3. Game ID 由接口 `game` 统一归一化，Cards 与 Sets 使用同一规则，避免真实 Set 被前端过滤为空。
4. 输入清空时重新加载默认目录，并继续携带当前会话恢复 Qty/Wishlist。
5. Collect 写入当前选中文件夹；同卡存在多条 Collection Item 时进入详情管理，避免误删。
6. Collect 成功后自动移除 Wishlist，并刷新 Home、Collection 和 Card Detail 消费者。

异常规则：初始目录或资产加载失败时页面进入失败状态；后续 Cards/Sets 查询失败只在当前 Tab 显示重试，不得拖垮另一 Tab；价格缺失显示 `--`，30D 基准缺失显示 `-/-`；写入失败不得把本地状态伪装成成功。

## 4. 核心数据实体

| 实体 | 关键字段 | Search 用途 |
|---|---|---|
| `cards_all` | product_id、game、set_code、name、image_url | Cards、Sets 与 Game 来源 |
| `tcgplayer_skus` | product_id、price_history | 当前价与 30D 基准 |
| `portfolio_folder` | owner、id、is_default | 快捷 Collect 目标 |
| `collection_item` | folder_id、card_ref、quantity、状态字段 | Qty 与 Collected |
| `wishlist_item` | owner、card_ref | Wishlist 状态 |

## 5. 业务规则与计算

- Game ID：小写，并将非字母数字连续字符转换为 `-`；Cards 和 Sets 共用该规则。
- Set 唯一聚合键：`game + set_code`，不同 Game 的同代码系列不得合并。
- Qty：当前选中文件夹内同 card_ref 的 quantity 总和。
- 30D Change：`(current - previous30d) / previous30d * 100%`；不随货币切换变化。
- 快捷 Collect 默认：Quantity 1、Raw、TCG Condition 为 Near Mint、沿用卡牌 Language/Finish。

## 6. 上下游与影响面

| 依赖 | 方向 | 失败影响 |
|---|---|---|
| D1 卡牌/价格目录 | 上游 | Cards/Sets 为空或缺价 |
| Auth session | 上游 | 无法加载或写入资产状态 |
| Collection | 下游 | Collect/Wishlist 结果不可管理 |
| Home | 下游 | 新资产不能进入估值和 Most Valuable |
| Card Detail | 下游 | 卡片点击或多资产管理闭环中断 |
| Scan | 双向 | Scan 可转 Search 手工兜底，Search 相机入口可转 Scan |

## 7. 行业术语

| 术语 | 含义 |
|---|---|
| Game / IP | 卡牌所属游戏或知识产权，用作 Cards/Sets 共同范围 |
| Set | 同一 Game 下的系列，`set_code` 不能脱离 Game 单独作为全局标识 |
| Qty | 当前 Portfolio 文件夹中的持有数量，不包含 Wishlist |
| 30D Change | 当前市场价相对 30 天基准价的百分比变化 |

## 8. 证据索引

| 编号 | 文件/结果 | 说明 |
|---|---|---|
| E1 | `apps/flutter-app/lib/features/search/search_repository.dart` | 真实目录、Game 映射、资产写入 |
| E2 | `apps/flutter-app/lib/features/search/search_controller.dart` | Tab/Game、搜索和资产状态恢复 |
| E3 | `apps/flutter-app/lib/shared/card_data/card_data_api_client.dart` | Card/Set 接口契约 |
| E4 | `apps/workers-api/src/data-source/routes.ts` | Cards/Sets/Trending 路由 |
| E5 | `apps/flutter-app/test/search_controller_test.dart` | Search 业务意图与资产回归测试 |
| E6 | `apps/workers-api/src/data-source/routes.test.ts` | Game 精确过滤、空查询浏览与跨 Game 聚合测试 |
| E7 | Worker `83511391-d10a-41bd-af1b-34528fa0e45e` | 2026-07-17 当前生产部署 |
| E8 | `b21d7b8`、`272c053`、`8546b4e`、`7ca202e` | Workers Game/Set 聚合、Flutter Game 透传与 Tab 故障隔离 |

## 9. 待确认问题与上线边界

| 冲突/问题 | 当前决策 | 后续要求 |
|---|---|---|
| PRD/Figma 示例默认 Pokémon，生产目录当前主要为 Magic | 默认跟随真实 Trending 的首个 Game，保证 Cards/Sets 同时可见 | 补齐 Pokémon 生产数据后再确认固定默认值 |
| 本轮未取得可用 Figma 节点上下文 | 不改视觉结构，只修真实数据链路 | 上架截图前按可用节点重新做 iOS 视觉验收 |

## 10. 本轮验证记录

| 验证项 | 结果 |
|---|---|
| 生产 Cards/Sets Game 浏览 | `game=magic: the gathering` 仅返回 `Magic: The Gathering`；部分值 `Magic` 返回 0 |
| 生产 Set 完整计数 | `ECC` API `card_count: 176`，生产 D1 同条件 `COUNT(*): 176` |
| 生产图片代理 | `/cards/596128/image` 返回 `200 image/jpeg` |
| Workers 全量测试 | 26 个文件、242 项通过 |
| Workers 类型检查 | 通过 |
| Workers dry-run | 通过，绑定生产 D1、KV 与独立 Scan R2 |
| Flutter 全量测试 | 344 项通过、1 项原生 OpenCV 条件测试按既有环境跳过 |
| Flutter analyze | 无问题 |
| 分段提交 | `b21d7b8`、`272c053` Workers；`8546b4e`、`7ca202e` Flutter |

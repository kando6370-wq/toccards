# Search 业务审计

## 0. 文档说明

- 分析范围：Flutter Search 页面、Card Data/Portfolio API、Workers 卡牌与系列路由、生产 D1 返回。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`；本地视觉对照为 `source-tcg-card-docs/ui/search/`。
- 产品规则：`00-product/modules/search.md` 与 `source-tcg-card-docs/search.md`。
- 证据口径：只采用可执行代码、自动化测试、生产 API 和部署结果；不以进度文档的完成标记为证据。
- 审计日期：2026-07-17。

## 1. 业务总览与主线

Search 的闭环是：加载真实游戏与卡牌目录和当前文件夹资产状态 -> 按 Game 浏览或分别搜索 Cards/Sets -> 从 Set 进入按 `game + set_code` 分页的卡牌二级页 -> 打开 Card Detail，或快捷加入当前 Portfolio/Wishlist -> Collection、Home 与 Card Detail 消费同一份服务端资产状态。

| 模块 | 真实接口 | 当前结论 |
|---|---|---|
| Cards 默认列表 | `GET /cards/trending` | 真实 D1 数据 |
| Game 筛选 | `GET /games` | 读取 `games.load=1`，生产返回 8 个启用游戏 |
| Cards 浏览/搜索 | `GET /cards/search?q=&game=&set_code=` | 真实 D1 数据，服务端按 Game/Set 精确过滤 |
| Sets 浏览/搜索 | `GET /sets/search?q=&game=` | 读取真实 `sets` 表；封面由 `sets.set_image_id` 映射 R2 |
| Set 二级页 | `GET /cards/search?game=&set_code=&page=` | 不同 Set 使用独立 KV 缓存键并分页返回真实卡牌 |
| Qty/Collected | `GET /portfolio/items`、Portfolio CRUD | 当前文件夹真实资产 |
| Wishlist | `GET /wishlist`、Wishlist CRUD | owner 级真实数据 |

## 2. 用户身份与数据隔离

游客和登录用户均可读取公开卡牌目录；Qty、Collected、Wishlist 和快捷写入必须携带当前匿名或用户会话。Workers 按 owner 校验 Portfolio/Wishlist，Flutter 页面可见性不是权限边界。未认证的资产请求返回 401。

## 3. 核心业务流程

1. Search 从 `GET /games` 加载启用游戏，使用第一个真实游戏查询默认 Sets；Trending 只提供 Cards 内容，不再推导筛选项。
2. Cards 与 Sets 各自保留搜索词和查询失败状态；切换 Tab 不覆盖或阻塞另一 Tab。
3. Game ID 由接口 `game` 统一归一化，Cards 与 Sets 使用同一规则，避免真实 Set 被前端过滤为空。
4. 输入清空时重新加载默认目录，并继续携带当前会话恢复 Qty/Wishlist。
5. Collect 写入当前选中文件夹；同卡存在多条 Collection Item 时进入详情管理，避免误删。
6. Collect 成功后自动移除 Wishlist，并刷新 Home、Collection 和 Card Detail 消费者。
7. 点击 Set 时携带 `game + set_code` 进入二级页；分页失败重试同一页，不得跳页或复用其他 Set 缓存。

异常规则：初始目录或资产加载失败时页面进入失败状态；后续 Cards/Sets 查询失败只在当前 Tab 显示重试，不得拖垮另一 Tab；价格缺失显示 `--`，30D 基准缺失显示 `-/-`；写入失败不得把本地状态伪装成成功。

## 4. 核心数据实体

| 实体 | 关键字段 | Search 用途 |
|---|---|---|
| `games` | game_id、name、load | Game 筛选来源 |
| `sets` | game、name、set_code、set_image_id、total_cards | Set 列表、R2 封面与卡数来源 |
| `cards_all` | product_id、game、set_code、name、image_url | Cards 与 Set 二级页来源 |
| `tcgplayer_skus` | product_id、price_history | 当前价与 30D 基准 |
| `portfolio_folder` | owner、id、is_default | 快捷 Collect 目标 |
| `collection_item` | folder_id、card_ref、quantity、状态字段 | Qty 与 Collected |
| `wishlist_item` | owner、card_ref | Wishlist 状态 |

## 5. 业务规则与计算

- Game ID：小写，并将非字母数字连续字符转换为 `-`；Cards 和 Sets 共用该规则。
- Set 卡牌与缓存范围：`game + set_code`，不同 Game 或不同 Set 的卡牌不得合并或共享缓存。
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
| E3 | `apps/flutter-app/lib/shared/card_data/card_data_api_client.dart` | Game、Set、Set Cards 接口契约 |
| E4 | `apps/workers-api/src/data-source/routes.ts` | Cards/Sets/Trending 路由 |
| E5 | `apps/flutter-app/test/search_controller_test.dart` | Search 业务意图与资产回归测试 |
| E6 | `apps/workers-api/src/data-source/routes.test.ts`、`kv-cache.test.ts` | Game/Set 精确过滤、R2 封面与 Set 缓存隔离 |
| E7 | Worker `496065fb-5954-4700-b971-039973f043a9` | 2026-07-17 当前生产部署 |
| E8 | `da05a5d`、`f5c326c`、`1337abe`、`0140701`、`8810a08` | D1 目录、Flutter 二级页、API 契约、缓存隔离与冗余列迁移 |

## 9. 待确认问题与上线边界

| 冲突/问题 | 当前决策 | 后续要求 |
|---|---|---|
| PRD/Figma 示例默认 Pokémon，生产卡牌目录当前主要为 Magic | 默认跟随 `games.load=1` 的真实排序，保证 Cards/Sets 同时可见 | 补齐 Pokémon 卡牌数据后再确认固定默认值 |
| Web imperative `push` 已切换页面但地址栏仍保留 `#/search` | iOS 页面栈、返回和业务不受影响，本轮不改变路由模式 | 若 Web 需要可刷新深链，单独启用并回归 URL 反射 |

## 10. 本轮验证记录

| 验证项 | 结果 |
|---|---|
| 生产 Game/Set 浏览 | `/games` 返回 8 个启用游戏；Magic 返回 454 个有效 Set |
| 生产 Set 数据 | `sets` 共 4239 行，50 行已有 `set_image_id`；重复 `set_name` 已迁移删除，API 仍由 `name` 映射 `set_name` |
| 生产 Set 封面 | TMC 封面 `679068` 返回 `200 image/jpeg` |
| Set 二级页隔离 | FDN 返回 `695515/695516`，ECL 返回 `656658/668578`，卡牌无交集 |
| 390x844 真实串联 | Search Collect 后 HOME `$0.21`、Collection Qty 1；清理后 HOME `$0.00`、Collection 0 卡 |
| Workers 全量测试 | 28 个文件、251 项通过 |
| Workers 类型检查 | 通过 |
| Workers dry-run | 通过，绑定生产 D1、KV 与独立 Scan R2 |
| Flutter 全量测试 | 389 项通过、1 项原生 OpenCV 条件测试按既有环境跳过 |
| Flutter analyze | 无问题 |
| 分段提交 | `da05a5d` Workers；`f5c326c` Flutter；`1337abe` 契约测试；`0140701` 缓存；`8810a08` D1 迁移 |

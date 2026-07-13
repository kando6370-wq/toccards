# tcg-card 卡牌数据源接入

> **定位**：定义 tcg-card v1.0 的卡牌数据源接入口径，包括：本地 D1 卡牌基础表、可插拔适配层接口、字段映射、缓存策略、降级策略。默认数据源为当前项目 D1 中的 `cards_all` / `games` / `sets` / `tcgplayer_skus`，由外部采集程序写入。
> **日期**：2026-06-30
> **来源**：
> - Spec [`docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md`](../../superpowers/specs/2026-06-30-tcg-card-preparation-design.md) §4.2、§4.3、§6
> - 架构 [`docs/tcg-card/02-architecture/architecture.md`](../02-architecture/architecture.md) §2.2、§3、§5
> - 跨切面规则 [`docs/tcg-card/00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)

---

## 1. 设计原则

1. **当前 D1 为默认数据源**：卡牌目录与 SKU 价格历史来自同一个 D1 数据库中的 `cards_all`、`sets`、`games`、`tcgplayer_skus`。
2. **采集与读取分离**：外部采集程序负责写入/更新基础表；Workers 只读查询并向 App 暴露稳定 REST 契约。
3. **App 不直连采集源**：客户端只访问 Workers，不接触采集程序或采集侧凭证。
4. **覆盖层优先**：Workers 返回卡牌数据时，先读 D1 `card_override` 表，有覆盖字段则合并后返回，无覆盖则直接返回基础表数据（见数据模型 §6.1）。
5. **降级而不中断**：基础表查询或缓存失败时按端点返回空列表、空价格或 404，不向 App 抛出 500。

---

## 2. 可插拔适配层

### 2.1 DataSourceAdapter 接口

Workers 内部定义以下统一接口。默认实现为 `LocalDbDataSourceAdapter`，读取当前 D1 卡牌基础表；测试或后续扩展仍可注入其他 Adapter：

```typescript
interface CardSearchResult {
  card_ref: string;          // cards_all.product_id（用作 card_ref）
  name: string;              // 卡牌名称
  set_name: string;          // 系列名
  set_code: string;          // 系列编号
  card_number: string;       // 卡编
  finish: string | null;     // 工艺 / 版本（如 Holofoil）
  language: string | null;   // 语言
  object_type: 'tcg' | 'sports' | 'sealed' | 'other';
  image_url: string | null;  // 卡牌图片 URL
  rarity: string | null;     // 稀有度
}

interface PricePoint {
  date: string;              // ISO 8601 日期
  price: number;             // 价格原值（USD）
}

interface MarketPrice {
  grader: string;            // 'Raw' | 'PSA' | 'BGS' | 'CGC' | 'SGC' | 'TAG' | 'AGS'
  grade: number | null;      // 评级等级；Raw 时为 null
  condition: string | null;  // Raw 品相；评级时为 null
  price: number | null;      // 当前市场价（USD）；null = 无数据
}
// 注：单条口径的「当前市场价」= 对应 grader/grade/condition 的 getPriceSeries
// 返回序列中最新一个 PricePoint.price；getMarketPrices 则一次性返回卡牌
// 各状态口径的最新价，供 Market Prices 表格与价值计算使用。

interface SoldListing {
  date: string;
  title: string;
  price: number;
  platform: string;          // 成交平台名称
  url: string | null;
}

interface DataSourceAdapter {
  /**
   * 搜索卡牌
   * @param query    搜索关键词
   * @param options  object_type 过滤、分页等
   */
  searchCards(
    query: string,
    options?: { object_type?: string; page?: number; page_size?: number }
  ): Promise<CardSearchResult[]>;

  /**
   * 获取单张卡牌详情
   * @param card_ref  cards_all.product_id
   */
  getCard(card_ref: string): Promise<CardSearchResult | null>;

  /**
   * 获取价格时间序列（用于图表）
   * @param card_ref   cards_all.product_id
   * @param grader     评级机构或 'Raw'
   * @param grade      评级等级；Raw 时传 null
   * @param condition  Raw 品相；评级时传 null
   * @param days       时间窗口（如 30、90、180、365）
   */
  getPriceSeries(
    card_ref: string,
    grader: string,
    grade: number | null,
    condition: string | null,
    days: number
  ): Promise<PricePoint[]>;

  /**
   * 获取卡牌各状态口径的当前市场价（用于 Market Prices 表格与价值计算）。
   * 每条 MarketPrice.price 即该 grader/grade/condition 口径下
   * getPriceSeries 序列中最新一个 PricePoint.price（无序列则为 null）。
   * @param card_ref  cards_all.product_id
   */
  getMarketPrices(card_ref: string): Promise<MarketPrice[]>;

  /**
   * 获取 Trending Today 列表
   */
  getTrending(): Promise<CardSearchResult[]>;

  /**
   * 获取成交记录
   * @param card_ref  cards_all.product_id
   */
  getSoldListings(card_ref: string): Promise<SoldListing[]>;
}
```

### 2.2 适配器注册与选择

```typescript
// Workers 默认适配器
const primaryAdapter: DataSourceAdapter = createLocalDbDataSourceAdapter(env.DB);
```

Mock 适配器仅用于测试或本地演示，不作为生产数据源。

---

## 3. 字段映射

以下映射表说明 D1 基础表字段如何对应到 App 的展示字段。适配器负责在 `DataSourceAdapter` 实现中完成映射，调用方只接触统一结构。

### 3.1 卡牌基础信息映射

| App 展示字段 | DataSourceAdapter 字段 | 映射说明 |
|---|---|---|
| 卡牌名称（主标题） | `name` | 直接使用 |
| IP / Game（TCG） | `game` / `game_id` | 适配器内处理 |
| Set / 系列 | `set_name` | 直接使用 |
| 系列编号 | `set_code` | 直接使用 |
| 卡编 | `card_number` | `cards_all` 当前无此字段，返回空字符串 |
| Finish / Variant | `finish` | `cards_all` 当前无卡级字段，返回 null；SKU 维度在价格历史中保留 |
| Language | `language` | `cards_all` 当前无卡级字段，返回 null；SKU 维度在价格历史中保留 |
| 稀有度 | `rarity` | 直接使用 |
| 卡牌图片 | `image_url`，覆盖层 `card_override.image_url` 优先 | 覆盖层有图则替换 |
| card_ref（系统内部） | `card_ref` | 存入 `collection_item.card_ref` 等 |

### 3.2 价格字段映射

「当前市场价」统一来自 `getMarketPrices`（其每条 `MarketPrice.price` 即对应口径 `getPriceSeries` 序列中最新一个 `PricePoint.price`）：

| App 展示字段 | DataSourceAdapter 字段 | 说明 |
|---|---|---|
| Raw 当前市场价 | `getMarketPrices` → `MarketPrice.price`（grader='Raw'） | 按对应 condition 取价 |
| Graded 当前市场价 | `getMarketPrices` → `MarketPrice.price`（grader+grade） | 按 grader + grade 组合取价 |
| Sealed 当前市场价 | `getMarketPrices` → `MarketPrice.price`（grader='Raw'，Sealed 对象） | Sealed 无评级，取 Raw 价 |
| 价格缺失 | `MarketPrice.price = null` | 展示 `--`，不计入总资产 |
| 30D Price Series | `PricePoint[]`（days=30） | 用于 30D Change 计算和图表 |
| 7D Change | 计算自 `PricePoint[]`（days=7） | 见 global-rules.md 计算公式 |
| 30D Change | 计算自 `PricePoint[]`（days=30） | 见 global-rules.md 计算公式 |
| 涨跌幅缺失 | 历史价格点不足 | 展示 `-/-`，见 global-rules.md |

### 3.3 成交记录映射

| App 展示字段 | DataSourceAdapter 字段 | 说明 |
|---|---|---|
| 成交日期 | `SoldListing.date` | ISO 8601 → 按时区格式化 |
| 商品标题 | `SoldListing.title` | 直接使用 |
| 成交价格 | `SoldListing.price`（USD） | 按用户货币换算展示 |
| 成交平台 | `SoldListing.platform` | 直接使用 |
| 外链 | `SoldListing.url` | 打开平台详情页 |

### 3.4 Trending Today 映射

| App 展示字段 | DataSourceAdapter 字段 | 说明 |
|---|---|---|
| 卡牌名称 | `CardSearchResult.name` | 运营置顶卡 `card_override` 可覆盖 |
| 系列 | `CardSearchResult.set_name` | 直接使用 |
| 图片 | `CardSearchResult.image_url` | 覆盖层图片优先 |
| 涨幅排序 | `trending_pin.rank` / 适配器返回顺序 | 运营置顶（`trending_pin`）插入列表首位；无本地趋势算法时仅返回置顶项 |

---

## 4. 缓存策略

### 4.1 缓存层分工

| 接口 | 缓存位置 | 原因 |
|---|---|---|
| `searchCards` | Workers KV | 搜索结果字符串不大，KV 更新简单；搜索热词可共享缓存 |
| `getCard` | Workers KV | 卡牌基础信息变化少，KV 适合 |
| `getMarketPrices` | Cache API | 各状态口径当前价，与价格序列同源，Cache API 适合 |
| `getPriceSeries` | Cache API | 价格序列数据量较大，Cache API 支持更大 payload |
| `getTrending` | Workers KV | Trending 数据全局共享，KV 适合 |
| `getSoldListings` | Cache API | 成交列表数据量大，Cache API 适合 |

### 4.2 TTL 建议

| 接口 | TTL | 理由 |
|---|---|---|
| `searchCards` | 1 小时 | 卡牌目录变化频率低 |
| `getCard` | 6 小时 | 基础信息几乎不变 |
| `getMarketPrices` | 30 分钟 | 当前价随价格序列更新，与 getPriceSeries 对齐 |
| `getPriceSeries` | 30 分钟 | 价格数据每日更新，半小时刷新平衡实时性与成本 |
| `getTrending` | 15 分钟 | Trending Today 需要较高实时性 |
| `getSoldListings` | 30 分钟 | 成交记录实时性要求中等 |

⚠️ TBD：具体 TTL 值在接入阶段根据基础表刷新频率和业务实时性需求最终确定。

### 4.3 缓存 Key 设计原则

```
// 格式：{接口名}:{必要参数的有序拼接}
searchCards:{query}:{object_type}:{page}:{page_size}
getCard:{card_ref}
getMarketPrices:{card_ref}
getPriceSeries:{card_ref}:{grader}:{grade}:{condition}:{days}
getTrending
getSoldListings:{card_ref}
```

- Key 中所有参数小写 + URL encode，避免大小写造成缓存穿透。
- `getTrending` 全局共用单一 Key（所有用户看同一份数据）。
- `getPriceSeries` 的 Key 包含 grader / grade / condition 组合，不同品相 / 评级独立缓存。

### 4.4 缓存回填时机

Workers 成功读取 D1 基础表并组装响应后，**同步写入**对应缓存层。写入失败不影响本次响应，下次请求再尝试回填。

---

## 5. 降级策略

D1 基础表读取或缓存读取失败时，按以下顺序降级（见架构文档 §5.2）：

```
D1 基础表读取
    │
    ├─ 成功 ──► 写入缓存，返回数据
    │
    └─ 失败
          │
          ├─ 读有效缓存（未过期）──► 返回缓存数据，附响应头标注 cache_hit=true
          │
          ├─ 读过期缓存（stale）──► 返回过期缓存数据，附响应头标注 stale=true，异步发起重新请求
          │
          └─ 无任何缓存
                │
                └─ 返回占位值
                      price: null    → 展示 "--"
                      change: null   → 展示 "-/-"
                      image: null    → 展示占位图
                      list: []       → 展示空列表 + "No content available"
```

**具体占位展示规则**见 [`../00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)（金额缺失、涨跌幅缺失、图片缺失、局部内容不可用）；本文档不重复定义。

### 5.1 各接口降级行为

| 接口 | 降级后行为 | App 感知 |
|---|---|---|
| `searchCards` | 返回空列表 | 搜索结果区域展示 "No content available" + Refresh |
| `getCard` | 返回 null | 卡牌详情页整页失败状态 |
| `getMarketPrices` | 返回空数组 | Market Prices 区域展示 "No content available" + Refresh；各价格展示 `--` |
| `getPriceSeries` | 返回空数组 | 图表区域展示 "No price data available"，涨跌幅展示 `-/-` |
| `getTrending` | 返回空列表 | Home Trending Today 区域展示 "No content available" + Refresh |
| `getSoldListings` | 返回空列表 | Shop 区域展示 "No content available" + Refresh |

### 5.2 覆盖层与降级的关系

即使基础表中没有对应记录，D1 `card_override` 中 `is_missing_card = 1` 的卡牌仍可正常展示（基础信息由覆盖层提供）；价格字段无覆盖则展示 `--`。

---

## 6. TBD 汇总

| # | 待定项 | 影响面 |
|---|---|---|
| 1 | 卡牌基础表导入任务与刷新频率 | 目录完整性、价格历史新鲜度、Trending 非置顶数据是否可用 |
| 2 | 汇率接口提供方 | `purchase_price` 展示换算、货币切换 |
| 3 | 各接口最终 TTL（取决于基础表刷新频率） | 缓存命中率与数据新鲜度 |
| 4 | `tcgplayer_skus.condition_*` 枚举值 | `collection_item.condition` 字段的合法值集合 |
| 5 | `tcgplayer_skus.variant_*` 枚举值 | `collection_item.finish` 字段的合法值集合 |

# tcg-card 第三方数据接入

> **定位**：定义 tcg-card v1.0 的第三方卡牌数据接入口径，包括：可插拔适配层接口、字段映射、缓存策略、降级策略。具体厂商待定。
> **日期**：2026-06-30
> **来源**：
> - Spec [`docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md`](../../superpowers/specs/2026-06-30-tcg-card-preparation-design.md) §4.2、§4.3、§6
> - 架构 [`docs/tcg-card/02-architecture/architecture.md`](../02-architecture/architecture.md) §2.2、§3、§5
> - 跨切面规则 [`docs/tcg-card/00-product/modules/global-rules.md`](../00-product/modules/global-rules.md)

---

## 1. 设计原则

1. **厂商无关**：Workers 内部使用统一适配层接口（DataSourceAdapter），不同厂商实现各自适配器；切换或叠加厂商只需替换 / 新增实现，不改调用方。
2. **App 不直连第三方**：所有第三方数据经 Workers 代理，第三方 API Key 仅存于 Workers 环境变量。
3. **不落 D1 长期存储**：第三方数据（目录 / 价格 / Trending / 成交）只存 KV / Cache API 短期缓存，不写入 D1。
4. **覆盖层优先**：Workers 返回卡牌数据时，先读 D1 `card_override` 表，有覆盖字段则合并后返回，无覆盖则直接返回第三方数据（见数据模型 §6.1）。
5. **降级而不中断**：第三方失败时按顺序降级，不向 App 抛出 500，只在无有效数据时返回占位值。

---

## 2. 可插拔适配层

### 2.1 DataSourceAdapter 接口

Workers 内部定义以下统一接口，每个厂商实现一个 Adapter：

```typescript
interface CardSearchResult {
  card_ref: string;          // 厂商内唯一卡牌 ID（用作 card_ref）
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
   * @param card_ref  厂商卡牌唯一 ID
   */
  getCard(card_ref: string): Promise<CardSearchResult | null>;

  /**
   * 获取价格时间序列（用于图表）
   * @param card_ref   卡牌唯一 ID
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
   * @param card_ref  卡牌唯一 ID
   */
  getMarketPrices(card_ref: string): Promise<MarketPrice[]>;

  /**
   * 获取 Trending Today 列表
   */
  getTrending(): Promise<CardSearchResult[]>;

  /**
   * 获取成交记录
   * @param card_ref  卡牌唯一 ID
   */
  getSoldListings(card_ref: string): Promise<SoldListing[]>;
}
```

### 2.2 适配器注册与选择

```typescript
// Workers 启动时注册适配器
const adapters: DataSourceAdapter[] = [
  // ⚠️ TBD：在此注册具体厂商适配器，如 new TCGPlayerAdapter(env), new eBayAdapter(env)
];

// 当前版本使用单一主适配器；后续可扩展为按 object_type 路由
const primaryAdapter: DataSourceAdapter = adapters[0];
```

⚠️ TBD：具体厂商（TCGplayer / eBay / PriceCharting 等）、API Key 申请方式、适配器实现见开发阶段确认（Spec §6 TBD #1）。

---

## 3. 字段映射

以下映射表说明第三方原始字段如何对应到 App 的展示字段。适配器负责在 `DataSourceAdapter` 实现中完成映射，调用方只接触统一结构。

### 3.1 卡牌基础信息映射

| App 展示字段 | DataSourceAdapter 字段 | 映射说明 |
|---|---|---|
| 卡牌名称（主标题） | `name` | 直接使用 |
| IP / Game（TCG） | 由 `set_name` / 厂商元数据推断 | 适配器内处理 |
| Set / 系列 | `set_name` | 直接使用 |
| 系列编号 | `set_code` | 直接使用 |
| 卡编 | `card_number` | 直接使用 |
| Finish / Variant | `finish` | 直接使用；null 则不展示 |
| Language | `language` | 直接使用；null 则不展示 |
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
| 涨幅排序 | 厂商返回顺序 / Trending Today 接口内部排序 | 运营置顶（`trending_pin`）插入列表首位 |

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

⚠️ TBD：具体 TTL 值在接入阶段根据厂商 API 限速策略和业务实时性需求最终确定。

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

Workers 成功获取第三方响应后，**同步写入**对应缓存层。写入失败不影响本次响应，下次请求再尝试回填。

---

## 5. 降级策略

第三方 API 请求失败时，按以下顺序降级（见架构文档 §5.2）：

```
第三方 API 请求
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

即使第三方完全不可用，D1 `card_override` 中 `is_missing_card = 1` 的卡牌仍可正常展示（基础信息由覆盖层提供）；价格字段无覆盖则展示 `--`。

---

## 6. TBD 汇总

| # | 待定项 | 影响面 |
|---|---|---|
| 1 | 第三方数据源厂商（TCGplayer / eBay / PriceCharting 等）及 API Key 申请 | 适配器实现、`card_ref` 格式、字段映射细节 |
| 2 | 汇率接口提供方 | `purchase_price` 展示换算、货币切换 |
| 3 | 各接口最终 TTL（取决于厂商限速策略） | 缓存命中率与 API 调用成本 |
| 4 | 厂商 API `condition` 枚举值（如 `Near Mint` / `Lightly Played` 等） | `collection_item.condition` 字段的合法值集合 |
| 5 | 厂商 API `finish` 枚举值（如 `Holofoil` / `Reverse Holo` 等） | `collection_item.finish` 字段的合法值集合 |

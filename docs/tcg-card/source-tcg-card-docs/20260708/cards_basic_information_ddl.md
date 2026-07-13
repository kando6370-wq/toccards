# cards_basic_information.db DDL 解析

本文档描述 `Current_version/recognition_data/cards_basic_information.db` 的 SQLite 表结构、字段语义、逻辑关系、枚举/代码值和多类型字段。

统计基于当前库文件快照：

| 项 | 值 |
|---|---:|
| 数据库大小 | 约 3010.60 MB |
| `cards_all` 行数 | 217,589 |
| `games` 行数 | 8 |
| `sets` 行数 | 4,208 |
| `tcgplayer_skus` 行数 | 4,848,730 |

注意：

- SQLite 是弱类型数据库，DDL 中的 `TEXT` / `INTEGER` / `REAL` 是声明类型，不等于业务上永远只有一种格式。
- 本库没有显式外键约束，下面的关联关系是根据代码和数据推断出的逻辑关系。
- 当前 `cards_all` 是精简后的识别元数据表，只保留识别和 OCR 重排所需的核心字段。价格、SKU JSON、下载状态、`source_table`、`type`、`sealed`、`product_line_id` 等旧字段已经不在 `cards_all` 中。

## 表总览

| 表名 | 用途 | 主键/唯一性 |
|---|---|---|
| `cards_all` | 识别服务回查用的核心卡牌/商品元数据表 | `product_id TEXT PRIMARY KEY` |
| `games` | 已加载的游戏/产品线清单 | 未声明主键；业务上 `id` 可视为内部游戏 ID |
| `sets` | 系列/扩展包信息 | `id INTEGER PRIMARY KEY AUTOINCREMENT`，`UNIQUE(game, name)` |
| `tcgplayer_skus` | TCGplayer SKU 维度价格、语言、品相、版本信息 | `sku_id INTEGER PRIMARY KEY` |
| `sqlite_sequence` | SQLite 自增序列表 | SQLite 内部表 |
| `sqlite_stat1` | SQLite ANALYZE 统计信息 | SQLite 内部表 |

## 逻辑关系

| 来源字段 | 目标字段 | 说明 |
|---|---|---|
| `cards_all.game_id` | `games.id` | 内部游戏 ID，也是历史源表名 `cards_<id>` 的后缀。不要和 `games.game_id` 混淆。 |
| `cards_all.product_id` | `tcgplayer_skus.product_id` | 逻辑关联。`cards_all.product_id` 是数字字符串，`tcgplayer_skus.product_id` 是整数。关联时建议 `CAST(cards_all.product_id AS INTEGER)`。 |
| `cards_all.set_id` | `sets.set_id` | 系列 ID。建议同时带上 `game` 限定，避免跨产品线重复。 |
| `cards_all.product_id` | `phash_cards_all.db.cards.product_id` | 与 pHash 数据库按产品 ID 关联，用于识别后回查元数据。 |

当前 `games` 映射：

| `games.id` / `cards_all.game_id` | `games.game_id` / TCGplayer 产品线 ID | `games.name` | `cards_all` 行数 |
|---:|---:|---|---:|
| 1 | 1.0 | Magic: The Gathering | 110,825 |
| 2 | 2.0 | YuGiOh | 45,225 |
| 3 | 3.0 | Pokemon | 30,708 |
| 56 | 62.0 | Flesh and Blood TCG | 8,498 |
| 57 | 63.0 | Digimon Card Game | 8,016 |
| 62 | 68.0 | One Piece Card Game | 5,881 |
| 63 | 71.0 | Disney Lorcana | 2,620 |
| 71 | 79.0 | Star Wars: Unlimited | 5,816 |

## 原始 DDL

```sql
CREATE TABLE "cards_all" (
    product_id TEXT PRIMARY KEY,
    game_id INTEGER NOT NULL,
    "game" TEXT,
    "set_name" TEXT,
    "set_code" TEXT,
    "set_id" TEXT,
    "name" TEXT,
    "rarity" TEXT,
    "description" TEXT,
    "product_type_name" TEXT,
    "foil_only" INTEGER DEFAULT 0,
    "normal_only" INTEGER DEFAULT 0,
    "image_url" TEXT,
    "created_at" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "card_type" TEXT,
    "full_type" TEXT,
    "color" TEXT,
    "converted_cost" TEXT,
    "flavor_text" TEXT,
    "power" TEXT,
    "power_number" TEXT,
    "toughness" TEXT
);

CREATE INDEX idx_cards_all_game_id ON cards_all(game_id);
CREATE INDEX idx_cards_all_game_product ON cards_all(game_id, product_id);

CREATE TABLE games (
    id INTEGER,
    game_id REAL,
    name VARCHAR(50),
    total_cards INTEGER,
    image_source VARCHAR(50),
    images_enabled INTEGER,
    created_at NVARCHAR(50),
    load INTEGER
);

CREATE TABLE sets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game TEXT NOT NULL,
    name TEXT NOT NULL,
    set_name TEXT,
    set_code TEXT,
    set_id TEXT,
    series TEXT,
    total_cards INTEGER DEFAULT 0,
    release_date TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(game, name)
);

CREATE INDEX idx_sets_set_id ON sets(set_id);

CREATE TABLE tcgplayer_skus (
    sku_id INTEGER NOT NULL PRIMARY KEY,
    product_id INTEGER NOT NULL,
    sku_key TEXT NOT NULL,
    condition_code TEXT,
    condition_name TEXT,
    language_code TEXT,
    language_name TEXT,
    variant_code TEXT,
    variant_name TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    price_history TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX idx_tcgplayer_skus_product_id
    ON tcgplayer_skus(product_id);

CREATE INDEX idx_tcgplayer_skus_lookup
    ON tcgplayer_skus(product_id, language_code, variant_code, condition_code);
```

## cards_all 字段说明

`cards_all` 是识别服务最重要的表。pHash 命中后会按 `product_id` 回查这个表，补充卡名、系列、稀有度、图片地址以及 OCR 重排文本等元数据。

| 字段 | DDL 类型 | 当前实际类型 | 字段说明 | 枚举/多类型说明 |
|---|---|---|---|---|
| `product_id` | `TEXT PRIMARY KEY` | `text` | TCGplayer 商品/product ID。当前全部是数字字符串。 | 多类型注意：和 `tcgplayer_skus.product_id INTEGER` 关联时需要类型转换；不要直接假设两表类型一致。 |
| `game_id` | `INTEGER NOT NULL` | `integer` | 内部游戏 ID。对应 `games.id` 和历史源表 `cards_<game_id>`。 | 枚举：`1` MTG，`2` YuGiOh，`3` Pokemon，`56` Flesh and Blood，`57` Digimon，`62` One Piece，`63` Lorcana，`71` Star Wars Unlimited。 |
| `game` | `TEXT` | `text` | 游戏/产品线显示名。 | 当前 8 个值，和 `games.name` 基本对应。 |
| `set_name` | `TEXT` | `text` | 系列/扩展包显示名。 | 非固定枚举，高基数字段。 |
| `set_code` | `TEXT` | `text` | 系列代码，如 MTG 的 `P02`、`10E`。 | 可为空字符串；不同游戏格式不同，不应按统一长度校验。 |
| `set_id` | `TEXT` | `text` | TCGplayer 系列 ID。 | 多类型注意：保存为文本，常见格式是 `"87.0"` 这种小数字符串；逻辑上是数字 ID。 |
| `name` | `TEXT` | `text` | 商品/卡牌名。 | 高基数字段。 |
| `rarity` | `TEXT` | `text/null` | 稀有度。 | 类枚举但不是闭集，当前 74 个非空值。详见“枚举和代码值”。 |
| `description` | `TEXT` | `text/null` | 规则文字/商品描述。 | 可能包含 HTML 标签，如 `<em>`、`<br>`。OCR 重排会清理 HTML 后使用。 |
| `product_type_name` | `TEXT` | `text` | 商品类型名称。 | 枚举：`Cards`、`Sealed Products`、`Booster Box` 等，详见下方。 |
| `foil_only` | `INTEGER DEFAULT 0` | `integer` | 是否只存在闪版/foil。 | 布尔：`0=false`，`1=true`。 |
| `normal_only` | `INTEGER DEFAULT 0` | `integer` | 是否只存在普通版/normal。 | 布尔：`0=false`，`1=true`。 |
| `image_url` | `TEXT` | `text/null` | 商品图片 URL。 | 通常是 `https://product-images.tcgplayer.com/.../{product_id}.jpg`。 |
| `created_at` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | `text` | 记录创建时间。 | SQLite 文本时间。 |
| `updated_at` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | `text` | 记录更新时间。 | 用于判断数据新旧；SQLite 实际以文本保存。 |
| `card_type` | `TEXT` | `text/null` | 卡牌类型。 | 跨游戏字段，可能包含逗号分隔多类型。 |
| `full_type` | `TEXT` | `text/null` | 完整类型行。 | 例如 MTG 的 `Creature - Nightstalker`；可能含子类型。 |
| `color` | `TEXT` | `text/null` | 颜色/属性。 | 多值字段用逗号分隔，如 `Green, White`。不同游戏语义不同。 |
| `converted_cost` | `TEXT` | `text/null` | 费用/总法术力值/成本。 | 多类型注意：多数是数字字符串，也可能有特殊大值；不要强制整数。 |
| `flavor_text` | `TEXT` | `text/null` | 风味文字。 | 可为空字符串或 null。 |
| `power` | `TEXT` | `text/null` | 力量/攻击力/战力字段。 | 多语义字段：MTG 可能是 `2`、`*`、`1/*`；Digimon/One Piece 等可能是 `5000`、`12000`；也出现 `1/1`、`+1` 等复合值。 |
| `power_number` | `TEXT` | `text/null` | 从 `power` 派生或清洗出的数值字段。 | 多类型注意：仍是文本，仍可能包含 `*`、`1/1` 等，不保证可转数字。 |
| `toughness` | `TEXT` | `text/null` | 防御/生命/韧性字段。 | 多语义字段：MTG 是 toughness；其他游戏可能为空或复用不同战斗数值。 |

### cards_all 空值和特殊观察

| 字段 | 当前观察 |
|---|---|
| `set_code` | 无 null，但有 7,525 个空字符串。 |
| `description` | 3,828 行为 null，25,847 行为空字符串；清洗时需要同时处理两种空值。 |
| `image_url` | 116 行为 null。 |
| `full_type` | 115,138 行为 null，4 行为空字符串。 |
| `color` | 103,207 行为 null。 |
| `converted_cost` | 126,368 行为 null。 |
| `flavor_text` | 74,061 行为 null，86,990 行为空字符串。 |
| `power` | 153,941 行为 null，10 行为空字符串。 |
| `power_number` | 166,674 行为 null。 |
| `toughness` | 167,283 行为 null。 |
| `product_id` | 当前全部是数字字符串，但 DDL 是 `TEXT`。如果未来写入非数字自定义 ID，会影响与 `tcgplayer_skus` 和 pHash 矩阵的兼容性。 |

## games 字段说明

| 字段 | DDL 类型 | 当前实际类型 | 字段说明 | 枚举/多类型说明 |
|---|---|---|---|---|
| `id` | `INTEGER` | `integer` | 内部游戏 ID。 | 与 `cards_all.game_id`、历史源表 `cards_<id>` 对应。 |
| `game_id` | `REAL` | `real` | TCGplayer 产品线 ID。 | 注意不是 `cards_all.game_id`。例如 Flesh and Blood 的 `id=56`，但 `game_id=62.0`。 |
| `name` | `VARCHAR(50)` | `text` | 游戏/产品线名称。 | 当前 8 个加载游戏。 |
| `total_cards` | `INTEGER` | `integer` | 数据源中该游戏总卡/商品数。 | 与 `cards_all` 行数可能略有差异，因为 `cards_all` 按 `product_id` 去重。 |
| `image_source` | `VARCHAR(50)` | `text` | 图片/数据来源。 | 当前全为 `tcgplayer`。 |
| `images_enabled` | `INTEGER` | `integer` | 是否启用图片。 | 布尔：当前全为 `1`。 |
| `created_at` | `NVARCHAR(50)` | `text` | 创建时间。 | 文本时间。 |
| `load` | `INTEGER` | `integer` | 是否加载该游戏。 | 布尔：当前全为 `1`。 |

## sets 字段说明

| 字段 | DDL 类型 | 当前实际类型 | 字段说明 | 枚举/多类型说明 |
|---|---|---|---|---|
| `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | `integer` | 本地自增 ID。 | 仅本库内部使用。 |
| `game` | `TEXT NOT NULL` | `text` | 游戏/产品线名称。 | 当前 `sets` 表包含比 `cards_all` 更多的产品线，不只 8 个加载游戏。 |
| `name` | `TEXT NOT NULL` | `text` | 系列名称，用于唯一约束 `UNIQUE(game, name)`。 | 高基数字段。 |
| `set_name` | `TEXT` | `text` | 系列显示名。 | 通常等于 `name`。 |
| `set_code` | `TEXT` | `text` | 系列代码。 | 可为空字符串。 |
| `set_id` | `TEXT` | `text` | TCGplayer 系列 ID。 | 文本数字或小数字符串，如 `"1.0"`、`"17666.0"`。 |
| `series` | `TEXT` | `null` | 系列分组预留字段。 | 当前全为空。 |
| `total_cards` | `INTEGER DEFAULT 0` | `integer` | 该系列商品/卡牌数量。 | 数据源计数。 |
| `release_date` | `TEXT` | `text/null` | 系列发售日期。 | 当前大多数为空。 |
| `created_at` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | `text` | 本地创建时间。 | SQLite 文本时间。 |

## tcgplayer_skus 字段说明

`tcgplayer_skus` 是 SKU 维度表。一张产品卡牌可以有多个 SKU，按品相、语言、版本区分。

| 字段 | DDL 类型 | 当前实际类型 | 字段说明 | 枚举/多类型说明 |
|---|---|---|---|---|
| `sku_id` | `INTEGER NOT NULL PRIMARY KEY` | `integer` | TCGplayer SKU ID。 | 主键。 |
| `product_id` | `INTEGER NOT NULL` | `integer` | TCGplayer 产品 ID。 | 关联 `cards_all.product_id` 时注意类型不同。 |
| `sku_key` | `TEXT NOT NULL` | `text` | 组合 SKU key。 | 通常格式为 `{condition_code}_{language_code}_{variant_code}`，如 `NM_EN_N`。 |
| `condition_code` | `TEXT` | `text` | 品相代码。 | 枚举见下方。 |
| `condition_name` | `TEXT` | `text` | 品相名称。 | 与 `condition_code` 对应。 |
| `language_code` | `TEXT` | `text` | 语言代码。 | 枚举见下方；有极少空字符串。 |
| `language_name` | `TEXT` | `text` | 语言名称。 | `XX` 代码可对应简体/繁体中文名称。 |
| `variant_code` | `TEXT` | `text` | 版本/工艺代码。 | 枚举见下方；有极少空字符串。 |
| `variant_name` | `TEXT` | `text` | 版本/工艺名称。 | 同一 `variant_code` 可能对应多个细分名称，不能只靠 code 表达全部语义。 |
| `created_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` | `text` | SKU 记录创建时间。 | 文本时间。 |
| `updated_at` | `TEXT DEFAULT CURRENT_TIMESTAMP` | `text` | SKU 记录更新时间。 | 文本时间。 |
| `price_history` | `TEXT NOT NULL DEFAULT '[]'` | `text` | JSON 数组字符串，保存历史价格。 | 结构为 `[{"price": "0.13", "date": "2026-07-07"}, ...]`；当前约 397 万行是空数组。 |

## 枚举和代码值

### `cards_all.game_id`

| 值 | 释义 |
|---:|---|
| `1` | Magic: The Gathering |
| `2` | YuGiOh |
| `3` | Pokemon |
| `56` | Flesh and Blood TCG |
| `57` | Digimon Card Game |
| `62` | One Piece Card Game |
| `63` | Disney Lorcana |
| `71` | Star Wars: Unlimited |

### 布尔型整数字段

以下字段按 `0/1` 布尔处理：

| 表 | 字段 | `0` | `1` |
|---|---|---|---|
| `cards_all` | `foil_only` | 非仅 foil | 仅 foil |
| `cards_all` | `normal_only` | 非仅 normal | 仅 normal |
| `games` | `images_enabled` | 不启用图片 | 启用图片 |
| `games` | `load` | 不加载 | 加载 |

### `cards_all.product_type_name`

当前非空枚举值：

| 值 | 释义 |
|---|---|
| `Cards` | 单卡/卡牌 |
| `Sealed Products` | 密封产品 |
| `Intro Pack` | 入门包 |
| `Booster Box` | 补充包盒 |
| `Booster Pack` | 补充包 |
| `Fat Pack` | Fat Pack / Bundle 类产品 |
| `Precon/Event Decks` | 预组/赛事套牌 |
| `Magic Deck Pack` | MTG 套牌包 |
| `Magic Booster Box Case` | MTG 补充包箱 |
| `Box Sets` | 盒装套装 |
| `Tin` | 铁盒 |
| `All 5 Intro Packs` | 入门包组合 |
| `Intro Pack Display` | 入门包展示盒 |
| `YGO Start Decks` | YuGiOh 起始套牌 |
| `3x Magic Booster Packs` | 3 包 MTG 补充包 |
| `Booster Battle Pack` | Booster Battle Pack |

### `cards_all.rarity`

`rarity` 是类枚举字段，但不是严格闭集。不同游戏共用此列，当前有 74 个非空值。常见值包括：

| 值 | 说明 |
|---|---|
| `Common` | 普通 |
| `Uncommon` | 非普通 |
| `Rare` | 稀有 |
| `Mythic` | MTG 神话稀有 |
| `Promo` | 促销/赠品 |
| `Token` | 衍生物/Token |
| `Land` | MTG 土地类稀有度/分类 |
| `Ultra Rare` | YuGiOh/Pokemon 等使用的高稀有度 |
| `Super Rare` | 超稀有 |
| `Secret Rare` | 隐秘稀有 |
| `Holo Rare` | 闪稀有 |
| `Code Card` | Pokemon code card |
| `None` | 数据源显式无稀有度 |
| `Leader` | One Piece 等游戏的 Leader 类别 |
| `DON!!` | One Piece DON!! 卡类别 |
| `Majestic`、`Legendary`、`Marvel`、`Fabled` | Flesh and Blood 等游戏稀有度 |
| `Enchanted` | Lorcana 稀有度 |

其他当前存在值包括 `Common / Short Print`、`Quarter Century Secret Rare`、`Ultimate Rare`、`Platinum Secret Rare`、`Prismatic Secret Rare`、`Illustration Rare`、`Double Rare`、`Collector's Rare`、`Special Illustration Rare`、`Hyper Rare`、`Ghost Rare`、`ACE SPEC Rare`、`Radiant Rare`、`Amazing Rare`、`10000 Secret Rare` 等。新增数据时不要把该字段限制为固定少数几个值。

### `cards_all.color`

`color` 是跨游戏多语义字段：

- MTG：颜色，如 `White`、`Blue`、`Black`、`Red`、`Green`、`Colorless`。
- 多色：逗号分隔，如 `Green, White`、`Black, Blue, Red`。
- Lorcana / One Piece 等：也可能使用 `Purple`、`Yellow` 等游戏内颜色。
- 该字段不是标准化关联表，不适合用单值枚举建模。

### `cards_all.card_type`

`card_type` 是跨游戏卡牌类型。常见值：

| 值 | 说明 |
|---|---|
| `Creature`、`Instant`、`Sorcery`、`Artifact`、`Enchantment`、`Land`、`Planeswalker` | MTG 类型 |
| `Pokemon`、`Supporter`、`Item`、`Energy`、`Trainer`、`Stadium` | Pokemon 类型 |
| `Main Deck Monster`、`Extra Deck Monster`、`Spell`、`Trap` | YuGiOh 类型 |
| `Character`、`Action`、`Item` | Lorcana 等游戏类型 |
| `Digimon`、`Option`、`Tamer`、`Digi-Egg` | Digimon 类型 |
| `Leader`、`DON!!` | One Piece 类型 |
| `Unit`、`Upgrade`、`Event`、`Base` | Star Wars: Unlimited 类型 |

组合类型用逗号分隔，例如 `Legendary, Creature`、`Artifact, Creature`、`Main Deck Monster, Extra Deck Monster`。

### `tcgplayer_skus.condition_code`

| code | name | 释义 |
|---|---|---|
| `NM` | `Near Mint` | 近全新 |
| `LP` | `Lightly Played` | 轻度使用 |
| `MP` | `Moderately Played` | 中度使用 |
| `HP` | `Heavily Played` | 重度使用 |
| `DM` | `Damaged` | 损坏 |
| `UO` | `UO` | 数据源用于密封/未开封类商品的状态代码；当前 `condition_name` 也为 `UO`，业务上应按非单卡品相处理。 |

### `tcgplayer_skus.language_code`

| code | name | 释义 |
|---|---|---|
| `EN` | `English` | 英文 |
| `JP` | `Japanese` | 日文 |
| `FR` | `French` | 法文 |
| `DE` | `German` | 德文 |
| `ES` | `Spanish` | 西班牙文 |
| `IT` | `Italian` | 意大利文 |
| `PT` | `Portuguese` | 葡萄牙文 |
| `KO` | `Korean` | 韩文 |
| `XX` | `Chinese (S)` / `Chinese (T)` | 中文；当前 code 未区分简体/繁体，需结合 `language_name`。 |
| 空字符串 | 非标准空值 | 当前有极少数，应按未知语言处理。 |

### `tcgplayer_skus.variant_code`

| code | 常见 `variant_name` | 释义 |
|---|---|---|
| `N` | `Normal` | 普通版 |
| `F` | `Foil` | 闪版 |
| `U` | `Unlimited` / `Unlimited Edition Normal` | Unlimited 版本；同一 code 的显示名存在差异。 |
| `1E` | `1st Edition` / `1st Edition Normal` / `1st Edition Holofoil` 等 | 一版/首版；具体工艺要看 `variant_name`。 |
| `XX` | `Holofoil` 等 | 数据源保留/特殊版本代码，不能只靠 code 判断具体工艺。 |
| 空字符串 | `Limited` 等 | 非标准空值，需结合 `variant_name`。 |

### `sku_key`

`sku_key` 通常由三段组成：

```text
{condition_code}_{language_code}_{variant_code}
```

示例：

| `sku_key` | 拆解 | 释义 |
|---|---|---|
| `NM_EN_N` | `NM` + `EN` + `N` | Near Mint / English / Normal |
| `LP_JP_F` | `LP` + `JP` + `F` | Lightly Played / Japanese / Foil |
| `DM_FR_N` | `DM` + `FR` + `N` | Damaged / French / Normal |

不要只解析 `sku_key` 后丢弃单独列，因为 `variant_code` 和 `language_code` 存在 `XX`、空字符串等边界情况，`*_name` 字段保留了更多语义。

## JSON / 文本复合字段

当前精简版 `cards_all` 不再包含旧的 `skus`、`tcgtraders_sku`、`formats` 等 JSON 字段。JSON 字段主要保留在 `tcgplayer_skus.price_history`。

### `tcgplayer_skus.price_history`

类型：JSON 数组字符串。

结构：

```json
[
  {"price": "0.13", "date": "2026-07-07"},
  {"price": "0.13", "date": "2026-07-04"}
]
```

说明：

- `price` 当前保存为字符串，不是 JSON number。
- `date` 是 `YYYY-MM-DD`。
- 空历史为 `[]`。

## OCR 相关说明

当前数据库没有 `ocr_txts` 列，但 OCR 重排代码 `Current_version/tools/ocr/reranker.py` 会优先尝试读取候选结果中的 `ocr_txts` 字段。如果未来扩展数据库，建议新增：

```sql
ALTER TABLE cards_all ADD COLUMN ocr_txts TEXT;
```

推荐结构是 JSON 数组字符串：

```json
["BEAST", "Creature Beast", "3/3"]
```

如果 `ocr_txts` 不存在或为空，当前代码会从以下字段组合候选 OCR 文本：

`name`、`full_type` / `card_type`、`description`、`flavor_text`、`power` / `toughness`、`set_code`、`set_name`、`rarity`、`color`、`converted_cost`。

## 查询建议

按识别结果回查元数据：

```sql
SELECT *
FROM cards_all
WHERE product_id = ?;
```

按游戏限定回查：

```sql
SELECT *
FROM cards_all
WHERE game_id = ?
  AND product_id = ?;
```

查询某产品的 SKU：

```sql
SELECT *
FROM tcgplayer_skus
WHERE product_id = CAST(? AS INTEGER)
ORDER BY language_code, variant_code, condition_code;
```

查 Near Mint / English / Normal SKU：

```sql
SELECT *
FROM tcgplayer_skus
WHERE product_id = CAST(? AS INTEGER)
  AND condition_code = 'NM'
  AND language_code = 'EN'
  AND variant_code = 'N';
```

关联游戏信息：

```sql
SELECT c.product_id, c.name, c.game_id, g.name AS game_name, g.game_id AS product_line_id
FROM cards_all AS c
LEFT JOIN games AS g ON g.id = c.game_id
WHERE c.product_id = ?;
```

关联系列信息：

```sql
SELECT c.product_id, c.name, c.set_name, c.set_code, s.id AS local_set_id
FROM cards_all AS c
LEFT JOIN sets AS s
  ON s.set_id = c.set_id
 AND s.game = c.game
WHERE c.product_id = ?;
```

## 已移除的旧 cards_all 字段

当前 `cards_all` 不再包含以下旧字段。旧文档或旧代码如果仍引用这些字段，需要同步调整：

`source_table`、`series`、`number`、`low_price`、`mid_price`、`market_price`、`lowest_price_with_shipping`、`product_line_id`、`product_line_url_name`、`product_type_id`、`product_url_name`、`product_status_id`、`set_url_name`、`shipping_category_id`、`skus`、`subTypeName`、`sealed`、`image_count`、`max_fulfillable_quantity`、`seller_listable`、`has_image`、`image_obtained`、`download_attempted`、`download_failed_reason`、`last_download_attempt`、`reference`、`subtitle`、`type`、`languages_override`、`duplicate`、`score`、`formats`、`release_date`、`data_source`、`detail_note`、`tcgtraders_sku`。

## 建模注意事项

1. `cards_all.game_id` 和 `games.game_id` 不是同一个概念。前者是内部游戏 ID，后者是 TCGplayer 产品线 ID。
2. `product_id` 在 `cards_all` 中是 `TEXT`，在 `tcgplayer_skus` 中是 `INTEGER`。跨表关联要显式转换或在应用层统一成字符串/整数。
3. `set_id` 是文本字段，但内容像数字，且常见为 `"1.0"` 这类小数字符串。
4. `rarity`、`card_type`、`color` 是跨游戏字段，不应按单个游戏的枚举强约束。
5. `power`、`power_number`、`toughness` 是文本型战斗数值字段，可能包含 `*`、斜杠、加号、超大数值或其他游戏特有表示。
6. `tcgplayer_skus.price_history` 声明为 `TEXT`，读写时应使用 JSON parser，不要用字符串截取。
7. 布尔字段没有 CHECK 约束，虽然当前主要是 `0/1`，应用层仍应容错。
8. `sets` 表包含很多未加载到 `cards_all` 的产品线，不能用 `sets.game` 反推当前识别服务支持的全部游戏。

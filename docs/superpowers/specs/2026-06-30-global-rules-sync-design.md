# global-rules 同步设计 —— 同步产品 updateby 意见

> **日期**：2026-06-30
> **来源意见**：`docs/tcg-card/source-tcg-card-docs/updateby-global-rules.md`（产品对 global-rules.md 的 10 条意见 + 5 条重点）
> **目标真相源**：`docs/tcg-card/00-product/modules/global-rules.md`

---

## 1. 背景

产品评审了 `global-rules.md`，提出 10 条修改意见，写在 `updateby-global-rules.md`。本设计把这些意见落到文档，保持 global-rules.md 的"唯一真相源"定位。

## 2. 执行策略

采用**真相源驱动**：先把 10 条意见全部落到 `global-rules.md`，再仅对**确有内嵌副本、会与新口径矛盾**的正式文档做对齐。

## 3. 改动范围

**需改动（2 个文件）**：
- `docs/tcg-card/00-product/modules/global-rules.md` —— 主，10 条意见全部落位。
- `docs/tcg-card/00-product/modules/profile.md` —— 仅 §11.2 补第 3 条"退出后切回游客资产"一句。

**不改动（已核对）**：
- `auth.md` —— §八第242行声明游客规则全部引用 `global-rules.md §十四`，纯引用、无内嵌副本。
- `search.md` —— 已写明"只展示百分比不展示金额"，已符合第 5 条。
- `api-spec.md` —— 401/403 的"客户端调起登录/注册引导"是端点鉴权语义，与第 1 条（资产操作不拦登录）不冲突；迁移失败专用文案 `Something went wrong. Please try again later.` 按第 6 条保留。
- `source-tcg-card-docs/` —— 原始底稿，历史素材，不动。
- 其余模块文档（home/collection/glossary/flows 等）—— 均为引用型，无矛盾。

## 4. 逐条变更（含 before/after）

### 第 1 条 —— §八 删除强制登录弹窗

- **位置**：`global-rules.md §八` 第 229 行。
- **Before**：`- 未登录用户点击需要账号资产的操作时，调起登录 / 注册弹窗。`
- **After**（替换为两条）：
  - `- 游客状态下，用户可正常进行 Portfolio、Wishlist、Scan、Search 快捷收藏、Collection Item 编辑等资产相关操作，不强制登录（详见 §十四）。`
  - `- 仅"注册 / 登录"入口本身进入账号流程；资产操作不拦截登录。`
- 第 228 行（资产与账号绑定）、第 231 行（退出后不展示账号资产）保留不变。

### 第 2 条 —— 游客资产措辞统一为 anonymous_account 服务端备份

- **位置**：`global-rules.md §14.1 / §14.3 / §14.5`。
- **§14.1** 末尾补一句统一口径：
  `游客资产绑定 anonymous_account 并在服务端备份；客户端本地可缓存游客资产，但服务端 anonymous_account 为游客资产的主数据来源。`
  并把 §14.1 "其他与用户收藏资产相关的本地数据" 中的"本地数据"改为"资产数据"。
- **按替换表逐处替换**：
  | 现写法 | 改成 |
  |---|---|
  | 本地游客资产 | 游客资产 / anonymous_account 资产 |
  | 当前设备上的游客资产 | 当前 anonymous_account 下的游客资产 |
  | 不删除本地游客数据 | 不删除 anonymous_account 资产及本地缓存 |
  | 游客资产保持不变 | 游客资产仍保留在原 anonymous_account 下 |
- 具体命中：§14.3 第 350 行"当前设备上的游客资产"、第 352 行"其他本地游客资产相关配置"、迁移失败处理第 357 行"保留游客本地资产，不删除本地游客数据"。
- §15 冲突4 已是 anonymous_account 新口径，核对一致即可。

### 第 3 条 —— 登录已有账号后，退出可恢复 anonymous_account 资产

- **位置**：`global-rules.md §14.4 / §14.5` + `profile.md §11.2`。
- **§14.4** 补一句：`登录已有账号后，原 anonymous_account 资产仍保留。`
- **§14.5** 第 380 行改为：
  `如果客户端仍持有该 anonymous_account 绑定关系，则退出登录后切回游客状态并展示该 anonymous_account 游客资产；否则展示空游客状态。`
- **profile.md §11.2**（第 313 行附近）补一句：
  `退出后若客户端仍持有原 anonymous_account 绑定，切回游客态并展示该游客资产（见 global-rules §14.5）。`

### 第 4 条 —— §15 冲突3 拆分"数据来源"与"排序规则"

- **位置**：`global-rules.md §15 冲突3` 第 414–416 行。
- **After**（固化结论改为两条独立规则）：
  - 数据来源：以第三方聚合数据为准，App 不自行维护价格数据库（卡牌价格、历史价格序列均来自第三方数据适配层，见 `third-party.md`）。
  - 默认排序：Search / 系列列表等默认排序不再以"本地数据库入库时间"为业务口径，改为使用第三方数据适配层返回的默认排序字段（如 `release_date`、`updated_at`、`market_rank`、`provider_order`）；具体排序字段由接口返回，前端按接口结果展示。
  - 原 PRD 中"入库时间倒序""数据库无匹配"等措辞作废。

### 第 5 条 —— Search 列表只展示 30D 百分比

- **位置**：`global-rules.md §1.6`。
- 在 §1.6 公式下补说明：`- Search 列表只展示 30D Change 百分比，不展示涨跌金额（见 §七、search.md）。`
- `search.md` 已符合，不动。

### 第 6 条 —— 通用失败 Toast 统一（无 later 版本）

- 通用 Toast 当前已是 `Something went wrong. Please try again.`，无 later。
- **核对项**：确认无散落的把 `...try again later.` 当作**通用** Toast 的写法。迁移失败 / 提交反馈失败 / 打开网页失败等**专用** later 文案保留。
- 预期：仅核对，无编辑；若发现散落通用 later 版本则替换。

### 第 7 条 —— 去掉"轻操作"歧义

- **位置**：`global-rules.md §4.1` 第 153 行、第 161 行"轻操作"界定框；§13.2 边界说明第 329 行。
- 第 153 行：`所有**轻操作**失败统一使用通用 Toast：` → `大多数可恢复的操作失败统一使用通用 Toast：`
- 第 161 行界定框改为：
  `通用 Toast 适用于大多数可恢复的操作失败，包括切换、保存、添加、移除、删除等；操作失败时不改变数据状态，用户可重新操作。账号删除、退出登录、官网链接打开、提交反馈、游客资产迁移等特殊场景使用专用文案（见 §13.2）。`
  保留"枚举清单优先于字面定义"与对 §4.2 / §九 的引用。
- §13.2 第 329 行"通用 Toast 适用于轻操作失败" → "通用 Toast 适用于大多数可恢复的操作失败"。

### 第 8 条 —— §九 确认失败提示区分通用 / 专用

- **位置**：`global-rules.md §九` 第 250 行。
- **Before**：`- 确认失败后不改变数据，并展示通用 Toast。`
- **After**：`- 确认失败后不改变数据，并按场景展示失败提示：普通删除 / 移除操作使用通用 Toast（§4.1）；删除账号、退出登录等账号级操作使用场景专用失败文案（§13.2）。`

### 第 9 条 —— §12 局部失败是模块内状态

- **位置**：`global-rules.md §12` 说明区。
- 补一条说明：`- 局部模块加载失败不是整页状态，不影响页面其他区域展示；它在"页面正常数据状态"内按模块独立展示，不因优先级排序低于正常数据而被隐藏。`

### 第 10 条 —— 迁移失败不得出现空资产（硬性规则）

- **位置**：`global-rules.md §14.3` 迁移失败处理。
- 将迁移失败处理补充/收敛为：
  `迁移失败时，游客资产仍保留在 anonymous_account 下，不得标记为已迁移；新账号保持登录态。为避免"注册成功 → 看到空资产"，注册成功但迁移失败时优先保留当前游客资产展示并提示稍后重试同步，迁移成功后再切换为正式账号资产。`
- 成功路径（"迁移成功后刷新为新账号资产"）保持不变。

## 5. 验收标准

1. `updateby-global-rules.md` 的 10 条意见在 `global-rules.md` 中均有对应落位，措辞与产品建议一致。
2. `global-rules.md` 内部无残留旧措辞："调起登录 / 注册弹窗"、"本地游客资产"、"当前设备上的游客资产"、"轻操作"（作为定义性术语）、"入库时间倒序"。
3. `profile.md §11.2` 含退出后切回 anonymous_account 游客资产的描述。
4. 全库 `grep` 确认无把 `Something went wrong. Please try again later.` 当作通用 Toast 的写法（专用场景保留）。
5. `global-rules.md` 目录、内部交叉引用（§号）与正文一致，无断引用。
6. `auth.md`、`search.md`、`api-spec.md`、`source-tcg-card-docs/` 未被改动。

## 6. 标注与风险

- 第 10 条按产品建议写成**硬性规则**（不留 TBD）。
- 第 4 条排序字段（release_date / updated_at / market_rank / provider_order）为示例，最终以接口返回为准，文档已表述为"由接口返回"。
- 改动集中在 `global-rules.md`，§号引用较多；编辑后需重新核对目录与交叉引用一致性。

# global-rules 同步实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把产品 `updateby-global-rules.md` 的 10 条意见同步到 `global-rules.md`（真相源）及 `profile.md`，保持文档一致、无残留旧措辞。

**Architecture:** 真相源驱动——10 条意见全部落到 `global-rules.md`；仅 `profile.md §11.2` 补一句下游对齐。其余文档已核对为引用型或已符合，不改。

**Tech Stack:** Markdown 文档；校验用 `grep`（ripgrep）+ 人工读取；每任务一次 commit。

## Global Constraints

- 设计依据：`docs/superpowers/specs/2026-06-30-global-rules-sync-design.md`。
- 仅改动 `docs/tcg-card/00-product/modules/global-rules.md` 与 `docs/tcg-card/00-product/modules/profile.md`。
- 不得改动 `auth.md`、`search.md`、`api-spec.md`、`source-tcg-card-docs/`。
- 文案保留产品建议措辞；不"顺手优化"相邻无关内容。
- 编辑后保持 §号目录与交叉引用一致。
- 提交信息结尾加 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`。
- 校验命令在仓库根目录 `D:/IdeaProjects/kando-global-project` 执行。

---

### Task 1: §八 登录与账号规则 —— 删除强制登录弹窗（意见 1）

**Files:**
- Modify: `docs/tcg-card/00-product/modules/global-rules.md`（§八，约 229 行）

**Interfaces:**
- Produces: §八 新增"游客可正常进行资产操作、不强制登录"口径，被 §十四 与 profile.md 引用语境依赖。

- [ ] **Step 1: 编辑 §八**

将该行：

```
- 未登录用户点击需要账号资产的操作时，调起登录 / 注册弹窗。
```

替换为：

```
- 游客状态下，用户可正常进行 Portfolio、Wishlist、Scan、Search 快捷收藏、Collection Item 编辑等资产相关操作，不强制登录（详见 §十四）。
- 仅"注册 / 登录"入口本身进入账号流程；资产操作不拦截登录。
```

（第 228 行账号绑定、第 231 行"退出登录后不展示账号资产"保持不变。）

- [ ] **Step 2: 校验旧措辞已消失、新措辞就位**

Run: `grep -n "调起登录 / 注册弹窗" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 无输出（exit 1）。

Run: `grep -n "不强制登录（详见 §十四）" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 命中 1 行。

- [ ] **Step 3: Commit**

```bash
git add docs/tcg-card/00-product/modules/global-rules.md
git commit -m "docs(tcg-card): global-rules §八 游客可正常产生资产，移除强制登录弹窗(意见1)"
```

---

### Task 2: §十四 游客资产措辞统一 + 登录/退出恢复 + 迁移失败硬规则（意见 2/3/10）

**Files:**
- Modify: `docs/tcg-card/00-product/modules/global-rules.md`（§14.1 / §14.3 / §14.4 / §14.5）

**Interfaces:**
- Consumes: Task 1 的 §八"不强制登录"口径。
- Produces: §14.5"退出后切回 anonymous_account 游客资产"口径，被 Task 3 的 profile.md 引用。

- [ ] **Step 1: §14.1 统一主数据口径（意见 2）**

在 §14.1 "技术实现" 段后补一句：

```
游客资产绑定 anonymous_account 并在服务端备份；客户端本地可缓存游客资产，但服务端 anonymous_account 为游客资产的主数据来源。
```

并把 §14.1 "其他与用户收藏资产相关的本地数据" 中的 `本地数据` 改为 `资产数据`。

- [ ] **Step 2: §14.3 措辞替换 + 迁移失败硬规则（意见 2/10）**

§14.3 第一句：`系统将当前设备上的游客资产迁移到该新注册账号下。`
→ `系统将当前 anonymous_account 下的游客资产迁移到该新注册账号下。`

§14.3 "迁移范围" 末项 `其他本地游客资产相关配置` → `其他 anonymous_account 下游客资产相关配置`。

§14.3 "迁移失败处理" 列表（当前 4 条）替换为：

```
1. 游客资产仍保留在 anonymous_account 下，不删除资产及本地缓存，不得标记为已迁移。
2. 展示专用失败提示（见 §13.2 "游客资产迁移失败"）。
3. 新账号保持登录态；为避免"注册成功 → 看到空资产"，优先保留当前游客资产展示并提示稍后重试同步，迁移成功后再切换为正式账号资产。
4. 用户可稍后重试资产迁移；需在后台保留待迁移状态，避免重复注册。
```

（"迁移成功后" 段落保持不变。）

- [ ] **Step 3: §14.4 登录已有账号补恢复前提（意见 3）**

在 §14.4 "规则" 末尾补一句：

```
登录已有账号后，原 anonymous_account 资产仍保留。
```

- [ ] **Step 4: §14.5 退出后恢复（意见 3）**

将 §14.5 第二条：

```
- 如果设备上仍存在未迁移游客资产，则展示该游客资产；否则展示空游客状态。
```

替换为：

```
- 如果客户端仍持有该 anonymous_account 绑定关系，则退出登录后切回游客状态并展示该 anonymous_account 游客资产；否则展示空游客状态。
```

- [ ] **Step 5: 校验**

Run: `grep -nE "当前设备上的游客资产|其他本地游客资产相关配置|不删除本地游客数据" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 无输出（exit 1）。

Run: `grep -n "为游客资产的主数据来源" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 命中 1 行。

Run: `grep -n "切回游客状态并展示该 anonymous_account 游客资产" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 命中 1 行。

Run: `grep -n "看到空资产" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 命中 1 行。

- [ ] **Step 6: Commit**

```bash
git add docs/tcg-card/00-product/modules/global-rules.md
git commit -m "docs(tcg-card): global-rules §十四 统一 anonymous_account 口径+退出可恢复+迁移失败硬规则(意见2/3/10)"
```

---

### Task 3: profile.md §11.2 退出后切回游客资产（意见 3 下游）

**Files:**
- Modify: `docs/tcg-card/00-product/modules/profile.md`（§11.2，约 313 行）

**Interfaces:**
- Consumes: Task 2 的 §14.5 口径。

- [ ] **Step 1: 编辑 §11.2**

在该行之后：

```
- 退出后，Portfolio、Wishlist、账号详情等账号资产数据不再展示。
```

新增一行：

```
- 退出后若客户端仍持有原 anonymous_account 绑定，切回游客态并展示该游客资产（见 `./global-rules.md §14.5`）。
```

- [ ] **Step 2: 校验**

Run: `grep -n "切回游客态并展示该游客资产" docs/tcg-card/00-product/modules/profile.md`
Expected: 命中 1 行。

- [ ] **Step 3: Commit**

```bash
git add docs/tcg-card/00-product/modules/profile.md
git commit -m "docs(tcg-card): profile §11.2 退出后切回 anonymous_account 游客资产(意见3)"
```

---

### Task 4: Toast 与确认弹窗去歧义（意见 6/7/8）

**Files:**
- Modify: `docs/tcg-card/00-product/modules/global-rules.md`（§4.1、§九、§13.2 边界说明）

- [ ] **Step 1: §4.1 去掉"轻操作"（意见 7）**

第 153 行：`所有**轻操作**失败统一使用通用 Toast：`
→ `大多数可恢复的操作失败统一使用通用 Toast：`

§4.1 "轻操作"界定框（`> **"轻操作"界定**：...` 整段）替换为：

```
> **适用界定**：通用 Toast 适用于大多数可恢复的操作失败，包括切换、保存、添加、移除、删除等；操作失败时不改变数据状态，用户可重新操作。**具体以 §4.2 枚举清单为准，枚举清单优先于字面定义。** 账号删除、退出登录、官网链接打开、提交反馈、游客资产迁移等特殊场景使用专用文案（见 §九确认弹窗流程 + §13.2 场景专用文案）。
```

- [ ] **Step 2: §九 确认失败区分通用/专用（意见 8）**

第 250 行：`- 确认失败后不改变数据，并展示通用 Toast。`
→ `- 确认失败后不改变数据，并按场景展示失败提示：普通删除 / 移除操作使用通用 Toast（§4.1）；删除账号、退出登录等账号级操作使用场景专用失败文案（§13.2）。`

- [ ] **Step 3: §13.2 边界说明措辞（意见 7）**

第 329 行 `- **通用 Toast** 适用于轻操作失败：切换文件夹、切换货币、筛选排序、加入或移除收藏等。`
→ `- **通用 Toast** 适用于大多数可恢复的操作失败：切换文件夹、切换货币、筛选排序、加入或移除收藏等。`

- [ ] **Step 4: 意见 6 核对（无编辑则跳过）**

Run: `grep -rn "Something went wrong. Please try again later." docs/tcg-card/00-product docs/tcg-card/03-data-api`
Expected: 仅命中"游客资产迁移失败 / 迁移写入失败"等**专用**场景；不得有标注为通用 Toast 的用法。若发现通用用法才替换为 `Something went wrong. Please try again.`。

- [ ] **Step 5: 校验**

Run: `grep -nE "\*\*轻操作\*\*|轻操作失败|轻操作.界定" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 无输出（exit 1）。

Run: `grep -n "按场景展示失败提示" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 命中 1 行。

- [ ] **Step 6: Commit**

```bash
git add docs/tcg-card/00-product/modules/global-rules.md
git commit -m "docs(tcg-card): global-rules Toast/确认弹窗去'轻操作'歧义+区分专用文案(意见6/7/8)"
```

---

### Task 5: 状态优先级 + 数据来源/排序 + Search 百分比（意见 9/4/5）

**Files:**
- Modify: `docs/tcg-card/00-product/modules/global-rules.md`（§12、§15 冲突3、§1.6）

- [ ] **Step 1: §12 局部失败说明（意见 9）**

在 §12 "说明" 列表末尾补一条：

```
- 局部模块加载失败不是整页状态，不影响页面其他区域展示；它在"页面正常数据状态"内按模块独立展示，不因优先级排序低于正常数据而被隐藏。
```

- [ ] **Step 2: §15 冲突3 拆分数据来源与排序（意见 4）**

将 §15 冲突3 "固化结论" 两条 bullet 替换为：

```
- **数据来源**：以第三方聚合数据为准，App 不自行维护价格数据库；卡牌价格、历史价格序列均来自第三方数据适配层（见 `third-party.md`）。
- **默认排序**：Search / 系列列表等默认排序不再以"本地数据库入库时间"为业务口径，改为使用第三方数据适配层返回的默认排序字段（如 `release_date`、`updated_at`、`market_rank`、`provider_order`）；具体排序字段由接口返回，前端按接口结果展示。
- 原 PRD 中"入库时间倒序""数据库无匹配"等措辞作废。
```

- [ ] **Step 3: §1.6 Search 只展示百分比（意见 5）**

在 §1.6 公式代码块后补一行说明：

```
**说明**：Search 列表只展示 30D Change 百分比，不展示涨跌金额（见 §七、`search.md`）。
```

- [ ] **Step 4: 校验**

Run: `grep -n "入库时间倒序" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 仅命中"等措辞作废"那一行（说明作废），无作为现行口径的"统一替换为"用法。

Run: `grep -nE "默认排序字段|Search 列表只展示 30D Change 百分比|按模块独立展示" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 3 条均命中。

- [ ] **Step 5: Commit**

```bash
git add docs/tcg-card/00-product/modules/global-rules.md
git commit -m "docs(tcg-card): global-rules §12局部失败+§15数据来源与排序拆分+§1.6 Search百分比(意见9/4/5)"
```

---

### Task 6: 全局一致性收尾校验（验收标准）

**Files:**
- Read-only 校验；如发现目录/交叉引用断裂则 Modify `global-rules.md`。

- [ ] **Step 1: 残留旧措辞总扫**

Run: `grep -nE "调起登录 / 注册弹窗|本地游客资产|当前设备上的游客资产|\*\*轻操作\*\*" docs/tcg-card/00-product/modules/global-rules.md`
Expected: 无输出（exit 1）。

- [ ] **Step 2: 目录与 §号交叉引用一致**

读取 `global-rules.md` 目录（§15）与正文小节标题，确认 §一~§十五 标题、锚点、正文内 `§x` 引用均存在且对应；§13.2、§4.1、§4.2、§九 等被引用锚点未改名。
Expected: 无断引用。如有则修正后并入本任务提交。

- [ ] **Step 3: 确认未误改其他文档**

Run: `git status --porcelain docs/tcg-card`
Expected: 仅 `global-rules.md`、`profile.md` 出现在改动中（以及未跟踪的 `updateby-global-rules.md`）；`auth.md`/`search.md`/`api-spec.md`/`source-tcg-card-docs/` 无改动。

- [ ] **Step 4: 逐条回填核对**

对照 spec §5 验收标准逐条确认意见 1~10 均已落位。

- [ ] **Step 5: Commit（仅当 Step 2 有修正时）**

```bash
git add docs/tcg-card/00-product/modules/global-rules.md
git commit -m "docs(tcg-card): global-rules 目录与交叉引用一致性收尾"
```

---

## Self-Review

- **Spec coverage**：意见 1→T1；2→T2;3→T2+T3;4→T5;5→T5;6→T4;7→T4;8→T4;9→T5;10→T2。验收标准 §5 → T6。全部覆盖。
- **Placeholder scan**：无 TBD/TODO；所有编辑均给出 before/after 实文本。
- **一致性**：§号引用（§4.1/§4.2/§九/§13.2/§14.5/§十四/§七）在各任务间用法一致；anonymous_account 措辞统一。

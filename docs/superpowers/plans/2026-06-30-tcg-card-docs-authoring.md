# TCG-Card v1.0 开发文档体系 撰写计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `docs/tcg_cord_docs/` 下零散的 9 份 PRD 与管理后台截图，整理为 `docs/tcg-card/` 下一套完整、无冲突、可直接驱动 AI 开发的文档体系。

**Architecture:** 分层文档集——全局性内容（架构/数据模型/API/全局规则/开发计划）各自成册，业务模块按模块分文件，顶层 README 用相对链接串联。撰写顺序遵循依赖：术语与范围 → 架构 → 数据与 API → 全局规则 → 模块 PRD → 流程/状态机 → 后台 → 开发计划 → 索引。

**Tech Stack:** 纯 Markdown 文档；流程图与状态机用 Mermaid。无代码、无测试框架。

## Global Constraints

- 交付物为**纯文档**，不写任何业务代码、不搭脚手架。
- 文档语言：**中文叙述 + 英文标识符**（字段名 / 接口名 / 枚举值 / 表名用英文）。
- 原始资料 `docs/tcg_cord_docs/` **保持不动**，仅作为溯源来源。
- 所有外部依赖决策用统一 `⚠️ TBD` 标注，注明影响面与决策方，**不静默假设**。
- 单一真相源：跨切面规则（涨跌算法、加载/失败/空状态、Toast、货币、游客迁移）只在 `global-rules.md` 定义，其他文档**引用而非重复**。
- Spec 依据：`docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md`，本计划所有决策以该 spec 为准。
- 范围基准：v1.0 只交付 iOS 范围；Scan 不做真扫描（保留 Tab + 占位引导）；不做订阅；游客采用**后端匿名账号同步**口径。
- 每份文档顶部含：标题、一句话定位、最后更新日期、上游来源链接（指向 `docs/tcg_cord_docs/` 对应原件）。
- 每完成一个任务即提交一次 git commit，message 用中文，格式 `docs(tcg-card): <内容>`。

---

## 文件结构总览

```
docs/tcg-card/
├── README.md                         # Task 12
├── 00-product/
│   ├── overview.md                   # Task 1
│   ├── glossary.md                   # Task 1
│   └── modules/
│       ├── global-rules.md           # Task 5
│       ├── auth.md                   # Task 6
│       ├── profile.md                # Task 6
│       ├── home.md                   # Task 7
│       ├── collection.md             # Task 7
│       ├── search.md                 # Task 8
│       ├── card-detail.md            # Task 8
│       └── scan.md                   # Task 8
├── 01-flows/
│   ├── flows.md                      # Task 9
│   └── state-machines.md             # Task 9
├── 02-architecture/
│   ├── architecture.md               # Task 2
│   ├── monorepo.md                   # Task 2
│   └── tech-stack.md                 # Task 2
├── 03-data-api/
│   ├── data-model.md                 # Task 3
│   ├── third-party.md                # Task 3
│   └── api-spec.md                   # Task 4
├── 04-admin/
│   └── admin.md                      # Task 10
└── 05-plan/
    └── dev-plan.md                   # Task 11
```

**依赖关系：** Task 1 → 2 → 3 → 4 → 5 → {6,7,8} → 9 → 10 → 11 → 12。
（6/7/8 之间无强依赖，可并行；都依赖 1–5。9 依赖模块 PRD；10 依赖 3/4；11 依赖全部；12 最后。）

---

### Task 1: 产品基石 —— overview.md + glossary.md

**Files:**
- Create: `docs/tcg-card/00-product/overview.md`
- Create: `docs/tcg-card/00-product/glossary.md`

**Interfaces:**
- Produces: v1.0 范围边界（包含/延后/删除清单）、模块清单、统一术语表。后续所有文档引用本任务定义的术语与范围。

- [ ] **Step 1: 撰写 glossary.md**

  按下列条目逐条给出"英文标识符 + 中文释义 + 一句话用法"，至少覆盖：
  `Portfolio`（资产集合，参与总资产计算）、`Wishlist`（心愿单，不参与资产）、`Folder/Portfolio Folder`（文件夹，区分不同 Portfolio 集合）、`default folder`（星标默认文件夹，唯一、不可删）、`Collection Item`（用户持有记录，含数量/状态/价格口径）、`Grader`（评级机构：Raw/PSA/BGS/CGC/SGC/TAG/AGS）、`Condition`（Raw 品相）、`Grade`（评级等级）、`Finish/Variant`（工艺/版本）、`Sealed Product`（套盒/卡包/整箱）、`Raw / Graded / Sealed`（三类状态口径）、`Trending Today`、`Most Valuable`、`Guest / Anonymous Account`（游客匿名账号）、`override layer`（卡牌覆盖层）、`30D Change`。
  释义口径必须与 spec §2、§4 一致。

- [ ] **Step 2: 撰写 overview.md**

  章节：①产品定位（海外 TCG/球星卡收藏管理 App）②目标平台（v1.0 仅 iOS，Android 延后）③模块清单（Auth/Home/Collection/Search/Scan/CardDetail/Profile/启动引导/管理后台/后端）④v1.0 范围边界三张表，**逐项从 spec §5 抄入**：
  - ✅ 包含：见 spec §5「包含」
  - ⏳ 延后：Scan 真扫描识别、Home Performance Tab（标"预留接口/后续版本"）
  - ❌ 删除/隐藏：订阅全部、Restore（标 TBD）、客服 Subscription 选项
  ⑤Scan 导航处理（保留 Tab + 占位引导页）⑥一句话说明"跨切面规则见 global-rules.md，架构见 02-architecture/"。

- [ ] **Step 3: 自检验收清单**

  逐条确认：术语表覆盖 Step 1 全部条目且无歧义；overview 的三张范围表与 spec §5 完全一致；订阅/Performance/真扫描均出现在正确分类；术语英文标识符大小写统一；两份文档顶部含定位+日期+来源链接。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/00-product/overview.md docs/tcg-card/00-product/glossary.md
git commit -m "docs(tcg-card): 产品需求总览与术语表"
```

---

### Task 2: 技术架构 —— architecture.md + tech-stack.md + monorepo.md

**Files:**
- Create: `docs/tcg-card/02-architecture/architecture.md`
- Create: `docs/tcg-card/02-architecture/tech-stack.md`
- Create: `docs/tcg-card/02-architecture/monorepo.md`

**Interfaces:**
- Consumes: overview.md 的范围与平台决策。
- Produces: 分层架构图、Workers 职责划分、两层数据策略、技术选型表、Monorepo 包划分与公有化边界。data-model / api-spec / dev-plan 引用本任务的分层与包结构。

- [ ] **Step 1: 撰写 architecture.md**

  内容来自 spec §4.1–4.4：①整体分层图（Mermaid，App + 后台 Web → Workers → D1 + 第三方+缓存）②Workers 职责（用户资产 CRUD / 第三方代理+缓存两类）③两层数据策略（第三方实时层只读不落库；D1 override 层；读取覆盖层优先回落第三方）④货币与涨跌幅口径（金额存原始货币+原值，展示换算；百分比按原始序列不随货币变；公式以 global-rules.md 为准）⑤缓存与降级策略（KV + Cache API，第三方失败时降级到缓存/占位）。

- [ ] **Step 2: 撰写 tech-stack.md**

  把 spec §4.7 选型表落入，每项给"选型 + 理由"：App=Flutter+Riverpod+Dio+go_router+freezed；后台前端=React+Vite+TS+Ant Design+TanStack Query；后端=Workers+Hono+Drizzle ORM；缓存=KV+Cache API；Monorepo=pnpm workspaces+Turborepo（TS）+Melos（Dart）；邮件=Resend（默认）/SES 备选（标 TBD）。补充"待定子项"小节：汇率接口、第三方数据源厂商、OAuth 凭证（均引用 §6 TBD）。

- [ ] **Step 3: 撰写 monorepo.md**

  内容来自 spec §4.6：①顶层目录草案（`apps/`：flutter-app、admin-web、workers-api；`packages/`：auth-core、api-client、ui-kit、workers-common；Dart 侧共享包目录）②公有化模块边界——逐个说明 auth-core / api-client / ui-kit / workers-common 的职责与"与 tcg-card 业务无关、可跨项目复用"的边界③TS 与 Dart 双 monorepo 工具如何协作（Turborepo 管 TS、Melos 管 Dart、顶层约定）④业务包依赖通用包的方向规则（业务→通用，禁止反向）。

- [ ] **Step 4: 自检验收清单**

  确认：架构图含全部 4 个外部块且方向正确；两层数据"覆盖层优先回落第三方"明确；选型表 6 行齐全且各有理由；TBD 子项均链接到统一 TBD 来源；monorepo 包职责与公有化边界与 spec §4.6 一致；依赖方向规则明确。

- [ ] **Step 5: Commit**

```bash
git add docs/tcg-card/02-architecture/
git commit -m "docs(tcg-card): 技术架构、技术选型与Monorepo划分"
```

---

### Task 3: 数据模型与第三方接入 —— data-model.md + third-party.md

**Files:**
- Create: `docs/tcg-card/03-data-api/data-model.md`
- Create: `docs/tcg-card/03-data-api/third-party.md`

**Interfaces:**
- Consumes: architecture.md 两层数据策略；glossary.md 术语。
- Produces: D1 全部表结构与 ER 图、第三方数据字段映射与降级口径。api-spec / admin / 模块 PRD 引用这些表名与字段。

- [ ] **Step 1: 撰写 data-model.md —— 用户/账号层**

  给出表结构（英文表名/字段名 + 类型 + 约束 + 说明），覆盖：
  - `user`（正式账号：id、email、password_hash、created_at…）
  - `anonymous_account`（匿名账号：id、device_id、created_at、upgraded_user_id 可空——升级正式账号后回填）
  - `auth_identity`（第三方登录：user_id、provider=google|apple、provider_uid）
  - `session`（JWT 会话/刷新令牌）
  - `verification_code`（邮箱验证码：email、code、expires_at、purpose=register|reset）
  说明匿名账号→正式账号的升级映射（呼应 spec §4.5）。

- [ ] **Step 2: 撰写 data-model.md —— 资产层**

  覆盖：
  - `portfolio_folder`（owner_id 指向 user 或 anonymous、name、is_default、sort_order、created_at；约束：同 owner 名称唯一、默认唯一）
  - `collection_item`（owner_id、folder_id、card_ref 第三方卡标识、object_type=tcg|sports|sealed|other、grader、condition、grade、language、finish、quantity、purchase_price、purchase_currency、notes、created_at）
  - `wishlist_item`（owner_id、card_ref、created_at；无文件夹、无数量）
  - `user_preference`（owner_id、currency、amount_hidden、last_selected_folder_id）
  明确"同一张卡可多条 collection_item（不同状态分别记）"。

- [ ] **Step 3: 撰写 data-model.md —— 覆盖层 + 运营 + 反馈**

  覆盖：
  - `card_override`（card_ref、字段级覆盖 JSON、image_url、is_missing_card 手动录入标记、updated_by、updated_at——支撑后台"卡牌数据运维"）
  - `trending_pin`（运营置顶 Trending：card_ref、rank、active）
  - `app_config`（运营配置 KV：启动引导图、版本升级提示、公告、协议链接等）
  - `feedback_ticket`（客服工单：email、types[]、functions[]、message、status、created_at）
  并补 ER 图（Mermaid erDiagram），标主外键关系。

- [ ] **Step 4: 撰写 third-party.md**

  ①可插拔数据源适配层设计（不绑定具体厂商，定义统一接口口径：searchCards、getCard、getPriceSeries、getTrending、getSoldListings）②第三方原始字段 → App 展示字段的映射表（卡名、系列、编号、Finish、Raw/Graded 价、30D 序列、成交记录等）③缓存策略（各接口缓存 TTL 建议、KV/Cache 分工）④降级策略（第三方失败→读缓存→占位 `--` / `-/-`，对齐 global-rules）⑤`⚠️ TBD`：具体厂商（TCGplayer/eBay/PriceCharting）、API 密钥、汇率接口提供方。

- [ ] **Step 5: 自检验收清单**

  确认：spec §8 要求的实体全部建表（用户/匿名账号、文件夹、collection_item、wishlist、偏好、覆盖层、反馈工单、运营配置）；匿名账号升级路径有字段支撑；多 collection_item 规则有体现；ER 图主外键完整；third-party 适配层为厂商无关；缓存与降级口径与 architecture/global-rules 一致；TBD 标注齐全。

- [ ] **Step 6: Commit**

```bash
git add docs/tcg-card/03-data-api/data-model.md docs/tcg-card/03-data-api/third-party.md
git commit -m "docs(tcg-card): 数据模型(D1)与第三方数据接入"
```

---

### Task 4: API 规范 —— api-spec.md

**Files:**
- Create: `docs/tcg-card/03-data-api/api-spec.md`

**Interfaces:**
- Consumes: data-model.md 表与字段；third-party.md 适配层接口。
- Produces: 全部 REST 接口契约。flutter-app、admin-web、dev-plan 引用这些端点。

- [ ] **Step 1: 撰写通用约定**

  ①Base URL / 版本前缀（如 `/api/v1`）②鉴权方式（JWT Bearer；匿名账号也持 token）③统一响应包络（success/data/error）④统一错误码与对应文案（对齐 global-rules：通用失败、网络异常、表单错误）⑤分页/排序/筛选 query 约定。

- [ ] **Step 2: 撰写鉴权与账号接口**

  逐个端点给"方法+路径+请求体+响应+错误"：匿名账号创建/获取、邮箱注册（发码/验码/设密）、邮箱登录、找回密码（发码/验码/重置）、Google/Apple OAuth 回调、刷新 token、登出、删除账号、匿名→正式升级（迁移资产）、获取账号信息。对齐 `注册登录.md` 与 `个人中心.md` 的校验与文案。

- [ ] **Step 3: 撰写资产接口**

  文件夹 CRUD + 排序 + 设默认；collection_item CRUD（含移动文件夹）；wishlist 增删；user_preference 读写（货币、金额隐藏、最后选中文件夹）。每个写操作标注影响（如删除文件夹连带删卡、Home 需刷新）。

- [ ] **Step 4: 撰写数据代理接口**

  搜索（Cards/Sets，带 Game/IP 与关键词）、卡牌详情（含 Price/Market Prices/Shop 分区）、价格序列（周期参数）、Trending Today、成交记录、汇率换算、Collect 快捷加入。明确这些走 third-party 适配层 + 缓存。

- [ ] **Step 5: 撰写后台接口**

  用户管理（列表/详情/禁用，含游客匿名账号可见）、反馈工单（列表/详情/状态流转）、运营配置（app_config 读写、trending_pin）、卡牌数据运维（card_override CRUD、缺失卡录入、补图）。

- [ ] **Step 6: 自检验收清单**

  确认：spec §8 要求的 API 覆盖面齐全（鉴权/资产 CRUD/搜索价格 Trending 代理/后台）；每个端点引用的字段都能在 data-model 找到；错误码与 global-rules 文案一致；后台用户管理能看到匿名账号；OAuth 与升级迁移端点存在。

- [ ] **Step 7: Commit**

```bash
git add docs/tcg-card/03-data-api/api-spec.md
git commit -m "docs(tcg-card): REST API 接口规范"
```

---

### Task 5: 全局规则单一真相源 —— global-rules.md

**Files:**
- Create: `docs/tcg-card/00-product/modules/global-rules.md`

**Interfaces:**
- Consumes: glossary.md；data-model 价格口径。
- Produces: 全局涨跌算法、加载/失败/空状态、Toast、货币、游客迁移、确认弹窗、防重复点击、状态优先级、统一文案表。所有模块 PRD 引用本文件。

- [ ] **Step 1: 迁移并固化全局规则**

  以 `docs/tcg_cord_docs/全局用其他补充事项.md` 为底稿迁入，逐节保留并固化：涨跌幅公式（通用/7D/30D/周期/Portfolio总资产/Collection Item/Most Valuable/Search）、局部 vs 整页加载失败、loading 动效、操作失败 Toast、网络异常、图片缺失、金额与百分比、登录账号规则、确认弹窗、刷新、防重复点击、状态优先级、统一文案表。

- [ ] **Step 2: 写入"已固化的口径"小节（消解 spec §7 冲突）**

  显式记录并替换：①缺价卡 → 展示 `--`、不计入总资产/Most Valuable ②相同单张价值排序 → 30 天涨幅优先 → 最近添加时间优先 ③"入库时间倒序/数据库无匹配"等措辞 → 统一为"以第三方聚合数据为准" ④游客资产口径 → 指向 spec §4.5 后端匿名账号同步，并**明确标注此处修正了原 PRD"仅本地、不跨设备、卸载丢失"的旧措辞**。

- [ ] **Step 3: 自检验收清单**

  确认：全部涨跌公式无遗漏；统一文案表与原 PRD §十三一致；spec §7 全部 5 条冲突均有显式固化；游客口径变更有醒目标注；本文件被声明为跨切面规则的唯一真相源。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/00-product/modules/global-rules.md
git commit -m "docs(tcg-card): 全局规则单一真相源(含冲突固化)"
```

---

### Task 6: 模块 PRD 批 A —— auth.md + profile.md

**Files:**
- Create: `docs/tcg-card/00-product/modules/auth.md`
- Create: `docs/tcg-card/00-product/modules/profile.md`

**Interfaces:**
- Consumes: global-rules.md、glossary.md、api-spec.md。
- Produces: Auth 与 Profile 模块完整 PRD。flows/state-machines 引用其流程。

- [ ] **Step 1: 撰写 auth.md**

  以 `注册登录.md` 为底稿，结构化为：入口、注册/登录方式（Email/Google/Apple）、Email 注册流程、Email 登录流程、找回密码流程、邮箱校验规则、密码规则、验证码规则、成功 toast、全部错误文案。跨切面失败/网络/Toast **引用 global-rules**。接口处引用 api-spec 对应端点。补齐：匿名→正式升级在 Auth 流程中的位置（引用 global-rules 游客口径）。

- [ ] **Step 2: 撰写 profile.md**

  以 `个人中心.md` 为底稿，结构化为：游客态页面、登录态页面、Account 详情、删除账号确认、Customer Support（反馈表单字段/校验/提交）、Score 评分、Share、Terms/Privacy、Log Out、账号与资产绑定规则、状态与异常。**删除订阅相关**（Upgrade/Subscribe/Restore——Restore 标 TBD）、客服 Subscription 选项删除。游客资产迁移引用 global-rules。

- [ ] **Step 3: 自检验收清单**

  确认：auth 五条流程（注册/登录/找回/Google/Apple）齐全且错误文案完整；profile 订阅内容已删除、Restore 标 TBD；两份文档跨切面规则均为引用 global-rules 而非重复；接口引用 api-spec 存在的端点；顶部含定位+日期+来源链接。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/00-product/modules/auth.md docs/tcg-card/00-product/modules/profile.md
git commit -m "docs(tcg-card): Auth 与 Profile 模块PRD"
```

---

### Task 7: 模块 PRD 批 B —— home.md + collection.md

**Files:**
- Create: `docs/tcg-card/00-product/modules/home.md`
- Create: `docs/tcg-card/00-product/modules/collection.md`

**Interfaces:**
- Consumes: global-rules.md、glossary.md、data-model.md。
- Produces: Home 与 Collection 完整 PRD。

- [ ] **Step 1: 撰写 home.md**

  以 `home页说明.md` 为底稿：页面定位、入口、顶部区域、Portfolio 总资产卡片（含图表取价规则）、资产隐藏、Most Valuable、Trending Today、文件夹切换/新建/编辑/排序/删除弹窗、货币切换、无数据/加载失败状态、核心交互、数据展示规则、与其他模块关系。**Performance Tab 标"延后(1.0.1)"**。涨跌公式、失败、Toast、货币 **引用 global-rules**。

- [ ] **Step 2: 撰写 collection.md**

  以 `collection说明.md` 为底稿：定位、入口、顶部、Portfolio Tab（字段/取价/涨跌）、金额隐藏（与 Home 联动）、排序/筛选/搜索、卡牌点击与分享、Wishlist Tab、文件夹管理（与 Home 一致——指向 home.md，不重复）、异常、数据范围、业务规则。跨切面引用 global-rules。

- [ ] **Step 3: 自检验收清单**

  确认：home 的图表取价/Most Valuable/Trending 规则完整且涨跌公式引用 global-rules；Performance Tab 标延后；collection 文件夹管理指向 home 不重复正文；金额隐藏 Home/Collection 联动有写；缺价卡口径引用 global-rules 固化值；顶部元信息齐全。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/00-product/modules/home.md docs/tcg-card/00-product/modules/collection.md
git commit -m "docs(tcg-card): Home 与 Collection 模块PRD"
```

---

### Task 8: 模块 PRD 批 C —— search.md + card-detail.md + scan.md

**Files:**
- Create: `docs/tcg-card/00-product/modules/search.md`
- Create: `docs/tcg-card/00-product/modules/card-detail.md`
- Create: `docs/tcg-card/00-product/modules/scan.md`

**Interfaces:**
- Consumes: global-rules.md、glossary.md、data-model.md、api-spec.md。
- Produces: Search、Card Detail、Scan 完整 PRD。

- [ ] **Step 1: 撰写 search.md**

  以 `search.md` 为底稿：定位、入口、顶部搜索区、Cards Tab 统一结构、四类卡字段（TCG/体育/Sealed/特殊）、涨跌百分比规则、Qty 规则、Collect/Collected、Wishlist 爱心、快捷默认 Collection Item、Cards 列表规则、Sets Tab。把"入库时间倒序"等措辞按 global-rules 固化口径调整为"第三方数据为准"。

- [ ] **Step 2: 撰写 card-detail.md**

  以 `卡牌详情.md` 为底稿：两态（未加入/已加入 Portfolio）、各对象类型基础信息、Price Tab（图表/Market Prices/Shop）、Collection Item 字段（四类）、编辑 Collection Item 页（表单/校验/规则）、Remove from Portfolio/Wishlist、状态与异常、数据展示规则。跨切面引用 global-rules，接口引用 api-spec。

- [ ] **Step 3: 撰写 scan.md（v1.0 预留）**

  顶部醒目标注：**v1.0 不做真扫描识别；保留底部 Scan Tab，点进为"扫描功能即将上线"占位页 + 引导到 Search**。随后**完整保留** `scan.md` 原始流程（拍摄/批量 Review/Collection Item 合并编辑/权限/异常等）作为"后续版本设计留档"，并清晰用分隔说明"以下为 future 版本，不在 v1.0 实现"。

- [ ] **Step 4: 自检验收清单**

  确认：search 四类卡字段与列表/详情口径一致、措辞已对齐第三方口径；card-detail 两态字段完整、编辑校验齐全；scan 顶部 v1.0 占位说明醒目、原流程作为 future 留档且边界清晰；三份跨切面均引用 global-rules；顶部元信息齐全。

- [ ] **Step 5: Commit**

```bash
git add docs/tcg-card/00-product/modules/search.md docs/tcg-card/00-product/modules/card-detail.md docs/tcg-card/00-product/modules/scan.md
git commit -m "docs(tcg-card): Search、CardDetail、Scan 模块PRD"
```

---

### Task 9: 业务流程与状态机 —— flows.md + state-machines.md

**Files:**
- Create: `docs/tcg-card/01-flows/flows.md`
- Create: `docs/tcg-card/01-flows/state-machines.md`

**Interfaces:**
- Consumes: 全部模块 PRD、global-rules.md。
- Produces: 核心流程图与关键状态机（Mermaid）。

- [ ] **Step 1: 撰写 flows.md（Mermaid 流程图）**

  至少覆盖：①注册/登录/找回密码端到端 ②游客使用→注册迁移 / 游客→登录已有账号（不合并）③Search→Collect 加入 Portfolio ④卡牌详情添加/编辑/移除 Collection Item ⑤文件夹切换对 Home/Collection 的联动 ⑥货币切换刷新链路。每图配文字说明并链接对应模块 PRD。

- [ ] **Step 2: 撰写 state-machines.md（Mermaid 状态图）**

  至少覆盖：①账号身份状态机（游客匿名 → 正式账号 / 登出 / 删除账号，对齐 spec §4.5）②收藏对象状态（未收藏 / 在 Wishlist / 在 Portfolio，及互斥规则）③文件夹状态（普通/默认/当前选中/删除）④Scan 扫描项状态（标注：future 版本，留档）。

- [ ] **Step 3: 自检验收清单**

  确认：Step 1 六条流程齐全、与模块 PRD 不矛盾；账号状态机与 global-rules 游客口径一致；收藏对象互斥（同对象不同时在 Portfolio 与 Wishlist）有体现；Scan 状态机标注 future；Mermaid 语法可渲染。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/01-flows/
git commit -m "docs(tcg-card): 业务流程图与状态机"
```

---

### Task 10: 管理后台 PRD（新写）—— admin.md

**Files:**
- Create: `docs/tcg-card/04-admin/admin.md`

**Interfaces:**
- Consumes: data-model.md、api-spec.md（后台接口）、overview 范围。
- Produces: 管理后台四大模块 PRD。

- [ ] **Step 1: 参考截图并撰写四大模块**

  参考 `docs/tcg_cord_docs/ui/管理后台/` 截图（作为视觉参考，**以 spec 选定的四块范围为准**，截图与范围冲突时以范围为准）。逐模块写定位/页面/字段/操作/异常：
  ①用户管理（正式+匿名账号列表/详情/禁用，可见游客；查看其资产）
  ②反馈/客服工单（列表/详情/状态流转，对应 feedback_ticket）
  ③运营配置（启动引导图、版本升级提示、公告、协议链接、Trending 置顶——对应 app_config / trending_pin）
  ④卡牌数据运维（card_override 增改、缺失卡录入、补图、字段纠错）。

- [ ] **Step 2: 写后台通用规则**

  登录鉴权（后台账号体系或复用，标 TBD 若未定）、权限/角色（v1.0 是否单一管理员，标明）、列表分页/搜索/筛选约定、操作二次确认与失败提示（引用 global-rules 风格）。

- [ ] **Step 3: 自检验收清单**

  确认：四大模块全覆盖且字段映射到 data-model 表；用户管理含匿名账号；运营配置项与 app_config 对应；卡牌运维与 card_override 对应；接口引用 api-spec 后台端点；范围与 spec §2 一致（不含订阅）；未定项标 TBD。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/04-admin/admin.md
git commit -m "docs(tcg-card): 管理后台PRD(新写)"
```

---

### Task 11: 开发计划 —— dev-plan.md

**Files:**
- Create: `docs/tcg-card/05-plan/dev-plan.md`

**Interfaces:**
- Consumes: 全部文档。
- Produces: 分阶段里程碑、任务拆分、依赖、每阶段验收标准。

- [ ] **Step 1: 撰写阶段里程碑**

  建议阶段：M0 工程基建（Monorepo + Workers + D1 + CI，引用 monorepo/tech-stack）→ M1 鉴权与账号（含匿名账号同步）→ M2 数据代理层（搜索/价格/Trending + 缓存）→ M3 核心资产（文件夹/Portfolio/Wishlist/Collection Item）→ M4 三大页面（Home/Collection/Search）→ M5 卡牌详情 → M6 Profile/客服/启动引导 → M7 管理后台 → M8 iOS 联调/上线准备（OAuth/邮件/协议链接/审核项）。每阶段标依赖与可交付。

- [ ] **Step 2: 撰写任务拆分与验收**

  每个里程碑列出主要任务条目 + 该阶段验收标准（可演示/可测的成果），并标注其依赖的文档与 TBD 阻塞项（如 M2 依赖第三方厂商选定、M1 依赖邮件服务与 OAuth 凭证）。给出建议的关键路径与可并行项。

- [ ] **Step 3: 自检验收清单**

  确认：里程碑覆盖 overview 全部 v1.0 包含项；每阶段有依赖与验收标准；TBD 阻塞项标注到对应阶段；Scan 真扫描/Performance/Android 标为后续不在 v1.0 关键路径；纯文档无代码。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/05-plan/dev-plan.md
git commit -m "docs(tcg-card): 分阶段开发计划"
```

---

### Task 12: 顶层索引与一致性收尾 —— README.md

**Files:**
- Create: `docs/tcg-card/README.md`

**Interfaces:**
- Consumes: 全部文档。
- Produces: 导航索引 + 全局一致性校验结果。

- [ ] **Step 1: 撰写 README.md**

  ①项目一句话简介 ②推荐阅读顺序（新人路径：overview→glossary→architecture→data-model→api-spec→global-rules→模块→flows→admin→dev-plan）③完整文档目录树带相对链接 ④术语表入口 ⑤TBD 总清单（汇总各文档 ⚠️ TBD，集中一处便于决策跟踪）⑥溯源说明（原始资料在 `docs/tcg_cord_docs/`）。

- [ ] **Step 2: 全局一致性收尾校验**

  通读全部文档，逐项核对并就地修正：①所有相对链接可达 ②术语用法跨文档一致（对照 glossary）③跨切面规则均"引用 global-rules"无重复定义 ④api-spec 引用字段都能在 data-model 找到、模块 PRD 引用端点都在 api-spec ⑤v1.0 范围在各文档表述一致（订阅删除/Scan 占位/Performance 延后/仅 iOS）⑥TBD 标注风格统一且 README 已汇总。

- [ ] **Step 3: 自检验收清单（对照 spec §8 成功标准）**

  逐条核对 spec §8：文档结构齐全、四类文档齐全、9 份 PRD 无遗漏并入、冲突按 §7 统一、TBD 显式标注、数据模型覆盖面、API 覆盖面、开发计划要素齐全、"AI 可据此独立开始 v1.0 iOS 开发"。发现缺口就地补任务或补内容。

- [ ] **Step 4: Commit**

```bash
git add docs/tcg-card/README.md
git commit -m "docs(tcg-card): 顶层索引与全局一致性收尾"
```

---

## 计划自检（对照 spec）

- **Spec 覆盖：** spec §3 文档结构 → Task 1–12 逐文件覆盖；§4 架构决策 → Task 2/3；§4.5 游客口径 → Task 3/5/9；§5 范围 → Task 1 + 各模块；§6 TBD → 各任务标注 + Task 12 汇总；§7 冲突固化 → Task 5 Step 2 + Task 8 Step 1；§8 成功标准 → Task 12 Step 3 逐条核对。无遗漏。
- **占位符扫描：** 各任务步骤给出了具体章节、来源映射、要消解的冲突与验收清单（文档型任务的"应有内容"），无 TBD/TODO/"稍后补充"。文档正文 prose 在执行阶段产出，符合纯文档交付性质。
- **一致性：** 表名/字段（user、anonymous_account、collection_item、card_override、feedback_ticket、app_config、trending_pin 等）在 Task 3 定义，Task 4/10 引用一致；global-rules 单一真相源在 Task 5 确立，Task 6–9 一致引用。

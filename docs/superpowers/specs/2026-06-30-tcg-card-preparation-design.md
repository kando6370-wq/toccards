# TCG-Card v1.0 前期准备 · 设计总纲（Spec）

> 状态：已与负责人确认，待最终 review
> 日期：2026-06-30
> 作者：wuxuyi + AI
> 类型：前期准备产出物设计（纯文档体系）

---

## 1. 背景与目标

公司转战海外市场，开发一款类似球星卡 / TCG 集换式卡牌的 App，项目名 **tcg-card**，包含 **App 端**与**管理后台**。第一个版本 **v1.0**，App 用 Flutter，**先交付 iOS**，Android 延后；全程由 AI 辅助开发。

产品已给出零散的原型图与分模块 PRD（位于 `docs/tcg-card/source-tcg-card-docs/`），但内容分散、存在口径冲突、且服务端 / 数据来源 / 管理后台几乎无文字说明。

**本次任务目标（已确认为纯文档交付）：** 把零散材料整理成一套**完整、无冲突、能直接驱动 AI 开发**的开发文档体系，覆盖：产品需求总览、业务流程+状态机、技术架构+Monorepo 划分、数据模型+API 规范+开发计划。

**本次任务不包含**：编写业务代码、搭建 Monorepo 骨架或脚手架（留待后续开发阶段）。

---

## 2. 已确认的关键决策

| 领域 | 决策 |
|---|---|
| 交付物 | **纯文档体系**（不含代码 / 骨架） |
| 卡牌目录 & 价格数据 | **第三方聚合 API 实时接入**：Workers 做代理+缓存，D1 不长期存储目录/价格 |
| 卡牌数据运维 | D1 设**覆盖层（override）**：补充缺失卡、纠错、补图、运营数据；读取时覆盖层优先、回落第三方 |
| Scan 扫描识别 | **v1.0 不做真扫描**；保留底部 Scan Tab，点进为"即将上线"占位页 + 引导到 Search |
| Auth | **自建于 Workers + D1**：D1 存用户/密码哈希/会话，Workers 签 JWT，自接 Google/Apple OAuth |
| 游客态 | **后端匿名账号同步**（见 §4 调和口径） |
| 管理后台 | v1.0 范围：用户管理、反馈/客服工单、运营配置、卡牌数据运维（现仅有截图，需新写 PRD） |
| 订阅 | v1.0 **不做**，相关 UI 全部删除/隐藏 |
| 平台 | v1.0 **只交付 iOS 范围**，Android 仅架构预留 |
| 文档语言 | **中文叙述 + 英文标识符**（字段名/接口名/枚举值用英文） |

---

## 3. 文档集结构（产出物布局）

原始零散资料保留在 `docs/tcg-card/source-tcg-card-docs/` 不动（作为溯源）。整理后的文档产出到 `docs/tcg-card/`：

```
docs/tcg-card/
├── README.md                         # 顶层索引：文档导航 + 阅读顺序 + 术语表入口
├── 00-product/                       # 【产品·需求总览】
│   ├── overview.md                   #   产品定位、v1.0 范围边界、模块清单、删减项
│   ├── glossary.md                   #   术语统一(Portfolio/Collection Item/Folder/Grader...)
│   └── modules/                      #   按模块汇编的 PRD（对齐冲突、补齐缺口）
│       ├── auth.md
│       ├── home.md
│       ├── collection.md
│       ├── search.md
│       ├── scan.md                   #     v1.0 预留说明 + 完整流程留档
│       ├── card-detail.md
│       ├── profile.md
│       └── global-rules.md           #     涨跌算法/加载失败/Toast/货币/游客迁移
├── 01-flows/                         # 【业务流程 + 状态机】
│   ├── flows.md                      #   核心流程图（Mermaid）
│   └── state-machines.md             #   关键状态机（扫描项/收藏对象/账号-游客/文件夹）
├── 02-architecture/                  # 【技术架构 + Monorepo 划分】
│   ├── architecture.md               #   总体架构、Workers 分层、第三方接入与缓存策略
│   ├── monorepo.md                   #   目录/包划分、公有化模块边界、复用约定
│   └── tech-stack.md                 #   技术选型与理由
├── 03-data-api/                      # 【数据模型 + API 规范】
│   ├── data-model.md                 #   D1 表结构/ER、用户资产层 + 卡牌覆盖层
│   ├── api-spec.md                   #   REST 接口契约（鉴权/资产/搜索代理/价格代理/后台）
│   └── third-party.md                #   第三方数据源接入口径、字段映射、降级策略
├── 04-admin/                         # 管理后台 PRD（新写）
│   └── admin.md
└── 05-plan/                          # 【开发计划】
    └── dev-plan.md                   #   分阶段里程碑、任务拆分、依赖、验收标准
```

**组织原则**：分层文档集（每份文件单一职责、可独立喂给 AI），全局性内容各自成册，业务模块按模块分文件，顶层 README 用相对链接串起来。

---

## 4. 要写进文档的架构决策

### 4.1 整体分层

```
Flutter App (iOS先行) ──┐
                        ├──► Cloudflare Workers (API网关/BFF) ──► D1 (用户资产 + 卡牌覆盖层)
管理后台 Web ───────────┘                │
                                         └──► 第三方聚合API (目录/价格/Trending/成交) + 缓存(KV/Cache)
```

### 4.2 Workers 职责
统一 API 网关。对外提供 REST；对内分两类：
1. **用户资产 CRUD** → 落 D1（folder / collection_item / wishlist / 偏好）。
2. **第三方数据代理 + 缓存** → 搜索、价格、Trending、成交记录，经 KV / Cache API 缓存并带降级。

**App 和管理后台都不直连第三方**，统一经 Workers。

### 4.3 数据分两层
- **第三方实时层**：目录 / 价格只读，Workers 缓存，不落 D1 长期存储。
- **D1 覆盖层（override）**：①用户资产 ②卡牌补充/纠错/补图/运营数据（Trending 置顶等）。
- **读取规则**：覆盖层优先，回落第三方实时数据。

### 4.4 货币与涨跌幅口径
- 金额存"原始货币 + 原值"，展示时按汇率接口换算。
- **百分比按原始价格序列计算，不随货币切换变化**（PRD 已明确，固化为全局统一规则）。
- 涨跌幅公式以 `global-rules.md` 为单一真相源（7D/30D/周期通用公式见原 PRD §二）。

### 4.5 游客态 —— 后端匿名账号同步（冲突调和口径）

> ⚠️ 此口径**修正**了原 `全局用其他补充事项.md` 中"游客资产仅本地、不跨设备、卸载可能丢失"的措辞。以本节为准，并在 `global-rules.md` 中标注该变更。

- 首次启动即在后端创建**匿名账号**（绑定设备标识），游客资产实时同步到 D1 → 后台用户管理可见游客、资产有服务端备份。
- 匿名账号**无登录凭证**，用户**无法跨设备登录恢复**（换设备 = 新匿名账号）。即"用户视角不可跨设备"成立。
- **注册** = 匿名账号升级为正式账号（资产保留）。
- **登录已有账号** = 不合并匿名资产（保留 PRD 原则）。

### 4.6 公有化模块边界（Monorepo 复用核心）
抽出与"球星卡业务"无关的通用能力做成独立包，未来新项目直接复用：
- `auth-core`：鉴权通用逻辑
- `api-client`：客户端网络层
- `ui-kit`：通用 UI 组件
- `workers-common`：D1 访问 / JWT / 缓存 / 错误处理
- 业务包（tcg-card 专属）依赖通用包。

### 4.7 技术选型（已确认）

| 层 | 选型 | 理由 |
|---|---|---|
| App | Flutter + Riverpod + Dio + go_router + freezed | Riverpod 类型安全可测试；freezed 配合不可变状态与 JSON 序列化 |
| 后台前端 | React + Vite + TypeScript + Ant Design + TanStack Query | Ant Design 自带成熟后台组件，开发后台最快；与 Workers 同 TS 生态 |
| 后端 | Cloudflare Workers + Hono + Drizzle ORM | Hono 专为 Workers 设计；Drizzle 对 D1 类型安全、迁移友好 |
| 缓存 | Workers KV + Cache API | 第三方价格/搜索缓存与降级 |
| Monorepo 工具 | pnpm workspaces + Turborepo（TS 侧）+ Melos（Dart/Flutter 侧） | TS 与 Dart 两套生态分别用各自 monorepo 工具，顶层统一约定 |
| 邮件 | Resend（默认），SES 备选 | Resend 对 Workers DX 好、接入简单 |

---

## 5. v1.0 范围边界

### ✅ 包含
- Auth：Email 密码 + 验证码 + Google + Apple；找回密码
- Home：Portfolio 概览、总资产、价值图表、Most Valuable、Trending Today、文件夹管理、货币切换
- Collection：Portfolio + Wishlist、排序/筛选/搜索、分享
- Search：Cards + Sets、Collect/Wishlist 快捷操作、各卡类字段
- 卡牌详情：未加入/已加入两态、Price Tab、Collection Item 增删改
- Profile：游客态/登录态、Account、客服反馈、评分、分享、删除账号
- 全局：涨跌算法、加载/失败/空状态、Toast、货币、游客匿名账号同步+迁移
- 启动引导页
- 管理后台：用户管理、反馈工单、运营配置、卡牌数据运维
- 后端：Workers API 网关、D1、第三方数据代理+缓存、覆盖层

### ⏳ 延后（文档标"预留接口/后续版本"）
- Scan 真扫描识别（拍照识别）
- Home 顶部 Performance Tab（PRD 标 1.0.1）

### ❌ 删除/隐藏
- 所有订阅相关（Upgrade to Pro / Subscribe / PRO 标识）
- Restore 恢复购买（除非 App Store 审核要求保留 → 见 TBD）
- 客服反馈里的 Subscription 选项

### 平台
- v1.0 只交付 iOS 范围；Apple 登录、iOS 原生分享按 iOS 实现；Android 仅架构预留。

### Scan 导航
- 保留底部 Scan Tab，点进为"扫描功能即将上线"占位页 + 引导到 Search。

---

## 6. 待定项（TBD）

文档中用统一 `⚠️ TBD` 标注，注明影响面与决策方，不静默假设。

| # | 待定项 | 影响 | 默认处理 |
|---|---|---|---|
| 1 | 第三方数据源具体厂商（TCGplayer / eBay / PriceCharting…）、API 申请与密钥 | 字段映射、整个搜索/价格能力 | 按"可插拔数据源适配层"写，不绑定具体厂商 |
| 2 | 汇率接口提供方 | 货币换算 | 按统一汇率服务接口抽象 |
| 3 | 邮件服务 Resend vs SES | 验证码发送 | 默认 Resend |
| 4 | Apple/Google OAuth 开发者账号与凭证 | 第三方登录 | 文档写流程，凭证标 TBD |
| 5 | Restore 恢复购买是否保留 | Profile 页 | 默认隐藏，按 App Store 审核确认 |
| 6 | 官网协议链接（Terms/Privacy）、官网下载页 | Profile 跳转、分享 | 标 TBD，上线前配置 |
| 7 | PRD 中"建议补充"项（缺价卡口径、相同价值排序等） | 细节规则 | 取 PRD 建议值固化为明确规则，不留模糊 |

---

## 7. 整理过程中需统一的口径（去冲突清单）

整理 PRD 汇编时，对以下已知冲突/模糊点统一处理：
1. "入库时间倒序""数据库无匹配"等隐含自建库的措辞 → 统一为"以第三方聚合数据为准"，标注口径。
2. 游客资产本地 vs 后端同步 → 以 §4.5 调和口径为准。
3. 缺失价格卡牌的展示与计入规则 → 取 PRD 建议（展示 `--`、不计入总资产/Most Valuable）固化。
4. 相同单张价值的排序 → 取 PRD 建议（30 天涨幅优先 → 最近添加时间优先）固化。
5. 全局文案、Toast、空状态/失败状态以 `global-rules.md` 为单一真相源，各模块引用而非重复定义。

---

## 8. 成功标准（验收条件）

- `docs/tcg-card/` 下全部文档按 §3 结构产出，顶层 README 可导航。
- 四类文档齐全：产品需求总览、业务流程+状态机、技术架构+Monorepo、数据模型+API+开发计划。
- 原 9 份 PRD 内容无遗漏地并入模块文档，已知冲突按 §7 统一。
- 所有外部依赖决策以 `⚠️ TBD` 显式标注，无静默假设。
- 数据模型覆盖：用户/匿名账号、文件夹、Collection Item、Wishlist、偏好、卡牌覆盖层、反馈工单、运营配置。
- API 规范覆盖：鉴权、用户资产 CRUD、搜索/价格/Trending 代理、后台接口。
- 开发计划给出分阶段里程碑、任务拆分、依赖关系与每阶段验收标准。
- AI 可据此文档独立开始 v1.0 iOS 开发，无需再回头追问基础架构与范围问题。

---

## 9. 下一步

本 spec 经 review 通过后，使用 **writing-plans** 制定"逐份文档的撰写计划"（每份文档的内容大纲、撰写顺序与依赖），随后进入文档撰写执行阶段。

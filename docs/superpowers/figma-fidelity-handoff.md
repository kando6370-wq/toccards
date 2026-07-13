# 卡牌 App — Figma 设计还原 & 收口交付手册（Handoff）

> 目标（唯一核心）：让 App **可用（usable）** + **高还原度（贴合 Figma 设计）**。
> 本文档面向接手的同事，自带现状、已做改动、未验证项、待办清单、验证步骤与 Figma 映射，读完即可接着干。
>
> 生成时间：2026-07-13 ｜ 生成者：Claude Code（设计还原轮）
> 关联分支：`design/figma-fidelity-pass`（基于 `main`）

---

## 0. TL;DR（30 秒读懂）

1. App 代码已建到里程碑 **M0–M7 全部 completed**，只剩 **M8 上线准备** 未做（见 `docs/superpowers/execution-status.md`）。
2. 设计系统**已经落在代码里**（`apps/flutter-app/lib/shared/ui/kando_style.dart`），颜色 tokens 与 Figma 完全一致。
3. 本轮用 Figma MCP 对 **6 个业务模块做了逐屏 UI 精修**（只改 UI 层，未碰数据/逻辑），改动都在分支 `design/figma-fidelity-pass` 的**工作区（尚未 commit）**。
4. ⚠️ **精修改动尚未通过验证门**（本地无 Flutter，`flutter analyze` / `flutter test` 没跑）。**接手第一件事就是补验证。**
5. 要达成"可用 + 高还原"，还有明确缺口：**scan 扫描流未实现**、**品牌字体/卡图资源未接入**、**若干 Figma 专属组件（表格/图表/轮播）待补**。详见第 4、5 节。

---

## 1. ⚠️ 接手第一步：把改动 commit + 跑验证门（阻塞项）

本轮精修是 UI 层改动，**还没经过任何自动化验证**，也**还没 commit**。请先固化并验证。

### 1.1 固化改动（在有 git 的机器上；不需要 Flutter）
```bash
git checkout design/figma-fidelity-pass        # 分支已存在
git status                                       # 确认 10 个改动文件（见第 3 节）
git add -A
git commit -m "style(flutter): Figma 逐屏 UI 精修（6 模块，UI 层）"
git push -u origin design/figma-fidelity-pass    # 推给同事拉取
```

### 1.2 跑完成门（需要装了 Flutter 的机器）
仓库要求：每次交付至少一次 **打包 + 自动化单测**（见 `CLAUDE.md` → Completion gate）。
```bash
# 方式 A（对齐 Dart CI）：仓库根执行
flutter pub get
dart run melos run analyze
dart run melos run test

# 方式 B（只测 Flutter app）
cd apps/flutter-app
flutter analyze
flutter test
```

### 1.3 判定标准
- `flutter analyze` **0 error**（info/warning 视情况修）。
- `flutter test` 全绿。**特别注意**：多个 widget 测试断言了精确文案 / widget key（见下），精修 agent 已刻意保留，但仍需实跑确认：
  - `apps/flutter-app/test/widget/collection_page_test.dart`：`'N cards'` / `'N graded'` / `'Qty: N'` / `'Main'` / 空态文案 `'No cards in this portfolio yet.'` / sheet 里的 `'Japanese'` `'Apply'`
  - 各页保留的 key：`home-hide-amount`、`collection-hide-amount`、`collection-filter-button`、`search-field`、`search-clear-button`、`search-card-<id>`、`search-wishlist-<id>`、`card-detail-scroll`、`feedback-email-field`、`feedback-message-field`、`auth-agreement-text` 等。
- 若 analyze/test 失败：多半是精修引入的小问题（未用的 import、const、括号）。修掉后再 commit。**验证未过之前，不得对外宣称"已完成"**（`CLAUDE.md` 规则十二）。

---

## 2. 现状快照

| 维度 | 状态 |
|---|---|
| 后端 Workers API | M1–M7 completed（鉴权/数据代理/CRUD/管理后台）|
| Flutter App 架构 | 已成型：`lib/app/`（theme/router）、`lib/shared/`、`lib/features/*`（home/collection/card_detail/search/profile/auth/onboarding/scan）|
| 设计系统 | 已落码：`lib/shared/ui/kando_style.dart` + `theme.dart` + `app_shell.dart`（5 Tab 底部导航）|
| 本轮精修 | 6 模块 UI 精修完成，**未验证、未 commit** |
| 已知功能缺口 | **scan 扫描仅占位页**；弹窗分散；M8 上线项未做 |
| 还原度缺口 | 品牌字体、真实卡图、若干 Figma 专属组件未接 |

---

## 3. 本轮精修改了哪些文件（分支 `design/figma-fidelity-pass`）

> 全部只改 UI 层。看完整 diff：`git diff main...design/figma-fidelity-pass`

| 模块 | 改动文件 | 精修要点 |
|---|---|---|
| **home** | `lib/features/home/home_page.dart` | 概览/货币双 pill 头部；Portfolio 卡片重构（r16 + 大号 accent 数值 + 眼睛切换）；图表区间从 ChoiceChip 改分段控件 + 虚线基线 + accent 渐变面积；Most Valuable / Trending 卡片化；收藏夹 & 货币 bottom sheet 重做 |
| **collection** | `lib/features/collection/collection_page.dart` | 药丸分段 Tab；搜索框内嵌筛选按钮；Portfolio 汇总卡；单列改 **2 列卡片网格**；筛选 sheet（SORT/LANGUAGE/GAME/IP）；收藏夹 sheet |
| **card_detail** | `lib/features/card_detail/card_detail_page.dart` | 深色 ink 画布 + 扁平 AppBar；hero 卡加高 + accent 辉光；药丸 Tab（Collection Item / Price）；价格行改 bordered 面板；增删改按钮 accent 药丸化 |
| **search** | `lib/features/search/search_page.dart` | Figma 搜索框（内嵌 scan 图标）；游戏选择器字段；结果网格改**竖版卡片**（aspect 0.5）；wishlist 心形浮层；居中无结果空态 |
| **profile** | `lib/features/profile/profile_page.dart`、`account_page.dart`、`customer_support_page.dart` | ACCOUNT/SUPPORT/OTHERS 分组卡片；头像 accent 环 + 邮箱首字母；反馈页重做（药丸 chip + 提交按钮）；删除账号弹窗重做 |
| **auth + onboarding** | `lib/features/auth/ui/auth_sheet.dart`、`lib/features/auth/ui/email_auth_pages.dart`、`lib/features/onboarding/onboarding_page.dart` | 药丸第三方登录（Google/Apple/Email）；带标签输入框（label + r12 边框 + accent focus）；密码显隐；主 CTA 全宽 accent 药丸；引导页 CTA |

**未触碰**（精修红线）：任何 `*_controller.dart` / `*_repository.dart` / `*_models.dart` / `*_providers.dart` / `lib/app/router.dart` / `lib/main.dart` / `lib/shared/*` / `pubspec.yaml`。widget key、导航、表单逻辑、provider 接线全部保留。

---

## 4. 还原度未达标 / 待补（本轮有意留空，因为要动数据或资源）

这些是"高还原度"的剩余工作。精修 agent 在代码里留了 `// TODO(figma): ...`，可全局 grep 定位。

### 4a. 需要**后端/模型数据**支撑（改数据结构 + 后端字段）
| 待补项 | 位置 | 需要什么 |
|---|---|---|
| 卡片**真实图片** | collection / search / card_detail 现用占位图 | `CollectionItem` / 搜索结果 / 详情模型缺 `imageUrl` 字段；需后端返回卡图 URL |
| **Most Valuable 横向轮播** | `home_page.dart` | 模型每文件夹只暴露 1 个精选，Figma 是多卡轮播；需 `List<Highlight>` |
| **Market Prices 分级表格** | `card_detail_page.dart` | Figma 是 Ungraded/PSA/ACE/BGS × GRADE/MARKET/7D 表格；现仅 flat `priceTabMarketRows` |
| **价格折线图** | `card_detail_page.dart` | 无图表 widget / series 几何；需引图表库 + 数据 |
| **收藏夹增删改** | `home_page.dart` `_showFolderSheet` | `HomeController` 只有 `selectFolder`，缺 create/rename/delete/reorder action（后端可能已有接口，需接线）|
| **货币搜索框** | `home_page.dart` 货币 sheet | 需筛选状态 |
| **订阅/购买恢复** | `profile_page.dart` | Figma 有 SUBSCRIBE/Restore，无对应 action |

### 4b. 需要**资源/资产**接入（改 `pubspec.yaml` assets）
| 待补项 | 说明 |
|---|---|
| **品牌字体** | Figma 用 **Fraunces**（衬线展示字）+ **Geist**（无衬线正文）；当前用系统默认近似字号字重。需下载字体、放 `apps/flutter-app/assets/fonts/`、在 `pubspec.yaml` 声明、在 `theme.dart` 配 `fontFamily`。**这是提升还原度最快见效的一步。** |
| **Google / Apple 品牌图标** | 现用 Material 单色图标近似；需彩色 Google "G" + 白色 Apple SVG/PNG |
| **空态插画** | Figma 无结果/空 portfolio 用定制插画；现用 Material 图标近似 |

---

## 5. 功能缺口（直接影响"可用"）

### 5.1 🔴 scan 扫描模块（最大功能缺口）
- **现状**：`lib/features/scan/scan_page.dart` 只有占位页（无 controller/repository）。
- **Figma**：完整 **19 屏** 拍照识卡流（section `131:19436`「扫描页」）——相机取景、拍摄、识别中、识别结果、批量入库等。
- **要做成可用**：需新建 `scan_controller.dart` / `scan_repository.dart` / 模型；接入相机（如 `camera` 插件）；对接识别 API（后端是否已有识别端点需确认，见 `docs/tcg-card/03-data-api/`）；串联入库到 collection。
- **这是"UI 精修"覆盖不到的净新增功能**，需单独立项（建议作为一个里程碑）。

### 5.2 弹窗（🟡 分散待系统化）
- Figma section `221:2139`「弹窗」有 7 类通用弹窗；代码里散落在各模块。建议抽一套共享弹窗组件对齐 Figma。

### 5.3 M8 上线准备（🟡）
见 `execution-status.md` → M8：OAuth 凭证填入、iOS 联调、生产端点收尾等（生产 admin/API 域名已在近期 commit 接通）。

---

## 6. Figma 设计源 & 节点映射（给继续还原的人）

- **文件**：卡牌app — `https://www.figma.com/design/DjacfTioobtRy59SnqH7SY/`
- **接入方式**：Figma **远程 MCP**（`https://mcp.figma.com/mcp`），需 **付费会员 + 对该文件有编辑权限** 的账号 OAuth 授权。见第 9 节。
- **两页结构**：
  - `01 Foundations`（`40:27`）+ `02 Components`（`40:28`）= 设计系统规范「Vault & Vellum」
  - `40:30` = 全部成品屏幕，下分 7 个 section：

| 业务模块 | Figma section id | Flutter 目录 |
|---|---|---|
| home | `131:21334` | `lib/features/home/` |
| 收集 collection | `142:10515` | `lib/features/collection/`（卡详情也在此 section）|
| 卡牌详情 card_detail | `142:10515` 内 | `lib/features/card_detail/` |
| 搜索 search | `142:9783` | `lib/features/search/` |
| 个人 profile | `183:8212` | `lib/features/profile/` |
| 注册登陆 auth | `183:8753` | `lib/features/auth/` + `lib/features/onboarding/` |
| **扫描 scan** | `131:19436` | `lib/features/scan/`（**仅占位，待建**）|
| 弹窗 dialogs | `221:2139` | 分散（待系统化）|

- **设计规范 frame（`02 Components` 页内，做还原时对照）**：
  - `368:8536` DS Spec 1 设计规范书 ／ `368:8580` 颜色系统 ／ `368:8699` 字体与字号（Type scale `368:8714`）／ `368:8760` 圆角·间距·效果 ／ `368:8827` 组件模式

---

## 7. 设计系统 tokens 现状（代码即真源）

`apps/flutter-app/lib/shared/ui/kando_style.dart` — 颜色已与 Figma 对齐：

| Token | 值 | 用途 |
|---|---|---|
| `ink` | `#10100B` | 页面底色（深色）|
| `surface` | `#1A1C14` | 卡片/输入框面 |
| `elevatedSurface` | `#2A2B20` | 抬升面 |
| `border` | `#464835` | 描边 |
| `text` | `#EEECD8` | 主文字 |
| `mutedText` | `#C7C8B0` | 次要文字 |
| `accent` | `#F0FE6F` | 主色（荧光黄绿）|
| `softAccent` | `#F0E7FF` | 柔和强调 |

- **涨跌语义色**当前为局部常量（无对应 token）：跌 `#E5484D` / `#F87171`，涨 `#4ADE80`。**建议**：给 `KandoColors` 增加 `gain`/`loss` 语义 token，统一各模块（精修时各 agent 各写了一份，需收敛）。
- **字体**：尚未接入 Fraunces/Geist（见 4b）。

---

## 8. 推荐推进顺序（P0 可用 → P1 还原 → P2 打磨）

**P0 — 让它可用 / 不回归**
1. commit + push 精修分支（第 1.1 节）
2. 跑 `flutter analyze` + `flutter test`，修掉所有问题（第 1 节）
3. 建 **scan 扫描流**（第 5.1 节）—— 这是唯一大的功能空洞
4. 收尾 **M8 上线项**

**P1 — 提升还原度**
5. 接 **Fraunces + Geist 字体**（4b，性价比最高）
6. 打通 **卡片真实图片** 数据链路（4a）
7. 补 Figma 专属组件：**价格折线图 / 分级价格表格 / Most Valuable 轮播**（4a）
8. **弹窗系统化** 对齐 Figma（5.2）
9. 收敛 **涨跌语义色 token**（第 7 节）

**P2 — 逐屏打磨**
10. 拿装了 Flutter 的机器，`flutter run` 逐屏截图，与 Figma 对屏精修间距/字重/微交互（自动精修无法肉眼比像素，这步必须人工）

---

## 9. 如何复用 / 重跑这套还原 workflow

- **Figma MCP 接入**（一次性）：
  ```bash
  claude mcp add --transport http figma https://mcp.figma.com/mcp
  # 然后 /mcp → figma → Authenticate，用【有会员 + 对文件有编辑权限】的账号 OAuth
  ```
  注意：新加的 MCP 需**重启 Claude Code 会话**（`claude --continue`）才会在 `/mcp` 出现。
- **精修 workflow 脚本**（可再跑/改）：
  `~/.claude/projects/-Users-git-kando-toC-toccards/<session>/workflows/scripts/figma-fidelity-refine-*.js`
  （按第 3 节的模块映射，一个模块一个 agent，只改 UI 层，收口 `flutter analyze`）
- 还原新模块（如 scan）时，可照此结构：先 `get_metadata(section)` 列屏，再 `get_design_context` / `get_screenshot` 逐屏读，再写 Flutter。

---

## 10. 执行日志

- **2026-07-13**：接入 Figma 远程 MCP（会员+编辑权限打通）；确认 `40:28`=设计规范、`40:30`=7 大模块成品屏；对 home/collection/card_detail/search/profile/auth+onboarding 六模块做 UI 层逐屏精修（分支 `design/figma-fidelity-pass`，10 文件，未 commit）。**完成门（analyze/test）因本地无 Flutter 未执行 → 状态：待验证，未标 completed。** scan 扫描流确认为待建功能缺口。

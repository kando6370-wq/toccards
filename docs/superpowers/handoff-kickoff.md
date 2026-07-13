# 接手启动指南（Handoff Kickoff）

> 给拿到最新代码的同事（人类或 AI Agent）：从这里开始，5 分钟进入状态。
> 关联：`figma-fidelity-handoff.md`（总路线）、`scan-module-taskbook.md`（scan 落地）
> 生成时间：2026-07-13

---

## 1. 环境准备（一次性）

```bash
# 1) 取代码 + 切到工作分支
git clone git@github.com:kando6370-wq/toccards.git
cd toccards
git checkout design/figma-fidelity-pass      # 本轮设计精修都在这条分支

# 2) 工具链（仓库要求，见 CLAUDE.md）
#    - Node >= 22, pnpm 11.9.0
#    - Flutter / Dart SDK ^3.9.2   ← 关键：必须本机装好 Flutter，否则跑不了验证门
corepack enable && corepack prepare pnpm@11.9.0 --activate   # 或自行安装 pnpm

# 3) 安装依赖
pnpm install                                  # TS 侧（workers-api / admin-web / packages）
flutter pub get                               # 仓库根即 Dart workspace 根，一次装全部
```

> ⚠️ **上一位交接人本机没有 Flutter**，所以本轮 UI 精修的验证门（analyze/test）**尚未跑过**。接手第一件事就是补验证（见第 3 步）。

---

## 2. 先读什么（按顺序，约 15 分钟）

1. **`CLAUDE.md`**（仓库根）—— 铁律：数据库 gate、完成门（每次交付必跑 打包+单测）、执行状态文档规范、双工作模式。
2. **`docs/superpowers/figma-fidelity-handoff.md`** —— 全局路线：现状、已做改动、P0/P1/P2 待办、Figma 节点映射、设计 tokens。
3. **`docs/superpowers/scan-module-taskbook.md`** —— scan 唯一大功能缺口的落地方案（T1–T6）。
4. **`docs/superpowers/execution-status.md`** —— 里程碑状态（M0–M7 completed，M8 todo；本轮设计任务为"待验证"）。
5. **`docs/tcg-card/README.md`** —— 产品/架构/数据模型/API 真源（代码注释多处声明要与之对齐）。忽略仓库根 `README.md`（是 GitLab 模板）。

---

## 3. 冒烟：先证明现状可跑 + 补验证门（P0）

```bash
# 静态分析 + 单测（对齐 Dart CI）
flutter pub get
dart run melos run analyze
dart run melos run test
# 或只测 App：
cd apps/flutter-app && flutter analyze && flutter test

# 真机/模拟器跑起来看
cd apps/flutter-app && flutter run
```
- 目标：`flutter analyze` 0 error、`flutter test` 全绿。若本轮精修引入小问题（未用 import / const / 括号），修掉再 commit。
- **通过前不得对外宣称"完成"**（CLAUDE.md 规则十二）。

---

## 4. 看设计稿做对照（还原度必需）

两种方式二选一：
- **接 Figma MCP**（推荐，可读节点级属性）：`figma-fidelity-handoff.md` 第 9 节有接入步骤（`claude mcp add` + OAuth，需付费会员 + 对文件有编辑权限的账号）。
- **导出图对照**：让有 Figma 权限的人把 section 导出 PNG（节点映射见手册第 6 节）。

---

## 5. 干活顺序（照手册第 8 节）

- **P0 可用**：① 补验证门 ② 建 scan 真流程（照 `scan-module-taskbook.md`）③ 收尾 M8 上线项
- **P1 还原**：① 接 Fraunces/Geist 字体 ② 卡图数据链路 ③ 价格图表/分级表格/轮播 ④ 弹窗系统化
- **P2 打磨**：装了 Flutter 的机器逐屏 `flutter run` 对照 Figma 精修

每完成一块：更新 `execution-status.md`（带 `[Mx-y]` 前缀才更新里程碑覆盖层）→ 跑完成门 → commit。

---

## 6. 如果用 AI Agent（Claude Code）执行：直接粘贴这段作为开场上下文

```
你在仓库 toccards 上继续「卡牌 App 的 Figma 设计还原 + 收口可用」工作。

必读（按序）：
1. CLAUDE.md（仓库铁律：数据库 gate、完成门=每次交付必跑 打包+单测、执行状态文档规范）
2. docs/superpowers/handoff-kickoff.md（启动指南）
3. docs/superpowers/figma-fidelity-handoff.md（总路线、P0/P1/P2、Figma 节点映射、设计 tokens）
4. docs/superpowers/scan-module-taskbook.md（scan 落地任务 T1–T6）
5. docs/superpowers/execution-status.md（里程碑状态）

当前分支：design/figma-fidelity-pass。上一轮做了 6 模块 UI 层精修（home/collection/card_detail/search/profile/auth+onboarding），但完成门（flutter analyze / flutter test）尚未执行。

请从 P0 开始，按顺序推进，每次只做一小块并遵守：
- 只在明确 scope 内改动；UI 精修不碰 controller/repository/models/providers/router/数据逻辑。
- 任何要改 D1/schema/迁移/wrangler 绑定的改动，先停下通知我确认（数据库 gate）。
- 每完成一块，跑完成门（flutter analyze + flutter test；Dart 侧 dart run melos run analyze/test），过了才更新 execution-status 为 completed；没过如实保留未完成。
- 先给我"本轮目标 + scope + 单轮验证方式 + 停机条件"，我确认后再动手。

第一步：跑 flutter analyze + flutter test，把上一轮精修的验证门补上并修掉所有问题，然后向我报告结果。
```

---

## 7. 一句话给人类同事

「拉 `design/figma-fidelity-pass` 分支 → 装 Flutter → 跑 `flutter analyze && flutter test` 修干净 → 按 `figma-fidelity-handoff.md` 的 P0/P1/P2 推进，scan 照 `scan-module-taskbook.md` 做 → 每块交付前必跑完成门、更新 `execution-status.md`。」

# Codex 最小交接上下文（2026-07-08）

## 1. 当前接力点

**当前 worktree：`D:\Projects\kando-global-project\.worktrees\m2-data-adapter`。**

**当前分支：`codex/m2-data-adapter`，已推送远程。**

当前主线已经推进到：

- M5 卡牌详情：`completed`，5 / 5
- M6 Profile / 客服 / 启动引导：`in_progress`，1 / 6
- M7 管理后台：`not_started`

下一轮默认从 **M6-2 Profile 登录态** 继续，不要进入 M7/Admin。

## 2. 真源说明

### 规则真源

- `CLAUDE.md`
- `docs/superpowers/claude-harness-rules.md`
- 本仓库 AGENTS 规则：始终简体中文、先思后码、外科手术式修改、TDD、关键步骤检查点、显式失败

### 计划真源

- `docs/tcg-card/05-plan/dev-plan.md`

### 运行态覆盖层

- `docs/superpowers/execution-status.md`

明确约束：

- `dev-plan.md` 是只读计划真源。
- `execution-status.md` 只负责展示当前运行态、状态覆盖层与执行日志。
- `docs/superpowers/plans` 与 `docs/superpowers/specs` 可作为历史设计和实施参考。

## 3. 本轮最新完成内容

### M5-4 Collection Item 增删改

已完成并推送：

- `9edcdfa docs: design M5 CardDetail Collection Item CRUD`
- `66e73e3 docs: plan M5 CardDetail Collection Item CRUD`
- `27972c7 feat: add CardDetail collection item draft state`
- `adf6be0 feat: render CardDetail collection item editor`
- `1bab1d0 docs: complete M5 CardDetail Collection Item CRUD status`

完成能力：

- CardDetail Collection Item 新增、编辑、删除
- Raw / graded 表单联动
- inline validation
- 删除二次确认
- mock-first，状态仅局限于 CardDetail

### M5-5 价格降级展示

已完成并推送：

- `1c4aeca docs: design M5 CardDetail price fallback states`
- `b3d187a docs: plan M5 CardDetail price fallback states`
- `fcb6cf5 feat: add CardDetail price fallback state`
- `543622f feat: render CardDetail price fallback states`
- `c55c4ca docs: complete M5 CardDetail price fallback status`

完成能力：

- Price Tab market price 缺失展示 `--`
- 7D change 缺失展示 `-/-`
- price series 无数据展示 `No price data available.`
- sold listings 无数据展示 `No sold listings available.`
- 现有有数据路径保持不变

### M6-1 Profile 游客态

已完成并推送：

- `e5d323b docs: design M6 Profile guest state`
- `469eabb docs: plan M6 Profile guest state`
- `36c937c feat: complete Profile guest state`
- `c01f451 docs: complete M6 Profile guest state status`

完成能力：

- Profile 游客态显示 `Guest session`
- 显示当前 anonymous id
- 显示 `Sign in / Sign up`
- 保留 Customer Support / Score / Share With Friends / Terms Of Use / Privacy Policy
- 游客态显示 Delete account，且不显示 Log Out
- 补齐底部 `Version 1.0.0`

## 4. 最新验证记录

M6-1 收口前已执行并通过：

- `flutter test test/widget/auth_profile_test.dart`：18 / 18 passed
- `flutter test test/auth_controller_test.dart`：21 / 21 passed
- `flutter pub get`：成功
- `dart run melos run test`：144 tests passed
- `flutter analyze`：No issues found
- `dart format --set-exit-if-changed lib test`：0 changed

M5-5 收口前已执行并通过：

- `flutter test test/card_detail_controller_test.dart`：14 / 14 passed
- `flutter test test/widget/card_detail_page_test.dart`：11 / 11 passed
- `flutter test test/widget/search_page_test.dart`：12 / 12 passed
- `dart run melos run test`：144 tests passed
- `flutter analyze`：No issues found
- `dart format --set-exit-if-changed lib test`：0 changed

## 5. 下一步建议：M6-2 Profile 登录态

推荐从 `docs/tcg-card/05-plan/dev-plan.md` 的 M6-2 继续：

> Profile 登录态：Account 详情（email / display_name）、评分 App、分享 App、删除账号；参见 `modules/profile.md`

建议最小切片：

1. 先读：
   - `CLAUDE.md`
   - `docs/superpowers/claude-harness-rules.md`
   - `docs/superpowers/execution-status.md`
   - `docs/tcg-card/05-plan/dev-plan.md`
   - `docs/tcg-card/00-product/modules/profile.md`
   - `apps/flutter-app/lib/features/profile/profile_page.dart`
   - `apps/flutter-app/lib/features/profile/account_page.dart`
   - `apps/flutter-app/lib/features/auth/auth_controller.dart`
   - `apps/flutter-app/test/widget/auth_profile_test.dart`
2. 先落设计文档：
   - `docs/superpowers/specs/YYYY-MM-DD-m6-profile-signed-in-state-design.md`
3. 再落实施计划：
   - `docs/superpowers/plans/YYYY-MM-DD-m6-profile-signed-in-state.md`
4. 再按 TDD 实现。

M6-2 推荐边界：

- 只补 Flutter Profile 登录态和 Account 详情可见字段。
- 复用现有 `AuthSession.email` / `AuthSession.userId`。
- 不接真实评分、真实分享、真实协议链接；这些受 TBD M6-A / M8 影响。
- 不改后端，不改数据库，不碰 M7/Admin。

## 6. 高风险约束

以下路径不要动，除非用户明确要求并再次确认：

- `docs/tcg-card/**`
- `apps/admin-web/**`
- `apps/workers-api/src/db/schema.ts`
- `apps/workers-api/src/db/migrations/*`
- `apps/workers-api/wrangler.toml`
- `apps/workers-api/drizzle.config.ts`

继续开发时保持：

- 非琐碎改动必须 TDD：先写失败测试，确认失败，再实现。
- Flutter tests 不要并发跑。
- 每个阶段完成后验证、提交、推送。
- 不要进入 M7 管理后台；M7 由另一个 worktree `m7-admin` 处理。
- 避免与 M7 合并冲突：不碰 `apps/admin-web/**`、Admin API、Admin schema 初始化、Admin docs 实现。

## 7. 新会话可直接使用的提示词

```text
请基于当前 worktree `D:\Projects\kando-global-project\.worktrees\m2-data-adapter`
继续开发，遵守：
- CLAUDE.md
- docs/superpowers/claude-harness-rules.md
- docs/superpowers/codex-handoff.md
- docs/superpowers/execution-status.md

当前分支 `codex/m2-data-adapter` 已推送远程。
M5 已全部完成，M6-1 Profile 游客态已完成。
请从 M6-2 Profile 登录态继续，做到 M7 管理后台之前停止。
不要触碰 docs/tcg-card/**、apps/admin-web/**、schema/migrations/wrangler/drizzle。
按 TDD 执行，阶段完成后验证、提交并推送。
```

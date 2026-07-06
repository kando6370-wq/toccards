# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace and toolchain

- Monorepo with two parallel ecosystems:
  - TypeScript/Node: `apps/admin-web`, `apps/workers-api`, `packages/*`
  - Dart/Flutter: `apps/flutter-app` (managed from the root `pubspec.yaml` workspace)
- Required runtimes from repo config:
  - Node `>=22` (`package.json`)
  - pnpm `11.9.0`
  - Dart SDK `^3.9.2` / Flutter (from `pubspec.yaml`)

## Common commands

### Root (TS workspace via pnpm + Turborepo)

- Install JS dependencies:
  - `pnpm install`
- Build all TS packages/apps:
  - `pnpm build`
- Type-check all TS packages/apps:
  - `pnpm type-check`
- Lint / dependency-boundary check:
  - `pnpm lint`
- Match the TS CI job locally:
  - `pnpm install --frozen-lockfile && pnpm build && pnpm type-check && pnpm lint`

### Admin web (`apps/admin-web`)

- Start dev server:
  - `pnpm --filter @kando/admin-web dev`
- Build:
  - `pnpm --filter @kando/admin-web build`
- Type-check:
  - `pnpm --filter @kando/admin-web type-check`
- Preview production build:
  - `pnpm --filter @kando/admin-web preview`

### Workers API (`apps/workers-api`)

- Start local Workers dev server:
  - `pnpm --filter @kando/workers-api dev`
- Build dry-run output to `dist/`:
  - `pnpm --filter @kando/workers-api build`
- Type-check:
  - `pnpm --filter @kando/workers-api type-check`
- Run all API tests:
  - `pnpm --filter @kando/workers-api test`
- Run a single API test file:
  - `pnpm --filter @kando/workers-api test -- src/auth/anonymous.test.ts`
- Generate Drizzle migrations from schema:
  - `pnpm --filter @kando/workers-api db:generate`
- Apply local D1 migrations:
  - `pnpm --filter @kando/workers-api db:migrate:local`

### Shared TS packages

- Build one package:
  - `pnpm --filter @kando/auth-core build`
  - `pnpm --filter @kando/api-client build`
  - `pnpm --filter @kando/ui-kit build`
  - `pnpm --filter @kando/workers-common build`
- Run shared auth tests:
  - `pnpm --filter @kando/auth-core test`
- Run a single shared auth test file:
  - `pnpm --filter @kando/auth-core test -- src/index.test.ts`

### Flutter workspace

- Install Dart/Flutter workspace dependencies from repo root:
  - `flutter pub get`
- Analyze all Dart/Flutter packages:
  - `dart run melos run analyze`
- Run all Dart/Flutter tests:
  - `dart run melos run test`
- Match the Dart CI job locally:
  - `flutter pub get && dart run melos run analyze && dart run melos run test`
- Run the Flutter app directly:
  - `cd apps/flutter-app && flutter run`
- Analyze only the Flutter app:
  - `cd apps/flutter-app && flutter analyze`

## Claude Code harness rules

### Dual working modes

- **快速开发模式**：优先做局部改动、局部验证、少弹权限，默认不主动扩大到整仓重构。
- **长期运行模式**：用于 `/loop` 或持续推进任务；每轮都必须声明目标、作用域、单轮验证和停机条件，连续 2~3 轮无实质进展就应停下并总结。

### Database change gate

- 原则上优先复用现有数据库结构、表和迁移。
- 任何会新增或修改数据库结构、迁移、D1 绑定、schema 契约的改动，都必须先通知用户并得到确认后再做。
- 高风险数据库面主要包括：
  - `apps/workers-api/src/db/schema.ts`
  - `apps/workers-api/src/db/migrations/*`
  - `apps/workers-api/wrangler.toml`
  - `apps/workers-api/drizzle.config.ts`

### Completion gate for every task

- 每次任务完成后，至少要执行一次**打包 + 自动化单元测试**。
- 当前阶段**不把前后端联调**作为每次任务结束的默认门槛。
- 由于完整打包 App 很慢，日常快速闭环优先采用 **Web/H5 风格验证**：
  - TS/Workers/Admin Web：跑 `pnpm build` 与相关单测
  - Dart/Flutter：跑 `dart run melos run test` / `flutter analyze`，而不是每次都做完整 App 打包
- 需要完整 App 打包与更重的联调时，应作为阶段性里程碑或人工确认后的收口动作，而不是每轮任务的默认步骤。

### Execution status document

- 必须维护执行状态文档：`docs/superpowers/execution-status.md`。
- 每次任务开始与完成后，都要更新当前任务状态、时间戳与任务摘要。
- 自动 hook 负责写入基础检查点；复杂多阶段任务在交付前仍需补充人工总结。

## Big-picture architecture

### Product/documentation source of truth

- Ignore the root `README.md` for implementation guidance; it is still the default GitLab template.
- The real project brief lives under `docs/tcg-card/`.
- Start with `docs/tcg-card/README.md`, which links the intended reading order for product, architecture, data model, API spec, admin behavior, and milestones.
- The tcg-card docs are unusually important here: many code comments explicitly say they must stay aligned with those docs.

### Monorepo shape

- `apps/admin-web`: React + Vite + TypeScript + Ant Design admin frontend.
- `apps/workers-api`: Cloudflare Workers backend using Hono + Drizzle + D1/KV.
- `apps/flutter-app`: Flutter client app.
- `packages/auth-core`: shared auth primitives (JWT signing/verification, refresh token hashing, password hashing).
- `packages/api-client`: intended shared Web API client layer.
- `packages/ui-kit`: intended shared UI primitives.
- `packages/workers-common`: intended shared Workers utilities.

Important current-state note: `api-client`, `ui-kit`, and `workers-common` are still placeholders with comments describing their future responsibilities. Do not assume they already contain production abstractions.

### Dependency direction is enforced

- The repo enforces a one-way dependency rule: `apps/` may depend on `packages/`, but `packages/` must not depend on `apps/`.
- `pnpm lint` runs `scripts/check-dep-direction.mjs`, which fails if any package depends on an app.
- Match this rule when introducing shared code: move reusable logic down into `packages/*`, but do not pull app-specific logic upward accidentally.

### Backend architecture

- The Workers app entrypoint is `apps/workers-api/src/index.ts`.
- Hono mounts everything under `/api/v1` and currently exposes:
  - `GET /health`
  - auth-related routes mounted from `src/auth/*`
- There is no ORM-based repository layer yet; route modules currently own request parsing, SQL statements, D1 access, and HTTP responses directly. Keep new backend changes consistent with that existing style unless you are intentionally doing a broader architectural refactor.
- Auth is split by use case rather than by framework layer:
  - `anonymous.ts`: create/reuse guest account, create session, seed default folder and preferences
  - `current.ts`: resolve current account from bearer token
  - `register.ts`: email verification + account creation + anonymous-to-user migration
  - `login.ts`: email/password login
  - `session.ts`: refresh access token and logout/revoke session
  - `forgot-password.ts`: password reset flow
- Shared auth crypto is intentionally kept in `@kando/auth-core`; route files compose that package with D1 SQL and HTTP responses.

### Data model and persistence

- D1 schema lives in `apps/workers-api/src/db/schema.ts` and is large enough that you should treat it as a product contract, not just implementation detail.
- The schema comment says it must stay aligned with `docs/tcg-card/03-data-api/data-model.md`.
- Current design uses:
  - ULID text primary keys
  - ISO8601 UTC timestamps as text
  - soft delete fields like `deleted_at`
  - polymorphic ownership via `owner_type + owner_id`
- Auth/session state, portfolio folders, collection items, wishlist, preferences, admin users, overrides, trending pins, app config, and feedback tickets are all modeled in D1.

### Override-first data flow

Per `docs/tcg-card/02-architecture/architecture.md`, the intended runtime model is:

1. clients call Workers only
2. Workers read/write user-owned data in D1
3. third-party market/card data is proxied through Workers
4. D1 override data wins over third-party data
5. KV / Cache API are used for cached third-party responses

This means backend changes often have cross-cutting impact across:
- D1 schema
- route SQL
- cache strategy
- tcg-card docs

### Frontend status

- `apps/admin-web` is currently an M0 placeholder, not a fleshed-out admin product.
- `src/main.tsx` wires up React Query and Ant Design globally.
- `src/App.tsx` is intentionally just a placeholder page.
- When adding real admin features, prefer following the documented target architecture rather than extrapolating from the current tiny UI surface.

### Flutter status

- `apps/flutter-app` is also still near scaffold state and still contains the default Flutter counter example in `lib/main.dart`.
- Root `pubspec.yaml` is the Dart workspace root and also contains the Melos scripts; there is no separate `melos.yaml`.
- The app package itself uses `resolution: workspace`, so workspace-level Dart dependency management matters.

## Repo-specific implementation guidance

### Treat docs as contracts when code comments say so

Several files explicitly say they align to docs, especially:
- `apps/workers-api/src/db/schema.ts`
- `scripts/check-dep-direction.mjs`
- docs under `docs/tcg-card/02-architecture` and `03-data-api`

Before changing schema shape, auth semantics, ownership rules, or package boundaries, read the corresponding tcg-card docs first.

### Be careful with Workers config placeholders

- `apps/workers-api/wrangler.toml` still contains placeholder `database_id` and KV namespace IDs.
- The comments indicate these are TBD and must be replaced after real Cloudflare resources are created.
- `apps/workers-api/drizzle.config.ts` is only for generating migration SQL; runtime database access is through Wrangler D1 bindings, not local DB credentials.
- Do not mistake the current values for working infrastructure.

### Testing intent already matters in this repo

- `packages/auth-core/src/index.test.ts` is a good style reference: tests explain why behavior matters (token trust boundary, fail-closed password verification, etc.), not just raw outputs.
- `apps/workers-api/src/auth/anonymous.test.ts` is the integration-style reference for the API layer: it exercises the Hono app directly with a fake D1 implementation and verifies auth/session/ownership lifecycle rules end to end.
- When extending auth behavior, keep tests focused on security and lifecycle intent, not only happy-path assertions.

### Current abstraction maturity

Right now the most real implementation is in:
- `apps/workers-api/src/auth/*`
- `apps/workers-api/src/db/schema.ts`
- `packages/auth-core/src/*`

The rest of the workspace is a mix of scaffold and planned extension points. When choosing where to add code, prefer the already-real modules unless you are intentionally establishing a new shared boundary.

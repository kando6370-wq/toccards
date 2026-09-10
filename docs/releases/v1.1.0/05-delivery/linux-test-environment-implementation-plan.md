# Linux Test Environment Implementation Plan

> 后续变更遵循当前根 `AGENTS.md`：BUGFIX 必须先复现并建立失败证据，再执行最小修复、回归验证与 Code Review。下方任务勾选及测试结果保留原始实施记录，不代表当前提交已重新验收。

## 当前实现边界（2026-09-10）

- 当前 main 已包含 Linux 测试环境，核对基线为 `main@659a7c6`；来源为 `19a6ac4`，分支监听器默认仍跟踪 dev。
- Cloudflare dev/test 与 prod 已完成 PostgreSQL 迁移，D1 已退役；Linux 使用独立 PostgreSQL。
- 当前扫描路由只使用 `VECTOR_RECOGNITION`，Linux 配置仍要求旧 `OCR_SERVICE_BASE_URL` 且未提供向量适配器。Linux 扫描不可用，填写 OCR 地址不能恢复，见[架构中的兼容缺口](../02-architecture/linux-test-environment.md#扫描兼容缺口)。
- 本轮未连接 kd201；下方 10 条 migration、容器运行与发布结果只对应注明的历史时间，当前 ledger、运行 SHA 及自动发布状态需重新核验。

**Goal:** Add a single-instance Linux test deployment that runs the existing Hono/PostgreSQL application without duplicating business code or changing Cloudflare production behavior.

**Architecture:** Extract the Hono application from the Worker adapter, reuse `PostgresDatabase` with `DATABASE_URL`, and provide Linux-only KV, filesystem object storage, execution-context, scheduler and HTTP-server adapters. Package PostgreSQL, API and Caddy/Admin through Docker Compose.

**Tech Stack:** Node.js 22, Hono, `@hono/node-server`, postgres.js, esbuild, PostgreSQL, Docker Compose and Caddy.

---

## File Map

- Modify `apps/workers-api/src/index.ts`: retain only Cloudflare fetch/scheduled adaptation.
- Create `apps/workers-api/src/app.ts`: shared Hono routes, CORS and scheduled task function.
- Modify `apps/workers-api/src/env.ts`: add configuration-only `ALLOWED_ORIGINS`.
- Create `apps/workers-api/src/linux/config.ts`: validate and map Linux environment variables.
- Create `apps/workers-api/src/linux/in-memory-kv.ts`: TTL cache adapter.
- Create `apps/workers-api/src/linux/filesystem-r2.ts`: local scan image adapter.
- Create `apps/workers-api/src/linux/execution-context.ts`: `waitUntil` tracking for Node.
- Create `apps/workers-api/src/linux/server.ts`: Node HTTP lifecycle and scheduler.
- Create `apps/workers-api/scripts/build-linux.mjs`: bundle Linux server with esbuild.
- Modify `apps/workers-api/package.json` and `pnpm-lock.yaml`: add Linux dependencies and scripts.
- Create `apps/admin-web/.env.linux` and modify `apps/admin-web/package.json`: same-origin Linux Admin build.
- Create `deploy/linux/Dockerfile`: API and Admin/Caddy targets.
- Create `deploy/linux/Caddyfile`: SPA hosting and API/share proxy.
- Create `deploy/linux/docker-compose.yml`: PostgreSQL, migration, API and Caddy services.
- Create `deploy/linux/migrate.sh`: ordered PostgreSQL migration ledger.
- Create `deploy/linux/.env.example`: non-secret configuration template.
- Create `deploy/linux/README.md`: server setup, deploy, backup, update and rollback commands.
- Create `deploy/linux/offline/*` and `docker-compose.offline.yml`: registry-blocked server fallback that packages the host Node 22 runtime, builds native-architecture PostgreSQL from the server's Ubuntu source and uses prebuilt application artifacts without changing business code.
- Modify `docs/releases/v1.1.0/README.md`: link design and operations documentation.

## Task 1: Shared Application Boundary

- [x] Move route registration, CORS and `runScheduledTasks` from `src/index.ts` to `src/app.ts`.
- [x] Preserve the Worker default export contract: `fetch`, `request` and `scheduled`.
- [x] Resolve CORS from `ALLOWED_ORIGINS` with current origins as the fallback.
- [x] Keep Hyperdrive mandatory in the Cloudflare adapter.

## Task 2: Linux Runtime Adapters

- [x] Load required Linux values: `DATABASE_URL`, `JWT_SECRET`, `OCR_SERVICE_BASE_URL`, `OBJECT_STORAGE_PATH`, `ALLOWED_ORIGINS` and `PORT`.
- [x] Build `Env` with the existing `createPostgresDatabase`.
- [x] Implement in-memory KV TTL for current string `get/put` calls.
- [x] Implement filesystem `put/get/delete` while preventing path traversal.
- [x] Track Node background promises used by `c.executionCtx.waitUntil`.
- [x] Run the shared scheduled tasks at the configured interval without overlap.
- [x] Gracefully close HTTP, background tasks and PostgreSQL on SIGTERM/SIGINT.

## Task 3: Build and Deployment Assets

- [x] Add `@hono/node-server` and esbuild to the Workers API package.
- [x] Bundle `src/linux/server.ts` to `dist/linux/server.mjs`.
- [x] Build Admin in Linux mode with `/api/v1/admin`.
- [x] Define API and Caddy image targets from the repository root.
- [x] Start PostgreSQL with a persistent volume; host access defaults to loopback, with the later explicit LAN override recorded below.
- [x] Apply missing PostgreSQL migration files once through `schema_migrations`.
- [x] Start API only after migration succeeds and PostgreSQL is healthy.
- [x] Proxy `/api/*` and `/share/*`; serve all other paths as the Admin SPA.
- [x] Add an offline Compose override for servers that cannot pull Node/Caddy images.

## Task 4: Documentation and Safety

- [x] Document first deployment, updates, logs, health checks and backup commands.
- [x] Document that Linux credentials and OCR endpoint must be independent test values.
- [x] Document that Linux does not modify Cloudflare resources; Cloudflare dev/prod now use PostgreSQL and D1 is retired.
- [x] Keep the existing UI autostash untouched.

## Task 5: Final Impacted Verification

Historical results from the original implementation; follow the current root verification rules for subsequent changes:

- [x] `pnpm --filter @kando/workers-api type-check`
- [x] Focused Workers tests for app/Worker runtime, PostgreSQL adapter and Linux adapters: 26/26 passed.
- [x] `pnpm --filter @kando/workers-api build:linux`
- [x] `pnpm --filter @kando/workers-api deploy:dry-run:dev`
- [x] `pnpm --filter @kando/workers-api deploy:dry-run:prod`
- [x] `node --test apps/admin-web/test/api-environment-intent.test.mjs`: 2/2 passed.
- [x] `docker compose -f deploy/linux/docker-compose.yml config`
- [x] PostgreSQL container became healthy; all 10 PostgreSQL migrations applied successfully and a second run skipped all 10 through the ledger.
- [x] Build/start API and Web containers, then verify `/api/v1/health`, Admin SPA and persisted image volume.

## Verification Record — 2026-08-26

- Linux Admin and Node bundle build passed; output includes `apps/workers-api/dist/linux/server.mjs`.
- Cloudflare dev/prod dry-runs passed and retained Hyperdrive, KV, R2 and environment-specific bindings.
- Compose configuration and migration shell syntax passed.
- Focused Workers tests passed 26/26; Linux Admin environment test passed 2/2.
- A mistakenly broad Workers test invocation ran 567 tests: 557 passed, 9 CORS failures were fixed in this task, and 1 existing D1-backed Performance test remains incompatible with the PostgreSQL-only SQL baseline.
- Full Admin test command remains red on two pre-existing `dev` baselines: a stale billing intent source assertion and local `i18n-iso-countries` resolution. The Linux Admin environment test is green.
- Code review found no conflict markers, diff whitespace errors or committed real secrets.

## Deployment Record — 2026-08-27

- Selected `kd201` because it was reachable, had 16 CPU cores, 30 GiB memory, 431 GiB free root storage and no conflict on port `8080`; `kd200` resolved to the previously known `192.168.50.200` address but current SSH credentials could not authenticate, so it was not modified.
- Deployed release `20260827-111216` to `/home/user/apps/toccards-test/releases/20260827-111216`; `/home/user/apps/toccards-test/current` points to that release.
- Docker Hub was unreachable from `kd201`. The offline override packaged the server's Node.js `22.22.1` runtime, built native `amd64` PostgreSQL `18.6` from the Ubuntu 26.04 source and used the same prebuilt Linux API/Admin artifacts.
- `db`, `api` and `web` are running; `migrate` exited successfully. The migration ledger contains all 10 migrations and a repeated migration run skipped all 10.
- `http://192.168.50.201:8080/api/v1/health` returned `{"status":"ok"}`; the Admin SPA returned `<title>Kando Admin</title>`; allowed-origin CORS returned the configured origin.
- The scan-image volume retained an exact probe value across an API container restart, and the health endpoint returned successfully after restart.
- The independent test OCR service is not available yet. `OCR_SERVICE_BASE_URL` intentionally uses the reserved `.invalid` domain, so scan recognition remains disabled without calling the production OCR service.

## Automatic Deployment Extension — 2026-09-09

- Added `.github/workflows/linux-test-deploy.yml` as a manual-only optional path that can run affected Linux checks, build the API/Admin artifact and dispatch deployment to a future `toccards-kd201` self-hosted runner.
- Added `deploy/linux/ci/deploy-release.sh` with deployment locking, artifact validation, PostgreSQL pre-deployment backup, immutable release directories, health gates and previous-application rebuild on failure.
- Added `watch-branch.sh` and `install-branch-watcher.sh`; `kd201` now uses user crontab to check `dev` every two minutes without repository Admin permission.
- Added `linux-test-auto-deployment.md` covering branch filtering, watcher installation, normal operations, retries, rollback and security boundaries.
- Local affected verification passed on 2026-09-09: workflow YAML, Bash guard, Workers type-check, 26 focused Workers tests, 2 Admin environment tests, Linux build and merged Compose configuration.
- A manual end-to-end invocation on `kd201` created a PostgreSQL backup and successfully switched from release `20260827-111216` to `manual-validation-20260909`; the API health response remained `{"status":"ok"}` and the migration ledger remained at 10.
- The branch watcher then completed a clean end-to-end feature-branch validation and switched to `branch-feature-linux-test-environment-2cd72364b6ad-20260909111201`. At that checkpoint the formal watcher tracked `dev` before the assets were merged. Merge `19a6ac4` is now present; a successful automatic deployment of the merged commit has not been reverified in this documentation update.
- Because the available GitHub account has push permission but no repository Admin/Actions Runner management permission, the GitHub workflow remains a manual-only future option and must not run concurrently with the watcher.
- On 2026-09-09, release `manual-pg-lan-20260909` added the explicit LAN-only PostgreSQL mapping `192.168.50.201:15432`. A direct Mac connection returned database `toccards_test`, user `toccards`, PostgreSQL `18.6` and migration count 10; the API health check remained green.

# Flutter Chrome Production API Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-command Flutter Chrome workflow connected to the production API.

**Architecture:** Centralize the Dart API base environment constant, pass the production URL through a fixed Chrome run command, and extend Worker CORS only for the fixed localhost origin.

**Tech Stack:** Flutter Web, Dart, Dio, Hono, Vitest, Cloudflare Workers

---

### Task 1: Shared Flutter API environment

**Files:**
- Create: `apps/flutter-app/lib/shared/api/api_environment.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Modify: `apps/flutter-app/lib/features/app_upgrade/app_upgrade_repository.dart`

- [ ] Define `kandoApiBaseUrl` from `KANDO_API_BASE_URL` with the existing local Worker fallback.
- [ ] Replace duplicated environment constants with the shared value.
- [ ] Run Dart analysis for the Flutter app.

### Task 2: Fixed Chrome production run command

**Files:**
- Modify: `package.json`
- Modify: `apps/flutter-app/README.md`

- [ ] Add a root script that runs Flutter on Chrome port `3000` with the production API dart define.
- [ ] Document the command and state that D1/KV remain behind the Worker.

### Task 3: Localhost CORS policy

**Files:**
- Modify: `apps/workers-api/src/index.ts`
- Modify: `apps/workers-api/src/cors.test.ts`

- [ ] Add a failing preflight test for `http://localhost:3000`.
- [ ] Extend the existing CORS origin resolver to allow only the production admin origin and fixed localhost origin.
- [ ] Run the focused Worker CORS test.

### Task 4: Verification and integration

**Files:**
- Verify: `apps/flutter-app`
- Verify: `apps/workers-api`

- [ ] Run static configuration checks and `git diff --check`.
- [ ] Run available focused tests and analysis.
- [ ] Commit the changes and push them to `main`.

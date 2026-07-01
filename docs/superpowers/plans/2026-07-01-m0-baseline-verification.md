# M0 Baseline Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the M0 engineering baseline is stable enough to start M1 authentication/account work, while preserving the user's existing uncommitted changes.

**Architecture:** This is a layered verification pass, not a feature build. Each task validates one boundary: workspace state, package management, TS monorepo, Dart/Flutter workspace, dependency direction, Workers API startup, and CI parity. Small configuration/script fixes are allowed only when the observed failure matches the approved spec.

**Tech Stack:** PowerShell, git, pnpm 11, Turborepo, TypeScript 5.7, Dart pub workspace, Melos 8, Flutter 3.35.5 CI image target, Cloudflare Workers, Wrangler, Hono.

---

## File Structure

Read-only during normal verification:

- `package.json`: top-level TS scripts and package manager declaration.
- `pnpm-workspace.yaml`: pnpm package inclusion and allowed build dependencies.
- `pnpm-lock.yaml`: frozen dependency baseline.
- `turbo.json`: TS task graph.
- `.gitlab-ci.yml`: CI command source of truth.
- `pubspec.yaml`: Dart pub workspace and Melos script source.
- `apps/flutter-app/pubspec.yaml`: Flutter app dependency and workspace membership.
- `apps/workers-api/package.json`: Workers scripts.
- `apps/workers-api/wrangler.toml`: Workers local startup configuration.
- `scripts/check-dep-direction.mjs`: dependency direction lint.
- `apps/*/package.json` and `packages/*/package.json`: package script coverage.

Allowed small-fix files when a command proves a local mismatch:

- `package.json`
- `pnpm-workspace.yaml`
- `turbo.json`
- `.gitlab-ci.yml`
- `pubspec.yaml`
- `apps/*/package.json`
- `packages/*/package.json`
- `scripts/check-dep-direction.mjs`

Do not modify:

- M1 authentication code.
- D1 business schema beyond M0 startup validation.
- Flutter Auth UI.
- External service credentials.
- Existing user changes unless the exact changed file is the proven root cause and the fix is approved by the small-fix rules.

## Global Failure Protocol

- [ ] For every failing command, record the command, exit code, and first actionable error line.
- [ ] Before editing, classify the failure as either small fix or approval-required using the spec at `docs/superpowers/specs/2026-07-01-m0-baseline-verification-design.md`.
- [ ] For a small fix, edit only the directly responsible file, rerun the failed command, then rerun the wider task command.
- [ ] For an approval-required issue, stop execution and report the exact blocker. Do not patch around it.
- [ ] Never describe a skipped command as passed. Mark it as not verified with the reason.

---

### Task 1: Workspace Baseline Inventory

**Files:**
- Read: `docs/superpowers/specs/2026-07-01-m0-baseline-verification-design.md`
- Read: `package.json`
- Read: `pnpm-workspace.yaml`
- Read: `pubspec.yaml`
- Read: `.gitlab-ci.yml`
- Modify: none

- [ ] **Step 1: Confirm the approved spec is present**

Run:

```powershell
Test-Path docs/superpowers/specs/2026-07-01-m0-baseline-verification-design.md
```

Expected: `True`.

- [ ] **Step 2: Capture current git status**

Run:

```powershell
git status --short
```

Expected: exit code `0`. The known user changes are allowed:

```text
 M apps/workers-api/package.json
 M pnpm-lock.yaml
 M pnpm-workspace.yaml
?? .claude/
```

If additional paths appear, classify them before continuing. Paths created by the current plan execution are allowed only if they are explicitly documented.

- [ ] **Step 3: Confirm no user changes are staged before verification**

Run:

```powershell
git diff --cached --name-status
```

Expected: no output. If output appears, stop and report it before running verification commands.

- [ ] **Step 4: Read the baseline config files**

Run each command:

```powershell
Get-Content -Raw package.json
Get-Content -Raw pnpm-workspace.yaml
Get-Content -Raw turbo.json
Get-Content -Raw .gitlab-ci.yml
Get-Content -Raw pubspec.yaml
```

Expected: each command exits `0`. Record the script names and CI commands used by later tasks.

---

### Task 2: Package Manager and Workspace Coverage

**Files:**
- Read: `package.json`
- Read: `pnpm-workspace.yaml`
- Read: `pnpm-lock.yaml`
- Conditionally modify: `pnpm-workspace.yaml`
- Conditionally modify: package `package.json` files when a workspace membership mismatch is proven

- [ ] **Step 1: Verify pnpm is available**

Run:

```powershell
pnpm --version
```

Expected: exit code `0`; version should be compatible with the top-level `packageManager` declaration `pnpm@11.9.0`.

- [ ] **Step 2: Verify frozen install consistency**

Run:

```powershell
pnpm install --frozen-lockfile
```

Expected: exit code `0` and no lockfile rewrite. If the command fails due registry or network access, rerun it once with escalated permission as required by the environment policy.

- [ ] **Step 3: List workspace packages**

Run:

```powershell
pnpm -r list --depth -1
```

Expected: exit code `0` and visible entries for:

```text
@kando/admin-web
@kando/workers-api
@kando/api-client
@kando/auth-core
@kando/ui-kit
@kando/workers-common
```

- [ ] **Step 4: Check for unintended lockfile changes**

Run:

```powershell
git diff --name-only -- pnpm-lock.yaml pnpm-workspace.yaml package.json
```

Expected: only pre-existing user changes are present. If `pnpm install --frozen-lockfile` changed a file, stop and report because frozen install should not rewrite dependency metadata.

---

### Task 3: TS Monorepo Build and Type Baseline

**Files:**
- Read: `package.json`
- Read: `turbo.json`
- Read: `apps/admin-web/package.json`
- Read: `apps/workers-api/package.json`
- Read: `packages/api-client/package.json`
- Read: `packages/auth-core/package.json`
- Read: `packages/ui-kit/package.json`
- Read: `packages/workers-common/package.json`
- Conditionally modify: script fields in the files above when a script mismatch is proven

- [ ] **Step 1: Verify top-level type-check script**

Run:

```powershell
pnpm run type-check
```

Expected: exit code `0`. This proves `turbo type-check` can traverse the TS workspace.

- [ ] **Step 2: Verify top-level build script**

Run:

```powershell
pnpm run build
```

Expected: exit code `0`. This proves package builds and app builds are wired into Turborepo.

- [ ] **Step 3: Verify CI-style turbo invocation**

Run:

```powershell
pnpm turbo build type-check
```

Expected: exit code `0`. If this differs from `pnpm run build` plus `pnpm run type-check`, classify it as a CI parity issue.

- [ ] **Step 4: Check generated output is limited to build artifacts**

Run:

```powershell
git status --short
```

Expected: user changes remain; build artifacts under ignored directories may exist but should not appear as tracked source changes. If tracked source files changed, stop and classify the change before continuing.

---

### Task 4: Dependency Direction Baseline

**Files:**
- Read: `scripts/check-dep-direction.mjs`
- Read: `apps/*/package.json`
- Read: `packages/*/package.json`
- Conditionally modify: `scripts/check-dep-direction.mjs` only if the script fails due a proven path/package discovery bug

- [ ] **Step 1: Run dependency direction lint**

Run:

```powershell
pnpm run lint
```

Expected: exit code `0`; output should state that package dependencies do not reverse-depend on apps.

- [ ] **Step 2: Confirm lint is represented in CI**

Run:

```powershell
Select-String -Path .gitlab-ci.yml -Pattern "pnpm run lint"
```

Expected: exit code `0` and a matching CI script line.

- [ ] **Step 3: Record coverage boundary**

Record in the final execution summary: this lint checks TS `packages/` against TS `apps/`. It does not prove Dart package direction unless Dart packages are later added to the workspace.

---

### Task 5: Dart and Flutter Workspace Baseline

**Files:**
- Read: `pubspec.yaml`
- Read: `pubspec.lock`
- Read: `apps/flutter-app/pubspec.yaml`
- Read: `apps/flutter-app/lib/main.dart`
- Read: `apps/flutter-app/test/widget_test.dart`
- Conditionally modify: `pubspec.yaml` or `apps/flutter-app/pubspec.yaml` when a workspace/script mismatch is proven

- [ ] **Step 1: Verify Flutter is available**

Run:

```powershell
flutter --version
```

Expected: exit code `0`. Record the version in the final summary. If Flutter is missing, mark Dart/Flutter verification as blocked by environment.

- [ ] **Step 2: Resolve Dart/Flutter workspace dependencies**

Run:

```powershell
flutter pub get
```

Expected: exit code `0` from the repository root.

- [ ] **Step 3: List Melos packages**

Run:

```powershell
dart run melos list
```

Expected: exit code `0` and `kando_app` listed.

- [ ] **Step 4: Run static analysis through Melos**

Run:

```powershell
dart run melos run analyze
```

Expected: exit code `0`.

- [ ] **Step 5: Run Flutter tests through Melos**

Run:

```powershell
dart run melos run test
```

Expected: exit code `0`.

---

### Task 6: Workers API Local Baseline

**Files:**
- Read: `apps/workers-api/package.json`
- Read: `apps/workers-api/wrangler.toml`
- Read: `apps/workers-api/src/index.ts`
- Read: `apps/workers-api/src/db/schema.ts`
- Conditionally modify: `apps/workers-api/package.json` when a script mismatch is proven
- Conditionally modify: `apps/workers-api/wrangler.toml` only for local startup configuration defects

- [ ] **Step 1: Run Workers package type-check**

Run:

```powershell
pnpm --filter @kando/workers-api run type-check
```

Expected: exit code `0`.

- [ ] **Step 2: Run Workers dry-run build**

Run:

```powershell
pnpm --filter @kando/workers-api run build
```

Expected: exit code `0`; `wrangler deploy --dry-run --outdir dist` completes without deploying.

- [ ] **Step 3: Start Workers locally and verify base route**

Run this as one PowerShell command block:

```powershell
$job = Start-Job -ScriptBlock { Set-Location 'D:\IdeaProjects\kando-global-project'; pnpm --filter '@kando/workers-api' run dev -- --port 8787 --local }
Start-Sleep -Seconds 15
try {
  try {
    $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/v1/' -UseBasicParsing
    $status = [int]$response.StatusCode
  } catch {
    $status = [int]$_.Exception.Response.StatusCode
  }
  $status
  if ($status -ne 404) { throw "Expected 404 but got $status" }
} finally {
  Stop-Job -Job $job -ErrorAction SilentlyContinue
  Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}
```

Expected: command prints `404` and exits `0`. A `404` is acceptable for M0 because it proves the Worker starts and the unregistered `/api/v1/` route does not crash the runtime.

---

### Task 7: CI Parity Check

**Files:**
- Read: `.gitlab-ci.yml`
- Read: `package.json`
- Read: `pubspec.yaml`
- Conditionally modify: `.gitlab-ci.yml` when a CI command references a non-existent local script
- Conditionally modify: `package.json` or `pubspec.yaml` when the local script is the proven missing entry

- [ ] **Step 1: Verify TS CI commands have local equivalents**

Run:

```powershell
Select-String -Path .gitlab-ci.yml -Pattern "pnpm turbo build type-check","pnpm run lint"
```

Expected: exit code `0` and both script lines are found.

- [ ] **Step 2: Verify Dart CI commands have local equivalents**

Run:

```powershell
Select-String -Path .gitlab-ci.yml -Pattern "dart run melos run analyze","dart run melos run test"
```

Expected: exit code `0` and both script lines are found.

- [ ] **Step 3: Re-run exact CI script commands locally**

Run:

```powershell
pnpm turbo build type-check
pnpm run lint
dart run melos run analyze
dart run melos run test
```

Expected: each command exits `0`. If one command is skipped because a prior environment prerequisite is missing, record it as not verified with the prerequisite name.

---

### Task 8: Final Baseline Decision

**Files:**
- Read: all files touched by prior tasks
- Modify: none unless a small fix was already performed and verified in its own task

- [ ] **Step 1: Capture final git status**

Run:

```powershell
git status --short
```

Expected: user changes are still present. Any new changes introduced by verification are explicitly known and tied to a small fix.

- [ ] **Step 2: Capture final diff summary**

Run:

```powershell
git diff --stat
```

Expected: output only includes user changes plus approved small fixes from this execution.

- [ ] **Step 3: Produce the final M0 decision**

Use exactly one of these decision labels in the final response, followed by a Chinese explanation:

```text
READY_FOR_M1
READY_FOR_M1_WITH_RISKS
NOT_READY_FOR_M1
```

Include:

- commands run and pass/fail summary;
- files changed by any small fix;
- commands not verified and why;
- remaining risk items;
- recommended next action.

- [ ] **Step 4: Commit verified small fixes only when fixes were made**

If no small fixes were made, do not create a commit.

If small fixes were made, stage only the allowed files modified by this execution and commit:

```powershell
$allowed = @(
  'package.json',
  'pnpm-workspace.yaml',
  'turbo.json',
  '.gitlab-ci.yml',
  'pubspec.yaml',
  'apps/admin-web/package.json',
  'apps/workers-api/package.json',
  'packages/api-client/package.json',
  'packages/auth-core/package.json',
  'packages/ui-kit/package.json',
  'packages/workers-common/package.json',
  'scripts/check-dep-direction.mjs'
)
$changed = git diff --name-only -- $allowed
if (-not $changed) { throw 'No allowed small-fix files changed; do not create a commit.' }
git add -- $changed
git diff --cached --name-status
git commit -m "build(m0): fix baseline verification config"
```

Expected: `git diff --cached --name-status` lists only files changed by this execution. Do not stage `.claude/` or unrelated user changes.

# Production Domain Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the production admin domain to the production API domain with a controlled CORS policy.

**Architecture:** Extract admin API base selection into a small environment-aware module, then add Hono CORS middleware at the Worker API boundary. Keep local development relative and production explicit.

**Tech Stack:** TypeScript, React, Vite, Hono, Vitest, Cloudflare Workers

---

### Task 1: Admin API base selection

**Files:**
- Create: `apps/admin-web/src/api-base.ts`
- Modify: `apps/admin-web/src/App.tsx`

- [ ] Add a focused environment resolver asserting production defaults to `https://api.tcgcard.fun/api/v1/admin`, development defaults to `/api/v1/admin`, and an explicit `VITE_API_BASE_URL` wins.
- [ ] Implement `resolveAdminApiBase` and use it from `App.tsx`.
- [ ] Run TypeScript and production build verification.

### Task 2: Worker CORS policy

**Files:**
- Modify: `apps/workers-api/src/index.ts`
- Create: `apps/workers-api/src/cors.test.ts`

- [ ] Add a Worker request test for an allowed admin-domain preflight and an unrelated origin.
- [ ] Run the focused test and confirm the expected failure.
- [ ] Add Hono CORS middleware for `/api/*` with the production admin origin, required headers, and required methods.
- [ ] Run the focused test and confirm it passes.

### Task 3: Production verification and integration

**Files:**
- Verify: `apps/admin-web`
- Verify: `apps/workers-api`

- [ ] Run focused tests for both applications.
- [ ] Run the admin production build.
- [ ] Run the Worker dry-run build.
- [ ] Commit the verified changes and push them to `main`.

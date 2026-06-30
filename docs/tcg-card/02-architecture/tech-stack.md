# tcg-card 技术选型

> **定位**：列出 tcg-card v1.0 各层技术选型及选型理由，并标注待定依赖项。
> **最后更新**：2026-06-30
> **上游来源**：[`docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md`](../../superpowers/specs/2026-06-30-tcg-card-preparation-design.md) §4.7

---

## 1. 技术选型一览

| 层 | 选型 | 选型理由 |
|---|---|---|
| App | Flutter + Riverpod + Dio + go_router + freezed | 见 §2.1 |
| 后台前端 | React + Vite + TypeScript + Ant Design + TanStack Query | 见 §2.2 |
| 后端 | Cloudflare Workers + Hono + Drizzle ORM | 见 §2.3 |
| 缓存 | Workers KV + Cache API | 见 §2.4 |
| Monorepo 工具 | pnpm workspaces + Turborepo（TS 侧）+ Melos（Dart 侧） | 见 §2.5 |
| 邮件 | Resend（默认）/ SES 备选 | 见 §2.6 |

---

## 2. 逐项说明

### 2.1 App：Flutter + Riverpod + Dio + go_router + freezed

| 依赖 | 理由 |
|---|---|
| **Flutter** | 跨平台框架，v1.0 先交付 iOS，Android 架构预留；一套代码后续可复用 |
| **Riverpod** | 类型安全、可测试的状态管理方案；相较 Provider 编译期安全性更强；AI 辅助开发时上下文清晰 |
| **Dio** | 功能完善的 HTTP 客户端，支持拦截器、统一错误处理、Token 注入；与 Workers REST 接口配合成熟 |
| **go_router** | Flutter 官方推荐路由方案，声明式路由配置，支持深链、守卫跳转（未登录重定向） |
| **freezed** | 不可变数据类 + `copyWith` + `fromJson`/`toJson` 自动生成；与 Riverpod 不可变状态模式配合无缝 |

### 2.2 后台前端：React + Vite + TypeScript + Ant Design + TanStack Query

| 依赖 | 理由 |
|---|---|
| **React** | 生态成熟，与 Workers TS 同生态；团队/AI 熟悉度高 |
| **Vite** | 构建快、开发体验好，适合后台轻量化工程 |
| **TypeScript** | 与后端 Workers 共享类型定义，减少接口联调错误 |
| **Ant Design** | 自带完整后台 UI 组件（Table、Form、Modal、权限控制等），最小化自研 UI 工作量 |
| **TanStack Query** | 服务端状态管理（数据缓存、自动刷新、乐观更新），与 Workers REST 接口配合直接 |

### 2.3 后端：Cloudflare Workers + Hono + Drizzle ORM

| 依赖 | 理由 |
|---|---|
| **Cloudflare Workers** | Serverless 运行时，无需运维；D1、KV、Cache API 均为原生绑定，部署与扩展简单；全球边缘网络低延迟 |
| **Hono** | 专为 Cloudflare Workers 设计的轻量 Web 框架，性能优秀，与 Workers 运行时无缝兼容 |
| **Drizzle ORM** | 对 D1（SQLite）类型安全、Schema 版本管理（迁移）友好；类型直接从 Schema 推断，无运行时魔法 |

### 2.4 缓存：Workers KV + Cache API

| 依赖 | 理由 |
|---|---|
| **Workers KV** | 全球分布式 KV 存储，适合 Trending Today、搜索结果等读多写少的第三方数据缓存 |
| **Cache API** | Workers 内置 HTTP 缓存，适合价格、成交记录等有 HTTP 语义（`Cache-Control`）的响应缓存 |

两者配合使用，降低第三方 API 调用频次，并提供降级兜底（详见 [`architecture.md §5`](architecture.md)）。

### 2.5 Monorepo 工具：pnpm workspaces + Turborepo + Melos

| 依赖 | 理由 |
|---|---|
| **pnpm workspaces** | TS/JS 侧 Monorepo 基础，节省磁盘空间，依赖安装快 |
| **Turborepo** | TS 侧任务编排（构建、Lint、测试并行化），增量缓存加速 CI |
| **Melos** | Dart/Flutter 生态标准 Monorepo 工具，管理 Flutter App 与 Dart 共享包的依赖和发布 |

两套工具分别管理各自生态，顶层通过约定协作（详见 [`monorepo.md`](monorepo.md)）。

### 2.6 邮件：Resend（默认）/ SES 备选 ⚠️ TBD

- **Resend（默认）**：对 Cloudflare Workers 开发体验友好，接入简单，适合验证码邮件等低频场景。
- **SES 备选**：如发送量上升或成本要求变化，可切换至 AWS SES；⚠️ TBD（见 spec §6）。

---

## 3. 待定子项

以下依赖尚未最终确认，均标注 ⚠️ TBD，以 spec §6 待定项清单为准，不静默假设。

| # | 待定项 | 影响范围 | 说明 |
|---|---|---|---|
| 1 | **汇率接口提供方** | 货币换算展示（Home / Collection / CardDetail） | 按统一汇率服务接口抽象，厂商待定；见 spec §6 #2 |
| 2 | **第三方数据源厂商**（TCGplayer / eBay / PriceCharting 等） | 搜索、价格、Trending、成交记录全部能力 | 按可插拔数据源适配层设计，不绑定具体厂商；见 spec §6 #1 |
| 3 | **Apple / Google OAuth 开发者账号与凭证** | Auth 第三方登录（Apple Login、Google OAuth） | 文档写流程，凭证待开发者账号配置后填入；见 spec §6 #4 |
| 4 | **邮件服务 Resend vs SES 最终选择** | 验证码发送、找回密码 | 默认 Resend，最终选型根据发送量和成本确认；见 spec §6 #3 |

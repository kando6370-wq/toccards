# Kando 安全架构分析

Kando 是 Flutter 与 TypeScript 并行的 monorepo。Flutter App、React Admin 和插件通过共享 Hono API 访问 PostgreSQL、缓存和图片存储；生产运行在 Cloudflare Workers，dev运行在Linux Node适配器。当前服务端回调仅接入 Apple App Store Server Notifications 的 production 与 sandbox 路由；Google服务端 webhook 尚未接入。Apple通知、识别服务和依赖registry是主要外部信任边界。

核心安全边界包括公网客户端到API、普通用户到Admin权限域、API到PostgreSQL/R2、Cloudflare/Linux运行时差异，以及依赖供应链到发布产物。升级策略必须同时覆盖Node依赖、pnpm包管理器、Flutter/Dart SDK、Gradle wrapper和两个服务端运行时。

当前架构没有Next.js/RSC，也没有产品侧LLM/Agent运行时；相关热点漏洞不适用，不应引入无关升级。

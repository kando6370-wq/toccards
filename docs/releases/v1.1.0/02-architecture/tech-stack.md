# v1.1.0 技术栈

## 1. 应用与运行时

| 层 | 当前技术 | 证据 |
|---|---|---|
| 移动/Web App | Flutter、Dart、Riverpod、GoRouter、Dio | `apps/flutter-app/pubspec.yaml` |
| 订阅模块 | `in_app_purchase`、StoreKit adapter | `dart-packages/subscription-core/pubspec.yaml` |
| API | TypeScript、Hono、Cloudflare Workers | `apps/workers-api/package.json` |
| 数据访问 | Postgres.js 适配器、Cloudflare Hyperdrive、PostgreSQL 顺序 migrations | `src/db/postgres-database.ts`、`src/db/postgres/migrations/` |
| Admin | React 18、Vite 6、Ant Design 5、TanStack Query 5 | `apps/admin-web/package.json` |
| Marketing | Cloudflare static assets/Workers | `apps/marketing-web/wrangler.jsonc` |
| Monorepo | pnpm 11.9.0、Turborepo 2、Dart pub workspace、Melos 8 | 根 manifests |
| 测试 | Vitest 4、Node test runner、Flutter test | 各应用 scripts 与 test 目录 |

## 2. 工具链约束

| 工具 | 当前约束 |
|---|---|
| Node.js | `>=22` |
| pnpm | `11.9.0` |
| Dart SDK | `^3.9.2` |
| Flutter App / subscription-core | `>=3.44.0` |
| GitLab Flutter CI | `3.44.0` |
| GitHub iOS CI | `3.44.7` |

CI 的 Flutter 版本冲突是显式目标差异，不合并成虚构的统一版本。涉及复现或发布时按目标流水线选择；统一版本必须作为独立变更同时更新 manifest、CI 和 lockfile 验证。

Flutter 业务 API 继续按 Auth、Card Data、Portfolio、Scan 等领域持有独立 Dio 实例，不使用全局单例。共享网络基础层提供一致的 Dio 创建入口、单次操作总 Deadline、可选的安全读请求重试和进行中请求合并；当前 Card Data 及 Portfolio 的 Dashboard、Folders/Items/Wishlist 列表、Valuation History、Portfolio/Item Performance 读取已迁移。上述 GET/HEAD 对连接、发送、接收 Timeout、连接失败及 `408/429/500/502/503/504` 最多重试一次，使用 300ms 指数退避起点与最多 30% 抖动，并与首次请求共享 15 秒总 Deadline；完全相同的进行中 GET 按 Method、Path、排序后的 Query 与 Header 合并，完成或失败后立即移除，不形成响应缓存。Portfolio Key 的 Authorization 隔离账号，Path 与 Query 隔离 Item、Folder、Range、Days；Portfolio 响应固定为 USD 原始值，显示货币在 DTO 之后换算，不属于 HTTP 请求上下文。`401` 仍由既有会话拦截器处理，普通 `409/422`、POST/PATCH/DELETE 和上传请求不进入通用重试；Home 1Y、Home Performance 与 Item Performance 的精确 `ENTITLEMENT_SYNC_REQUIRED` 仍由业务 Controller 校正并最多重放一次，但首次请求、权益校正和重放共用同一个绝对 15 秒 Deadline。Portfolio Preferences、所有 Portfolio 写请求及其 Idempotency-Key、Auth、Scan、Subscription 与其他 Dio Client 尚未迁移，不得把该策略视为全 App 已启用。

## 3. Cloudflare 能力

| 能力 | 当前用途 |
|---|---|
| Workers | API、分享页、定时补偿与 Admin assets 入口 |
| Hyperdrive | Workers 到共享 PlanetScale PostgreSQL 的连接边界，查询缓存已关闭 |
| PlanetScale PostgreSQL 18.6 | dev/prod 共用的目录、账号、资产、扫描、订阅、通知、价格和运营唯一真源 |
| KV | 可重建目录/汇率缓存 |
| R2 | 扫描图片 |
| Wrangler 4.106.0 | 本地开发、迁移、dry-run 与环境部署 |

当前 `wrangler.toml` 使用 `nodejs_compat`，以支持 Apple 官方 App Store Server Library 在 Worker 请求/定时任务上下文中加载。

## 4. 外部与平台集成

- Apple StoreKit、App Attest、App Store Server Notifications V2 与 Server API。
- Google/Apple OAuth；邮箱注册与找回密码使用 ZeptoMail。
- OCR 服务处理扫描识别；PostgreSQL/R2 保存结构化记录与受保护图片。
- 汇率服务以 USD 为基准提供快照，KV 可缓存。
- Firebase Analytics/Crashlytics、Mixpanel、Singular 和 ATT 用于分析、归因与稳定性，不作为授权真源。Flutter 在 dev/prod 环境均开启 Mixpanel 移动端自动事件采集；Project Token 仍按环境加载。每次完整冷启动异步执行一次 Mixpanel 初始化，不阻塞 `runApp`；初始化失败后仅在当前进程内按 2 秒、5 秒、15 秒重试三次，成功后按原顺序补发初始化期间的内存事件，全部失败后停止重试并清空待发事件。表格定义的全部自定义事件共用同一属性组装入口；首次认证会话恢复完成前事件只暂存在内存，恢复为账号或游客后分别使用用户 UID 或匿名 ID 组装 `uid` 并发送，认证明确失败且没有可用身份时才发送空 `uid`。后续身份切换只影响切换后发生的事件，不回写已经组装的历史事件。

## 5. 配置和安全边界

- Flutter API 地址等使用 `--dart-define-from-file` 按环境注入；未注入 `APP_ENV` 时默认 production，以匹配 iOS/Android 默认生产 App 身份，test 构建必须显式加载 `apps/flutter-app/config/test.json`，根 Melos 测试任务显式注入 `APP_ENV=test`。
- Workers 公开 vars 与 bindings 在 `wrangler.toml` 分环境声明。
- Apple、JWT、邮件、分析等密钥必须使用 secret 管理，不进入源码、文档或测试夹具。
- dev 与 prod 共享 PostgreSQL 业务数据，但 `APP_ENVIRONMENT`、Bundle ID、Product ID 白名单、KV、R2、域名和密钥严格隔离。
- Admin 的 Vite 构建模式随对应 Worker assets 部署，不能把独立本地 dev server 当成生产部署模型。

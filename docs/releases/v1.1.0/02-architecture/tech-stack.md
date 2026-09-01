# v1.1.0 技术栈

## 1. 应用与运行时

| 层 | 当前技术 | 证据 |
|---|---|---|
| 移动/Web App | Flutter、Dart、Riverpod、GoRouter、Dio | `apps/flutter-app/pubspec.yaml` |
| iOS Scan | iOS 16+、Core ML、Core Image、`CIPerspectiveCorrection` | `ios/Runner/ScanModelRuntime.swift`、`ios/Runner/AppDelegate.swift` |
| Android Scan | Android API 24+、Bitmap/Matrix/Canvas、ONNX Runtime 1.23.0 minimal AAR、四 ABI ORT 模型 | `android/app/build.gradle.kts`、`android/app/src/main/kotlin/com/cardai/tcg/` |
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

## 3. Cloudflare 能力

| 能力 | 当前用途 |
|---|---|
| Workers | API、分享页、定时补偿与 Admin assets 入口 |
| Hyperdrive | Workers 到共享 PlanetScale PostgreSQL 的连接边界，查询缓存已关闭 |
| PlanetScale PostgreSQL 18.6 | dev/prod 共用的目录、账号、资产、扫描、订阅、通知、价格和运营唯一真源 |
| KV | 可重建目录/汇率缓存 |
| R2 | 扫描矫正卡面 |
| Service Binding | `VECTOR_RECOGNITION` 连接内部 `recognize-vec` Worker |
| Wrangler 4.106.0 | 本地开发、迁移、dry-run 与环境部署 |

当前 `wrangler.toml` 使用 `nodejs_compat`，以支持 Apple 官方 App Store Server Library 在 Worker 请求/定时任务上下文中加载。

## 4. 外部与平台集成

- Apple StoreKit、App Attest、App Store Server Notifications V2 与 Server API。
- Google/Apple OAuth；邮箱注册与找回密码使用 ZeptoMail。
- Flutter 端使用 RTMDet-Ins、纯 Dart mask 几何、iOS Core Image/Android Bitmap Matrix 和 PE-Core-T16 完成卡牌检测、矫正与 512 维向量化；iOS 模型运行时为系统 Core ML，Android 为裁剪到两个模型所需 CPU 算子和类型的 `onnxruntime-android 1.23.0` minimal AAR；主 Worker 通过 Service Binding 调用 `recognize-vec` 检索，PostgreSQL/R2 保存结构化记录与受保护的矫正卡面。
- OpenCV、RGB pHash、`OCR_SERVICE_BASE_URL` 和完整预编译 Android ORT AAR 均不属于当前实现；Web 端侧 Scan 识别当前不支持。完整平台与制品契约见[扫描识别流程](../01-flows/scan-recognition.md)。
- 汇率服务以 USD 为基准提供快照，KV 可缓存。
- Firebase Analytics/Crashlytics、Mixpanel、Singular 和 ATT 用于分析、归因与稳定性，不作为授权真源。

## 5. 配置和安全边界

- Flutter API 地址等使用 `--dart-define-from-file` 按环境注入。
- Workers 公开 vars 与 bindings 在 `wrangler.toml` 分环境声明。
- Apple、JWT、邮件、分析等密钥必须使用 secret 管理，不进入源码、文档或测试夹具。
- dev 与 prod 共享 PostgreSQL 业务数据，但 `APP_ENVIRONMENT`、Bundle ID、Product ID 白名单、KV、R2、域名和密钥严格隔离。
- Admin 的 Vite 构建模式随对应 Worker assets 部署，不能把独立本地 dev server 当成生产部署模型。

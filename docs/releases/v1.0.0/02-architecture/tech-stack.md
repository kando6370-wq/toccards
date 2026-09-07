# v1.0.0 技术栈

## 应用与运行时

| 层 | 当前技术 | 用途 |
|---|---|---|
| 移动端 | Flutter、Dart、Riverpod、GoRouter | iOS/Android/Web 客户端与状态管理 |
| API | TypeScript、Hono | Cloudflare Workers HTTP API |
| 数据访问 | Drizzle ORM、SQL migrations | D1 schema 与迁移 |
| Admin | React 18、Vite 6、Ant Design 5、TanStack Query | 内部运营后台 |
| Monorepo | pnpm 11、Turborepo、Melos | Node 与 Dart 工作区任务 |
| 测试 | Vitest、Node test runner、Flutter test | Workers、Admin 与 Flutter 验证 |

根 Node 要求为 `>=22`。Dart SDK 约束以根 `pubspec.yaml` 和 Flutter CI 为准。

## Cloudflare 能力

| 能力 | 用途 |
|---|---|
| Workers | API、分享页和 Admin 静态资源入口 |
| D1 | 卡牌目录、价格、账号、资产、扫描和运营数据 |
| KV | 目录查询、汇率等短期缓存 |
| R2 | 扫描图片 |
| Wrangler | 本地开发、迁移、dry-run 和 dev/prod 部署 |

## 外部集成

- Google OAuth 与 Apple Sign In：正式账号登录。
- ZeptoMail：注册和找回密码验证码邮件。
- OCR 服务：扫描图片识别。
- 汇率服务：将 USD 市场价格转换为用户货币。
- Firebase：Flutter 平台服务与配置。
- Mixpanel：产品事件分析；Workers 也预留服务端 token/secret。

## 配置边界

- Flutter 的 API base URL 等按 `--dart-define-from-file` 环境文件注入。
- Workers 非敏感公开变量与资源 binding 在 `wrangler.toml` 中区分 dev/prod。
- `JWT_SECRET`、邮件 token、Mixpanel secret 等敏感值必须使用 Cloudflare secrets。
- Admin 的环境 API 地址由 Vite mode 构建配置决定，并随对应 Worker assets 部署。

证据：各应用的 `package.json`、Flutter `pubspec.yaml`、`wrangler.toml`、CI workflow。

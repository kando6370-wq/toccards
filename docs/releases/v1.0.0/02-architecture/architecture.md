# v1.0.0 系统架构

## 1. 运行结构

```text
Flutter App -----------+
                       +--> Cloudflare Workers (Hono, /api/v1)
React Admin -- assets -+        |-- D1: 目录、账号、资产、运营数据
                                |-- KV: 卡牌与汇率缓存
                                |-- R2: 扫描图片
                                |-- OCR / OAuth / 邮件 / 汇率服务
```

Workers 是移动端和 Admin 的服务端边界。Admin 构建产物位于 `apps/admin-web/dist`，由 `apps/workers-api/wrangler.toml` 的 assets 配置随 Worker 一起部署；`/api/*` 和 `/share/*` 优先进入 Worker，其余路径按 SPA 处理。

## 2. 客户端

- Flutter 使用功能目录组织认证、首页、搜索、扫描、收藏、卡牌详情和个人中心。
- Riverpod 管理状态与依赖，GoRouter 管理页面导航。
- Repository/Client 封装 HTTP 和本地持久化；客户端不直连 D1、KV 或 R2。
- Admin 是 React 单页应用，使用 React Query 请求 `/api/v1/admin`。

## 3. 服务端边界

`apps/workers-api/src/index.ts` 将路由统一挂载到 `/api/v1`：Admin、Auth、App Config、Data Source、Feedback、Legal、Portfolio 和 Scan。卡牌分享页挂载在根 `/share` 路径。

鉴权分为两套：App JWT 表达 `user` 或 `anonymous` 所有者；Admin Token 表达 `admin_user`。业务资产访问始终由服务端解析身份并附加所有者过滤。

## 4. 数据与缓存

- D1 同时保存外部导入的卡牌目录/价格，以及账号、收藏、扫描和运营数据。
- Drizzle schema 是 TypeScript 数据结构入口，SQL 迁移 `0000` 至 `0024` 是数据库演进记录。
- KV 缓存目录查询和汇率等可再获取数据；缓存失败不能改变 D1 中的业务真源。
- R2 仅在 `SCAN_IMAGES` binding 可用时保存扫描原图，读取受 Admin 鉴权保护。

## 5. 环境

| 环境 | Worker | 域名 | D1/R2 |
|---|---|---|---|
| dev | `toccards-api-dev` | `api-dev.tcgcard.fun` | 独立 dev 资源 |
| prod | `toccards-api-prod` | `api.tcgcard.fun` | 独立 production 资源 |

部署脚本会先按环境构建 `auth-core` 与 Admin，再由 Wrangler 部署 Worker 和静态资源。部署操作不等同于 Git push。

## 6. 关键约束

- `apps` 可以依赖 `packages`，共享包不得反向依赖应用。
- `card_ref` 使用 `cards_all.product_id`；系列过滤使用 `set_id`。
- 资产权限以服务端 `owner_type + owner_id` 为准，不能信任客户端自报所有者。
- 密钥通过 Worker secrets 注入，不进入仓库；环境公开配置由 Wrangler vars 管理。

证据：`apps/workers-api/src/index.ts`、`env.ts`、`wrangler.toml`、`src/db/schema.ts`、根 workspace 配置。

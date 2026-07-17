# 运行时真实数据审计

## 0. 审计范围

- 范围：Flutter `lib/`、Workers `src/`、Admin Web `src/` 的生产运行时数据来源，以及 Cloudflare D1、Workers、Pages 和公开 API。
- 日期：2026-07-17。
- 口径：测试目录允许使用 fixture/mock；任何可被生产入口调用的静态业务数据、demo session 或失败回退均不允许存在。

## 1. 结论

当前生产运行时已不依赖 mock 数据。Flutter 的 HOME、Collection、Search、Card Detail、Profile 和 Scan 均通过真实 API repository；Workers 使用 D1、R2、KV 与外部识别/价格适配器；Admin Web 已移除 `?demo_admin=1`、`local-token` 和所有静态 demo 响应。

测试专用 `apps/workers-api/src/data-source/test-support/mock-data-source-adapter.ts` 仍保留，但只有 `adapter.test.ts` 与 `routes.test.ts` 引用，不进入运行时路由默认依赖或生产 bundle。

## 2. 代码证据

| 检查项 | 结果 | 证据 |
|---|---|---|
| Flutter runtime mock 关键词 | 0 命中 | `apps/flutter-app/lib` 全量 `rg` |
| Admin runtime mock/demo 关键词 | 0 命中 | `apps/admin-web/src` 全量 `rg` |
| Workers runtime mock 关键词 | 排除 `test-support` 后 0 命中 | `apps/workers-api/src` 全量 `rg` |
| Workers 测试夹具引用 | 仅 2 个测试文件 | `adapter.test.ts`、`routes.test.ts` |
| Admin API 失败 | 保留 error 状态和 reload，不再返回静态成功数据 | `useAdminData()`、`adminRequest()` |
| Admin Scan 图片 | 只用带 Bearer Token 的真实 blob；失败显示占位 | `AuthenticatedScanImage()` |

对应提交：`a9141b1 fix(admin): remove runtime demo data`。

## 3. 生产接口与数据证据

| 验证项 | 生产结果 | 结论 |
|---|---|---|
| `GET /cards/trending` | 10 条真实卡牌；首条 `card_ref=9359` | 真实 D1/价格数据 |
| `GET /cards/search?q=Escape Artist` | 返回 `card_ref=9359` | 真实目录查询 |
| 卡图 | Trending/Search 均返回 `image.tcgcard.fun` R2 变体 | 无第三方示例图回退 |
| D1 `cards_all` | 4066 个 product | 真实目录有数据 |
| D1 `tcgplayer_skus` | 10 个 product、61 行 SKU | 覆盖不足但不是 mock |
| D1 `price_sync_state` | `blocked / covered_products=10 / total_products=4066` | 缺 `JUSTTCG_API_KEY`，未伪造价格 |
| `/app-config` | Terms/Privacy 有真实 URL，`app_store_url=null` | 显式暴露 iOS 阻断 |

## 4. Cloudflare 部署证据

| 表面 | 当前生产标识 | 复验 |
|---|---|---|
| Workers API | `8a482fcb-3e0f-4278-9fb3-f302a1545948` | 自定义域名 `api.tcgcard.fun` 返回真实 Cards/R2 URL |
| Admin Pages | `24c54f1f.toccards2.pages.dev` | `admin.tcgcard.fun` 已加载 `index-mIUzNeV7.js` |
| Admin bundle | `demo_admin`、`local-token`、Pokémon 示例图、示例 scan id 均为 false | 生产 bundle 内容回读 |

## 5. 仍未关闭的真实数据阻断

| 优先级 | 阻断 | 当前决定 |
|---|---|---|
| P0 | Raw 价格仅覆盖 10/4066 | 配置真实 `JUSTTCG_API_KEY` 后跑完同步；不得插测试价格冒充生产覆盖 |
| P0 | 无真实 Graded 价格源与生产样本 | 接入并验收真实来源前保持 `--` |
| P0 | `app_store_url=null` | App Store Connect 创建应用后写入真实 URL |
| P1 | Admin bundle 仍有体积警告 | 不影响数据真实性；后续按独立性能任务拆包 |

## 6. 验证命令

- Admin：3 项测试通过，TypeScript 类型检查通过，生产构建通过。
- Workers：28 个测试文件、249 项通过，TypeScript 与 dry-run 通过。
- Flutter：237 项通过、1 项因缺平台 dartcv 动态库明确跳过，`flutter analyze` 通过。
- iOS CI：GitHub Actions run `29562484453` 在 `f3e4b2e` 上成功。

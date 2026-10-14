# v1.1.2 实际验证记录

本文件保留 Admin、营销站等其他业务的实际验证。App 兼容规则、源码合同证据及 Home 文件夹切换历史记录见 [AI 执行版](../03-data-api/app-backward-compatibility-ai-guide.md)；历史版本记录见 [v1.1.1](../../v1.1.1/05-delivery/VERIFICATION.md)。未运行或只有部分证据的事项不得标记为完整验收通过。

## 2026-10-13：Google Sitemap 最小隔离实验

### 根因证据与实验边界

- GSC 的 `/sitemap.xml` 详情在 2026-10-13 再次显示“网站地图无法读取”、发现页面 0，最后读取日期已更新为 2026-10-13；因此不再把现象归类为 2026-10-10 的旧报表尚未刷新。GSC 普通 URL 检查同时记录 Googlebot 智能手机在 2026-10-12 10:21:51 已抓取该 URL，允许抓取且页面加载成功。
- 2026-10-13 17:43:07 的 GSC 实时 URL 测试返回“网址可供 Google 使用”，允许抓取、页面加载和允许索引均为“是”。同日人工处置措施和安全问题均显示未检测到问题。
- 公开端精确 URL 与 Googlebot UA 均返回 HTTP 200、`application/xml`、2719 字节和相同 SHA-256；XML 可解析且包含 25 个 URL，robots.txt 允许抓取并只声明正式 sitemap；25 个正式 sitemap 子 URL 用 Googlebot UA 检查均为 200、无重定向。由此确认当前可复现的失败位于 Sitemap 专用识别/处理链路与普通抓取链路之间，而不是已证实的 Cloudflare 拦截、robots、XML 语法或子 URL 故障；没有无请求日志证据地把外部处理分歧写成唯一 Google 根因。
- 用户批准最小隔离实验。新增 `/sitemap-minimal.xml`，只包含 `/`、`/pokemon-card-scanner` 和 `/card-price-checker` 三个绝对 `<loc>`，不含注释、`priority`、`lastmod`、`changefreq` 或扩展命名空间。正式 `/sitemap.xml`、robots.txt、页面、canonical、部署配置和数据库均不改；该测试文件不写入 robots，也不加入正式 sitemap。

### 当前状态与验收边界

- 内容生成完成后，`pnpm --filter @kando/marketing-web test` 退出 0，19/19 通过；新增契约逐字节检查最小文件、三个 URL 和无可选字段边界，同时确认正式 sitemap 与 robots 未引用测试文件。正式 sitemap 和 robots 相对 `origin/main@7db7d63` 无差异。
- `xmllint --noout` 对正式和最小 sitemap 均通过；最小 sitemap 另通过官方 Sitemap 0.9 XSD。`git diff --check` 退出 0。没有运行无影响面的 Workers、Admin、Flutter、App 兼容或数据库测试。
- 本地 Wrangler `http://127.0.0.1:8791/sitemap-minimal.xml` 返回 200、`application/xml`、307 字节，与生成文件 SHA-256 `740090137b8a36b5224cd25467b1ab37dec8c4031955ba73996e23411268f695` 一致；三个目标页面均返回 200 且无重定向。
- 提交前独立 Code Review 核对计划对齐、正式发现信号隔离、生成器确定性、契约测试和文档边界，Critical/Important/Minor 均无问题，结论为 Ready to merge。审查后只补记本条结论，未修改实现或验收断言。
- 截至本地验收检查点，尚未提交、推送、部署或执行 GSC 最终提交；这些步骤必须取得各自实际结果后补证，不能按计划记为完成。
- 生产验收要求 Cloudflare 自动构建成功、线上 `/sitemap-minimal.xml` 返回 200 `application/xml`、内容与已批准生成物逐字节一致，三个 URL 均为 200 且无重定向。GSC 提交是独立外部写操作，必须在点击提交前再次确认；提交成功也只表示实验请求被接受，不代表 Google 已读取、发现页面或索引成功。

## 2026-10-13 Admin 订单金额与退款金额汇总（本地）

- 范围与用户确认：订单统计页按当前筛选条件汇总全部匹配订单，已退款订单不计入订单金额，并单列退款金额。实现在独立 worktree `C:\Users\jhon\.codex\worktrees\dev-1-0-6\kando-global-project` 的 `codex/dev-1.0.6`，基准 `main@7db7d63`；本条为本地增量，不代表远端已更新。
- 实现：列表接口保留分页/明细，原数量查询扩展为数量、不含退款的 USD 合计、退款 USD 合计及两类缺失笔数。复用现有全部筛选、通知确认、产品/环境边界，按整数微单位聚合；退款不会混入订单合计，也不会重复扣减。前端复用既有统计卡片样式，分别展示三项数据及缺失提示。全部缺失为 `--`，无该类订单或合法零金额为 `$0.00`，加载/失败时不显示旧汇总。契约见 [后台增量](../04-admin/admin.md)。
- 失败证据：新增 `billing-summary.postgres.test.ts` 在实现前执行，7 项因缺少 `summary` 失败、既有鉴权/非法筛选场景 1 项通过；PostgreSQL 查询、登录及明细已正常执行。实现后 8 项全部通过。测试使用现有 PGlite 工具与真实 PostgreSQL `0000_business_schema.sql`，没有新增或扩展 D1 测试基座。
- 意图反证：临时移除订单金额的退款排除条件，定向运行 `pnpm --filter @kando/workers-api test src/admin/billing-summary.postgres.test.ts --maxWorkers=1 -t "retains refunded rows"`，目标用例因 `amount_usd_micros` 从应为 `0` 变成 `30000000` 而失败，其他 7 项因名称过滤未运行。恢复实现的原始字节后，无过滤重跑该文件，8/8 通过、无跳过。
- 环境与验证：Windows、Node 22.20.0、pnpm 11.9.0；新 worktree 执行 `pnpm install --frozen-lockfile`、`pnpm --filter @kando/auth-core build`，均退出 0。首次 Workers 类型检查发现新测试的全局 URL 与 Node URL 类型冲突，改为仓库既有 `node:url` 显式导入后复验通过。
- 相关回归：`pnpm --filter @kando/workers-api test src/admin/billing-summary.postgres.test.ts src/admin/billing-routes.integration.test.ts src/admin/routes.test.ts --maxWorkers=2` 退出 0，3 文件/43 项全部通过，覆盖组合筛选、跨页与越界页、退款隔离、退款时间口径、金额缺失/零值、状态恢复、USD 快照精度、环境/通知范围和鉴权；既有列表与 XLSX 场景通过。`pnpm --filter @kando/admin-web test` 退出 0，26 项通过。
- 静态与构建：`pnpm lint` 退出 0；`pnpm type-check` 退出 0，7 项成功，其中 Admin/Workers 实际执行、5 项命中缓存；`pnpm --filter @kando/admin-web build:prod` 退出 0。
- 页面交互：使用当前 Admin/Vite、当前 Hono API 与独立内存 PostgreSQL，在本机环回地址和合成测试账号下验收。27 笔匹配订单显示不含退款 `$148.45`、退款 `$30.00`；第二页显示 21–27 条时汇总不变。仅退款筛选显示 2 笔、订单合计 `$0.00`、退款 `$30.00`；缺失退款金额单笔显示退款 `--` 并提示 1 笔未计入。筛选草稿未查询前不影响汇总，无结果时订单数/两项金额归零，重置和刷新恢复全部结果。截图位于忽略目录 `apps/workers-api/.wrangler/billing-summary-ui/summary.jpg`，不是生产订单。
- Code Review（本地自审）：检查同筛选复用、分页独立、退款不重复扣减、空值与零值、旧响应字段兼容、加载/失败显示及权限边界，未发现阻断项；未进行独立人员审查。同步当前版本文档、入口和根 Agent 规则；`git diff --check` 退出 0，26 处本地文档链接有效，新文件无尾随空白，验证记录原有字节前缀保持不变。
- 未执行：未重跑完整 Workers 全套、Flutter/App 兼容测试或 Workers 部署 dry-run，因本次改动限定 Admin 展示与 Admin 列表聚合，相关回归/类型检查及 Admin 构建已覆盖；没有修改部署配置、数据库 schema/migration 或 App 契约。未在 dev/prod 真实账号和生产数据量上验收，未部署、迁移或写入远端业务数据库；本次增量尚未 Git commit/push。

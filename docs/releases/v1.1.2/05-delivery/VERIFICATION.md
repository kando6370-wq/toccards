# v1.1.2 实际验证记录

本文件保留 Admin、营销站等其他业务的实际验证。App 兼容规则、源码合同证据及 Home 文件夹切换历史记录见 [AI 执行版](../03-data-api/app-backward-compatibility-ai-guide.md)；历史版本记录见 [v1.1.1](../../v1.1.1/05-delivery/VERIFICATION.md)。未运行或只有部分证据的事项不得标记为完整验收通过。

<a id="trial-conversion-order-status"></a>

## 2026-10-21：试用 SKU 首扣订单分类（本地）

- 根因：Admin 已有 `trial_conversion`／“试用转付费”展示与筛选，但订单事实只在同链先存在一笔 Apple 通知确认的 `trial` 交易时才生成该状态。动态准入新增的 `is_trial_product` 没有参与订单分类，因此试用开始订单缺失时，试用 SKU 的首次正金额续费被保存为 `renewal`。
- 修复：Notifications V2 读取当前环境／Bundle 的动态准入表，将 `is_trial_product=true` 的 SKU 传入订单事实重算。仅 `RENEWAL`、正金额、通知确认且同链无更早正金额付费的首扣生成 `trial_conversion`；第二次起恢复 `renewal`。既有试用交易证据继续生效，宽限期恢复、账单重试恢复、升级、退款、零金额和金额缺失保持原优先级及分类。
- 历史数据：新增 PostgreSQL `0015_trial_conversion_status.sql`，按相同条件回填现有 `renewal`，并修正已退款订单的退款前状态。该 migration 只更新数据，不变更表、列或索引；重复执行结果稳定。旧代码已支持 `trial_conversion`，回退代码不会遇到未知状态，但数据不会自动反向恢复。
- 本地验证：按仓库正式排除规则执行 `pnpm --filter @kando/workers-api exec vitest run src/entitlements/billing-order-facts.integration.test.ts src/entitlements/apple-notification-routes.integration.test.ts src/entitlements/apple-product-policy.postgres.test.ts src/db/postgres/trial-conversion-status-migration.test.ts --exclude "**/.wrangler/**" --maxWorkers=1 --no-file-parallelism`，最终退出 0，4 个真实源测试文件／72 项通过。覆盖缺失试用起始订单、首扣／后续续费、退款后重算、零金额／缺失金额、动态准入到 DID_RENEW 建单，以及历史 migration 的普通／试用 SKU、未确认交易、退款前状态和幂等重跑。`node --test deploy/linux/preflight.test.mjs` 8/8 通过，并明确报告待执行 `0015_trial_conversion_status.sql`。`pnpm --filter @kando/workers-api type-check`、`pnpm lint` 与 `git diff --check` 均退出 0。
- 本地构建：`pnpm --filter @kando/workers-api build:linux:api` 退出 0，3/3 独立 Linux bundle 测试通过并生成本地 API bundle；`pnpm --filter @kando/workers-api deploy:dry-run:prod` 退出 0，Admin production 构建及 Wrangler prod dry-run 成功，仅生成本地忽略产物，没有上传 Worker 版本、切流或部署。
- 首次测试异常：并行启动三组 Vitest 时，两个进程因 Windows/V8 Worker 内存不足退出；后续直接调用 Vitest 时一度漏带正式脚本的 `.wrangler` 排除规则，重复扫描 `subscription-baseline-*` 生成副本，分别出现一次 Undici `bad port` 和一次 5 秒超时。上述错误范围和重复生成目录结果均不计为通过；修正为单进程、单 Worker且显式排除 `.wrangler` 后，取得上述 4 文件／72 项退出 0 结果，没有跳过真实源测试。
- 边界：未执行全量 Workers 测试、App 兼容编排、真实 Apple 通知、远程 migration、dev/prod 部署、生产数据库写入、Git commit 或 push。当前结论只证明本地分类和回填逻辑，不代表现有 dev/prod 订单已经改写或后台真实登录查询已验收。

## 2026-10-14：管理后台扫描详情原图放大

- 问题定位：扫描详情顶部原图与列表缩略图共用 `AuthenticatedScanImage`，私有图片已通过 Admin Token 获取 Blob，但组件固定渲染原生 `img`；候选卡牌图片使用 Ant Design `Image`，因此只有候选图具备预览和缩放能力。
- 修复范围：为 `AuthenticatedScanImage` 增加默认关闭的预览开关，仅在扫描详情原图调用处开启；鉴权请求、Blob URL 创建/释放、失败占位及列表缩略图行为保持不变。详情图片增加放大光标，不修改 Admin API、数据库、权限或 Flutter。
- 先失败证据：新增“详情原图开启鉴权预览且列表保持原行为”的回归测试，修复前该测试因详情调用未开启预览而按预期失败；修复后该文件 8/8 通过。
- 发布基线冲突：准备发布时独立回读发现 Linux dev 实际运行 `dev-xiangyang@2c56e9f`，而开发 worktree 基于 `main@7811db0`；main 的 Admin 已包含订单金额汇总 UI，当前 dev-xiangyang API 没有对应增量。为避免把 dev API 回退或部署不匹配的订单页面，没有直接发布 main 构建，而是从运行提交 `2c56e9f` 建立临时 detached worktree，只移植本次 `App.tsx`、`App.css` 和 `scans-intent.test.mjs` 三文件改动。相对运行提交共 28 行新增、3 行替换，API、部署脚本、依赖和锁文件无差异。
- 本地门禁：临时部署源的 `pnpm --filter @kando/admin-web test` 27/27 通过，Admin type-check 通过，Linux bundle 3/3 通过，`deploy:dry-run:dev` 成功生成 `sha=2c56e9f`、`branch=detached`、`working_tree_dirty=true` 的发布包。首次并行执行 Workers type-check 时，因 `auth-core` 尚未完成构建而报告模块缺失；dry-run 构建依赖后串行重跑通过，不将首次失败写成通过。
- 远程预检与发布：发布前回读旧 release 为 `manual-2c56e9f12901-1791943069936`，API/DB healthy、Web running、migration exited/0、部署锁空闲。标准远程脚本确认数据库 `toccards_test`、PostgreSQL 18、CF 向量识别可达、`pendingMigrations=[]`，随后创建 1,135,406,873 字节 custom-format 备份并发布 `manual-admin-scan-image-2c56e9f-dirty-20261014151507`。备份由 PostgreSQL 18 镜像执行 `pg_restore --list` 成功列出 339 项，未做恢复演练。
- 发布后独立回读：`current` 与 manifest 指向新 dirty release，共享 `.env` 链接仍指向原私有文件；API/DB healthy、Web running、migration exited/0，ledger 为 14 项且最新 `0013_cards_all_search_trgm.sql`。新旧 release 的 API bundle SHA-256 均为 `a2b6caf368362bdb60f3de10ad69b60fc17a3d3bdbb114b22147d2bfb435b67f`，确认本轮未改变 API 运行代码；失败标记不存在，上传 archive 已清理。
- 静态与 HTTP 验收：从开发机逐个获取 Linux dev 的 HTML/JS/CSS，11 个文件与批准 development 构建 SHA-256 全部一致；`/api/v1/health` 返回 200/`status=ok`，未登录 `/api/v1/admin/scans` 返回 401。
- 边界：未执行 Git commit/push、prod 部署、数据库业务写入或移动端验证；未使用真实 Admin 账号打开扫描详情并点击原图，因此线上 dev 的真实登录态交互仍待补验。后续其他手工发布或分支发布可能覆盖本次 dirty release。

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

## 2026-10-14 prod Admin 双入口重新部署与独立验收

- 授权与输入：用户要求重新部署 prod 管理后台。发布源为干净的本地 `main@ee3f298f0587eeb001629009279497b27dcefa1d`；先前保存 dev 部署文档的 stash `715cccb5bd4d7c5baa5d1c58ce9cbd0fefdbdef1` 保留，没有应用到本次构建。发布前 API 仍为 `ac0654e0-5b71-457f-9ddf-6f478995e6d9` / 100%，Pages 已于当日 09:02 自动发布 `ee3f298`，deployment 为 `cb11fe3c-ae15-49ee-a81b-eb46144f52bd`。双入口主资源分别为新 `index-CPQl0UUO.js` 与旧 `index-Cplutb86.js`，存在页面/API 未同步的运行状态。
- 发布范围与回退点：完整下载旧线上 Worker 后，与当前生产 dry-run 脚本对比，唯一差异位于 `/api/v1/admin/billing/transactions` 的数量/金额汇总；该路由之外的脚本前后缀逐字节一致，已有插件 redirect 修复保留。新页面依赖 `summary`，因此配套更新必要 Admin API 与双静态入口；数据库 migrations、部署配置、共享包及锁文件相对已核对生产源码没有变化。回退参考为旧 Worker `ac0654e0` 和 Pages `cb11fe3c`；本轮没有回退或删除旧版本。
- 本地验证：Windows / Node 22.20.0 / pnpm 11.9.0 / Wrangler 4.106.0。`pnpm --filter @kando/admin-web test` 26/26；`pnpm --filter @kando/workers-api test src/admin/billing-summary.postgres.test.ts src/admin/billing-routes.integration.test.ts src/admin/routes.test.ts src/extension src/deployment-config.test.ts src/cors.test.ts --maxWorkers=2 --reporter=dot` 8 文件/119 项通过、无跳过；`pnpm lint` 通过；`pnpm type-check` 7 项成功，Admin/Workers 实际执行、5 项命中缓存；`pnpm --filter @kando/workers-api deploy:dry-run:prod` 退出 0，构建 auth-core、Admin production 与 Worker，未在 dry-run 阶段上传。
- 候选核验：冻结同一构建的 Admin 11 个文件及 Worker 脚本；批准 Worker 为 2,112,768 字节、SHA-256 `715af5c24f4f8ef1b1e3f9f9c635139588bf13d7e94b2802a937d9d62a9108e9`。`wrangler versions upload --env prod --keep-vars --strict --assets <approved-admin-dist> --tag prod-admin-ee3f298 --message <发布说明>` 退出 0，09:11:08 创建 `3345b389-2501-4dd2-8f30-f85c03c87949`。上传后独立回读候选脚本与批准字节一致，所有 binding 描述符、runtime、handlers、placement 与旧版本相同；功能设置仅允许本次 tag/message annotations 变化。上传阶段旧版本继续接收 100% 流量。
- Worker 切流：`wrangler versions deploy 3345b389-2501-4dd2-8f30-f85c03c87949@100 --env prod --yes --message <发布说明>` 退出 0，09:12:29 创建 deployment `a186c31b-67d6-41cb-b1d4-41d07efd4a31`。独立回读确认候选为唯一活动版本、100% 流量，线上完整脚本与批准构建逐字节一致；CLI 同步的 logpush/observability 值未改变，未执行 triggers deploy。
- Pages 重发：Worker 切流与 9 项烟测通过后，执行 `wrangler pages deploy <approved-admin-dist> --project-name toccards-admin --branch main --commit-hash ee3f298f0587eeb001629009279497b27dcefa1d --commit-message <发布说明> --commit-dirty=false`，退出 0。09:13:08 Pages deployment `2c600e3e-1cd1-4e5c-a7c2-adceceb0bf9f` 为 production/success；API 回读 branch/hash/dirty 与干净输入一致。CLI 明确忽略不适用于 Pages 的 Worker wrangler.toml，沿用既有 Pages 项目配置，没有新增配置文件。
- 09:15 独立验收：`admin.tcgcard.fun` 与 `api.tcgcard.fun` 各 11 个 HTML/JS/CSS 共 22 个文件，与同一批准 production 构建的原始字节/SHA-256 全部一致；主资源均为 `index-CPQl0UUO.js`。首次并行取文件时，一个 Pages React vendor 连接被远端关闭（`UND_ERR_SOCKET`），其余 21 个已匹配；单独重取该文件后状态 200、原始字节一致，没有归一化文件或放宽断言。生产 health 为 200/status=ok 且新查询参数取得 MISS；未登录 auth/me、Admin 订单、Admin scans、portfolio folders 均 401；iOS/google app-config 均 200；Admin 登录 OPTIONS 为 204，允许正式 Admin Origin 和 POST；插件缺失 Key 为 401。9 份响应正文指纹与发布前一致。
- 配置保留：发布前后完整功能 settings、变量/Secret binding 描述符、Hyperdrive 配置及缓存、KV/R2、Service Binding、插件限频、Smart Placement、运行缓存、cron、Worker 域名/预览开关、Pages 构建/环境/自动部署配置与域名逐项一致。没有读取或替换 Secret 明文；版本注释及预期的 Worker/Pages deployment 标识更新。
- Review 与边界：部署方案、完整产物差异、候选/线上内容、配置保留、回退点及双入口证据已本地自审，无阻断项；不是独立人员 Code Review。业务、测试和部署源码未修改；未执行 Git commit/push、数据库迁移、SQL 业务写入、备份/恢复、生产 ledger 回查、Linux dev/营销站/Flutter 发布。未重跑完整 Workers 全套、App 兼容/Flutter 或真机测试；没有真实 Admin 登录态下的订单金额、筛选、分页和页面交互验收，插件正确 Key/详情/限频、性能及缓存一致性等既有待验项不因此关闭。原始证据保存在忽略目录 `apps/workers-api/.wrangler/prod-admin-redeploy-20261014-1791940042844/`，未将日志或构建产物加入 docs。

<a id="subscription-config-prototype"></a>

## 2026-10-14：App 1.0.6 订阅配置需求与离线原型

- 需求输入为 [PRD 1.14](../00-product/admin-subscription-config-prd.md)，对应 App 1.0.6；商品映射和接口／数据结构仍为待实施方案。新 SKU、真实订阅组、Page／Modal 兜底映射和旧包新增商品支持的未核验边界按正文保留。
- 历史本地原型证据：此前已对完整内嵌脚本完成语法解析，并从 HTML 原样抽取纯逻辑在隔离 JavaScript 上下文验证；按钮回退 13/13、保存校验 22/22，通过。对保存的 1.13 原始脚本进行同输入反证：12 种按钮占位符输入全部被放行，1.14 全部拒绝；缺字段恢复保持原试用文案。DOM 错误渲染由空操作替代，因此不是浏览器端到端或真实 API 测试；反证在修订完成后运行，不记为修改前已经实测。
- 归档的 [HTML 原型](../../../../prototypes/admin-subscription-config-standalone.html) 与上述已验证版本原始字节一致，SHA-256 为 `aff5bc3a7a7a0f20458ea8cce8cdd59e221b8619ef495dd1f7b7c681937aa37e`。本次只整理文档位置与链接，没有改写或重跑原型逻辑。
- 浏览器视觉检查未完成：当时电脑操作工具无法可靠确认当前浏览器地址而停止。未完成后台真实接口、Flutter／真机、Apple 私有目录、真实购买／恢复、收入平台及完整兼容验收；业务源码未随这些材料实现或发布。原始商品和价格是演示数据，不能当作真实接入证据。

<a id="subscription-config-server"></a>

## 2026-10-14：订阅展示配置与商品准入第一阶段

- 源码基线为 codex/dev-1.0.6@8751b7e 加本轮未提交改动；环境为 Windows、Node 22.20.0、pnpm 11.9.0。新接口／数据／环境合同见 [服务端文档](../03-data-api/subscription-display-config.md)。PostgreSQL 0014 仅新增三表，复用现有管理员鉴权；原购买、Restore 和 app-config 合同不改。Admin 页面与 Flutter 消费仍待后续阶段。
- 本地功能／回归：`pnpm --filter @kando/workers-api exec vitest run src/subscription-config/model.test.ts src/subscription-config/catalog.test.ts src/subscription-config/routes.postgres.test.ts src/linux/config.test.ts src/admin/billing-summary.postgres.test.ts src/app-config/routes.test.ts src/app-config/version-control.integration.test.ts src/compatibility/app-contract.test.ts --maxWorkers=2` 退出 0，8 文件／89 项通过，未跳过测试。覆盖 Apple 只读目录分页、作用域与失败／空值、签名、优惠事实，配置校验、管理员权限、两类页面、冲突／幂等／回滚、失效准入及旧 Admin/API 边界；App 兼容的证据限制另见 AI 执行版。
- 类型与依赖：pnpm lint、pnpm type-check 最终均退出 0。首轮类型检查发现测试中的 WebCrypto 联合返回类型和 Node／Workers URL 类型冲突，已通过类型收窄及显式 node:url 导入修正，没有放宽断言；最终全仓类型检查 7 个任务成功，其中 6 个未改包命中缓存。
- 真实 PostgreSQL 补验：使用既有本地 postgres:18.6-alpine 镜像创建仅绑定 loopback 的独立临时容器，数据库名 subscription_config_test，无既有业务表。显式设置 SUBSCRIPTION_TEST_DATABASE_URL 后运行 pnpm --filter @kando/workers-api test:subscription-config:postgres，最终退出 0；5 个独立连接场景通过（TAP 含父项显示 6/6），没有 skipped/cancelled。通过 pg_stat_activity 确认两个独立写连接等待 scope 行锁，以及撤销映射的连接在生效提交前等待 FOR SHARE 行锁；覆盖重复创建、竞争启用、并发编辑、商品准入稳定性及真实事务回滚。测试后两个任务自建容器均停止并自动移除，标签回查无残留，没有修改既有容器或业务数据库。
- 补验发现与修复：最初真实 PostgreSQL 创建因 body 的 object CHECK 失败。最小只读查询证明，对已序列化的同一 JSON，直接参数 ::jsonb 得到 jsonb_typeof=string，先 ::text::jsonb 得到 object；根因是 postgres.js 按 JSON OID 再次序列化字符串，而 PGlite 不表现相同行为。仅修正新 store.ts 的 6 处 JSON 参数转换，未修改共享数据库适配；同一原始创建／并发路径在新隔离数据库重跑通过。验证脚本另有顶层 after 过早关闭连接的问题，改为一个父测试管理生命周期，后续 5 个场景均实际执行。
- 打包：最终 pnpm --filter @kando/workers-api build:linux:api 退出 0，包含 3/3 真实 Node bundle 子测试；pnpm --filter @kando/workers-api deploy:dry-run:prod 退出 0，包含已有 Admin production 构建和 Worker dry-run。仅生成本地忽略产物，没有上传版本、切流或部署。
- Code Review：本轮自审覆盖管理员中间件作用范围、公开响应裁剪、scope 与复合外键、事务快照、幂等操作者／指纹、商品行锁及 JSON 驱动边界；补验修复后重新运行受影响回归、类型与两端构建并复审，未发现当前改动的阻断项。不是独立人员审查。
- 未验／未执行：真实 Apple 私有目录权限、正式组／新 SKU／优惠地区、已批准准入列表和线上 billing_product 映射仍待接入负责人核对；未做真机购买、恢复、收入平台、真实旧包或完整客户端兼容编排，未重跑全量 Workers／Admin／Flutter 测试。没有远程迁移、业务数据写入、Git commit/push 或 dev/prod 部署。真实 PostgreSQL 的本地多连接结果不代表生产延迟、连接池／Hyperdrive 或性能验收。

<a id="subscription-config-admin"></a>

## 2026-10-14：订阅配置第二阶段 Admin 页面

- 源码基线为 `codex/dev-1.0.6@cef51ec5195210397386ac8f57042afacd63b40d` 加本轮未提交改动，环境为 Windows、Node 22.20.0、pnpm 11.9.0。新增订阅配置一级入口、列表／编辑、商品／试用关系、准入提示和持久化结果核对，复用现有 Admin 请求与鉴权。接口、数据库、Flutter 和依赖未改，冻结 PRD／原型原样保留；行为见[后台文档](../04-admin/admin.md)。
- 自动化回归：最终 `pnpm --filter @kando/admin-web test` 退出 0，58/58 通过，无 skipped/cancelled。覆盖既有 Admin 行为、真实组件渲染、SKU／试用关系与文案校验、不可变操作快照、原 UUID 重放、超时核对、迟到响应隔离、会话恢复和存储失败；401／403／幂等拒绝不会误删未确认操作，手动重试的前置查询与重发共用 15 秒预算。
- 类型、依赖与构建：最终 `pnpm lint`、`pnpm type-check`、`pnpm --filter @kando/admin-web build:prod`、`pnpm --filter @kando/admin-web build:dev` 均退出 0；全仓类型检查 7 个任务成功，其中 6 个未改包命中缓存。最终 prod／dev 主 JS 分别为 `index-nH9XbSSE.js`／`index-CGSK7v0i.js`，共用 CSS 为 `index-B_9gcndT.css`；这些是本地构建结果。
- 浏览器联调使用实际 Admin 前端、第一阶段 Hono API 和隔离 PGlite；仅 Apple 商品目录及延迟、目录失败、revision 冲突和核对失败条件使用测试响应，其他外部网络访问禁用。正常读写经过现有服务端路由、校验及数据库逻辑，未访问真实 Apple 私有目录或远程业务数据库。
- 浏览器业务验证：登录／一级菜单／列表、未准入项禁止启用、已生效页面类型只读、SKU 排序连同默认项与文案保留、试用关闭再打开保留内容、最后一组解除确认、切换一次性商品后的显式解除、独立试用 SKU、空 CTA、45 秒关闭延迟及新增默认不生效均通过。CTA 含 `{price}` 时前端阻止提交，独立回查为 0 次写入；替换确认展示旧／新配置，取消无写入，确认后同类型仅一个生效。
- 异常与恢复验证：保存响应延迟 18 秒后通过原请求核对成功，仅一次写入且保存不改变生效状态；真实 revision 冲突返回 409 后输入保留，载入最新需确认；目录 503 保留已保存 Product ID 和编辑输入，失败保存不改变旧记录。另组合 18 秒延迟与核对接口 503，使结果进入 unknown；离开再进入恢复同一编辑副本，解除故障后手动核对仅确认既有结果，回查为一个写请求、一个新增记录，未重复创建且保持不生效。
- 视觉与生命周期：桌面和 780px 窄屏完成实际浏览器检查；窄屏文档宽度等于视口、表单单列、保存可达、收起侧栏账号区不遮挡。所读取的浏览器控制台无 error。临时测试页已关闭，任务自建 Vite／API 已停止，5173／6966 端口回查均无监听。截图和测试服务仅保留在本地忽略目录 `apps/workers-api/.wrangler/admin-subscription-ui-20261014170612/`，未纳入 docs 或交付源码。
- Code Review：本轮自审覆盖请求／鉴权兼容、关系保留与解除、离开保护、原请求持久化与重放预算、服务端错误映射及页面样式作用范围。联调与审查中修正了一次性商品的关系解除入口、手动重试的额外等待窗口、登录失效时原操作保留及窄屏账号遮挡；修正后完成上述最终回归、构建与对应浏览器复验，未发现当前范围的阻断项。此为本地自审，不是独立人员审查。
- 未验／未执行：真实 Apple 账号权限、正式订阅组／SKU／优惠及准入映射仍需接入负责人核验，本轮测试目录不能替代这些事实；Flutter 配置消费尚待下一阶段开发，真机购买／恢复、真实旧包新增商品支持、收入平台和线上环境未验收。未重跑全量 Workers、Flutter 或完整 App 兼容编排，服务端证据保留于上一阶段。本轮没有 Git commit/push、远程业务写入、迁移或 dev/prod 部署。

<a id="subscription-config-flutter"></a>

## 2026-10-15：订阅配置第三阶段 Flutter 消费（本地）

- 基线 codex/dev-1.0.6@fb2b274 加本轮未提交改动。配置读取、单次预算、Page／Modal 快照、SKU／试用选择、计费摘要、购买前确认和独立权益支持集合已实现；合同见[客户端流程](../01-flows/subscription-display.md)。未修改 API／数据库，Restore 既有阶段及超时保持。
- 环境：Windows、Flutter 3.44.7、Dart 3.12.2。本次没有升级依赖或工具链。最终根 Melos 执行 `dart run melos exec --scope=kando_app -- flutter test --no-pub --dart-define=APP_ENV=test <受影响测试文件> --reporter expanded` 退出 0，25 文件／644 项通过，无跳过／失败及点击未命中警告。范围为所有 subscription 命名测试、apple_current_entitlements，以及实际引用 SubscriptionPage／subscriptionControllerProvider／AppSubscriptionConfiguration 等入口的直接调用方；包含认证、启动、Profile、Home、Collection、卡牌详情和扫描页面。
- 核心包：根 `dart run melos exec --scope=subscription_core -- flutter test --no-pub --reporter expanded` 退出 0，11/11 通过。新增断言保护刚确认的实际商品对象不被旧缓存替换，以及展示 ID 不能绕过长期权益注册；既有两商店隔离、验证后完成交易和恢复失败分支继续通过。
- 静态检查：最终 `dart run melos exec -- flutter analyze --no-pub` 退出 0，App 与 subscription_core 两包均 No issues found；pnpm lint 和 pnpm type-check 退出 0，TypeScript 7 个任务成功、6 个命中缓存。首次分析发现新增代码的括号／导入规范问题，已修正且没有放宽检查。
- 自动化重点：真实 V1 响应形状解析、page/modal 查询、配置与商品共用预算、迟到结果及卸载隔离、前台刷新保持已展示快照、默认降级、关联与独立试用三态、计费条件变化需再次点击、长期支持列表、实际购买目标和 Purchase／Restore／来源返回。新 SKU／StoreKit 响应与资格在这些测试中使用明确夹具，不能当作真实 Apple 商品事实。
- UI：360px 宽度长名称／说明／100 字符 CTA 的换行和点击可达验证通过，关闭延迟同时限制按钮与 iOS 手柄拖动；Android 原行为回归通过。新增 `test/widget/goldens/rendered/subscription_config_sheet_390x844.png` 作为配置页面的结构回归基线并回读检查，使用 Flutter 测试字体，不等于真实字体／Figma 定稿或真机视觉验收。历史 v1.1 图像原字节保留；旧 iOS 固定布局用例改为动态 SKU、金额摘要、购买时冻结选择的业务断言。
- 验证中修正：初次 widget 测试有平台变量复位／滚动未完成的问题；扩大回归后，认证夹具未隔离新增配置依赖，导致真实测试 HTTP 失败、关闭按钮等待及遗留提示定时器，已补齐确定性配置夹具。受动态 UI 影响的 iOS 图像改用上述新基线；未重录历史快照。一次带空格的 Melos 测试筛选参数转发失败，不能计为通过；最终完整 25 文件回归未使用该筛选且退出 0。
- Android：最终 `flutter build apk --debug --no-pub --dart-define-from-file=config/test.json` 退出 0，产物 `apps/flutter-app/build/app/outputs/flutter-apk/app-debug.apk` 为 225519078 字节，SHA-256 `2c4c654337fcd5a787ce06469aea182fda7574b35f56cf8e94a94c80f29593eb`。首轮构建出现 Kotlin 跨盘增量缓存异常日志但最终仍产包，后续完整命令复构成功；现有 Gradle／AGP／Kotlin 版本提示保留，未升级版本或跳过构建校验。没有安装到设备，也不是签名发布验收；工程版本号仍为原 1.0.5+163。
- Code Review：本地自审复核公开接口解析、单次预算、配置快照、资格安全文案、明确商品对象、长期权益集合、原 Restore 时序、iOS 调用与 Android 隔离、关闭方式和文档边界；未发现当前本地范围的新增阻断项。不是独立人员审查，也不替代下面的原生与外部验收。
- 未运行／待验：本机无 Swift／Xcode，新增 iOS channel 的原生编译、Decimal 真实币种格式及 iOS 16.0–16.3／16.4+ 分支须在 macOS 与相应设备补验；Android 只完成 debug 构建，未做真机支付／恢复。Page／Modal 最终兜底、新商品真实 ID／优惠／准入及收入映射、旧包新增商品支持仍待接入／产品负责人确认。没有真实 Apple 调用、正式旧包测试、远端 CI／dev/prod 验收、迁移、部署、提交或推送；未重跑全量 Workers／Admin 或固定旧 Dart 客户端兼容编排。

<a id="subscription-config-ios-compile"></a>

## 2026-10-15：订阅配置 iOS 原生编译补验

- 输入与目标流水线：补验对象为远端与本地一致的干净提交 `codex/dev-1.0.6@850e3399e2bc0e07b1191d1747fbf22a73dc327d`。手动触发仓库既有 `iOS build` workflow，GitHub Actions run [#369](https://github.com/kando6370-wq/toccards/actions/runs/38669374723)／ID `38669374723` 于北京时间 10:08–10:15 完成，head SHA 与请求提交一致，job 及全部 step 结论均为 success。环境为 `macos-15-arm64`、macOS 15.7.9、Flutter 3.44.7、Xcode 16.4（16F6）、CocoaPods 1.17.0，符合仓库 iOS CI 固定工具链。
- 原生编译：目标命令 `flutter build ios --release --no-codesign --no-pub` 退出 0，Xcode 编译 176.3 秒，生成 production Bundle `com.cardai.tcg` 的 `build/ios/iphoneos/Runner.app`（日志显示 64.9 MB）。这会编译提交中新增的 StoreKit 商品读取 channel、Decimal 周均价和 iOS 16.4 `groupLevel` 可用性分支；结论仅为默认 production scheme 的无签名 device Release compile gate 通过，不是 IPA、签名或运行时业务验收。
- 依赖与锁文件：Fastlane 配置语法、workspace 依赖解析、CocoaPods 安装及 base configuration 门禁均通过；Pods 为 22 个直接依赖、49 个总 Pods。CI artifact `ios-release-lockfiles-850e3399e2bc0e07b1191d1747fbf22a73dc327d` 已下载并校验压缩包完整，`Gemfile.lock` SHA-256 `d190126a7d1e37a17e36c39e73702ad3356744b7fd77bbe7d7c849e44e01a60b`、`Podfile.lock` SHA-256 `d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，均与当前提交逐字节一致；CI 的提交锁文件无漂移门禁同步通过。
- 本机辅助补验：macOS 27.0.1／Xcode 27.0／CocoaPods 1.17.0 下，现有 Flutter 3.44.5 分别执行默认 production 命令和 `flutter build ios --release --flavor=test --dart-define-from-file=config/test.json --no-codesign --no-pub`，两次均退出 0，生成 64.7 MB／65.1 MB `Runner.app`。最终 test 产物回读为 Bundle `com.kando.kandoApp.beta`、版本 `1.0.5+163`、arm64、最低 iOS 16.0、SDK 27.0，且确认为未签名；因 Flutter patch 版本不等于目标 3.44.7，本机结果只补充覆盖 test scheme，不替代上述 CI 结论。
- 非阻断提示：CI 保留 `sign_in_with_apple` 尚不支持 Swift Package Manager 的未来兼容提示，以及 FirebaseCore CocoaPods 将停止发布新版本的弃用提示；当前 workflow 显式关闭 SPM，Pod 安装和 Xcode 编译均成功，本轮未升级依赖或改换依赖管理方式。
- 未运行／待验：未生成或检查签名 IPA、dSYM、最终 entitlements 与 beta Bundle 的 App Attest `development`，未安装真机，也未调用真实 StoreKit 商品、优惠资格、购买或 Restore；Decimal 真实币种输出和 iOS 16.0–16.3／16.4+ 运行时分支仍须对应真机补验。CI 默认 production scheme 不覆盖 test flavor；本机 test flavor 仅完成较低 Flutter patch 下的编译。Page／Modal 最终兜底、真实新 SKU／准入／收入映射、旧包新增商品支持、完整 Flutter／兼容测试及 dev/prod 部署均未在本轮执行；没有 Git commit/push、迁移、业务写入或发布。

<a id="subscription-config-dev-preflight"></a>

## 2026-10-15：Linux dev 订阅配置接入只读预检（部分完成）

本条保留首次尚未取得服务器身份时的结论；用户随后提供访问凭据后的结果见[服务器只读补验](#subscription-config-dev-server)，不再把 SSH 不可用作为当前阻塞项。

### 已取得的证据

- 本地候选为干净的 codex/dev-1.0.6@808eb1797bdc2b02835892622b47c412ff83b09a；仅同步读取远端引用，没有切换分支、合并或推送。2026-10-15 检查 Linux dev 内网 HTTP，并核对接入源码及既有部署流程。
- HTTP 健康与后台可达：GET /api/v1/health 返回 200、body 为 {"status":"ok"}；GET / 返回 200、Kando Admin HTML。这个 health 不返回运行 SHA，不能据此确认实际发布版本或数据库状态。
- 新读取接口尚不可用：GET /api/v1/subscription-display-config 的 page/ios、modal/ios、page/google 三个请求均返回 404、body 为 {"error":"NOT_FOUND"}。源码中 google 分支应在访问数据库前返回成功空配置，因此本轮不能将这些 404 简单解释为“没有生效配置”或确认是迁移未执行。
- 后台当前主包为 /assets/index-DJUOEcjk.js，200、66663 字节，SHA-256 为 9d829e0119c49c7cc90c8b2e573412c3489b44339eece02fc751104efc80c552；全文未包含 subscription-configs、subscription-products 或“订阅配置”入口。该事实与公开新接口 404 一起证明当前 HTTP 入口不能开展本次配置联调；不据此推断运行文件对应的精确 Git SHA。
- 未登录 GET /api/v1/admin/subscription-products?type=subscription 返回 401 UNAUTHORIZED。鉴权中间件可以先于路由匹配返回 401，所以该响应不能证明新目录路由存在、Apple 凭据齐备或目录权限已通过；没有创建管理员登录会话或发起配置写入。
- 远端 dev 为 8a00619fa0cf30d369ffc4b9f959cacb5714e45e，与本地候选相对独有提交数为 dev 3／候选 5；共同基线为 8ecc02577d8daf2d280233ac26d67edfd63c3006。远端 dev 不包含第一阶段提交 cef51ec，也不存在新订阅服务端／Admin 目录和 0014 迁移文件。dev 独有业务修复 0691a72 为扫描详情图片放大，当前候选尚未包含；发布候选须先整合并保留该修复。远端 Git 分支状态不等于服务器已经部署该 SHA。

### 未核验项与阻塞原因

| 项目 | 当前结论 | 继续核验所需证据 |
| --- | --- | --- |
| 服务器访问 | Windows 默认 .ssh 目录只有 known_hosts；无 SSH config、无可用 agent 身份，TOCCARDS_SSH_TARGET 未设置。本地 deploy/linux/.env 也不存在。使用项目文档中的 user@192.168.50.201、BatchMode=yes、StrictHostKeyChecking=yes 执行只读 id -un，返回 Permission denied (publickey,password)，退出 255；既有主机记录存在。 | 可用的 SSH 配置／密钥路径或已配置 kd201 的 Mac 执行环境；不将密钥或密码写入文档、聊天或仓库。 |
| 实际部署与 watcher | 未能读取 current、release-manifest、current-release、容器运行文件或 watcher 状态。 | 确认实际 SHA、容器健康与退出码、last-seen／last-deployed、失败标记及是否正在部署。 |
| 数据库迁移 | 本地候选包含 0014_subscription_display_config.sql；仅新增配置、active 指针和幂等结果三表。远端 ledger／表是否存在未知，不能沿用历史 0013 记录判定。 | 在 development 数据库只读查询 schema_migrations、三表存在性及 PostgreSQL 版本；按实际 ledger 得出 pending migrations。 |
| Apple 目录与作用域 | APP_STORE_CONNECT_* 是否齐备、实际 Bundle／App／组归属、目录读取权限均未核验。没有调用 Apple 私有 API。 | 只报告凭据存在性；使用服务端已有凭据只读核对 App／组／商品／优惠，不输出私钥或 JWT。 |
| 商品准入 | 服务端 APPLE_IAP_PRODUCT_IDS、SUBSCRIPTION_DISPLAY_PRODUCT_IDS、SUBSCRIPTION_LIFETIME_PRODUCT_IDS 和 active billing_product 映射均未回读。 | 按 Product ID 对照环境允许范围、active 状态、商品类型及 performance_pro 权益映射，不读取用户订单或购买明细。 |
| 客户端与新商品 | 当前 test.json 仍只有 cardx.week、cardx.year、cardx.lifetime，未填新增长期支持清单；Singular 仍仅映射 weekly／yearly／lifetime。 | 新商品真实 ID、试用角色、长期支持注册、收入命名及旧包支持口径；当前代码中的 ID 不等于已核验 Apple 事实。 |
| Page／Modal 兜底 | 正式两套商品组合、默认项与文案未在本轮取得定稿。 | 产品／设计确认各自节点和分环境映射；已有三档仅作为当前保留行为。 |

### 后续部署方案（尚未执行）

1. 恢复服务器只读访问，补齐上表的实际运行 SHA、ledger、环境作用域、目录及商品映射。数据库查询使用只读事务／default_transaction_read_only=on 和查询超时；不运行 migrate.sh、deploy-release.sh 或 watcher，因为这些入口会产生写入。
2. 在候选代码中整合当前 dev 的扫描图片预览修复，完成必要冲突处理与受影响验证，固定唯一发布 SHA。源码 watcher 默认跟踪 dev；先回读远端 watcher 状态，再协调合并推送与发布时序，避免手工发布被其他 dev 提交接替或并发执行。此处不自动合并或推送。
3. 补齐真实商品与 Page／Modal 定稿，形成明确的环境变量／商品映射变更清单。先选一个经核验的既有商品做首条闭环；新 SKU 在旧包支持和收入映射未闭合前保持未准入。已有秘密值原字节保留，仅新增已确认的必要配置。
4. 经部署与远程变更授权后，从已整合的干净 SHA 生成 Linux 包并检查 manifest；按既有流程执行环境／数据库预检、备份并验证备份可读性，再应用实际未执行的 PostgreSQL 迁移、发布 API 与 Admin。不重绑 D1，不处理 prod。
5. 发布后独立核对运行 SHA、容器、数据库 ledger 和静态产物；再以真实管理员读取 Apple 目录、保存不生效配置、启用／替换 page 与 modal，并用签名测试 IPA 完成购买／Restore／收入去重。配置为 null、读取失败与 404 必须分别验收，不能混为兜底成功。
6. 回退采用已知版本的应用代码／关闭新配置入口，保留新增三表与既有权益、账单数据；不删除商品映射或自动逆向 migration。

本轮没有执行远程迁移、环境改写、部署、备份、业务配置写入、Git merge／commit／push，也没有重跑无实现变更的业务测试；仅新增本条证据与方案并执行文档检查。服务器侧检查因访问条件不足未完成，不能将本次预检标为通过或已具备发布条件。

<a id="subscription-config-dev-server"></a>

## 2026-10-15：Linux dev 订阅配置服务器只读补验

### 访问与实际运行版本

用户提供服务器访问凭据后，沿用已有 known_hosts 并启用 StrictHostKeyChecking=yes，通过交互密码输入建立 SSH；凭据未写入项目文件、进程命令参数或本记录。北京时间 10:49–10:59 的补验仅执行文件／容器检查、只读 SQL 和向量服务 GET health，没有调用部署脚本、修改环境或发起业务写入。

- 宿主机 Node v22.22.1。current 与 shared/current-release 指向 manual-admin-scan-image-2c56e9f-dirty-20261014151507，manifest 的 sha 为 2c56e9f12901c33d22684c869ac29d42f3ee77c3、branch=detached、working_tree_dirty=true、source=deploy-dev。必须记录为手工 dirty 发布包，不能将远端 dev@8a00619 或该基线提交单独视为实际运行源码。
- API／DB 为 running、healthy，Web 为 running，migration 容器 exited/0。数据库继续使用 PostgreSQL 18 的既有 postgres-data 卷，没有创建新容器或数据卷。
- API 运行文件与当前 release 文件 SHA-256 均为 a2b6caf368362bdb60f3de10ad69b60fc17a3d3bdbb114b22147d2bfb435b67f，均未包含新 subscription-display-config 路由；Admin 运行容器与该 release 的 11 个 HTML／JS／CSS 文件全量匹配。结合首次 HTTP 的 404／旧后台入口，确认本次订阅模块尚未在该运行包中提供。
- shared/.env 与 API 运行环境的本次相关字段一致；10:49、10:54、10:56 回读文件 SHA-256 都为 68e7190776e49b623f86ae42b703af5be27088a00479ec0537e6ece33e2b32c8。只输出新目录凭据是否存在及必要的非敏感业务配置，没有输出私钥、数据库密码或 JWT。

### 数据库、作用域和商品准入

数据库通过容器内 TCP psql -X -w 读取，设置 default_transaction_read_only=on、statement_timeout=10000，并从查询结果确认 transaction_read_only=on。实际数据库为 toccards_test，用户 toccards，server_version_num=180006（PostgreSQL 18.6）。ledger 为 14 项，0000–0013 齐全；subscription_display_config、subscription_display_active、subscription_display_mutation 三表均不存在。相对当前候选的明确待执行迁移只有 0014_subscription_display_config.sql，本轮未执行。

运行环境为 APP_ENVIRONMENT=development、APPLE_IAP_BUNDLE_ID=com.kando.kandoApp.beta；DATABASE_URL 指向 Compose db:5432/toccards_test，与 POSTGRES_DB／USER／PASSWORD 一致。现有 APPLE_IAP_PRODUCT_IDS 为 cardx.week、cardx.year、cardx.lifetime，与客户端 test.json 内置三个 ID 相同。

| 测试 Product ID | plan_id | 数据库类型 | active／权益映射 |
| --- | --- | --- | --- |
| cardx.week | weekly | subscription | 1／performance_pro |
| cardx.year | yearly | subscription | 1／performance_pro |
| cardx.lifetime | lifetime | non_consumable | 1／performance_pro |

billing_product 另外保留 3 条 prod_* 历史映射，但不在当前 dev 环境允许列表中，不能据其 active=1 就将其当作 dev 可启用商品。本轮没有查询用户订单或购买链明细，也没有修改任何商品映射。

共享环境文件及运行容器中，下列 **7 项新配置均未设置**：

- APP_STORE_CONNECT_APP_ID、APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID。
- APP_STORE_CONNECT_ISSUER_ID、APP_STORE_CONNECT_KEY_ID、APP_STORE_CONNECT_PRIVATE_KEY。
- SUBSCRIPTION_DISPLAY_PRODUCT_IDS、SUBSCRIPTION_LIFETIME_PRODUCT_IDS。

因此旧测试商品虽具有既有权益映射，仍缺新展示准入；一次性目录也缺显式商品范围。目录读取的五项必要配置缺失，本轮没有请求 Apple 私有 API，不能宣称目录权限、真实订阅组／周期／等级／地区优惠已验证，也没有自动借用既有验单凭据。上述测试商品只能作为后续待核验候选，不能自动填入已审核展示列表。

### watcher 的实际发布阻塞

- 10:56 回读：cron 仍配置 watcher，目标分支为 dev；last-seen=f9d04a6238bc9af7512e025f556633b89b76429b、last-deployed=841db2792e485333fd1d052f21c3f49c8dafecb7。failed-sha 为 8a00619fa0cf30d369ffc4b9f959cacb5714e45e，failed-at 对应北京时间 2026-10-15 10:41:52；最近几轮处于重试冷却。手工 current release 与 watcher 的历史已部署指针不同，不能混报。
- 限量读取 watcher 日志尾部确认：该轮相关测试报告 11 个文件通过、TAP fail 0，随后失败于 Linux preflight 的 CF recognition health 契约检查。这里的测试日志属于 watcher 自己此前执行的发布尝试，不是本轮主动运行或重新验证的测试。
- 10:59 从正在运行的 API 容器、使用既有网络／代理配置发出一次 GET health：上游 HTTP 200，ok=true、dimensions=768、metric=euclidean、top_k=5。当前发布检查明确要求 512／cosine／5，候选 API 与 iOS 向量源码也仍固定 512；这是实际契约差异，不是 HTTP 连通失败或单纯缺字段。
- 本轮只证实健康契约不匹配以及它触发发布失败，未发送向量识别请求、未读取上游服务源码，也未判定应调整服务地址、模型还是业务协议；不能把检查直接改成 768／euclidean 或据此宣称所有实际扫描已经失败。未停止 watcher、改写失败标记、修改识别服务或触发重试。
- 最近备份文件为 toccards-test-20261014-151712-before-manual-admin-scan-image-2c56e9f-dirty-20261014151507.dump，1,135,406,873 字节。仅核对存在性和元数据，未运行 pg_restore --list 或恢复演练；后续部署仍须按流程创建并验证新的发布前备份。

### 当前结论与修订后的执行顺序

服务器访问条件已经解除，本轮已完成运行包、容器、ledger、环境配置及本地商品映射的只读核验；**预检结论为尚不具备订阅配置联调发布条件**。真实 Apple 权限／商品事实、两套兜底定稿、新 SKU 收入与旧包支持仍待完成。

1. 先核对 dev 配置的向量服务与当前 512 维模型／cosine 协议，确认兼容方案并完成独立修复验证；保留有效部署门禁，不仅为通过发布而放宽检查。原始服务地址／模型是否变更的根因仍待定位。
2. 在候选中整合 dev 的 0691a72 扫描详情图片预览修复，固定唯一可验收 SHA；协调仍在运行的 watcher，避免自动重试、合并推送与手工发布并发。当前没有执行 Git 合并或推送。
3. 安全补齐上述 Apple App／组／团队 Key，并完成真实目录只读核验；经审核后确定 Lifetime 范围、展示准入、Page／Modal 兜底和新 SKU 支持／收入映射。保留已有环境值与历史商品支持，不以本地或数据库存在 ID 代替 Apple 核验。
4. 获得实际远程变更授权后，按既有流程预检、备份并检查可读性、应用唯一待执行的 0014、发布 API／Admin，再独立核验实际 SHA、ledger、产物及目录。随后用已核验的既有商品开启首条 Sandbox 真机购买／恢复／收入闭环。

本轮仅更新预检文档和索引；未执行业务代码修改、Git commit／push、远程迁移、环境改写、备份、部署或配置启用，也未操作 prod。已有密码登录成功不等于后续非交互发布已具备密钥／agent 配置；自动化发布的 SSH 登录方式仍须按发布入口准备。

<a id="subscription-config-baseline-resolution"></a>

## 2026-10-15：订阅发布候选的扫描基线定位与 Admin 修复整合

### 根因与协议冲突

本条补充前述健康检查差异的根因证据。11:10 从 Linux dev 的实际共享配置和运行容器回读，VECTOR_RECOGNITION_BASE_URL 均为 https://recognize.tcgcard.fun。该服务自报 recognize-phash-vector，使用 cards_phash、768／euclidean／Top 5，输入为 Base64URL 的 r／g／b 和可选 ocr_text，不是当前候选的 vector 数组协议。

运行 manifest 指向的 dev-xiangyang@2c56e9f 源码使用 rgb-phash-16-v1；其 preflight 也明确校验 768／euclidean／5 和 cards_phash。因此不能把原问题概括为“原向量服务突然改了参数”，也不能仅修改当前候选的健康检查数字。当前 dev 手工运行基线和 watcher 跟踪的 dev／订阅候选属于两套协议。

当前订阅候选继续使用 PE Core T16 512 维向量：共享 Flutter 检查 embedding 长度为 512，API 校验 512，部署门禁校验 512／cosine／5；仓库默认 URL 为 https://recognize-vec.tcgcard.fun。11:15 从正在运行的 dev API 容器，以相同网络／代理环境只读访问此候选 URL，返回 200、ok=true、dimensions=512、metric=cosine、top_k=5，输入声明为 JSON vector:number[512]。无需为了通过发布放宽现有检查。

| 基线 | API／客户端协议 | 配套服务 | 已确认边界 |
| --- | --- | --- | --- |
| 当前 Linux 手工运行包 | 2c56e9f 对应 pHash／OCR，r／g／b／ocr_text | recognize.tcgcard.fun，768／euclidean | manifest、源码、实际环境与 health 可对应；未发送实际识别请求。 |
| 当前订阅候选 808eb17 + 本地增量 | 512 维向量，vector／card_type | recognize-vec.tcgcard.fun，512／cosine | iOS／Android 共享长度校验、API 与 health 契约一致，dev 网络可达；未切换服务器。 |

后续若采用当前候选，应将 API／测试 App 与 VECTOR_RECOGNITION_BASE_URL 一起按向量基线安排切换。单独改正在运行的 pHash API 地址会令输入协议不匹配；将候选改成 pHash 则需要移植另一分支的扫描业务，并与当前仓库的向量约束冲突。此项会改变 dev 正在运行的扫描基线，需要明确确认后执行，不能在订阅功能发布中静默夹带。 用户随后已确认本次采用 512 维向量，见下文[方案确认](#subscription-config-vector-decision)。环境文件回读 SHA-256 仍为 68e7190776e49b623f86ae42b703af5be27088a00479ec0537e6ece33e2b32c8，本轮没有修改环境、部署门禁或任何扫描实现。

### 已完成的独立整合

将 dev 中 0691a72 的三个 Admin 文件补丁精确移植到当前工作区，并合入其两份既有业务／历史验证文档；原来的两份未提交预检文档内容保留。扫描详情原图继续走鉴权 Blob，仅详情开启 Ant Design 图片预览，列表缩略图、候选图和失败占位沿用原行为。订阅配置页面及服务端源码没有改动。

这是工作区内容整合，尚未执行 Git merge／cherry-pick 提交或推送，也没有把当前分支描述为已经在提交历史上包含全部 dev。原修复的历史失败证据保留；本轮将从整合前 HEAD 提取原实现，在本地隔离目录使用相同用例补做失败反证，再对最终工作区执行回归。

### Apple 接入准备与仍缺的输入

- 当前服务端七项新增配置仍缺失；没有新增或复用其他验单凭据，没有请求 Apple 私有目录，也没有批准任何新商品。
- 历史[Apple 设置文档](../../v1.1.0/05-delivery/app-store-connect-subscription-setup.md#86-weekly-与-yearly-查询前置检查)记录测试 Bundle com.kando.kandoApp.beta、Performance Pro 组 22251901 和三个 cardx 商品。该组 ID 仅是历史核验候选，不代表今天的 App／组归属、销售范围或免费优惠已确认，不自动写入服务器。
- 需要提供具备本 App 目录读取权限的团队 Key 的安全配置位置，并确认 App 数字资源 ID；随后才能通过 Apple 只读 API 核验组和商品、填写展示准入。Page／Modal 定稿、新 SKU 及收入／旧包支持缺项保持原记录。

### 本地验证与交付边界

- 隔离反证：从整合前 HEAD（808eb17）提取 App.tsx／App.css，使用最终 scans-intent.test.mjs 在忽略目录执行 node --test，退出 1；原有 7 项通过，新增“详情原图鉴权预览”用例唯一失败，无跳过。该反证在补丁移植后对旧源码执行，不记为修改前已经实测。
- 最终 Admin：pnpm --filter @kando/admin-web test 退出 0，59/59 通过；pnpm --filter @kando/admin-web type-check 退出 0。既有订阅配置、鉴权、请求 ID、列表与原图占位行为继续通过相关回归；没有复验真实远端 Admin 登录态点击。
- 部署合同：node --test deploy/linux/preflight.test.mjs 退出 0，8/8 通过。代码和门禁未变；检查继续拒绝不匹配的识别健康协议并在失败时阻止备份／容器变更。
- 本地候选打包：pnpm --filter @kando/workers-api deploy:dry-run:dev 退出 0，包含 Admin development 构建及 Linux bundle 3/3；包为 apps/workers-api/.wrangler/linux-release-YUrUIp.tar.gz，2128463 字节，SHA-256 dd7ac1e7d9001c8b8a0b9cc63b6c57555a8ec5b4eee2496664178daeded1e774。manifest 为 sha=808eb1797bdc2b02835892622b47c412ff83b09a、branch=codex/dev-1.0.6、working_tree_dirty=true；因此不是纯提交发布包。含 15 份 PostgreSQL migration（包括 0014），目录检查未包含 .env、.dev.vars 或 .p8 私钥。
- 本地 Code Review：原图预览三个文件可以对 0691a72 原补丁完整反向检查，确认移植内容没有另起实现；复核列表默认关闭、详情显式开启、Blob 鉴权与生命周期、样式作用域以及订阅入口共存。未发现本地源码阻断项；这是自审，不是独立人员审查或真机／线上验收。
- 未运行／未执行：没有变更 Flutter／扫描协议或预检门禁，未重跑完整 Workers／Flutter／固定旧客户端编排；所有远端探针只发 GET health，没有识别或购买请求。没有远程环境改写、迁移、部署、配置启用、Git merge／commit／push。扫描基线切换与真实 Apple 目录／商品准入仍待确认和接入，不能把打包成功作为发布验收通过。

<a id="subscription-config-vector-decision"></a>

## 2026-10-15：订阅联调采用 512 维向量方案的用户确认

- 用户明确 pHash／OCR 是另一位同事的测试，本次业务采用 512 维向量方案。该业务选择已经确认，后续不再重复询问，也不将另一分支的 pHash／OCR 实现移植进本次订阅候选。
- 本次配套合同固定为：Flutter 端侧 PE Core T16 512 维输出、API 的 vector／card_type 请求、recognize-vec.tcgcard.fun 的 512／cosine／Top 5；VECTOR_RECOGNITION_BASE_URL 的候选值为 https://recognize-vec.tcgcard.fun。当前源码、模板和门禁已经符合此选择，无需修改扫描算法或放宽检查。
- 前述 Linux 运行包／环境回读仍是历史实测证据，用户选择不代表已经执行服务器切换。后续按同一候选版本安排 API、环境地址和测试 App 配套，协调同事的独立测试；本轮没有覆盖或停止其运行包，也没有修改 watcher。
- 独立的 Apple 目录前置条件仍未完成：目录团队 Key 的安全配置位置、App 数字资源 ID及组归属／商品事实需通过受权的 Apple 只读访问核验。历史组 22251901 继续只是核验候选；其余展示准入、Lifetime 范围、正式兜底和新 SKU 收入／旧包支持保持既有要求，不自动填入猜测值。
- 本轮仅更新规则与文档，沿用上一轮业务验证，不重复运行业务测试；执行文档链接／锚点和 git diff --check 检查。没有新增业务代码变更、Git commit／push、远程迁移、环境改写、部署或配置启用。

<a id="subscription-config-apple-env"></a>

## 2026-10-15：指定测试环境文件与已有 Apple Key 的目录认证核验

本条是原 APPLE_IAP 凭据的失败证据；随后用户提供的新目录团队 Key 已通过真实目录读取，见[新 Key 与商品目录补验](#subscription-config-apple-catalog-live)。

用户指定 /home/user/apps/toccards-test/current/deploy/linux/.env 为测试配置入口。11:39 实际 lstat／readlink／realpath 确认该文件为符号链接，目标就是 /home/user/apps/toccards-test/shared/.env，与此前检查的是同一文件、相同字节；没有遗漏另一份独立配置。

- 文件中已有 APPLE_IAP_ISSUER_ID、APPLE_IAP_KEY_ID、APPLE_IAP_PRIVATE_KEY。私钥可由 Node 解析为 EC／prime256v1（P-256）；只检查格式和存在性，没有输出任何凭据值。APPLE_IAP_APP_ID 为空，Bundle 为 com.kando.kandoApp.beta，产品允许列表仍为三个 cardx 商品。
- APP_STORE_CONNECT_APP_ID、APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID、APP_STORE_CONNECT_ISSUER_ID、APP_STORE_CONNECT_KEY_ID、APP_STORE_CONNECT_PRIVATE_KEY、SUBSCRIPTION_LIFETIME_PRODUCT_IDS、SUBSCRIPTION_DISPLAY_PRODUCT_IDS 七项仍未设置。此前“新目录配置缺失”指这些新模块字段，不表示服务器完全没有 Apple 签名配置。
- 按用户指明的凭据位置，在确认文件与 API 容器的相关值一致后，仅在运行容器进程内使用已有 APPLE_IAP Key，向官方 App Store Connect API 发出两次按 beta Bundle 过滤的 GET /v1/apps。没有请求其他 App 的目录、读取用户交易或进行业务写入；诊断中的内存字段映射不是新模块的自动凭据回退实现，也没有复制／改写任何环境字段。
- 11:43 首次请求使用 ES256、64 字节原始签名和 120 秒有效期，并限制可选 scope；本地签名自检通过，Apple 响应时间与宿主时钟相差小于 1 秒，响应为 401 NOT_AUTHORIZED，标题为 Authentication credentials are missing or invalid。
- 11:47 使用当前 catalog.ts 的 createCatalogToken 原始实现，在内存中打包并执行，按新模块实际 claims（不带可选 scope）复核同一只读请求，仍返回 401 NOT_AUTHORIZED；响应时间差仍小于 1 秒。不能将失败仅归因于首次探针的可选 scope，也不能认为将变量改名为 APP_STORE_CONNECT_* 就能恢复目录访问。
- 结论：指定配置路径和已有签名材料已找到；现有这组凭据目前未通过目录 API 认证。其是否属于目录可用的团队 Key、是否已撤销／失效，或者 Issuer ID／Key ID／私钥是否正确配对，当前证据尚不能唯一判定。私钥能解析／本地签名正确不等于 Apple 接受认证，本轮也没有验证这组凭据的既有 App Store Server API 能力。
- 仍需在 Apple 后台核对该 Key 的类型、状态和配对信息，或提供可用于目录读取的团队 Key 安全配置；获得成功的只读目录响应后，再确认 App 数字资源 ID、历史组 22251901 的实际归属及商品事实。不写入猜测的 App／组 ID，不批准新 SKU。
- 两次请求前后的环境文件 SHA-256 保持 68e7190776e49b623f86ae42b703af5be27088a00479ec0537e6ece33e2b32c8；密码、私钥、Issuer／Key ID 和 JWT 均未输出或写入项目记录。没有代码变更、远程环境修改、部署、迁移、商品启用或 Git commit／push；仅更新文档并执行链接／差异检查。

<a id="subscription-config-apple-catalog-live"></a>

## 2026-10-15：新目录团队 Key 与真实测试商品目录补验

用户提供新下载的 .p8 路径和 Issuer ID，Key ID 从下载文件名取得；不再沿用旧 APPLE_IAP 的签名材料。私钥在本地解析为 EC／prime256v1，通过 SSH 标准输入传给 dev 容器内存中的诊断进程；没有复制到项目、远端文件或进程命令参数，也未输出私钥、Issuer ID 或 JWT。

14:00 起，从 dev API 容器使用当前 catalog.ts 的 createCatalogToken／createAppleCatalogLoader 实际实现，以 GET 查询指定 beta Bundle。发现 App 和组的 2 次请求、正式目录读取的 9 次请求共 11 次均返回 200；当前实现的 10 秒目录预算内成功完成 App 归属、指定组、5 个订阅及各自介绍性优惠、显式 Lifetime 范围读取，未重试或请求无关 App。鉴权与目录权限已验证，不代表商店交易和商品准入完成。

- 测试 Bundle：com.kando.kandoApp.beta；App 数字资源 ID：6790245922；当前 Apple 名称：Kando KP App。
- 订阅组 ID：22251901，已由目标 App 的实际组列表确认归属；当前 referenceName 为 card ai。历史文档里的 Performance Pro 是当时记录，不回写历史，也不把名称当作 ID 判断依据。
- 一次性读取的诊断范围仅包含已有配置中的 cardx.lifetime，已确认 Apple 返回的类型为 NON_CONSUMABLE；该临时只读范围不等于已向服务器写入 Lifetime 配置或批准展示。

| Product ID | Apple 参考名 | 类型／周期 | group_level | 当前免费试用目录事实 |
| --- | --- | --- | --- | --- |
| cardx.week | weekly | subscription／ONE_WEEK | 2 | 无介绍性优惠记录 |
| cardx.year | yearly | subscription／ONE_YEAR | 1 | 无介绍性优惠记录 |
| weekly.trial | 周试用 | subscription／ONE_WEEK | 3 | 175 个地区记录，FREE_TRIAL／THREE_DAYS／1 期，2026-10-12 起、无结束日期 |
| yearly.pro | 年订阅 | subscription／ONE_YEAR | 5 | 无介绍性优惠记录 |
| cardx.month | 月订阅 | subscription／ONE_MONTH | 4 | 无介绍性优惠记录 |
| cardx.lifetime | lifetime | non_consumable | 不适用 | 不适用 |

- 六个返回商品的 state 均为 MISSING_METADATA。这是实际目录状态，不能把 HTTP 200 或目录存在当作商品元数据齐备、正式可售、Sandbox 可购买或已审核通过；没有查询个人 StoreKit storefront 或实际发起交易。
- cardx.week 与 weekly.trial 同组／同周期但等级分别为 2 和 3。使用真实目录结果在本地执行当前 validateCatalogReferences，拟关联卡片准确返回 skus.0.trial.product_id 错误；因此按现有合同不能建立这组关联。weekly.trial 作为独立 SKU 的方案仍需商品准入、客户端注册及收入／旧包支持核验，不自动调整 Apple 等级或放宽服务端规则。
- 新发现的 weekly.trial、yearly.pro、cardx.month 不在此前回读的 dev APPLE_IAP_PRODUCT_IDS／billing_product 测试映射及客户端长期支持注册中；需要明确接入后才能启用。原三个 cardx 商品的历史映射证据保留，本轮未重查或写入数据库。
- 原有 401 只适用于旧 APPLE_IAP 凭据；新 Key 已通过当前目录实现验证，目录认证阻塞解除。App ID／组 ID 现在来自实际返回值，后续部署可据此准备配置；服务器 APP_STORE_CONNECT_*、展示准入和 Lifetime 环境项本轮仍未写入。
- 环境文件读取前后字节一致，SHA-256 仍为 68e7190776e49b623f86ae42b703af5be27088a00479ec0537e6ece33e2b32c8。没有配置替换、Apple 管理写操作、商品启用、远程数据库迁移、部署、Git commit／push；仅新增验证摘要和更新文档入口，执行文档链接／差异检查，不重跑无源码变更的业务测试。剩余边界为商品元数据、试用关联等级、准入／收入／旧包支持、独立兜底定稿及真机联调。

<a id="subscription-config-trial-level-recheck"></a>

## 2026-10-15 14:20：周订阅与周试用的等级调整复验

用户告知已在 Apple 后台将 cardx.week 和 weekly.trial 设为同等级后，使用同一新目录团队 Key、当前 catalog.ts 实现，从 dev 容器重新只读拉取 beta App 的实际目录。共 11 次 GET 全部 200；App 6790245922、Bundle com.kando.kandoApp.beta、订阅组 22251901 的归属不变。

| Product ID | 实际 group_level | 周期 | 免费试用目录事实 |
| --- | --- | --- | --- |
| cardx.week | 2 | ONE_WEEK | 无介绍性优惠记录，has_free_trial=false |
| weekly.trial | 2 | ONE_WEEK | 175 个地区，FREE_TRIAL／THREE_DAYS／1 期，2026-10-12 起、无结束日期 |

- 使用相同拟关联配置，调用当前 parseDisplayConfig 与 validateCatalogReferences：配置结构无错误；14:00 旧目录仍复现 skus.0.trial.product_id 错误，14:20 新目录返回空 issues。确认等级不一致的关联阻塞已解除，无需修改 PRD 或放宽校验；本轮没有保存／启用该拟配置。
- 两个商品当前 state 仍为 MISSING_METADATA；目录关系有效不等于用户具有试用资格、商品已经正式可售、已完成 Sandbox 购买或系统商品准入。weekly.trial 的服务端允许列表／active 权益映射、客户端长期支持及收入／旧包支持仍需后续接入。
- 本次 Apple 商品等级修改由用户完成；本轮工具只读取目录。远端环境文件前后字节一致，SHA-256 仍为 68e7190776e49b623f86ae42b703af5be27088a00479ec0537e6ece33e2b32c8。没有改写 .env、数据库、Apple 商品、部署或 Git 提交推送；仅更新文档并检查链接及 git diff --check，不重跑无业务源码变更的测试。

<a id="subscription-config-dev-catalog-env"></a>

## 2026-10-15 14:37–14:40：dev 目录配置落地与运行环境验证

按用户“继续完成 dev 目录配置落地”的明确授权，仅更新 Linux dev 的目录读取配置并让现有 API 容器加载。目标 /home/user/apps/toccards-test/current/deploy/linux/.env 仍链接到 shared/.env；先核对 development／beta Bundle、current release、运行镜像、Compose 环境一致性及原文件哈希，再持有既有 watcher／deploy 两把锁实施变更。

| 本轮新增环境字段 | 落地值／验证方式 |
| --- | --- |
| APP_STORE_CONNECT_APP_ID | 6790245922 |
| APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID | 22251901 |
| APP_STORE_CONNECT_ISSUER_ID | 用户提供的团队 Issuer，文件与运行容器一致；不记录原值 |
| APP_STORE_CONNECT_KEY_ID | 已验证的新目录团队 Key，文件与运行容器一致 |
| APP_STORE_CONNECT_PRIVATE_KEY | 用户提供的新 P-256 私钥，多行原文只存入私有环境配置，不进入项目或诊断输出 |
| SUBSCRIPTION_LIFETIME_PRODUCT_IDS | cardx.lifetime，仅限定非消耗型目录读取范围，不代表商品展示准入 |

### 配置保存与运行加载

- 修改前独立快照确认原 .env 权限 600、属主／组均为部署用户，Compose 2.40.3+ds1-0ubuntu1 解析的现有 API 环境与运行容器完全一致。原镜像 tag 指向当前运行 image ID，没有镜像漂移。
- 原文件逐字节备份到 /home/user/apps/toccards-test/shared/.env.before-catalog-20261015T063719787Z.bak，权限 600；采用同目录临时文件＋原子 rename 更新真实 shared/.env，保留用户访问的符号链接、属主／组及 600 权限。旧文件全部原始字节保留为新文件前缀，只追加上述 6 项。Node 与 Compose 对多行私钥的解析均与期望一致，其余配置及服务定义全量对照未变。
- 原 .env SHA-256 为 68e7190776e49b623f86ae42b703af5be27088a00479ec0537e6ece33e2b32c8，新值为 062e06594191a9125081a9f595a23f9fa13c4798280f86a9b582c4f920847b6e。已有 APPLE_IAP_*、数据库／JWT、代理、插件及其他环境项原值全部保留；没有自动复用或替换旧验单 Key。
- 使用当前 release 的两份 Compose 文件执行仅 api 的 up -d --no-deps --no-build --pull never。API 容器重建后 healthy，image ID 仍为 sha256:1a559fcbff112c2c2f9e8b04c6f2cbccbf27323a0e4838b723598708ff71e805，API bundle SHA-256 仍为 a2b6caf368362bdb60f3de10ad69b60fc17a3d3bdbb114b22147d2bfb435b67f。DB／Web／migrate 的容器 ID、镜像、启动时间与状态对照均不变，未运行 build、pull、migrate、完整发布脚本或 watcher。
- current／manifest 仍为 manual-admin-scan-image-2c56e9f-dirty-20261014151507，VECTOR_RECOGNITION_BASE_URL 未改，未切换同事的 pHash／OCR 运行包。两把锁仅在本操作期间持有，结束后释放；14:40 回读时既有 watcher 按 cron 自行运行，未改其分支、计划或状态文件。

### 实际验证

- 从重建后的 API 容器直接读取 process.env，临时运行当前 catalog.ts 的目录读取实现；本次没有再从开发机注入凭据。App／组／5 个订阅及介绍性优惠／Lifetime 共 9 次 GET 全部 200，返回 cardx.week、cardx.year、weekly.trial、yearly.pro、cardx.month、cardx.lifetime。测试 App 6790245922、Bundle com.kando.kandoApp.beta、组 22251901 正确；周普通与试用的等级均为 2。
- 独立第二次 SSH 回读确认：shared/.env 与运行容器的目录字段一致、三项凭据均存在，新文件哈希匹配，API／DB healthy、Web running。数据库只读查询仍为 PostgreSQL 18.6、ledger 14 项／最新 0013；新增订阅三表仍不存在，没有执行 0014。
- 外部 HTTP 烟测：health 200／status=ok，Admin 首页 200；无认证 auth/me 与 admin/scans 均为 401。新 subscription-display-config 接口仍返回 404，符合当前运行包尚无新订阅路由的事实；目录函数的临时真实读取通过不等于新业务接口或 Admin 订阅菜单已上线。
- SUBSCRIPTION_DISPLAY_PRODUCT_IDS 仍未设置；APPLE_IAP_PRODUCT_IDS 仍为原三个 cardx 商品，billing_product 未改。没有启用任何配置或批准新 SKU。本轮目录配置完成，不包含商品准入、真实 StoreKit 可售／资格、购买／Restore、收入、正式兜底或生产验收。

失败回退预案为恢复同权限原文件备份并以原镜像重新加载 API；本轮执行成功，未触发回退，不宣称完成回退演练。没有 Git commit／push 或业务源码变更；本地仅补充实际操作记录及入口，验证文档链接／锚点和 git diff --check，没有重复运行无代码变化的全量测试。

<a id="subscription-config-dev-release"></a>

## 2026-10-15：订阅模块整合 dev、0014 迁移与 512 维向量配套发布

### 发布来源与验证

- 用户明确授权整合并推送 dev、协调 watcher、备份与迁移 0014、发布 API／Admin 和切换 512 维向量；新配置保持不生效，prod 不操作。本地 dev 从 8a00619 合入 codex/dev-1.0.6@ca0180d，无冲突，合并树与 ca0180d 完全一致；保留 dev 的扫描原图预览修复。干净合并提交 f8afca9f401e785a586194637f02cab23016f35c 已推送 github/dev 并回读一致。
- 本地发布检查：Workers 9 文件／101 项、Admin 59 项、Linux 预检与 Web 服务合同 10 项、Linux bundle 3 项均退出 0，无跳过。Workers 范围包括 subscription-config、Linux config／vector adapter、Admin billing summary、app-config／version-control 和 App contract；pnpm lint、pnpm type-check 通过，7 个类型任务成功、6 个命中缓存。合并树未改变 Flutter 代码，没有重跑之前的完整 Dart 回归。
- 同一 f8afca9 的远端 [App compatibility run 38696980247](https://github.com/kando6370-wq/toccards/actions/runs/38696980247) 与 [iOS build run 38696980522](https://github.com/kando6370-wq/toccards/actions/runs/38696980522) 经 GitHub API 回读为 completed／success、head SHA 一致；本机没有 gh，使用官方 REST 只读取得结果。此为工作流结果，不等于签名包、真机或完整兼容矩阵通过。
- 本地 deploy:dry-run:dev 生成 linux-release-Nfqv5A.tar.gz，2,128,446 字节、SHA-256 411a4da12e8fd31a9cac385ddddf57f9a335edce411a498a6014d111c82c81b7；manifest 为 branch=dev、sha=f8afca9、working_tree_dirty=false。上传后 archive 哈希一致，包不包含 .env、.dev.vars 或 .p8 私钥。

### 备份、发布与配置切换

- 先持有既有 watcher/watch.lock，确保 push、环境准备和发布期间不会并发自动发布；标准 deploy-release.sh 自行持有 shared/deploy.lock。远端预检确认独立 toccards_test／PostgreSQL 18、向量健康 512／cosine／Top 5，唯一 pending migration 为 0014_subscription_display_config.sql。
- 为避免发布失败时旧 pHash API 被错误地址破坏，先在 shared 下生成权限 600 的私有候选环境文件，仅改变 VECTOR_RECOGNITION_BASE_URL 为 https://recognize-vec.tcgcard.fun；正式 shared/.env 在新应用验收前保持原字节。使用既有 TOCCARDS_ENV_FILE 参数把候选交给标准发布脚本，未修改脚本或放宽门禁。
- 迁移前独立验证备份：toccards-test-20261015T071446Z-verified-before-manual-dev-f8afca9f401e-20261015T071443Z.dump，1,135,406,947 字节，pg_restore --list 成功读取 324 项。此备份先于标准脚本的数据库／容器变更完成，确保存在已验证的恢复材料。
- 标准脚本另生成发布前备份：toccards-test-20261015-152057-before-manual-dev-f8afca9f401e-20261015T071443Z.dump，1,135,407,026 字节；发布后 pg_restore --list 同样成功读取 324 项。两份备份均保留于 /home/user/apps/toccards-test/backups/，没有执行恢复演练。
- 标准脚本发布 release manual-dev-f8afca9f401e-20261015T071443Z，退出 0；迁移容器退出 0，ledger 从 14 项到 15 项，新增唯一为 0014。原 PostgreSQL 18 数据卷 toccards-linux-test_postgres-data 保留，旧 billing_product 的 6 条映射前后相同，没有注册新权益商品。
- 新应用验证后，把候选内容原子保存到 shared/.env，并将新 release 的 .env 链接指回该共享文件。环境哈希从 062e06594191a9125081a9f595a23f9fa13c4798280f86a9b582c4f920847b6e 变为 19496cce4b00b2bbfabb7af8330b7075ba86c23a86d83ac3c8d4b2ccb3d0048f，完整解析比较仅向量服务地址不同；目录／验单 Key、数据库、JWT、代理、插件等原值全部保留，权限仍为 600。
- 原私有环境备份为 shared/.env.before-manual-dev-f8afca9f401e-20261015T071443Z；临时候选文件在确认共享配置和链接正确后移除。若要回退到旧 pHash release，必须先恢复对应原环境并重新加载旧应用，不能只回退代码而留下向量地址；新增三表及历史权益不自动逆向迁移或删除。本轮未触发回退。
- 经独立确认发布 SHA、产物、数据库与空生效状态后，备份 watcher 原状态到 shared/watcher-state.before-manual-dev-f8afca9f401e-20261015T071443Z.json，将 last-seen／last-deployed 对齐已验收手工发布的 f8afca9，并清除旧 8a00619 失败标记。此为人工协调后让 watcher 接手，不伪称 watcher 自己构建了本次 release；cron、跟踪分支和脚本未修改。发布锁随后释放。

### 15:38 独立验收

- current、manifest、current-release 指向该干净 f8afca9 release；API／DB healthy、Web running、migrate exited/0。运行 API SHA-256 为 9c1018d6d9b07647163b446a094f75a65d7dd282c8087ed330d1a48566b06902，与批准构建一致。运行容器与 HTTP 实际返回的全部 11 个 Admin HTML／JS／CSS 文件分别逐字节匹配批准构建。
- SQL 通过只读会话确认 PostgreSQL 18.6、ledger 15 项／最新 0014；subscription_display_config、subscription_display_active 中的非空生效指针、subscription_display_mutation 计数均为 0。没有创建草稿或启用 Page／Modal 配置，SUBSCRIPTION_DISPLAY_PRODUCT_IDS 仍未设置，APPLE_IAP_PRODUCT_IDS 仍为原三个 cardx 商品。
- HTTP：health、Admin 首页为 200；未认证 auth/me 与 Admin 商品目录为 401；Page／Modal 的 ios 读取和 google 读取均为 200、success=true、data=null，响应 no-store；非法页面类型为 422。新路由已从先前的 404 变为正确空生效响应。
- 从新 API 容器的实际环境读取向量 health，返回 200、512／cosine／Top 5。临时运行当前目录函数、仅使用持久环境配置进行 Apple GET，9 次均为 200，正确读取 beta App 6790245922／组 22251901 下的 5 个订阅与显式 Lifetime 商品。
- 当时 watcher last-seen／last-deployed 均为 f8afca9，失败标记不存在。后续只含文档的提交可能仅推进 last-seen，部署源码仍以本条 manifest SHA 为准。
- 未验范围：没有真实 Admin 登录态的新增／编辑／启用操作，没有真机扫描、StoreKit 价格／资格、购买／Restore／收入或旧包新增商品恢复；没有发布 Flutter 签名包、营销站或 prod。目录读取和健康响应不代表这些业务验收完成。本轮仅履行新模块 dev 部署且保持不生效的范围。

## 2026-10-15：iOS 测试环境内部安装包 1.0.5 (166)

- 构建输入：从构建前干净且与远端一致的 `dev@7dc6a1bd2557f505f1efd01c53a0c536165d90f9` 构建。源码版本为 `1.0.5+163`，但测试包保存目录已有 164、165，因此显式执行 `./tool/release_ios.sh --env test --pgy --build-number 166`，避免默认构建号碰撞。脚本在全部制品门禁通过后将 `apps/flutter-app/pubspec.yaml` 同步为 `1.0.5+166`。
- 环境与依赖：`config/test.json` 校验通过，dev health `http://192.168.50.201:8080/api/v1/health` 返回 `status=ok`。`flutter pub get` 没有改变锁定依赖；根 `pubspec.lock` 与 iOS `Podfile.lock` 构建前后 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021` 和 `d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`。当前清理构建没有 Google ML Kit Pods 或对应模拟器架构提示；`sign_in_with_apple` 尚未支持 Swift Package Manager 的工具链提示不阻断本次 CocoaPods 真机 IPA。
- 本地验证：Flutter 3.44.5／Dart 3.12.2。`flutter analyze` 与发布脚本内第二次分析均通过；共享 `subscription-core` 使用 `flutter test` 运行 11 项全部通过。App 的发布配置、环境、订阅展示／恢复／启动与 Profile 相关 8 个测试文件共 216 项，其中 212 项通过；4 项 Golden 像素对比失败，分别为 Profile 升级横幅 3.48%、订阅成功 300ms 帧 0.04%、订阅配置底部页 2.36%、订阅成功页 1.54%，本轮没有擅自更新 Golden。最初误用 `dart test` 运行依赖 `flutter_test` 的共享包时因缺少 `dart:ui` 无法加载，已改用正确的 `flutter test` 并通过，不把前一次无效调用记为业务测试通过。
- 构建结果：依赖解析、清理、Xcode Archive、IPA 导出、签名校验与保存流程均退出 0。对保存产物的独立只读审计确认 `com.kando.kandoApp.beta / 1.0.5 (166)`、最低 iOS 16、Apple Development 签名、`get-task-allow=true`、App Attest `development`，包含测试 Firebase `card-ai---test` 与 dev API `http://192.168.50.201:8080/api/v1`；描述文件包含 6 台设备。IPA 的 42 个唯一 Mach-O UUID 均有匹配 dSYM，缺失和额外 UUID 均为 0；压缩包内两个完全重复的 dSYM 条目不影响 42/42 覆盖或符号化。
- 保存与保留：IPA 为 39,936,383 字节，SHA-256 `468605552ee72703ee09c9803a9575547f9c75be263ae6f1494ba407b3962d7c`；`dSYMs.zip` 为 61,179,019 字节，SHA-256 `d24d0c9ff709de866a5f6fee4be87ff8ce2ec409b0cf6ddb6a7eb61a10a1afec`。两份 ZIP 完整性检查通过，保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-166/`。新版本完整保存后，旧 162 版移入废纸篓；当前保留 164、165、166，正式包及 Xcode Archives 不受影响。
- 边界：本次没有安装设备、上传蒲公英／TestFlight／App Store Connect、提交或推送 Git，也没有部署或修改服务端。没有运行全量 Flutter／Android 测试，未执行 iOS 真机登录、订阅价格／资格、购买／Restore、扫描或崩溃上报端到端验收；4 项 Golden 失败仍是明确的未关闭验证项。

<a id="subscription-config-sku-limit"></a>

## 2026-10-15 页面展示 SKU 最多 3 个（本地验证）

用户补充每组订阅配置最多 3 个页面展示 SKU。基于 `codex/dev-1.0.6@ca0180d` 加本轮未提交改动，在 Windows 本地实现并验证；本节仅描述数量上限增量，不替代此前的 dev 发布记录。

- Admin 在 3 个及以上时禁用添加，删除后可恢复；保存校验同时拦截超限。组件静态渲染覆盖 Page／Modal、三卡禁用、删减后恢复和四卡存量仍完整显示，未将静态渲染记为浏览器点击验收。
- 服务端共用校验器覆盖新增、保存、生效和公开读取。3 个展示项外可关联试用；独立试用与一次性商品计入展示数量。PGlite 内存 PostgreSQL 接口用例确认超限写入返回 422、失败结果可核对，原内容、版本和生效指针不变；超限存量仍可读取、关闭和修正，公开读取返回 503。
- Flutter 拒绝整份超限远端配置，使用既有兜底，不截断商品列表。合法三卡的顺序、默认项和关联试用目标保留；购买／Restore 长期商品集合未改变。无 Schema、migration、原生平台或购买接口修改。

| 实际命令 | 结果 |
| --- | --- |
| `pnpm --filter @kando/admin-web test` | 退出 0，61 项通过，0 跳过 |
| `pnpm --filter @kando/workers-api test src/subscription-config/model.test.ts src/subscription-config/routes.postgres.test.ts src/subscription-config/catalog.test.ts --maxWorkers=2` | 退出 0，3 文件／54 项通过 |
| Flutter 目录执行 `flutter test --no-pub --dart-define=APP_ENV=test test/subscription_display_test.dart test/subscription_restore_ui_test.dart` | 最终退出 0，59 项通过 |
| Flutter 目录执行 `flutter analyze --no-pub lib/features/subscription/subscription_display_config.dart test/subscription_display_test.dart` | 退出 0，No issues found |
| `pnpm type-check` | 退出 0，7 项任务成功；Admin／Workers 类型检查实际执行，其余 5 项命中缓存 |
| `pnpm lint` | 退出 0，依赖方向通过 |
| `dart format --output=none --set-exit-if-changed`（本轮两个 Dart 文件） | 退出 0，无格式变化 |
| 文档相对路径检查／`git diff --check` | 4 份文档的 43 个相对链接可解析；差异检查通过 |

Flutter 首次运行有 1 个新增用例失败：测试夹具的原始 List 在 addAll 时丢失泛型，与实际 Map 列表的运行时类型不匹配，业务断言尚未执行；补齐测试列表类型后用相同命令重跑，59 项全部通过。没有放宽断言或跳过测试。

Code Review 自查覆盖计数口径、直接请求绕过、存量数据保留、默认项／顺序、幂等失败、公开读取兜底与 iOS／Android 边界，未发现本增量阻断项。相关规则已同步至服务端合同、Admin 文档与 Flutter 流程；原始 PRD 和原型保持原样。

本轮未运行真实浏览器登录交互、远程 API、真机交易、新 iOS／Android 构建或完整旧包兼容矩阵；本地用例不替代这些验收。未执行 Git commit／push、远程数据库迁移或 dev／prod 发布。

<a id="weekly-trial-admission-preparation"></a>

## 2026-10-15 周试用商品准入核查与客户端注册准备

本地来源为 `codex/dev-1.0.6@a522668` 加本轮未提交改动。按用户授权，先核查 dev，再准备 `cardx.week → weekly.trial` 接入；没有把目录可读、客户端注册或本地测试写成已可购买。

### dev 只读核查

- 17:00 SSH 回读：current 指向 `branch-dev-e53f75c30ffc-20261015163152`，manifest／watcher last-seen／last-deployed 均为 `e53f75c30ffc3004e4e9d7b7436f862fccd1ccca`，失败标记不存在；API／DB healthy、Web running、migrate exited/0。此次只是回读既有 watcher 发布结果，未手工重发，也未逐字节核对全部运行产物。
- PostgreSQL 查询显式使用只读事务和只读会话，确认独立 toccards_test／PostgreSQL 18.6，ledger 15 项、最新 0014。billing_product 仍为原 6 条 App Store 映射，weekly.trial、yearly.pro 均无映射；没有读取用户订单、购买明细或执行写库。
- 实际 API 容器的 APPLE_IAP_PRODUCT_IDS 仍为 cardx.week、cardx.year、cardx.lifetime，SUBSCRIPTION_DISPLAY_PRODUCT_IDS 未设置。shared/.env 权限 600；17:16 回读 release 未变，环境文件 SHA-256 仍为 19496cce4b00b2bbfabb7af8330b7075ba86c23a86d83ac3c8d4b2ccb3d0048f。凭据只在服务器原有环境内使用，没有输出私钥、Issuer、Key 或 JWT。
- 从实际 API 容器以当前源码 createAppleCatalogLoader 做只读诊断，App／组／订阅／优惠／Lifetime 共 9 次 GET 全部 200；未修改 Apple 商品。App 6790245922、Bundle com.kando.kandoApp.beta、组 22251901。cardx.week 与 weekly.trial 均为 ONE_WEEK、等级 2；后者有 175 个地区的 FREE_TRIAL／THREE_DAYS／1 期，起始 2026-10-12、无结束日期，当前 validateCatalogReferences 返回空问题列表。yearly.pro 当前为 ONE_YEAR／等级 4。返回商品状态仍为 MISSING_METADATA；未以真实 StoreKit 查询当前账户资格、价格或可购买性。
- 当前 Page 草稿 id 为 01M4ZAZ65YY55VJNH8XTM73AQ3、revision=2、不生效；三张卡片为 cardx.week（关联 weekly.trial）、yearly.pro、cardx.lifetime。该年商品与既定周试用接入范围不同，本轮保留用户选择，未替换为 cardx.year、注册额外商品或启用草稿。

按当前运行配置、数据库与源码准入条件逐项核对：

| 草稿涉及商品 | 购买白名单 | active Premium 映射 | 展示准入名单 |
| --- | --- | --- | --- |
| cardx.week | 已有 | 已有，plan_id=weekly | 未配置 |
| weekly.trial | 缺少 | 缺少 | 未配置 |
| yearly.pro | 缺少 | 缺少 | 未配置 |
| cardx.lifetime | 已有 | 已有，plan_id=lifetime | 未配置 |

局域网 HTTP 独立回读：health 200／status=ok；Page／Modal 均为 200、success=true、data=null，且 no-store。该结果确认没有生效配置，不表示新商品购买已验收。

### 本地准备及验证

- test.json 增加长期注册 weekly_trial → weekly.trial，product_type=subscription、is_trial_product=true；保留原三个商品。使用既有注册能力，不扩展展示卡片、不改 production 配置、不增加接口或 migration。新增回归读取实际 test 构建文件，验证四个长期支持商品、独立 plan_id、试用身份、三卡兜底顺序及 Yearly 默认项。
- Flutter 目录执行 `flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart test/subscription_restore_ui_test.dart test/subscription_singular_events_test.dart`，退出 0，68 项通过；现有 Android 隔离与原收入事件回归包含在内，不代表新增收入映射已完成。
- `flutter analyze --no-pub test/subscription_display_test.dart` 退出 0，No issues found。未修改服务端代码，因此未重复执行服务端全量测试。
- 当前 Singular 仅按 weekly／yearly／lifetime 映射事件；本轮没有猜测新 test 事件名称或借用原 weekly 档位。新商品收入命名仍按 PRD 10.7 等待确认。

待明确：yearly.pro 是否一并接入；weekly.trial 的 dev 收入事件名称。确认后再完成对应收入映射、dev 白名单／权益映射／展示准入和测试配置启用。旧包新增商品支持、Mac 签名测试包与真机 Sandbox 购买／恢复仍待验；本轮没有远端配置或业务数据写入、Git commit／push、iOS／Android 构建、App 发布或 prod 操作。

<a id="dev-subscription-product-onboarding"></a>

## 2026-10-15 周试用与新年订阅的 dev 接入

用户明确将 yearly.pro 纳入本轮，并授权生成 weekly.trial 的 dev 收入事件名称。按既有 test 后缀约定采用 card_weekly_trialtest；yearly.pro 沿用年订阅事件 yearly_cardtest，以实际 Product ID 区分商品。前一节待确认事项已由本次授权解除；旧包新增商品支持和真机验收边界继续保留。

### 本地实现与验证

- 来源为 codex/dev-1.0.6@a522668 加本轮未提交改动；test.json 长期支持集合追加 weekly_trial → weekly.trial（试用商品）和 yearly_pro → yearly.pro（普通年订阅），原三商品保持。两个新 plan_id 独立且不占用 weekly／yearly。Page／Modal 兜底仍为原三卡、原顺序和 Yearly 默认项；正式配置仍遵守最多三张展示卡片。
- Singular 的两个新 dev 映射按实际成交 Product ID 分支，生产未注册这两个新 ID，原三档事件不变。Firebase／Singular 共用收入记录反序列化补入两个 plan_id，避免 SDK 发送失败后新档位记录在重启时被丢弃；交易 JWS 金额、零值、币种、去重和 Restore 不计新收入保持原规则。
- Flutter 目录执行 `flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart test/subscription_restore_ui_test.dart test/subscription_singular_events_test.dart test/subscription_singular_revenue_test.dart test/subscription_revenue_reporter_test.dart test/subscription_analytics_test.dart`，退出 0，101 项通过。新增用例覆盖实际商品 ID 选事件、dev／prod 隔离、零元试用、两个新档位的持久化与重启重试、重复回调只上报一次、Restore 不新增收入以及原商品／Android 行为。
- `flutter analyze --no-pub` 针对 subscription_singular_events.dart、subscription_revenue_reporter.dart 及四个受影响测试文件，退出 0，No issues found。根 `pnpm lint`、`pnpm type-check` 均退出 0；类型任务 7 项成功，其中 5 项命中缓存、Admin／Workers 实际执行。六个 Dart 文件格式检查及 `git diff --check` 通过。本轮注册、事件映射及重试队列修改的 Code Review 自查通过；联查发现的新 SKU 订阅切换限制单列于下文，不将其记为已支持。无原生工程、API 协议、schema 或 migration 源码变化；未重复运行服务端全量或完整旧包兼容矩阵。

### 17:50–17:51 dev 数据与配置落地

- 17:30 回读并在 17:43 用当前服务端实现再次核查：current／manifest 仍为 branch-dev-e53f75c30ffc-20261015163152；PostgreSQL 会话明确 read-only=on，Apple 目录 9 次 GET 均为 200，草稿结构与商品关系校验通过。两个新商品的三项准入当时均未满足。
- 变更时持有 watcher/watch.lock 与 shared/deploy.lock；先确认目标为独立 toccards_test、development／com.kando.kandoApp.beta，环境文件和 API 运行配置一致、当前镜像 tag 没有漂移。未改 watcher 分支、计划或状态文件。
- 私有环境逐字节备份至 `/home/user/apps/toccards-test/shared/.env.before-product-onboarding-20261015T095058Z`，权限 600。目标 billing_product 表另以 pg_dump custom／data-only 备份至 `/home/user/apps/toccards-test/backups/billing-product-before-onboarding-20261015T095058Z.dump`，1417 字节、SHA-256 b492be719a55e48e804d2c5b888ef2c94a392c5ac12f33c5bedbf5c2af1ae260；pg_restore --list 成功确认 TABLE DATA public billing_product。另保留同名前缀 JSON 原记录快照。此为目标表定向备份，不是全库备份，未做恢复演练。
- 在显式事务和表锁下确认备份后的原记录未变，再 INSERT 两条 App Store 商品映射：weekly.trial／weekly_trial 与 yearly.pro／yearly_pro；两者均为 subscription、active=1、entitlement_id=performance_pro。原六条记录逐字段保持，表记录数变为八条。没有改订单、已有购买权益或迁移 ledger。
- 仅把 APPLE_IAP_PRODUCT_IDS 扩为 cardx.week,cardx.year,cardx.lifetime,weekly.trial,yearly.pro，并新增相同集合的 SUBSCRIPTION_DISPLAY_PRODUCT_IDS。候选 Compose 解析与原配置全量比较，仅 API 的这两项环境值变化，其他环境及服务定义不变。原凭据保留、权限／属主／组保留，原子替换 shared/.env；文件 SHA-256 从 19496cce4b00b2bbfabb7af8330b7075ba86c23a86d83ac3c8d4b2ccb3d0048f 变为 aa18acda180ef63978529f52f36bd03a10434d36f344308f9444db45d7963346。
- 使用现有两份 Compose 文件执行仅 api 的 `up -d --no-deps --no-build --pull never api`，API 恢复 healthy。镜像 ID 与原值相同，运行 /app/server.mjs 的 SHA-256 仍为 6cc72299a50fbf77d8af7d64d37b5eb60ac8e4ff243a3de667133beed7d2b7f7；DB／Web／migrate 容器 ID 未变，未 build／pull／migrate 或发布新 API／Admin 产物。锁在操作结束后释放。失败预案可恢复原环境并按原镜像重载，本轮未触发；不自动删除已经新增的商品映射以免破坏后续购买引用。

### 独立回读与待验边界

- 17:53 从新 API 容器再次运行当前目录／productAdmission／配置校验实现，使用实际 PostgreSQL 只读连接，Apple 9 次 GET 均为 200。原三个商品与 weekly.trial／yearly.pro 五项均 admitted=true、reasons=[]；草稿实际引用的四个购买商品均通过准入，catalogIssues=[]。本轮未纳入的 cardx.month 仍未准入。此项是容器内实际函数与真实数据库验证，不冒充已通过登录态的 Admin HTTP 请求。
- 17:59 独立 SSH 回读：环境哈希及 600 权限正确；release／watcher last-seen／last-deployed 仍为 e53f75c，failed-sha／failed-at 均不存在。API／DB healthy、Web running、migrate exited/0；ledger 仍为 15 项、最新 0014，billing_product 八条，生效配置数 0，原 Page 草稿 revision 仍为 2。局域网 health、Page／Modal 读取均为 200，两个展示接口仍 success=true、data=null。
- 使用已有 Chrome 后台标签页刷新商品目录时，页面转至登录界面，当前没有可用 Admin 登录态；未填写或猜测后台密码，未通过 SQL 绕过配置启用流程。原草稿仍不生效，待重新登录后继续页面提示和启用验收。浏览器中旧警告的消失尚未取得登录态 UI 证据，不用后端函数检查代替该验收。
- 联查当前回调源码：独立 Cloudflare relay 只转发签名原文，没有另一份 Product ID 白名单；Linux 的普通 SUBSCRIBED／DID_RENEW 建单复用配置和权益映射。但 apple-notification-routes.ts 的 PLAN_CHANGE_PRODUCT_IDS 仍仅包含既有周／年商品，DID_CHANGE_RENEWAL_PREF 的目标识别和升级补单分支尚未扩展到 weekly.trial／yearly.pro。本轮未改动该服务端生命周期分支，不能把准入通过视为新 SKU 升级／降级通知支持完成；完整订阅切换验收前须补齐对应实现与回归。
- Apple 商品目录仍显示 MISSING_METADATA，真实 StoreKit 地区价格、资格、购买／恢复和 Singular／Firebase 平台实际接收未验。当前为 Windows 环境，尚未构建新的 Mac 签名测试包或做真机验证；本地代码尚未 Git commit／push。未操作 prod、营销站、Apple 商品设置或发布 Flutter App。


<a id="subscription-dynamic-admission"></a>

## 2026-10-16 动态商品准入（本地实现与验证）

### 需求与定位

基线为干净的 codex/dev-1.0.6@67387fc，以下验证结果在提交前的增量工作区取得。用户确认 weekly.trial／yearly.pro 已在上一轮 dev 接入后恢复；当前未准入对象为 cardx.month，并明确采用“超级管理员逐 SKU 审批”，要求区分 dev/prod。原提示来自购买环境名单、展示审批名单和 active billing_product 三重条件，缺少后台接入流程；客户端还只消费构建时注册集合，通知升降级分支也有固定商品范围。此项按用户确认的功能迭代补齐准入能力，不将原先的审批拦截简单删除。

### 实现与审查

- 新增超级管理员审批 API，重新校验 Apple 目录，核对 expected_scope、Premium 类型、收入事件和旧包限制确认；使用现有 request_id 与结果核对，审批与商品映射同事务提交。保留既有兼容映射，冲突显式失败。
- PostgreSQL app_config 按 APP_ENVIRONMENT:APPLE_IAP_BUNDLE_ID 保存动态记录；复用现有 billing_product、mutation_lock 和订阅 mutation 表，没有新 schema／migration。原环境名单保留；Fresh Purchase、Restore、Premium／生命周期、通知、校正及 Admin 账单读取当前 scope 的动态并集。
- 同库同名动态 Product ID 跨 scope 审批会令未带 Bundle 的历史账单映射产生歧义。审查新增回归修复前得到 200（期望 409），修复后返回 PRODUCT_SCOPE_CONFLICT；同一商品锁覆盖检查及写入，真实 PostgreSQL 两连接并发也只允许一个 scope 成功。
- Flutter 的注册表读取／缓存按 API、环境及实际 Bundle 隔离；启动、前台权益同步、未知展示 SKU 和 Restore 可更新长期集合，追加到现有购买客户端而不重启监听。页面移除不撤历史恢复支持。收入事件随交易持久化，重启重试保留原映射及去重。
- Code Review 已完成变更及直接调用链自审，处理了损坏的审批编辑快照、审批弹窗遮挡 unknown 结果核对、销毁后的迟到响应、前台长期集合刷新及同库跨 scope 重复商品问题；最后复验后未发现本次范围内的阻断项。没有声称第三方独立审查或远端验收。

### 实际验证

环境：Windows／Node 22.20.0、本地 Flutter 工具链及隔离的 PostgreSQL 18.6-alpine 测试容器。新增审批回归先运行得到 4 项失败（缺少审批路径、返回 404），实现后通过；共享 scope 拒绝回归也先失败后通过。Apple 目录、JWS 与 App Attest 在自动化测试中使用显式注入响应／验证器，不冒充真实签名交易。

| 检查 | 实际结果与范围 |
| --- | --- |
| Workers 受影响测试 | 41 个文件的唯一用例去重共 451 项通过。39 文件／393 项分独立进程退出 0；动态购买／Restore／升级／scope 合同最终 5 项退出 0；扫描全部 53 项按清单分组退出 0。最终另运行订阅配置与动态权益 2 文件／35 项退出 0，其中已有 30 项不重复计数。覆盖 entitlements、subscription-config、Admin billing、scan、portfolio、data-source。 |
| Admin | pnpm --filter @kando/admin-web test：63 项通过，退出 0，含审批恢复快照；不是登录态浏览器实机验收。 |
| Flutter | 根 Melos 对 kando_app 执行 16 个订阅／当前权益／启动门禁相关测试文件，165 项通过，退出 0；包含真实 SubscriptionController 的注册追加和销毁后迟到响应、动态收入重启去重。 |
| 共享 Dart 包 | 根 Melos 对 subscription_core 执行测试，12 项通过、退出 0，包含追加计划后保持购买监听和拒绝历史映射替换。 |
| 静态与依赖 | pnpm lint、pnpm type-check、根 Melos 两包 analyze（最终带 --no-pub）均退出 0；未升级依赖，锁文件无改动。 |
| 真 PostgreSQL | test:subscription-config:postgres 在独立 loopback 空测试库执行 8 个子场景（TAP 含外层共 9 项），全部退出 0。验证真实锁等待、幂等、并发生效／审批、同库跨 scope 商品竞争、原子回滚；临时容器及其匿名卷已移除。没有接入既有业务数据库。 |
| 构建 | 最终 deploy:dry-run:dev 与 deploy:dry-run:prod 均退出 0，包括对应 Admin 构建、Linux 完整 bundle 的 3 项测试及 Cloudflare 打包。dev 只生成本地 tar.gz，prod 仅 dry-run；没有 SSH／上传／发布。 |
| 旧版源码合同 | pnpm test:app-compatibility 退出 0；当前 API 8 项，固定 1.0.4+161、1.0.5+163 各 24 项。覆盖及限制集中见 [AI 执行版](../03-data-api/app-backward-compatibility-ai-guide.md#2026-10-16-动态商品准入的兼容补证)。 |

批量运行限制必须保留：两次大批量 Workers 命令以及单独扫描整文件命令出现 Windows 进程异常退出 3221226505，未记为通过。对同一 HEAD 的独立源码快照运行扫描文件得到 41 通过／12 失败，失败为 PGlite 初始化的 Array buffer allocation failed，证明基线也存在单进程资源限制；没有据此断言当前异常退出的完整底层根因。随后用 vitest list 枚举 53 个唯一测试名，按 8／8／8／8／8／8／5 分进程全部执行，并核对每组通过数；分组之外的过滤项由其他组覆盖，没有删测试或放宽断言。原始输出保留在忽略的 apps/workers-api/.wrangler/subscription-admission-* 与 subscription-scan-* 文件中，不纳入 docs 原始日志。

上述扫描测试异常的后续定位与修复见[关闭后引擎引用保留补证](#pglite-closed-engine-retention)，原阶段失败及分组结果仍按历史证据保留。

### 交付边界与下一步使用

上述实现与验证阶段未执行 Git commit／push、远程业务数据写入、dev/prod 部署或新 App 签名打包。没有实际在 dev 审批 cardx.month；当前线上状态仍以之前已验收记录为准。发布本次 API＋Admin 并安装含动态注册能力的新测试 App 后，超级管理员在 dev 选择 cardx.month，点击“审核商品准入”，填写经确认的 dev 收入事件名、核对环境和旧包限制，再保存／启用配置。prod 必须使用自己的 App／目录配置并独立审批，不能直接复用 dev 批准状态。

1.0.4／1.0.5 原有商品和 V1 仍保留，但它们无法恢复包内未知的新 SKU；相关源码结论与待验项见 AI 执行版。真实 Apple 可售／资格／购买／Restore、旧签名包／真机、iOS 签名与 App Attest entitlement、平台实际收入接收、远端 CI 均未执行，不能记为通过。没有修改 iOS／Android 原生工程；Android 继续不消费 Apple 售卖配置。生产首次接入仍需核对既有 0014 等前置条件；“本次无新迁移”不代表可以跳过已有迁移检查。回退应保留商品与审批数据；新 SKU 已售卖后，旧服务代码不读动态准入，回退前须安排持续的购买／恢复支持。


<a id="pglite-closed-engine-retention"></a>

## 2026-10-16 扫描测试进程退出与 PGlite 内存保留

本轮从干净的 codex/dev-1.0.6@3c7f9e5 排查上条记录中的两个本地异常：当前扫描测试进程退出 3221226505，以及 67387fc 基线扫描测试在 initdb 的 HEAPU8.slice 分配处报 Array buffer allocation failed。原异常记录保留；以下是新的定位与修复证据，不把历史失败改写为通过。

### 根因与边界

扫描测试每个 fixture 都对 PGliteDatabase.prepare 安装 spy，用于 SQL 次数／并行行为断言。安装的 @vitest/spy 4.1.9 使用强引用集合保留注册的 mock；spy 的恢复闭包、调用上下文或实现可继续引用数据库包装对象。原包装层 close() 仅调用底层 PGlite.close()，没有解除 wrapper.client，因此已关闭引擎及其 WASM／内存文件系统仍可达。扫描文件连续创建多个数据库时，该保留跨用例累积；失败堆栈位于后续 PostgreSQL 初始化的内存分配步骤。

在同一 Windows／Node 22.20.0／PGlite 0.5.7 环境，独立进程连续创建、查询并关闭 8 个实例，用 WeakRef 和显式 GC 观测回收性，结果如下。数值是该小实验的本地测量，不是线上 API 内存或通用容量结论；普通扫描测试没有增加 GC 或内存参数。

| 对照模式 | 第 8 轮仍可达引擎 | external MiB | RSS MiB |
| --- | ---: | ---: | ---: |
| 无 spy | 1 | 236 | 322 |
| 原包装层＋spy | 8 | 1872 | 1778 |
| 原包装层＋spy，调用 restoreAllMocks | 8 | 1872 | 1775 |
| 关闭后手动解除 client 的诊断对照 | 1 | 236 | 363 |
| 修复后的包装层＋spy | 1 | 236 | 362 |

该实验中每实例 WASM 线性内存约 189 MiB；外部内存还包含内存文件系统等数据。恢复 spy 本身不能解决当前保留链。PGlite 可能保留最新模块，关键回归是更早的已关闭引擎不随 fixture 数量持续累积。

3221226505 对应 0xC0000409，是 Windows 快速失败退出通道；仅凭退出码不能断言具体原生子码或栈。本轮未取得历史进程的原生崩溃栈，也未从应用事件记录取得进一步证据。因此，内存引用保留及分配失败已被对照实验确认；当前进程退出的更细原生触发点仍不作无证据推断。

### 修复与回归设计

仅修改测试辅助层 [PGliteDatabase](../../../../apps/workers-api/src/test-support/pglite-database.ts)：close() 先解除包装对象对底层引擎的持有，再等待原关闭操作；关闭错误继续传播，已关闭对象的数据库操作明确失败。生产 PostgresDatabase、API、扫描业务、schema、依赖版本、Vitest worker／堆上限及扫描断言均未修改。

在[已有辅助层测试](../../../../apps/workers-api/src/test-support/pglite-database.test.ts)增加独立 Node 子进程回归，保留 4 个已关闭包装对象，通过公共 PGlite.create 观测它们拥有的引擎，并验证更早的 3 个引擎可被回收。修复前该断言稳定得到 3（期望 0）、退出 1；修复后为 0。--expose-gc 只用于此观测子进程，默认测试命令和实际扫描运行不靠强制 GC 维持通过。

### 已取得的验证

- pnpm --filter @kando/workers-api test src/test-support/pglite-database.test.ts --maxWorkers=1：3 项通过，退出 0。
- 当前分支原扫描文件 --maxWorkers=1 --reporter=verbose：53 项全部通过、无跳过，退出 0，105.90 秒；未使用 testNamePattern 或分组。
- 旧 67387fc 基线副本：保留原扫描测试字节和原业务源码，只替换本轮 PGliteDatabase 辅助文件，53 项全部通过、无跳过，退出 0，50.72 秒。此前该基线同文件为 41 通过／12 内存分配失败；此结果应标为“基线＋测试辅助层修复”，不是未经修改的旧提交突然通过。
- pnpm lint、pnpm type-check：退出 0。
- pnpm --filter @kando/workers-api test --maxWorkers=2 --reporter=verbose：标准完整 Workers 范围 90 文件／854 项全部通过，无失败、无跳过，退出 0，161.17 秒；未按文件或用例拆分，没有修改 worker／堆上限或配置全局 GC。该运行覆盖共享 PGlite 辅助层的其他调用方。
- Code Review：完成变更及调用方自审，检查关闭前后的所有权、关闭失败继续传播、关闭后显式失败、正常查询／batch 语义，以及回归对真实底层引擎的观测范围；最后验证后无阻断项。没有声称第三方独立审查。
- 未运行 Linux／macOS／远端 CI；本机结果仅证明 Windows 11／Node 22.20.0 下的本地回归。生产适配器与 App 代码未变，本轮没有部署或设备交易验收。

详细对照输出位于忽略目录 apps/workers-api/.wrangler/pglite-lifetime/；没有把原始日志或基线源码快照加入 docs。上述定位与验证阶段未执行远端部署、数据库业务操作、依赖升级或 Git commit／push。

<a id="subscription-dynamic-dev-release"></a>

## 2026-10-16 动态商品准入 Git 交付与 Linux dev 发布

### 来源与部署

- 用户明确授权提交推送并重新部署 dev。原合并提交 06f420a072463454d8eda21c9fd09bf18768eda5 已推送 github/dev，本地与远端 SHA 核对一致，工作区干净；源功能分支 e6f986f 的代码／配置／测试文件在合并中保持，文档冲突按历史检查点解决。
- 登录目标为 kd201（192.168.50.201，系统 hostname=srs-node-test1）。独立回读发现既有 watcher 已取得该提交并持有 watch.lock，因此接续等待该轮自动发布，没有并发启动第二次部署、修改 watcher 配置或手工覆盖状态。
- watcher 采用 Node 22.22.1／pnpm 11.9.0，远端 11 个 Vitest 文件／112 项通过，包含完整扫描文件；后续既有脚本检查与 Linux API／Admin 构建完成。实际发布预检确认 toccards_test／PostgreSQL 18／识别服务可达，pendingMigrations=[]；测试夹具输出的 pending 列表不作为实际迁移结果。
- 发布 release 为 branch-dev-06f420a07246-20261016105341。10:59 已独立回读到新 current；11:04–11:22 进一步核对 manifest、运行文件和来源检出。manifest source=kd201-branch-watcher，sha 为完整 06f420a；watcher 来源检出 clean，安装的 watcher 脚本与该提交版本一致。

### 数据库、备份与配置保留

- 只读 PostgreSQL 会话确认 default_transaction_read_only=on、数据库 toccards_test、版本 18.6；ledger 仍为 15 项，最新 0014_subscription_display_config.sql。迁移容器 exited/0，日志逐项跳过已有 0000–0014，没有执行新 migration。原卷 toccards-linux-test_postgres-data 保留，挂载点仍为 /var/lib/postgresql/data。
- 发布前备份：toccards-test-20261016-105343-before-branch-dev-06f420a07246-20261016105341.dump，1,135,415,530 字节；独立 pg_restore --list 退出 0，列出 336 项，临时 .tmp 文件不存在。未执行恢复演练。
- shared/.env 权限仍为 600，完整 SHA-256 仍为 aa18acda180ef63978529f52f36bd03a10434d36f344308f9444db45d7963346，与发布前一致；API、DB、Web 容器环境数组的排序哈希也与发布前分别一致。没有更换目录／验单 Key、插件 Key、数据库密码或代理设置；记录仅保存哈希与存在性，不保存凭据明文。
- API／DB healthy，Web running，migrate exited/0；API 无宿主端口绑定。既有 billing_product 8 条、展示配置 1 条、非空生效指针 0 条、动态商品审批 scope 记录 0 条。本轮未审批 cardx.month、未启用 Page／Modal、未进行用户订单或权益业务写操作。

### 产物与 HTTP 独立核对

- 本地从同一干净提交执行 build:dev，Linux bundle 的 3 项检查及 Admin development 构建退出 0。API 运行 /app/server.mjs、Linux release 文件与本地批准构建三者 SHA-256 均为 4cb4348eabed004a2094e61e070c4413f27a22375e934635353a2d8e36c95bf0。Web 运行代理脚本与 release 文件匹配。
- Admin 容器内 11 个文件与 Linux release 原始字节全部匹配；HTTP 的 10 个 JS／CSS 文件与本地同提交构建原始字节一致。HTTP HTML 与 Linux release 一致，跨 Windows 构建仅有 12 个 CR 字符差异：HTTP 为 1048 字节，本地为 1060 字节，去 CR 后 SHA-256 同为 dea8227c2992991902bc7d4991c077bc9cde81f01fdf5e24357e8425d2ff11bf。不将该结果描述为跨平台 HTML 原始字节一致。
- 10 项 HTTP 检查通过：health／Admin 首页 200；未认证 auth/me、Admin 商品目录和审批 POST 均 401；新增长期注册表 iOS 200、scope=development:com.kando.kandoApp.beta、products=[]、no-store；Google 注册表为空，非法平台 422；Page／Modal 均 200 且 data=null。
- 在 API 容器实际环境中，用本提交目录实现执行只读 Apple 目录探测，9 次 GET 均为 200，读取 beta App 6790245922／组 22251901 的 5 个订阅及 cardx.lifetime。cardx.month 可见，但仍未审批；目录商品仍显示 MISSING_METADATA，不据目录读取推断 StoreKit 可售、资格或购买成功。
- 完成时 current／manifest／last-deployed 均指向 06f420a，失败标记不存在，watcher 与 deploy 锁均空闲。后续文档补证提交可以只推进 last-seen；运行源码 SHA 与 Git 文档提交须分别报告。

### 验收边界

本轮完成的是 dev 的 API／Admin 重新部署及上述运行核对；未发布 prod、营销站或 Flutter 签名包。真实 Admin 登录态审批／启用、StoreKit 价格／资格／购买／Restore、收入平台实际接收和正式旧包／真机仍待验。1.0.4／1.0.5 恢复新 SKU 的限制不因本次服务端发布而消失，见 [兼容 AI 执行版](../03-data-api/app-backward-compatibility-ai-guide.md)。本轮没有回查 GitHub 托管 CI，不将服务器 watcher 的测试结果写成 GitHub CI 已通过。

精简运行回读、批准构建哈希和 HTTP 结果保留在忽略目录 apps/workers-api/.wrangler/dev-deploy-06f420a-20261016/；原始日志、基线副本和任何凭据均不加入 docs。

## 2026-10-16：iOS 测试环境内部安装包 1.0.5 (167)

- 构建输入：从构建前干净且与远端一致的 `dev@d1ec5928f7722597288b2871c249624edc9491e8` 构建。源码版本为 `1.0.5+166`，执行 `./tool/release_ios.sh --env test --pgy`；脚本完整退出 0，并在全部制品门禁通过后将 `apps/flutter-app/pubspec.yaml` 同步为 `1.0.5+167`。这是首个包含动态订阅商品注册能力的签名测试包，包含 `weekly.trial`、`yearly.pro`，注册表按 API、环境与 Bundle ID 隔离。
- 环境与依赖：`config/test.json` 校验通过，dev health `http://192.168.50.201:8080/api/v1/health` 返回 `status=ok`。依赖解析没有改变锁定依赖；根 `pubspec.lock` 与 iOS `Podfile.lock` 的 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021` 和 `d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，与 166 构建一致，没有依赖更新。
- 本地验证：`flutter analyze` 通过；共享 `subscription-core` 12 项通过，App 发布配置、环境及订阅相关 8 个定向测试文件 116 项通过。构建后补跑当前 16 个订阅／权益／启动门禁测试文件，165 项全部通过。这些范围不包含此前失败的 4 项 Golden；Profile 升级横幅、订阅成功 300ms 帧、订阅配置底部页和订阅成功页的像素差异本轮没有重录或关闭，仍是明确待验项。
- 构建结果：依赖解析、Xcode Archive、IPA 导出、签名校验、dSYM 覆盖与保存流程均退出 0。保存制品的独立只读审计确认 `com.kando.kandoApp.beta / 1.0.5 (167)`、最低 iOS 16、Apple Development 签名、`get-task-allow=true`、App Attest `development`，包含测试 Firebase `card-ai---test` 与 dev API `http://192.168.50.201:8080/api/v1`，未命中生产 API。描述文件包含 6 台设备。IPA 的 42 个唯一 Mach-O UUID 均有匹配 dSYM，缺失和额外 UUID 均为 0；压缩包内 `cupertino_http` 与 `objective_c` 各有一份 UUID 相同的重复 dSYM，不影响覆盖或符号化。
- 保存与保留：IPA 为 39,946,633 字节，SHA-256 `9394ee5ff84c1dade39cf294cb575b6be588ae1823870b0bc5451b29c2014277`；`dSYMs.zip` 为 61,233,095 字节，SHA-256 `38bc3b024815b316118f66b690c07b6b4b9fa77105be9176f522cdaca8bce84a`。两份 ZIP 完整性检查通过，保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-167/`。新版本完整保存后，旧 164 版移入废纸篓；当前保留 165、166、167，正式包及 Xcode Archives 不受影响。
- 边界：本次没有安装设备、上传蒲公英／TestFlight／App Store Connect、提交或推送 Git，也没有部署或修改服务端。4 项 Golden 差异仍未关闭；没有完成真实 Sandbox 购买、Restore、动态新 SKU、收入平台实际接收或真机端到端验收。
<a id="subscription-store-price-rounding"></a>

## 2026-10-16 StoreKit 价格浮点表示导致周卡被过滤

本次从 `codex/dev-1.0.6@e6f986f1` 的干净工作区定位并修复 Flutter 客户端问题。原 test 调试包在 iPhone 13 的完整订阅页与弹窗入口均缺少周卡关联试用；真机读取确认插件和原生 StoreKit 都返回 `cardx.week`，但插件 `rawPrice=3.9899999999999998`，原生 `price_decimal="3.99"`。锁定的 `in_app_purchase_storekit 0.4.11` 将 StoreKit Decimal 经 `NSDecimalNumber.doubleValue` 转为插件金额，原生只读桥接将同一 Decimal 转为字符串；Swift 最小复现显示两种路径落在相邻的 double 值。原 Dart 严格相等校验因此丢弃周卡，关联 `weekly.trial` 的资格虽为 eligible，也无法显示试用切换。这是修复前的真机与转换证据，未将另一路未返回的 `yearly.pro` 归因为同一问题。

修复仅限 iOS 商品事实与插件商品的金额比较：有限、非负价格最多允许 1 ULP 的二进制表示差异，零价还须确认原生十进制字符串确实为零；超过 1 ULP 的差异继续拒绝。Product ID、币种、格式化展示价、类型和周期的校验保留，购买前 `sameTerms` 的十进制金额与资格二次确认没有放宽。Flutter 的 Android 既有隔离路径、原生桥接、API、schema 和商品配置均未改。

验证：`flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart` 退出 0，25 项通过，覆盖真机观测价格、Page／Modal 的关联试用开关、真实差价拒绝、零价下溢拒绝及已有购买前金额变化二次确认；`flutter analyze --no-pub` 退出 0、无问题，`git diff --check` 退出 0。最初一次分析指出新增 `dart:typed_data` 导入多余，移除后重新分析通过。目标本机 Flutter 为 3.44.5，设备为 iPhone 13／iOS 26.6.2。更新后的 `1.0.5+163` test Debug 包通过 `flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json` 在同一设备构建、安装并启动。独立抓屏确认完整页与弹窗均显示 `US$3.99` 普通周卡；完整页下半部抓屏还可见试用开关开启、`START FREE TRIAL`、年订阅和终身商品。试用商品的续费文案为 `US$4.99/周`，与普通周卡当前价格不同，此为两个 StoreKit 商品的实测展示，需按业务预期核对，不属于本次浮点校验修复。弹窗试用开关位于当前抓屏视口以下，未单独看到其实际控件；年商品当前可见不能归因于本次金额修复。

真机调试日志还出现 Firebase Installations 与 Logging 请求超时；App 仍启动并显示订阅页，本轮未排查该独立网络问题。未执行真实购买、Restore、弹窗试用开关的独立真机视口检查、Android 真机或商店签名包验证；本次也未执行 Git push、服务端发布、远程数据库写入或 prod 操作。独立 Code Review 检查了浮点位序、零价、周卡与试用控制器路径、购买前 `sameTerms` 及文档；无阻断性问题。审查建议已收窄上述金额差异表述。

<a id="subscription-figma-ui"></a>

## 2026-10-16 订阅页面 Figma 视觉增量

通过 Figma 插件读取完整画板 `3465:8692`、内容节点 `3465:8694` 及同组两／三商品和试用状态。iOS 完整页与弹窗复用配置商品布局：试用开关位于卡片上方，价格和运营价格说明在右侧，折算周均价保持辅助信息；计费摘要、CTA 和条款固定在底部安全区，商品列表独立滚动。常规高度标题固定，紧凑视口标题随内容滚动，关闭／恢复入口始终固定。背景继续使用原视频，未添加全屏遮罩；选中商品的背景填充和面阴影按用户真机反馈移除，仍保留描边和单选标记。完全重复的价格说明已去重。Figma 中的金额和试用按钮文字仅作视觉示例，实际内容来自已校验的 StoreKit 商品及后台配置；购买前复核和 Android 原商品逻辑未改。代码和页面契约见[客户端订阅展示](../01-flows/subscription-display.md#订阅页面视觉增量)。

本地执行 `flutter test --no-pub --dart-define-from-file=config/test.json` 的订阅展示与恢复 UI 两文件，66 项通过；新增用例覆盖两商品、试用切换、带安全区的三商品页面／弹窗滚动、重复价格说明去重和 CTA 固定。更新现有 390×844 订阅弹窗 golden 后，单独复跑对应截图用例通过；`flutter analyze --no-pub` 无问题。iPhone 13 重新构建、安装 test Debug 包并热重载最终选中态；真机抓屏确认完整页首屏出现三档商品、真实价格、试用开关和底部按钮，未执行购买或 Restore。

`test/widget/auth_profile_test.dart` 全文件运行有 3 项旧截图失败，分别为未订阅 Profile banner 和订阅成功页的静态、动效 golden；本次只更新了订阅弹窗 golden，没有改这三个图像或其页面实现，也不将全文件记为通过。未运行 Android 真机、签名 IPA／App Attest、真实交易和弹窗入口的本轮独立真机抓屏；未 Git push、部署或改动远端配置。

## 2026-10-19 iOS 测试环境 Debug 安装包 1.0.5 (168)

- 构建输入：从构建前干净且与跟踪分支一致的 `codex/dev-1.0.6@325ad38068257e2cb15cead9f3b6b5fce094b614` 构建。源码声明版本为 `1.0.5+163`，但本机已保存 165、166、167，因此本次显式使用 `1.0.5 (168)`，制品完整保存后再将 `apps/flutter-app/pubspec.yaml` 同步为 `1.0.5+168`。本机工具链为 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1，与 GitHub iOS CI 的 Flutter 3.44.7／Xcode 16.4 不同。
- 环境与验证：`config/test.json` 发布配置校验通过，`http://192.168.50.201:8080/api/v1/health` 返回 `status=ok`；`flutter analyze` 通过。测试构建的 `DART_DEFINES` 回读为 `APP_ENV=test`、`APP_HTTP_TRANSPORT=native`、`FLUTTER_APP_FLAVOR=test`，API 环境与 Debug Overlay 两个测试文件共 6 项通过。根 `pubspec.lock` 与 iOS `Podfile.lock` 的 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，没有依赖锁更新。
- 构建与签名：现有 `release_ios.sh` 固定构建 Release，故本次先用 Flutter 的 `--debug --flavor=test` 生成 Debug archive。Flutter 自带的 debugging 导出把归档中原为 `development` 的 App Attest 重签为 `production`，该首个导出包被门禁拒绝且未保存。随后使用同一 Debug-test 配置直接生成 Xcode archive，显式保持 `APP_ATTEST_ENVIRONMENT=development`，并从归档内已签名 App 原样封装 IPA，不经过导出重签。最终 IPA 解包确认 `com.kando.kandoApp.beta / 1.0.5 (168)`、最低 iOS 16、Apple Development 签名、`get-task-allow=true`、App Attest `development`、测试 Firebase `card-ai---test`；`kernel_blob.bin`、`vm_snapshot_data` 和 `isolate_snapshot_data` 均存在，确认是 Flutter Debug JIT 制品而非 Development 签名的 Release 包。描述文件有效至 2027-09-07，包含 6 台设备。
- 符号边界：Debug archive 原生生成 38 个 dSYM；使用最终二进制经 `dsymutil` 补齐 `objective_c`、`cupertino_http`、`Flutter`、`App` 四个 UUID 后，最终 42 个 Mach-O UUID 与 42 个 dSYM UUID 集合一致，缺失／额外均为 0。`cupertino_http` 与 `App` 报告无调试符号，Flutter engine 因上游构建机对象路径不可用仅能生成现有二进制可恢复的符号；因此 42/42 表示 UUID 结构覆盖，不宣称这三个预编译 Debug 框架具备完整源码行级符号。App 自身 Runner 及其余 37 个框架 dSYM 由本次归档原生生成。
- 保存与边界：`Card AI Debug.ipa` 为 76,731,403 字节，SHA-256 `1aaa6a0925fe81aeda2780c07f61b380b196034f43ab538ae73cd7a235630bf3`；`dSYMs.zip` 为 23,118,505 字节，SHA-256 `e0c0a0277eef8542815feb8c1ed2761f3a8dcf67caa5d84ac7a4639415195058`。两份 ZIP 完整性检查通过，保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-168/`；完整保存后旧 165 版移入废纸篓，当前保留 166、167、168。Debug JIT 未做 Release tree shaking，包内同时保留未选环境的常量字符串；运行选择以 `APP_ENV=test` 和环境测试为证据。本次未安装设备、上传蒲公英／TestFlight／App Store Connect、提交或推送 Git，也未执行真实登录、扫描、购买、Restore、崩溃上报或真机启动验收。

## 2026-10-19 iOS 测试环境 Release 内部安装包 1.0.5 (169)

- 构建输入：从 `codex/dev-1.0.6@325ad38068257e2cb15cead9f3b6b5fce094b614` 的当前工作区重新构建；源码构建前版本为 `1.0.5+168`，本次使用 `1.0.5 (169)`，制品完整保存并校验后将 `apps/flutter-app/pubspec.yaml` 同步为 `1.0.5+169`。工具链为 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。
- 环境与依赖：`config/test.json` 校验通过，测试 API 为 `http://192.168.50.201:8080/api/v1`，Firebase 项目为 `card-ai---test`；`pubspec.lock` SHA-256 为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`，`ios/Podfile.lock` SHA-256 为 `d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，本次没有依赖锁更新。
- 构建与签名：使用 `flutter build ios --release --flavor=test --dart-define-from-file=config/test.json --build-name=1.0.5 --build-number=169 --no-codesign` 后，以 `Release-test` 配置创建 Xcode archive。最终 IPA 从归档内已签名 App 原样封装，未经过会改变 App Attest 的导出重签。解包确认 Bundle ID `com.kando.kandoApp.beta`、Apple Development 签名、`get-task-allow=true`、App Attest `development`，描述文件包含 6 台登记设备。
- 符号与完整性：IPA 为 39,926,111 字节，SHA-256 `c9bb165187d1eda72f33229defb05f8dd42d21dc91e68314475fcb3b153ad95e`；`dSYMs.zip` 为 61,217,810 字节，SHA-256 `59d39cf9505bd7d3bedceb1fafb50f42b5f22ab70ca86df613d33853b6502324`。IPA 与 dSYM ZIP 完整性检查通过，42/42 个 Mach-O UUID 有对应 dSYM，签名严格校验通过。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-169/`，当前测试包保留 167、168、169；旧 166 版在新版本完整保存后移入废纸篓。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、购买、Restore、崩溃上报或真机启动验收。

<a id="subscription-trial-selection-state"></a>

## 2026-10-19 试用开启后切换商品导致列表恢复

本次从 `codex/dev-1.0.6@d575ec87` 的干净基线修复 Flutter 订阅展示状态。原控制器把“当前选中商品”和“试用替换位置”作为同一状态处理：选择其他商品时会直接关闭 `trialOn`，商品卡又以当前选中项判断是否显示关联试用，购买前复核也会把普通商品错误纳入试用关系校验。因此，用户开启试用后选择年卡或终身商品，会同时关闭开关并把列表中的试用商品恢复为基础商品。

修复增加页面实例内的试用替换位置状态。开启试用时记录当时生效的关联位置；之后选择其他普通商品只更新选中项，开关和开启后形成的商品列表保持不变，再次选择该关联位置仍显示试用商品。只有用户主动关闭开关时才清除替换位置并恢复基础列表。购买普通商品不校验另一位置的试用资格；实际购买关联试用商品时仍执行原有资格和条款复核。多组有效试用关系仍只替换开启开关时选定的一组。API、后台配置、StoreKit 商品校验及 iOS／Android 原生代码均未修改。

修复前，控制器与页面点击两条新增回归均稳定复现，失败值为 `trialOn=false`、期望 `true`。首轮 Code Review 发现商品重载后的资格短暂为 `unknown` 时，换回关联位置可能遗留 `trialInvalid` 并无提示禁用购买；换选现在只清除既有失效标记，实际试用购买继续由提交前强制复核拦截失效资格。修复后，`flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 退出 0，两个文件共 69 项通过；覆盖试用列表保持、切回关联位置、主动关闭恢复基础列表、普通商品购买复核、多关联仅替换一组、资格异步刷新及普通商品购买打断资格刷新。`flutter analyze --no-pub` 退出 0、无问题，`git diff --check` 退出 0。返工后的 Code Review 检查状态生命周期、页面调用、资格刷新及购买前复核后无阻断项。

本轮未构建或安装新包，未执行真机交互、真实 Sandbox 购买、Restore、Android 真机、签名包、部署、远程配置或数据库操作，也未执行 Git commit／push。此前 1.0.5 (169) 包不包含本修复。

<a id="subscription-config-copy-layout"></a>

## 2026-10-19 订阅配置文案与商品布局修正

本次在上一节试用状态修复的同一未提交工作区继续调整 Flutter 订阅页。有效后台配置现在显式标记为远端来源：配置商品价格下方只显示当前实际 SKU 的 `price_note`，字段为空时不展示；不再叠加 StoreKit 推导的 `per year`、`every 7 days` 或 `one-time purchase`。远端配置无法取得，或其中没有任何可展示商品而切入客户端兜底时，原 StoreKit 周期文案继续保留。试用目标沿用自己的配置文案，StoreKit 主价格、固定交易摘要和购买前复核没有改变。

布局将试用开关到首张商品及相邻商品卡片间距统一为 20px，移除 Lifetime 额外顶距；带浮动角标的价格列下移 12px，避免角标遮挡本卡价格，20px 卡片间距使下一张角标与上一张商品之间仍保留 9px 净距。后台配置商品的角标选中颜色改为同帧更新，旧商品展示路径的既有选中动画保留。iOS 固定购买区的 Terms 下方间距统一改为 16px，包括底部安全区为 34px 的 iPhone 13 视口；CTA 继续固定在 Terms 上方，商品内容仍在独立滚动区。

验证：`flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 单独运行退出 0，共 72 项通过；覆盖远端文案完全替换、空值不回退、兜底周期保留、价格与角标不重叠、卡片间距 20px、角标与上一项保留 9px 净距、Footer 底部空白及角标背景／边框在切换首帧和 70ms 均无中间色。更新 `test/widget/goldens/rendered/subscription_config_sheet_390x844.png` 后，定向 golden 用例单独复跑通过；`flutter analyze --no-pub` 退出 0、无问题。首次并行运行三个 Flutter 命令时，订阅测试因共享 `build/native_assets` 临时文件竞争退出 1；改为单独运行后通过，不把首次运行记为业务测试通过。

本节后续记录的 1.0.5 (170) IPA 于 11:03 保存；20px 商品间距与 16px Footer 底距在 11:15 完成，因而该制品包含此前的订阅状态、配置文案及角标修正，但不包含这两项最终尺寸。最终尺寸修改后未重新构建或安装新包，也未执行 iPhone／Android 真机视觉与交互、真实 Sandbox 购买、Restore、部署、远程配置、数据库操作或 Git commit／push。

## 2026-10-19 iOS 测试环境 Release 内部安装包 1.0.5 (170)

- 构建输入：从 `codex/dev-1.0.6@d575ec872ae2dfdf71f8d46c5a0190e1da2b9c22` 加当前未提交的订阅状态、文案和布局工作区构建，必须标记为 dirty，不能写成纯提交制品。构建前版本为 `1.0.5+169`，本次使用 `1.0.5 (170)`；制品完整保存并校验后将 `apps/flutter-app/pubspec.yaml` 同步为 `1.0.5+170`。工具链为 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。
- 环境与依赖：`config/test.json` 校验通过，最终 App 的 Bundle ID 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1` 已嵌入，Firebase 项目为 `card-ai---test`。`pubspec.lock` 与 `ios/Podfile.lock` 的 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，本次没有依赖锁更新。
- 验证与构建：`flutter analyze --no-pub` 通过；测试环境订阅展示与恢复两个文件共 72 项通过，OAuth authorizer 与发布配置两个文件共 12 项通过。执行 `flutter clean` 后重新解析依赖并构建 Release-test 原生产物，再以 `Release-test` 配置创建 Xcode archive。最终 IPA 从归档内已签名 App 原样封装，未经过导出重签；解包确认 Apple Development 签名、`get-task-allow=true`、App Attest `development`，描述文件包含 6 台登记设备。Xcode 归档退出 0，保留第三方依赖弃用、`in_app_review` 隐私清单无处理规则等非阻断警告。
- 符号与完整性：`Card AI Test.ipa` 为 39,925,934 字节，SHA-256 `ad1009d209b9eba925ecfc45a642156834246589f596c3b59003c8051e35c46c`；`dSYMs.zip` 为 61,217,309 字节，SHA-256 `b2617a0aac76c05c7fce404df60d66c0dd01cd7b48c8da2b2a3cb28d42e24e4c`。两份 ZIP 完整性、IPA 深度严格签名以及归档 App 逐文件一致性检查通过；42/42 个 Mach-O UUID 有对应 dSYM。44 个 dSYM bundle 中 43 个通过 `dwarfdump --verify`，`App.framework.dSYM` 报告 171 个 Dart／Flutter DIE range 错误；UUID 覆盖完整，但不能声称全部 dSYM 深度校验通过。
- Google OAuth 边界：测试 Firebase plist 使用测试项目的 `490325688457...` Client ID，但最终 App `Info.plist`、URL Scheme 和 AOT 常量使用 `1030914046373...`。源码与测试明确要求使用后者作为 Workers 校验 token 的 iOS audience，因此这是当前有意的拆分，不是本次构建或签名阻断项；本次仍未做真机 Google 登录，不能把实际登录和回调记为通过。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-170/`；新版本完整保存后将旧 167 版移入废纸篓，当前保留 168、169、170。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、购买、Restore、崩溃上报或真机启动验收。

## 2026-10-19 iOS 测试环境 Release 内部安装包 1.0.5 (171)

- 构建输入：从 `codex/dev-1.0.6@d575ec872ae2dfdf71f8d46c5a0190e1da2b9c22` 加当前未提交的订阅工作区构建，必须标记为 dirty，不能写成纯提交制品；构建期间 `git diff HEAD --binary` 的 SHA-256 始终为 `8467c6a00667241b7bc20be61577ea71217d878dd3792a4cce068e6ba8cfe290`。相较 170，本包包含随后完成的 20px 商品间距和 16px Footer 底距。构建前版本为 `1.0.5+170`，本次使用 `1.0.5 (171)`；制品完整保存后将 `pubspec.yaml` 同步为 `1.0.5+171`。
- 环境与依赖：`config/test.json` 校验通过，最终 App 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1` 已嵌入，Firebase 项目为 `card-ai---test`。`pubspec.lock` 与 `ios/Podfile.lock` 的 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，没有依赖锁更新。
- 验证与构建：`flutter analyze --no-pub` 通过；订阅展示、恢复、OAuth authorizer 与发布配置四个测试文件共 84 项通过。执行 `flutter clean` 后重新解析依赖并构建 Release-test 原生产物，再创建 Xcode archive。最终 IPA 从归档内已签名 App 原样封装；Apple Development 签名、`get-task-allow=true`、App Attest `development`，描述文件包含 6 台登记设备。Xcode 归档退出 0，保留第三方依赖弃用、Swift 6 前置兼容和 `in_app_review` 隐私清单无处理规则等非阻断警告。
- 符号与完整性：`Card AI Test.ipa` 为 39,924,748 字节，SHA-256 `46d120b01dcb46888876f73f7c0a4032152332ed06905945f81fd585abe27477`；`dSYMs.zip` 为 61,217,698 字节，SHA-256 `c8f00f5e9c5d2ba50d2a5765f7a026e6d892120f8b86c8aca9110a6b6c8bff72`。两份 ZIP、IPA 深度严格签名以及 IPA App 与归档 373 个文件逐字节一致性检查通过；42/42 个 Mach-O UUID 有对应 dSYM。44 个 dSYM bundle 中 43 个通过 `dwarfdump --verify`，`App.framework.dSYM` 仍有 171 条 Dart／Flutter range 错误，不能声称全部 dSYM 深度校验通过。
- Google OAuth 边界：测试 Firebase plist 使用测试项目，但最终 App 使用源码要求的生产 Google OAuth audience，供 Workers 校验 token；相关测试通过，但本次未做真机 Google 登录和回调验收。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-171/`；新版本完整保存后将旧 168 版移入废纸篓，当前保留 169、170、171。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、购买、Restore、崩溃上报或真机启动验收。

## 2026-10-19 本地兜底每周价格修正与 iPhone 13 复测

从 `codex/dev-1.0.6@42f4d7e4` 的未提交订阅工作区继续定位，未把此前未提交改动视为纯提交构建。用户在 test 真机看到周试用 `US$4.99` 无 `then`、年卡 `US$0.96`、月卡 `US$3.00`；同时确认年卡保持现状，月卡按月价除以 4 并标准四舍五入。test 的 Page／Modal 配置接口均返回 `data:null`，设备使用本地兜底。首次同机 Debug 抓屏确认试用标题已由 `Premium` 变成 `3-Day Free`，但周期仍写 `every 7 days`，周价无 `then`；这将问题定位到 StoreKit 返回的 7 天周期没有被现有一周价格分支识别，而非试用资格未通过。年卡由 `US$49.99÷52` 得 `US$0.96`，保持不变；原月卡 `US$12.99×12÷52` 得 `US$3.00`。

修复在 iOS StoreKit 只读商品事实中将 7 天视为一周，月卡另给本地兜底提供 `月价÷4` 的本地化字段；Flutter 兜底周卡直接使用该 StoreKit 商品的正常周期金额，资格确认后加 `then`，月卡使用新字段。后台配置既有 `月价×12÷52` 周均参考口径、真实扣费金额和购买前复核均未改。`US$12.99÷4` 最终四舍五入为 `US$3.25`，图稿 `US$3.24` 不符合该规则。

`flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 退出 0，74 项通过，含 7 天周卡无派生周价、资格未知到可试用、月／年右侧金额及原生字段映射；`flutter analyze --no-pub` 退出 0。`flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json` 在 iPhone 13 上完成 Xcode 编译、安装和启动；构建后签名 App 的 App Attest entitlement 回读为 `development`。修复后同机抓屏可见周试用的 `then` 和 `per week`、月卡 `US$3.25 / per week`、年卡 `US$0.96 / per week`、`TRY FOR FREE` 和 `NO PAYMENT NOW`。test 环境已有的右侧悬浮调试入口遮住了周价末尾；完整 `US$4.99` 金额以同机修复前显示、StoreKit 原价路径和页面测试交叉核对。只读 Code Review 未发现阻断问题。未制作新 IPA、未执行真实购买／Restore、Android 真机、远程配置修改、服务端部署、Git commit／push 或商店发布。

<a id="subscription-price-visibility"></a>

## 2026-10-19 订阅商品价格展示方式增量（本地）

从 `codex/dev-1.0.6@235b7019` 的干净工作区开始，新增后台“价格展示方式”的“不展示”选项，并在关联试用 SKU 的“试用商品展示名称”上方增加同款独立下拉。V1 保留旧 `price_mode=actual|weekly`，用可选 `hide_price` 表示卡片隐藏；试用新增可选独立模式和隐藏字段，缺省继承源 SKU。配置仍存原 JSONB，无新 migration；旧客户端能忽略新增字段，但不会执行新隐藏效果。新版 iOS Page／Modal 仅隐藏商品卡金额、价格说明与辅助周均价，保留购买区真实计费摘要；Android 仍走原路径。详见[服务端合同](../03-data-api/subscription-display-config.md)、[后台页面](../04-admin/admin.md)和[客户端流程](../01-flows/subscription-display.md)。

本地环境为 macOS、Node 22.23.1、pnpm 11.25.0、Flutter 3.44.5／Dart 3.12.2。`pnpm --filter @kando/admin-web test` 67/67、Workers 订阅配置 3 文件 62/62、`flutter test test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 80/80 均退出 0；`pnpm lint`、`pnpm type-check`（7/7 任务）、`flutter analyze`、`pnpm --filter @kando/admin-web build:dev`、`git diff --check` 均退出 0。Admin 测试覆盖旧配置继承、两处回显和字段顺序；API 测试覆盖字段保存／公开读取及旧 payload；Flutter 测试覆盖 Page／Modal 的隐藏、试用独立覆盖和购买摘要保留。只读跨模块审查未发现阻断项；依赖锁文件未修改。

以上是本地源码与测试结果，未执行真实后台登录编辑、真实 Apple 目录／StoreKit、iPhone／Android 真机、签名构建、旧版 App 实机兼容、dev/prod 部署、远程配置写入、数据库迁移或 Git commit／push。旧版 App 对隐藏字段的忽略是代码合同结论，不代表已做正式旧包验收。

## 2026-10-19 iPhone 13 安装价格展示增量 Debug 包

从干净的 `codex/dev-1.0.6@eb365651` 在 macOS／Flutter 3.44.5／Xcode 27.1 上执行 `flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json`，Xcode 构建成功，Debug-test App 已安装并启动在 `kando的iPhone13`（iOS 26.6.2），Dart VM Service 建立；随后 detach 调试器，使用 `devicectl` 再次启动成功。设备安装列表回读为 `Card AI`、Bundle `com.kando.kandoApp.beta`、版本 `1.0.5 (171)`。对实际签名的 `build/ios/iphoneos/Runner.app` 回读确认 Bundle 一致、`get-task-allow=true`、App Attest entitlement 为 `development`；未制作或保存新 IPA。

设备运行日志报告 Internet offline，测试 API `192.168.50.201:8080`、Firebase 和 Singular 请求失败；开发机同一 API 的 health 请求正常。这说明本轮仅验收安装、签名和启动，未验收设备上的订阅配置读取、隐藏价格显示、登录、StoreKit 购买／恢复或外部埋点。前述本地服务端价格字段增量仍未部署到 dev；本轮无远端配置写入、数据库操作或 Git push。

## 2026-10-19 iOS 测试环境 Release 内部安装包 1.0.5 (172)

- 构建输入：从 `codex/dev-1.0.6@eb365651af68cbcddafd00b1f88e5bec2506e29b` 构建；构建前 App 源码与该提交一致，工作区仅有既存验证文档记录，构建期间 `git diff HEAD --binary` 的 SHA-256 保持为 `c4ed4e20ddf49d10aafba7ae86dff72fd57c4d4c2b4bc060c832010fa4549d55`。构建前版本为 `1.0.5+171`，本次使用 `1.0.5 (172)`；制品完整保存并校验后将 `pubspec.yaml` 同步为 `1.0.5+172`。工具链为 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。
- 环境与依赖：`config/test.json` 发布配置与 dev health 校验通过，最终 App 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1` 已嵌入且未发现生产 API，Firebase 项目为 `card-ai---test`。`pubspec.lock` 与 `ios/Podfile.lock` 的 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，没有依赖锁更新。
- 验证与构建：`flutter analyze --no-pub` 通过；订阅展示、恢复、OAuth authorizer 与发布配置相关测试共 92 项通过。执行 `flutter clean` 后构建 Release-test 原生产物并创建 Xcode archive。最终 IPA 从归档内已签名 App 原样封装，373 个文件逐字节一致；严格签名检查通过，Apple Development 签名、`get-task-allow=true`、App Attest `development`，描述文件有效至 2027-09-07，包含 6 台登记设备。归档退出 0，仅保留第三方弃用、Swift 6 前置兼容和 `in_app_review` 隐私清单处理等非阻断警告。
- 符号与完整性：`Card AI Test.ipa` 为 39,927,489 字节，SHA-256 `15a683cf03eb27af8023d7aa06e2d036ba8dad9303f3b0a6f3c305241702f71a`；`dSYMs.zip` 为 61,217,958 字节，SHA-256 `dc63ffff7f7f6ae7337532fbb9808967e696a5ac9120a2acce8e67b26f4e36f4`。两份 ZIP 完整性检查通过，42/42 个唯一 Mach-O UUID 有对应 dSYM，缺失／额外均为 0。44 个 dSYM bundle 中 43 个通过 `dwarfdump --verify`；`App.framework.dSYM` 有 169 个 Flutter AOT DWARF range 实际错误，命令输出包含 2 条汇总后共 171 条 `error:`，不能声称全部 dSYM 深度校验通过。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-172/`；新版本完整保存后将旧 169 版移入废纸篓，当前保留 170、171、172。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、购买、Restore、崩溃上报或真机启动验收；未部署、迁移数据库、提交或推送 Git。

<a id="linux-dev-manual-02b800e"></a>

## 2026-10-19 Linux dev 手工发布 `02b800e`

- 发布来源为本地干净 `dev@02b800e5bd6947c69d43b6fbbc1ab2dffea59e13`，执行 `pnpm --filter @kando/workers-api deploy:dev`，目标为 kd201 Linux dev；发布清单记录 `branch=dev`、`working_tree_dirty=false`、`source=deploy-dev`。release 为 `manual-02b800e5bd69-1792401770228`，`current` 与 `shared/current-release` 均指向该版本。
- 发布前 Linux 预检通过：数据库 `toccards_test`、PostgreSQL 18、CF 识别服务可达、`pendingMigrations=[]`。发布前备份为 `toccards-test-20261019-172257-before-manual-02b800e5bd69-1792401770228.dump`，1,135,483,183 字节；备份临时文件已清理，未执行恢复演练。
- 远端发布完成后，API／DB 容器分别为 healthy，Web 容器 running，migration 容器退出码 0；PostgreSQL ledger 为 15 项，最新 `0014_subscription_display_config.sql`。本次没有待执行 migration，也没有业务 SQL 写入。
- 独立 HTTP 烟测：`GET /api/v1/health` 返回 200／`{"status":"ok"}`，Admin 首页返回 200，未登录 `/api/v1/auth/me` 返回 401，`GET /api/v1/subscription-display-config?type=page&platform=ios` 返回 200／`{"success":true,"data":null}`。current release 中 API bundle SHA-256 为 `a3d3b1fe5433d214ba2921355be480f9f8f0c4370c1ad6ebebbc025ec5c79138`，运行文件与 release 文件一致。
- 本次为未推送本地提交的手工发布：watcher 的 `last-seen-sha` 仍为 `c23ae02`，`last-deployed-sha` 仍为 `06f420a`；未修改 watcher 状态、未执行 Git push。prod、旧 CF dev、营销站、Flutter 制品、真实登录、真实图片识别、购买／Restore 和完整真机验收均未执行。

## 2026-10-19 Home 顶部模式 Tab 视觉调整

按用户截图将 Home 的 Overview／Performance 从描边胶囊改为纯文字与选中下划线：两项均为 16px，选中项文字和 2px 底线使用 `KandoColors.accent`，未选中项使用同一主色的 45% 不透明度。点击时不显示默认按压覆盖或水波纹。Tab 宽度在切换时不变；窄屏空间不足时货币控件换到下一行，保留完整字号。原 Tab 状态、埋点、Free 顶部订阅入口和货币选择逻辑不变。

本地 Tab 切换、埋点、返回 Home、文字与底线样式及 360px 紧凑布局的 5 项定向 Widget 测试通过，`flutter analyze --no-pub` 无问题。Home 全文件 Widget 测试为 75 项通过、4 项 Golden 失败：两张整页 Golden 包含本次改动的顶部，另两张为独立 Performance 区域；整页对比还存在未改动内容的像素差异，因此未批量重录基线。320px 全页测试另暴露图表时间按钮和下方卡片已有的横向溢出，本次未修改这些模块。

同日以 `test` Debug flavor 在已连接的 iPhone 13 构建、安装并启动当前工作区，Dart VM Service 和 DevTools 已连接；实际签名 Bundle 为 `com.kando.kandoApp.beta`，App Attest 为 `development`。首张真机截图发现 `Overview` 被固定宽度裁掉末字，增加标签宽度并缩小间隔后热重载，复抓画面确认两个标签完整，`Performance` 选中态的主色文字和底线正常；随后关闭 Tab 默认按压覆盖和水波纹并再次热重载。最终宽度与按压反馈修正尚未重新构建独立安装包；Android 真机未验，未发布或上传商店。

## 2026-10-19 购买按钮上方自定义说明互斥展示

从 `codex/dev-1.0.6@6b9edc5d` 的干净工作区修改 iOS 订阅 Page／Modal 的共同购买区：有效后台配置为 `custom` 时只显示当前实际基础或关联试用 SKU 的自定义说明，空文本不显示说明；`auto` 时显示按 StoreKit 商品及资格生成的摘要，两者不再叠加。试用资格 unknown／ineligible 时沿用中性价格摘要，屏蔽可能误导的免费承诺。后台表单提示同步反映这一行为。原 PRD 1.14 要求固定摘要始终展示，当前用户指令已改变此规则；冻结 PRD 保留，实际消费规则更新至[客户端流程](../01-flows/subscription-display.md)与[服务端合同](../03-data-api/subscription-display-config.md)。未修改 V1 字段、服务端保存、StoreKit 价格校验、购买前复核、本地兜底或 Android 路径。

本地 `flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 86/86 通过，新增用例覆盖 Page／Modal 的基础与关联试用自定义文案、切换自动说明、空自定义及独立试用 eligible／unknown／ineligible 资格；`flutter analyze --no-pub` 无问题。`pnpm --filter @kando/admin-web test` 67/67、`pnpm --filter @kando/admin-web type-check`、`git diff --check` 均通过。未在真实 Admin 页面保存配置，也未以真机读取后台配置或执行购买／Restore；未构建、安装或发布包含本次改动的新 App 包，未部署服务端、迁移数据库或推送 Git。

<a id="linux-dev-redeploy-4f1ded1"></a>

## 2026-10-20 09:17–09:22 Linux dev 重新部署与独立验收

- 来源为干净的本地 `dev@4f1ded10008edca6e3eb89ed472b8fda06c68988`，本轮未推送远端。发布前实际运行的是 watcher 于 2026-10-19 发布的 `dev@be50921`／`branch-dev-be5092129aab-20261019173745`，不是此前手工 release；该状态来自独立 SSH 回读。相对运行源码，Linux 范围仅修改 Admin 订阅表单说明提示，Workers、共享包、部署脚本和 migration 文件均未改变；Flutter 增量不属于本次服务器发布制品。
- 本地执行 `pnpm --filter @kando/workers-api deploy:dry-run:dev`，Admin development／auth-core／Linux API 构建及 3 项独立 Linux bundle 检查退出 0。固定发布包 `linux-release-RuYmXd.tar.gz` 为 2,135,850 字节，SHA-256 `e4539426f5b57fb40fa6a8c68f11760ae4c16fa288d7f039974b010fad521e12`；65 个归档条目已检查，无私有环境文件、密钥或数据库备份。上传后校验同一归档哈希，再调用包内既有 `deploy/linux/ci/deploy-release.sh`，未修改或跳过发布门禁。
- 手工发布期间持有既有 watcher 的 `watch.lock`，发布脚本自行持有 `shared/deploy.lock`；候选预检和标准发布预检均确认 `toccards_test`、PostgreSQL 18、512／cosine／Top 5 识别契约可达、`pendingMigrations=[]`，才继续备份与发布。新 release 为 `manual-dev-4f1ded10008e-20261020T091702`，`current`／`shared/current-release`／manifest 指向一致；manifest 为 `branch=dev`、`working_tree_dirty=false`、`source=deploy-dev`，完整源码 SHA 与上述提交一致。
- 发布前备份 `toccards-test-20261020-091746-before-manual-dev-4f1ded10008e-20261020T091702.dump` 为 1,135,484,781 字节；发布后独立执行 PostgreSQL 18 `pg_restore --list` 退出 0，读取 336 项，临时文件不存在。未做恢复演练。独立只读 PostgreSQL 会话确认数据库为 `toccards_test`、版本 18.6、`default_transaction_read_only=on`；ledger 15 项／最新 `0014_subscription_display_config.sql`，与发布包 15 个 migration 文件一致，发布后预检无待执行项。migration 容器 exited/0，本次未执行新 migration 或业务数据写入。
- API／DB healthy、Web running；API／DB／Web 的环境数组哈希、端口绑定和挂载卷身份与发布前一致，原 PostgreSQL 18 数据卷及挂载目录保留。共享 `.env` 完整哈希保持不变且权限仍为 600，watcher 配置和脚本哈希未变。Web 的 `docker inspect` 挂载列表只改变排列顺序，逐项核对卷名和挂载点一致，不据此误报为换卷。
- 发布目录的 28 个 API／Admin／migration 文件与批准包 SHA-256 全部匹配；运行 API `/app/server.mjs`、Web 代理脚本和 Admin 容器内 11 个文件均与对应发布文件一致。API bundle SHA-256 仍为 `a3d3b1fe5433d214ba2921355be480f9f8f0c4370c1ad6ebebbc025ec5c79138`，与发布前相同。
- 从开发机访问内网入口的 8 项 GET 烟测通过：health／Admin 首页 200，未登录 auth/me／Admin 订阅配置列表 401，iOS Page／Modal 及 Google 展示配置 200，非法页面类型 422；配置接口均为 `no-store`。HTTP 返回的全部 11 个 HTML／JS／CSS 文件与批准构建原始字节一致。当前 iOS Page／Modal 已有生效配置，分别返回 revision 9／4；Google 为 `data:null`。本轮仅只读核对，未创建、审批、保存或切换任何订阅配置；不沿用历史 `data:null` 作为当前运行结论。
- 发布完成后 watcher 的 last-seen／last-deployed 均仍为 `be50921`，失败标记不存在，两把锁均空闲；未手改 watcher 状态或改变跟踪分支。后续远端 dev 的相关提交仍可能触发正常自动部署。证据保存在忽略目录 `apps/workers-api/.wrangler/dev-redeploy-4f1ded1-20261020/`，未把原始日志或凭据写入 docs。

本轮未重新运行完整 Workers／Flutter／App 兼容矩阵或 GitHub CI，未制作或安装新 Flutter 包，未执行真实管理员登录交互、真机扫描、StoreKit 购买／Restore、旧正式包验收、prod／营销站发布或 Git push。合并阶段已完成的订阅 86 项、Admin 67 项及静态检查不记为本轮重跑；当时 Home 77 项通过、2 项整页 Golden 失败的边界仍保留，本次服务器部署不关闭这些视觉基线问题。

## 2026-10-20 iOS 测试环境 Release 内部安装包 1.0.5 (173)

- 构建输入：从干净且与跟踪分支一致的 `codex/dev-1.0.6@4e37c7aa5380ecf4e3869121ed8d15be640bf3fe` 构建，包含 172 之后的 Home Tab 视觉调整及购买按钮上方说明逻辑；构建期间 `git diff HEAD --binary` 为空。构建前版本为 `1.0.5+172`，本次使用 `1.0.5 (173)`；制品完整保存并校验后将 `pubspec.yaml` 同步为 `1.0.5+173`。工具链为 Flutter 3.44.5／Dart 3.12.2／Xcode 27.1。
- 环境与依赖：`config/test.json` 发布配置校验通过，dev health 返回 `status=ok`。最终 App 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1` 已嵌入且未发现生产 API，Firebase 项目为 `card-ai---test`。根 `pubspec.lock` 与 `ios/Podfile.lock` 的 SHA-256 分别保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，没有依赖锁更新。
- 验证与构建：`flutter analyze --no-pub` 通过；订阅展示、恢复、OAuth authorizer 与发布配置 98 项通过，Home Tab 两项定向测试通过。执行 `flutter clean` 后构建 Release-test 原生产物并创建 Xcode archive。最终 IPA 从归档内已签名 App 原样封装，373 个文件逐字节一致；严格签名检查通过，Apple Development 签名、`get-task-allow=true`、App Attest `development`，描述文件有效至 2027-09-07，包含 6 台登记设备。构建和归档退出 0；保留 `sign_in_with_apple` 尚未支持 Swift Package Manager、第三方 Swift 前置兼容、App Intents 无依赖以及 `in_app_review` 隐私清单无处理规则等非阻断提示。既有 Firebase Crashlytics 构建阶段验证成功并启动后台符号上传，本轮未独立确认远端处理完成。
- 符号与完整性：`Card AI Test.ipa` 为 39,927,076 字节，SHA-256 `6af3598a1769159208e9e9031146b0868ab22deff568a95bc7c7cf2284b631c8`；`dSYMs.zip` 为 61,218,109 字节，SHA-256 `3cb3a7b394f15961df96f3d34a39bab1643eb08e55da2d01a9499a9da5cd764c`。两份 ZIP 完整性检查通过，42/42 个唯一 Mach-O UUID 有对应 dSYM，缺失／额外均为 0。44 个 dSYM bundle 中 43 个通过 `dwarfdump --verify`；`App.framework.dSYM` 有 169 个 Flutter AOT DWARF range 实际错误，命令输出包含 2 条汇总后共 171 条 `error:`，不能声称全部 dSYM 深度校验通过。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-173/`；新版本完整保存后将旧 170 版移入废纸篓，当前保留 171、172、173。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、购买、Restore、崩溃上报或真机启动验收；未部署、迁移数据库或推送 Git。

<a id="singular-admission-event-name"></a>

## 2026-10-20 Singular 商品准入事件名长度与回显修复（本地）

基线为干净的 `codex/dev-1.0.6@5d277631f9482e62742e06c135a98e55e59a5ad7`，本节增量为本地未提交改动。用户截图显示商品再次审核时收入事件名为空；代码路径确认 Admin 的 `openApproval` 每次重置为空，目录接口又只返回准入状态／原因，没有当前 scope 的已保存名称。前后端新审批校验均允许最多 100 字符，与 Singular 自定义事件的 32 个 ASCII 字符要求不符。这些是定位证据，不把此前的 SDK 模拟测试称为真实平台接收验收。

修复仅收紧新增／重新审批的事件名为 1–32 个字符，前端输入计数、按钮和提交函数以及 API 同步校验。后台目录增加当前环境／Bundle 的可选 `admission.singular_event_name`，普通商品和关联试用的审核弹窗按当前商品回显；未设置为空，切换商品不串值，确认勾选每次重置。已有长事件名仍完整读取与回显，纠正后才能重新审批；不截断、清空或批量改写历史映射／收入队列。App 公开注册表、购买／Restore、SDK 上报和 V1 原字段保持，无 schema／migration 或 Flutter 代码修改。

按兼容 AI 执行版，先完成代码、回归用例与文档，再在隔离的原基线上执行相同用例取得反证，并验证当前修复。原基线副本保留 `5d27763` 业务代码，只复制本轮回归用例，未覆盖实际工作区；不是修复前已经运行过的新测试。

- 隔离 UI 基线执行 `node --test .../apps/admin-web/test/subscription-config-approval.test.mjs`：依赖路径修正后退出 1，1 项通过／4 项失败；普通与关联试用名称均为空、输入上限为 100、旧长值也未回显。首次运行在加载 React 前失败，仅属隔离依赖解析问题，不作为 BUG 反证；补齐指向既有依赖的本地链接后才取得以上业务断言失败。
- 隔离 API 基线执行 `pnpm --filter @kando/workers-api exec vitest run --root <baseline>/apps/workers-api src/subscription-config/routes.postgres.test.ts --maxWorkers=2 --reporter=verbose`：退出 1，32 项通过／2 项失败；已保存名称为 undefined（期望保存值），33 字符审批返回 200（期望 422）。长值旧读取的兼容用例在原基线也通过。

| 当前修复的实际命令 | 结果 |
| --- | --- |
| `node --test apps/admin-web/test/subscription-config-approval.test.mjs` | 退出 0，5 项通过；调用真实页面回调，控制 hooks 与 AntD 渲染，验证回显、切换商品不串值、确认重置、32/33 边界及旧长值保留，不冒充真实浏览器验收 |
| `pnpm --filter @kando/admin-web test` | 退出 0，72 项全部通过、无跳过，包含上述新增用例 |
| `pnpm --filter @kando/workers-api test src/subscription-config/model.test.ts src/subscription-config/routes.postgres.test.ts src/subscription-config/catalog.test.ts --maxWorkers=2` | 退出 0，3 文件／65 项全部通过；含当前 scope 名称读取、跨环境／Bundle 不泄露、32 字符成功／超限拒绝且原映射不变、旧长值公开注册表读取，以及原鉴权／幂等／公开展示合同 |
| `pnpm type-check` | 退出 0，7/7 任务成功；Admin 与 Workers 实际执行，另 5 项命中缓存 |
| `pnpm lint` | 退出 0，依赖方向检查通过 |
| Flutter 目录执行 `flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_product_registry_test.dart test/subscription_singular_revenue_test.dart test/app_attribution_test.dart` | 退出 0，38 项通过；既有注册表、收入持久化／去重与 SDK 模拟调用回归，不等于真实平台接收 |
| 文档相对路径／锚点检查、`git diff --check` | 65 个相对链接／锚点可解析，差异检查退出 0 |

Code Review 完成代码及调用方自查，无阻断项：新增字段只进入已鉴权后台目录，值取已有当前 scope 注册表；原 `admitted/reasons` 与公开 App 响应保持；未收紧历史注册表解析而破坏既有商品支持；32 字符校验覆盖 UI 与直接 API，且不改变幂等结果核对。两类审核入口共用打开逻辑，回显不自动勾选确认或提交，超长值不静默截断。审查后未修改业务代码，未声称独立人员审查。

基线副本及定位材料保留在忽略目录 `apps/workers-api/.wrangler/singular-admission-fix-40tneg8a/`。本轮没有重跑完整 Workers／Flutter／旧包兼容矩阵，没有制作 Admin／Linux／Flutter 发布制品；未验证真实后台登录与浏览器交互、真机 StoreKit 交易或 Singular 平台接收。本轮以本地组件回调与内存 PostgreSQL 覆盖已定位路径；真实浏览器交互尚待补验，远端运行结果须另行部署后独立核对。未执行远程配置修改、数据库迁移、dev/prod 发布、Git commit 或 push。

## 2026-10-20 iPhone 13 订阅商品名称居中 Debug 复测

从 `codex/dev-1.0.6@5d277631` 加未提交的订阅商品布局、组件测试和客户端流程文档增量，执行 `flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json`。Xcode 编译、安装、启动成功，Dart VM Service 与 DevTools 已连接；设备安装列表确认 `kando的iPhone13` 上的 `Card AI` 为 `com.kando.kandoApp.beta`、`1.0.5 (173)`。签名 App 的 `get-task-allow=true`，App Attest entitlement 为 `development`。随后从 Flutter 调试器 detach，App 保持运行。

真机订阅完整页抓屏可见后台配置的 `Lifetime Access` 无副文案，右侧价格说明为两行；名称现在位于商品卡片垂直中部，选中态、价格和角标同时显示。设备画面是当前 Debug 构建，不等同于已保存的 173 Release IPA；本次未制作新 IPA，未检查弹窗、真实购买／Restore、Android 真机或服务端配置变更。此前本地订阅 UI 测试 55 项、`flutter analyze --no-pub` 和 `git diff --check` 均通过；本轮真机步骤没有重新运行这些检查。

## 2026-10-20 iPhone 13 订阅商品单选圆圈居中

配置商品的单选圆圈此前跟随文字行顶部定位。把周卡副文案扩成多行后，新增的中心点断言先复现圆圈比卡片中心高 32px；改为按卡片实际内容高度垂直居中后，周卡多行、年卡无副文案和一次性商品的圆圈均通过中心点断言，名称及价格的原有排布保持。`subscription_restore_ui_test.dart` 完整 55 项通过，`flutter analyze --no-pub` 与 `git diff --check` 通过。

使用当前未提交工作区再次执行 test flavor `flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json`，Xcode 构建、iPhone 13 安装与启动完成；设备应用列表回读为 `com.kando.kandoApp.beta`、`1.0.5 (173)`。真机订阅完整页抓屏显示后台配置的周卡多行副文案和年卡，两张卡的圆圈均位于卡片垂直中部。首次 Flutter 调试连接在启动后断开；第二次经无线连接启动后 Dart VM Service 未发现，`flutter run` 最终以 1 退出。因此本轮没有完成调试器附着或热重载，不把真机抓屏写成完整交互验收。未制作新 Release IPA、执行购买／Restore、Android 真机测试、服务端变更或 Git 提交／推送。

## 2026-10-21 iOS 测试环境 Release 内部安装包 1.0.5 (176)

- 构建输入：从干净且与实时远端一致的 `codex/dev-1.0.6@b578245b5878380115ef233db500a74632f7e420` 构建，包含订阅商品布局、名称、副文案和价格显示的最新提交。源码版本为 `1.0.5+173`，但本机已保存测试 174 和正式 175 制品；为避免构建号回退及同名目录覆盖，本轮显式选择 `1.0.5 (176)`，制品完整保存后将 `pubspec.yaml` 同步为 `1.0.5+176`。
- 环境与依赖：`config/test.json` 发布配置及 dev health 校验通过。最终 App 为 `com.kando.kandoApp.beta`，包含测试 API `http://192.168.50.201:8080/api/v1`、测试 Firebase `card-ai---test` 及测试订阅商品 `cardx.*`；未发现生产 API、生产 Firebase 项目或 `CardAi.*` 正式商品。根 `pubspec.lock` 与 `ios/Podfile.lock` 的 SHA-256 仍分别为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，没有依赖锁更新。Google OAuth audience 继续按既有合同使用生产 Client ID 供 Workers 验签，这是有意例外，不代表混入生产 Firebase。
- 验证与构建：发布脚本执行 `flutter clean` 后重新解析锁定依赖，`flutter analyze` 通过；test 定义下的订阅展示、恢复结果／界面、OAuth authorizer 与发布配置 5 个测试文件共 106 项通过。Release-test Archive 与导出完成，最终内部 IPA 从归档内开发签名 App 原样封装；严格 codesign 通过，Apple Development 签名、`get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`，描述文件有效至 2027-09-07并包含 6 台登记设备。`sign_in_with_apple` 尚未支持 Swift Package Manager 的提示仍存在。
- 符号与完整性：`Card AI Test.ipa` 为 39,926,843 字节，SHA-256 `525d53d9c615176dfbe82941559571e5d6473add81db6c64cc7a07d41e1dbf43`；`dSYMs.zip` 为 61,218,861 字节，SHA-256 `c3e6741e7765757f8b88a6c9c66601a328e93e244a9bf234e8158cf319bc7bf9`。两份 ZIP 完整性检查通过，IPA 的 42 个唯一 Mach-O UUID 均有 dSYM，缺失／额外 UUID 均为 0。44 个 dSYM bundle 中 43 个通过 `dwarfdump --verify`；仅 `App.framework.dSYM` 有 169 个 Flutter AOT parent-range 实际错误，另有 2 条汇总 error 行，不能声称全部 dSYM 深度校验通过。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-176/`；完整保存后将最旧的测试包 172 移入废纸篓，当前保留 173、174、176。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、StoreKit 商品读取、购买／Restore、崩溃上报或真机启动验收；未部署、迁移数据库、提交或推送 Git。

<a id="linux-dev-redeploy-f6f5ab3"></a>

## 2026-10-21 09:40–09:44 Linux dev 发布 Singular 事件名限制与审核回显修复

- 发布来源为干净的本地 `dev@f6f5ab339d370f300d524eba935c71ff09d5cbaa`，包含 `391e6ab` 的 Admin／API 修复；本次未推送 Git。发布前独立回读的实际 current 为 `branch-dev-b1f9e63d004e-20261020093144`／`dev@b1f9e63`，watcher last-seen 为 `96bf376`，last-deployed 为 `b1f9e63`。相对该运行基线，Linux 发布范围仅变更 Singular 审批事件名 32 字符写入校验、当前作用域的目录名称字段及审核弹窗回显；没有部署脚本、数据库 migration、依赖或 Flutter 原生实现变更。App 源码版本 1.0.5+176 不代表本轮制作或安装了新 App 包。
- `pnpm --filter @kando/workers-api deploy:dry-run:dev` 退出 0，Admin development／auth-core／Linux API 构建完成，3 项 Linux bundle 检查全部通过。固定包 `linux-release-btIBqN.tar.gz` 为 2,136,286 字节，SHA-256 `bb751d6bfcfcaad3d693a2ebd37781189776a08f0d6342e9323f95647cf43210`；65 个条目通过路径和私有文件检查，上传后哈希一致。仅上传白名单产物，未打包真实环境文件、密钥或数据库备份。
- 手工发布期间持有既有 watcher 的 `watch.lock`，复用包内 `deploy/linux/ci/deploy-release.sh` 和其 `shared/deploy.lock`。候选和标准发布预检均通过：`toccards_test`、PostgreSQL 18、识别 512／cosine／Top 5 契约、`pendingMigrations=[]`；候选预检显式拒绝任何待执行迁移，未放宽既有门禁。release 为 `manual-dev-f6f5ab339d37-20261021T093912`，current／shared current-release／manifest 一致，manifest 为 `branch=dev`、`working_tree_dirty=false`、完整 SHA 与上述源码一致。
- 发布前备份 `toccards-test-20261021-094013-before-manual-dev-f6f5ab339d37-20261021T093912.dump` 为 1,135,595,148 字节；发布后独立 `pg_restore --list` 退出 0，读取 336 项，临时文件不存在。未做恢复演练。独立只读 PostgreSQL 会话确认 18.6、数据库 `toccards_test`、`default_transaction_read_only=on`；ledger 15 项／最新 `0014_subscription_display_config.sql`，与包内 migration 文件一致，发布后预检仍无待执行项。migration 容器 exited/0，本次没有新 migration 或业务 SQL 写入。
- API／DB healthy、Web running；原 PostgreSQL 18 数据卷和扫描图片卷保留，API／DB／Web 的环境数组哈希、端口绑定和挂载卷身份与发布前一致。共享 `.env` 完整哈希不变、权限仍为 600；watcher 环境和脚本哈希不变，未更换 Key／密码／代理设置，未记录或输出凭据明文。完成时两把锁均空闲，watcher last-seen／last-deployed 仍为 `96bf376`／`b1f9e63`，失败标记不存在；没有手改 watcher 状态或触发第二轮自动发布。
- 发布目录的 28 个 API／Admin／migration 文件与批准归档哈希匹配，运行 API `/app/server.mjs` 与 Web 代理脚本均匹配发布文件；API SHA-256 为 `8cff134aea470c951db909e2cb2832fb4ef11f974efad10f002d8582114c6d7c`。Admin 容器内及开发机通过 HTTP 取得的 11 个 HTML／JS／CSS 文件均与批准构建原始字节一致，确认新 Admin 与 API 配套运行。
- 12 项内网 GET 烟测通过：health／Admin 首页 200；未登录 auth/me、Admin 配置和商品目录 401；iOS Page／Modal 及 Google 展示读取 200，非法类型 422；iOS／Google 商品注册表 200，非法平台 422。公开订阅接口均为 `no-store`。Page／Modal 分别为 revision 10／4，iOS 注册表为当前 development／beta Bundle 作用域、4 个商品；这三份公开响应的原始字节哈希与发布前完全相同。未创建、审批、保存或切换订阅配置。

本轮实际重跑的是发布构建和 3 项 bundle 检查、远端预检及上述运行验收；此前同源码合并阶段的 Admin 72 项、订阅 API 65 项、Flutter 订阅 86 项及类型／静态检查不是本轮重跑。32 字符与回显的组件／内存 PostgreSQL 反证和回归见[本地修复记录](#singular-admission-event-name)，新代码上线由产物匹配证明；未执行真实管理员登录态的审核回显、重新审批或超限提交，也未新增真实交易验证。未重新运行完整 Workers／Flutter／旧包兼容矩阵、GitHub CI、真机扫描、StoreKit 购买／Restore 或 Singular 平台接收；未发布 prod、营销站或 Flutter 制品，未执行 Git push。原始证据位于忽略目录 `apps/workers-api/.wrangler/dev-redeploy-f6f5ab3-20261021-xcxgcfis/`，未将原始日志或私有配置写入 docs。

<a id="trial-conversion-dev-release-51323e7"></a>

## 2026-10-21 16:28–16:33 Linux dev 发布试用转付费修复并应用 0015

- 来源为干净的本地 `dev@51323e75a90e645512c08579c061f1b2736c4d3e`，包含 `fd7aefd` 的订单分类修复。本轮开始时实际运行 `dev@10ff05e`／`branch-dev-10ff05ece3be-20261021095942`，API／DB healthy、Web running。候选只新增 PostgreSQL `0015_trial_conversion_status.sql` 及对应 Notifications V2／订单事实逻辑；Admin 业务代码、依赖和部署脚本未改。
- 先按实际 SQL 的 CTE 条件在 `default_transaction_read_only=on` 会话核查：16:07 及授权后 16:26 均为 0 条候选，ledger 仍为 15 项／最新 0014。发布准备阶段没有执行 migration 或切换应用；向用户明确说明历史订单回填及不可自动反向回退的边界，收到用户明确“允许”后才执行本次远程 0015 与部署。
- 本轮本地执行 Workers 的 4 个实际源测试文件（billing-order-facts、apple-notification-routes、apple-product-policy、trial-conversion-status-migration），使用标准 `.wrangler` 排除、`--maxWorkers=1 --no-file-parallelism`，退出 0，72 项全部通过；Workers type-check 及预检测试 8/8 通过。`deploy:dry-run:dev` 完成 auth-core／Admin development／Linux API 构建，3 项 bundle 检查通过。固定包 `linux-release-FG8gq5.tar.gz` 为 2,137,372 字节，SHA-256 `9e00e9818e5576f07837a4ec3d472a2a84595695ff81df5a156a632665f36f18`；66 个条目无私有环境／密钥／数据库备份，上传后哈希一致，授权后再次校验并从同一归档重新解包。
- 准备阶段备份 `toccards-test-20261021-161105-verified-before-candidate-dev-51323e75a90e-20261021T160943.dump` 为 1,135,597,657 字节，`pg_restore --list` 读取 336 项；授权后既有发布脚本另行生成最新发布前备份 `toccards-test-20261021-162819-before-manual-dev-51323e75a90e-20261021T162814.dump`，1,135,597,728 字节，独立目录读取同为 336 项，临时文件均不存在。两份备份均未做恢复演练。
- 发布期间持有既有 watcher 的 `watch.lock`，由包内标准 `deploy-release.sh` 自行持有 `shared/deploy.lock`，未修改发布脚本。授权只允许候选的 `0015`：候选与标准预检均确认 `toccards_test`、PostgreSQL 18、向量 512／cosine／Top 5 可达，唯一待执行项为 0015。标准迁移容器逐项跳过 0000–0014，16:31:17（北京时间）提交 0015，日志明确 `UPDATE 0`、迁移记录插入及 `COMMIT`；历史订单实际更新 0 行。独立只读回查 ledger 为 16 项／最新 0015，发布后预检 `pendingMigrations=[]`；16:37 以同一 CTE 再核查待回填候选仍为 0。不能把迁移已执行写成历史订单已转换若干条，也不能因此声称真实 Apple 通知已验收。
- 新 release 为 `manual-dev-51323e75a90e-20261021T162814`，current／shared current-release／manifest 一致，manifest 为 `branch=dev`、`working_tree_dirty=false`、完整源码 SHA 与上述提交一致。API／DB healthy、Web running、migration exited/0；PostgreSQL 18.6 原卷及图片卷保留。私有 `.env` 完整哈希和 600 权限、API／DB／Web 环境数组哈希、端口和挂载卷身份、watcher 配置／脚本均与发布前一致。watcher last-seen／last-deployed 仍为 `10ff05e`，失败标记不存在，完成时两把锁空闲；没有手写 watcher 状态或 Git push。
- 发布目录 29 个 API／Admin／migration 文件均匹配批准包；API 运行 `/app/server.mjs` 的 SHA-256 为 `b813fc90f8793a69c96bc058bec88d18ba01502b58447b21f2e44b332f8909b2`，与发布文件一致，Web 代理脚本也匹配。Admin 容器内及 HTTP 取得的全部 11 个 HTML／JS／CSS 文件与批准构建原始字节一致。
- 12 项 GET 烟测通过：health／Admin 首页 200；未登录 auth/me、Admin 配置和商品目录 401；iOS Page／Modal／Google 展示读取 200，非法页面 422；iOS／Google 商品注册表 200，非法平台 422。公开订阅接口 `no-store`；Page／Modal 当前 revision 1／4，iOS 当前作用域 7 个注册商品，这三份响应哈希与本轮发布前采样完全一致，未保存／审批／启用任何订阅配置。此处是本次 16:28 前采样，不沿用上午 release 的 Page revision 10 或 4 个注册商品结论。

本次已完成 dev 的授权迁移及 API／Admin 发布，prod、旧 CF dev、营销站、Flutter 制品和 Git 远端均未操作。未跑完整 Workers／Flutter／旧包兼容矩阵或 GitHub CI；未做真实 Apple 通知、StoreKit 购买／Restore、真实管理员登录统计／筛选／导出、真机或收入平台端到端验收。应用回退不逆向迁移；本轮没有触发回退或进行数据库恢复。原始证据在忽略目录 `apps/workers-api/.wrangler/dev-redeploy-51323e7-20261021-rgbf580c/`，未把日志、数据库备份或私有配置加入 docs。
<a id="collection-item-edit-duplicate"></a>

## 2026-10-21 收藏编辑重复项 500 修复（本地）

Mixpanel 中与 Crashlytics 时间一致的请求显示，App 1.0.5 (163) 编辑收藏时，`PATCH /api/v1/portfolio/items/:item_id` 连续返回裸 `500 Internal Server Error`。代码路径确认新增收藏已有完整收藏身份预查与 `409 DUPLICATE_COLLECTION_ITEM`，编辑接口此前直接执行 PostgreSQL 更新；编辑后撞上 `uq_collection_item_folder_card_variant` 唯一索引时，异常会穿透为 500。

本地修复在编辑更新前查询完整收藏身份，仅当命中另一条 item 时返回既有 409；命中当前 item 不影响数量、备注等普通编辑。更新事务同时捕获 PostgreSQL `23505` 且约束名为 `uq_collection_item_folder_card_variant` 的并发冲突并返回同一 409，其他数据库错误保持内部错误。请求字段、成功响应、owner 隔离、数据库唯一索引和 schema 均不变，无 migration；现有 Flutter 已按 `DUPLICATE_COLLECTION_ITEM` 保留编辑输入并显示重复提示，无需客户端协议修改。

基线为干净的 `codex/dev-1.0.6@fd7aefd3`。`pnpm --filter @kando/workers-api test src/portfolio/items.test.ts --maxWorkers=2` 退出 0，1 个文件／20 项全部通过；新增用例覆盖编辑后命中另一条收藏身份时更新与事件均不执行，以及预查后发生 PostgreSQL 命名唯一约束冲突时仍返回同一 409。既有普通字段编辑和编辑时移动收藏夹用例继续通过。`pnpm --filter @kando/workers-api type-check`、`git diff --check` 与文档路径／锚点检查均退出 0。

Code Review 自查确认：预查命中当前 item 时继续保存；只有目标约束的 `23505` 或包含目标约束名的唯一冲突消息映射为重复收藏，其他数据库异常返回结构化 `500 INTERNAL_ERROR`；PostgreSQL batch 保持更新与事件写入的原事务边界。未运行完整 Workers、Flutter 或旧源码兼容编排，也未执行真实 PostgreSQL 并发、正式旧包／真机、远程数据库写入、migration、dev/prod 部署、Git commit 或 push。

## 2026-10-21 订阅页底部购买区样式对齐（本地）

从干净的 `codex/dev-1.0.6@40d6c9c8` 修改 iOS Page／Modal 共用 Footer。Figma `3465:9667` 的正常 Action Area 为 350×90（无计费说明）或 350×122（有 16 高计费说明），CTA 为 350×56、圆角 99、16／24 SF Pro Semibold 深色文字，计费说明及协议行分别与按钮相距 16。独立兜底参考状态的协议行到辅助提示间距为 4。实现同步调整计费说明、按钮、协议及本地兜底辅助提示的字号、颜色和间距；后台配置不显示 `NO PAYMENT NOW`／`CANCEL ANYTIME`，两条提示仍只在本地兜底按当前商品试用事实择一显示。未改配置读取、商品选择、试用、购买或 Android 分支。

Flutter 3.44.5／Dart 3.12.2 下，`subscription_restore_ui_test.dart` 55/55、`subscription_display_test.dart` 31/31 通过；测试检查了配置来源的辅助提示隔离、350×56 按钮、16／24 加粗文本及兜底提示样式。配置加载时的 iOS 按钮也保持整行宽度。`flutter analyze --no-pub` 与 `git diff --check` 无问题。390×844 弹窗 Golden 因预期样式差异首次比较失败（14.35% 像素差异），更新该单张基线后不带更新参数复跑通过。首次 Flutter 测试在编辑中因 `const Padding` 包含运行时样式而编译失败，修正后完整重跑通过。只读 Code Review 未发现可操作回归，确认 Android 样式分支和本地兜底提示来源条件保持原状。Golden 不能代替真机 SF Pro 与紧凑机型视觉复测；本轮也未执行购买／Restore、iOS 安装包构建、Android 真机、远程部署、Git commit 或 push。

## 2026-10-21 订阅商品周均价展示方式（本地增量）

后台“价格展示方式”为页面展示 SKU 和关联试用 SKU 增加“只展示周均价”。V1 继续使用 `price_mode=weekly`，以可选 `weekly_only=true` 表示只展示周均价；试用字段省略时继承基础 SKU，显式 false 覆盖继承，`hide_price` 优先。旧版 App 可忽略该字段并继续读取配置，但不会呈现新版样式。新版 iOS Page／Modal 的“实际周期价格 + 周均参考价”把周均金额移到右侧实际价下方，显示本地化金额加固定 `per week`；“只展示周均价”用周均金额作右侧主价、下方显示 `per week`。周均和本地兜底月卡等派生金额最终四舍五入为两位小数。实际 StoreKit 扣费价格、购买目标、权益、Android 路径及现有 PostgreSQL schema 不变，详见[服务端合同](../03-data-api/subscription-display-config.md)、[后台页面](../04-admin/admin.md)和[客户端流程](../01-flows/subscription-display.md)。

`pnpm --filter @kando/admin-web test` 77/77，`pnpm --filter @kando/workers-api exec vitest run src/subscription-config/model.test.ts src/subscription-config/catalog.test.ts src/subscription-config/routes.postgres.test.ts` 3 文件 68/68；两端 `type-check` 退出 0。`flutter test --no-pub test/subscription_display_test.dart test/subscription_restore_ui_test.dart` 91/91，`flutter analyze --no-pub` 无问题，`flutter test --no-pub test/widget/auth_profile_test.dart --plain-name 'subscription bottom sheet renders the 390x844 fixture' -r expanded` 1/1；Dart 格式检查和 `git diff --check` 通过。首轮 Flutter 目标测试因新增测试的滚动控件定位及两条旧 `price_note` 预期失败，修正测试后完整重跑通过。只读 Code Review 未发现可确认的功能或兼容性回归；截图示例金额不是计算真值，`$49.99/year` 按年价÷52 得 `$0.96/week`，`$12.99/month` 按月价×12÷52 得 `$3.00/week`。新增的三个文档相对链接目标存在。

以上仅为本地源码及组件验证。Admin 本地 Vite 预览 HTTP 200 且新选项包含在已转换模块中，预览代理的 dev API 尚未部署本轮服务端改动，不能用它保存新字段。未进行 iOS／Android 真机、购买／Restore、安装包构建、远端配置写入、数据库迁移或 dev/prod 部署，也未运行全量 Workers 测试。

## 2026-10-21 iOS 测试环境 Release 内部安装包 1.0.5 (177)

- 构建输入：从与实时远端一致的 `codex/dev-1.0.6@40d6c9c8f2f5b979a202b9efeb24df2fb24af3d0` 加当前未提交的订阅配置、Flutter UI／测试／Golden、Admin、Workers 与文档增量构建，必须标记为 dirty，不能写成纯提交制品。构建前 `git diff HEAD --binary` 的 SHA-256 为 `682ad48f0f50747bffc976a8cf4cdebf8708387b04e61820da085c478d382c0a`；本次使用 `1.0.5 (177)`，完整保存后将 `pubspec.yaml` 从 `1.0.5+176` 同步为 `1.0.5+177`。本包包含 Flutter 的 `weekly_only` 展示合同、周均价布局及购买区样式增量；未提交的 Admin／Workers 代码不进入 IPA。
- 环境与依赖：`config/test.json` 校验及 dev health 通过。最终 App 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1`、测试 Firebase `card-ai---test` 与 6 个测试商品均存在；生产 API、生产 Firebase 及 `CardAi.*` 正式商品均不存在。Google OAuth audience 按既有合同继续使用固定生产 Client ID，属于后端验签的已知例外。根 `pubspec.lock` 与 `ios/Podfile.lock` 哈希保持 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，iOS 工程和依赖未变化。
- 验证与签名：发布脚本执行 `flutter clean`、锁定依赖解析和 `flutter analyze`，均通过；本轮重新运行订阅展示与恢复 UI 测试 91/91、390×844 弹窗 Golden 定向测试 1/1。Release-test Archive 与内部 IPA 生成成功；IPA 内 373 个文件与 Archive 逐字节一致，App 与 41 个 Framework 共 42 个组件均通过严格签名校验且均为 Apple Development。最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`；描述文件有效至 2027-09-07，包含 6 台登记设备。
- 符号与完整性：`Card AI Test.ipa` 为 39,927,527 字节，SHA-256 `36c303fd2073489cfc009722f87ebc4641d1da42f8b7784ea48ca1df69d3c71c`；`dSYMs.zip` 为 61,219,053 字节，SHA-256 `af9162ac607801314486eb463bfa3d922a7718ca84d3008e0bcffa689f001156`。两份 ZIP 完整性及与 Archive 的逐文件对照通过，42/42 个唯一 Mach-O UUID 有覆盖，缺失／额外均为 0。44 个 dSYM 中 43 个通过深检；仅 `App.framework.dSYM` 有 169 个 Flutter AOT parent-range 实际错误，另有 2 条汇总 error 行，不能声称全部 dSYM 深度校验通过。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-177/`；完整保存后将最旧测试包 173 移入废纸篓，当前保留 174、176、177。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、StoreKit 商品读取、购买／Restore、崩溃上报或真机启动验收；未部署、迁移数据库、提交或推送 Git。

<a id="linux-dev-redeploy-b0b6496"></a>

## 2026-10-22 09:45–09:51 Linux dev 发布收藏重复项与订阅周均价增量

- 来源为干净的本地 `dev@b0b649665f8785266768ccc67036d40d72ea233a`，包含 `40d6c9c` 的收藏编辑重复项 409 修复及 `4b997fd` 的订阅周均价配置。发布前实际运行 `dev@c4b39ed`／`branch-dev-c4b39ed9a1ee-20261021165343`，API／DB healthy、Web running，watcher 与 deployment 两把锁空闲。相对该运行基线，Linux 发布范围为收藏 API、订阅配置 API 与 Admin；Flutter 源码／版本变化未作为 App 制品发布，依赖、部署脚本及 migration 文件没有变化。
- 本轮实际执行 Workers 的 portfolio/items、subscription-config/model、catalog、routes.postgres 四个测试文件，使用正式测试入口的 `.wrangler` 排除、`--maxWorkers=1 --no-file-parallelism`，88/88 通过；Admin 77/77、两端 type-check、预检测试 8/8 通过。`deploy:dry-run:dev` 完成 auth-core／Admin development／Linux API 构建及 3/3 bundle 检查。固定包 `linux-release-G68e7c.tar.gz` 为 2,138,780 字节，SHA-256 `3445ed177f102c3a35a0454b3d94f262414234c9716078188ef37723b3822311`；66 个归档条目未包含真实环境、密钥或数据库备份，上传后哈希及 29 个运行文件逐项一致。
- 手工发布持有既有 watcher 的 `watch.lock`，复用包内标准 `deploy/linux/ci/deploy-release.sh` 与其 `shared/deploy.lock`。候选、标准发布及发布后预检均确认独立 `toccards_test`、PostgreSQL 18、识别 512／cosine／Top 5 可达及 `pendingMigrations=[]`；不允许本次候选执行新增迁移。标准迁移容器逐项跳过 0000–0015、退出 0；独立只读回查 PostgreSQL 18.6、ledger 16 项／最新 `0015_trial_conversion_status.sql`，本次没有执行新增 migration 或历史订单回填。
- 发布前备份 `toccards-test-20261022-094530-before-manual-dev-b0b649665f87-20261022T094348.dump` 为 1,135,717,341 字节，独立 `pg_restore --list` 退出 0、读取 336 项，临时文件不存在；未做恢复演练。备份成功后才更新容器，本轮没有触发应用回退或数据库恢复。
- 新 release 为 `manual-dev-b0b649665f87-20261022T094348`，current／shared current-release／manifest 一致，manifest 为 `branch=dev`、`working_tree_dirty=false`，源码 SHA 与上述提交一致。API／DB healthy、Web running、migration exited/0。API 运行文件 SHA-256 为 `5225c84c4aa9936e494b9447e6b1be91630608a9a66a114bed30a2f03d36d615`；发布目录全部 29 个 API／Admin／migration 文件、Web 代理脚本、Admin 容器内及 HTTP 取得的全部 11 个 HTML／JS／CSS 文件均匹配批准构建。
- 12 项 GET 烟测通过：health／Admin 首页 200；未登录 auth/me、Admin 配置和商品目录 401；iOS Page／Modal／Google 展示读取 200，非法页面 422；iOS／Google 商品注册表 200，非法平台 422，公开订阅接口均为 `no-store`。Page／Modal 当前 revision 12／4，iOS 作用域 `development:com.kando.kandoApp.beta` 共 7 个注册商品，三份响应哈希与本轮发布前完全一致；本轮没有保存、审批或启用配置。
- 私有 `.env` 完整哈希与 600 权限、API／DB／Web 环境数组哈希、端口及原 PostgreSQL／图片／Web 卷身份均保留。配置检查首次按原始 Web 挂载数组比较报顺序差异；逐项核实为相同卷名与目标的排列变化，按 Type／Name／Destination 身份排序后完全一致，未修改服务器挂载。watcher 配置／脚本／状态未改，last-seen／last-deployed 仍为 `c4b39ed`，失败标记不存在，完成时两把锁空闲。

本次仅发布 Linux dev API／Admin，未推送 Git、发布 prod／旧 CF dev／营销站／Flutter 制品或执行远程业务写入。未跑完整 Workers／Flutter／旧包兼容矩阵或 GitHub CI；真实管理员登录态的周均价保存／审批／启用、真实收藏编辑冲突、StoreKit 购买／Restore、真机视觉和收入平台端到端仍未验收，不能用源码测试或产物匹配替代。本地公开响应采样脚本首轮因 CommonJS 与顶层 await 混用未执行，改为 ESM 后三项采样及发布后对照通过；未修改产品代码。原始证据在忽略目录 `apps/workers-api/.wrangler/dev-redeploy-b0b6496-20261022-8ae535f5/`，未将日志、备份或私有配置写入 docs。

## 2026-10-22 iOS 测试环境 Release 内部安装包 1.0.5 (178)

- 构建输入：从干净且与实时远端一致的 `codex/dev-1.0.6@4b997fd22b578e2612ee55f4f803078540033f4a` 构建；177 制品使用的订阅展示、周均价布局及购买区样式增量已提交到该版本，177 之后没有新的 Flutter 业务源码、依赖或 iOS／Android 工程变化。本次显式选择 `1.0.5 (178)`，完整保存后将 `pubspec.yaml` 从 `1.0.5+177` 同步为 `1.0.5+178`。
- 环境与依赖：`config/test.json` 校验及 dev health 通过。最终 App 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1`、测试 Firebase `card-ai---test` 与 6 个测试商品均存在；生产 API、生产 Firebase 及 `CardAi.*` 正式商品均不存在。Google OAuth audience 按既有合同继续使用固定生产 Client ID，属于后端验签的已知例外。根 `pubspec.lock` 与 `ios/Podfile.lock` 哈希保持 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，构建及回归后均未漂移。
- 验证与签名：发布脚本执行 `flutter clean`、锁定依赖解析和 `flutter analyze`，均通过；订阅展示与恢复 UI 测试 91/91、390x844 弹窗 Golden 定向测试 1/1 通过，未更新 Golden。Release-test Archive 与内部 IPA 生成成功；App 与 41 个 Framework 共 42 个签名组件均通过严格签名校验，签名为 `Apple Development: kancloud cq (578WZAD3DU)`。最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`；开发描述文件有效至 2027-09-07，包含 6 台登记设备。`sign_in_with_apple` 尚未支持 Swift Package Manager 的提示仍存在；本机构建使用 Flutter 3.44.5，与文档目标 CI 3.44.7 存在小版本差异。
- 符号与完整性：`Card AI Test.ipa` 为 39,927,512 字节，SHA-256 `a7a39aeb368242fc4005f45a0af7e0e3d810b98165be9384d84457e97a168e41`；`dSYMs.zip` 为 61,219,052 字节，SHA-256 `551fb1aa9820007932384f1f453dbdfb9f4814cfa67a003cb12229eee1c8fade`。两份 ZIP 完整性通过，42/42 个唯一 Mach-O UUID 有 dSYM，缺失／额外 UUID 均为 0。44 个 dSYM 中 43 个通过深检；仅 `App.framework.dSYM` 有 169 个 Flutter AOT parent-range 实际错误，另有 2 条汇总 error 行，与前包相同，不能声称全部 dSYM 深度校验通过；两组重复 bundle 共享已有 UUID，不影响符号覆盖。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-178/`；完整保存后将最旧测试包 174 移入废纸篓，当前保留 176、177、178。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、StoreKit 商品读取、购买／Restore、崩溃上报或真机启动验收；未部署、迁移数据库、提交或推送 Git。

## 2026-10-22 iOS 测试环境 Release 内部安装包 1.0.5 (179)

- 代码同步与构建输入：构建前将当前 `codex/dev-1.0.6` 从 `4b997fd22b578e2612ee55f4f803078540033f4a` 严格快进到实时远端 `b4dacd1cf5b5a309881eda9fb3ec96320c63e1bf`，构建后再次回读远端仍为同一提交。新增业务代码仅为首页空状态标题样式及对应测试；本地同时保留上次打包产生的 `1.0.5+178` 和 178 验证记录，没有其他未提交业务源码。本次显式构建 `1.0.5 (179)`，完整保存后将 `pubspec.yaml` 从 `1.0.5+178` 同步为 `1.0.5+179`。
- 环境与依赖：`config/test.json` 校验及 dev health 通过。最终 App 为 `com.kando.kandoApp.beta`，测试 API `http://192.168.50.201:8080/api/v1`、测试 Firebase `card-ai---test` 与 6 个测试商品均存在；生产 API、生产 Firebase 及 `CardAi.*` 正式商品均不存在。Google OAuth audience 按既有合同继续使用固定生产 Client ID，属于后端验签的已知例外。根 `pubspec.lock` 与 `ios/Podfile.lock` 哈希保持 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021`、`d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`，拉取、构建及测试后均未漂移。
- 验证与签名：发布脚本执行 `flutter clean`、锁定依赖解析和 `flutter analyze`，均通过；首页空状态两个受影响定向测试 2/2 通过。完整 `home_page_test.dart` 有 72 项通过、4 个 Golden 测试失败，前两个可能包含本轮可见样式变化，另两个与本提交无关；没有使用 `--update-goldens`，不能将完整首页测试记为通过，真机仍需关注小屏标题换行或裁切。Release-test Archive 与内部 IPA 生成成功，Archive 与 IPA 的 373/373 个常规文件逐路径 SHA-256 一致；App 与 41 个 Framework 均通过严格签名校验，签名为 `Apple Development: kancloud cq (578WZAD3DU)`。最终 `get-task-allow=true`、App Attest=`development`、Apple Sign In=`Default`；开发描述文件有效至 2027-09-07，包含 6 台登记设备。`sign_in_with_apple` 尚未支持 Swift Package Manager 的提示仍存在；本机 Flutter 3.44.5 与文档目标 CI 3.44.7 仍有小版本差异。
- 符号与完整性：`Card AI Test.ipa` 为 39,927,437 字节，SHA-256 `47b13bb32bef95460e0dcf434308aa461174f9a07efd2f4deda1ca1150b608e0`；`dSYMs.zip` 为 61,219,046 字节，SHA-256 `aec152e025c91ff7345894d75de91b81a25d6d9882ce8136f06a08e3027fb750`。两份 ZIP 完整性通过，保存符号与 Archive 的 131/131 个常规文件逐路径一致；42/42 个唯一 Mach-O UUID 有 dSYM，缺失／额外 UUID 均为 0。44 个 dSYM 中 43 个通过深检；仅 `App.framework.dSYM` 有 169 个既有 Flutter AOT parent-range 实际错误，另有 2 条汇总 error 行，不能声称全部 dSYM 深度校验通过；两组重复 bundle 与原 bundle 的 UUID 及 DWARF 字节相同，不影响符号覆盖。
- 保存与边界：制品保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.5-179/`；完整保存后将最旧测试包 176 移入废纸篓，当前保留 177、178、179。本次未安装设备、上传蒲公英／TestFlight／App Store Connect，也未执行真实登录、扫描、StoreKit 商品读取、购买／Restore、崩溃上报或真机启动验收；未部署、迁移数据库、提交或推送 Git。

## 2026-10-23 完全离线订阅兜底（本地增量）

用户确认：冷启动时即使后台配置与 StoreKit 商品都无法读取，iOS Page／Modal 仍展示周试用、年订阅、月订阅三张本地兜底卡。包内固定 USD 参考价分别为 `US$4.99 per week`、`US$49.99 per year`（右侧 `US$0.96 per week`）、`US$12.99 per month`（右侧 `US$3.25 per week`）。离线预览提示价格仅供参考，购买入口禁用；没有 StoreKit 商品事实时不承诺可用试用或真实地区售价，也不把参考价传入购买、权益或收入上报。预览期间每 15 秒自动重读后台配置及 StoreKit 商品，手动重试和回到前台也触发刷新；读取并通过现有校验后，页面以 StoreKit 本地化实际价格和商品试用事实刷新，才恢复购买。既有已展示后台商品的快照保护和 Android 订阅路径保持原合同，详见[客户端流程](../01-flows/subscription-display.md#兜底与平台边界)。

本地验证：`flutter test --no-pub test/subscription_display_test.dart` 38/38 通过，覆盖离线三卡、购买禁用、StoreKit 查询中不提前预览、超时后预览、恢复后台配置／商品真实价及既有配置快照保护；`flutter test --no-pub test/subscription_restore_ui_test.dart` 62/62 通过，覆盖 Page／Modal 的离线参考价、禁用按钮和手动重试后真实价格；`flutter analyze --no-pub` 无问题，`git diff --check` 通过。本机 Flutter 为 3.44.5，目标 iOS CI 为 3.44.7；本地测试本身不代表签名、真机或交易验收。

同日补验：当前未提交工作区通过 `flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json` 在有线连接的 iPhone 13（iOS 26.6.2）完成 Xcode 编译、安装与启动，Dart VM Service／DevTools 已连接。设备应用列表回读为 `Card AI`、`com.kando.kandoApp.beta`、`1.0.5 (179)`；最终签名 `Runner.app` 通过严格校验，`get-task-allow=true`、App Attest=`development`。设备当时无网络，日志中 test API 的订阅配置请求报 `NSURLErrorDomain -1009`；独立真机截屏可见周试用、年、月三张固定 USD 参考价卡及禁用的 `CONNECT TO CONTINUE`，年/月完整价也显示。test 环境的右侧调试悬浮入口遮住周卡价格末尾，不能凭本次截屏独立读全 `US$4.99`；该金额已由本地页面测试覆盖。本次尚未进行真机联网恢复、购买／Restore、Android 真机或新 IPA 验收，未部署服务端或推送 Git。

### 同日可选兜底与购买提交调整

用户在上述离线真机检查后追加要求：后台配置与 StoreKit 商品全量失败时，包含弱网、超时和已展示真实商品后的全量刷新失败，显示可选择的三张固定 USD 参考价卡，不显示按钮上方离线提示；中性 `SUBSCRIBE` 可点击。点击按所选 Product ID 即时重新读取并校验 StoreKit 商品，成功时复用既有购买前复核和购买链路，读取或校验失败用顶部提示反馈。无真实商品对象时不得调起 Apple 支付面板，固定价不作为交易价格。固定价阶段持续重试，恢复后显示 StoreKit 真实本地化价格；部分商品成功时保留已有配置与成功商品。该合同覆盖本节此前的“离线按钮禁用”及“真实商品展示后全量失败仍保留快照”行为，详见[客户端流程](../01-flows/subscription-display.md#兜底与平台边界)。

上面的 38/38、62/62 和 iPhone 13 截屏只证明调整前的禁用按钮版本；它们不构成本次可选、可提交、失败顶部提示及全量刷新失败切换的验证。

调整后本地验证：`flutter test --no-pub test/subscription_display_test.dart` 43/43、`flutter test --no-pub test/subscription_restore_ui_test.dart` 62/62 通过；覆盖离线默认与切换选中、点击瞬间锁定 SKU、重复提交、点击商品读取失败及成功、购买前再次校验全失败回兜底、弱网配置超时、已展示远端商品后全量失败切兜底并保留原关闭延迟、部分成功保留与 Page／Modal 按钮和顶部提示。`flutter analyze --no-pub` 无问题，`git diff --check` 通过。本机仍为 Flutter 3.44.5，与目标 iOS CI 3.44.7 有小版本差异。

同一 iPhone 13 test Debug 调试会话对最新 Dart 代码热重启成功；设备仍无网络，独立截屏确认本地周试用默认选中、三卡固定 USD 参考价保留、按钮上方离线提示消失、`SUBSCRIBE` 为亮色可点击样式。该热重启未重新生成独立安装包，真机没有点击购买，也未验证 StoreKit 支付弹窗、联网恢复、Restore、Android 真机或新 IPA；后台配置及服务端未改动，Git 未推送。

同日 Footer 修正：固定价三卡没有真实 StoreKit 商品时，旧 Footer 因 `selectedCard == null` 同时隐藏了两条辅助提示。按用户确认改为本地兜底始终在 Terms 下方显示一条：已注册周试用商品显示 `NO PAYMENT NOW`，年／月订阅显示 `CANCEL ANYTIME`；已有真实商品时仍由 StoreKit 试用事实决定。按钮上方继续没有离线提示，固定参考价仍不参与交易。定向 Flutter 测试 105/105 通过，覆盖 Page／Modal 两种入口的周、年、月切换及 Terms 下方 4px 间距；`flutter analyze --no-pub` 无问题。同一 iPhone 13 test Debug 会话热重启成功，设备离线时的独立截屏确认默认周试用卡选中、`SUBSCRIBE` 可见、Terms 下方显示 `NO PAYMENT NOW`，按钮上方无离线提示；年／月真机切换与交易未验证。

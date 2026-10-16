# v1.1.2 实际验证记录

本文件保留 Admin、营销站等其他业务的实际验证。App 兼容规则、源码合同证据及 Home 文件夹切换历史记录见 [AI 执行版](../03-data-api/app-backward-compatibility-ai-guide.md)；历史版本记录见 [v1.1.1](../../v1.1.1/05-delivery/VERIFICATION.md)。未运行或只有部分证据的事项不得标记为完整验收通过。

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

<a id="subscription-store-price-rounding"></a>

## 2026-10-16 StoreKit 价格浮点表示导致周卡被过滤

本次从 `codex/dev-1.0.6@e6f986f1` 的干净工作区定位并修复 Flutter 客户端问题。原 test 调试包在 iPhone 13 的完整订阅页与弹窗入口均缺少周卡关联试用；真机读取确认插件和原生 StoreKit 都返回 `cardx.week`，但插件 `rawPrice=3.9899999999999998`，原生 `price_decimal="3.99"`。锁定的 `in_app_purchase_storekit 0.4.11` 将 StoreKit Decimal 经 `NSDecimalNumber.doubleValue` 转为插件金额，原生只读桥接将同一 Decimal 转为字符串；Swift 最小复现显示两种路径落在相邻的 double 值。原 Dart 严格相等校验因此丢弃周卡，关联 `weekly.trial` 的资格虽为 eligible，也无法显示试用切换。这是修复前的真机与转换证据，未将另一路未返回的 `yearly.pro` 归因为同一问题。

修复仅限 iOS 商品事实与插件商品的金额比较：有限、非负价格最多允许 1 ULP 的二进制表示差异，零价还须确认原生十进制字符串确实为零；超过 1 ULP 的差异继续拒绝。Product ID、币种、格式化展示价、类型和周期的校验保留，购买前 `sameTerms` 的十进制金额与资格二次确认没有放宽。Flutter 的 Android 既有隔离路径、原生桥接、API、schema 和商品配置均未改。

验证：`flutter test --no-pub --dart-define-from-file=config/test.json test/subscription_display_test.dart` 退出 0，25 项通过，覆盖真机观测价格、Page／Modal 的关联试用开关、真实差价拒绝、零价下溢拒绝及已有购买前金额变化二次确认；`flutter analyze --no-pub` 退出 0、无问题，`git diff --check` 退出 0。最初一次分析指出新增 `dart:typed_data` 导入多余，移除后重新分析通过。目标本机 Flutter 为 3.44.5，设备为 iPhone 13／iOS 26.6.2。更新后的 `1.0.5+163` test Debug 包通过 `flutter run --no-pub --flavor test --debug -d 00008110-000A242A01A2801E --dart-define-from-file=config/test.json` 在同一设备构建、安装并启动。独立抓屏确认完整页与弹窗均显示 `US$3.99` 普通周卡；完整页下半部抓屏还可见试用开关开启、`START FREE TRIAL`、年订阅和终身商品。试用商品的续费文案为 `US$4.99/周`，与普通周卡当前价格不同，此为两个 StoreKit 商品的实测展示，需按业务预期核对，不属于本次浮点校验修复。弹窗试用开关位于当前抓屏视口以下，未单独看到其实际控件；年商品当前可见不能归因于本次金额修复。

真机调试日志还出现 Firebase Installations 与 Logging 请求超时；App 仍启动并显示订阅页，本轮未排查该独立网络问题。未执行真实购买、Restore、弹窗试用开关的独立真机视口检查、Android 真机或商店签名包验证；本次也未执行 Git push、服务端发布、远程数据库写入或 prod 操作。独立 Code Review 检查了浮点位序、零价、周卡与试用控制器路径、购买前 `sameTerms` 及文档；无阻断性问题。审查建议已收窄上述金额差异表述。

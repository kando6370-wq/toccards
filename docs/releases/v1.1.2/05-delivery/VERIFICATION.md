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

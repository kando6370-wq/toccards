# AGENTS.md

本文件适用于整个仓库。所有 Agent 默认使用简体中文沟通。

## 工作原则

- 注意该项目app开发选择了Flutter而不是Ios或Android原生开发，所以开发要兼容两者,不能实现时，应先停止并询问。
- 先读后写：修改前阅读目标文件、直接调用方、相关配置和已有测试。
- 先明确假设：存在会改变实现或删除范围的歧义时，先停止并询问。
- 保持简单：只实现当前需求，不增加猜测性功能或一次性抽象。
- 外科手术式修改：不顺手重构、格式化或清理无关代码。
- 遵循既有规范：仓库内部的一致性优先于个人偏好；若既有规范存在实质风险，应明确说明，不得暗中引入另一套范式。
- 显式暴露冲突：代码、配置和文档不一致时，以当前可执行代码和已验证配置为证据，说明选择，不静默融合。
- 显式失败：不得把跳过的检查写成通过；必须列出未运行项及原因。
- 目标驱动：开始前定义验收条件，重要步骤后总结完成项、验证结果和剩余工作。
- 模型仅用于判断类任务：适合分类、起草、摘要和信息提取；路由、重试、数据转换等确定性任务应使用常规代码完成。
- 必须注意docs文件夹下文档,和此文档的实时更新

## 仓库结构

这是 TypeScript/Node 与 Dart/Flutter 并行的 monorepo：

- `apps/admin-web`：React、Vite、TypeScript、Ant Design 管理后台。
- `apps/marketing-web`：Cloudflare Workers 营销与法律页面。
- `apps/workers-api`：共享 Hono API、Cloudflare Workers 与 Linux Node 运行入口、PostgreSQL 访问层及 migrations。
- `apps/flutter-app`：Flutter 客户端，使用 Riverpod 与 GoRouter。
- `packages/auth-core`：共享认证与密码学能力。
- `packages/api-client`、`packages/ui-kit`、`packages/workers-common`：TypeScript 共享包。

Node workspace 由 `pnpm-workspace.yaml` 管理；Dart workspace 由根 `pubspec.yaml` 管理。当前 Dart workspace 正式包含 `apps/flutter-app` 与 `dart-packages/subscription-core`，不要把未跟踪目录当作工作区成员。

### 项目架构

当前业务环境只分 `prod` 和 `dev`：prod 保持原 Cloudflare 部署，dev 指 kd201 Linux 独立数据库环境。旧 Cloudflare dev 业务 Worker 已退役，不得作为后续 dev 发布目标；CF 向量识别与独立 Apple 回调仅作为 dev 的外部服务保留。下图描述 prod，dev 使用下述 Linux 独立数据库与 HTTP 识别适配。

```text
Flutter App ───────────────┐
                          ├─> Cloudflare Workers API (`/api/v1`)
React Admin ── HTTPS ──────┘          ├─> PlanetScale PostgreSQL（经 Hyperdrive）：业务与目录真源
                                     ├─> KV：目录与汇率缓存
                                     ├─> R2：扫描图片
                                     ├─> recognize-vec：Service Binding 向量检索
                                     └─> OAuth、邮件、汇率等外部服务

Marketing Web ──> 独立的营销与法律页面
```

- Flutter App 只通过 API 访问服务端数据，不直接连接 PostgreSQL、KV 或 R2。
- Admin 是独立 React SPA；prod 的 `admin.tcgcard.fun` 由 Cloudflare Pages 项目 `toccards-admin` 托管，`api.tcgcard.fun` 的后台副本由 `toccards-api-prod` Workers assets 托管，两者均调用生产 API，必须分别发布并同时验收。Linux dev 仍由 Caddy 或离线 Node 静态服务托管，与对应 API 一起部署。
- 共享 Hono API 是鉴权、账号归属、资产隔离、卡牌查询、扫描识别和 Admin 操作的服务端边界。`src/app.ts` 组合业务路由；`src/index.ts` 和 `src/linux/server.ts` 分别适配 Cloudflare 与 Linux。
- D1 已废弃；旧 CF dev/test 与 prod 曾通过同一 Hyperdrive 使用 PlanetScale PostgreSQL，2026-09-09 回读时均无 D1 binding。2026-09-07 prod 直接使用共享 PostgreSQL，没有复制旧 D1 数据或执行冲突合并；旧 D1 不得重新绑定、读写或用于回滚，删除资源另需明确授权。2026-09-17 旧 CF dev Worker、域名和 cron 已退役，历史测试数据保留；当前 dev 使用 Linux 独立 PostgreSQL，prod 保持 Cloudflare/Hyperdrive。后续发布不再包含 D1 迁移、冲突审计或 D1 回滚前置任务。
- dev/prod 的 PostgreSQL 迁移均已完成。后续 v1.1 开发不得新增或恢复 D1 binding、schema、migration、类型依赖、测试基座、读写路径、数据补全、回退或灾备方案；旧 prod D1 仅作为历史资源，不得成为新实现或回退依据。仓库中仍存在的 `D1Database` 兼容类型、Miniflare 测试和退役迁移工具属于待清理债务，只能在明确授权的清理任务中收敛，任何新功能或 BUG 修复不得复制、扩展或继续维护。`docs/releases/v1.0.0` 冻结内容仍按文档规则原样保留。
- 插件免登录识别入口为 `/api/v1/extension/recognize`：使用独立 `EXTENSION_RECOGNITION_KEY` 与按 IP 的短时间防刷，转发现有 `{vector, card_type}` 后，按 `product_id` 复用现有卡牌详情查询，返回图片、价格及运营修正字段；仅只读访问卡牌/价格数据，不接入 App 登录、订阅、额度或扫描记录；缺失 Key/限频/IP 时仅关闭新入口。prod 使用独立原生 Rate Limiting binding，Linux 默认不信任客户端代理头；插件源码不在本仓。2026-10-09 已按 `dev-extension` 的 dirty 工作区包手工部署 Linux dev，真实 Key/频率原字节保留，仅在确认 API 私有网络后追加代理信任标志；同日 14:19 已由既有 watcher 发布并独立验收干净的 `dev@b621d76`，私有配置保持不变。同日 15:05 已确认插件发布至 prod `e8c5d1fb-0e4d-4eb0-8483-3a77a4ba08fb`，现有生产 Key 保留，新增独立限频绑定 60/60 秒；生产仅完成无 Key/错误认证拒绝验证，正确 Key 的识别、详情和触发限频仍待补验。dev 合成向量 5 个候选的详情与原接口一致，真实图片/插件验收未完成，详见 [插件接口契约](docs/releases/v1.1.1/03-data-api/extension-recognition.md)。
- dev 扫描使用 Flutter 编排的端侧模型和 iOS/Android 原生推理桥接，经 `VECTOR_RECOGNITION` 调用 `recognize-vec`。prod Cloudflare 通过 Service Binding；Linux 源码通过必填 `VECTOR_RECOGNITION_BASE_URL` 的 HTTP 适配只发送向量和 `card_type`，候选补全、额度和扫描记录仍使用本地 PostgreSQL。旧 OpenCV/pHash 请求及 `OCR_SERVICE_BASE_URL` 运行时字段已移除。平台范围为 iOS 16+、Android API 24+，Web 扫描暂不支持；后续变更须保持两端兼容。旧来源分支已清理，后续从含向量合并的 `dev` 开发与部署。
- Linux 入口仅允许 `APP_ENVIRONMENT=development`，通过 `DATABASE_URL` 使用独立 PostgreSQL，配合进程内 KV 与本地图片卷。2026-09-15 用户明确这是现有 dev 环境迁至 Linux 的整改，CF 只读向量识别继续复用，prod 保持 Cloudflare。源码中 App `test` 默认请求 `http://192.168.50.201:8080/api/v1`，Admin development 使用同源 API/本机 Vite 内网代理；测试分享与移动端指定 IP 的网络策略一并隔离。2026-09-29 17:03 回读确认 Linux watcher 已自动发布 `dev@c9f950e`，包含扫描并行增量及 Admin 候选图放大；API/DB healthy、Web running、migration exited/0，失败标记为空。实际发布预检 pendingMigrations 为空，PostgreSQL ledger 只读回查为 14 项、最新 `0013`。2026-09-29 17:37 仅更新 `api.tcgcard.fun` 所在 prod Worker 的 Admin 候选图放大副本，version `1b806fe1-7516-4749-ac87-77c3c6c29deb` 回读为 100% 流量；发布前后 Worker 脚本逐字节一致，后端业务仍为原 `main@7868f4c` 对应逻辑，未上线 dev 的扫描并行增量。既有 Smart Placement 和 Hyperdrive 查询缓存均保留开启，17:39 回读绑定、变量、运行配置和定时任务均未变；17:46 补验发现另一 prod Admin 入口 `admin.tcgcard.fun` 仍返回旧版；2026-09-30 补齐 Pages 授权后确认它由独立项目 `toccards-admin` 托管，09:07 发布同一批准产物为 deployment `038a65be-4858-4e31-89d1-fa67bf4ff559`，09:09 两个入口的 HTML 和各 10 个 JS/CSS 资源均与批准构建一致。Pages 构建配置与域名、API Worker、Hyperdrive 和 cron 未变。当时 Pages 跟踪 main 自动发布，而 main 尚无本次 Admin 改动；该历史覆盖风险的后续状态以 2026-10-08 检查点为准。今后 Admin 发布必须同时核验这两个 prod 入口，不能以 API 域名副本替代实际 Admin 域名验收；原性能及缓存一致性验收缺口不因本次 Admin 发布而关闭，详见 [v1.1.1 验证记录](docs/releases/v1.1.1/05-delivery/VERIFICATION.md)；本次没有执行 migration，prod PostgreSQL ledger 的上次独立回读仍为 2026-09-21 的 14 项，未在本轮重查。旧 CF dev 业务入口和 cron 已退役，见 [Linux 测试环境](docs/releases/v1.1.0/02-architecture/linux-test-environment.md)。
- 历史 prod 检查点（2026-10-08 09:27–09:36）：按干净的 `main@61b5420` 重新发布 API 和两个 Admin 入口，Worker version `4adbd0b7-3c67-4795-8ad0-c39795dc4be6` 为 100% 流量，Pages deployment `39154bee-45d6-429d-8118-dfafed526ab7` 为 production/success。线上 Worker 与批准构建逐字节一致；两个 Admin 入口各 11 个 HTML/JS/CSS 文件全量匹配。Smart Placement、Hyperdrive 缓存、变量/绑定、cron、域名及 Pages 配置未变，仅 Worker 发布注释随新版本更新。既有 Pages 自动部署已来自同一 main，候选图预览改动现已包含在 main。未执行 migration、SQL 业务写入、营销站或 Flutter 发布，未重查生产 ledger；旧 App 真机、真实扫描/登录态、性能与缓存一致性仍未验收。基础 health 固定 URL 可命中 HTTP 缓存，本轮用新查询参数取得 MISS 样本验收，并从一条真实新 Worker 日志确认 `placement`、`ingress_colo`、`country` 字段；单条 health 不证明扫描或性能收益。详见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md`。
- 历史 prod 检查点（2026-10-09 15:01–15:05）：从干净的本地 `main@c253647` 发布插件增量；先上传并逐字节校验候选，再将 Worker version `e8c5d1fb-0e4d-4eb0-8483-3a77a4ba08fb` 切到 100%，deployment `188b72b5-68a8-473d-9a8e-45019547f663`。仅新增 `EXTENSION_RECOGNITION_RATE_LIMITER`（namespace `2026100801`、60 次/60 秒），现有变量/Secret binding 描述符、Hyperdrive/KV/R2、Service Binding、Smart Placement、运行缓存、cron 和域名配置均保持；不宣称读取了 Secret 明文。Pages `toccards-admin` 同步同一批准产物，deployment `cda22b78-846e-4b91-b6fc-7a69a022c768` 为 production/success；双 Admin 共 22 个文件原始字节全部匹配，Admin 业务代码未改。完整 Workers 84 文件/771 项（maxWorkers=2）、Admin 26 项、类型/依赖及 prod dry-run 通过；health/原鉴权/App 配置/Admin CORS、新入口缺失 Key/错误 Key/错误格式返回 401 验收通过。生产 Key 已存在且未替换，但明文不可用，因此正确 Key 的识别/详情/限频、真实插件及真机仍待补验。该生产发布阶段没有数据库迁移或业务写请求、Git push、Linux dev/营销站/Flutter 发布；当时远端 main 为 `f952e50`，发布源为本地 main 与远端 dev 的 `c253647`。后续 Git 交付见下条，不把生产部署等同于推送 main。详见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md`。
- 插件 prod 故障定位（2026-10-09）：线上 `e8c5d1fb` 的插件路由向 Service Binding 传入 Workers 不支持的 `redirect: "error"`，会在到达上游前抛出 TypeError，再被包装为 `502 VECTOR_RECOGNITION_UNAVAILABLE`。已用本地真实 Workers 运行时及实际插件路由复现；最小本地修复改为 `manual`，仍拒绝重定向，Linux HTTP 适配器保留 Node 支持的 error 模式。定位阶段先完成本地验证，170 项相关回归、类型检查、Linux 打包与生产 dry-run 通过；随后经明确授权于 16:08 发布 prod，版本及用户反馈见下一条，源码仍未提交/推送。原请求历史日志未获得（查询权限 403），用户附件的 Key 是脱敏值，脱敏重放的 401 不是原问题证据；用户随后回复“可以了”，按修复后的调用恢复反馈记录；独立的生产正确 Key 原始请求、候选详情逐字段对照及限频触发仍未补验，不得把用户反馈扩展为这些专项验收已完成。详见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md` 的 BUGFIX 补证。
- 历史 prod 修复检查点（2026-10-09 16:08–16:09）：从 `main@4b31cba` 加未提交的 redirect 最小修复发布，必须标记 dirty，不能写成纯提交构建。Worker version `ac0654e0-5b71-457f-9ddf-6f478995e6d9` 为 100%，deployment `317beb8f-ca11-4e7e-8b22-34488f13ec5d`；实际产物与原线上仅差 error→manual 及说明注释。Key/限频、完整绑定、变量、运行缓存、Hyperdrive、cron、域名配置均保留。Pages 保持已有自动发布的 `a17f8f12-5e12-4eba-a206-d48be3c45313`（来源 `4b31cba`），本轮未重发；双入口 22 个文件发布前后均未变，Pages HTML 与 Windows 构建有既存 CR 差异，不称 22/22 跨平台字节一致。基础 API/鉴权/CORS 与插件错误认证烟测通过；用户发布后反馈“可以了”。未执行数据库迁移、Git commit/push、dev/营销站/Flutter 发布，详情/限频等独立验收边界保留，详见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md`。
- 最新 prod Admin 发布（2026-10-14 09:12–09:15）：从干净的 `main@ee3f298` 配套发布订单金额/退款汇总 API 与两个后台入口。Worker `3345b389-2501-4dd2-8f30-f85c03c87949` 为 100%，deployment `a186c31b-67d6-41cb-b1d4-41d07efd4a31`；Pages `2c600e3e-1cd1-4e5c-a7c2-adceceb0bf9f` 为 production/success，来源同一 main、dirty=false。完整 Worker 与旧线上仅差 Admin 订单汇总路由，已有插件 redirect 修复保留；双入口 22 个静态文件与批准构建原始字节一致，9 项 HTTP 烟测通过。变量/绑定、Secret 描述符、Hyperdrive/运行缓存、Smart Placement、cron、域名和 Pages 配置未变。无数据库迁移/业务写入、Git push、dev/营销站/Flutter 发布，未回查生产 ledger；真实 Admin 登录业务、真机与原有专项验收仍待完成，见 `docs/releases/v1.1.2/05-delivery/VERIFICATION.md`。
- Git 交付检查点（2026-10-09）：prod 发布记录提交 `dbc2091` 已推送 `github/main`，本地/远端 main 一致；dev 为 `c253647`，已完整包含于 main。`dbc2091` 相对 `c253647` 仅变更 6 份文档/Agent 规则，最近已验收的 prod 发布源仍记为 `c253647`、Linux dev 发布源为 `b621d76`；推送后的 CI、自动发布与运行状态本轮未回查。本地/远端均无 `dev-ext*` 分支，历史来源名保留，不再作为开发分支。生产正确 Key 的识别/详情/限频以及真实插件/真机待验项没有因提交推送而关闭。
- `deploy:dev` 构建 Linux 发布包并通过显式 SSH 目标发布，`deploy:dry-run:dev` 仅打包，不连接服务器；prod 继续使用原 Wrangler 发布入口。Linux 发布须先通过环境/数据库/识别预检，再备份已有数据库；标准与离线 Compose 均以 PostgreSQL 18 和原有 `PGDATA=/var/lib/postgresql/data` 为契约，不自动进行大版本升级。2026-09-30 历史 dev 检查点的 Linux release 为 `branch-dev-7516cfd2a06a-20260930110549`，2026-09-30 11:10 确认 manifest、`current-release`、`last-seen-sha` 与 `last-deployed-sha` 一致，失败标记不存在；既有 watcher 已自动发布请求放置日志增量。发布日志显示 API/DB healthy、Web started、migration 检查成功且 ledger 为 14 项，实际预检无待执行 migration；这些容器/数据库结果来自发布脚本，未另行通过 SSH 独立回查。发布前备份为 1,135,397,728 字节，临时文件已不存在；本轮未执行 `pg_restore --list` 或恢复演练。11:13 内网 health 200、未登录 auth/me 401、Admin 200；10 个 JS/CSS 资源与本地 dev 构建字节一致，HTML 仅 CR 字符有差异，不宣称原始字节一致。DBX MCP 只读策略阻止了手动 SSH 和产物下载，本轮没有绕过策略；运行容器 API bundle 哈希与新增字段的运行日志未独立回读。Apple 官方 Sandbox TEST 已经独立公网回调处理成功。旧 CF dev 的 Worker、域名和 cron 已退役，旧测试数据和包保留；API 与 watcher 的代理配置仍分别存放在各自私有环境文件。验证范围与未执行项见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md`。
- 历史 Linux dev 检查点（2026-10-09 10:58）：手工发布 `manual-extension-f952e50-dirty-20261009-1791513409974`，来源为未提交的 `dev-extension` 工作区，不能标记为纯 `f952e50` 提交。API/DB healthy、Web running、migration 检查 exited/0，ledger 仍为 14 项且最新 `0013`，无待执行 migration；原 PostgreSQL 18 数据卷保留。发布前数据库备份 1,135,397,964 字节，`pg_restore --list` 成功列出 324 项，未做恢复演练；API/Web 运行文件与批准产物 SHA256 一致，Admin 的 11 个 HTML/JS/CSS 字节全量匹配。插件 Key、频率 60 原字节保留，仅追加 `EXTENSION_TRUST_PROXY=true` 并备份私有环境文件；确认 API 没有宿主端口绑定，更新后的离线代理覆盖来源头。鉴权、参数拒绝、合成向量 5 个完整详情对照与防刷验收通过，不代表真实图片识别准确率。watcher 仍跟踪 `dev`，其 last-deployed 保持 `7516cfd`；后续 dev 自动发布可能覆盖此手工版本，未擅自修改 watcher 或 Git 推送。prod 未改动，详见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md`。
- 历史 Linux dev 检查点（2026-10-09 14:19）：既有 watcher 已发布干净的 `dev@b621d76501e67ecc22fa6888c7bd6bdc3c2dba34`，release 为 `branch-dev-b621d76501e6-20261009140959`。manifest、current、last-seen 与 last-deployed 一致，失败标记不存在；本轮接续正在执行的发布并独立验收，没有并发启动第二次部署或手改 watcher。API/DB healthy、Web running、migration 检查 exited/0，PostgreSQL 18 原卷保留，ledger 14 项且最新 `0013`，无待执行 migration。发布前备份 1,135,398,457 字节，`pg_restore --list` 通过并列出 324 项，未做恢复演练。API/Web 运行文件与同提交本地构建 SHA256 一致；Admin 11 个文件与 Linux release 原始字节一致，跨 Windows 构建对照的 10 个 JS/CSS 一致，HTML 仅有 12 个 CR 字符差异，不称跨平台 HTML 字节一致。私有环境文件完整哈希未变，插件 Key 保留、频率 60、trustProxy=true，API 无宿主端口绑定；合成向量 5 个详情与原接口一致。未部署 prod；完整默认 Workers 测试未重跑，既有全量超时记录与真机/真实插件待验边界仍保留，详见`docs/releases/v1.1.1/05-delivery/VERIFICATION.md`。
- 最新 Linux dev 补验（2026-10-12 14:22–14:26）：PR #3 已合入 `dev@e8d1dd9`；SSH 独立回读确认 watcher/current/manifest 指向 `branch-dev-e8d1dd952f05-20261012131153`，失败标记不存在。API/DB healthy、Web running、migration exited/0；PostgreSQL 18、ledger 14 项/最新 `0013`、无待执行迁移。发布前备份 1,135,398,457 字节，`pg_restore --list` 成功列出 324 项，未做恢复演练。运行 API/Web 文件及 Admin 11 个静态文件与 Linux release 字节一致，基础 HTTP 烟测通过；本轮只读验收，未手工重发或迁移。该运行检查点早于 C03 的后续合并整理，C03 增量由 PR #6 跟踪；正式旧包/真机、完整兼容矩阵仍待验，见 [AI 执行版的历史证据摘要](docs/releases/v1.1.2/03-data-api/app-backward-compatibility-ai-guide.md#63-保留的历史证据摘要)。
- 历史 Linux dev 订阅首次发布（2026-10-15 15:38 独立验收）：按用户授权把订阅候选整合为 `dev@f8afca9`，发布 `manual-dev-f8afca9f401e-20261015T071443Z`，dirty=false；0014 备份后执行，PostgreSQL 18 原卷保留，ledger 15 项。API／DB healthy，API 与 Admin 11 个静态产物匹配批准构建，Page／Modal 均无生效配置。共享环境仅把识别地址配套切至 recognize-vec.tcgcard.fun 的 512／cosine 服务，Apple 目录凭据及其他配置保留；pHash／OCR 是同事此前的独立测试基线，本次不移植。watcher 已备份并对齐实际发布 SHA，旧失败标记清除，锁已释放；后续文档提交可以只推进 last-seen。真实管理员业务、真机扫描／购买恢复、新商品准入仍待验，prod 未操作。详见 [dev 发布记录](docs/releases/v1.1.2/05-delivery/VERIFICATION.md#subscription-config-dev-release)，之前的基线差异保留在同文历史检查点。
- 历史 Linux dev 发布（2026-10-20 09:17–09:22）：从干净本地 `dev@4f1ded1` 手工重发，release `manual-dev-4f1ded10008e-20261020T091702`；API／DB healthy、Web running、migration exited/0，PostgreSQL 18.6 原卷保留，ledger 15 项／最新 0014，无待执行迁移。API 与发布前字节相同；Admin 容器及 HTTP 的 11 个文件均匹配批准构建，8 项 HTTP 烟测通过。发布前备份 1,135,484,781 字节、`pg_restore --list` 读取 336 项，未做恢复演练。私有环境和 watcher 配置／状态未改，last-seen／last-deployed 均保持 `be50921`，本地合并未推送；Page／Modal 当前已有生效配置（revision 9／4），本轮只读核对。未发布 Flutter 包或 prod，真实业务与两项既有 Home Golden 失败边界保留，见 [本次 dev 验证记录](docs/releases/v1.1.2/05-delivery/VERIFICATION.md#linux-dev-redeploy-4f1ded1)。
- 历史 Linux dev 发布（2026-10-21 09:40–09:44）：干净本地 `dev@f6f5ab3` 手工发布 API／Admin，release `manual-dev-f6f5ab339d37-20261021T093912`，包含 Singular 审批事件名 32 字符校验与审核回显修复。API／DB healthy、Web running、migration exited/0；PostgreSQL 18.6 原卷保留，ledger 15 项／最新 0014，无待执行迁移。发布前备份 1,135,595,148 字节，`pg_restore --list` 读取 336 项，未做恢复演练；API 与 Admin 11 个容器／HTTP 文件均匹配批准构建，12 项 HTTP 烟测通过。Page／Modal revision 10／4 与当前商品注册表的响应哈希均与发布前一致，未改配置；私有环境、原卷和 watcher 状态保留，last-seen／last-deployed 仍为 `96bf376`／`b1f9e63`。本轮未推送 Git、未发布 prod 或 Flutter 包，真实管理员登录业务、真机交易及既有未验范围保留，见 [本次 dev 验收](docs/releases/v1.1.2/05-delivery/VERIFICATION.md#linux-dev-redeploy-f6f5ab3)。
- 历史 Linux dev 发布（2026-10-21 16:28–16:33）：经用户明确授权应用 0015 后，按干净本地 `dev@51323e7` 发布 API／Admin，release `manual-dev-51323e75a90e-20261021T162814`，包含试用 SKU 首扣订单分类修复。0015 实际 `UPDATE 0` 并提交迁移记录；PostgreSQL 18.6 原卷保留，ledger 16 项／最新 `0015_trial_conversion_status.sql`，无待执行迁移。最新发布前备份 1,135,597,728 字节、`pg_restore --list` 读取 336 项，未做恢复演练；API／DB healthy、Web running、migration exited/0。API 及 Admin 11 个容器／HTTP 文件匹配批准包，12 项 HTTP 烟测通过；Page／Modal revision 1／4 与 7 个商品注册表响应均保持。私有配置和 watcher 状态未改，last-seen／last-deployed 仍为 `10ff05e`，未推送 Git 或操作 prod／Flutter 制品；真实通知和管理员业务待验，见 [本次 dev 发布验收](docs/releases/v1.1.2/05-delivery/VERIFICATION.md#trial-conversion-dev-release-51323e7)。
- 最新 Linux dev 发布（2026-10-22 09:45–09:51）：从干净本地 `dev@b0b6496` 手工发布收藏重复项 409 与订阅周均价 API／Admin，release `manual-dev-b0b649665f87-20261022T094348`。API／DB healthy、Web running、migration exited/0；PostgreSQL 18.6 原卷保留，ledger 16 项／最新 0015，无待执行迁移，本轮没有新增迁移。发布前备份 1,135,717,341 字节、目录读取 336 项，未做恢复演练；29 个发布文件及 Admin 11 个容器／HTTP 文件匹配批准构建，12 项 HTTP 烟测通过。私有配置、端口、原卷及 watcher 状态保留，last-seen／last-deployed 仍为 `c4b39ed`；Page／Modal revision 12／4 与 7 个商品响应哈希不变。未推送 Git 或发布 prod／Flutter，真实业务待验，见[本次 dev 验收](docs/releases/v1.1.2/05-delivery/VERIFICATION.md#linux-dev-redeploy-b0b6496)。
- `packages/*` 只承载跨应用共享能力，应用之间通过包依赖或 HTTP 契约协作。

## 工具链与常用命令

- Node `>=22`，pnpm `11.9.0`，Dart SDK `^3.9.2`。
- 安装 Node 依赖：`pnpm install --frozen-lockfile`
- TypeScript 全仓构建：`pnpm build`
- TypeScript 类型检查：`pnpm type-check`
- App 兼容源码回归：`pnpm test:app-compatibility`；固定 v1.0.4/v1.0.5 提交，在本地内存 PostgreSQL 跑当前 API，再使用旧 Dart 客户端处理真实测试响应。覆盖配置、文件夹、额度及 C03 目录/价格/汇率的首批源码场景，不能替代正式制品/真机或完整 C01–C13 验收；命令不触发远程部署/迁移。
- App 兼容 CI 定义：`.github/workflows/app-compatibility.yml`，固定检查名 `App compatibility (Windows)`；Windows/Node 22/pnpm 11.9.0/Flutter 3.44.7，完整获取标签、锁定安装依赖并构建 auth-core 后执行源码合同。覆盖目标 dev/main 的 PR 和 dev/main push，不设 PR 路径过滤；开发分支 push 不触发此兼容工作流，已有 PR 的后续提交仍触发 PR 检查。2026-10-13 已按用户授权删除远端规则集 24904725，兼容检查保留为异步反馈，不再作为 dev/main 推送或合并的强制门槛；无部署权限或业务 Secret。工作流定义、本地冷启动通过、GitHub 托管运行通过和分支 required check 生效是独立状态，不得混报；见 v1.1.2 兼容文档。
- 依赖方向检查：`pnpm lint`
- Workers 测试：`pnpm --filter @kando/workers-api test`；默认命令仅追加 `**/.wrangler/**` 排除规则，避免生成的发布包/诊断被误扫，不删除历史材料、不缩减其他既有测试范围。
- Admin 测试：`pnpm --filter @kando/admin-web test`
- Flutter 依赖：`flutter pub get`
- Dart/Flutter 分析：`dart run melos run analyze`
- Dart/Flutter 测试：`dart run melos run test`

GitLab Flutter CI 使用 3.44.0，GitHub iOS CI 使用 3.44.7。涉及工具链或 iOS 构建时以目标流水线为准；需要统一版本时，明确选择并同步修改所有约束。

## 架构约束

- `apps/` 可以依赖 `packages/`，`packages/` 不得反向依赖 `apps/`；`pnpm lint` 强制检查此规则。
- 共享 API 路由组合位于 `apps/workers-api/src/app.ts`，当前业务路由挂载在 `/api/v1`；后续确需不兼容协议时只新增受影响的 `/api/v2` 接口，并保留 V1，具体遵循下述 App 兼容规则。Cloudflare 入口是 `src/index.ts`，Linux 入口是 `src/linux/server.ts`。
- Cloudflare prod Admin 有两个独立静态发布目标：Pages `toccards-admin`（`admin.tcgcard.fun`，production branch=main）与 Workers assets 副本（`api.tcgcard.fun`）。只运行 Workers 的 `deploy:prod` 不会更新 Pages；只发 Admin 时不得夹带当前 dev 的后端增量。两端均须核对产物哈希及对生产 API 的跨域/鉴权边界。Linux 托管方式见 `deploy/linux/`。
- PostgreSQL schema/migration 与 Hyperdrive binding 是数据库产品和基础设施契约；新增 schema 变更只允许写入 `apps/workers-api/src/db/postgres/migrations/`。修改前必须读取相关实现和文档，并先向用户说明影响。
- 服务端授权、账号归属、资产隔离和购买权益必须由可信服务端数据验证，不能信任客户端自报状态。
- Singular 商品准入的新增／重新审批收入事件名最多 32 个 ASCII 字符，以英文字母开头，仅含字母、数字和下划线；后台回显当前环境／Bundle 已保存的名称，历史较长值保持可读且不自动截断。仅收紧新写入，不能因此破坏旧商品购买／恢复或清空历史收入映射，见 `docs/releases/v1.1.2/03-data-api/subscription-display-config.md`。
- 后续app所有轻提示框不在使用底部提示框，使用项目组件中的顶部提示框组件；项目组件中有不同类型的顶部提示组件，使用时需区分使用类型。
- iOS 内部测试包使用 Bundle ID `com.kando.kandoApp.beta` 时，最终签名 entitlement 的 App Attest 环境必须为 `development`，不得交付 `production`；必须解包检查最终 IPA，不能只看 Xcode 工程设置或描述文件允许值。其他 Bundle ID 的 App Attest 环境暂不固定。
- iOS IPA 和 dSYM 统一保存到 `~/Downloads/CardAI-Packages/<Bundle ID>/`，下面按 `CardAI-Test-<版本>-<构建号>` 或 `CardAI-Prod-<版本>-<构建号>` 建版本目录。测试包保留最近保存的 3 个版本，正式包保留 7 个版本；新版本完整保存并校验后，才将同一 Bundle ID 下超额的最旧版本移入废纸篓。使用发布脚本的自动保存流程；此保留规则不清理 Xcode Archives。

- 2026-10-16 动态订阅准入：超级管理员按 APP_ENVIRONMENT:APPLE_IAP_BUNDLE_ID 审批，复用 PostgreSQL app_config 保存长期准入并事务注册 billing_product；旧环境名单保留为兼容基线。新增商品不得自动跨 dev/prod 批准，不把 Apple Sandbox 当作业务环境。API／Admin 已由既有 watcher 发布干净的 dev@06f420a，并独立核对运行文件、数据库和 HTTP；私有配置与原 PostgreSQL 18 卷保留，ledger 15 项／最新 0014，无待执行迁移。Page／Modal 未启用，cardx.month 仍待超级管理员审批。Flutter 动态注册源码需新的测试包；旧包恢复新 SKU 的限制、真实交易与真机验收边界保留，prod 未修改。详见 docs/releases/v1.1.2/05-delivery/VERIFICATION.md#subscription-dynamic-dev-release。

## App 向后兼容

- 本节约束后续开发；仅确认或落实规则时，只维护规则及文档入口，不修改业务代码或主动补测。具体功能需求、已证实且属于当前任务的兼容 BUG，或用户明确的补测要求，才触发相应开发与验证；覆盖缺口不等同 BUG 或自动整改清单。
- 人员阅读入口：[App 向后兼容开发规则](docs/releases/v1.1.2/05-delivery/app-backward-compatibility-plan.md)；AI 涉及 App API、共享数据或协议修改前，必须读取 [AI 执行版](docs/releases/v1.1.2/03-data-api/app-backward-compatibility-ai-guide.md)及受影响业务契约。
- 以现有 V1 对外约定为基础；新增请求字段可选且缺省保持旧行为，新增响应字段须能被旧 App 忽略。必须改变旧约定时局部新增 V2，同时保留 V1，不因新 App 发布而整体升级 API。
- 旧 App 原有功能、账号隔离和权益保持正确；旧编辑不能清空未提交的新版属性。没有已证实兼容问题时，不批量重写旧接口或自行增加发布门禁。
- 按用户要求完成开发和必要文档修改后再测试，只验证受影响功能及共享调用方；BUG 的定位证据和修复验证时序按 AI 执行版说明处理，未运行项不得记为通过。

## 文档真源

根 `README.md` 是项目入口，详细实现文档按发布版本归档：

- `docs/releases/v1.0.0/00-product`：11 份原始 PRD，只读保留。
- `docs/releases/v1.0.0/01-flows` 至 `04-admin`：v1.0.0 实际业务与工程基线。
- `docs/releases/v1.1.0/00-product`：三份初始 PRD、两份订阅升级降级补充和一份收藏待编辑/卡牌详情改版 PRD，共六份产品输入，只读保留。
- `docs/releases/v1.1.0/01-flows` 至 `05-delivery`：相对 v1.0.0 的开发归档、架构、数据/API、Admin 和交付证据；未验证边界按原记录保留。
- `docs/releases/v1.1.1/README.md`：2026-10-09 起的开发归档入口；`docs/releases/v1.1.1/03-data-api/app-compatibility-contract.md` 和 `docs/releases/v1.1.1/05-delivery/app-compatibility-acceptance.md` 定义从 App 1.0.4 起的服务端兼容目标与待执行门禁，尚非已验证实现。`docs/releases/v1.1.1/01-flows/scan-recognition.md` 记录 2026-09-29 扫描 R2/向量并行的本地实现、失败补偿及批量额度边界，已通过相关本地与 PostgreSQL 多连接验证，2026-09-29 已自动发布 Linux dev，2026-10-08 随 `main@61b5420` 部署 prod；真机批量验收仍未完成。历史契约、故障与发布证据保留原路径及未验收边界。
- `docs/releases/v1.1.2/README.md`：当前增量开发入口；App 兼容只维护 `05-delivery/app-backward-compatibility-plan.md` 阅读版与 `03-data-api/app-backward-compatibility-ai-guide.md` AI 执行版。测试入口、覆盖缺口和必要证据摘要集中在 AI 执行版，不新增独立兼容说明／验证文件；正式制品/真机与完整兼容验收仍待执行。Admin 订单统计新增按筛选结果汇总的 USD 金额，已退款订单不计入订单金额、单列退款金额，缺失金额分别提示；契约见 `docs/releases/v1.1.2/04-admin/admin.md`，本地验证与部署状态以[其他业务验证记录](docs/releases/v1.1.2/05-delivery/VERIFICATION.md)为准。后续实际需求按版本目录维护，未变化内容引用历史基线。
- App 1.0.6 订阅配置的 PRD 1.14、商品接入映射和最小实施草案见 [订阅配置产品输入](docs/releases/v1.1.2/00-product/admin-subscription-config-prd.md)；[离线原型](prototypes/admin-subscription-config-standalone.html)保留在正式 docs 之外。服务端第一阶段源码与环境／接口合同见 [订阅展示配置与商品准入](docs/releases/v1.1.2/03-data-api/subscription-display-config.md)。Admin 页面实现见 [当前后台文档](docs/releases/v1.1.2/04-admin/admin.md)，Flutter 消费源码与兜底／平台边界见 [客户端订阅展示](docs/releases/v1.1.2/01-flows/subscription-display.md)；2026-10-15 已基于干净的 `850e339` 在目标 macOS 15／Flutter 3.44.7／Xcode 16.4 CI 完成默认 production 无签名 Release 编译，run `38669374723` 成功且 iOS 锁文件无漂移。真实新商品接入、签名 IPA／App Attest、真机、iOS 版本运行时分支及旧包新增商品支持仍未验收，未远程迁移或部署，不能写成已发布功能。

`docs/releases/v1.0.0` 是已发布冻结基线，后续迭代不得回写；若需修正已经确认的文档错误，必须先说明原因并获得用户明确授权。11 份原始 PRD 包括 `glossary.md`、`overview.md`、`ui-design-system.md` 和 `00-product/modules/` 下的 8 份模块文档，必须保持字节不变，不得因当前实现或后续需求而修订。

实现文档以对应版本代码、迁移和运行配置为准。v1.1.0 与 v1.1.1 开发记录已原位归档；后续 v1.1.2 的新增、变更、移除及实现结果按需写入 `docs/releases/v1.1.2/`，未变化部分引用 v1.1.1、v1.1.0 或 v1.0.0。旧版本的补充验收在当前版本按新日期补证并链接原检查点，不覆盖历史结论；归档不等于设计实现、外部验收或商店发布通过。不要新增执行日志、任务状态快照、交接文档、生成截图或原始设计素材到 `docs/`。

Flutter UI 变更前必须阅读 `docs/releases/v1.0.0/00-product/ui-design-system.md`，并优先复用现有组件、颜色、间距和交互模式；若 v1.1.0/v1.1.1 基线或 v1.1.2 有明确增量契约，同时读取对应版本文档。

## 安全边界

- 未经明确授权，不执行 Git push、部署、远程数据库迁移、生产写操作或发布。
- 生产环境受保护；必须区分本地验证、dev 部署和 prod 部署。
- 数据库 schema、PostgreSQL migration、Hyperdrive/KV/R2 binding 变更需先说明兼容性、回滚和环境影响。
- 保留用户已有改动和未跟踪文件；不要清理、覆盖或回退不属于当前任务的内容。
- 禁止使用破坏性 Git 命令，除非用户明确指定并已核对精确目标。

## 验证规则

验证范围应与改动风险匹配：

- 文档或 Agent 规则：检查路径/链接、`git diff --check` 和残留引用；无需强制全仓构建。
- Admin：运行相关测试、`type-check`，需要交付构建时再运行对应 build。
- Workers：运行相关测试和 `type-check`；涉及打包或部署配置时运行 dry-run build。
- Flutter：运行相关测试和 `flutter analyze`；跨包变更使用根 Melos 命令。
- 共享边界、依赖或 CI 变更：运行根 `pnpm lint`、`pnpm type-check` 及受影响构建/测试。

测试必须保护业务意图和回归风险，而不仅断言实现细节。交付时分别报告通过、失败和未运行的检查。

## BUG 修复

本节是所有 `BUGFIX` 的修改硬规则；简单 BUG 可以使用轻量记录，但不得跳过定位、验证和 Code Review 门禁。

#### 定位阶段

- **复现优先**：修复前必须先确认实际行为、期望行为和稳定复现路径，记录环境、版本、输入、触发条件、频率及适用的日志/堆栈。无法复现且证据不足的 BUG 不得凭猜测直接修改；只能继续收集证据、增加不改变业务行为的诊断，或将任务标记为 `BLOCKED`。
- **读上下文**：定位到目标代码后，必须阅读目标文件完整相关部分、导出接口、直接调用方、公共工具、相关配置、数据/接口契约和已有测试，理解代码为何这样设计后才能修改。
- **查关联**：确认问题是否影响其他模块、调用入口、平台/版本、缓存/并发、数据一致性、权限、安全或已有测试，列出可能受影响范围和明确不受影响范围；不得把第一次发现的异常位置直接当作完整影响面。
- **证实根因**：使用失败测试、最小复现、日志、堆栈、调试、二分或代码路径建立根因证据；相关性、时间先后或“修改后不报错”都不等于根因。
- **先失败证据**：优先在修改前建立能暴露问题的回归测试或可重复最小复现，并确认其在修复前失败。无法获得失败测试时必须记录原因和等价证据，禁止省略后假称已验证修复意图。

#### 修复阶段

- **最小修改**：只修复当前 BUG，不顺手重构、不扩展功能、不改变未批准行为、不引入当前修复不需要的新抽象。
- **外科手术式**：修改范围严格限定在 BUG 根因及直接关联代码；不碰无关逻辑、格式、依赖、生成物和元数据。必须修改共享代码时，说明为什么局部修复不足以及受影响调用方。
- **针对根因**：修复必须恢复既定预期行为，不得只绕开复现输入、针对单个样例硬编码、扩大重试或用默认值遮住根因。
- **不掩盖问题**：禁止通过注释/删除检查、跳过或放宽断言、吞异常、屏蔽日志、禁用测试、无条件返回成功等方式让 BUG “看起来”通过。
- **保持契约**：接口、数据口径、错误语义、权限、兼容性和平台行为默认保持不变。若修复必须改变其中任一项，必须停止并转为 `ITERATION` 或请求有权人员确认，不能以 BUG 名义绕过范围控制。

#### 验证阶段

- **回归验证**：修复后必须使用修复前相同的环境、输入和触发条件重新执行原始复现路径，确认实际行为恢复为预期；只运行新测试或只观察“不再报错”不等于原问题已解决。
- **回归测试**：修复前失败的测试必须在修复后通过；新增/修改测试必须表达该 BUG 所破坏的业务意图，并证明删除修复或恢复错误逻辑时会失败。
- **影响面验证**：按定位阶段列出的范围验证直接调用方、相关模块、相邻分支、边界条件、受影响平台/版本和已有测试，确认修改没有引入回归。
- **最窄到扩展**：先运行最小复现和针对性测试，再按影响范围运行格式/静态/类型检查、单元、集成、端到端、构建或平台验证；验证规模与风险相称，不能用一个窄测试替代已识别的跨模块风险。
- **显式记录**：实际执行的命令、环境、退出状态和关键结果必须记录。因设备、账号、权限、外部服务或其他条件未执行的验证，必须逐项列出未运行项、原因、影响和需要谁补验，禁止标记为通过。
- **强制 Code Review**：每次完成 BUG 修复代码或审查返工修改后必须执行 Code Review。审查未通过或审查后代码再次变化时，必须重新运行受影响验证并重新审查；未审查不得标记 `COMPLETED`。

#### 文档与记录

- 修复导致接口、配置、行为、Schema、架构、部署、运维或用户操作方式变化时，必须在同一任务中更新 `docs` 下相关文档或项目既有等价位置；不得等全部编码结束后补写。
- 每个 BUG 必须在 Issue、任务系统、提交说明或当前版本既有业务文档中记录根因、证据、修复方式、影响范围、验证结果、Code Review 结论和未验证项，保证后续可追溯。v1.1.2 的 App 兼容补证集中合入 AI 执行版，不再新建独立兼容验证文档。
- 文档影响不存在时必须记录 `N/A` 及理由，不得为了满足流程创建无业务价值的重复文档。简单 BUG 若已由 Issue、提交和回归测试完整追踪，不强制新建独立工作项目录。
- 文档只描述实际修复后的当前行为，不得把猜测根因、未执行验证或计划中的后续改进写成已确认事实。

# Linux 测试环境与 Cloudflare 正式环境兼容设计

## 状态

- 当前后端适配：2026-09-15，`dev-inner` 基于 `dev@b941a3f`；原始设计基线为 2026-08-26 的 `dev@8e22c1d`。
- 合并状态：`19a6ac4` 引入 Linux 基础部署；2026-09-16 的 `75c0ec4` 已将 HTTP 向量、App/Admin 内网入口和发布预检整改合入 dev，并保留原后台筛选增量。
- 2026-09-17 回读 kd201：watcher 发布的 `dev@4d5d66f` 正在运行，manifest、部署状态和 API/Admin 实际产物一致；PostgreSQL 18.6 的 ledger 为 13 项，发布前备份目录可读取，未做恢复演练。此前手工 ESM 修复现已包含在自动发布版本中，详见[退役验证](../05-delivery/VERIFICATION.md#旧-cloudflare-dev-业务退役2026-09-17)。
- 受控扫描、幂等扣次与本地收藏/初始价格事件写入均通过；App test/Admin development 和 `deploy:dev` 已统一到 Linux。Apple Sandbox 官方 TEST 已经由独立公网回调进入 Linux 并成功处理。用户确认两端客户端路径已测试无问题，本次未独立重跑真机；指定交易的统计后台收件和完整生命周期矩阵仍单独验收。
- 2026-09-17 已删除旧 `toccards-api-dev` Worker、`api-dev.tcgcard.fun` 自定义域名及唯一 cron；旧测试数据和包保留。正式 API、共享 CF 向量识别和独立 Apple 回调保持运行。
- 2026-09-16 配置增量：原 CF dev 的 Google/App Attest/邮件公开配置及 Apple 官方根证书已落入 Linux；API 通过 Node 22.22.1 原生环境代理访问外网，Google 网络验证通过，CF 向量服务和内网仍直连。私密凭据、公网通知入口与真机缺项集中维护在[开发计划](../05-delivery/development-plan.md#linux-dev-集中处理清单2026-09-16)。
- 同日已将用户提供的原始 ZeptoMail Token 写入服务器私有配置，唯一一封注册验证码测试邮件由用户确认收到；邮件凭据缺项解除，完整注册与找回密码流程未验收。
- Apple Server API 的三项 dev 凭据也已配置，项目客户端从实际 API 容器查询 Sandbox 通知历史返回 200；私钥解析与验签器构造通过。公网 Sandbox TEST 已验收；真实购买/恢复与交易校正仍待独立验收。
- 2026-09-17 已部署独立 CF Apple Sandbox 回调代理并绑定 `dev-callback.tcgcard.fun`，仅允许通知路径 POST；该 Worker 无业务数据库或 Apple 私钥绑定。用户保存 DNS-only 回源 A 记录与 Apple Sandbox URL 后，官方 TEST 已送达 Linux；修复 ESM 包加载 Apple SDK 问题并重处理原通知后，Sandbox/beta 的 inbox 和结构化 `TEST` 记录均为 `processed`，见[代理配置](../../../../deploy/cloudflare/apple-callback/README.md)及[验证记录](../05-delivery/VERIFICATION.md)。
- 同日公网映射变更曾使 Worker 回源 502、Apple TEST 投递超时并触发限流；网络恢复后新发一条 TEST，Linux 于 `06:10:48Z` 将其验签并处理，随后真实 `DID_CHANGE_RENEWAL_STATUS` 也处理成功。Apple 官方投递状态查询仍受 429 限制，未取得本条 SUCCESS 回执；本次接收与验签证据见[验证记录](../05-delivery/VERIFICATION.md)。
- 同日已在 kd201 宿主机部署独立回调网关与 nftables 预路由：公网到 `201:8080` 的 IPv4 请求先转到仅允许 Apple Sandbox POST 的 `8081`，私网仍直接使用 `8080`。源站公网的 Admin/其他 API 路径及伪造 Host 均被拒绝，CF 回调和内网 API/Admin 保持可用；宿主机规则独立于 Docker/自动发布，详细边界与回退见[回源隔离策略](../../../../deploy/linux/security/README.md)。CF→origin 仍是 HTTP。
- 网关启用后新增的一条官方 Apple Sandbox TEST 已获投递 `SUCCESS` 回执，JWS 摘要与 Linux 新增且处理成功的 inbox 一致；该 TEST 不创建交易，详见[验证记录](../05-delivery/VERIFICATION.md)。
- 同日已将旧 CF dev 公共配置下发的 Mixpanel Project Token、Singular API Key/Secret Key 同步至 Linux 私有 `.env`；用户随后提供与原 dev Token 匹配的 Mixpanel API Secret，也已加入 Linux 私有配置。两次均只重建 API，iOS/Google 的三项公开值与旧 dev 相同且不下发 API Secret；当前代码未使用后者。Linux 容器使用该 Secret 的 Mixpanel 只读导出返回 200，并回读到 App 类事件；指定测试订阅的事件归属和 Singular 后台收件仍未验收。
- 环境边界：Linux 使用独立测试 PostgreSQL；Cloudflare dev/test 与 prod 已完成 PostgreSQL 迁移且无 D1 binding，不存在待执行的 prod D1 切换任务。

## 背景与架构纠正

最新 `dev` 已完成 PostgreSQL/Hyperdrive 切换。运行入口通过 `HYPERDRIVE.connectionString` 创建现有 `PostgresDatabase`，业务路由仍调用统一 `Database` 契约。仓库规则明确禁止为 v1.1 新增或恢复 D1 路径。

因此 Linux 测试环境不再采用旧讨论中的 SQLite 方案，而是连接一个独立 PostgreSQL 容器。Cloudflare 与 Linux 共享同一个 `PostgresDatabase`、同一套 PostgreSQL migration、全部 Hono 路由和业务规则；差异只存在于运行入口、资源适配器和配置文件。

## 目标

1. 现有 dev 业务部署迁至 Linux，保持原 test/development 环境身份，不新增长期并行的第三套环境；prod 继续使用 Cloudflare。
2. Linux 使用独立 PostgreSQL、内存 KV 与本地扫描图片目录，向量检索复用现有 CF `recognize-vec/Vectorize`。
3. Cloudflare prod 继续使用 Hyperdrive、KV、R2、Workers Assets 和 Cron Triggers；旧 CF dev 业务部署已退役，历史测试数据保留。
4. 后续业务版本只开发一套路由、SQL 和业务逻辑。
5. Linux 业务读写不连接正式 PostgreSQL、R2 或 KV；按用户明确方向，仅复用 CF 的只读向量识别服务，其他外部服务使用相应测试配置。

## 非目标

- Linux 实例升级没有修改 Cloudflare 业务数据库；后续独立退役仅删除旧 dev Worker、业务域名和 cron，未删除历史数据或 prod/向量/回调资源。D1 已退役，不属于发布或回滚目标。
- 不新增 D1、SQLite、Miniflare 数据库回退路径。
- 不在第一版引入 Redis、MinIO、Kubernetes 或多 API 副本。
- 不在仓库提交 Linux 服务器真实域名、密码、Token 或证书私钥。

## 总体结构

```text
共享应用与业务代码
├── Hono routes / middleware
├── PostgresDatabase
├── PostgreSQL migrations
└── OAuth / Mail / Billing / Scan / Admin contracts

Cloudflare 运行时
├── Hyperdrive -> PostgreSQL
├── Workers KV
├── R2
├── Workers Assets
└── Cron Triggers

Linux 测试运行时
├── Node.js HTTP server -> PostgreSQL container
├── In-memory KV adapter
├── Local filesystem object-storage adapter
├── HTTP vector adapter -> CF recognize-vec / Vectorize
├── Caddy or offline Node server -> Admin SPA + API reverse proxy
└── Node interval -> scheduled jobs
```

## 共享代码边界

### Hono 应用

路由注册、CORS 和 `runScheduledTasks` 已抽取到 `apps/workers-api/src/app.ts`。Cloudflare 入口 `src/index.ts` 和 Linux Node 入口 `src/linux/server.ts` 调用同一个 Hono app，不复制 API 路由。

允许来源由 `ALLOWED_ORIGINS` 配置覆盖；未配置时继续使用当前 Cloudflare 默认列表，保证现有部署行为不变。

Linux 单文件 ESM 构建在 `linux-build-options.mjs` 中通过 `createRequire(import.meta.url)` 提供 CommonJS 加载器，使 Apple SDK 的 `node-fetch` 等依赖可加载 Node 内置模块。`build:linux:api` 构建前运行独立 bundle 回归：使用真实 Linux 配置适配与官方 SDK，在仓库外的 Node 子进程验证通知/交易验签器及 Server API 客户端初始化，并确认无效 JWS 仍被拒绝；测试不连接数据库或 Apple 服务。Cloudflare 继续由 Wrangler 和 `nodejs_compat` 构建。

### PostgreSQL

Linux 直接复用 `apps/workers-api/src/db/postgres-database.ts`：

- Cloudflare 从 Hyperdrive binding 取得连接串。
- Linux 从 `DATABASE_URL` 取得连接串。
- 两者执行 `apps/workers-api/src/db/postgres/migrations/*.sql`。
- 后续不得创建 Linux 专用 SQL 或 SQLite migration。

### KV

Linux 第一版使用带 TTL 的进程内 KV，只实现当前业务使用的字符串 `get` 和 `put`。服务重启后缓存清空是允许行为；数据库和业务结果不能依赖缓存持久化。

### 扫描图片

Linux 使用本地文件目录代替 R2，实现当前使用的 `put/get/delete`。对象 key 与 Cloudflare 保持一致，数据库继续保存对象 key。文件目录通过 Docker volume 持久化。

### 扫描兼容缺口

`src/scan/routes.ts` 只接受 512 维 `vector`，并通过 `Env.VECTOR_RECOGNITION.fetch()` 调用检索服务。Cloudflare 继续使用 Service Binding；Linux 的 `src/linux/config.ts` 通过 `vector-recognition.ts` 构造 HTTP 适配，目标为 `VECTOR_RECOGNITION_BASE_URL` origin 下的 `/recognize`。共享路由只发送 `{vector}`，不向识别服务转发图片、用户 token 或业务数据库请求；候选资料、游戏过滤、额度与扫描记录使用 Linux 的 `DB`。

HTTP 适配的 10 秒超时持续覆盖响应正文，并保留调用方取消，不重试或跟随重定向。上游 HTTP 失败、无效 JSON 或超时沿用共享路由的 `502 VECTOR_RECOGNITION_UNAVAILABLE`、审计失败记录与释放额度；无匹配或本地目录不可用不错误扣次。缺少 binding 的既有受控 `503` 分支保留。旧 `OCR_SERVICE_BASE_URL` 已从运行时配置和 `Env` 移除，不再作为回退。

此前“必须独立部署向量服务、不得复用 CF 识别”的设计已被 2026-09-15 用户明确的整改方向替代：dev 业务本地化，识别继续使用现有 CF 服务。本次已从 kd201 验证 CF 出站与实际响应，并经内网 API 验证合成图片/512 维向量的完整服务端链路；它不覆盖两端模型推理、真实图片准确率或真机局域网权限。

### 定时任务

Cloudflare 保留 5 分钟 Cron Trigger。Linux 入口使用单进程 interval 调用同一组通知重试与 Server API 校正函数，并禁止任务重叠执行。

### Admin 静态资源

Admin 继续构建同一份 React/Vite 应用：

- Cloudflare 使用 Workers Assets。
- Linux 标准模式使用 Caddy 托管 SPA，并将 `/api/*` 与 `/share/*` 转发给 Node API；离线模式使用 `deploy/linux/offline/web-server.mjs`，仅开放 HTTP，HTTPS 需由入口反向代理处理。
- Admin development 和原 Linux 构建均使用同源相对路径 `/api/v1/admin`，本机 Vite 将 `/api` 代理到 `http://192.168.50.201:8080`；production 继续使用原 CF 生产 API。
- 离线 Node 代理保留请求的外部 Host，使分享 canonical/og:url 使用访问者实际请求的 host/port，不再生成 `api:3000` 内部地址。本阶段使用内网 HTTP；尚未新增 HTTPS 网关或对任意转发头的信任。

### App 测试入口与平台网络策略

Flutter 继续以 `APP_ENV=test` 代表现有 dev，默认业务 origin 为 `http://192.168.50.201:8080`，API 路径为 `/api/v1`；`APP_ENV=production` 和未配置值维持原生产 HTTPS API。测试分享由相同 origin 派生 `/share/cards`，即使复制的数据库下发生产分享地址，测试 App 也使用内网地址；production 继续优先采用服务端分享配置。目录卡牌图片仍由原 `image.tcgcard.fun` 提供。

Android 从 Flutter 传给 Gradle 的 `APP_ENV` 参数选择 network security config，仅 test 对 `192.168.50.201` 允许 HTTP，其他目标禁止明文。iOS 的三个既有 test flavor 配置使用独立 `Info-test.plist`，仅添加该 IP 的 ATS 例外及局域网权限说明，生产 plist 不变；测试保护两个 plist 的其他字段一致。iOS 17+ 的 ATS IP exception 和 iOS 16 的 IP 直连规则不同，需在对应设备验证；本机源码检查不能代替签名 IPA 与真机权限验收。

iOS IP 访问规则依据 Apple 的 [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking) 与 [NSExceptionDomains](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains)；本次没有使用全局 `NSAllowsArbitraryLoads`。

## 配置边界

Linux 真实配置存放在服务器 `.env`，仓库只提交 `.env.example`：

```dotenv
LINUX_TEST_SITE_ADDRESS=http://192.168.50.201
POSTGRES_DB=toccards_test
POSTGRES_USER=toccards
POSTGRES_PASSWORD=replace-me
DATABASE_URL=postgres://toccards:replace-me@db:5432/toccards_test
PORT=3000
ALLOWED_ORIGINS=http://192.168.50.201:8080,http://localhost:3000,http://127.0.0.1:3000
OBJECT_STORAGE_PATH=/data/scan-images
VECTOR_RECOGNITION_BASE_URL=https://recognize-vec.tcgcard.fun
JWT_SECRET=replace-with-independent-test-secret
SCHEDULED_TASK_INTERVAL_SECONDS=300
APP_ENVIRONMENT=development
```

OAuth、Apple、ZeptoMail、Mixpanel 和 Singular 配置全部使用测试凭证。缺失的可选外部配置保持现有受控错误语义，不允许回退到 Cloudflare 正式值。

受限网络可在 API 启动环境中设置 `NODE_USE_ENV_PROXY=1`、`HTTP_PROXY`/`HTTPS_PROXY` 和 `NO_PROXY`，要求 Node 22.21.0+。这是 Linux 运行配置，不改变共享 OAuth 路由或 Cloudflare 构建。kd201 使用已验证的混合代理端口的 HTTP CONNECT 模式，数据库和 CF 向量识别保留直连；配置、回退和验证限制见[运维手册](../../../linux-test-environment/README.md#外部服务配置与代理)。

`VECTOR_RECOGNITION_BASE_URL` 必须为无凭据、路径、查询参数或 fragment 的 HTTP(S) origin；缺失或非法时启动失败。Linux 只接受 `APP_ENVIRONMENT=development`。升级前需补齐新键；如需回滚旧代码，可在过渡期保留旧 OCR 键或恢复旧版 `.env`，新代码不会读取该旧值。

## 数据与安全隔离

- PostgreSQL volume、扫描图片 volume、JWT secret 和外部服务凭证均为 Linux 测试专用。
- PostgreSQL 默认仅映射宿主机回环地址 `127.0.0.1:15432`；开发机直连时可显式设置可信局域网 `POSTGRES_LISTEN_ADDRESS`。2026-09-15 已再次从局域网只读查询 kd201 的 `192.168.50.201:15432`，发布保留该映射和原数据库卷。
- API 不直接发布宿主机端口；Web 入口与上述受限 PostgreSQL 端口由 Compose 管理，数据库不得映射到公网。
- migration runner 使用独立 ledger 表记录已执行的 PostgreSQL migration。
- Linux 环境禁止配置正式 PlanetScale/Hyperdrive 连接串。

## 日常发布流程

```text
开发共享功能
→ 构建并部署整改后的 Linux dev
→ 完成受影响功能验收
→ 按发布授权使用同一套业务代码发布 Cloudflare prod
```

只有基础设施接口新增能力时才需要同时扩展 Cloudflare/Linux 适配器。普通 API、页面、业务规则和 PostgreSQL migration 只实现一次。App/Admin 默认入口与 dev 发布指令已整改：`deploy:dry-run:dev` 只生成 Linux 发布包，`deploy:dev` 通过显式 SSH 目标调用既有版本化发布脚本；预检配置、本地数据库和 CF 识别后，先备份再迁移/发布。Linux 发布检查覆盖全部 `src/linux`、PostgreSQL 扫描路由、离线代理及发布预检/备份回归。服务器现已通过 dev 监听器自动发布合并后的整改版本，见[自动部署手册](../05-delivery/linux-test-auto-deployment.md)。

## 验收范围

按根 `AGENTS.md` 从复现和最窄验证开始，再覆盖受影响面；BUGFIX 必须先建立失败证据：

- Node API 启动、健康检查和 CORS
- PostgreSQL migration 与现有 `PostgresDatabase`
- 登录、资产、卡牌、扫描和 Admin 的代表性请求
- 内存 KV TTL
- 本地扫描图片写入、读取和删除
- CF HTTP 识别成功、失败、超时和无匹配时，本地候选资料、扫描记录与额度结果正确；实际服务与设备链路单独验收
- Linux scheduled jobs 不重叠
- Admin SPA 同源 API 代理
- Cloudflare prod/dev dry-run 仍通过

Flutter UI、iOS/Android 打包和未涉及页面不属于本任务验证范围。

## 完成标准

- Linux 可通过一条 Docker Compose 命令启动完整测试环境。
- Linux 与 Cloudflare 使用同一套业务代码和 PostgreSQL migration。
- HTTP 向量适配完成后，扫描端到端验收通过；当前仅完成本地后端验证，设备与部署验收尚未满足。
- Linux 重启后 PostgreSQL 数据和扫描图片保留，内存缓存允许清空。
- Linux 不依赖 D1、Hyperdrive、Cloudflare KV 或 R2。
- Cloudflare prod 与共享识别服务保持独立；旧 CF dev 主 Worker 业务入口与 cron 已退役，自动部署入口为 Linux watcher 和显式 SSH 发布。

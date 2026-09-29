# v1.1.1 验证记录

本文件只记录实际取得的证据；运行配置核查不等于业务兼容、性能优化或发布验收通过。兼容验收范围仍以 [App 兼容验收矩阵](app-compatibility-acceptance.md) 为准。

## 2026-09-28：生产 Placement 试验前置核查

### 范围与结论

用户批准“观测与缓存核查 + 独立 Placement 试验”小阶段。本轮完成生产配置与平台指标只读核查；由于历史观测查询权限不足，以及共享业务 Hyperdrive 查询缓存开启的正确性风险尚未处置，**前置门禁未通过，未部署 Placement**。

未修改业务代码、Wrangler 配置、缓存开关、绑定、连接池、数据库或权限；未执行 Git 提交/推送、生产业务请求造数、SQL、migration 或部署。凭据仅通过现有 Wrangler 会话在内存中使用，未输出或保存到本记录。

### 已确认的环境与配置

- 本地：Windows / PowerShell、Node 22.20.0、Wrangler 4.106.0；核查开始时工作区干净，分支 dev，HEAD 为 7982c1622a693a6a4b0a0dc137f1d682bc8f50c6。
- 本地 apps、packages、锁文件及根 Node 配置与已记录生产源码 7868f4c 的比较无差异；这不代替远端配置回读。
- 生产 Worker：toccards-api-prod；deployment 35134321-a835-405d-8558-893dab13d0f5；version 6be8c5f9-60dd-499b-b19f-23d4fa6ac7c4 承载 100% 流量。未创建新版本。
- Worker settings 于 2026-09-28 16:51:27（北京时间，UTC+08:00）回读：placement 为 {}，未声明 Smart 或显式 Placement；compatibility_date 为 2024-11-01，flag 为 nodejs_compat。
- Observability 配置：enabled=true，head_sampling_rate=1；logs.enabled=true、persist=true、invocation_logs=true；traces.enabled=false。这里只确认配置，不宣称历史数据完整可查询。
- 关键绑定仍为 HYPERDRIVE、CACHE_KV、SCAN_IMAGES、VECTOR_RECOGNITION；向量服务目标 recognize-vec / production；未发现 D1 绑定。
- Hyperdrive：tcg-cards-db，ID 7d71bcd0bcf64e518a23a852ced76d66；origin.scheme=postgres，host=aws-us-east-1-5.pg.psdb.cloud，port=5432。主机名提供 AWS us-east-1 区域线索，本轮未独立登录 PlanetScale 控制台核验区域元数据。
- Hyperdrive caching.disabled=false，origin_connection_limit=100。返回的 caching 对象只包含 disabled，本记录不将未返回的 TTL 字段写成实测值。

### 最新平台基线及限制

GraphQL 查询范围：UTC 2026-09-28T06:30:00Z 至 2026-09-28T08:45:00Z，即北京时间 14:30 至 16:45；于 16:51 回读。Workers 数据限定上述生产 Worker 和 version，Hyperdrive 数据限定上述 config ID。

| 指标 | 实际结果 | 解释边界 |
|---|---|---|
| Workers 成功调用 | 2,636 次 | workersInvocationsAdaptive；未按接口或事件类型分组，不能当成某个 API 的样本 |
| requestDuration P50 / P95 | 927.784 / 3,146.644 ms | 原始微秒值分别为 927784 / 3146644；不是客户端端到端耗时 |
| wallTime P50 / CPU P50 | 927.931 / 7.625 ms | 不据此估算每条 SQL 的延迟 |
| Hyperdrive uncacheable | 12,327 次，均为 IAD / complete | 另有 transaction 438 次、notaquery 85 次；本窗口未返回缓存命中分组 |
| Hyperdrive waitingClients 峰值 | 0 | 不支持以本窗口证据要求扩连接池 |

这些是混合调用平台基线，不满足“同接口、同状态、同地区”的 Placement 效果对照条件。本窗口无缓存命中记录也不能证明强一致读取永远不受缓存影响。

### 未通过的前置门禁

1. **历史观测查询不可用。** 对 workers/observability/telemetry/query 执行 dry=true、view=calculations 的临时只读计数查询，2026-09-28 16:51:25 返回 HTTP 403、code=10000、Authentication error。相同现有凭据能读取 Worker settings、deployment 和 GraphQL；本轮没有自动重新登录、创建 token、扩大 OAuth scope 或切换其他凭据。Cloudflare 当前该接口文档要求 Workers Observability Write 权限，现有 Wrangler OAuth 列出的 scope 不含该项。
2. **强一致读取与缓存配置冲突尚未解决。** Cloudflare fetch 入口从同一 HYPERDRIVE 创建 DB，Session、权益和额度等业务共用该连接。当前缓存开启，不符合将该业务连接视为“已禁用查询缓存”的前提。官方说明写入不会自动使旧 SELECT 缓存失效。此处记录的是配置风险，未通过生产写入或撤销 Session 实验复现实际陈旧读取，也不把它确定为本轮延迟根因。
3. **分段计时不是全量分布。** 当前 api_request 在请求完成时记录日志，但历史检索被上述权限阻断；scan_recognize_timing 只记录 total_ms >= 1000 的请求。不能用慢请求分段样本估算全量 P50/P95，也不能在启用 Placement 后仅凭 Worker 内计时降低宣称用户端变快。

### 已执行与未执行的验证

| 检查 | 结果 |
|---|---|
| git status、HEAD/分支及生产源码差异检查 | 通过；核查开始时工作区干净，指定路径比较无差异 |
| wrangler --version / whoami | 退出 0；使用现有 OAuth。工具同时提示缺少其他预期 scope；未按提示自动扩权 |
| wrangler deployments status --env prod --json | 退出 0；回读上述 100% 版本 |
| wrangler hyperdrive get <config-id> --env prod | 退出 0；仅输出非凭据配置字段 |
| Worker settings REST GET | HTTP 200，success=true |
| GraphQL 平台指标查询 | HTTP 200，无 GraphQL errors |
| Observability Telemetry 临时计数查询 | 失败：HTTP 403 / 10000；不能由读取脚本进程退出 0 推断全部接口成功 |
| Node 只读探针首轮 | 本地 CommonJS 顶层 await 语法失败，未发送 API 请求；改为异步函数后完成上述实际读取，不算首轮通过 |
| Placement 配置变更、prod dry-run、部署、切流、回退 | 未执行；门禁未通过，未创建候选配置或版本 |
| Workers / Flutter / Admin 测试与构建 | 未执行；仅配置核查及文档记录，无实现修改，不宣称测试通过 |
| 生产登录态兼容、扫描、购买、缓存陈旧复现与数据库 SQL | 未执行；不在本轮只读核查范围，也未另获生产业务写入授权 |

文档交付检查已通过：git diff --check 退出 0；两份 Markdown 的 UTF-8、末尾换行、行尾空白及 12 个本地链接检查通过；确认实现、Wrangler 和 v1.0.0 / v1.1.0 归档文档未改。Git 仅提示下次触碰 README 时 LF 将转换为 CRLF，没有 diff 空白错误。文档自查保留了 403、缓存风险、未部署和未验证边界，不把本阶段记为性能验收通过。

### 继续试验所需条件

- 账号管理员通过安全的本地凭据配置提供目标账号的 Workers Observability Write 查询权限，或提供覆盖同类接口与地区、未按慢请求阈值筛选的可核验观测数据；不要在聊天或仓库中粘贴 token。
- 单独确认缓存处置方式。建议先关闭现有共享业务 HYPERDRIVE 的查询缓存；本轮只有核查授权，不执行该变更。不因这个建议新增绑定、变更 SQL 或扩大连接池。
- 如果获准改变缓存设置，必须先回读配置、验证正确性并重新建立基线，再开展仅包含 Smart Placement 的独立试验；不得把缓存变更前的数据直接归因给 Placement。
- 前置条件满足后，再在 env.prod.placement 设置 mode=smart，验证 prod dry-run、部署版本、实际放置与同类请求指标，并保留试验前版本/配置的回退证据。原有 Placement 试验授权不包含 Git push、数据库迁移或其他架构优化。
- v1.0.0 / v1.1.0 历史记录保持原样；本核查不覆盖或取消旧版本未验证边界。

### 核查依据

- [Cloudflare Placement](https://developers.cloudflare.com/workers/configuration/placement/)
- [Hyperdrive Query caching](https://developers.cloudflare.com/hyperdrive/concepts/query-caching/)
- [Workers Observability Telemetry Query API](https://developers.cloudflare.com/api/resources/workers/subresources/observability/subresources/telemetry/methods/query/)
- [生产配置](../../../../apps/workers-api/wrangler.toml)、[Cloudflare 入口](../../../../apps/workers-api/src/index.ts)、[请求日志](../../../../apps/workers-api/src/request-id.ts)、[扫描分段计时](../../../../apps/workers-api/src/scan/routes.ts)。

## 2026-09-28 17:04 后：关闭现有查询缓存及浏览器观测补证

本节是新增授权后的补证，不覆盖 16:51 的核查结果。用户随后明确授权“仅关闭当前 HYPERDRIVE 的查询缓存，不新增绑定、不改 SQL”，并允许打开浏览器完成观测访问。

### 实际配置变更

- 只执行一次更新：在 apps/workers-api 目录使用 Wrangler 4.106.0 执行 hyperdrive update 7d71bcd0bcf64e518a23a852ced76d66 --caching-disabled true --env prod。
- 更新前读取 caching.disabled=false；更新后及 17:05:18（北京时间）的独立 GET 均为 caching.disabled=true。服务端 modified_on 返回 2026-09-28T09:04:26.067844Z（北京时间 17:04:26）。
- 更新前后完整返回对象的差异只有 caching.disabled 和服务端维护的 modified_on。源库、端口、用户/数据库配置、mTLS、名称和 origin_connection_limit=100 均未变；凭据字段只在内存比较，不写入记录。
- 更新子命令成功。外层校验脚本最初将 modified_on 的自动更新时间误判为超范围差异，退出 1；没有重发更新命令。根据已输出的差异字段清单确认它是元数据变化，再执行只读回查验证缓存关闭。不得把首次校验脚本记录为通过，也不得把这次告警误记为缓存更新失败。
- 未新增 Hyperdrive 或其他绑定，未修改 SQL/业务代码/连接池，未执行数据库命令或缓存恢复操作。
- 随后 deployments status 再次回读原 deployment 35134321-a835-405d-8558-893dab13d0f5、原 version 6be8c5f9-60dd-499b-b19f-23d4fa6ac7c4 仍为 100%；未部署 Placement，也未修改本地 Wrangler 配置。

### 浏览器观测访问

- 打开 Cloudflare 控制台后，浏览器已具有目标账号的有效登录态，生产 Worker 的 Observability Invocations 和 Visualizations 历史视图可用；无需用户重复输入密码或验证码。
- 没有创建长期 API Token、重新执行 OAuth 授权或扩大权限；没有读取浏览器 Cookie，也没有把浏览器会话转换成 API 凭据。控制台查询全部通过可见 UI 完成。
- 这解除的是“无法取得历史观测”的浏览器访问限制，不代表上一节 Wrangler OAuth 的 Telemetry API 403 已修复。后续若要求自动化 API 查询，仍需单独解决该接口凭据权限。
- 未启用 Workers Traces、Live Tail 或保存长期查询/告警。控制台页面保留在当前聊天，供用户查看。

### 缓存关闭后的首个独立窗口

窗口为北京时间 2026-09-28 17:05–17:09（UTC 09:05–09:09），完全在缓存关闭之后；GraphQL 于 17:12:48 回读。

| 证据 | 实际结果 | 边界 |
|---|---|---|
| 控制台 Visualizations count | 65 条事件 | 是日志事件数，不是 HTTP 请求数 |
| 控制台 Invocations | 32 条 HTTP 调用、1 条 scheduled 调用 | 已读取该窗口的实际列表；不合并缓存关闭前的数据 |
| 目标接口覆盖 | scan/recognize=0、scan/quota/reserve=0、collection/dashboard=1、portfolio/valuation-history=1 | 尚不能估计这些接口的 P50/P95，也不能据此启动有充分基线支撑的效果验收 |
| GraphQL Workers | 33 次 success；requestDuration P50=941.282 ms、P95=5,389.695 ms | 包含定时任务，仍是混合调用分布，不当作某个接口或客户端端到端指标 |
| GraphQL Hyperdrive | 163 次 uncacheable / complete，全部位于 IAD | 未返回失败或缓存命中分组；仅覆盖该窗口 |
| GraphQL 连接池 | waitingClients 峰值为 0 | 不据此声称已完成所有业务健康检查 |

控制台出现 Dashboard 和估值历史慢调用，但当前样本量和请求组成不足以把它归因于关闭缓存，也没有证明新故障。权限撤销后的读取新鲜度、真实购买/扫描和完整旧包兼容仍未执行，不以这些指标替代业务验收。

### 当前验收边界

- 用户本次追加授权的缓存关闭与浏览器观测访问已完成；缓存和观测访问的前置问题已有上述处置证据。
- Placement 尚未部署。当前剩余门禁是缓存关闭后的目标接口基线覆盖与样本量，而不是再次要求用户授权同一个缓存变更。
- 后续只使用缓存关闭之后的同类请求进行 Placement 对照；先补充扫描、额度预占、Dashboard 和估值历史的代表性正常业务样本，不拿 65 条事件冒充 65 个请求，不用单个样本推断 P95。
- 未启动后台持续监控、定时任务或自动部署；没有承诺在本轮结束后自动继续观测。原 Placement 试验授权保留，但未完成的试验不记为通过。
- 本轮仍只有 v1.1.1 文档修改；不执行 Git 提交/推送，不改变 v1.0.0 / v1.1.0 冻结或归档内容。应用测试和构建未运行，因为没有应用或 Wrangler 源码变更；远端配置变更仅完成上述回读与短窗口观测验证。

## 2026-09-28 17:17 后：扩展基线与 Smart Placement 本地候选

用户要求继续原小阶段；未授权扩大至 SQL、绑定、连接池或 Git push。先扩展缓存关闭后的窗口，再准备仅包含生产 Smart Placement 的候选配置。**本节记录本地候选，不代表生产已启用 Placement。**

### 新取得的观测证据

- 窗口：北京时间 17:05–17:16（UTC 09:05–09:16）。GraphQL 于 17:20:57 返回 135 次 success 调用，requestDuration P50=947.103 ms、P95=2,588.405 ms；仍包含不同路径及定时任务，不能用作单一路径的结论。
- Hyperdrive 同窗为 583 次 uncacheable / complete，均在 IAD；waitingClients 峰值为 0。独立回读 caching.disabled=true、origin_connection_limit=100，modified_on 未再变化。
- 控制台扫描路径单独筛选显示 No events found。未筛选列表最多先显示 50 条，不能据首屏计算整个窗口的接口数量；全文 OR 的多词输入被 UI 合并为 needle，不采用该组合查询作为证据，改用单个路径筛选及下述 API 分组计数。
- Zone HTTP Analytics 按 host=api.tcgcard.fun、requestSource=eyeball 和精确路径分组的查询于 17:26:20 成功，sampleInterval 平均值均为 1。搜索请求 46 次（AU / BNE、HTTP 200）：hit 20、miss 25、expired 1；Dashboard 与估值历史分别 1 次（AU / BNE、HTTP 200、bypass）；扫描识别与额度预占没有返回分组。控制台 Worker Invocations 的搜索记录为 26 次，与 25 次 miss + 1 次 expired 对应；这是两个数据集的对照，不把 20 次边缘缓存命中计入 Worker 执行样本。
- 带 edgeTimeToFirstByteMsP95 的 Zone HTTP Analytics 查询返回 HTTP 200 但 GraphQL errors.code=authz，明确表示该 zone 无权访问该字段；没有绕过限制或升级套餐。后续成功查询只读取已获准的路径/地区/状态/缓存计数，不包含受限延迟字段；不能因此宣称取得按路径的边缘 TTFB P95。

### 本地候选与验证边界

- 仅在 [生产配置](../../../../apps/workers-api/wrangler.toml) 增加 env.prod.placement / mode=smart；不增加顶层 placement，不固定 region/host，不恢复 Cloudflare dev 或 D1。
- 在 [部署配置测试](../../../../apps/workers-api/src/deployment-config.test.ts) 增加生产范围和 Smart 模式断言，保护“不把 Linux dev 或其他目标一起改为放置试验”的意图。
- 17:27 在增加候选配置前先运行该文件：新增断言按预期失败，原有 2 项通过。此失败是缺少候选配置的先失败证据，不记为最终测试通过。
- 候选配置加入后执行 pnpm --filter @kando/workers-api exec vitest run src/deployment-config.test.ts src/index-postgres-runtime.test.ts src/entitlements/node-fetch-worker-shim.test.ts：退出 0，3 个文件 / 11 项测试通过；新增配置断言由先失败转为通过。
- pnpm --filter @kando/workers-api run type-check：退出 0。
- pnpm --filter @kando/workers-api run deploy:dry-run:prod：退出 0。按既有脚本构建 auth-core 和 Admin production assets（12 个文件），打包 Worker（2056.43 KiB，gzip 387.41 KiB），最后明确输出 --dry-run: exiting now；没有上传部署。显示的 Hyperdrive、KV、R2、向量 Service Binding 均沿用原配置。
- 完成候选 diff 自查：只有生产 placement 两行配置和相应的 5 行测试增量；未发现越界业务修改。git diff --check 通过，保留 Git 的既有 LF/CRLF 提示。
- 17:31:32–17:31:33 独立回读生产 settings 和 Hyperdrive：placement 仍为 {}，缓存 disabled=true、modified_on 未变，原 Hyperdrive ID 和 recognize-vec / production 服务绑定不变。此时本地候选与现网状态明确不同。
- 未执行完整 Workers 测试、Flutter/Admin 测试、Linux 构建、真实旧包业务烟测、生产部署及 Placement 效果验收；本轮只有生产配置候选变化，Admin 构建成功不等于其测试通过。
- 当前生产仍为原 version 6be8c5f9-60dd-499b-b19f-23d4fa6ac7c4 / 100%；未执行部署或回退。不得将本地 mode=smart 写成现网状态。
- 扫描基线缺失、Dashboard/估值各仅 1 次，以及按路径边缘 P95 不可取，仍限制本轮可做出的性能结论。试验授权保留，不自动扩大成全接口 SLO 验收，也不据此调整业务实现。

### 放行与回退边界

搜索已有可核验的同地区请求及 HTTP 缓存分组，但该窗口的 Worker 搜索执行只有 26 次，仍不是完整的全接口尾延迟验收。若希望在扫描样本补齐前启用 Smart Placement，应明确将它视为有限样本试运行：Placement 作用于整个生产 Worker，当前证据只覆盖部分读接口，扫描与分路径边缘 P95 继续列为未验证；不能把缩小观测覆盖范围静默写成原验收全部通过。

如后续试验需要回退，应恢复对应 Worker 配置/版本并重新回读 Placement；本轮已获授权关闭的 Hyperdrive 查询缓存继续保持 disabled=true，不随 Placement 回退而重新开启。当前没有执行任何回退命令。

## 2026-09-28 17:37 后：有限样本试运行放行

用户明确同意在当前有限样本与观测边界下启用整个生产 Worker 的 Smart Placement；以已有搜索请求作为初步对照，扫描与分路径边缘 P95 保留未验证，不宣称全面提速或 SLO 通过。

- 发布前再次确认本地候选仅含 env.prod.placement / mode=smart 与相应配置测试；业务源码、锁文件和依赖相对已记录生产源码未变。工作区中的当前版本文档属于本任务，未覆盖其他改动。
- 17:40:06 UTC+08:00 前置快照：生产 deployment 35134321-a835-405d-8558-893dab13d0f5，version 6be8c5f9-60dd-499b-b19f-23d4fa6ac7c4 为 100%；settings.placement={}；Hyperdrive 查询缓存 disabled=true，连接上限 100；25 个绑定中 10 个为 Secret 名称（未读取或保存其值）。
- 旧版本可通过 versions view 读取，已记录为回退目标；非版本化配置的恢复仍需回读确认，不能只凭 rollback 命令成功声称全部设置恢复。
- 发布前只读烟测：GET /api/v1/health=200、无 Authorization 的 GET /api/v1/portfolio/folders=401、GET /=200。未发起用户登录、购买、扫描或业务写入；这些检查不替代登录态兼容验收。
- 即将按仓库既有 deploy:prod 入口发布，不运行 migration，不修改 Hyperdrive/KV/R2/Service Binding，不提交或推送 Git。实际发布与回读结果待执行后补记。

## 2026-09-28 17:41 / 17:51：Smart 已发布，按新授权恢复查询缓存

本节补齐上一阶段已实际发生的发布，并记录用户随后明确要求“还是需要开启 Hyperdrive 查询缓存”的新授权。历史缓存关闭及单变量试验约定按时间保留，以下为最新运行状态。

### Smart Placement 发布与回读

- 17:41:16 开始、17:41:34 结束，按既有 pnpm --filter @kando/workers-api run deploy:prod 发布一次，退出 0；没有重试发布。Wrangler 明确报告 No updated asset files to upload，Admin 静态文件无需更新。
- 新 deployment 为 39820d69-049f-4234-ad8c-1a1393d8afa8，新 version 为 3ecee0b5-20e6-47a3-86f5-34f65f1d5465，17:43:48 及 17:52:43 的回读均承载 100% 流量。
- 业务源码与原生产基线 7868f4c 保持一致；本地 dev@7982c16 的未提交候选仅增加生产 mode=smart 及配置测试。未执行 Git 提交/推送；配置在现网生效不代表 Git 已交付。
- 发布前后 Worker settings 的归一化比较只有 placement 变化。25 个绑定的名称/类型/资源引用保持不变，其中 10 个 Secret 只比较名称及元数据，未读取或存储其值；Hyperdrive 配置在这次 Worker 发布中没有变化。
- 发布后烟测：GET /api/v1/health=200、未登录 GET /api/v1/portfolio/folders=401、GET /=200；生产 Admin 首页与本地构建逐字节一致，SHA-256 为 6e8a3b9b066723a523ba2d55ff7a96f262e340484101049c99fa84d6f5f99a8e。
- 17:45:21 读取服务元数据：placement_mode=smart、placement_status=SUCCESS；placement.last_analyzed_at=2026-09-28T09:41:55.944851Z。SUCCESS 表示平台分析状态，不证明每个请求远程执行于 IAD，也不证明延迟改善幅度。
- 没有启动 Tail 会话、创建定时监控或执行回退；扫描、购买、完整旧包兼容及分路径边缘 P95 仍未验证。未取得足以宣布 Placement 性能改善的发布后同类样本。

### 依用户新要求恢复现有 Hyperdrive 查询缓存

- 对同一资源 7d71bcd0bcf64e518a23a852ced76d66 / tcg-cards-db 执行一次 hyperdrive update <id> --caching-disabled=false --env prod；不是新增缓存连接或绑定。
- 更新前 caching.disabled=true，更新后独立读取为 false；服务器 modified_on=2026-09-28T09:51:04.293107Z（北京时间 17:51:04）。命令及回读均成功。
- 前后完整返回配置的差异仅有 caching.disabled 和系统修改时间 modified_on。没有传入 max-age、swr、源库、端口、连接上限或 mTLS 参数；未调整 TTL、连接池、SQL 或绑定。源库仍为 aws-us-east-1-5.pg.psdb.cloud:5432，origin_connection_limit=100。
- 17:52:43 再次回读 Worker：仍为上述 version / 100%，placement.mode=smart，绑定元数据与发布后快照一致。开启查询缓存没有重新发布 Worker。
- 恢复缓存后的只读烟测：GET /api/v1/health=200、未登录 GET /api/v1/portfolio/folders=401。没有执行撤销 Session、权益或额度的陈旧读取复现；这些烟测不证明缓存一致性风险已经解决。

### 最新试验与回退边界

当前是 Smart Placement + Hyperdrive 查询缓存同时开启。17:51:04 之前的缓存关闭阶段与之后的缓存开启阶段必须分开统计；不能将之后的延迟变化全部归因于 Placement，也不能把此前 17:05–17:16 的基线直接用于单变量收益计算。

同一 HYPERDRIVE 仍承载 Session、权益、额度等业务读取。恢复缓存是遵从用户最新配置要求，不是已证明这些读取不会使用陈旧结果；该风险继续保留，后续若要隔离读取或改变业务实现须另行确认范围。

本次新授权取代上一节“回退时缓存保持 disabled=true”的旧运行假设：后续如需回退 Worker，不应擅自改变用户最新要求的查询缓存开启状态；任何缓存处置仍须明确说明，不把旧计划误当新授权。未执行 migration、生产业务写入、数据库命令、Git 提交/推送或后续架构优化。

文档同步到根 README、AGENTS 及本版本入口，仅更新当前部署/配置事实，不改工作规则或 v1.0.0 / v1.1.0 历史归档。应用源码和测试在本次缓存恢复中没有变化，未重跑应用测试；上一阶段的 11 项针对性测试、类型检查和 prod dry-run 结果不扩写为生产性能或一致性验收通过。

## 2026-09-29：扫描 R2/向量并行与批量额度本地验证

范围：用户要求在并行上传与识别时明确失败处理，特别保证多用户批量识别不重复扣费、不漏扣。本轮为本地 I/O 调度迭代，不调整配额 SQL、锁、租约、缓存、数据库或客户端协议；保留前一日 Placement/文档未提交改动，不部署或推送。

### 定位与先失败证据

- 阅读 Scan 路由、quota 状态机、PostgreSQL 适配和 mutation lock、直接 Flutter Gallery/ScanApi 调用、PGlite 测试及版本契约。确认 Gallery 每张独立 request_id，预占串行、识别可并发。
- 原始服务端先 await R2.put，再调用向量与目录；两者输入没有依赖，且计时 recognition_ms 使用 imageStored 作为起点。
- 修改前执行 pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts src/scan/scan-image.test.ts：退出 0，2 个文件 / 44 项通过。
- 新增 6 个带 Promise 屏障的测试，先阻塞上传再断言识别已开始；旧代码全部按预期失败（识别调用为 0），证明尚未并行。finally 释放屏障并等待请求结束，未留下挂起任务。定向运行中 42 项未选择测试显示 skipped，不等同于本轮全文件通过。
- 本地测试编辑脚本首轮因嵌套模板字符串语法失败而未写文件；改为普通文件编辑后成功，不将失败步骤记为通过。

### 实现与阶段性验证

- 上传异常立即捕获为失败结果；向量/目录继续使用既有错误分类。审计和结算前等待上传完成，上传失败时清理可能已写入的图片并返还该请求额度。
- 仅修改共享 Scan 路由中的 I/O 顺序和计时起点；没有复制、扩展 D1 类型、查询或测试基座，没有改额度 UPDATE/INSERT、owner 级锁、Free 10 次或 Premium 定义。
- 相同的 6 个时序用例在修改后通过，覆盖成功、无匹配、上游失败、审计失败、R2 已写入但确认失败以及双重失败；同时检查处理中重入 409、完成后重放、审计/图片/额度状态。
- 双 owner 并发批量测试通过：各已有 8 次消耗，分别竞争 3 个预占，仅 2 个成功；混合 no_match/R2 失败分别返还各自一格，后续各复用一次，最终各恰好 10 次 consumed、1 次 released、0 次 reserved。跨 owner 抢占和重放被拒绝，无额外 R2/识别调用。
- Premium 11 个同时进行的识别测试通过，Free consumed/reserved 始终为 0；同 owner 两个 session 竞争最后一格测试通过，最终仅 1 次识别/扣费。
- 已提交 settlement 后 quota 回读故障测试通过：首次失败响应，使用同 request_id 重放恢复成功且仅扣一次。并行阶段计时测试通过：向量比 R2 先完成时，不把 recognition_ms 截为 0，也不把并行等待误计为 audit_ms。
- 当前增量契约写入 [扫描并行流程](../01-flows/scan-recognition.md)。完整回归、静态检查与最终 Code Review 在执行后补记，不提前记为通过。

### 初始验证边界（Docker 启动前）

- 本机 Docker context=desktop-linux、目标为本地 npipe dockerDesktopLinuxEngine；docker version 返回该管道不存在，真实 PostgreSQL 容器多连接测试未运行。没有自动连接 dev/prod 数据库或安装/启动新数据库服务来绕过此限制。
- PGlite 测试覆盖 PostgreSQL SQL 语义与应用 Promise 交错，不能证明真实多连接事务锁竞争；原配额 SQL 和锁未改。生产 Hyperdrive 缓存读新鲜度、>60 秒租约/接管、进程中断、外部 R2 补偿失败和真实 iOS/Android Gallery 仍不是已验收保证。
- 尚未部署或调用线上向量服务，不将局部并行证明或理论关键路径缩短写成生产毫秒收益。整个系统的跨资源“绝对一次性”也不由本次修改保证。

### Docker 启动后的真实 PostgreSQL 补验与最终结果

用户告知 Docker 已启动后重新核验：仍是本机 desktop-linux/npipe，Docker Server 29.4.3。只创建本任务的临时容器，不连接远端数据库、不改用户已有容器或卷。

| 检查 | 实际命令 / 环境与结果 |
|---|---|
| Workers 相关回归 | pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts src/scan/scan-image.test.ts src/owner-auth.test.ts src/owner-auth.integration.test.ts src/entitlements/premium-access.test.ts src/db/postgres-database.test.ts src/index-postgres-runtime.test.ts；退出 0，7 文件 / 82 项通过，未跳过 |
| Workers 类型 | pnpm --filter @kando/workers-api run type-check；退出 0 |
| Cloudflare 打包 | pnpm --filter @kando/workers-api run deploy:dry-run:prod；退出 0，Worker 2056.79 KiB / gzip 387.47 KiB，明确 dry-run exiting，未部署 |
| Linux API | pnpm --filter @kando/workers-api run build:linux:api；退出 0；Node bundle 检查 2 项通过，API bundle 成功 |
| Flutter 调用与额度 | Flutter 3.44.7 / Dart 3.12.2；flutter test --no-pub test/scan_api_client_test.dart test/scan_result_source_test.dart test/scan_quota_controller_test.dart；退出 0，32 项通过，包括 Gallery 预占顺序、相同请求重试与乱序额度响应 |
| PostgreSQL 扫描全文件 | 在 apps/workers-api 执行 node .wrangler/scan-parallel-postgres-20260929/run.mjs；53 项全部通过，最终附证据的一轮核验 53 个独立 schema，每个实际建立 5 个不同 backend PID，服务器报告 18.6 |
| PostgreSQL 核心竞争重复 | 同一 runner 使用 -t 'isolates two concurrent|shares the final Free|keeps a Premium batch' 连续执行 3 轮；每轮 3 项通过、50 项因名称筛选未选择，各轮均证实 3 个独立 schema / 每池 5 连接。不是把过滤的 50 项算作通过，完整 53 项结果见上一行 |

PostgreSQL 镜像为 postgres:18.6-alpine，拉取 digest sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873。容器仅绑定 127.0.0.1 动态端口，PGDATA 使用本任务 tmpfs，数据库固定 scan_parallel、测试用户固定 scan_test，随机临时密码仅在进程环境中传递。

为避免新增持久测试基础设施，用忽略目录 .wrangler/scan-parallel-postgres-20260929 下的本地 overlay 将现有 routes.test.ts 的测试数据库工厂替换为真实 PostgreSQL：业务 prepare/batch 复用生产 PostgresDatabase，batch 仍是多连接下的真实事务；只适配测试所需 exec/query/close 及故障注入入口，未添加人为串行队列。每个测试独立 schema，连接池 max=5，并发 SELECT pg_backend_pid() / pg_sleep 验证真实多连接，未取到证据时 runner 主动失败。辅助文件和不含凭据的 backend PID 证据不加入 docs 或 Git；正式回归用例仍在已跟踪 Scan 测试文件中。

首次真实数据库 runner 从仓库根目录启动时找不到根 node_modules/vitest/vitest.mjs，测试未执行，临时容器已自动清理；随后固定到 apps/workers-api 后执行成功。后续一次人工读取容器活动时容器已被 runner 清理，返回 No such container；不据此宣称取得活动查询结果，改用每次工厂内记录的 backend PID 硬断言补足证据。各轮容器停止前核对精确名称及任务 label，--rm 清理已确认；未停止或删除用户已有容器/数据卷。镜像缓存保留。

### Code Review 与交付范围

2026-09-29 完成当前 diff 的本地 Code Review（未委派子 Agent）：

- 逐一检查预占/权限门禁仍在外部 I/O 前；没有绕过 owner 锁、修改配额 SQL 或用客户端配额授权。
- 检查上传拒绝立即处理、两个分支结束后才审计/结算，上传晚于识别或审计失败时不会出现“清理后上传又完成”的本次竞态。
- 对照账本断言检查批量成功仅扣各自一次，失败只归还本请求，重复/跨 owner 请求不触发额外工作，Premium 不改变 Free 消耗。
- 对照计时测试确认 recognition_ms 与 audit_ms 不再使用串行链路的错误起点；重叠阶段不强行累加。
- 审查结论：当前修改及已覆盖的正常租约内并发/失败路径未发现阻断问题；现有租约过期接管、进程崩溃与外部缓存/存储一致性不被本地测试扩写为绝对一次性保证。

未运行全仓 Workers、Admin 测试、Flutter 全量 analyze/test 或 iOS/Android 真机；仅对识别相关调用方做了上述验证。没有修改 Flutter 源码，不把 Flutter 单测或 Linux 打包冒充真实移动端/生产环境验收。未改写 v1.0.0/v1.1.0 归档，未提交、推送、部署、迁移或发送真实识别请求。

最终文档交付检查：git diff --check 退出 0（仅提示既有 LF/CRLF 转换）；5 份当前文档的 UTF-8、末尾换行、行尾空白与 37 个本地链接检查通过；再次确认 quota SQL、数据库适配器、Flutter 源码及 v1.0.0/v1.1.0 归档无改动。

## 2026-09-29 10:07：Linux dev 自动部署完成回读

用户先授权通过 SSH 只读核对 kd201，随后提出重新部署 dev。检查过程中原有 watcher 已自动完成目标提交发布，因此没有再执行强制部署、重启或数据库命令，避免重复同一版本的备份和容器重建；这不是一次额外手工发布。

### 目标与时序

- 目标为部署文档中的 kd201 / 192.168.50.201，SSH 返回主机名 srs-node-test1、用户 user；使用本地既有主机密钥严格校验。密码未写入脚本、环境文件或文档；未读取服务器私有 .env / watcher.env。
- 10:04:19 回读时仍运行旧 release branch-dev-15228be54603-20260928100313；watcher 已构建 dab850f 的发布包并正在执行发布前备份，未看到失败标记。
- 10:07:07 第二次只读检查发现部署已完成。watch.log 显示 Deployment completed for dab850f85778c2dd4a39b32183c35cdb91904eb7；10:06 的后续定时检查已报告 No new commit。没有重发或并发启动部署命令。

### 一致性与健康证据

| 检查 | 结果 |
|---|---|
| current / shared current-release | branch-dev-dab850f85778-20260929100150 |
| release manifest | branch=dev，sha=dab850f85778c2dd4a39b32183c35cdb91904eb7，built_at=2026-09-29T02:01:50Z，source=kd201-branch-watcher |
| last-seen-sha / last-deployed-sha | 均为 dab850f85778c2dd4a39b32183c35cdb91904eb7 |
| failed-sha / failed-at | 均不存在 |
| API / DB | running / healthy |
| Web | running；未配置独立容器 healthcheck，不写为 Docker healthy |
| migration 容器 | exited / 0；本轮未查询 migration ledger |
| release 文件 / 运行容器 API SHA-256 | 均为 d502d6db74c3f0c99c872a62aa7001c0eeb04d78987ef0a6b1e519235b0f02bb |
| HTTP 健康 | 服务器 localhost 与 10:08:54 本机经内网访问 /api/v1/health 均 200，body={"status":"ok"} |
| Admin 静态入口 | 10:08:54 经内网访问 / 为 200，title=Kando Admin |

部署前备份文件为 toccards-test-20260929-100152-before-branch-dev-dab850f85778-20260929100150.dump，大小 1,135,365,150 字节，mtime=2026-09-29 10:04:28+08:00；对应 .tmp 已不存在。只核查文件元数据，没有执行 pg_restore --list 或恢复演练，不宣称该备份已通过可恢复性验收。

### 操作与未验证边界

两次 SSH 只读检查均退出 0，未使用 sudo、未执行服务器文件写入、部署脚本、重启、migration 或 SQL；部署/备份/容器切换由此前已经运行的 watcher 完成。本地 HTTP 检查首轮 PowerShell 命令解析失败，未发送请求；改用 Node 的只读 GET 后成功，未重试任何超时远程命令。没有查询业务表或执行真实识别、购买及账号写入。

确认的是目标版本已在 Linux dev 运行且基础服务健康，不是用户批量识别、额度账本、Hyperdrive 缓存一致性或旧包双端端到端通过。本轮未触碰 Cloudflare prod。当前部署事实只更新当前版本与根入口文档，不回写 v1.0.0/v1.1.0 历史归档；本轮文档尚未提交或推送。

## 2026-09-29：Pixel_8 真实 Gallery 验收被 Android 权益门禁阻断

用户授权在 Pixel_8 Android 模拟器新建测试 UID，并使用 D:\Downloads\bug 的卡牌图片验证 dev Gallery 与额度。**结果为 BLOCKED：客户端未打开选图器，尚未发起任何扫描预占/识别；不得把环境准备、额度初始值或本地回归写成真实 Gallery 批量识别通过。**

### 测试环境与隔离

- Pixel_8 / emulator-5554，Android 16、x86_64。发现原有 com.cardai.tcg 1.0.3 (157) 已安装，因此不清除或覆盖其数据。
- 使用未改动的 dab850f App 业务源码、config/test.json 和本次临时 Gradle init 脚本构建独立包名 com.cardai.tcg.gallerytest；APP_ENV=test，版本 1.0.4 (161)。init 只覆盖 applicationId/version 元数据，未修改任何已跟踪 Flutter/Android 源码，未安装插件或绕过构建检查。
- 构建成功（Gradle 8.12 / AGP 8.9.1 的未来兼容性及依赖编译警告保留，不在验收任务中升级工具链）。APK 大小 140,664,814 字节，SHA-256=ac91e5b648adf1452fa8503e95f3ab91ca8d04e40de12d3f55c1811ad8bbaa61。安装后原包版本与最后更新时间保持原样。此隔离 debug APK 不是原生产分发 APK，不能用来宣称正式包兼容验收。
- 用户目录共 49 张图片，生成了本地输入哈希清单。将其中 A 组 8 张、B 组 6 张复制到新建的 CodexGallery_20260929_A/B 相册；原始图片未修改、未删除。A 组拟覆盖首批识别，B 组拟覆盖剩余额度与混合图片；这两组只是准备好的输入，未上传到扫描 API。
- 初次检查模拟器时钟停在 2026-09-07；仅通过 Android alarm 服务同步到当前 2026-09-29 UTC 时间，并回读确认，再执行 Gallery 点击。未修改 Windows 或服务器时钟。
- 截图、输入清单与脱敏 App 诊断保存在本机 visualizations 的 gallery-dev-20260929 目录；临时构建/只读诊断脚本在忽略目录 .dart_tool/gallery_dev_20260929，不加入 docs、Git 或发布包源代码。

### 实际身份、请求与账本证据

- 新 UID / anonymous owner_id 为 100044，dev 创建时间 2026-09-29T02:31:47.449Z。未创建 Premium grant，也未修改真实用户账号。
- 仅对隔离测试 App 使用 Dart VM 只读对象检查，提取身份、配额和已有请求日志；未提取、输出或保存 access/refresh token，未设置 Provider 状态或替换 API/模型。静态环境常量在 VM 对象接口中显示未初始化，因此不用它们作运行环境证据。
- 脱敏 App 请求记录中 20 条已记录请求均指向 http://192.168.50.201:8080，其中 /auth/anonymous 与多个 /scan/quota 均为 200。示例：创建会话 X-Request-ID=5bd518cb-c466-4c58-b954-17a578f653a1；quota X-Request-ID=5708306c-f031-4979-92ef-a8909f4819cb。没有 /scan/quota/reserve 或 /scan/recognize 请求记录。
- App 扫描页显示 10 scans remaining；配额状态可见 isServerAuthoritative=true、unlimited=false、consumed=0、remaining=10。
- 10:44:59 SSH 核对 dev release 仍为 dab850f，仅在 BEGIN READ ONLY / ROLLBACK 中按 owner_type=anonymous、owner_id=100044 查询：账号存在、session 1 个、consumed=0、有效 reserved=0、released=0、scan_record=0。
- 10:52:43 同样的限定 UID 只读回查：scan_quota_request 总数=0、Free consumed=0、有效 reserved=0、scan_record=0、关联 grant 行数=0。因此只能确认“未发起扫描、未扣额度”，不能声称扣费正确性场景已执行。

### 阻断复现与代码路径

输入：隔离的新 Android 安装、无本地权益缓存、已取得有效 dev 匿名 session 与服务端 Free 额度。操作：进入 Scan，点击 GALLERY。实际结果：顶部显示 Unable to verify Premium access. Please try again.，没有打开系统选图器；10:56 再次从同一 Scan 页面点击 Gallery 复现相同提示，并取得包含提示的截图。预期：有效 Free 用户在额度允许时可以进入 Gallery，最终授权和扣费仍由服务端决定。

根因证据：

1. [订阅控制器](../../../../apps/flutter-app/lib/features/subscription/subscription_controller.dart) 的 AppSubscriptionConfiguration.fromEnvironment 仅为 iOS 配置 appStore；Android 返回 store=null、空 productIds，与临时包名无关。
2. 新的 SubscriptionState 默认 premiumState=unknown；未配置平台的 build 直接返回该状态。_refreshEntitlement 在 store 非 appStore 时返回现有状态、wasVerified=false，并没有取得可用于继续的 Free/Premium 结论。
3. [Scan 入口](../../../../apps/flutter-app/lib/features/scan/scan_page.dart) 的 _resolvePremiumBeforeScan 只在 Premium/unlimited 或本地已确认 Free 时直接放行；刷新仍为 unknown 就提示失败。已有的服务端权威 Free quota 不会在该路径解除阻断。
4. 因而这次真实测试被 Flutter 前置门禁拦住，尚未触及 R2 并行实现。不能归因为 PostgreSQL、R2 或向量服务慢，也不能用修改本地权益状态或手工向量 HTTP 请求冒充 Gallery 成功。

### 处置与未执行项

- 未实施客户端修复，未给测试 UID 授予 Premium，未伪造 Free 状态，未绕过图片处理/门禁，未通过 SQL 插入配额或扫描数据。
- 新 UID、隔离测试 App、测试相册保留，供取得修复授权后继续；原 App 和原图片保留。未触碰 prod、未部署服务端、未提交或推送文档。
- 尚未执行 A/B 批量识别、成功与失败扣费核对、超额排队、重复请求重放、弱网或双端真机验收。下一步需独立确认 Android Free 用户入口修复范围；不能把 unknown 无条件当作 Free，必须保持可信服务端权益/额度校验。
- 诊断工具中的首次 UI dump 在 Splash 阶段未生成 XML、首次 getInstances 使用错误参数、静态常量 evaluate 编译失败均未改变业务状态；后续使用已安装 VM 服务定义与只读对象读取取得以上证据，不将失败步骤标为通过。

## 2026-09-29：Android unknown 权益门禁修复，保留 iOS 业务

用户明确授权修复，并要求不要改变 iOS 业务。实际生产代码范围仅为 ScanPage._resolvePremiumBeforeScan 新增 14 行原生 Android 专属条件分支，不修改 SubscriptionController、StoreKit、订阅缓存、额度 controller、服务端、SQL 或 iOS 原生工程。

### 根因与回归意图

根因与模拟器失败截图、UID 100044 的零扣费账本见上一节。修复利用已有 ScanQuotaController.refresh 的成功/失败结果和 isServerAuthoritative 标识，只有 Android 未配置本地订阅商店且本地刷新仍 unknown 时允许向服务端确认；不是无条件将 unknown 解释为 Free，也不跳过后续额度为 0 的检查。

原 widget “unknown 刷新失败就阻断”用例未指定平台，默认 Android；本轮显式保留为 iOS 用例，断言完全保留，并增加 Android/ iOS 的 Photo、Gallery 对照测试。新增用例覆盖失败请求仍有旧额度、非权威本地额度、权威耗尽结果和刷新期间重复点击。

- 修改前原 unknown 定向 3 项通过；新增测试在修复前运行，校正测试提示框观察时间后，6 项 Android 场景按预期失败、3 项 iOS 场景通过。
- 首轮新增 iOS 对照测试把时间推进至提示消失后才查找提示，导致 2 项测试夹具失败；改为在提示有效窗口内断言，未修改业务或放宽断言。修复后的初次成功路径测试还把正常结算后的额外 quota 刷新计入“入口刷新”次数；改用结果屏障在识别完成前核对入口次数，保留结算后刷新，不删检查。
- 修复后定向 9 项全部通过。全局订阅状态仍为 unknown，不被局部 fallback 改成 Free/Premium；iOS 不增加此服务端 fallback 请求。

### 已执行检查

- flutter test --no-pub test/widget/scan_page_test.dart test/scan_quota_controller_test.dart test/scan_api_client_test.dart test/scan_result_source_test.dart test/subscription_entitlement_cache_test.dart test/subscription_entitlement_lifecycle_test.dart test/subscription_server_entitlement_sync_test.dart test/apple_current_entitlements_test.dart：193 项全部通过，包括整份 Scan widget、iOS 权益/StoreKit 相关 mock 场景和原有 Gallery 额度状态机。
- flutter analyze --no-pub：退出 0，No issues found。
- 运行源文件 dart format 检查通过。整份 scan_page_test.dart 的格式检查仍报告既有的其他区块格式差异；仅修正本次新增块，不顺手格式化旧测试，不把整文件检查报告为通过。
- 本次未运行 iOS 真机、Xcode 构建、真实 StoreKit 购买/Restore、服务端部署或数据库变更；Windows 平台 widget/单元测试不能代替这些外部验收。
- 正在重建同一隔离 dev 测试包，保留 UID 100044；App 源码修复未提交或推送。Code Review 与修复后的同路径设备验证结果待实际执行后补记。

### Android 修复最终审查与模拟器回归（2026-09-29）

- 本地 Code Review 检查后补充 !kIsWeb 限制，最终生产逻辑新增 14 行，只作用于原生 Android，避免 Android 浏览器误入分支。iOS 原生目录、整个订阅实现目录、quota controller 和服务端 diff 均为空。
- 显式给原“Free 刷新为 Premium”“unknown 刷新为 Premium”“unknown 刷新为 Free”测试增加 iOS/Android 平台对照，未放宽原断言。最终定向 15 项通过；完整上述 8 文件回归最终为 196 项全部通过，未跳过；flutter analyze --no-pub 无问题。
- 最终隔离 APK 仍为 com.cardai.tcg.gallerytest / 1.0.4 (161) / APP_ENV=test，SHA-256=fe8663bc40c2f0e668a58dc7dc30e31bf5368427103c4328a7ccdc401a9cb897。仅对该测试包执行覆盖安装，UID 100044 保留；原 com.cardai.tcg 仍为 1.0.3 (157)，最后更新时间未变。
- 使用与修复前相同 Pixel_8、UID 和 Gallery 按钮复测，原 Premium 校验错误已消失，正常进入 Android 照片权限及选图器。选择“有限访问”，只授权测试图片，没有开放所有原有照片。
- 本次选择器初次进入时仍使用旧图片索引视图；确认 MediaStore 已存在 14 张指定副本，只更新 A 组副本的时间戳并重新索引后，按系统 Photos → Browse → Images → CodexGallery_20260929_A 精确选择 8 张。原始 D:\Downloads\bug 文件未改，未选取原有 Camera 图片。所有扫描均由真实 App 的选图、端侧模型与既有 API 发起，没有提交手工向量、替换模型或伪造识别结果。

### A 组真实 Gallery 与额度核对：通过该组正常成功场景

实际提交时间 11:46:40（北京时间）。App 先显示 Scanned: 0/8，完成后显示 Scanned: 8/8、2 scans remaining。通过只读 SQL 按 owner_type=anonymous、owner_id=100044 回读，并将请求、审计和图片文件名对照：

| 文件 | 服务端匹配名 | 账本状态 / attempts / HTTP |
|---|---|---|
| 07-107055.jpg | Pikachu | consumed / 1 / 200 |
| 08-cards_107056.jpg | Poliwag | consumed / 1 / 200 |
| 03-516694.jpg | Lapras | consumed / 1 / 200 |
| 04-516695.jpg | Ditto | consumed / 1 / 200 |
| 05-516696.jpg | Eevee | consumed / 1 / 200 |
| 06-516697.jpg | Vaporeon | consumed / 1 / 200 |
| 01-516674.jpg | Marowak | consumed / 1 / 200 |
| 02-516684.jpg | Starmie | consumed / 1 / 200 |

11:50:01 回读：quota_total=8、free_consumed=8、reserved=0、released=0、scan_records=8、success_records=8，每行有图片引用，8 个不同业务请求 ID。首个为 2d280fe9-0bb3-4f32-8a35-3abd8830ab02（03:46:57.254Z 预占，03:47:00.733Z 结算）；末个为 4c92b939-457e-4694-884f-23301cd82792（03:47:36.863Z 预占，03:47:39.422Z 结算）。不能把逐张预占到结算的时间当作端侧处理总时长或并行性能 A/B 结论。

退出 A 组扫描页时仅确认退出未收藏的本地结果队列，没有删除服务端扫描审计、退款或调整额度。重新进入 Scan 仍显示剩余 2 次。

### 独立环境问题与 B 组边界

- 初次 A 组选择期间，Android 在 03:36:00.304Z 以 LOW_MEMORY 回收测试 App pid=7056，后台 RSS=507 MB；在 11:39 点击选图完成时进程已不存在，系统重新创建 App，选择未进入识别链路。因此这次不能记作 A 组识别通过或失败返还。确认无扫描请求后快速重走已准备好的相同选择流程，才取得上述 11:46 的真实 A 组结果。
- B 组准备了 6 张图片，拟在剩余 2 次时验证超额与混合结果。选图过程中系统再次于 03:53:44.212Z 以 LOW_MEMORY 回收 pid=10273，后台 RSS=709 MB；点击最终 Select 前通过 pidof 发现进程已不存在，没有提交该组，并取消了 6 张选择。
- guest MemTotal 回读为 2,531,824 kB；仅凭该瞬时内存与退出原因，不能断言具体内存泄漏、R2 问题或确定扩容收益。没有更改模拟器内存、重启模拟器、改超时/重试，或继续反复提交 B 组来掩盖环境问题。
- 11:59:07 最终只读回查仍为 quota_rows=8、distinct_request_ids=8、consumed=8、active_reserved=0、released=0、attempts_above_one=0、scan_success=8、scan_other=0。与 App 的剩余 2 次相符，没有因选图取消或进程回收增加消费。

### 最终结论与未验证项

Android 门禁 BUG 已有修复前失败、修复后同路径设备成功、平台定向测试和 Code Review 证据；iOS 业务代码及原分支没有修改。A 组真实 Gallery 的 8 次正常成功消费与账本一致，可作为该场景通过；不能扩写成 B 组超额/失败返还、真实多用户并发、弱网重放、低内存恢复或 iOS 真机全量通过。

后续应在合适的模拟器资源或真机环境补完 B 组，并单独评估 Android 进程被回收后的选择恢复。该问题未混入当前门禁修复。当前源代码、测试和本轮文档均未提交/推送；未部署 prod、未修改 iOS、未手工修改配额/权益或服务器配置。截图与原始诊断继续留在本地证据目录，不加入 docs。

## 2026-09-29 13:39：B 组剩余 2 次选择 6 张，额度未超扣但发生 Android OOM

用户要求继续同一 B 组。只执行真实 Gallery 验收及只读诊断，没有修改应用/服务器代码、重置额度、授予权益、调整模拟器 RAM/堆限制、部署或推送。上午 B 组“选图前进程被 LOW_MEMORY 回收、未提交”的记录保留；本节是下午确实提交后的新结果，不能混为同一次失败。

### 提交前状态与输入

- 13:36:53 通过 SSH 对 dev 做 BEGIN READ ONLY / ROLLBACK，确认 release 仍为 dab850f，UID 100044 账本为 8 个独立请求、8 次 Free consumed、active_reserved=0、released=0、8 条成功扫描，attempts_above_one=0。
- Pixel_8 / emulator-5554 的隔离 App 仍为 com.cardai.tcg.gallerytest，读取到相同 UID 100044。首次进入 Scan 出现加载期间的默认 10 次显示；等待服务端刷新后已确认 2 scans remaining，再打开 Gallery，未以本地默认值授权扫描。
- 通过系统 Photos → Browse → Images → CodexGallery_20260929_B 选择既定 6 张：01-516674.jpg、02-516684.jpg、03-IMG_3784.jpg、04-IMG_3778.jpg、05-227.PNG、06-cards_100022.jpg。截图明确显示 6 selected；没有使用 Camera 原有照片或修改输入。
- 13:39:35.837（宿主机北京时间）点击一次最终 Select，点击前确认 App pid=13364 仍存活；返回 App 后出现 Scanned: 0/6 与 Scanning。没有在崩溃后再次提交这组图片。

### 已发生的结果与额度证据

13:42:34 和 13:45:48 的两次限定 UID 只读回读均确认：总账本 10 行、10 个独立 request_id、Free consumed=10、reserved=0、released=0、attempts_above_one=0；scan_record=10 且全部 success。相对于 A 组只新增以下两项，均有图片引用：

| B 组文件 | 业务请求 ID | 匹配结果 | 状态 / attempts / HTTP |
|---|---|---|---|
| 06-cards_100022.jpg | 501b3932-0bb2-4fae-8071-e78709969860 | Checklist Card - Magic Origins (Planeswalker) | consumed / 1 / 200 |
| 01-516674.jpg | 11bd3d2c-9775-495f-b1d2-3e83a8f5c851 | Marowak | consumed / 1 / 200 |

服务器预占/结算时间分别为 05:39:45.374Z → 05:39:46.892Z、05:39:47.681Z → 05:39:48.186Z。这里直接记录各设备/服务器时间，不将模拟器时钟与服务器时钟当作毫秒级同步因果证据。

可以确认这次 B 组只新增 2 次成功消费、没有第 11 次消费或遗留预占；**不能确认剩余 4 张已正常得到拒绝响应并稳定显示 Waiting**，因为客户端发生了下面的崩溃，队列没有完成预期生命周期。

### 新发现的前台崩溃：不是上午的后台回收

- Android exit-info 报告 pid=13364 在设备时间 2026-09-29T05:39:47.315Z 退出，reason=4 APP CRASH(EXCEPTION)、importance=100、RSS 530 MB。此前上午的两次是 reason=3 LOW_MEMORY、importance=400，必须区别。
- AndroidRuntime 堆栈为主线程 java.lang.OutOfMemoryError：申请 134,217,744 字节（约 128 MiB）失败，growth limit=201,326,592 字节（192 MiB）；只读 getprop 也返回 dalvik.vm.heapgrowthlimit=192m、heapsize=576m。未调整这些值。
- 已确认失败发生在模型结果返回的序列化阶段：Arrays.copyOf → ByteArrayOutputStream.grow/write → StandardMessageCodec.writeInt/writeFloat/writeValue → StandardMethodCodec.encodeSuccessEnvelope → MethodChannel.result.success → [ScanModelRuntime.kt:42](../../../../apps/flutter-app/android/app/src/main/kotlin/com/cardai/tcg/ScanModelRuntime.kt)。该行是 mainHandler.post { result.success(output) }，**不是 createSession 的模型文件读取位置**；初步按类名称作“模型加载问题”的说法以这份完整堆栈为准纠正。
- 当前证据只足以定位主线程 MethodChannel 模型输出编码的内存分配失败；未进一步实测确定具体输出张量尺寸、是哪张图片触发、是否存在跨任务输出堆积或泄漏，不把这些推测写成根因已完全证实。
- 没有在本轮扩大为原生内存修复、使用 largeHeap 掩盖问题、吞异常或注入简化模型输出。iOS、StoreKit、权益/额度及后端实现均保持本轮开始时的状态。

### 重开后的恢复与耗尽门禁

崩溃后只重开同一测试 App，不清数据、不重交图片。再次确认 UID 为 100044，Scan 显示 0 scans remaining。点击 Gallery 进入 Choose Your Plan 订阅提示，没有打开选图器；没有点击购买或 Restore，随后关闭提示返回 Scan。

13:46 的脱敏调试快照记录权威 quota 状态 consumed=10、remaining=0、unlimited=false、isServerAuthoritative=true；新进程仅观察到 GET /scan/quota=200，示例 X-Request-ID=1893ee50-4368-49d5-a365-16c724fab40d、4ce04f5d-78bd-49ce-b509-6fd406a217ba。快照中还存在加载期间旧状态对象，不以旧对象覆盖屏幕和服务端最终值；未提取、输出或保存令牌，调试转发已清理。

截图及脱敏堆栈保留在本地 gallery-dev-20260929 证据目录：b2-current-quota、b2-six-selected、b2-submitted、b2-final-zero、b2-zero-quota-gate 和 b2-android-runtime-crash.txt；不加入 docs 或 Git。

### 本轮结论

- **通过的局部检查**：起始剩余 2 次，B 组新增 2 个成功结果恰好消费 2 次；最终总消费 10、预占 0；重开显示 0，耗尽时不再打开 Gallery。
- **整体验收不通过**：App 在处理六张图片时发生前台 OOM，剩余四张 Waiting/队列稳定性与结果可达性未完成，不能称为“B 组全部通过”或“无漏扣/多扣的全场景保证”。
- 需要独立确认 Android 模型输出桥接的内存修复范围，然后在明确的测试身份/额度条件下复验。UID 100044 当前已用完 10 次，本轮没有重置其账本，也不会以重复选择同样图片来规避额度上限。
- 本轮仅更新当前版本文档，不重新运行无代码变更的应用测试，不把前轮 196 项结果写成本轮真实 B 组通过；未提交、推送、部署或触碰 prod。

## 2026-09-29 13:52–14:20：卸载重装后复测，B 组仍出现相同输出编码 OOM

用户明确要求卸载 App 后重新安装再试。本轮只卸载 Pixel_8 上本任务的 com.cardai.tcg.gallerytest，并安装同一 APK；未卸载原 com.cardai.tcg，未清相册、改代码或调整 Android 堆/模拟器内存。**结论：干净重装未解决 B 组崩溃。**

### 安装隔离与额度基线

- 卸载前核对设备仍为 Pixel_8 / emulator-5554，APK 包名是 com.cardai.tcg.gallerytest，版本 1.0.4 (161)，SHA-256 仍为 fe8663bc40c2f0e668a58dc7dc30e31bf5368427103c4328a7ccdc401a9cb897；没有重建或改变测试二进制。
- adb uninstall 精确测试包返回 Success，确认包不存在后再 install -t 返回 Success。新 firstInstallTime/lastUpdateTime 为设备时间 2026-09-29 05:52:18；原 com.cardai.tcg 仍为 1.0.3 (157)、lastUpdateTime=2026-09-07 07:01:40，不受影响。
- App 正常创建新 dev 匿名 UID 100045，创建时间 2026-09-29T05:52:43.592Z。13:54:21 只读 SQL 确认新 UID 的 quota/consumed/reserved/scan_record 均为 0；旧 UID 100044 仍为 consumed=10、reserved=0、scan_record=10。卸载只清本地测试安装，不重置服务端旧账本。
- 有限照片授权仅选择已有 A 组测试副本；A/B 文件和原始 D:\Downloads\bug 文件均保持不变，没有为了复验写 SQL 增减额度或授予 Premium。

### 授权/后台中断与实际提交分开记录

1. 干净安装后首次进入选图器，系统在设备时间 06:01:11.965Z 以 PERMISSION CHANGE / one-time permission revoked 终止 pid=19409；最终提交前检查发现进程不存在，未提交 A 组，并取消选中状态。该事件不是 OOM，也不是识别失败返还。
2. 回到同一 App/UID 后实际提交 A 组一次，宿主机时间 14:08:55；页面从 Scanned: 0/8 变为 8/8，显示剩余 2 次。14:10:58 账本回读为 8 个不同请求、8 次 consumed、reserved=0、released=0、attempts_above_one=0、8 条成功扫描，文件清单与原 A 组相同。
3. A 组结束后首次准备 B 时，设备时间 06:13:00.397Z 系统以 LOW_MEMORY 回收后台 pid=22389，RSS 707 MB。最终提交前发现进程不存在，没有提交该次选择，也没有重新卸载或创建另一个 UID。
4. 取消未提交的选择后，只重开现有测试 App（pid=24033、UID 仍为 100045），快速走同一 Gallery → Browse → B 相册流程。每步都从当前 UI 树确认按钮及 B 组 6 个文件，最终截图为 6 selected，提交前再次确认同一进程存活。14:17:53 实际提交 B 组一次，返回 App 显示 Scanned: 0/6 和剩余 2 次。未进行模型/HTTP 重放或篡改识别状态。

### 干净安装复现了同一个前台 OOM

- 新进程在设备时间 06:18:01.205Z 退出，reason=4 APP CRASH(EXCEPTION)、importance=100、RSS 528 MB。
- AndroidRuntime 堆栈仍是主线程 OutOfMemoryError：申请 134,217,744 字节失败，growth limit=201,326,592；调用链同上一轮为 ByteArrayOutputStream.grow → StandardMessageCodec.writeFloat/writeValue → StandardMethodCodec.encodeSuccessEnvelope → MethodChannel.result.success → ScanModelRuntime.kt:42。
- 堆配置始终 heapgrowthlimit=192m、heapsize=576m；没有使用 largeHeap、增大 RAM、捕获吞掉 OOM 或裁剪模型输出来让试验通过。相同 APK、同一组 B 图片、新安装数据下仍可复现，说明本环境中仅靠卸载重装不足以解决，不得声称已排除所有模型尺寸、内存峰值或进程调度因素。

### B 组最终账本

14:20:06 限定 UID 100045 的只读事务回读：quota_rows=10、distinct_request_ids=10、consumed=10、reserved=0、released=0、attempts_above_one=0、scan_records=10、scan_success=10；旧 UID 100044 的 consumed 仍为 10。B 组恰好新增两条：

| 文件 | request_id | 结果 / 状态 / attempts / HTTP |
|---|---|---|
| 06-cards_100022.jpg | 88482d2f-649f-48fa-9325-147fcb89ebf5 | Checklist Card - Magic Origins (Planeswalker) / consumed / 1 / 200 |
| 01-516674.jpg | 044d8021-2933-4a15-89d2-e441ee40edcb | Marowak / consumed / 1 / 200 |

两次结算分别为服务器时间 06:18:04.452Z 和 06:18:05.581Z。端侧与服务器时钟不是逐毫秒同步测量，不能据时间差假称“进程退出后才开始所有操作”；成功记录与消费状态以服务端实际回读为准。

最后只重开 App 查看额度，不重新选图；读取到 UID 100045，页面 0 scans remaining，与权威配额 consumed=10、remaining=0 一致，调试转发已清理。只能确认两个成功请求各消费一次、没有第11次消费或遗留预占，不能确认其余 4 张已经正常变为 Waiting 或批量结果可恢复。

### 结果与后续边界

- **卸载/同包重装完成，原 App/相册保留；A 组通过；B 组整体仍不通过。**没有复用 UID 100044 的旧本地状态，也没有为两次测试重置任何服务端额度。
- 不再继续重装或提交 B。需要在独立授权范围内处理 Android 模型输出桥接的内存峰值，然后用明确的测试身份与额度条件复验，iOS 和服务端扣费规则不应随之改变。
- 本轮无新的源码修改、单元测试执行、Git 提交/推送、服务器部署、SQL 写入或 prod 操作；只更新当前验证事实。截图、重装前后安装信息和脱敏堆栈留在本地 gallery-dev-20260929 证据目录，未放入 docs。

## 2026-09-29：用户反馈手动测试通过

用户在本聊天反馈“我自己手动测试通过”，记录为用户提供的手工验收通过反馈。本次未提供设备、安装包、UID、图片组合及逐项结果，也未重新回读账本，因此不将其扩写为已独立复验“剩余 2 次选 6 张、2 张成功/4 张 Waiting”或双端完整验收通过。

此前代理在隔离 Pixel_8 环境取得的 OOM 堆栈及配额回读保留为历史证据；本次用户反馈不等同于 OOM 已由代码修复，也不据此否定用户的手工测试结果。不再自行推进额外内存修复；本轮仅补记反馈，未运行新测试、修改应用代码、提交/推送或部署。后续操作仍按单独授权范围执行。

### 2026-09-29 Git 交付前复验

用户另行授权提交并推送后，在当前 dev 工作区重新执行上述 8 个 Flutter 测试文件（--no-pub）：196 项全部通过、退出 0；flutter analyze --no-pub 退出 0、No issues found。再次审查最终 diff，确认运行逻辑仅增加原生 Android 条件分支，iOS 原生、StoreKit/订阅、quota controller、服务端和历史归档未改。文档本地链接及 git diff --check 通过（保留 LF/CRLF 提示）。

本次 Git 交付包括 Android 入口修复、平台回归测试、dev 部署回读及用户手工测试反馈；不将模拟器历史 OOM 标记为已修复。Git 推送、远端 CI、正式包发布和生产部署分别核验，本次提交/推送授权不触发人工部署或数据库操作。

## 2026-09-29：管理后台扫描详情候选卡牌图片预览

需求为 Admin 交互优化：在扫描记录详情中点击候选卡牌缩略图查看大图。原实现只有普通 `img`，没有点击预览入口；改为现有 Ant Design `Image` 预览，并限定相关样式，保留缩略图布局。失效图片隐藏整个图片组件，缺图保留不可预览的占位。业务行为见 [管理后台增量](../04-admin/admin.md)。

### 验证结果

- 修改实现前运行 `node --test apps/admin-web/test/scans-intent.test.mjs`：退出 1，原有 5 项通过，新增 2 项因缺少预览组件及其样式约束而失败。修改后相同命令退出 0，7 项通过。
- `pnpm --filter @kando/admin-web test`：退出 0，26 项通过，无跳过；其中新增的是遵循现有约定的源码意图检查，不冒充浏览器交互测试。
- `pnpm --filter @kando/admin-web type-check`：退出 0。
- `pnpm --filter @kando/admin-web build:prod`：退出 0，Vite 生产模式构建成功；此命令不部署。
- 在仅绑定 `127.0.0.1` 的临时 Vite 验证页渲染实际 `ScanDetailDrawer` 和样式，使用横版、竖版、缺图、404 图片四类本地样例，不连接业务 API。浏览器实际点击确认：两类正常图片可打开预览，竖版预览工具栏可继续放大；关闭按钮、Escape 均仅关闭大图并保留详情；缺图/失效图点击不打开空白预览。DOM 回读缩略图仍为 38×54，失效图组件为 `display: none`。模拟图片截图留在本地，不加入 docs 或 Git。

### 审查与边界

- 文档本地链接检查：23 项通过；`git diff --check` 退出 0，仅保留 Git 的 LF/CRLF 提示。临时浏览器页面和验证服务器已关闭。
- Code Review（本地最终差异自审）：未发现阻断项。改动只涉及候选图组件与其样式；私有扫描原图继续使用 Admin Token/Blob 路径，列表、API、候选数据、用户确认状态和权限未改。未新增依赖、接口、数据库结构或 Flutter 代码。
- 未执行真实登录态 dev/prod 端到端验收、跨浏览器矩阵或生产发布；本地样例不等同于线上图片源可用性验收。后续部署后由验收人员补验实际扫描记录。
- 未执行 Git 提交/推送、远程部署、数据库操作；本地实现不代表线上已生效。

### 2026-09-29 Git 交付前复验

用户随后明确授权将本次修改提交并推送到当前分支。已回读当前分支为 `dev`、上游为 `github/dev`，fetch 后两端基线一致；只纳入本次 Admin 图片预览、回归检查及当前版本文档，共 6 个文件。重新运行 Admin 全部测试（26 项，无跳过）、`type-check` 和 `build:prod`，均退出 0；最终差异再次自审，无新增业务代码变动或阻断项。

本次授权为 Git 提交/推送，不包含人工部署或数据库操作；远端 CI、Linux watcher 自动发布和真实环境验收结果需分别核验，不预填为已通过。

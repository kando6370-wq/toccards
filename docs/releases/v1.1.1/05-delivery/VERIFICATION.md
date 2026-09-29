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

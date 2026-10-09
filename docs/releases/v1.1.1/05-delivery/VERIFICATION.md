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


## 2026-09-29 17:03–17:04：候选图片预览已发布 Linux dev

用户明确要求部署 dev，目标为 kd201 / 192.168.50.201，提交为 `c9f950ef5f77d1ee00e7de825d0d3802a7c76686`。此前 Git 推送已触发现有 watcher；本轮确认其自行完成目标版本发布，没有并发启动人工发布、强制重建或重启，也未触碰 Cloudflare prod。

### 准备与时序

- 初次 SSH 非交互密钥认证被拒绝，不能据此读取服务器发布状态。HTTP health/Admin 当时均为 200，但主入口仍为旧 `index-Dpcx4bfa.js`。用户随后提供 SSH 认证方式，通过交互式密码认证成功登录，主机回读为 `srs-node-test1`；密码未写入脚本、配置文件或文档，未读取服务器私有 .env / watcher.env。
- `pnpm --filter @kando/workers-api deploy:dry-run:dev` 退出 0：Admin development 构建、Linux bundle 的 2 项检查及打包通过。发布包 manifest 为该完整 SHA、branch=dev、working_tree_dirty=false；仅生成本地包，dry-run 未连接服务器或部署。
- 最初 150 秒 HTTP 观察窗口未等到新入口，该等待超时不代表 watcher 发布失败。17:01 SSH 回读确认 watcher 已完成测试和构建，正在为目标 release 创建 PostgreSQL 备份；原 release 仍服务请求，没有失败标记。
- 17:03:44 SSH 回读确认目标版本已切换，watcher 日志明确记录 Deployment completed。日志中的服务端验证为 9 个文件 / 94 项通过，发布门禁 Node 检查 12 项、Linux bundle 检查 2 项通过；实际发布预检为 PostgreSQL 18、识别服务可达、pendingMigrations=[]，不是测试样例中的模拟待迁移列表。

### 发布一致性与健康

| 检查 | 实际回读 |
|---|---|
| current / shared current-release | `branch-dev-c9f950ef5f77-20260929165952` |
| manifest | branch=dev，sha=`c9f950ef5f77d1ee00e7de825d0d3802a7c76686`，built_at=2026-09-29T08:59:52Z，source=kd201-branch-watcher |
| last-seen-sha / last-deployed-sha | 均与目标完整 SHA 一致 |
| failed-sha / failed-at | 均不存在 |
| API / DB / Web | API、DB running / healthy；Web running，未配置独立 Docker healthcheck |
| migration 容器 / ledger | exited / 0；只读回查 toccards_test，PostgreSQL 18.6，14 项，最新 `0013_cards_all_search_trgm.sql` |
| release / 运行容器 API bundle SHA-256 | 均为 `d502d6db74c3f0c99c872a62aa7001c0eeb04d78987ef0a6b1e519235b0f02bb` |
| health | 服务器回环与 17:04:40 本机内网 GET 均 200，body=`{"status":"ok"}` |
| Admin 静态产物 | 入口 200，主资源 `index-yAJ8wPto.js`；HTML 引用的 10 个 JS/CSS 资源均与干净 c9f950e 的本地 development 构建 SHA-256 一致 |
| 本次预览代码 / 鉴权边界 | 主资源包含候选图“点击放大”和预览配置；未登录 GET `/api/v1/admin/scans` 返回 401 |

发布前备份为 `toccards-test-20260929-165953-before-branch-dev-c9f950ef5f77-20260929165952.dump`，大小 1,135,376,623 字节，mtime=2026-09-29 17:02:28+08:00，对应 .tmp 不存在。通过现有 PostgreSQL 18 容器运行 `pg_restore --list` 退出 0；仅证明备份目录可读取，未执行数据库恢复演练。

### 验证边界

- 两次经认证的 SSH 检查均退出 0；本机静态资源哈希、健康和未登录鉴权检查退出 0。远端操作限于部署状态/文件元数据/容器状态读取、schema_migrations 只读查询及备份目录解析；发布、备份和容器切换由已在运行的 watcher 完成，实际预检无待执行 migration。
- 本轮未登录 Admin 打开真实扫描记录，不把产物哈希一致写成真实记录交互已验收；本地模拟图片的点击、缩放、关闭和缺图检查仍以此前记录为证据。未执行真实扫描、购买或业务数据写入，也未运行恢复演练或 prod 发布。
- 本轮只补记当前版本及根入口文档，不回写 v1.0.0 / v1.1.0 冻结与归档内容；用户随后明确授权提交并推送这 5 份文档，本次 Git 交付不另行发布或部署。


## 2026-09-29 17:37–17:39：prod 仅发布 Admin 候选图片预览

用户明确授权“部署 prod，只发布 Admin 改动”。本次没有从当前 dev 整包发布；生产后端保留原逻辑，扫描 R2/向量并行增量仍仅在 Linux dev。

### 发布隔离与准备

- 发布前回读现网 deployment=`39820d69-049f-4234-ad8c-1a1393d8afa8`、version=`3ecee0b5-20e6-47a3-86f5-34f65f1d5465`、100% 流量，Smart Placement=smart，Hyperdrive caching.disabled=false、连接上限 100。保存脱敏配置指纹，并从 Cloudflare 读取现网 Worker 的唯一 `index.js` 模块。
- 以生产发布记录对应的 `7868f4cbcd725a4a68be731240782bed955f5617` 创建隔离工作树，仅应用 `c9f950e` 的 Admin `App.tsx`、`App.css` 和 `scans-intent.test.mjs`；另补齐现网已启用的 `[env.prod.placement] mode="smart"`。Workers 业务源码、packages、锁文件及 migration 相对该基线无差异。
- 隔离目录重建的 Worker 与下载的现网脚本逐字节一致：2,105,784 字节，SHA-256=`ffbc5a386743ee927368d4bb390ab54d84b5ba5e72349c277af779c3aeb0afd6`。最终上传还直接复用下载的现网脚本，采用 `--no-bundle`，避免把 dev 后端或其他编译差异带入。

### 本地验证及实际失败记录

- `pnpm install --frozen-lockfile --offline` 首次退出 1：缓存缺少 turbo 2.10.0 tarball。随后 `pnpm install --frozen-lockfile` 退出 0，按现有锁文件下载固定版本；没有修改依赖或锁文件。
- 首次 Workers `type-check` 在共享包产物尚未生成时退出 2，提示找不到 `@kando/auth-core` 声明；该次串联的 Workers 测试未执行。显式完成 `pnpm --filter @kando/auth-core build` 后重跑类型检查退出 0，再执行后述测试通过，不把首轮失败记为通过。
- Admin 全部测试 26 项通过、无跳过；Admin `type-check`、根 `pnpm lint` 均退出 0。
- Workers `src/deployment-config.test.ts src/index-postgres-runtime.test.ts src/entitlements/node-fetch-worker-shim.test.ts`：3 个文件、10 项通过、退出 0。这里是生产基线的针对性检查，不是含扫描并行的 dev 测试集，也不是全仓测试。
- 隔离目录执行 `deploy:dry-run:prod` 退出 0；再对实际上传入口运行 `wrangler versions upload .wrangler/admin-only-worker/index.js --env prod --no-bundle --keep-vars --strict --tag admin-preview-c9f950e --message "Admin preview only; preserve backend from version 3ecee0b5" --dry-run`，退出 0。两次均明确 dry-run，未切流。
- 最终发布范围自审通过：3 个 Admin 文件及现网 Placement 配置对齐，没有后端业务、SQL、环境绑定、Flutter 或营销站变更。

### 上传、切流与发布后回读

1. 使用上述 `versions upload` 命令去掉 `--dry-run`，仅上传候选，得到 version=`1b806fe1-7516-4749-ac87-77c3c6c29deb`、tag=`admin-preview-c9f950e`。实际新增/变化的静态资源为首页、主 JS/CSS 和 Ant Design 两个 vendor 文件，共 5 个文件；此时生产流量仍在旧版本。
2. 17:37:00 切流前比对 11 项全部通过：当前 deployment 未变，候选后端 ETag/handlers/Placement/运行配置/绑定与旧版一致，现网 settings、绑定、Hyperdrive、定时任务和 subdomain 开关保持原值。
3. 执行 `wrangler versions deploy 1b806fe1-7516-4749-ac87-77c3c6c29deb@100% --env prod --yes --message "Admin-only image preview; backend byte-identical to 3ecee0b5"`，退出 0。CLI 重新同步现有 logpush/observability 值；17:39 全量受检 settings 指纹与发布前一致，未产生配置值变化。

| 检查 | 17:39 实际回读 |
|---|---|
| deployment | `3e36d169-fc11-45e8-8077-0b1bab8656d5`，created_on=2026-09-29T09:37:42.767884Z |
| version / 流量 | `1b806fe1-7516-4749-ac87-77c3c6c29deb` / 100% |
| 实际生产 Worker 内容 | 再次下载 `index.js`，与发布前逐字节相同；2,105,784 字节，SHA-256 仍为 `ffbc5a386743ee927368d4bb390ab54d84b5ba5e72349c277af779c3aeb0afd6` |
| 后端 ETag | 仍为 `a1471312d4ca175f8457d1ea7f11fc6c268e7c607fda0f4c53a503266c34fee0` |
| 配置/资源 | Placement、兼容日期/flags、运行配置、完整变量/绑定指纹、settings 均与发布前相同 |
| Hyperdrive / cron / subdomain | Hyperdrive 完整配置指纹及 modified_on 均不变，缓存仍开启；cron、workers.dev 与预览开关不变 |
| Admin | 首页字节匹配；主资源 `index-Cplutb86.js`，10 个 JS/CSS 入口资源全部与隔离目录的 production 构建逐字节一致，包含候选图点击预览代码 |
| 只读烟测 | `/api/v1/health` 为 200 / status=ok；未登录访问 Admin scans、portfolio folders 均为 401 |

发布后 11 项版本/后端/配置比对以及静态产物和只读烟测均退出 0。脱敏指纹、前后 Worker、构建一致性和 HTTP 结果留在本地忽略目录 `apps/workers-api/.wrangler/prod-admin-preview-20260929`，不加入 docs 或 Git。

### 回退点及未执行边界

- 本次回退点为原 version `3ecee0b5-20e6-47a3-86f5-34f65f1d5465`；未执行回退。不能把这次 Admin 发布当作整个 dev 已部署 prod，扫描并行依然未上线生产。
- 未执行数据库 migration、生产 SQL、真实扫描/扣次、购买或其他业务写入；没有修改 Hyperdrive、KV/R2 绑定或营销站，也没有发布 Flutter 包或重新部署 Linux dev。生产 ledger 未在本轮重查。
- 未使用生产 Admin 账号打开真实扫描记录，本次部署验收是后端不变、正确静态产物生效及只读接口边界；交互行为沿用此前已通过的本地模拟图片验证，不宣称生产登录态端到端已验收。
- 本轮没有 Git 提交或推送；当前版本及根入口文档按实际生产状态补证，不修改 v1.0.0 / v1.1.0 冻结与归档内容。隔离发布工作树保留，便于追溯。


## 2026-09-29 17:46–17:52：双 prod Admin 域名版本不一致，前轮验收范围更正

用户反馈 `admin.tcgcard.fun` 仍不能放大，而 `api.tcgcard.fun` 已更新，并确认两者都属于 prod Admin。前轮仅验证了 API 域名的 Worker assets，遗漏实际 Admin 域名；“prod Admin 已全部完成”的结论应收窄为“API 域名副本已更新”，本问题尚未修复。

- 无登录态、带 Cache-Control: no-cache 的新请求稳定复现。Admin 域名 HTML 返回 DYNAMIC、public/max-age=0/must-revalidate，并引用旧 `index-BUAPc0VN.js`；其中候选图仍是原生 img，没有预览配置。API 域名引用新 `index-Cplutb86.js`，含点击放大及 Image 预览配置。这不是仅限用户浏览器的本地缓存现象。
- 在本地忽略目录增加可重复的双入口产物检查，运行 `node apps/workers-api/.wrangler/prod-admin-preview-20260929/check-admin-origins.mjs before` 退出 1：Admin 入口失败、API 入口通过；两端 HTML/JS 均为 200。旧主 JS SHA-256 为 `6aa9151c3ce60d4e24972fc0fe4812392e425e674d9d09998df4f9641554d36a`，新主 JS 为 `f78445917b2a1ff4263ec65f59a7a3b4021afde431f00218d698aec9728aff89`。该失败是修复前证据，未改断言或伪装通过。
- 只读 Cloudflare Workers 自定义域名列表中，API 域名绑定 toccards-api-prod；没有 Admin 域名条目。zone Workers route 仅看到营销站根域名路由。尚不能由此断定 Admin 域名的具体源站，不能猜测性改绑或改重定向。
- Pages 项目列表 GET 返回 403；现有 Wrangler OAuth scopes 只有 user/account/Workers/zone 权限，没有 pages:write。浏览器连接当前不可用，无法通过已登录控制台补查。需要用户补充相应授权后继续确认 Admin 实际发布目标；未绕过权限或扩大授权。
- 本轮未执行新的生产部署、DNS/route 修改、缓存清理、后端代码变更或业务数据写入。需在目标资源确认、发布完成后用同一双域名检查复验，再完成影响面与最终审查，不把当前调查标为已修复。


## 2026-09-30 09:03–09:09：补齐 Pages Admin 发布并完成双入口产物复验

### 根因与修复前证据

- 用户同意补充 Cloudflare Pages 权限；实际重新授权保留原 8 项 OAuth scope，仅增加 `pages:write`。首次把 `offline_access` 作为显式 CLI scope 时参数校验失败，没有启动授权；读取当前 Wrangler 实现后确认该项自动附加，移除显式参数后浏览器授权成功，`whoami --json` 核对最终权限集合恰好为原范围加 Pages。没有申请 DNS 写权限，也未保存/输出 token。
- 当前云端回读证实 `admin.tcgcard.fun` 属于独立 Pages 项目 `toccards-admin`，默认域 `toccards2.pages.dev`，生产分支 main，构建根目录 `apps/admin-web`、命令 `npm run build`、输出 `dist`；生产 VITE_API_BASE_URL 指向 `https://api.tcgcard.fun/api/v1/admin`。旧 canonical deployment=`c0c4ac81-3cd7-4fca-bfe6-2f91d1c70f29`，源提交 `e9e7578`，2026-09-28 成功，无 Pages Functions。
- 因此根因是遗漏独立 Pages 发布，而非 Admin 图片代码修复无效，也不是用户浏览器局部缓存。仓库先前“Admin 不是独立部署目标”的描述与现网冲突；按现网证据修正当前 AGENTS、README 和 v1.1.1 Admin 文档，v1.0.0/v1.1.0 历史归档不回写。
- 09:05 运行原双域名脚本 `node apps/workers-api/.wrangler/prod-admin-preview-20260929/check-admin-origins.mjs before-pages` 退出 1：Admin 仍为旧 `index-BUAPc0VN.js`、preview=false；API 为新 `index-Cplutb86.js`、preview=true。与 9 月 29 日的原复现一致，作为本轮修复前失败证据。

### 最小发布及验证

- 复用既有隔离工作树的批准产物，先比对其 10 个 JS/CSS 哈希与 9 月 29 日生产 Worker Admin 相同；dist 仅有首页和资源共 11 个静态文件，没有 Functions、`_worker.js`、`_headers` 或 `_redirects`。Admin `test` 再次 26 项通过、无跳过，`type-check` 退出 0；未修改或重建应用源码。
- 在隔离工作树 `apps/admin-web` 目录，通过已安装 Wrangler 4.106.0 执行 `pages deploy <该目录/dist> --project-name toccards-admin --branch main --commit-hash c9f950ef5f77d1ee00e7de825d0d3802a7c76686 --commit-message "Admin candidate image preview only; match approved prod Worker assets" --commit-dirty=true`，退出 0。metadata 的 commit 指批准的 Admin 来源；main 是 Pages 生产通道而非本轮 Git 合并，dirty=true 如实反映隔离补丁工作树。
- 新 canonical deployment=`038a65be-4858-4e31-89d1-fa67bf4ff559`，environment=production，created_on=2026-09-30T01:07:55.595025Z，deploy success=01:07:57Z。域名继续 active，未修改 DNS、路由、域名绑定、Pages 构建配置、环境变量或 GitHub 自动部署设置。
- 09:09 同一脚本 `check-admin-origins.mjs after-pages` 退出 0；两域名 HTML/JS 均为 200，主资源同为 `index-Cplutb86.js`，SHA-256 同为 `f78445917b2a1ff4263ec65f59a7a3b4021afde431f00218d698aec9728aff89`，preview=true。未放宽或修改原验收断言。
- 扩展比对两端 HTML 与各自全部 10 个入口 JS/CSS，均与批准构建逐字节一致；HTML SHA-256 同为 `729d63b2610847594f40064b37ce94fad87de8671fa974c082bc016732ea55e0`。生产 health=200/status=ok，未登录 scans/folders=401；以 Origin=`https://admin.tcgcard.fun` 发登录 OPTIONS 预检返回 204，Allow-Origin 正确、允许 POST。
- 云端发布前后 8 项检查全部通过：预期生产 Pages 部署及 active 域名、Pages 配置指纹不变、API deployment/resource/settings 不变、Hyperdrive 与 cron 不变。Worker 仍是 deployment `3e36d169-fc11-45e8-8077-0b1bab8656d5` / version `1b806fe1-7516-4749-ac87-77c3c6c29deb` 100%，没有再次上传后端。

### 影响面、审查与剩余边界

- 隔离目录补跑 `src/admin/cors-preflight.test.ts src/cors.test.ts`：2 个文件、9 项通过、退出 0，无跳过；文档本地链接和 `git diff --check` 通过，仅保留 Git 的 LF/CRLF 提示。
- 修复只更新原 Pages 项目的静态资源；另一 prod Admin 入口、生产 API、跨域/鉴权、变量/绑定和 Hyperdrive 均已检查不回退。没有部署 dev、营销站或手机安装包，没有 SQL/migration、账户、扫描或购买写入。旧 Pages deployment 保留为回退点，未执行回退。
- Code Review（部署方案、证据与文档自审）：根因、发布目标和失败转通过证据对应，未越过只发布 Admin 的范围；没有更改构建配置或以重定向绕开旧入口。历史“只有 Worker assets”描述已在当前文档明确纠正。
- 真实生产登录态的图片点击未执行，未使用用户会话或账号；本轮确认的是交付产物及入口/CORS/鉴权一致，交互行为仍引用已通过的本地模拟图片测试，不扩写为生产端到端全验收。
- `git ls-remote` 回读 main 仍为 `e9e7578`、dev 为 `10b5c55`。Pages main 自动部署仍开启，后续构建覆盖当前手动产物的风险存在，需另行授权将仅 Admin 的改动同步 main。未擅自提交、推送、合并或禁用自动部署。
- 脱敏前后快照与双域名检查结果留在本地忽略目录 `apps/workers-api/.wrangler/prod-admin-preview-20260929`，不加入 docs/Git；用户随后明确授权提交并推送这 5 份文档到当前 dev 分支。Git 交付前再次通过 43 处本地链接检查、diff 检查及文档自审；本轮仅文档，不重复运行应用测试，不合并 main 或另行部署。

## 2026-09-29：iOS 测试环境内部安装包 1.0.4 (162)

从干净的 `dev@10b5c553d2331b2e13075b697694f6def5051b50` 构建，仅交付内部安装包，不安装或上传。`config/test.json` 校验通过，目标 dev API `http://192.168.50.201:8080/api/v1/health` 返回 HTTP 200；环境相关 Flutter 测试 13 项通过。执行 `./tool/release_ios.sh --env test --pgy` 退出 0，依赖解析、`flutter analyze`、清理构建、Xcode 归档与导出通过；`pubspec.yaml` 由 `1.0.4+161` 更新为 `1.0.4+162`，Dart/CocoaPods 锁文件未变化。

最终内部 IPA 解包校验为 `com.kando.kandoApp.beta`、Apple Development 签名、App Attest `development`、测试 Firebase 及上述内网 API；42 个 Mach-O UUID 均有匹配 dSYM。保存的 IPA 为 39,921,830 字节，SHA-256 `4c0314bc0508177b707f310fff1d56e53a7a0b55b1f4ae46cd708b77493df4c4`，与导出源一致；`dSYMs.zip` 为 61,004,904 字节，SHA-256 `4655b6075d9a5f605d17698f625225923f4575186fd87d4dd204af978870d0f9`。两份 ZIP 完整性检查通过，保存于 `~/Downloads/CardAI-Packages/com.kando.kandoApp.beta/CardAI-Test-1.0.4-162/`。按测试包保留 3 版规则，旧 157 版移入废纸篓，当前保留 159、160、162；正式包及 Xcode Archives 不受影响。

未运行全量 Flutter/Android 测试、iOS 真机登录/购买/扫描验收；本次只构建 iOS 内部测试包，未安装设备、上传蒲公英或 App Store Connect，也未提交/推送 Git 或部署服务端。

## 2026-09-30：iOS 正式包 1.0.5 (163) 上传 App Store Connect

按用户要求从 `main@e930b72f160a7c6a9e22eada65ceb48b774a81f6` 构建并上传正式环境包。由于构建号 162 已用于测试包，本次将营销版本更新为 `1.0.5`、构建号更新为 163。生产配置为 Bundle ID `com.cardai.tcg`、Firebase 项目 `tcg-card-2072d`、API `https://api.tcgcard.fun/api/v1`、App Attest `production`，生产健康接口返回 HTTP 200 / `status=ok`。相对上次正式包 1.0.4 (161) 的源码提交，Flutter 直接依赖声明、根 `pubspec.lock` 和 iOS `Podfile.lock` 均无新增、删除或版本变化；构建前后两份锁文件 SHA-256 保持为 `0d85580159d1c598b6a61e32f9ad77c6a5013eaeb586ac29d9836d8b7e379021` 与 `d0879ca1f7222cbc2de5bd0d33a414c834eaec2235f469322ffd171ab0f75793`。依赖工具提示存在可升级版本，但本次没有升级依赖。

以 `config/production.json` 运行环境相关 Flutter 测试 13 项全部通过；执行 `./tool/release_ios.sh --env production --build-number 163`，依赖解析、`flutter analyze`、清理、Xcode Archive、App Store IPA 导出、签名/生产 Firebase/API 校验及 42 个 Mach-O UUID 的 dSYM 覆盖全部通过。另行解包保存的最终 IPA，确认 `com.cardai.tcg / 1.0.5 (163)`、Apple Distribution、`get-task-allow=false`、`beta-reports-active=true`、App Attest `production`，且描述文件没有设备列表。IPA 为 55,478,693 字节，SHA-256 `edf2bfd653ebb0efddae2a71c3a0d4f6e579179723e05e13597d7303a0a1cd32`；`dSYMs.zip` 为 60,940,339 字节，SHA-256 `1eaf58254be968c830251f3d39143a6c74cb594c8a4e711334a3bf905bd3176b`。两份 ZIP 完整性检查通过并保存于 `~/Downloads/CardAI-Packages/com.cardai.tcg/CardAI-Prod-1.0.5-163/`，源码版本同步为 `1.0.5+163`。

上传使用同一 Archive，Xcode 导出选项明确设置 `method=app-store-connect`、`destination=upload`、`uploadSymbols=true` 和 `manageAppVersionAndBuildNumber=false`。2026-09-30 14:16:38 +08:00，Apple 明确返回 `Uploaded package is processing.`、`Upload succeeded.` 与 `** EXPORT SUCCEEDED **`；这证明 IPA 与 Archive 中符号已提交给 Apple，不等于 App Store Connect 后台处理或符号处理最终完成，也不等于已提交审核或上架。用户说明上一版 1.0.4 (161) 未提交审核，本轮没有修改或提交该旧构建。

未运行完整 Flutter 全仓测试、Android 构建、iOS/Android 真机登录/购买/扫描验收、App Store Connect 后台处理完成与符号可用状态回读。当前 prod 服务端没有随本次客户端上传重新部署；本次也未安装设备、提交审核、Git commit/push、执行数据库操作或生产服务端写入。

## 2026-09-30：请求放置日志本地整改与两轮 Placement 验收边界

### 定位、根因与修改范围

- 本地环境：Windows / Node 22.20.0 / pnpm 11.9.0 / Vitest 4.1.9 / Wrangler 4.106.0；起点为 `dev@d96042d`。本地落后已存在的 `github/dev` 跟踪引用一项内部包版本/文档提交；未执行拉取、合并或重新发布该包。
- 问题：已有 `api_request` 包含传输 `request_id`、路由模板、状态及耗时，却丢弃运行时放置/入口/国家信息；无法仅凭既有日志区分入口节点与执行位置。这是观测缺口，不是已经证实的扫描延迟根因。
- 稳定复现：在 Node 测试中给请求注入 `cf-placement` 与 `request.cf`，既有日志仍只有原五个字段。先补回归断言，在未修改实现时请求日志测试 10 失败 / 4 通过；失败均为新增字段缺失，包括不带 CF 元数据的请求应输出显式 `null` 的断言。
- 最小修复：仅在 `src/request-id.ts` 的既有日志对象增加三行读取；沿用现有 Request 类型和可选链，不增加强制类型转换、环境分支或新请求 ID。测试覆盖 remote/local/未来格式标记、入口与执行位置不同、缺失/部分 CF 信息、错误响应、保留请求关联以及不泄露完整 CF 元数据。
- 影响面：共享中间件覆盖的全部 `/api/v1/*` 完成日志，包括 Cloudflare prod 与 Linux dev；响应契约、CORS、鉴权、计费、SQL、扫描并行逻辑、分段计时阈值均不变，非业务 API 路径仍无该日志。没有改动数据库 migration、依赖、绑定或缓存配置；未复制或扩展 D1 测试路径。
- 实现说明及待执行试验流程已同步到[扫描流程](../01-flows/scan-recognition.md)。用户原有版本入口修改与未跟踪的 Portfolio 调研文件保持不动；不修改 v1.0.0 冻结内容及 v1.1.0 归档。

### 实际验证

| 命令 / 检查 | 退出状态与结果 |
|---|---|
| 基线：`pnpm --filter @kando/workers-api exec vitest run src/request-id.test.ts src/deployment-config.test.ts` | 0；原有 9/9 通过 |
| 修复前：`pnpm --filter @kando/workers-api exec vitest run src/request-id.test.ts` | 1；10 失败、4 通过，确认旧实现不能满足新增观测契约，不是跳过或放宽断言 |
| 修复后：`pnpm --filter @kando/workers-api exec vitest run src/request-id.test.ts src/deployment-config.test.ts` | 0；17/17 通过 |
| 扩展回归：`pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts src/request-id.test.ts src/deployment-config.test.ts` | 0；70/70 通过（扫描路由 53、请求日志 14、部署配置 3）；扫描使用既有本地 PGlite 基座，未连生产数据库 |
| `pnpm --filter @kando/workers-api exec vitest run src/linux/config.test.ts src/linux/execution-context.test.ts src/linux/filesystem-r2.test.ts src/linux/in-memory-kv.test.ts src/linux/vector-recognition.test.ts` | 0；Linux 适配相关 20/20 通过；仍是本地测试，不代表 Linux 服务器部署验收 |
| `pnpm --filter @kando/workers-api type-check` | 0；Workers TypeScript 检查通过 |
| `pnpm --filter @kando/workers-api deploy:dry-run:prod` | 0；auth-core / Admin prod 构建及 Worker 打包通过，明确以 `--dry-run: exiting now` 结束；本地 Worker 产物含新增日志字段，未上传或部署 |
| 文档链接 / `git diff --check` | 本次两份文档的本地链接、UTF-8/末尾换行检查通过；初次 diff 检查发现本轮追加记录多一个 EOF 空行，已修正并重跑通过 |

### Code Review 与未验收事项

- 本轮执行主代理 Code Review 自审：复核中间件直接调用方、Cloudflare/Linux 入口、扫描计时契约、最终差异与回归结果；未发现阻断项。审查确认运行时代码仅增加三个日志字段，不以 `CF-Ray` / `CF-IPCountry` 替代 `request.cf`，不把 `ingress_colo` 当作实际执行节点，不改变 500 响应或既有请求关联。未进行独立第二审查人评审。
- 当前代码配置仍是 `[env.prod.placement] mode = "smart"`；本轮未改为 `region = "aws:us-east-1"`，因为用户要求先稳定运行“扫描并行 + 新日志”再只改 Placement。第二轮配置、指标口径和回退边界见扫描流程；本轮没有把待执行配置写成已部署状态。
- 未执行：Git commit/push、Linux dev/prod 部署、生产版本/绑定/缓存回读、全量生产日志采集、生产数据库操作、真实扫描扣次、iOS/Android 客户端计时和登录/Search/Portfolio 的生产回归。发布执行者需先确认批准的源码/产物及版本，再按两轮流程采集包含快请求和失败请求的同口径样本；设备持有者补客户端端到端验证。这些缺口使本轮只能证明本地观测实现，不能证明性能改善。
- 未运行全仓测试、Flutter 构建/真机验收或独立 PostgreSQL 多连接复验：本轮未改变 App、扫描/配额 SQL 或并发控制，已运行与新增日志及双运行入口相关的本地检查；不将这些未运行项标为通过。
- AU 108 次、P50 1.707 秒、P95 6.643 秒、超过 5 秒 45 次（41.7%）仅为用户提供的历史样本，本轮未重新查询或复算；P95 <3 秒、超过 5 秒占比 <5% 仍为待验收目标。未将 `scan_recognize_timing` 慢日志用作全量分布，也未关闭既有 Hyperdrive 缓存一致性验收缺口。

## 2026-09-30 11:09–11:13：请求放置日志已自动发布 Linux dev

### 发布方式与权限边界

用户要求重新部署 dev，目标明确为 kd201 Linux，不是 Cloudflare prod。核查时既有 watcher 已在处理此前推送的 `dev@7516cfd2a06a77c9a3a8ed5e94c1a3d6e909d876`；本轮没有重复启动发布、终止 watcher 或更改自动部署配置。DBX 的 SSH 状态查询及 SFTP 下载因 `MCP_READ_ONLY` 被拒绝，连接认证本身可用；后续仅使用允许的 SFTP 文本读取/元数据接口及内网 HTTP GET 跟进，没有改用其他通道绕过策略。用户提供的登录密码未写入仓库、脚本、证据文件或日志。

### 自动发布及状态回读

- watcher 日志确认 9 个 Vitest 文件共 94 项通过，Admin 环境/预检/离线 Web 校验 12 项通过，Linux bundle 启动与 Apple 依赖校验 2 项通过；随后 Admin development 与 Linux API 构建成功。此处是既有发布程序的日志证据，不声称本轮通过 MCP 手动执行了这些远端命令。
- 实际发布预检输出 `database=toccards_test`、`postgresMajor=18`、`recognition=reachable`、`pendingMigrations=[]`。前面的预检单元测试曾打印模拟的 `0013` 待执行列表，不能将其误当成实际发布结果。
- 发布前备份：`/home/user/apps/toccards-test/backups/toccards-test-20260930-110551-before-branch-dev-7516cfd2a06a-20260930110549.dump`，SFTP stat 回读为 **1,135,397,728 字节**，同名 `.tmp` 不存在。仅确认文件落盘及脚本 `pg_dump` 阶段已通过；本轮未运行 `pg_restore --list` 或整库恢复，不能把文件大小当作可恢复性验收。
- watcher 于约 11:09 完成发布，日志输出 `Linux test deployment completed` 及目标完整 SHA。新 release 为 `branch-dev-7516cfd2a06a-20260930110549`，上一 release 为 `branch-dev-c9f950ef5f77-20260929165952`；未执行回退。
- 11:10 SFTP 回读 `current/release-manifest.txt` 的 SHA、`shared/current-release`、`watcher/state/last-seen-sha` 与 `last-deployed-sha` 全部对应新 release / `7516cfd`；state 目录仅有两个正常 SHA 文件，无 `failed-sha` / `failed-at`。11:10 watcher 后续检查已报告同一 SHA 无新提交。
- 发布日志显示 DB/API Healthy、Web Started；已读取本次 release 的部署脚本，确认脚本只有在 API 健康、migration 容器退出 0、ledger 读取有效以及本机 health/Admin 检查成功后才切换 current；末尾 ledger 计数为 **14**。这些是发布程序的容器/数据库检查证据，不是本轮独立执行 docker inspect 或 SQL；未回读最新 migration 名称。migrate 服务照常运行，但实际预检没有待执行项，本轮未安排新增 migration 或数据修复。

### 独立只读 HTTP 与本地检查

| 检查 | 实际结果 |
|---|---|
| `GET http://192.168.50.201:8080/api/v1/health` | 11:13 返回 200 / `{"status":"ok"}`，带合法 UUID v4 `X-Request-ID` |
| 未登录 `GET /api/v1/auth/me` | 401，并带合法 UUID v4 请求 ID；未使用真实用户会话 |
| `GET /` 与页面引用的 10 个 JS/CSS | Admin 200，标题正确；10 个资源均 200，逐项 SHA-256 / 字节与本地同提交的 dev 构建一致 |
| HTML 交付差异核对 | 首次探针退出 1：HTML 原始字节及普通 CRLF 转换比较均不一致；逐行定位为 Windows 本地 HTML 多 12 个 CR 字符，其中一处为额外 CR。仅去除 CR 后其余内容完全相同，资源本身不受影响；11:13 按明确的跨平台换行口径重跑退出 0，不宣称 HTML 原始字节一致 |
| `pnpm --filter @kando/workers-api deploy:dry-run:dev` | 本地退出 0；Admin dev / Linux API 构建和 2 项 bundle 测试通过，生成的本地包未上传或部署。清单如实标记 `working_tree_dirty=true`，原有未提交文档不属于部署输入，未伪装为 clean 构建 |
| 本地发布包范围 | 64 个归档条目中没有 .env、Git 目录或数据库/图片卷；运行代码输入相对 HEAD 无差异，原有两项文档 SHA-256 不变 |

最终服务端 HTML SHA-256 为 `7a3e56b633f7679b4d9581ecb4217360ca7ab9c34df4f6105ceca8631fee2e35`，主资源为 `index-yAJ8wPto.js`。初次失败及最终通过的脱敏 HTTP 检查结果保存在本地忽略目录 `apps/workers-api/.wrangler/dev-deploy-7516cfd-20260930/`，不加入 docs/Git。

### 未验证及未执行项

- SSH 与 SFTP 产物下载均被 MCP 只读策略阻断；没有独立核对运行容器与 release API bundle 的 SHA-256，也没有独立读取运行容器里的新增 `api_request` 字段。新字段的源码、回归测试及发布版本已确认，不扩大为运行日志逐条验收。
- 未执行 iOS/Android 真机扫描、真实扣次/购买、生产业务请求、数据库写入或恢复演练；Linux dev 的基础发布检查不等于扫描业务闭环或性能验收。
- Cloudflare prod、Placement 与 Hyperdrive 配置未操作；生产“扫描并行 + 新日志”基线及随后单独切换 `aws:us-east-1` 的两轮试验仍未执行。
- 本轮仅补充部署事实及文档入口，不修改业务代码，不自动提交或推送这些文档；保留用户原有版本入口修改及 Portfolio 调研文档。

## 2026-10-08 09:27–09:36：从 main 重新发布 prod API 与双 Admin

### 授权、输入与影响范围

- 用户明确授权重新部署 prod。发布输入为干净的 `main@61b542063c72a47f6f46fc375b64786333e19b0f`，本地与 GitHub 远端一致，已包含 `dev@cd34e89`；正式发布前再次检查 HEAD、分支、工作区及远端，未混入未提交代码。文档在发布验收后才更新，不属于本次部署输入。
- 发布目标仅为 `toccards-api-prod`（API 和 API 域名的 Admin assets）与独立 Pages `toccards-admin`（`admin.tcgcard.fun`）。营销站、Flutter/iOS/Android 制品、Linux dev 不在本次范围。
- 相对原生产后端 `main@7868f4c`，本次带入扫描 R2/向量并行、失败补偿计时和请求放置日志；Admin 候选图片预览保留。PostgreSQL migration/schema 无源码增量；本任务没有直接执行 SQL/migration、修改 Hyperdrive/KV/R2 binding，也没有发起生产账号、资产、扫描或购买写请求。
- Node 22.20.0、pnpm 11.9.0、Wrangler 4.106.0。既有 OAuth 已具备 Workers/Routes/Pages 所需写权限，whoami 退出 0；CLI 仍提示其他未使用资源的缺失 scope，没有执行 `wrangler login`、扩大 scope 或升级工具链。

### 本地门禁：首轮失败与复验分列

| 实际命令 | 退出及结果 |
|---|---|
| `pnpm lint` | 0；4 个共享包依赖方向通过。 |
| `pnpm type-check` | 0；Turbo 7/7 成功，其中 5 项复用缓存，Workers/Admin 类型检查实际执行。 |
| `pnpm --filter @kando/admin-web test` | 0；26/26，无跳过。 |
| `pnpm --filter @kando/workers-api exec vitest run src --exclude "**/.wrangler/**"` | **1；77 文件中 76 通过、1 失败，676 测试中 675 通过、1 因原 5 秒上限超时。**失败为扫描拒绝退役 hash/无效向量的测试；不把该首轮记为通过。 |
| `pnpm --filter @kando/workers-api exec vitest run src/scan/routes.test.ts --exclude "**/.wrangler/**" --maxWorkers 1` | 0；53/53，测试代码、原超时与断言未改。 |
| `pnpm --filter @kando/workers-api exec vitest run src --exclude "**/.wrangler/**" --maxWorkers 2` | 0；77 文件、676/676 全部通过，无跳过；只降低进程并发，未修改业务或测试行为，不把初次超时归因为已证实的业务 BUG。 |
| `pnpm --filter @kando/workers-api run deploy:dry-run:prod` | 0；auth-core、Admin production 和 Worker 打包成功，没有远程发布。 |

测试明确排除既有忽略目录 `.wrangler/` 中的发布包/临时测试复制件，执行正式 `src` 测试；没有通过排除正常业务测试或放宽断言让检查变绿。

### 正式发布与控制面回读

- Worker 命令：`pnpm --filter @kando/workers-api run deploy:prod --keep-vars --message "Redeploy main 61b5420: parallel scan I/O and request placement logging; preserve production bindings"`，退出 0。09:27 创建 version `4adbd0b7-3c67-4795-8ad0-c39795dc4be6`；09:28 独立 API 回读及 09:36 复核均为唯一版本、100% 流量，deployment `02bcb7e4-7b11-49aa-a267-4378b8c56e25`。
- Pages 命令：在 Workers workspace 使用 Wrangler 4.106.0，`pages deploy <同一批准的 Admin dist> --project-name toccards-admin --branch main --commit-hash 61b542063c72a47f6f46fc375b64786333e19b0f --commit-message "Redeploy approved Admin production assets from main 61b5420; match API Worker assets" --commit-dirty=false`，退出 0。CLI 如实提示并忽略不含 Pages 输出配置的 Workers wrangler.toml，使用已有 Pages 项目配置；09:29 deployment `39154bee-45d6-429d-8118-dfafed526ab7` 为 production/success，metadata 的源 SHA、main 与 dirty=false 均由 API 回读确认。
- 发布前及实际切流前均保存旧版本与脱敏指纹，确认期间没有其他发布或资源配置变化。回退点：Worker `1b806fe1-7516-4749-ac87-77c3c6c29deb`；Pages `4186ccd0-0c7f-44fc-98a7-897e86fe2cd8`（GitHub main 自动构建于 9 月 30 日发布），本轮没有执行回退。

| 回读项 | 实际结果 |
|---|---|
| Worker 内容 | 再次读取现网 `index.js`，2,106,326 字节，SHA-256 `32e8c52e147502affcfbd824ac606cf1e8b6fd4114991fc3ebb86eaf08d8beb0`，与批准的 main prod dry-run 构建逐字节一致。 |
| 运行配置 | compatibility_date、flags、usage_model、logpush、observability、cache_options、变量/完整绑定与发布前指纹一致；仅版本发布 annotations 更新为本轮说明，不宣称读取或比较了 secret 明文。 |
| Placement / Hyperdrive | Smart mode 保留；Hyperdrive 完整配置指纹及 modified_on 不变，`caching.disabled=false`，未切定向 region 或修改连接/缓存配置。 |
| cron / 域名 / 预览 | cron 仍 `*/5 * * * *`；实际 Worker 自定义域名配置不变，workers.dev 与 previews 仍关闭。 |
| Pages 配置 | production branch、GitHub 自动发布、构建/环境配置和域名不变；`admin.tcgcard.fun` 仍 active。发布 Pages 后再次确认 API deployment/settings 未变。 |
| 双 Admin 产物 | 两入口各自 HTML 和全部 10 个 JS/CSS 均 200，22/22 与同一批准产物原始字节/SHA-256 完全一致；未把换行归一化冒充字节一致。 |

HTML SHA-256 为 `729d63b2610847594f40064b37ce94fad87de8671fa974c082bc016732ea55e0`；主 JS `index-Cplutb86.js` 的 SHA-256 为 `f78445917b2a1ff4263ec65f59a7a3b4021afde431f00218d698aec9728aff89`。发布前 Pages HTML 有字节差异，但 10 个 JS/CSS 已匹配；重新发布后原始 HTML 断言也通过，没有删除或放宽检查。

### 新请求烟测、缓存样本及运行日志

- 最终只读检查使用唯一查询参数，避免固定 URL 的 HTTP 缓存响应冒充当前 Worker 执行：health 200 / status=ok / CF-Cache-Status=MISS；未登录 auth/me、Admin scans、portfolio folders 均 401 / BYPASS；iOS/Google app-config 200 / BYPASS，完整响应指纹与发布前相同；Admin 登录 OPTIONS 204，Allow-Origin 为正式 Admin origin 且允许 POST。7 项全部通过，合法 UUID v4 请求 ID 全部正确回传。
- 初次固定 health URL 的日志探针未取得发送 ID 的回传，随后独立确认同一 URL 为 HTTP 缓存 HIT、Age=348，返回缓存中的旧请求 ID；带新查询参数则 MISS 并保留发送 ID。本轮只更换验证请求，不改 CDN 或 Hyperdrive 缓存策略；该现象不用于推断业务缓存一致性已验收。
- `wrangler tail --env prod --format json --search <专用 request-id>` 仅观察本轮唯一 health 请求，回读 scriptVersion=`4adbd0b7-3c67-4795-8ad0-c39795dc4be6`、outcome=ok、status=200；`api_request` 中实际出现 `placement=null`、`ingress_colo=SJC`、`country=US`。这只证明该请求的新日志字段，null 不代表 Smart Placement 未启用，也不证明扫描分段、扫描成功或任何延迟收益；监听已结束。
- 原始构建、前后版本/配置指纹与脱敏 HTTP 结果保存在本地忽略目录 `apps/workers-api/.wrangler/prod-redeploy-20261008/`；没有把 JSON、运行代码或原始日志素材加入 docs/Git。

### 自审及未执行边界

- 部署方案与证据自审：源码/远端/构建/现网版本对应，双 Admin 独立发布没有遗漏；无 migration 或资源配置越界，未以只读 HTTP 代替登录态或旧包兼容验收。不存在本轮业务代码修复，BUG Code Review 不适用；文档检查：六份更新文档的 49 个本地链接均存在；`git diff --check` 退出 0（只有既有 LF/CRLF 提示），差异仅为六份本次选定的当前文档，业务源码、发布脚本以及 v1.0.0/v1.1.0 归档无变更。
- 未执行 Flutter analyze/测试/构建、iOS/Android 真机或正式旧包冻结合同、新写旧读、生产登录/预览点击、真实批量扫描与账本、Apple 交易/外部写入；客户端本轮未改动，设备、真实制品、账号与专项生产写入授权未提供。由产品/发布负责人安排补验或明确接受相应未验证风险，不将该平台兼容或业务闭环标为通过。
- 未执行生产 PostgreSQL ledger 独立回查、迁移、备份/恢复演练；源 diff 无 migration/schema 增量，不宣称实时 pending migrations 为零。ledger 上次独立回读仍是 2026-09-21 的 14 项。
- 未执行生产 P50/P95、扫描耗时对照、Hyperdrive/CDN 缓存一致性验收或定向 Placement 第二轮；本次没有改变 Placement/缓存，也不承诺性能收益。
- 未发布营销站、Linux dev 或手机安装包；未触发 Git 合并、commit 或 push。仅更新本文档和相关当前入口，冻结 v1.0.0 内容不动。

## 2026-10-08：插件免登录识别接口本地交付

### 范围与当前状态

从本地 `dev@f952e50bd688e07f6d2650dcc02359069707f747` 创建并切换到用户指定的 `dev-extension`。起始工作区干净，本轮代码仍为未提交改动；没有提交、推送、SSH、远程数据库写入、migration 或 dev/prod 部署。

新增 `POST /api/v1/extension/recognize`：独立插件 Key 校验、按可信来源 IP 的短时间防刷、32 KiB JSON/512 维有限非零向量校验，转发现有 `{vector, card_type}` 并透传成功 JSON。免登录，不访问 App 账号、扫描额度、图片/KV 或扫描记录；不做卡牌目录/价格补全。prod 仅新增原生限频 binding 声明；Linux 使用单进程内存限频和显式可信代理开关。实际边界与配置见 [插件接口契约](../03-data-api/extension-recognition.md)。

原 App 扫描和认证实现、共享 auth-core、冻结的 `docs/releases/v1.0.0` 与 dev 的差异检查为空。现有数据库 schema、migration、Hyperdrive/KV/R2/向量 binding、prod 缓存/Smart Placement/cron 未修改；没有为新功能复制或维护旧 D1 路径。

### 本地证据

环境：Windows / PowerShell、Node 22.20.0、pnpm 11.9.0、Wrangler 4.106.0。

| 实际命令 | 退出状态与结果 |
|---|---|
| `pnpm --filter @kando/workers-api exec vitest run src/extension/routes.test.ts --reporter=dot`（实现前） | 1；35 项中 34 项因新接口尚为 404 失败、1 项既有 App 凭据拒绝测试通过；实现后原测试转绿 |
| `pnpm --filter @kando/workers-api exec vitest run src/extension src/linux/extension-client-ip.test.ts src/linux/extension-rate-limiter.test.ts src/linux/config.test.ts src/deployment-config.test.ts --reporter=dot`（最终） | 0；6 文件 / 64 项通过，含无登录转发、拒绝无效 Key/超频/无配置、IP 头伪造、数值溢出、UTF-8 字节边界、上游异常/正文 deadline，不读取业务存储 |
| `node --test deploy/linux/offline/web-server.test.mjs`（修复后） | 0；2 项通过，含原分享 Host 契约，以及普通/编码等价识别路径的转发头覆盖 |
| `pnpm --filter @kando/workers-api type-check`（最终） | 0；Workers 类型检查通过 |
| `pnpm lint` | 0；4 个共享包的依赖方向检查通过 |
| `pnpm type-check` | 0；7 个包成功，6 项使用有效缓存，Workers 本轮执行 |
| `pnpm --filter @kando/workers-api build:linux:api` | 0；独立 API bundle 构建及 2 项打包测试通过；真实本机 HTTP 进程验证 health、401、识别成功、伪造不同 IP 头仍为 429、上游仅收到原协议且无插件 Authorization；数据库地址不可达但该路径无 SQL 访问 |
| `pnpm --filter @kando/workers-api deploy:dry-run:prod` | 0；Admin production assets 和 Worker 构建通过，Wrangler 识别独立 `60 requests/60s` Rate Limit binding；`--dry-run` 退出，未发布 |
| `pnpm --filter @kando/workers-api deploy:dry-run:dev` | 0；Admin development、Linux API/打包测试及本地发布包生成通过；dirty 包未作为纯提交版本交付；无 SSH、迁移或部署 |
| `pnpm --filter @kando/workers-api exec vitest run src --maxWorkers=2 --reporter=dot`（最终） | 0；81 文件 / 734 项全部通过，未跳过，未放宽测试超时或断言 |
| `git diff --check` 与文档相对链接检查 | 0；无差异空白错误，新增/更新文档的本地链接有效 |

### 必须保留的失败记录

- 初次 `pnpm --filter @kando/workers-api test`（默认扫描）退出 1：99 文件中 18 失败、81 通过；748 项中 4 失败、744 通过。包含既有 `.wrangler/linux-release-*` 中 `node:test` 文件被 Vitest 判为无 suite、历史安装环境诊断 3 项断言失败，以及扫描测试 1 项 5 秒超时。未删除这些产物/诊断，未更改 Vitest 排除规则。
- `vitest run src --reporter=dot` 默认并发退出 1：81 文件中 2 失败、79 通过；731 项中 2 失败、729 通过，均为扫描/价格存储测试 5 秒超时。
- `vitest run src --maxWorkers=1 --reporter=dot` 退出 1：81 文件中 1 失败、80 通过；731 项中 1 失败、730 通过，为既有 Admin 账单测试的 `Undici: bad port`。本轮没有修改其实现或测试基座，不将该现象的根因推断写成已证实事实。
- 最终增加边界用例后，完整源码集在 2 个 worker 下 734 项通过；这是限定源码范围及测试运行并发的复验，不代表最初默认 `pnpm test` 已通过，也不代表历史诊断问题已修复。

### Code Review

已完成本地代码自审，非外部独立审查。检查鉴权及限频拒绝发生在上游调用之前、来源 IP 的运行入口信任边界、并发计数与内存容量、参数/响应契约、凭据与业务数据隔离、正文大小与 deadline、CORS/旧 App 路由以及配置/文档一致性。

自审发现并修复离线代理的新路径判断问题：代理比较原始 URL，而 Hono 解码 URI，导致 `/api/v1/extension/%72ecognize` 可绕过新接口转发头覆盖。先补测试，确认 `node --test deploy/linux/offline/web-server.test.mjs` 为 1 通过 / 1 失败；随后按解码路径判断，仅对识别路径覆盖来源头。同一普通/编码输入复验为 2 项通过，原分享 Host 行为保持不变，打包与源码回归亦通过。修复后再次自审，未发现其他阻断性代码问题；保留以下外部验收边界。

### 未执行及需要补验

- 没有真实插件源码，本轮未修改/构建插件；自动携带 Key 的后台请求方式已给出。插件工程负责人需对接并实测 Chrome/目标浏览器 host permissions、网络权限、429 暂停及真实识别结果。
- 没有设置真实 dev/prod Key 或发布接口；仅本地声明新的 Cloudflare 限频 binding，账户内 namespace 唯一性、真实 location 近似限频及 Service Binding deadline 尚未在线验收，需要发布人员按环境授权后补验。
- 未运行真实 Caddy/Compose 容器及 kd201 网络验证；显式信任代理时必须确认 API 3000 不对公网/用户网段开放，否则转发头可被伪造。离线代理及直连 Node 只进行了本机 HTTP 验证。
- 未验证独立识别服务的公网访问控制；新增入口不能自动封堵其既有直连旁路，需要识别服务运维在启用前核对。
- 无 Flutter 代码变化，未运行 Flutter 分析、真机、旧包或商店验收；不将本轮服务端源码回归当作这些外部验收通过。

## 2026-10-09：插件候选补全完整卡牌详情

### 范围与契约选择

用户明确要求图片、价格等完整卡牌详情。本轮在 `dev-extension` 保留既有未提交改动，并将插件成功响应从内部识别 JSON 透传升级为 `{candidates: [...]}`：每项等于现有 `GET /api/v1/cards/:card_ref` 的 `data`，再附规范化的 `product_id` 与首次识别 `confidence`。此处选择卡牌详情业务，而不是 App 扫码候选的严格目录过滤规则；运营补录、图片规范化、价格及字段缺失行为以原详情接口为准。

调用链直接复用 `createDefaultAdapter → resolveCard → withCardImageUrl("detail")`，没有复制或修改卡牌查询、价格选取/换算、运营修正或图片规则。原扫描文件仅把既有纯函数 `readRecognitionCandidates` 改为导出，函数体和其他扫描逻辑不变；插件复用其 ID/置信度校验、数字 ID 规范化及首项去重规则。

保持免登录、Key 与短时间防刷、不扣 App 扫描额度、不创建扫描/收藏记录、不上传图片。新增仅是卡牌/运营修正/已发布价格的只读查询；没有 schema/migration、真实 Key、部署配置或业务数据写入。详情不存在的候选省略，空识别不查询数据库，缺失价格不填 0，任一详情查询异常返回 500 `INTERNAL_ERROR`，不伪装成空匹配或向量服务错误。详情顺序沿用识别列表，原上游 10 秒 deadline 不宣称覆盖整条数据库详情查询链路。

当前契约见 [插件接口](../03-data-api/extension-recognition.md)。2026-10-08 的无业务数据库读取/原始响应透传检查点只描述当时版本，不能作为本轮新需求的当前契约；历史证据原样保留。

### 实际验证

环境：Windows / PowerShell、Node 22.20.0、pnpm 11.9.0、Wrangler 4.106.0。本轮没有 Git 提交/推送、SSH、远程迁移或 dev/prod 发布。

| 实际命令 | 退出状态与结果 |
|---|---|
| `pnpm --filter @kando/workers-api exec vitest run src/extension/routes.test.ts --reporter=dot`（实现前） | 1；55 项中 17 失败、38 通过，原实现不能补全详情、处理缺失 ID 或拒绝无效识别结果；这是新契约的先失败证据 |
| `pnpm --filter @kando/workers-api exec vitest run src/extension --maxWorkers=2 --reporter=dot`（最终） | 0；3 文件 / 62 项通过，含完整字段、顺序/置信度、重复/数字 ID、运营修正/补录、无价格/无匹配、数据库异常和原 Key/限频/参数拒绝 |
| `pnpm --filter @kando/workers-api type-check` | 0；Workers 类型检查通过 |
| `pnpm lint` | 0；依赖方向检查通过 |
| `pnpm type-check` | 0；7 个包成功，6 项使用有效缓存，Workers 本轮执行 |
| `pnpm --filter @kando/workers-api build:linux:api` | 0；Linux API 构建及 3 项独立打包测试通过：真实本机 HTTP 的 health/免登录无匹配/Key/防伪造 IP、原 Apple SDK 打包、编译后候选的完整详情与图片/价格/运营修正 |
| `pnpm --filter @kando/workers-api deploy:dry-run:prod` | 0；Worker/Admin 构建通过并以 `--dry-run` 退出，未发布 |
| `pnpm --filter @kando/workers-api deploy:dry-run:dev` | 0；Linux 发布包构建通过，3 项打包测试复验通过；dirty 本地包保留，无 SSH、迁移或部署 |
| `pnpm --filter @kando/workers-api exec vitest run src --maxWorkers=2 --reporter=dot` | 0；82 文件 / 756 项全部通过，未跳过或放宽测试断言/超时 |
| `git diff --check`、文档链接检查、无关业务差异检查 | 0；文档路径有效；现有详情/价格/auth-core/认证、PostgreSQL migrations 及冻结 v1.0.0 文档均未改动；原扫描只改一个导出声明 |

新增 PostgreSQL（PGlite）对照测试与原详情端点逐字段比较，覆盖已发布 Raw 价格优先于其他语言/版本/评级报价、1/7/30 天基准与涨跌幅、图片、语言/版本、运营修正、手工补录及无价格情况。另验证带 SQL 片段的 `product_id` 仍作为绑定值，不扩大查询范围。测试数据库仅为内存夹具；没有改动已有 PostgreSQL/D1 兼容门面，未新增或维护 D1/Miniflare 类型、binding、schema、迁移或测试基座。

旧打包用例的“识别有候选但数据库不可达仍成功”前提不再符合新业务，已改为真实空识别不访问数据库，并另增完整详情的独立打包断言；没有跳过旧用例或降低新业务验证要求。完整数据库业务一致性由真实 PostgreSQL 引擎的内存对照测试补证，打包内的非空详情测试使用受控只读 SQL 回应，不冒充远端数据库验收。

### Code Review 与未验证边界

已完成本地代码自审，非外部独立审查。检查现有详情 helper 的直接复用、上游数据不覆盖可信价格/名称、原识别顺序与去重、无资料/无价格/查询失败的区分、只读数据边界、Key/防刷拒绝前置、原 App/API 不变、依赖及文档一致性。最终未发现阻断性代码问题；审查后仅补证文档，没有再修改业务代码。

- 本轮没有新的未解决测试失败；实现前失败已在实现后转绿。没有复跑会扫描历史 `.wrangler` 产物的默认 `pnpm test`，2026-10-08 的相关失败未修复、未删产物或改排除规则；不将源码范围通过写成默认命令通过。
- 未修改/构建真实插件（源码不在本仓），未验证实际图片加载或真实识别准确率；现有插件负责人需要按新字段契约补验。
- 未部署或改动真实环境 Key，未实测 kd201/Cloudflare 与真实价格数据、代理边界或识别服务公网直连控制；这些外部验收仍需环境授权后执行。
- 未进行线上性能/并发测试。每个去重候选依次复用详情查询，10 秒只覆盖上游识别 I/O，不保证详情补全总耗时；不新增猜测性缓存或批量价格口径。
- 没有 Flutter 变更，未执行 Flutter 分析/真机/旧包验收，不把服务端源码回归写成移动端外部验收通过。

## 2026-10-09：kd201 Linux dev 手工部署与上线验收

### 授权、目标与来源

用户明确授权部署到 kd201 的 dev，并确认已在服务器私有 `.env` 配置插件 Key 与频率。本轮只操作项目记录的 `192.168.50.201`，系统 hostname 为 `srs-node-test1`，部署账号为 user；既有 SSH 主机密钥严格匹配，指纹为 `SHA256:YZP844Gs0a2P9Bk1/A4XQuJnSVcrSxrtvu6xi1TgqQ8`。本机无法解析 kd201 名称，使用已记录 IP；本机无 SSH key/agent 登录，临时 SSH 客户端仅在内存使用用户提供的认证，运行原发布脚本，不改 SSH 配置、项目依赖或登录凭据，不记录密码。

发布 ID：`manual-extension-f952e50-dirty-20261009-1791513409974`。manifest：`branch=dev-extension`、`sha=f952e50bd688e07f6d2650dcc02359069707f747`、`working_tree_dirty=true`、`built_at=2026-10-09T02:35:40.949Z`；这是未提交工作区构建，不能标为纯提交发布。没有 Git 提交/推送或 prod 操作。

前一 release 为 `branch-dev-7516cfd2a06a-20260930110549`，保留未删除。最终独立回读时间为 2026-10-09 10:58:03（北京时间）。

### 发布门禁、备份和运行回读

- 重新执行 `pnpm --filter @kando/workers-api deploy:dry-run:dev`，退出 0，包含 3 项独立 Linux 打包测试通过。仅上传白名单发布包；64 个归档条目通过路径与私有环境/数据文件检查，未包含真实 `.env`、登录凭据、数据库或图片卷。
- 归档 2,078,636 字节；本地/远端 SHA256 均为 `19dbaf4fb62d4b65c623048428b36a10a18beff8f6c921f6b1bd2e3bccad83c3`。
- 远端原 `preflight.mjs` 独立运行退出 0：`APP_ENVIRONMENT=development`、数据库为本地 `db`/toccards_test、PostgreSQL major 18、识别 health 符合 512/cosine/top_k=5，`pendingMigrations=[]`。只读 ledger 发布前为 `14|0013_cards_all_search_trgm.sql`。
- 使用已鉴权连接执行原 `deploy/linux/ci/deploy-release.sh`，退出 0：先数据库备份，再离线运行镜像/Compose 构建、健康验收和 current 切换；未因密码认证另写应用发布逻辑。
- 数据库备份保留在 `/home/user/apps/toccards-test/backups/toccards-test-20261009-104004-before-manual-extension-f952e50-dirty-20261009-1791513409974.dump`，1,135,397,964 字节，临时 `.tmp` 不存在。`docker exec -i ... pg_restore --list` 退出 0，324 个条目；没有执行恢复演练。
- current symlink 与 shared/current-release 均指向此 release。API/DB healthy、Web running、migration 检查容器 exited/0；没有待执行或新增 migration，ledger 发布后仍为 14 项、最新 `0013`。
- 实际数据库 `server_version_num=180006`，保持 major 18；原卷 `toccards-linux-test_postgres-data:/var/lib/postgresql/data` 保留。没有 SQL 业务写操作或重置用户数据。
- API `/app/server.mjs` 的运行 SHA256 与批准产物一致：`68a3410d018ae4c5a18b7ca6322ce6088e7affd22ed670fd94246a87d28d4df0`；Web `/app/web-server.mjs` 为 `94152704c4d0e728e60fc36d98152b36c9698d7cbcfd9cc359d099af2c37bc99`，亦一致。

### 私有环境配置

用户已配置的 Key 与频率 60 没有覆盖或回显。核对 API 端口绑定为空、API/Web 在同一私有 Compose 网络，Web 为离线 Node 代理；先发布并核对新版代理，再备份私有 `.env`（备份模式 600），仅追加 `EXTENSION_TRUST_PROXY=true` 并重建 API，未重建数据库。运行进程确认 development、Key 存在、频率 60、trustProxy=true；逐字节确认当前私有配置严格等于原备份加这一行，因此 Key/频率和所有原字段保留。失败回退保护未触发，配置备份保留在 shared 目录，不上传或记录内容。

### 上线验收

| 实际检查 | 结果 |
|---|---|
| 内网 `GET /api/v1/health`、未登录 `GET /api/v1/auth/me` | 200 / 401，原 App 鉴权未开放 |
| 插件未带 Key / 错误认证格式 | 401 / 401 |
| 正确 Key + 无效参数 `{}` | 422，无识别调用 |
| 一次合成 512 维非零向量、card_type=0 | 200，5 个候选；不上传图片，不代表真实卡牌识别准确率 |
| 逐个候选与原 `GET /cards/:card_ref` 对照 | 5/5 完整详情一致，5 个均有价格，均返回规范化图片 URL；不回显实际 Key 或卡牌/价格原始数据 |
| 一条真实新 API 日志 | request_id=`7c2e310a-1a2b-4ba3-8cdf-28be55a73261`，POST 新识别路径，200，duration_ms=2949 |
| 63 次正确 Key + 无效参数，同时不断伪造 X-Forwarded-For/CF-Connecting-IP | 60 次 422、3 次 429，`Retry-After=60`；来源头伪造未绕过；这批请求不触发识别查询，仅验证本机来源窗口 |
| Admin HTML 与 10 个 JS/CSS，从内网入口读取 | 11/11 与批准 dev 构建原始字节 SHA256 一致 |
| 最终容器/产物/ledger/私有配置回读 | 通过；SSH 会话关闭，临时会话内存清理 |

### 保留边界与风险

- 仅完成一次合成向量的真实链路与详情一致性冒烟，不是实际照片、端侧模型、真实浏览器插件、图片资源可加载性或识别准确率验收；没有运行 iOS/Android 真机、订阅/收藏写入或全面压力测试。
- 当前额外配置仅 dev 的代理信任标志；prod API/Pages/营销站、Cloudflare bindings/Secret、prod 数据库均未修改或发布。dev 对既有 CF 只读识别服务进行了 health 和一次向量检索，不更改该服务配置或索引。
- watcher 仍跟踪 `dev`，last-seen 为 `f952e50`、last-deployed 为 `7516cfd`，未改其分支、状态或自动发布规则；此手工 dirty release 与 watcher 来源不同，未来 dev 自动发布可能覆盖它。后续应在明确授权后完成源码合并/提交/推送，不把手工部署等同于 Git 发布。
- 原应用 release、数据库备份、私有环境备份和本地/远端发布材料均保留，没有清理历史数据；备份只做可读取校验，没有恢复演练。
- 独立识别服务既有公网直连访问控制未在本轮整改或验证，新入口防刷不等于已封堵其所有旁路，也不证明分布式防刷能力。

## 2026-10-09：BUGFIX 默认 Workers 测试误扫历史产物

### 根因、修改范围与影响

Workers 的默认 `test` 原为 `vitest run`，未排除 `.wrangler`。Linux 发布打包会复制 security 目录中的 Node 测试到历史 release；测试文件名符合 Vitest 默认匹配规则，但 `.gitignore` 不控制 Vitest 发现范围。默认因此同时发现历史 Node 测试副本和旧诊断，前者会触发 `No test suite`，后者可能执行不属于当前源码回归范围的历史断言。

本轮仅把 `apps/workers-api/package.json` 的 `test` 改为 `vitest run --exclude "**/.wrangler/**"`，CLI 规则为追加排除，不覆盖既有默认项。不把范围缩成 src，不修改断言/超时/并发，不删历史材料，不修改或继续维护退役迁移测试、旧 D1/Miniflare 基座。原有 83 个非产物测试文件全部保留；新增一个轻量测试命令回归断言，保护“发布历史不影响测试范围，且不悄悄排除 src 外既有测试”的意图。

直接调用方仍使用原 Workers `pnpm test` 入口，未变更 CI、依赖、构建/部署脚本或应用代码。root AGENTS 的命令说明已同步；这只影响本地测试工具，不需要重新发布，已上线 dev 的运行产物未改动，prod 亦未操作。

### 先失败、复验与实际结果

环境：Windows / PowerShell、Node 22.20.0、pnpm 11.9.0、Vitest 4.1.9。

| 实际检查/命令 | 退出状态与证据 |
|---|---|
| 修改前 `vitest list --filesOnly --json` 及发现范围断言 | 列表退出 0，断言退出 1；103 文件中有 20 个 `.wrangler` 文件，不满足无历史产物验收条件；只列路径，不执行模块 |
| 修改前 `vitest run src/test-discovery.test.ts --reporter=dot` | 1；新增命令断言失败，实际为原 `vitest run`，先失败证据确认 |
| 修改后同一针对性命令 | 0；1 项通过，断言转绿 |
| 修改后 `vitest list --filesOnly --json --exclude "**/.wrangler/**"` 及集合对比 | 0；84 文件，历史文件为 0；原 83 文件全部保留，只新增本轮的 1 个回归测试文件。退役迁移工具测试保留原状，未执行或修改其基座 |
| 第一次 `pnpm --filter @kando/workers-api test` | 1；84 文件中 83 通过、1 失败，771 项中 770 通过、1 失败；历史 `No test suite` 与诊断错误均不再出现，但既有扫描用例超时 |
| 新断言初次类型检查 | 2；Workers 全局 URL 与 Node 文件接口类型不兼容；已按仓库的 dirname/join/fileURLToPath 风格修正，仅修复新增测试代码 |
| 修正后 `pnpm --filter @kando/workers-api type-check` | 0；通过 |
| 最终默认 `pnpm --filter @kando/workers-api test` | 1；仍为 83 文件/770 项通过，1 文件/1 项失败，同一既有扫描用例 5 秒超时；未通过，不能标为全量绿色 |
| `pnpm --filter @kando/workers-api test src/test-discovery.test.ts src/scan/routes.test.ts` | 0；2 文件/54 项全部通过，无跳过；原超时用例在仅运行此范围时通过，不将此结果替代完整默认命令 |
| `git diff --check`、更新文档链接检查 | 0；通过 |

新增断言代码修正后重新执行了针对性测试、类型检查、原默认入口及窄范围复验。扫描误发现集合的修复前后对比保持同一当前环境与路径规则，没有删除产物或绕过正式测试。

### Code Review 与未完成项

已执行本地代码自审，非外部独立评审：package diff 仅一行，确认 glob 引号在实际默认入口生效、只排除生成目录、未覆盖默认排除项、src 及原脚本测试仍保留；新断言不执行历史产物，使用现有 Node 文件路径风格；用户此前未提交改动与历史目录均保留。修正新测试的类型问题后已复验并再次审查，未发现本次扫描修复的阻断问题。

**本次历史产物扫描问题已验证修复，但默认测试整体仍未通过。**唯一未解决项为 `src/scan/routes.test.ts` 的 `rejects retired hashes and invalid vectors before storage or quota consumption`：两次完整默认运行均报 `Test timed out in 5000ms`，窄范围运行通过。该现象与历史目录扫描是不同问题；未证明其根因，也未修改旧测试/测试基座、放宽超时或改变默认并发。若继续处理，需单独定位，不能把这次排除规则修复宣称为所有默认测试已绿。

没有执行新构建、服务部署、Git 提交/推送或远程变更；未进行本任务不涉及的 Flutter/真实设备验证。


## 2026-10-09 14:13–14:19：dev 分支 Linux 发布完成及独立验收

### 授权、来源与执行方式

用户要求将已推送的 dev 重新部署到 kd201，范围仅 Linux dev。此前 DBX MCP 全局只读策略拒绝 SSH 执行；没有用另一路径绕过。权限恢复且用户要求继续后，14:11 实际连接成功，确认本地 dev 与 GitHub dev 均为 b621d76501e67ecc22fa6888c7bd6bdc3c2dba34，工作区干净。

复查时既有 watcher 已持有 watch/deploy 锁，正在为同一提交备份数据库；因此没有并发启动第二轮手工部署。跟进原发布脚本，14:13:43 回读确认完成；14:19:27 最终核验 release 为 branch-dev-b621d76501e6-20261009140959，manifest 的 branch=dev、source=kd201-branch-watcher、built_at=2026-10-09T06:09:59Z。服务器 watcher/source 的 HEAD 等于该 SHA 且工作区干净；current、shared/current-release、last-seen-sha、last-deployed-sha 一致，failed-sha/failed-at 不存在。后续 watcher 已记录 No new commit，没有手改其配置或状态。

前一 release manual-extension-f952e50-dirty-20261009-1791513409974 保留，是应用回退参考；本轮未执行回退。源码已进入 dev 并发布，不再把新环境标成上午的 dirty 工作区版本。

### 本地检查与对照构建

环境为 Windows/PowerShell、Node 22.20.0、pnpm 11.9.0；远端 Node 为 22.22.1。以下命令均退出 0：

| 检查/命令 | 实际结果 |
|---|---|
| pnpm --filter @kando/workers-api deploy:dry-run:dev | Admin development 与 Linux API 构建通过，含 3 项独立 Linux 打包测试；生成干净 dev@b621d76 的 linux-release-whaxbm.tar.gz，只作本地对照，没有上传或执行第二次部署 |
| node --test apps/admin-web/test/api-environment-intent.test.mjs deploy/linux/preflight.test.mjs deploy/linux/offline/web-server.test.mjs | 13 项通过，无跳过 |
| pnpm lint | 依赖方向检查通过 |
| pnpm type-check | 7 项成功，6 项命中缓存，Workers 本轮执行 |
| pnpm --filter @kando/workers-api exec vitest run src/extension src/linux src/scan/routes.test.ts src/cors.test.ts src/index-postgres-runtime.test.ts src/test-discovery.test.ts src/deployment-config.test.ts --maxWorkers=2 --reporter=dot | 15 文件、168 项通过，无跳过；包含此前全量环境中超时的扫描用例，但不能替代默认全量命令 |

文档补证后，`git diff --check` 与 5 个相关文件的 Markdown 本地链接检查均退出 0，37 处链接有效；改动范围仅下述发布记录与相关文档入口，未改业务代码或冻结基线。

### 数据保护、配置与运行一致性

- 原发布日志的前置预检通过；发布后独立再运行原 preflight.mjs 也退出 0：development、本地 toccards_test、PostgreSQL major 18、CF 识别 health 契约可达，pendingMigrations=[]。
- 发布前备份为 /home/user/apps/toccards-test/backups/toccards-test-20261009-141000-before-branch-dev-b621d76501e6-20261009140959.dump，1,135,398,457 字节，临时 .tmp 不存在；独立 pg_restore --list 退出 0 并列出 324 项。未做恢复演练，不把目录可读性等同于完整恢复成功。
- API/DB running/healthy、Web running、migration 检查容器 exited/0。只读 SQL 回查 server_version_num=180006、ledger 为 14 项、最新 0013_cards_all_search_trgm.sql；本轮没有待执行的 migration SQL。原 toccards-linux-test_postgres-data:/var/lib/postgresql/data 卷保留，发布目录的 migrations 与该 dev 源码逐文件一致。
- 私有环境文件整体 SHA256 在部署前后完全一致，不记录或回显密钥；Key 保留、限频 60、trustProxy=true，API HostConfig.PortBindings={}。没有修改数据库凭据、代理配置或业务数据；验证仅执行只读卡牌查询，不上传图片、不调用 App 扫描写入。
- API 运行文件 /app/server.mjs、Linux release 与同提交 Windows 本地对照构建 SHA256 均为 68a3410d018ae4c5a18b7ca6322ce6088e7affd22ed670fd94246a87d28d4df0；Web /app/web-server.mjs 的三方 SHA256 均为 94152704c4d0e728e60fc36d98152b36c9698d7cbcfd9cc359d099af2c37bc99。
- Admin 入口返回的 HTML 与 10 个 JS/CSS 共 11 个文件，和 Linux 发布目录原始字节全部一致，根路径 HTML 亦一致。Linux HTML SHA256 为 7a3e56b633f7679b4d9581ecb4217360ca7ab9c34df4f6105ceca8631fee2e35。跨 Windows 本地构建的 10 个 JS/CSS 字节一致，HTML 不一致，差异仅为本地多 12 个 CR 字节（包括 CRCRLF）；不宣称跨平台 HTML 原始字节一致。

### HTTP 与插件详情冒烟

| 实际请求 | 结果 |
|---|---|
| GET /api/v1/health、未登录 GET /api/v1/auth/me | 200/status=ok、401，原 App 鉴权保持 |
| 插件未带 Key、正确 Key 加无效参数 | 401、422 |
| 一次合成 512 维非零向量、card_type=0 | 200、5 个候选、Cache-Control=no-store |
| 候选详情与原 GET /api/v1/cards/:card_ref | 5/5 逐字段一致，均有价格和 HTTPS 图片 URL；未下载图片 |
| 新 API 日志独立回读 | request_id=d3607ad9-b160-4b11-ad45-e7269f93645f，POST /api/v1/extension/recognize，200，duration_ms=907；仅单次冒烟，不是性能验收 |

### 失败记录、自审与未验证边界

- 首次 Windows/Linux HTML 对照检查失败；进一步逐字节定位发现除 CRLF 外还存在 CRCRLF，差异仅 12 个 CR。未修改应用产物或放宽发布目录与线上字节断言；Linux release 对线上 11/11 原始字节检查独立通过，跨平台差异如实保留。
- 首轮两个后台验收命令的 heredoc 结束标记被 DBX 后台包装尾缀连在同一行，Node 语法错误，相关 Node 验收未运行；备份/ledger 前置查询已成功。修正本次命令封装后原验收重跑退出 0，备份校验也单独复跑退出 0。没有因此重跑部署或修改服务代码。
- 仅进行了发布脚本/配置与文档的本地自审，非外部独立 Code Review；未修改业务、测试或部署脚本。部署后只更新本次相关文档和 AGENTS，尚未提交或推送这些记录。
- 未重跑默认完整 Workers 测试；此前默认命令中的扫描用例全量超时记录仍保留，不能以本轮 168 项通过声称全量问题已修复。没有运行 Flutter 分析、iOS/Android 真机、旧包业务闭环、真实照片/浏览器插件、图片加载、63 次限频压测、完整恢复演练或性能/缓存一致性验收。
- 未手工启动第二轮发布、修改 watcher 分支/自动化、清理历史 release/备份/产物、执行 SQL 业务写操作或 Git 推送；prod API/双 Admin、营销站、Flutter 与外部识别服务配置均未发布或修改。开发环境本轮仅对既有识别服务做 health 和一次向量查询。

## 2026-10-09 14:59–15:11：插件业务发布 prod，授权识别链路待补验

### 授权、输入、影响与回退点

- 用户明确要求将新增插件业务部署 prod。输入是干净的本地 `main@c253647ad56b097529bf1d2884d8fead89874c36`，与 GitHub dev 一致；GitHub main 仍为 `f952e50`，本轮没有 push。先完成对现网源码、完整配置、回退版本与双 Admin 的只读快照，再上传候选和切流；文档补证在部署后进行，不属于批准的发布输入。
- 现网发布前 `index.js` 为 2,106,326 字节、SHA256 `32e8c52e147502affcfbd824ac606cf1e8b6fd4114991fc3ebb86eaf08d8beb0`，与先前批准的 `main@61b5420` 生产构建逐字节一致。相对该源码，后端业务增量仅插件入口、共享候选解析导出及入口 IP/限频适配；没有 Admin/营销站/共享包/migration 源码增量。
- 仅新增生产 `EXTENSION_RECOGNITION_RATE_LIMITER`：type=ratelimit、namespace_id=2026100801、limit=60、period=60。既有 `EXTENSION_RECOGNITION_KEY` 已在 prod Secret 列表及 binding 中，未生成、替换或读取明文。用户的现有业务数据、数据库资源、其他变量/绑定、缓存及调度均保留。
- 回退参考：Worker `4adbd0b7-3c67-4795-8ad0-c39795dc4be6`；发布前实际 Pages production deployment `a3da17af-9579-4243-ad1a-c98c17fe0897`。原快照与代码保留；本轮没有回退、删除版本或执行数据库恢复。

### 本地门禁与版本候选

环境：Windows/PowerShell、Node 22.20.0、pnpm 11.9.0、Wrangler 4.106.0。既有 OAuth 具备 Workers/Pages 发布权限；CLI 提示的其他未使用 scope 没有扩权或补登录，工具链没有升级。

| 实际命令 | 退出状态与结果 |
|---|---|
| `pnpm lint` | 0；依赖方向通过 |
| `pnpm type-check` | 0；7 项成功，本轮 7 项缓存命中 |
| `pnpm --filter @kando/admin-web test` | 0；26/26，无跳过 |
| `pnpm --filter @kando/workers-api test --maxWorkers=2 --reporter=dot` | 0；完整默认发现范围 84 文件、771/771，通过且无跳过；仅限制进程并发，不修改断言/超时，不新增排除项 |
| `pnpm --filter @kando/workers-api deploy:dry-run:prod` | 0；Admin production、Worker 构建通过，未发布 |

历史无并发限制的默认测试曾发生 5 秒超时，本轮未重跑该并发配置，不宣称已经定位或修复那个超时根因。完整发现范围通过与默认并发通过严格区分。

批准 Worker 为 2,111,722 字节，SHA256 `63342d0e6fe6569c4758ffef3de5ed3634fbc99c194e8a9e866ce8d883850be3`。批准的 Admin 原始产物另存只读用途副本；源 HEAD/分支/clean 状态与所有产物字节在上传前再次断言。

### 上传、切流及双 Admin 同步

- `pnpm --filter @kando/workers-api exec wrangler versions upload --env prod --keep-vars --tag prod-plugin-c253647 --message <本次插件候选说明>`：退出 0，14:59:51 创建 `e8c5d1fb-0e4d-4eb0-8483-3a77a4ba08fb`。上传后旧 Worker 仍 100% 接流；候选代码经 `content/v2?version=...` 回读与批准字节一致，除了新增限频 binding，原 binding/变量描述符、script_runtime 与 placement 全部一致。静态资产上传器报告没有变更文件。
- `pnpm --filter @kando/workers-api exec wrangler versions deploy e8c5d1fb-0e4d-4eb0-8483-3a77a4ba08fb@100 --env prod --yes --message <本次插件切流说明>`：退出 0，15:01:08 创建 deployment `188b72b5-68a8-473d-9a8e-45019547f663`，新版本为唯一版本、100% 流量。未运行 triggers deploy；既有路由/域名/cron 没有改动。
- `pnpm --filter @kando/workers-api exec wrangler pages deploy <同一批准的 approved-admin-dist> --project-name toccards-admin --branch main --commit-hash c253647ad56b097529bf1d2884d8fead89874c36 --commit-message <双入口产物对齐说明> --commit-dirty=false`：退出 0，15:03:32 Pages `cda22b78-846e-4b91-b6fc-7a69a022c768` 为 production/success；真实 metadata 的 branch/hash/dirty 由 API 回读。CLI 提示并忽略不适用的 Worker wrangler.toml，沿用已有 Pages 项目配置，没有新增 Pages 配置文件。

### 独立生产回读

| 项目 | 实际结果 |
|---|---|
| Worker 代码 | 切流后再次从现网获取脚本，原始字节与批准构建一致，SHA256 同上 |
| 配置/绑定 | 原有变量/Secret binding 描述符、Hyperdrive/KV/R2/Service Binding 保留；只有新插件限频 binding 增加。Secret 明文不可读，未声称逐字节比较 Secret 值 |
| 运行参数/缓存 | compatibility_date/flags、usage_model、observability、logpush 等原值一致；Smart Placement 保持；活动版本 runtime 的 cache_options 仍 enabled=true、cross_version_cache=false；Hyperdrive 完整指纹未变、caching.disabled=false |
| 入口/调度 | 自定义域名、workers.dev/preview 关闭状态、cron `*/5 * * * *` 保持 |
| Pages 项目 | production branch=main、源码/自动发布/构建/环境配置与 active 域名不变；后续 API deployment 仍为本次版本 |
| 双 Admin | 发布前 API 11/11 匹配，Pages 10 个 JS/CSS 匹配但 HTML 不同；独立 Pages 发布后，两入口各 11 个文件共 22/22 原始字节/SHA256 全部匹配。HTML SHA256 `729d63b2610847594f40064b37ce94fad87de8671fa974c082bc016732ea55e0` |

现网 `/settings` 回读省略了 cache_options，本轮使用活动版本的 script_runtime 独立核对，不把省略字段当成缓存关闭。读取 multipart 脚本时，首轮本地断言误将字符串分片当作缺失 Blob；修正验收读取逻辑后完成前后字节对照，未改生产代码或放宽一致性断言。

### HTTP 验证及明确未完成项

- 发布前后均用唯一查询参数执行新请求：health 200/status=ok（MISS）、未登录 auth/me、Admin scans、portfolio folders 均 401；iOS/Android 公开 app-config 均 200；六个响应正文指纹前后一致。Admin 登录 OPTIONS 为 204，允许来源仍为正式 Admin 域名。
- 新插件入口无 Key、错误 Key、错误认证格式均为 401 `UNAUTHORIZED`、`Cache-Control: no-store`；请求 ID 回传正常。未用这些拒绝请求冒充成功识别或限频调用验证。
- **正确 Key 的生产业务链路未验收**：当前只有生产 Secret 的名称/类型可核对，明文不可用。没有借用 dev Key、尝试绕过鉴权或临时改生产 Key；没有执行有效 Key 下的参数 422、触发 429、合成/真实向量识别及候选详情比较。插件发布负责人需提供受控生产调用凭据后补验，不能拿上午 dev 的 5 候选结果替代生产验收。
- 未进行真实浏览器插件、图片加载、iOS/Android 真机、旧 App 完整兼容/登录态/扫描/购买闭环、性能与缓存一致性验收；未重新验证外部识别服务公网旁路限制。没有迁移/schema 增量，因此本轮未执行生产数据库迁移、业务写请求、备份恢复或独立 ledger 回查，不宣称实时 pending migrations 为零。
- 没有 Git commit/push、Linux dev/营销站/Flutter 发布，也未修改 Pages 自动部署、外部识别服务配置或清理历史材料。原 `toccards-website` 远端构建失败不属于本次部署目标，未在本轮整改或判定其根因。
- 本轮只审查发布范围、现网差异、回退点、配置保留和验收脚本，非外部独立 Code Review；无业务代码修复。原始产物、前后脱敏控制面、HTTP 结果与日志保存在本地忽略目录 `apps/workers-api/.wrangler/prod-extension-20261009-1791528849713/`，没有加入 docs/Git。后续仅更新本次相关文档和 AGENTS，尚未提交。

收尾复核（15:11:39）：Worker 仍为上述单一版本、100% 流量，Pages production 仍为上述 deployment；配置、Hyperdrive、cron、域名与验收时一致。额外确认 Admin OPTIONS 允许 POST，未触发其他发布。6 份文档/Agent 规则的 56 处本地链接检查与 `git diff --check` 均通过，改动仅本次文档，无业务代码或冻结基线修改。

## 2026-10-09：main 提交推送后的文档补证

- 上轮按用户授权提交并推送：`dbc2091a16f943903e3db3ea9b5314a52f47d730`，提交时间为北京时间 15:16:13，说明为 `docs: record production extension deployment verification`。远端 main 从 `f952e50` 快进到 `dbc2091`，连同此前本地已合入的 `b621d76` 插件业务和 `c253647` dev 发布记录，共交付 3 个提交；没有强制推送。
- 本次只读复核 `git ls-remote --heads github refs/heads/main refs/heads/dev`：远端 main 为 `dbc2091a16f943903e3db3ea9b5314a52f47d730`，远端 dev 为 `c253647ad56b097529bf1d2884d8fead89874c36`，均与本地分支一致。`git merge-base --is-ancestor dev main` 退出 0，main 包含全部 dev 提交；文档编辑前工作区干净。
- `git diff --name-only c253647..dbc2091` 只有已提交的 6 份文档/Agent 规则；`git diff --exit-code c253647..dbc2091 -- apps packages deploy .github` 退出 0。因此最近已验收的 prod 发布源仍是 `c253647`（Worker `e8c5d1fb`、Pages `cda22b78`），不能把文档提交 `dbc2091` 写成又一次已验收的运行发布。Linux dev 最近已验收源仍为 `b621d76`，不因远端 dev 变为 `c253647` 而推断其已再次部署。
- 本地分支、远端跟踪引用及 `git ls-remote --heads github "refs/heads/dev-ext*"` 均无匹配；`dev-extension` 已不再是工作分支。旧 release、dirty 工作区及其分支名保留为历史证据，未清理历史产物。
- 上文 14:59–15:11 发布记录中的“尚未提交/没有推送”描述该阶段的事实，原样保留；这次补证说明后续提交推送结果。此轮仅同步文档，没有再次 commit/push、部署或查询 Cloudflare/SSH 运行状态；推送触发的 CI/自动发布未验收，生产正确 Key 的识别/详情/限频、真实插件与真机等未验边界保持。

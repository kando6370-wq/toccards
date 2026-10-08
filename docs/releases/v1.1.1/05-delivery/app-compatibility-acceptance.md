# App 1.0.4+ 服务端兼容验收矩阵（计划，未执行）

状态：2026-09-28 制定，依据[兼容契约](../03-data-api/app-compatibility-contract.md)。目标是每次新 App 或配套服务端发布后，已发布的受支持旧包仍能使用其原有业务（包括读取新版写入的共享数据），不是要求旧包获得新功能。**“版本”按 `1.0.4`、`1.0.5` 等营销版本计；`(161)` 等修复构建号只用于分发制品和验收证据，不单独计为新版本，已分发旧构建仍须可用。**以下每一行均为未来发布门禁，不是本任务测试结果。既有 v1.1.0 自动化与发布记录只作起点，不可替代旧客户端冻结合同与真实制品验证。

## 1. 客户端和环境证据

| 层级 | 使用对象 | 能证明什么 / 不能证明什么 |
|---|---|---|
| 版本登记 | 每个平台实际发布的营销版本及该版本下的分发构建清单，分别登记 Bundle/包名、渠道、制品 SHA-256、API origin、最低系统版本与协议差异 | 以营销版本界定支持集合；同版修复构建不新增版本行，但要保留可识别的制品与差异证据，仅有源码版本或营销版本相同不能证明分发包等价。Android 1.0.4 正式分发基线仍待确认。 |
| 合同自动化 | 每个受支持营销版本的冻结请求/响应样本、错误与副作用断言，以及对应旧 DTO 解析；同版构建的协议相同时可复用执行组，存在差异时补测旧构建 | 证明候选服务端仍接受旧包语义及新版写入数据的旧版响应；不能仅用新 App 源码生成样本，也不能代替设备。样本、反例和真实包来源目前**待建立**。 |
| dev Linux | 用 `v1.0.4` 源码和 `config/test.json` 构建双端测试包连接 dev 独立数据库；新 App 写入后再以旧包读取并执行原有操作 | 验证候选 API 与跨版本数据路径；Bundle、App Attest、配置/签名不同于 production，不能称为同一个生产 IPA。真实设备、测试账号和内网权限尚待安排。 |
| prod Cloudflare | 保存并校验 [1.0.4 (161) 正式 IPA](../../v1.1.0/05-delivery/VERIFICATION.md) 的 SHA-256；按实际可获取的正式分发包，对最早受支持营销版本、上一已发布营销版本及有协议差异的构建抽查原有关键路径；Android 先确认真实分发制品 | 抽查只证明所测构建及场景，不能称所有历史制品已实测。正式包 API origin 固定，若无候选服务端可达路径，切流后烟测只能作为发布后证据；登录、资产、Scan、Apple 交易等生产写入与外部调用另需明确授权。 |
| 系统与平台 | iOS 16+、Android API 24+；Android Premium 销售范围待决 | iOS `<16` 和 Android `<24` 不属于本基线。Android 正式 1.0.4 包尚无同级分发证据，不能用 iOS 结果外推。 |

## 2. 每次服务端或 App 发布的兼容矩阵

状态初值统一为**未执行**。逐项记录适用平台/营销版本与实测构建、前置数据、输入、预期响应与副作用、实际结果和证据层级；结果只用通过、失败、未执行、不适用（附依据），不以“未执行”替代“通过”。P0 失败或承诺范围内必需的制品/权限缺失时，不得宣称相应平台的“1.0.4+ 持续兼容已验收”；被外部条件阻塞须写明原因、责任人与补验方式。表中现有测试文件只证明已有覆盖点，仍需加入冻结客户端合同和跨版本数据测试。

| ID / 优先级 | 业务场景与验收断言 | 自动化起点与必须补的证据 |
|---|---|---|
| C01 / P0 | iOS/Google 公共配置各按自己的环境与平台读取；1.0.4 可解析 `upgrade_prompt`（含旧文案字段）或 `null`；已批准最低版本不被候选服务端意外提高，失败显式返回。1.0.4 客户端只比较营销版本而忽略 `+161` 等构建号，不能以提高同营销版本构建号作为兼容或强更手段。 | `src/app-config/version-control.integration.test.ts`、`app_upgrade_policy_test.dart`；补 1.0.4 响应样本、`min=latest=1.0.4/force_update=true` 旧包仍可用，以及发布前后只读回读。 |
| C02 / P0 | 匿名/注册登录、找回密码、Token Refresh 后透明重试、登出/会话失效和账户删除旧行为不变；不同 owner/session 隔离；旧包不会因新增 Header/字段变为 4xx。无有效身份仍为 401，越权保持各接口既有的 403/404 且不泄露数据、不产生副作用。 | `src/owner-auth.integration.test.ts`、`auth_repository_test.dart`、`auth_session_interceptor_test.dart`；补旧包登录、切号、过期 token 与跨 owner 资源的接口级状态码/副作用证据；生产删除账号另需专门授权。 |
| C03 / P0 | Games→Search/Set→详情/市场价与历史、汇率：旧包能解析分页、字符串 card ref、缺价 `null` 与合法零价；新增字段不改变价格/币种口径，不把网络/DB 失败伪装为空列表。 | `src/data-source/routes.test.ts`、`card_data_api_client_test.dart`、`currency_rate_api_test.dart`；补冻结响应样本及真实目录抽样。 |
| C04 / P0 | Folder/Collection/Wishlist 创建、编辑、删除和刷新保持 owner 隔离；超时/不确定响应复用原业务幂等键，不重复建项，明确 409/422 保持语义；新版写入旧版原有资产后旧包仍能读取并操作。 | `src/portfolio/items.test.ts`、`src/portfolio/collect.test.ts`、`portfolio_api_client_test.dart`；补同账号新写旧读、旧包设备重复提交与断网恢复。 |
| C05 / P0 | `dev-xiangyang` 的 JPEG+三通道 `r/g/b` pHash、`card_type=0/1` 能完成 reserve→recognize→Review→confirm；缺少可选 `card_type` 默认 TCG，`card_number` 可选；旧 512 维 `vector` 返回明确 422 且不写图/耗额度。 | `src/scan/routes.test.ts`、`scan_api_client_test.dart`；补两端真实图片、TCG/Sports 与当前候选目录的设备结果。pHash 上游不接收 `card_type`，Sports 召回尚未真机验收，也不额外承诺完整 Sports 入库。 |
| C06 / P0 | Free 终身 10 次；仅完整 Matched 扣 1 次，No Match/技术失败释放；并发 Gallery、Timeout 与同业务 ID 重放后最终 Quota 与账本一致、不双扣，Premium 不扣 Free。 | `src/scan/quota.integration.test.ts`、`src/scan/routes.test.ts`、`scan_page_test.dart`；补同账号并发/弱网和服务端最终账本核对。 |
| C07 / P0（iOS） | Fresh Purchase/Restore 仅在 Apple 验证证据与当前 live session proof 成立后授予服务端 Premium；过期/退款撤销、无 proof 和不同 session 不误授权，旧包可识别既有错误；新版交易状态不得让旧包旧权益路径失效。 | `src/entitlements/routes.integration.test.ts`、`src/entitlements/restore-routes.integration.test.ts`、`subscription_entitlement_api_test.dart`；每版跑无副作用的权益合同/安全回归，权益链改动须补获授权的 Sandbox/TestFlight 生命周期与设备证据，未跑则单列未验证。Android 售卖/授权范围另待产品确定。 |
| C08 / P0 | 图片/分享与受保护扫描图保留 URL、鉴权和内容语义；网络传输层或超时策略变化时，旧包不得因此重复提交写请求。 | `src/scan/scan-image.test.ts`、`app_http_transport_test.dart`、`widget/kando_card_image_test.dart`；补真实图片列表，传输层改动时补弱网和内存峰值（尤其 Scan 上传）；不把 HTTP/2/3 协商当成每条 API 的业务字段。 |
| C09 / P0 | `X-Request-ID` 缺省/合法/非法值都不改变 API 业务包络；401 刷新后的物理重试换传输 ID，但同一业务操作保留 Idempotency-Key；超时、409/422/5xx 显式失败。 | `src/request-id.test.ts`、`api_request_id_test.dart`、`auth_session_interceptor_test.dart`；补冻结旧客户端无/有 Header 样本。 |
| C10 / P0（发布门禁） | PostgreSQL schema/迁移、缓存键和路由切换不得让旧包读取旧字段或新版写入的原有资产失败；候选服务端须在发布后目标 schema 上保持权限、价格和资产语义。若部署方案包含前一服务端版本滚动共存/回退，再单独验证该明确版本与新 schema，不承诺任意历史服务端可回滚。 | 受影响的 `src/db/postgres/`、目录/Portfolio/Scan 集成测试及新写旧读合同；任何 migration 先独立说明环境、备份、兼容和回退，并另行授权。D1 不参与。 |
| C11 / P0（制品证据） | 实际分发的 1.0.4 iOS 包、上一已发布营销版本的包及有协议差异的分发构建按原有关键路径抽查；修复构建不另算新版本，但已安装旧构建仍需可用。Android 正式包先确定发布事实与制品后才可宣称对应正式包验收。冻结合同覆盖所有受支持营销版本及构建间已知协议差异，真机抽样不代表未测历史构建均已实测。 | 记录平台、Bundle/包名、营销版本与实测构建号、制品哈希、API version、设备/网络、请求 ID、结果与时间；当前 iOS/Android 完整登录态矩阵**未执行**，Android 正式包基线**待确认**。 |
| C12 / P0 | 估值历史、Home/Card Detail Performance：旧版可解析 Free/Premium 响应、部分历史、无数据与网络/服务错误；新版写入价格/资产后不伪造零价或历史点，仍保持 owner/session 授权。 | `src/portfolio/performance.test.ts`、`src/portfolio/performance-premium.integration.test.ts`、`src/portfolio/valuation-history.test.ts`、`portfolio_api_client_test.dart`、`home_performance_controller_test.dart`；补冻结旧包响应与新写旧读样本。 |
| C13 / P0 | 新版 App 在同账号创建/修改旧版原有 Folder、Collection、Wishlist、Scan 或价格相关数据后，旧版列表、详情和原有编辑/删除路径仍可用；新枚举/状态和可选字段不导致旧 DTO 解析失败，旧版操作也不破坏新版数据。新功能独有数据明确隔离/降级，不污染旧列表或隐藏旧资产。 | 候选 API 上按“新版写→旧版读/原有操作→新版再读”建立固定样本与业务断言，关联 C03–C07、C12 的实际旧客户端解析和 owner/权益测试；新 App 涉及共享数据时发布前必验，尚无专用测试。 |

支持集合按营销版本计；每条实际执行证据以“服务端 SHA × 旧包平台/营销版本 × 实测构建号 × 场景 ID × 环境”标识，构建号是制品证据而非新增版本，不用一个构建的通过覆盖存在协议差异的其他已分发构建；仅发布新 App 时另登记新包 SHA。执行记录至少包含下列字段，不在设计稿中预填结果：

| 字段 | 单次发布必填内容 |
|---|---|
| 版本与前置 | 旧包分发来源/制品 SHA、系统和设备、新包及服务端 SHA、API origin、测试账号/owner 与数据种子；正式包与源码测试包分列。 |
| 输入与断言 | 请求方法/路径/样本 ID、旧 DTO 解析、HTTP/业务码、额度/权益/写入副作用，以及新版写入后旧包读取和原有操作的预期。 |
| 证据与结果 | 自动化命令和退出码、dev/prod 设备或服务端日志及请求 ID；结果为通过/失败/未执行/不适用（附依据），未执行写明阻塞原因、责任人和补验条件。 |

## 3. 执行与放行规则

1. 每次服务端候选在**干净 checkout**运行受影响的 Workers/Flutter 测试、依赖方向与类型检查，再跑各受支持营销版本的冻结请求、旧 DTO 解析及跨版本共享数据合同；同版修复构建若协议相同可复用执行组，有差异则补测并保留旧构建可用的证据。仅发布新 App 时，至少运行与旧包共用的数据/协议场景和受影响模块，不能只测新包。当前仓库曾有忽略的 `.wrangler/` 临时测试污染无参数 Vitest 运行；以实际项目测试配置或限定 `src` 的命令执行并记录范围，绝不把被中止/超时的首轮算作通过。
2. dev 先验 1.0.4、上一已发布营销版本及有协议差异构建的双端可用制品和受控账号，重点覆盖旧版原有关键路径及“新版写→旧版读/原有操作”；同版普通修复构建不另增版本基线。正式包若只能连接 prod，不能以 dev 测试包冒充预发布正式包验证。prod 切流后复核部署/version/关键绑定、公开接口及 Admin 静态资源，再在取得账号、生产写入与外部服务授权时执行生产旧包业务烟测。**生产只读 200/401 与静态资源哈希不等于登录态兼容通过。**
3. 每次发布对照 1.0.4 及所有后来仍受支持的已发布营销版本的冻结合同；同版修复构建不新增独立版本行，但须覆盖已知的协议差异及旧构建继续可用。实际旧包抽查最早、上一营销版本和差异构建，具体只报告已测制品/场景，不以抽查概括全部旧包。P0 失败则停止服务端切流或新 App 发布；已经切流时仅按已验证方案回退；承诺范围内必需的制品、预发布路径或外部服务缺失时须标记未验证，并明确由谁补验/批准风险，不能宣称该平台兼容已验收。确需破坏性改变时先提出版本化接口与持续服务旧路径的方案，或请求产品明确批准改变支持窗口；Git 合并、文档批准均不代替远程部署授权。
4. 每次执行按平台、受支持营销版本（附实测构建号）、合同 ID、环境和证据层级记录日期、服务端代码 SHA、制品 SHA、命令/退出码、通过/失败/未执行/不适用及补验责任，落在当次 v1.1.1 交付记录；本设计文档不预填任何成功结果。

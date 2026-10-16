# 订阅展示配置与商品准入（第一阶段）

需求输入：[PRD 1.14](../00-product/admin-subscription-config-prd.md)。本文件描述服务端第一阶段源码，Admin 第二阶段页面见 [后台文档](../04-admin/admin.md)，Flutter 消费源码见 [客户端流程](../01-flows/subscription-display.md)，测试 App 的[真实 Apple 目录读取](../05-delivery/VERIFICATION.md#subscription-config-apple-catalog-live)已通过，商品售卖、展示准入和旧包新增 SKU 恢复仍未验收。接口均为 V1 兼容新增，原 app-config、购买、Restore 与权益接口的 V1 请求／响应合同保持不变；动态商品扩展其受控准入来源。

## 环境与商品准入

存储作用域固定为 `APP_ENVIRONMENT:APPLE_IAP_BUNDLE_ID`，不接受客户端传入任意作用域。生产和测试数据库分别运行；即使共用测试数据库，不同环境／Bundle 也不能读写彼此配置。

| 配置 | 含义 |
|---|---|
| `APP_STORE_CONNECT_APP_ID` | 当前 App Store Connect 数字资源 ID，目录读取先核对其 Bundle ID 与 API 配置一致 |
| `APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID` | 当前 App 所属的唯一指定订阅组，读取 App 的完整组列表验证归属 |
| `APP_STORE_CONNECT_ISSUER_ID` / `APP_STORE_CONNECT_KEY_ID` / `APP_STORE_CONNECT_PRIVATE_KEY` | 具备本 App 目录读取权限的团队 API Key，ES256 JWT，有效期 5 分钟；服务端专用，不复用或自动回退到现有验单凭据 |
| `SUBSCRIPTION_LIFETIME_PRODUCT_IDS` | 允许配置的非消耗型永久 Premium 商品范围；缺失时一次性目录不可用，不把任意非消耗型商品当作 Lifetime |
| `SUBSCRIPTION_DISPLAY_PRODUCT_IDS` | 旧部署已经批准的展示商品集合，逗号分隔；保留兼容，新 SKU 改走超级管理员动态审批，不再逐项改此变量 |

上述新配置均可缺省，不阻止已有 Linux API 启动或旧购买接口工作。Cloudflare 通过同名变量／Secrets 注入；Linux 通过现有 `.env` 注入，示例不包含真实 ID 或密钥。没有凭据时新目录及需要重新校验目录的写入返回 503；已有配置读取、结果核对和关闭配置不访问 Apple。

dev 已[落地并加载目录配置](../05-delivery/VERIFICATION.md#subscription-config-dev-catalog-env)。2026-10-15 17:59 回读当前 release 为 dev@e53f75c，PostgreSQL ledger 包含 0014；原三个 cardx 商品与 weekly.trial／yearly.pro 共五项已完成本轮 dev 服务端准入。Page／Modal 仍无生效配置，真实 StoreKit 购买／恢复及平台收入接收未验，详见[商品接入结果](../05-delivery/VERIFICATION.md#dev-subscription-product-onboarding)。

有效商品须通过旧环境名单（`APPLE_IAP_PRODUCT_IDS` 与 `SUBSCRIPTION_DISPLAY_PRODUCT_IDS`）或下述动态审批，且 `billing_product` 为 active、类型匹配、权益为 `performance_pro`。目录接口返回每项 `admission.admitted/reasons`；未准入商品允许保存在不生效配置，启用和保存已生效配置时拒绝。保留但未启用的试用目标仍校验关系结构；它不参与本次生效购买的准入集合。

**展示编辑不注册或删除权益商品。** 独立的超级管理员审批操作可以注册商品；移除卡片与关闭配置不删除准入、映射、购买链或 session grant。

## 动态商品准入（2026-10-16 本地增量）

管理员在目录选择商品后，超级管理员通过 `POST /api/v1/admin/subscription-products/admit` 审批。请求包括 UUID v4 request_id、product_id、product_type、expected_scope、singular_event_name，以及 acknowledge_legacy_restore_limit=true。系统重新读取真实 Apple 目录，验证当前 App／订阅组／类型，确认目标 scope 与运行环境完全一致；普通 operator 返回 403、环境不符返回 409。收入事件名由审批人按当前 dev/prod 确认，不自动猜测 test 后缀。

审批使用现有 subscription_display_mutation 的幂等和结果核对机制。scope 锁与商品锁下，事务新增缺失的 billing_product（稳定 plan_id 为 apple:ProductID、performance_pro、active=1），保留已有兼容映射；已有 inactive、不同类型／权益或计划冲突返回 PRODUCT_MAPPING_CONFLICT，不覆盖旧数据。审批记录写入现有 PostgreSQL app_config 的 billing.apple.admission:环境:Bundle 键，记录商品类型、试用分类、计划、收入映射、审批人和时间。没有新增 schema／migration，不使用 D1；目标环境仍须已安装订阅配置原有的 0006／0014 迁移，不能将“本次无新迁移”理解为 prod 首次接入无需核对 ledger。

运行期购买白名单是旧环境名单与当前 scope 审批记录的并集。Fresh Purchase、Restore、Premium／生命周期、通知补单／Server API 校正及 Admin 订单范围使用这一来源；升降级通知保留旧商品基线并接受当前 scope 已批准的订阅。购买仍验证 Apple 签名、Bundle／环境、session challenge 或 App Attest，以及 active 权益映射。审批不跳过 Apple 可售和真实交易验证，不直接发放权益。

动态模块要求保留 APP_STORE_CONNECT_APP_ID 及环境／Bundle 配置；没有配置该可选模块的旧环境继续使用原名单。目录私钥不参与日常购买白名单读取。启用动态商品后不得删除模块 App ID，否则动态商品不再被运行期接受。dev 与 prod 独立审批，即使共用数据库或都接收 Sandbox 交易，也不跨 scope 共享。现有账单表不以 Bundle 分行，因此同一数据库内同一个动态 Product ID 只能属于一个 scope；跨 scope 重复审批返回 PRODUCT_SCOPE_CONFLICT，并由商品锁保护并发检查。历史环境名单保留，不再为每个新 SKU 修改环境变量或源码。

新增 GET /api/v1/subscription-supported-products?platform=ios|google 返回当前 scope 的长期已批准商品及收入映射，不受 Page／Modal 是否启用影响、不暴露管理员信息；Google 返回空集合。新客户端读取此接口并按 API／环境／Bundle 隔离缓存，用于购买监听、展示加载和 Restore；旧包继续原 V1。1.0.4／1.0.5 无法识别包内未登记的新 SKU，审批须明确确认此支持边界，不将其记作旧包恢复已验收。非消耗型仍受 SUBSCRIPTION_LIFETIME_PRODUCT_IDS 的明确 Premium 范围约束；本次不开放任意一次性商品。

代码回退须保留新增 app_config 键及 billing_product；旧代码不会读取动态名单，因此已有新 SKU 开始售卖后，不得仅回退代码而不同时安排这些商品的购买／恢复支持。本文为本地源码契约，远端部署和真实商品批准以验证记录为准。

## dev 商品接入映射（2026-10-15）

用户确认在独立 dev 环境接入 weekly.trial 与 yearly.pro。两者均为自动续期订阅、授予既有 performance_pro 权益，分别使用独立 plan_id=weekly_trial 与 yearly_pro；不复用原 weekly／yearly，也不修改原六条 billing_product 映射。仅新增商品数据与环境允许范围，不新增 schema 或 migration。

购买白名单保留 cardx.week、cardx.year、cardx.lifetime，并追加 weekly.trial、yearly.pro；本次展示准入对应这五个已注册 dev 商品。实际配置仍最多三张展示卡片，关联目标另计购买准入。更新前备份私有环境与目标商品表数据，按原 watcher／deploy 锁串行操作；环境更新仅涉及 APPLE_IAP_PRODUCT_IDS 和 SUBSCRIPTION_DISPLAY_PRODUCT_IDS，API 重载沿用原镜像及业务产物。

环境变更的实际结果以[商品接入验证](../05-delivery/VERIFICATION.md#dev-subscription-product-onboarding)为准，原凭据、Apple 商品设置、原有交易／权益及生产配置保持原边界；商品准入不等于真实 StoreKit 资格、可售、购买／恢复或收入验收。该历史接入点的新 SKU 升降级识别仍受旧 PLAN_CHANGE_PRODUCT_IDS 限制；2026-10-16 本地增量允许经动态审批登记的订阅参与该分支，尚未发布，不能据此改写历史运行状态。

## Apple 目录读取

- `GET /v1/apps/{id}` 核对 Bundle；订阅从 App 的组列表验证指定组后读取组内 subscriptions，并读取每个商品的 introductoryOffers／territory。
- 一次性使用 `/v1/apps/{id}/inAppPurchasesV2`，仅选择显式范围内的 `NON_CONSUMABLE`。商品基本字段、周期与等级均取真实 Apple 响应，不根据 Product ID 命名猜测。
- 列表全部翻页。后续 URL 只能保持 Apple HTTPS origin 和同一个资源列表路径；循环、跨来源／资源跳转、异常或缺失字段直接失败，不返回部分成功或假空数据。整次目录请求预算 10 秒，不跟随 HTTP 重定向。
- 免费试用目录分类仅表示在检查日（UTC 日期）至少一个地区具有有效 `FREE_TRIAL` 介绍性优惠。返回原始地区、日期、duration、numberOfPeriods；未来／已过期／付费优惠保留事实但不计为当前免费优惠。该标记不是当前用户／storefront 的资格或可购买承诺，日期边界必须由 StoreKit 最终确认。
- Apple 401/403/429/网络失败返回 503；真正成功的空列表返回 200 和空 products。响应不回显 Apple 错误正文、JWT 或私钥。

## 管理端 API

所有路径位于 `/api/v1/admin`，复用当前活跃管理员和会话验证，配置编辑与生效允许 `super_admin`、`operator`；商品审批仅允许 `super_admin`。新增中间件仅覆盖本模块路径，不改变其他 Admin 上传、缓存或请求大小行为。本模块 JSON 请求技术上限 256 KiB，不设置 30 秒关闭延迟业务上限。

| 方法与路径 | 合同 |
|---|---|
| `GET /subscription-products?type=subscription` 或 `non_consumable` | 读取该类型的目录与准入状态，两类读取相互独立 |
| `POST /subscription-products/admit` | 超级管理员按当前 scope 审批，原子注册商品与准入，使用同一 request_id 结果核对机制 |
| `GET /subscription-configs` | `{items, active}`；items 与 page/modal 生效指针及 active_revision 在同一 PostgreSQL 语句快照中读取 |
| `GET /subscription-configs/:id` | 本作用域详情，包含 body、revision、enabled、更新时间及管理员 ID |
| `POST /subscription-configs` | `{request_id, config}`；201，新配置永远不生效 |
| `PUT /subscription-configs/:id` | `{request_id, expected_revision, config}`；200，保存完整编辑副本；保留启用归属，已启用配置不能直接变更类型 |
| `PUT /subscription-configs/active/:page_type` | `{request_id, config_id, expected_active_revision, expected_config_revision}`；config_id=null 关闭，此时不需要目标内容版本；目标启用必须同时确认指针及内容版本 |
| `GET /subscription-config-mutations/:request_id` | 仅原操作者可核对；无记录返回 `status=unknown`；有记录返回 succeeded/failed、http_status 与原 response |

所有写入使用 UUID v4 `request_id`，编辑版本为正整数，初始生效指针版本 0。结果 HTTP 包络沿用 `{success,data}`／`{success:false,error:{code,message,fields?}}`。不允许通过客户端传入目录事实、准入结果、scope 或 enabled 绕过服务端判断。

`config` 的形状：

```json
{
  "schema_version": 1,
  "name": "运营内部名称",
  "page_type": "page",
  "trial_enabled": false,
  "trial_toggle_text": "",
  "cta": "",
  "close_delay_seconds": 0,
  "skus": [{
    "product_id": "<真实 Product ID>",
    "product_type": "subscription",
    "price_mode": "actual",
    "is_default": true,
    "name": "Weekly",
    "subtitle": "",
    "badge": "",
    "price_note": "",
    "cta": "",
    "billing_note_mode": "custom",
    "billing_note": "",
    "trial": null
  }]
}
```

- `product_type` 为 subscription／non_consumable；price_mode 为 actual／weekly；说明方式为 custom／auto。`trial` 可省略或 null，存在时为 `product_id` 加相同营销字段（不含默认项、价格模式）；空目标可保留替换文案。
- 可选文案缺失补空，CTA 拒绝花括号，长度用 JavaScript UTF-16 单元。基础名称、唯一默认、1–3 张展示卡片始终校验。切换启用时要求开关文案、至少一组完整关系及试用名称；关闭时保留隐藏试用文本，不验证其必填／长度／CTA，但引用结构与去重继续验证。
- 2026-10-15 用户补充规则：每组配置的页面展示 SKU 为 1–3 个，Page／Modal、未生效／已生效配置均适用。数量仅计算 `skus` 数组；关联试用目标不额外占名额，独立展示的试用商品和一次性商品各占一个。新增、保存与启用超限配置返回 `422 VALIDATION_ERROR`，字段路径为 `skus`，不改变原内容、版本或生效指针；保留失败幂等结果。存量超限数据不自动删减，Admin 仍可完整读取并修正；公开读取超限生效配置返回 `503 SUBSCRIPTION_CONFIG_UNAVAILABLE`，由 App 按既有规则兜底，不截取前三个商品。无需新增迁移或 V2。
- 基础与所有保留关系目标在配置内共同去重；关系为非试用自动续期源→当前免费试用目标，同组同周期同等级。Lifetime 不可配试用，未定义周期不可配 weekly。
- 保存和启用重新读取 Apple 目录。即使只改文案，目录失败也返回明确未写入的 503 并保留原配置；服务端没有新增目录缓存或把未知 ID 判为已删除。前端需保留输入，外部服务恢复后使用新请求 ID 重试已经明确失败的操作。

## 并发、幂等与 PostgreSQL

迁移 [0014_subscription_display_config.sql](../../../../apps/workers-api/src/db/postgres/migrations/0014_subscription_display_config.sql) 仅新增三张表：

- `subscription_display_config`：scope、page_type、body JSONB、revision 和更新信息。
- `subscription_display_active`：主键 scope＋page_type，指向零或一个 config_id；复合外键强制引用同作用域／同类型的配置。
- `subscription_display_mutation`：scope＋request_id 唯一，保存操作者、请求指纹、执行标识及结果。

沿用 PostgreSQL `batch` 事务与现有 mutation_lock 表，每作用域串行写入。在获得该作用域行锁后，用后续语句的 READ COMMITTED 快照重新检查当前配置／指针版本及生效商品映射；生效购买涉及的账单商品行以 FOR SHARE 锁定至提交，避免准入核对后映射被并发改写。Apple 查询在事务外执行。保存数据和最终幂等结果同事务提交，任一步失败整体回滚。序列化 JSON 先按 text 参数绑定，再转换 jsonb，避免 postgres.js 按 JSON OID 二次序列化字符串；PGlite 与真实 PostgreSQL 均需验证该边界。未修改现有 Database／D1 兼容类型、旧迁移或权限／购买模型。

请求指纹规范化对象 key 顺序，保留 SKU 数组顺序和 null／缺字段区别；绑定方法、目标路径和请求内容。同 ID、同操作者、同请求返回原结果，换 payload 或操作者返回 409。目录故障后的成功操作仍可重放，不依赖 Apple 重新可用。

无结果记录表示“未知”，不能当作确认未写入；原请求可能还在目录读取或事务中。客户端按 PRD 执行 15+15 秒等待，后续只能先核对或安全重放同 ID、同 payload；明确失败后修改输入／重试必须换新 ID。结果核对不开放给其他管理员。

错误语义：VALIDATION_ERROR 422、CONFIG_NOT_FOUND 404、CONFIG_CONFLICT／ACTIVE_PAGE_TYPE_IMMUTABLE／IDEMPOTENCY_CONFLICT 409、PRODUCT_NOT_ADMITTED 422、CATALOG_NOT_CONFIGURED／CATALOG_UNAVAILABLE／CATALOG_INVALID_RESPONSE／CATALOG_SCOPE_MISMATCH 503。数据库或未知内部失败返回 SUBSCRIPTION_CONFIG_UNAVAILABLE 503，不误报成功；需随后核对原 request_id。

## App 读取与兼容边界

`GET /api/v1/subscription-display-config?type=page|modal&platform=ios|google` 是新增公开只读接口。platform 缺省 ios，google 返回成功且 data=null，不读取 Apple 配置；未知枚举拒绝。无生效配置返回 `{success:true,data:null}`，实际读取失败仍返回失败。

成功 data 包含 schema_version=1、config_id、revision、page_type、关闭延迟、CTA、开关和有序 skus；不返回内部配置名称、管理员、scope、凭据或准入理由。关闭关联功能时输出空开关文案及 null trial，不将保留目标暴露为可购买卡片。每次读取验证当前环境准入／权益映射；已撤销准入的生效配置返回 503，让新客户端走独立兜底，不更改其历史购买。

旧客户端仍走原接口，不要求增加请求字段，也没有向已有枚举塞入新状态。该兼容新增不证明新 SKU 能在旧包 Restore；其支持范围仍须按原 PRD 接入核对。Flutter 实际资格三态、真实计费展示、15 秒预算与 CTA 回退的本地实现见 [客户端流程](../01-flows/subscription-display.md)，服务端不伪造资格或价格；原生与真机验收独立记录。

## 环境影响、回退及验证

部署前按目标环境核对 PostgreSQL ledger、目录凭据与已审核商品范围。2026-10-15 dev 已回读到既有 0014，本轮仅新增两条商品映射、更新两个环境字段并重载同镜像 API，没有新增或执行 migration；prod 未操作。缺少新表时仅新模块失败，不重绑定旧 D1。回退代码保留新增表和历史权益数据；关闭生效配置或回退使用原接口的客户端，不删除账单／映射，也不让展示列表收窄恢复集合。

独立多连接检查使用 `pnpm --filter @kando/workers-api test:subscription-config:postgres`，要求显式设置 `SUBSCRIPTION_TEST_DATABASE_URL`。脚本仅接受 loopback 的空 `subscription_config_test` 数据库，拒绝其他地址、数据库名或非空库；不进入默认测试命令，也不会静默跳过。它使用两组真实 PostgresDatabase 连接和独立锁持有／观察连接，以 `pg_stat_activity` 确认实际锁等待，覆盖重复创建、并发生效、并发编辑、准入行锁及事务回滚。临时数据库和容器的创建／清理由调用方负责，不连接既有业务数据库。

相关测试与实际执行结果见 [验证记录](../05-delivery/VERIFICATION.md#subscription-config-server)。测试 App 的目录权限已有真实只读补验证据；销售范围、StoreKit 可购买状态、生产目录权限／数据库、新旧包和收入平台仍需独立核验。自动化目录测试仍使用注入响应，与真实只读补验分开记录；运行时代码没有演示数据或假目录回退。

主要实现：[路由](../../../../apps/workers-api/src/subscription-config/routes.ts)、[事务存储](../../../../apps/workers-api/src/subscription-config/store.ts)、[目录](../../../../apps/workers-api/src/subscription-config/catalog.ts)、[模型校验](../../../../apps/workers-api/src/subscription-config/model.ts)。Apple 接口字段和 JWT 合同已查阅官方 App Store Connect 文档：

```text
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptiongroups-_id_-subscriptions
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-introductoryoffers
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-inapppurchasesv2
https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
```

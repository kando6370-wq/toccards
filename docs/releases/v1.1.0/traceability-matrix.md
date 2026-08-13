# v1.1.0 需求可追踪矩阵

## 1. 使用规则

本矩阵以三份 v1.1 原始 PRD 为产品依据，以当前分支代码、迁移和自动化测试为实现证据。`代码已完成` 只表示仓库内闭环成立；需要 Apple 配置、远程迁移、真机、Sandbox/TestFlight 或规模数据的项目仍不得视为发布完成。

状态定义：

- `代码已完成`：实现与自动化证据均存在。
- `代码已完成，外部验收待完成`：仓库内能力已闭环，但发布环境证据不足。
- `产品待决`：PRD 没有给出可测试口径，开发不得自行设定。

## 2. App 与服务端能力

| PRD 条款 | 实现证据 | 自动化证据 | 状态与剩余边界 |
|---|---|---|---|
| [App 0.3 全局 15 秒 Deadline 与写入幂等](00-product/TCG_Card_App_v1.1_PRD.md#03-全局异步请求loading-与-timeout-规则) | [Auth](../../../apps/flutter-app/lib/features/auth/auth_repository.dart)、[Card Data](../../../apps/flutter-app/lib/shared/card_data/card_data_api_client.dart)、[Portfolio](../../../apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart)、[Scan](../../../apps/flutter-app/lib/shared/scan/scan_api_client.dart)、[Entitlement](../../../apps/flutter-app/lib/features/subscription/subscription_entitlement_api.dart) | `auth_repository_test.dart`、`card_data_api_client_test.dart`、`portfolio_api_client_test.dart`、`scan_api_client_test.dart`、`subscription_entitlement_api_test.dart` | 代码已完成；Apple Purchase Sheet、`AppStore.sync()` 和原生 App Attest 计算按 PRD 不强制终止。 |
| [App 2 权益三态与账号/设备边界](00-product/TCG_Card_App_v1.1_PRD.md#2-用户状态模型)、[权益统一方案](00-product/Apple_Subscription_Premium_%E6%9D%83%E7%9B%8A%E7%BB%9F%E4%B8%80%E6%96%B9%E6%A1%88.md) | [本机缓存](../../../apps/flutter-app/lib/features/subscription/subscription_entitlement_cache.dart)、[当前 Apple 权益](../../../apps/flutter-app/lib/features/subscription/apple_current_entitlements.dart)、[session grant](../../../apps/workers-api/src/entitlements/premium-access.ts)、迁移 `0026` | `subscription_entitlement_cache_test.dart`（过期、Lifetime、损坏缓存与重启边界）、`premium-access.test.ts`、`owner-auth.test.ts` | 代码已完成，外部验收待完成：前后台、切号、续订过期和多设备真机矩阵。 |
| [App 3-7 订阅页、购买、Restore](00-product/TCG_Card_App_v1.1_PRD.md#3-subscription-page) | [页面与控制器](../../../apps/flutter-app/lib/features/subscription/subscription_page.dart)、[StoreKit 抽象](../../../dart-packages/subscription-core/lib/src/in_app_purchase_gateway.dart)、[Fresh Purchase](../../../apps/workers-api/src/entitlements/routes.ts)、[Restore proof](../../../apps/workers-api/src/entitlements/restore-routes.ts)、迁移 `0027-0028` | `subscription_restore_ui_test.dart`（含前台商品刷新与容器销毁边界）、`subscription_entitlement_cache_test.dart`（验收 110 重启不恢复瞬态流程）、`subscription_receipt_verifier_test.dart`、`routes.test.ts`、`restore-routes.integration.test.ts` | 代码已完成，外部验收待完成：正式 SKU、App Attest 真机、Sandbox/TestFlight。 |
| [App 8.5 Free Folder 上限与恢复动作](00-product/TCG_Card_App_v1.1_PRD.md#85-portfolio-folder-限制) | [服务端原子限制](../../../apps/workers-api/src/portfolio/routes.ts)、[App 状态恢复](../../../apps/flutter-app/lib/features/collection/collection_controller.dart) | `folder-premium.integration.test.ts`、`folders.test.ts`、`collection_controller_test.dart`、`collection_page_test.dart` | 代码已完成，外部验收待完成：迁移后多设备人工验收。 |
| [App 9 Scan 免费额度](00-product/TCG_Card_App_v1.1_PRD.md#9-scan-免费额度) | [额度账本](../../../apps/workers-api/src/scan/quota.ts)、[识别路由](../../../apps/workers-api/src/scan/routes.ts)、[App Queue](../../../apps/flutter-app/lib/features/scan/scan_page.dart)、迁移 `0030` | `quota.integration.test.ts`、`scan_api_client_test.dart`、`scan_page_test.dart` | 代码已完成，外部验收待完成：真实并发、Worker 中断及 Sandbox/TestFlight。 |
| [App 10-12 Performance](00-product/TCG_Card_App_v1.1_PRD.md#10-performance-feature) | [计算模型](../../../apps/workers-api/src/portfolio/performance.ts)、[Home](../../../apps/flutter-app/lib/features/home/home_performance_controller.dart)、[Card Detail](../../../apps/flutter-app/lib/features/card_detail/card_performance_controller.dart)、迁移 `0031` | `performance.test.ts`、`performance-premium.integration.test.ts`、`home_performance_controller_test.dart`、`card_performance_controller_test.dart` | 代码已完成，外部验收待完成：重度用户 1Y 数据规模和 Cloudflare 端到端时延。 |
| [App 13.3 Extended Price History](00-product/TCG_Card_App_v1.1_PRD.md#133-extended-price-history) | [受保护历史路由](../../../apps/workers-api/src/data-source/routes.ts)、[Card Detail](../../../apps/flutter-app/lib/features/card_detail/card_detail_controller.dart) | `price-history-premium.integration.test.ts`、`card_detail_controller_test.dart` | 代码已完成；1Y 仅接受当前 live session grant，普通公开接口仍裁剪到 90 天。 |

## 3. Admin、通知与归因

| PRD 条款 | 实现证据 | 自动化证据 | 状态与剩余边界 |
|---|---|---|---|
| [Admin 订单查询与 XLSX](00-product/TCG_Admin_%E8%AE%A2%E5%8D%95%E7%BB%9F%E8%AE%A1%E4%B8%8E%E8%8B%B9%E6%9E%9C%E9%80%9A%E7%9F%A5%E6%B6%88%E6%81%AF_PRD_V1.1_%E8%AE%A2%E9%98%85%E7%9C%9F%E5%80%BC%E6%94%B6%E5%8F%A3%E7%89%88.md#7-订单统计页面) | [Admin API](../../../apps/workers-api/src/admin/routes.ts)、[XLSX](../../../apps/workers-api/src/admin/xlsx.ts)、[Admin Web](../../../apps/admin-web/src/App.tsx)、迁移 `0032-0034` | `billing-routes.integration.test.ts`（11 类筛选的 13 个查询参数 AND 语义、自动续订订单快照隔离、有效订单时间排序、退款事实保留、非法筛选 `422`、列表/导出一致性）、`billing-admin-intent.test.mjs`（含空快照展示、越界页回退、防重复、页码跳转、固定异常文案与缺失值契约）、三项 migration test | 代码已完成，外部验收待完成：Sandbox 自动续订快照、有真实订单时的 3 秒查询目标与 10,000 行导出。 |
| [Admin Apple Notifications V2](00-product/TCG_Admin_%E8%AE%A2%E5%8D%95%E7%BB%9F%E8%AE%A1%E4%B8%8E%E8%8B%B9%E6%9E%9C%E9%80%9A%E7%9F%A5%E6%B6%88%E6%81%AF_PRD_V1.1_%E8%AE%A2%E9%98%85%E7%9C%9F%E5%80%BC%E6%94%B6%E5%8F%A3%E7%89%88.md#11-apple-server-notifications-v2-后端接收要求) | [接收与归约](../../../apps/workers-api/src/entitlements/apple-notification-routes.ts)、[Server API 校正](../../../apps/workers-api/src/entitlements/apple-server-api-correction.ts)、[Admin Web](../../../apps/admin-web/src/App.tsx)、迁移 `0029` | `apple-notification-routes.integration.test.ts`（含未知请求字段/通知类型前向兼容）、`apple-server-api-correction.integration.test.ts`、`billing-routes.integration.test.ts`（组合筛选、失败记录倒序分页、非法时间范围）、`billing-admin-intent.test.mjs`（第 14/15 章展示与两列详情布局） | 代码已完成，外部验收待完成：Apple Root CA/Server API Secret、Sandbox 通知及退款/恢复实单。 |
| [App 归因与收入上报](00-product/TCG_Card_App_v1.1_PRD.md#17-analytics) | [ATT/Singular](../../../apps/flutter-app/lib/shared/attribution/app_attribution.dart)、[收入上报](../../../apps/flutter-app/lib/features/subscription/subscription_revenue_reporter.dart) | `app_attribution_test.dart`（独立安装 marker、预取无 ATT/归因副作用、未完成 Onboarding 重启不重复请求、存量升级不弹框、后台只读同步）、`onboarding_gate_test.dart`（marker 不延长启动门禁）、`onboarding_page_test.dart` 与 `widget_test.dart`（首次安装仍按原节拍进入 Onboarding）、`subscription_revenue_reporter_test.dart`（verified-only、实时/启动并发幂等、失败重试与损坏存储拒绝） | 代码已完成，外部验收待完成：Singular 正式 Key、iOS 真机 ATT 与 Sandbox Revenue。 |

## 4. 评审问题收口

| 评审项 | 当前结论 | 证据 |
|---|---|---|
| P0-A 服务端动作结果矩阵 | 已形成统一行为：本机 Premium 但无 grant 返回 `ENTITLEMENT_SYNC_REQUIRED`；明确 Free 才返回 `PREMIUM_REQUIRED`；Unknown 先刷新且不产生受限业务副作用。 | [权益契约](entitlement-contract.md)、Folder/Scan/Performance 集成测试。 |
| P0-B Apple 可验证证据 | StoreKit 2 JWS、Workers 官方验签、环境/Bundle/SKU、nonce、幂等、重放和较新 lifecycle 保护均已实现。 | [权益契约](entitlement-contract.md)、`routes.test.ts`、`restore-routes.integration.test.ts`。 |
| P0-C session/device proof | 授权按 live session grant；UID 统计关联与授权表分离；另一 session 必须独立 Fresh Purchase/Restore。 | 迁移 `0026-0028`、`premium-access.test.ts`、`owner-auth.test.ts`。 |
| P1-A 生命周期归约 | 使用 `(signedDate, notificationUUID)`、交易幂等与不可比较时 Server API 校正。 | [契约变化](contract-changes.md)、通知与校正集成测试。 |
| P1-B Lifetime 缓存时限 | 产品待决。PRD 只定义“临时保持”，未给最长时间；当前不擅自设置。 | [开发计划](development-plan.md#2-当前基线)。 |
| P1-C Payload/导出安全 | 已落实按需详情、默认不返回 `signedPayload`、10,000 行上限与 XLSX 公式注入防护。新版 PRD 明确沿用现有后台权限，未要求查看/复制审计表，因此不扩展该范围。 | Admin PRD 3.2、4、7.6、15.3；Admin API 集成测试。 |
| P1-D Performance 历史 | 自然 Range、可靠历史起点、成本/数量/Folder Move 历史和迁移均已实现。 | 迁移 `0031` 与 Performance 测试。 |
| P1-E USD 汇率快照 | 除法口径、USD=1、快照、舍入、缺失非阻断均已实现。 | 迁移 `0033`、`billing-currency.test.ts`。 |
| Android Premium 范围 | 产品待决。三份 v1.1 PRD只定义 Apple 购买真值；当前 App 仅在 iOS 激活订阅，Android Free 业务可用但不误售、不误授权。Google Play 抽象保留而不激活。 | `subscription_restore_ui_test.dart` 平台边界用例。 |

## 5. 发布前仍需外部完成

1. 提供并冻结正式 Apple Product ID、Bundle/App ID、Root CA、App Store Server API Secret 与 Singular Key。
2. 获得授权后按 `0025` 至 `0034` 顺序迁移 dev，再完成数据不变量和回滚演练；prod 必须在 dev 验收通过后另行授权。
3. 完成 iOS 真机 App Attest、ATT、前后台、切号、Restore、多 entitlement 与离线矩阵。
4. 完成 Sandbox/TestFlight 购买、续订、Grace/Retry、退款、通知重试和 Revenue 验收。
5. 使用重度收藏数据验证 1Y Performance，并使用真实订单验证 Admin 查询与导出性能。
6. 由产品冻结 Lifetime 本地兜底最长时间；确认前保持 `产品待决`。
7. 由产品确认 Android v1.1 是否包含 Premium；若包含，需另行冻结 Google Play 商品、购买证据、服务端验签/proof 和生命周期契约。

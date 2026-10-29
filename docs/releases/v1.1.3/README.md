# v1.1.3 开发文档

状态：当前开发版本。启用日期：2026-10-26（Asia/Shanghai）。创建基线为 `main@0552669fb85a5037379eb3a2da1aaad54543ee0a`。

v1.1.2 已原位归档，不复制其产品、流程、架构、数据/API、Admin 或交付文档。本版本只记录归档后的新增、变更、移除和实际验证；未变化内容继续引用历史真源。

## 当前基线

- [v1.1.2 开发归档](../v1.1.2/README.md)保留 App 1.0.6、订阅展示配置、动态商品准入、Admin、兼容规则及生产交付历史。
- v1.1.2 的[生产收尾记录](../v1.1.2/05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)是本版本的运行起点，不因创建 v1.1.3 重新记为部署或验收。
- App 向后兼容原则继续以 v1.1.2 的[人员阅读版](../v1.1.2/05-delivery/app-backward-compatibility-plan.md)和[AI 执行版](../v1.1.2/03-data-api/app-backward-compatibility-ai-guide.md)为规则真源；v1.1.3 的新增兼容证据写入本版本受影响业务文档或[验证记录](05-delivery/VERIFICATION.md)，不回写归档版本。
- Flutter UI 继续遵循 [v1.0.0 UI 设计系统](../v1.0.0/00-product/ui-design-system.md)及后续已生效的增量合同。
- 当前扫描识别增量见 [RGB pHash + Latin／Japanese OCR 链路](01-flows/scan-recognition.md)：当前 App 与线上低版本 App 共用原识别路径，服务端按互斥请求字段兼容 pHash 与旧向量协议。
- Admin 扫描记录按 TCG／SPORTS 筛选及历史缺类型记录的边界见[扫描记录类型筛选](01-flows/scan-recognition.md#管理后台按卡牌类型筛选2026-10-28)。
- Admin 苹果通知消息使用 SKU 下拉完整匹配筛选，选项来自可见全部通知记录的去重 Product ID；接口、无 SKU 失败记录和部署边界见[后台增量](04-admin/admin.md#苹果通知消息-sku-筛选2026-10-28)。
- 当前订阅本地三卡兜底增量见 [订阅本地兜底页](01-flows/subscription-display.md)：普通周、独立年试用和终身商品；远端配置与 Android 原分支继续沿用 v1.1.2 合同。
- Cards 查询仅返回 `has_image = 2` 的目录记录，并按创建时间倒序；同时间内纯数字 ID 按数值降序、非数字 ID 置后，再按原字符串 ID 稳定排序。缓存与索引边界见 [Cards 排序与索引](03-data-api/cards-search-order.md)。
- Sets 系列列表按纯数字 `set_id` 数值倒序、非数字置后，再按原字符串 ID 倒序；名称不再参与排序，见 [Sets 排序规则](03-data-api/cards-search-order.md#sets-系列列表)。

## 文档路由

| 目录 | 记录范围 |
|---|---|
| `00-product/` | v1.1.3 新产品输入、明确批准的需求补充；不复制旧 PRD |
| `01-flows/` | 新增或变化的用户流程、状态与跨端行为 |
| `02-architecture/` | 新架构决策、部署拓扑和运行边界 |
| `03-data-api/` | 新数据模型、迁移、接口和兼容增量 |
| `04-admin/` | Admin 新功能与操作合同 |
| `05-delivery/` | 测试、构建、部署、回退和验收证据 |

没有对应增量时不创建占位文档。新增文档必须从本 README 提供入口；已有合同未变化时直接引用 v1.1.2 或更早版本。

## 记录规则

- 后续开发记录默认写入 `docs/releases/v1.1.3/`，不得继续向 v1.1.2 追加新功能或新日期检查点。
- 历史版本只允许在明确授权下修正确认过的事实错误；修正必须说明原因，并在 v1.1.3 留下引用。
- 本地验证、CI、dev、prod、商店发布、用户反馈和 Agent 独立验收必须分别标记，未执行项不得写成通过。
- 不在正式 docs 中保存执行日志、任务快照、截图、Secret、Token、私钥或原始生产响应。
- 文档版本、App 版本、API 版本、Git 提交和环境运行版本分别管理；创建 v1.1.3 不代表代码、数据库或环境发生变化。

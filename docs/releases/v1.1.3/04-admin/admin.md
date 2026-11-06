# Admin 增量

本文件只记录 v1.1.2 归档后的 Admin 变化。未变化的后台合同继续以 [v1.1.0 Admin 文档](../../v1.1.0/04-admin/admin.md)和 [v1.1.2 Admin 文档](../../v1.1.2/04-admin/admin.md)为准。

## 列表条件隔离与权限管理接线（2026-11-03）

共用列表读取按登录 token 和请求路径隔离展示结果。切换条件或账号后立即不再展示上一条件的数据，清理 effect 时取消旧请求；即使底层未执行取消，旧响应也不能写回。新条件失败保留错误及重试入口，不把旧行显示为新条件结果。同条件显式刷新可继续显示当前内容，同时暴露加载／失败状态。

权限页使用 `GET /api/v1/admin/permissions?page&page_size&q&status`，每页 8 条；邮箱与状态先编辑草稿，查询后生效并返回第一页，重置清空筛选。接口保留原默认 20 条、上限 100 条及原响应字段，仅增加同筛选条件的 `total`。分页不再局限于最初下载的 100 个账号，当前页超出更新后的总页数时返回有效末页。

编辑复用既有 `PATCH /api/v1/admin/permissions/:id`，只修改角色和状态，邮箱只读；不新增邮箱或密码修改能力。新增、编辑、启用／停用仅对 `super_admin` 开放，普通运营角色的按钮在原位置禁用，服务端继续强制校验权限。页面主体、筛选区和表格布局保持。既有接口的 `updated_at` 仍映射创建时间，本轮没有新增持久化字段，不能把编辑后该列视为真实修改时间。

实际本地验证与模拟环境见[开发记录](../05-delivery/VERIFICATION.md#owner-assets-admin-emulator-20261103)；配套 API／Admin 已随 `dev@399f4066` 发布 Linux dev，真实登录态未验边界见[发布记录](../05-delivery/VERIFICATION.md#dev-owner-assets-release-20261103)。API 与两个生产 Admin 入口后续已随 `main@94417983` 配套发布，见[生产发布记录](../05-delivery/VERIFICATION.md#prod-business-release-20261104)；真实管理员登录业务仍未独立验收。

## 反馈分页与扫描详情竞态修复（2026-11-02）

反馈页按每页 5 条向 `GET /api/v1/admin/feedbacks` 请求，不再固定下载前 100 条并显示不可切换的分页。响应保留 `items/page/page_size`，新增 `total`；API 默认每页 20 条、上限 100 条继续保留，列表与总数在 PostgreSQL 中使用相同筛选条件，按创建时间倒序、同时间 ID 升序排列。

UID、问题类型、处理状态及开始／结束日期先保留为草稿，点击查询后生效并回到第一页；翻页保留条件，重置清空条件，状态更新后刷新。当前筛选结果不足以保留当前页码时回到有效末页。接口新增可选 `uid/issue_type/date_from/date_to`：UID 去除首尾空格后完整匹配；问题类型匹配 `types` 数组中的任意元素；日期沿用现有 Admin 边界处理，日期值按 UTC 当日开始／结束时间包含匹配，无法解析时返回 `422 VALIDATION_ERROR`。

状态筛选在分页前完成，沿用 `open/in_progress → pending`、`closed → processed` 及 `pending/processed/ignored` 的既有展示口径。问题类型按当前 App 写入契约使用 `Bug Report/Feature Request/Improvement/Other`，纠正原先把模块 `Account` 混入类型选项的冲突。

历史 `types` 为非法 JSON 或非数组 JSON 时，无类型筛选仍保留记录并沿用“其他”展示；选择类型时安全排除，不让单条坏数据使列表与总数查询失败。不回填或修改历史记录。

反馈表未保存平台，用户明确选择回显“未知”并禁用平台筛选；不再硬编码为 iOS，也不从用户当前设备推断历史反馈平台。本轮不新增平台采集字段、App 反馈写入或 migration。其他既有反馈元数据占位字段未在本轮补采，不能作为实机信息使用。

扫描详情点击后立即打开加载状态；切换记录会取消旧请求并更新请求序号，关闭抽屉或离开页面使旧响应失效。即使取消未被底层请求执行，晚到结果也不能覆盖新选择或重新打开已关闭的抽屉。当前请求失败在抽屉显示错误并可重试；原鉴权、401 处理、详情内容和私有图片访问保持。

配套 API／Admin 已于 2026-11-02 随 `dev@fe5e319f` 发布 Linux dev；开发验证见[本地记录](../05-delivery/VERIFICATION.md#project-optimization-20261102)，部署及真实登录态交互未验边界见[发布记录](../05-delivery/VERIFICATION.md#dev-ux-loading-release-20261102)。配套 API 与两个生产 Admin 入口后续已随 `main@94417983` 发布，生产版本与未验边界见[生产发布记录](../05-delivery/VERIFICATION.md#prod-business-release-20261104)。

## 扫描列表读取与图片复用（2026-10-30）

扫描列表只读取列表响应需要的字段，卡牌类型筛选仍使用 `system_result.card_type`；完整审计内容保留在详情接口。私有图片接口只读取图片键，再通过原有存储获取原图，继续使用 Admin 鉴权与 `private, no-store`。

同一登录 token 和图片路径的列表／详情组件共享一次请求及 Blob；离开最后一个使用该图片的组件后不保留缓存，进行中的请求可取消。换 token 不复用旧会话缓存，401 继续触发既有会话过期处理，各组件在卸载时撤销自己的 Object URL。该优化减少打开详情的重复原图下载，首次列表仍读取原图，没有增加公开缓存或专用缩略图。

实现与观测口径见[性能说明](../02-architecture/performance.md)，开发验证见[本轮验证记录](../05-delivery/VERIFICATION.md#performance-optimization-20261030)，生产发布见[2026-11-04 记录](../05-delivery/VERIFICATION.md#prod-business-release-20261104)。

## 苹果通知消息 SKU 筛选（2026-10-28）

“数据统计 → 苹果通知消息”的 SKU 筛选使用可搜索、可清空的单选下拉框，默认“全部”。点击“查询”后，`GET /api/v1/admin/apple-notifications` 使用可选 `sku` 参数按通知结构化记录的 `product_id` 完整匹配；参数会去除首尾空格，匹配保留 Product ID 的大小写语义，不做包含或前缀查询。

`GET /api/v1/admin/apple-notifications/options` 保留原主／子通知类型 `items`，新增 `skus: string[]`。SKU 来自当前后台可见的全部通知记录中的 `apple_server_notification.product_id`，沿用通知列表的 Bundle／业务环境隔离，去重、排序并排除 null、空字符串和纯空格值；不从商品目录或当前分页收集，也不随页面的 SKU、环境等筛选草稿或已应用条件收缩。这样首页未出现的 SKU 仍可直接选择，切换 SKU 不必先清空原筛选。

SKU 与 UID、原始交易 ID、订单 ID、环境、主／子通知类型和创建时间继续使用 AND 语义，列表和总数复用同一条件。选择或清空下拉框后点击“查询”生效并回到第一页；分页、刷新保留当前 SKU；重置清空 SKU 并恢复当前部署的默认环境。刷新同时重新获取通知列表和筛选选项；选项请求失败时显示错误，可点击刷新重试。

不传 SKU 时保持原行为，包括继续显示尚未产生结构化通知、因而没有 SKU 的验签／处理失败 inbox；传入 SKU 时，这类无 SKU 记录自然不匹配。该增量复用既有 `apple_server_notification.product_id`，不新增数据库字段、migration、写入路径或通知处理逻辑。

本文件描述当前源码合同；Linux dev 已配套发布 Admin 与 API，见[2026-11-02 发布记录](../05-delivery/VERIFICATION.md#dev-ux-loading-release-20261102)。该 SKU 接口与 Admin 后续已随 `main@94417983` 配套发布生产，见[生产发布记录](../05-delivery/VERIFICATION.md#prod-business-release-20261104)；真实管理员登录交互仍未验收，开发验证边界见[验证记录](../05-delivery/VERIFICATION.md)。其他环境上线仍需配套更新 Admin 与 API，旧 API 不返回 `skus`。

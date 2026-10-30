# Admin 增量

本文件只记录 v1.1.2 归档后的 Admin 变化。未变化的后台合同继续以 [v1.1.0 Admin 文档](../../v1.1.0/04-admin/admin.md)和 [v1.1.2 Admin 文档](../../v1.1.2/04-admin/admin.md)为准。

## 扫描列表读取与图片复用（2026-10-30）

扫描列表只读取列表响应需要的字段，卡牌类型筛选仍使用 `system_result.card_type`；完整审计内容保留在详情接口。私有图片接口只读取图片键，再通过原有存储获取原图，继续使用 Admin 鉴权与 `private, no-store`。

同一登录 token 和图片路径的列表／详情组件共享一次请求及 Blob；离开最后一个使用该图片的组件后不保留缓存，进行中的请求可取消。换 token 不复用旧会话缓存，401 继续触发既有会话过期处理，各组件在卸载时撤销自己的 Object URL。该优化减少打开详情的重复原图下载，首次列表仍读取原图，没有增加公开缓存或专用缩略图。

实现与观测口径见[性能说明](../02-architecture/performance.md)，实际验证及未部署边界见[本轮验证记录](../05-delivery/VERIFICATION.md#performance-optimization-20261030)。

## 苹果通知消息 SKU 筛选（2026-10-28）

“数据统计 → 苹果通知消息”的 SKU 筛选使用可搜索、可清空的单选下拉框，默认“全部”。点击“查询”后，`GET /api/v1/admin/apple-notifications` 使用可选 `sku` 参数按通知结构化记录的 `product_id` 完整匹配；参数会去除首尾空格，匹配保留 Product ID 的大小写语义，不做包含或前缀查询。

`GET /api/v1/admin/apple-notifications/options` 保留原主／子通知类型 `items`，新增 `skus: string[]`。SKU 来自当前后台可见的全部通知记录中的 `apple_server_notification.product_id`，沿用通知列表的 Bundle／业务环境隔离，去重、排序并排除 null、空字符串和纯空格值；不从商品目录或当前分页收集，也不随页面的 SKU、环境等筛选草稿或已应用条件收缩。这样首页未出现的 SKU 仍可直接选择，切换 SKU 不必先清空原筛选。

SKU 与 UID、原始交易 ID、订单 ID、环境、主／子通知类型和创建时间继续使用 AND 语义，列表和总数复用同一条件。选择或清空下拉框后点击“查询”生效并回到第一页；分页、刷新保留当前 SKU；重置清空 SKU 并恢复当前部署的默认环境。刷新同时重新获取通知列表和筛选选项；选项请求失败时显示错误，可点击刷新重试。

不传 SKU 时保持原行为，包括继续显示尚未产生结构化通知、因而没有 SKU 的验签／处理失败 inbox；传入 SKU 时，这类无 SKU 记录自然不匹配。该增量复用既有 `apple_server_notification.product_id`，不新增数据库字段、migration、写入路径或通知处理逻辑。

本文件描述当前本地源码合同，不代表 dev／prod 已部署或真实后台交互已验收；上线需要配套更新 Admin 与 API，旧 API 尚不返回 `skus`。实际验证边界见[验证记录](../05-delivery/VERIFICATION.md)。

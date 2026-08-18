# trending_pin 废弃设计

## 结论

`trending_pin` 已无 App 读取方，当前 `/cards/trending` 只消费 PostgreSQL `card_trending_snapshot`。删除 Admin `/trending-pins` CRUD、当前 Schema 声明和迁移工具搬运入口，并通过向前 migration 删除 PostgreSQL 与保留 D1 schema 中的实体表。

## API 与调用方

- 删除 `GET/POST /api/v1/admin/trending-pins` 和 `PATCH/DELETE /api/v1/admin/trending-pins/:pinId`。
- Admin Web 当前没有对应菜单或调用方，因此不需要客户端兼容层；旧外部调用方在新 Worker 部署后得到 404。
- `/api/v1/cards/trending`、Flutter 首页和 View All 不变，继续读取 `card_trending_snapshot`。

## 数据库与迁移

- 不修改已经执行的 PostgreSQL `0000_business_schema.sql` 或 D1 `0000_famous_vector.sql`。
- 追加 PostgreSQL `0005_drop_trending_pin.sql` 和 D1 `0035_drop_trending_pin.sql`，均只执行 `DROP TABLE trending_pin`，不使用 `CASCADE`。
- 从当前 Drizzle schema 和 D1 到 PostgreSQL 的迁移表清单移除 `trending_pin`；旧 D1 源表列入显式排除清单，避免迁移工具重建或写入已废弃表。
- PostgreSQL migration worker 注册 `0005`，schema-only/fresh schema 路径最终不再包含该表。

## 上线与回滚

1. 先部署移除 Admin API 的 Worker，确认没有 `/trending-pins` 调用需求。
2. 再显式授权并执行 PostgreSQL drop migration；本任务不执行远程 migration。
3. drop 前回滚只需回滚 Worker；drop 后恢复旧 API 前必须先按历史 DDL 重建空表。历史置顶配置被删除后只能从数据库备份恢复。

## 验证

- Admin 路由测试保护四个废弃方法均返回 404，并回归 Card Override 权限。
- D1 完整 migration chain 验证最终不存在 `trending_pin`。
- 迁移工具测试验证 `0005` 已注册、目标表清单不含该表且旧 D1 表被显式排除。
- 运行 Workers 定向测试、type-check、残留引用检查和 `git diff --check`。

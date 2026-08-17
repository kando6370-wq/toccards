# PlanetScale 与 Cloudflare Hyperdrive 关联设计

## 目标

在 Cloudflare 账户中创建一条 Hyperdrive 配置，连接 PlanetScale 组织 `product-kando` 的 `tcg_cards` 数据库 `main` 分支，数据库名使用默认的 `postgres`。

## 实施范围

- 通过 Cloudflare 与 PlanetScale 的官方集成完成授权和连接配置。
- 配置名称优先使用与数据库一致且符合 Cloudflare 校验规则的名称。
- 保持 Hyperdrive 默认查询缓存设置；本次只验证连接，不承诺业务查询缓存语义。
- 创建后在 Cloudflare 配置详情中核对目标数据库、分支和连接状态。

## 边界

- 不执行 PostgreSQL Schema、迁移、导入或业务数据写入。
- 不修改 `apps/workers-api/wrangler.toml`，不把现有 `DB` D1 binding 替换为 Hyperdrive。
- 不部署 dev 或 prod Worker。当前 Workers 仍依赖 D1 `prepare`/`batch` 接口，不能直接切换连接字符串。
- 不把数据库凭据、连接串或令牌写入仓库、Harness 证据或最终回复。

## 回滚

若创建结果指向错误的组织、数据库或分支，停止后续绑定并删除该 Hyperdrive 配置；若官方集成同时创建 PlanetScale 凭据，再在 PlanetScale 侧撤销对应集成凭据。删除前必须再次核对精确资源并取得授权。

## 验证

- Cloudflare Hyperdrive 列表出现目标配置。
- 配置详情显示 `product-kando/tcg_cards/main`，连接测试成功。
- 仓库 Wrangler 配置仍只有现有 D1 binding，确认未发生部署切换。

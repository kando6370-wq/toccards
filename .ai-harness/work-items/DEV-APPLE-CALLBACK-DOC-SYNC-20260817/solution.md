# dev Apple 回调文档同步方案

## 范围

仅同步 2026-08-17 已核实的 dev 环境事实：App Store Connect Sandbox Server URL、dev Worker 部署与 Apple 配置项存在、dev D1 通知表与重试任务就绪，以及通知 inbox 当前为空。

## 边界

- 不修改 production 状态，不推断加密 Secret 内容有效。
- 不把路由可达、配置项存在或空请求返回 `400 INVALID_REQUEST` 表述为真实 Apple 通知已处理成功。
- 真实 Apple Sandbox 通知的验签、入库和业务归约仍需端到端验收。
- 不修改代码、Schema、迁移、D1 数据、Wrangler 配置或远程环境。

## 文档策略

- 在当前状态段落中写明 2026-08-17 dev 核验结果。
- 保留 2026-08-13 历史快照的原始时态，并补充较新的 dev 状态，避免改写历史。
- 统一四份 v1.1.0 文档中的阻塞表述：dev 配置不再列为缺失，production 配置和真实 Sandbox/TestFlight 验收继续列为未完成。

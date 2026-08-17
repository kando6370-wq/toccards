# 文档增量设计

## 目标

扩充现有 `docs/releases/v1.1.0/05-delivery/app-store-connect-subscription-setup.md`，使其成为 iOS 订阅商品配置、Sandbox Tester 创建和真机/TestFlight 验收的唯一说明入口。

## 修改范围

- 区分 dev/test Bundle ID `com.kando.kandoApp.beta` 与 production Bundle ID `com.cardai.tcg`。
- 记录 2026-08-17 App Store Connect 只读核验的商务与 Weekly/Yearly 状态，并明确时间点边界。
- 将 Sandbox 章节扩充为账号创建、字段约束、真机登录、测试包运行、TestFlight、验收和故障排查步骤。
- 补充 Apple 官方 Sandbox 文档链接。

## 边界

- 不新增重复说明文档，不修改 `docs/releases/v1.0.0` 或原始 PRD。
- 不修改 Flutter、Workers、数据库或部署配置。
- 不写入邮箱、密码、税务表内容、银行账户等敏感信息。

## 验证

- 检查 Markdown 标题、链接、代码块和关键配置值。
- 检查旧 Bundle ID 是否仍被误写为 dev/test 标识。
- 运行 `git diff --check` 并审阅目标文件差异。

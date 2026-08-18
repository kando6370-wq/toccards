# Apple JWS 验签错误诊断修复

## 根因

通知和嵌套 JWS 验签的 `catch` 丢弃了 Apple `VerificationException.status`，把证书链、环境、Bundle ID、Payload 和 OCSP 网络失败统一保存为终态错误。尤其 `RETRYABLE_VERIFICATION_FAILURE` 被写成 `verification_failed` 后，不会被 5 分钟重试任务再次领取。

## 设计

- 在 `apple-signed-data.ts` 内通过现有动态导入边界识别 Apple `VerificationException`，只返回受控的枚举名称和 `retryable` 标志。
- 外层通知错误码使用 `NOTIFICATION_JWS_<STATUS>`；嵌套错误码使用 `NESTED_JWS_<STATUS>`。
- 非 Apple 异常继续使用既有通用错误码，不保存异常消息、`cause`、JWS 或证书内容。
- 仅 `RETRYABLE_VERIFICATION_FAILURE` 写为 `processing_failed` 且不写 `processed_at`，由现有 cron 重试；其他外层错误写为 `verification_failed`，其他嵌套错误写为 `parse_failed`。

## 兼容与回滚

- 不改 Schema、Admin API 响应结构、验签参数或正常消费流程。
- 回滚只需恢复三个 Apple 验签相关源码/测试文件；历史 inbox 无需迁移。
- 部署范围仅 dev。prod 不部署、不改 Secret、不调整流量。

## 验证

- 集成测试覆盖全部 Apple `VerificationStatus` 的稳定错误码、非 Apple 异常的通用错误码，以及 OCSP 类可重试失败能够被 cron 再次处理。
- 运行相关集成测试、Workers type-check、dev dry-run build。
- 部署前核对工作树，若当前 bundle 含本任务之外未交付改动则停止 dev 部署并显式报告。

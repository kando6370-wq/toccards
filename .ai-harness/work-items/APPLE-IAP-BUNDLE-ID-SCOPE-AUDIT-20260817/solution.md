# Apple IAP Bundle ID 配置追溯审计

## 事实边界

- Harness 项目基线为 `a1257c43a4008acc09eb391ef93d0d8ced98fc33`。
- 历史提交 `df8e6d7c8ae6695d3f0366b17725abd65615e8d8` 只在 `apps/workers-api/wrangler.toml` 增加两行 `APPLE_IAP_BUNDLE_ID`。
- production 值为 `com.cardai.tcg`，development 值为 `com.kando.kandoApp.beta`；两者与对应环境的 Apple client/bundle 配置一致。
- Workers 的 Apple 签名校验和 Server API 校正逻辑均读取该变量。本审计不修改配置，也不重新部署。

## 验证与补证

1. 复核历史提交的精确差异和当前运行时代码读取点。
2. 运行 Workers 类型检查与测试，确认当前后端基线没有回归。
3. 在 Harness 计划中把 `apps/workers-api/wrangler.toml` 记录为该历史配置工作的真实写入范围。
4. 重新运行 `check --ci`，确认历史范围缺口消失。

## 回退

本任务不改变产品文件，无产品回退动作。若审计结论有误，只能通过新的更正工作项和提交修正控制面记录，不重写已推送历史。

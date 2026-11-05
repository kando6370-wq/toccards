# Kando 安全缓解措施

## 立即执行

- `MIT-001`：pnpm 11.28.10、Node 22.23.4，同步根 `packageManager`、CI和watcher；Docker构建从根 `packageManager` 解析pnpm版本，无单独版本常量；执行冻结安装与官方registry审计。
- `MIT-002`：Flutter 3.47.9、Dart 3.13.7、Gradle 8.14.6，Gradle wrapper固定官方SHA-256；执行移动分析、测试、构建和Android真机TLS回归。
- `MIT-004`：Hono/Node adapter/Drizzle/Vite/Vitest及高风险传递依赖升级；执行类型、构建、Workers/Admin测试和prod dry-run。

## 短期执行

- `MIT-003`：Cloudflare与Linux Node入口分别验证CORS、请求大小、代理头、超时和错误响应。
- `MIT-005`：普通用户、Admin、super_admin逐路由权限矩阵。
- `MIT-006`：当前 Apple production/sandbox 通知的签名、Bundle/环境绑定、事件幂等和重放拒绝。Google服务端 webhook 尚未接入，不列为当前实现验收。
- `MIT-007`：受控秘密扫描和Admin高权限审计字段核对，禁止输出Secret明文。

## 中期执行

- `MIT-008`：识别接口并发、限频、超时、上游故障和大输入测试。

已通过Workers 102文件／927项、Admin 87/87、auth 34/34、relay/offline/preflight 18/18、TypeScript 7/7、production dry-run、Linux打包dry-run、标准Melos两包分析0 issues、subscription_core 12项、旧App兼容24×2和图片异步解码专项回归。App最终全测为1326 pass／9 fail；Python集合对照确认失败集合严格等于旧源码基线的9项，新增失败为空，6项新版golden均通过。

Android Debug APK 已使用校验后的 Temurin 21.0.13+9 构建成功，Flutter doctor 与 Gradle PID 均确认实际JDK；临时全局 `jdk-dir` 已恢复，未写入永久内存配置。APK为251305638字节，SHA-256 `4a1c8c96de21817b0ad6c1b2e4c274348d4f72dca239548cced7aa14608b52c3`。离线OS载体Temurin 21.0.11不执行Java，仍需Linux独立验证后决定更新。iOS、真机、远端环境及渗透测试未验收。

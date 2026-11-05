# Kando 安全控制覆盖

| 控制域 | 当前评价 | 主要措施 |
|---|---|---|
| 认证与授权 | 需端到端补验 | 服务端会话、角色、账号归属、Admin矩阵 |
| 输入与API | 基础控制存在 | Hono验证、限频、大小与超时回归 |
| 密码学 | 移动SDK已升级待真机验收 | TLS、Dart3.13.7、Flutter3.47.9 |
| 数据保护 | 架构控制存在 | PostgreSQL服务端边界、R2/本地卷、Secret不落报告 |
| 日志审计 | 部分覆盖 | 高权限操作、Apple通知事件和请求关联ID待核验 |
| 基础设施 | 服务端本地验证通过，环境仍待回归 | Workers 102/927、Cloudflare bindings、Linux私有网络、代理信任及离线JDK载体验证 |
| 供应链 | 核心升级已实施 | pnpm11.28.10、Gradle哈希、锁文件、audit 0 |
| 移动安全 | 分析、App基线对照和Android Debug构建通过 | Flutter/Dart/Gradle、Temurin21.0.13+9构建证据；iOS、真机TLS与远端验收待完成 |

本报告是工程安全评估，不构成PCI DSS、SOC 2或ISO 27001认证。

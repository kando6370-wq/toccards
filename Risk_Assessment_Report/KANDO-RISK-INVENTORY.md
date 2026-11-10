# Kando 风险清单

`verified` 仅表示源码或版本证据确认组件处于公告影响范围，不表示攻击复现或生产利用成功。`theoretical` 是需要验证的威胁假设，不自动等同于整改缺陷。

补充残余边界：Android Debug APK已用校验后的Temurin21.0.13+9构建成功，临时全局JDK配置已恢复；Android Studio自带JBR21.0.10未用于该构建。离线OS载体Temurin21.0.11当前不执行Java，仍需Linux独立验证后处理。这些状态不改变下表十二项STRIDE风险的数量守恒。

| ID | 状态 | 优先级 | 风险 | 证据边界 |
|---|---|---|---|---|
| VR-004 | verified | P0 | pnpm 11.9.0供应链漏洞影响 | 版本与官方公告匹配，未执行恶意安装 |
| VR-008 | verified | P0 | Dart/Flutter Android `dart:io` TLS MITM | 版本与平台条件匹配，未进行网络劫持 |
| VR-012 | verified | P0 | Node依赖/Gradle构建工具链公告命中 | 官方审计和版本比对，未执行攻击载荷 |
| VR-007 | pending | P1 | Secret进入日志或产物 | 未读取明文，尚未完成秘密扫描 |
| VR-011 | theoretical | P1 | Admin路由授权遗漏 | 尚未完成全角色端到端矩阵 |
| VR-001 | theoretical | P2 | 会话冒充 | 无令牌泄漏证据 |
| VR-002 | theoretical | P2 | 伪造支付回调 | 未做生产攻击测试 |
| VR-003 | theoretical | P2 | 识别输入篡改与资源压力 | 待大小、并发和超时测试 |
| VR-005 | theoretical | P2 | Admin操作不可归责 | 待登录态审计字段核对 |
| VR-006 | theoretical | P2 | 支付事件重放 | 待Sandbox幂等测试 |
| VR-010 | theoretical | P2 | 外部识别服务故障传播 | 未做故障注入 |
| VR-009 | excluded | P3 | 当前Hono公告触发路径 | 非空allowHeaders且未使用serveStatic |

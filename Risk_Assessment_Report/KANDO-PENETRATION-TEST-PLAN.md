# Kando 渗透测试计划

所有测试先在本地或Linux dev执行；生产只允许现有健康、鉴权拒绝和只读烟测，攻击性载荷需另行授权。表中的覆盖关系是测试计划映射，并非测试已经执行或通过。

| 测试 | 覆盖 | 环境 | 通过标准 |
|---|---|---|---|
| TC-001 供应链冻结安装 | AP-001, VR-004, VR-012 | 本地/CI | 锁文件不漂移，audit全部严重度0 |
| TC-002 Android TLS回归 | AP-002, VR-008 | 测试App/受控网络 | Flutter3.47.9/Dart3.13.7，合法链成功、无效链失败 |
| TC-003 Admin角色矩阵 | AP-003, VR-011 | Linux dev | 普通用户所有Admin入口401/403，高权限操作有审计 |
| TC-004 Apple通知签名与重放 | VR-002, VR-006 | Sandbox/dev | 错签名、错Bundle、错环境、重复事件不提升权益；Google服务端webhook当前未接入 |
| TC-005 识别输入边界 | VR-003, VR-010 | Linux dev | 超限输入快速拒绝，上游超时不耗尽进程 |
| TC-006 双运行时CORS与代理 | VR-009 | 本地Miniflare/Linux dev | Cloudflare与Linux安全结果一致，未信任伪造代理头 |
| TC-007 Secret扫描 | VR-007 | 冻结产物 | 无凭据、日志脱敏，不输出Secret明文 |
| TC-008 回归套件 | 全部 | 本地/CI | lint、type-check、build、Workers/Admin/Flutter测试通过 |

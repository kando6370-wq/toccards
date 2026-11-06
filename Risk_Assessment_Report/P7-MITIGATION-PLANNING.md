# P7 缓解方案

## THINKING

缓解方案优先消除已验证的供应链和移动TLS风险，再补充授权、审计和双运行时回归。

## PLANNING

每项验证风险均映射至少一个 MIT，并给出可执行版本、验证命令和剩余边界。

## EXECUTION

```yaml:mitigation_plan
mitigations:
  - id: MIT-001
    risk_refs: [VR-004, VR-012]
    priority: P0
    action: 将pnpm从11.9.0升级到11.28.10并同步根packageManager、CI和watcher；Docker从根packageManager解析版本，锁文件重算
    acceptance: 官方npm registry审计全部严重度为0且冻结安装通过
  - id: MIT-002
    risk_refs: [VR-008, VR-012]
    priority: P0
    action: 升级Flutter至3.47.9、Dart约束至3.13.7、Gradle至8.14.6并固定官方distributionSha256Sum
    acceptance: flutter doctor、analyze、test、Android和iOS构建链通过；Android真机TLS和核心流程回归
  - id: MIT-003
    risk_refs: [VR-003, VR-009, VR-010]
    priority: P1
    action: 升级Hono至4.13.16、node-server至2.1.6，并对CORS、请求大小、超时和Cloudflare/Linux入口回归
    acceptance: Workers测试、Linux打包、Cloudflare dry-run及边界测试通过
  - id: MIT-004
    risk_refs: [VR-004, VR-012]
    priority: P0
    action: 升级Drizzle ORM 0.45.4、Drizzle Kit 0.31.11、Vite 6.4.4以上、Vitest 4.1.12，并对Miniflare精确覆盖undici7.30.1与sharp0.35.5
    acceptance: pnpm audit为0、类型检查、构建及现有测试通过
  - id: MIT-005
    risk_refs: [VR-001, VR-011]
    priority: P1
    action: 逐路由验证会话、角色、账号归属和Admin权限矩阵
    acceptance: 普通用户访问Admin均拒绝且高权限操作产生可归责审计记录
  - id: MIT-006
    risk_refs: [VR-002, VR-006]
    priority: P1
    action: 保持支付回调签名、环境/Bundle绑定、事件幂等和重放拒绝测试
    acceptance: 错误签名、错环境、重复事件无权益提升且日志可追踪
  - id: MIT-007
    risk_refs: [VR-005, VR-007]
    priority: P1
    action: 执行受控秘密扫描并核对Admin高权限操作审计字段，不读取或输出Secret明文
    acceptance: 发布产物无凭据、日志脱敏、批准退款和配置变更包含操作者与请求关联ID
  - id: MIT-008
    risk_refs: [VR-003, VR-010]
    priority: P2
    action: 对识别入口实施大小、并发、超时、上游失败和限频测试
    acceptance: 非法输入快速拒绝，上游失败不耗尽资源，Cloudflare与Linux结果一致
roadmap:
  immediate: [MIT-001, MIT-002, MIT-004]
  short_term: [MIT-003, MIT-005, MIT-006, MIT-007]
  medium_term: [MIT-008]
  long_term: []
```

```yaml:roadmap
immediate: [MIT-001, MIT-002, MIT-004]
short_term: [MIT-003, MIT-005, MIT-006, MIT-007]
medium_term: [MIT-008]
long_term: []
```

## REFLECTION

十二项VR全部获得缓解计划映射。Workers102／927、标准Melos两包分析、subscription_core12项、旧App兼容24×2、图片异步解码专项回归和Temurin21.0.13+9 Android Debug APK构建已通过。App最终全测1326 pass／9 fail，失败集合严格等于旧基线且新增失败为空；iOS、真机、远端、离线Linux JDK载体及渗透验收仍待完成。

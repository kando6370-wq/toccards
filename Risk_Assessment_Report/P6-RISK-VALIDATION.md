# P6 风险验证

## THINKING

验证仅使用源码、锁文件、官方公告和本地审计；不向生产发送攻击载荷。公告命中不自动等于可利用。

## PLANNING

逐项核对版本范围、触发条件、代码路径、平台影响和现有控制，并保持 P5 十二项威胁数量守恒。

## EXECUTION

```yaml:validated_risks
risk_summary:
  total_identified: 12
  total_verified: 3
  total_theoretical: 7
  total_pending: 1
  total_excluded: 1
risk_details:
  - {id: VR-001, threat_refs: [T-S-P-002-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P2, title: 会话冒充, evidence: 架构风险但本轮未取得令牌泄漏证据}
  - {id: VR-002, threat_refs: [T-S-P-005-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P2, title: 支付回调伪造, evidence: 需继续保持签名环境与幂等回归}
  - {id: VR-003, threat_refs: [T-T-P-003-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P2, title: 识别输入篡改与资源压力, evidence: 需协议和大小边界测试}
  - {id: VR-004, threat_refs: [T-T-P-006-001], gap_refs: [GAP-001], validation_status: verified, priority: P0, related_poc: POC-001, title: pnpm供应链版本风险, evidence: 项目明确固定11.9.0且低于多个官方公告修复边界11.11.0}
  - {id: VR-005, threat_refs: [T-R-P-004-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P2, title: Admin操作归责风险, evidence: 需登录态端到端核对审计字段}
  - {id: VR-006, threat_refs: [T-R-P-005-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P2, title: 回调重放归责风险, evidence: 未执行真实支付回放测试}
  - {id: VR-007, threat_refs: [T-I-DS-004-001], gap_refs: [GAP-005], validation_status: pending, priority: P1, related_poc: POC-002, title: Secret泄漏面, evidence: 本轮未读取Secret明文且未做产物秘密扫描}
  - {id: VR-008, threat_refs: [T-I-P-006-001], gap_refs: [GAP-003], validation_status: verified, priority: P0, related_poc: POC-003, title: 旧Dart TLS中间CA风险, evidence: 官方GHSA-frr6-h895-5pxp影响Dart稳定版3.13.7以下及Flutter3.47.8以下的Android与桌面dart:io}
  - {id: VR-009, threat_refs: [T-D-P-001-001], gap_refs: [GAP-002, GAP-006], validation_status: excluded, priority: P3, title: 当前Hono CORS公告触发路径, evidence: 项目显式配置非空allowHeaders且未使用serveStatic，已知公告条件不成立}
  - {id: VR-010, threat_refs: [T-D-P-003-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P2, title: 外部识别服务可用性, evidence: 架构依赖成立但本轮未做故障注入}
  - {id: VR-011, threat_refs: [T-E-P-004-001], gap_refs: [GAP-005], validation_status: theoretical, priority: P1, related_poc: POC-004, title: Admin授权遗漏, evidence: 高影响通用路径，需端到端角色矩阵验证}
  - {id: VR-012, threat_refs: [T-E-P-006-001], gap_refs: [GAP-002, GAP-003], validation_status: verified, priority: P0, related_poc: POC-005, title: 构建与依赖工具链公告命中, evidence: 官方npm审计升级前54项且Gradle旧版本处于官方高危公告影响范围}
excluded_threats:
  - {id: T-D-P-001-001, source_phase: P5, reason: 已知Hono公告的allowHeaders与serveStatic触发条件在当前代码路径不成立}
```

```yaml:poc_details
pocs:
  - {id: POC-001, type: read_only_version_check, result: confirmed, safety: 未安装恶意包}
  - {id: POC-002, type: bounded_static_review, result: pending, safety: 未读取Secret明文}
  - {id: POC-003, type: official_advisory_version_match, result: confirmed, safety: 未进行TLS劫持}
  - {id: POC-004, type: route_and_middleware_review, result: partial, safety: 未对生产越权测试}
  - {id: POC-005, type: official_audit_and_version_match, result: confirmed, safety: 仅本地读取}
```

```yaml:attack_paths
paths:
  - {id: AP-001, risk_refs: [VR-004, VR-012], steps: [恶意依赖进入解析范围, 旧pnpm或构建工具处理, 构建环境完整性受损]}
  - {id: AP-002, risk_refs: [VR-008], steps: [Android使用受影响Dart, 攻击者控制网络, 伪造受影响中间CA链, dart:io TLS流量被截获]}
  - {id: AP-003, risk_refs: [VR-011], steps: [获得普通会话, 命中遗漏角色校验的Admin路由, 执行高权限操作]}
```

```yaml:attack_chains
chains:
  - {id: AC-001, path_refs: [AP-001], objective: 构建供应链篡改}
  - {id: AC-002, path_refs: [AP-002], objective: Android TLS机密性破坏}
  - {id: AC-003, path_refs: [AP-003], objective: 权限提升}
```

## REFLECTION

数量守恒为 3 已验证、7 理论、1 待定、1 排除，共 12。已验证仅表示源码或版本与官方影响条件匹配，不表示攻击复现或生产利用成功；理论项是待验证威胁假设，不自动构成整改需求。

后续本地验证已通过Workers102／927、标准Melos两包分析0 issues、subscription_core12项、旧App兼容24×2及图片异步解码专项回归。App最终全测1326 pass／9 fail，失败集合严格等于旧基线9项，新增失败为空，6项新版golden均通过。Android Debug APK已用Temurin21.0.13+9构建成功；iOS、真机、远端、离线Linux JDK载体和完整渗透测试仍待完成。

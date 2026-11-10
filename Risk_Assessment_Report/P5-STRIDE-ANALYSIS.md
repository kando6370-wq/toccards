# P5 STRIDE 威胁分析

## THINKING

基于 P2 DFD 和 P3 边界，枚举与升级直接相关且可由代码或官方公告支撑的威胁。

## PLANNING

覆盖六类 STRIDE，并保留触发条件、实际路径和验证状态。

## EXECUTION

```yaml:threat_inventory
threats:
  - {id: T-S-P-002-001, stride_type: S, element_id: P-002, title: 被盗会话冒充用户或管理员, description: 令牌泄漏后攻击者以既有身份访问API, cwe_refs: [CWE-287]}
  - {id: T-S-P-005-001, stride_type: S, element_id: P-005, title: 伪造支付回调, description: 签名或环境绑定验证不足时可冒充平台通知, cwe_refs: [CWE-345]}
  - {id: T-T-P-003-001, stride_type: T, element_id: P-003, title: 篡改识别输入或候选响应, description: 非法大输入或上游响应可能改变识别结果, cwe_refs: [CWE-20]}
  - {id: T-T-P-006-001, stride_type: T, element_id: P-006, title: 受漏洞pnpm安装阶段篡改构建输入, description: 恶意依赖可利用旧pnpm供应链缺陷影响安装或锁文件完整性, cwe_refs: [CWE-494]}
  - {id: T-R-P-004-001, stride_type: R, element_id: P-004, title: 高权限操作不可归责, description: 审计记录不足会削弱批准和退款操作追踪, cwe_refs: [CWE-778]}
  - {id: T-R-P-005-001, stride_type: R, element_id: P-005, title: 回调重放与事件归责不清, description: 缺少幂等与原始事件关联会造成争议, cwe_refs: [CWE-294]}
  - {id: T-I-DS-004-001, stride_type: I, element_id: DS-004, title: Secret或API Key泄漏, description: 配置日志或构建产物泄漏会暴露高敏凭据, cwe_refs: [CWE-200]}
  - {id: T-I-P-006-001, stride_type: I, element_id: P-006, title: 旧Dart TLS信任链可遭中间人攻击, description: 受影响Dart版本在Android及桌面dart:io可接受可推导私钥的中间CA, cwe_refs: [CWE-295]}
  - {id: T-D-P-001-001, stride_type: D, element_id: P-001, title: 复杂头部或大请求消耗资源, description: CORS解析与识别输入可能形成CPU或内存压力, cwe_refs: [CWE-400]}
  - {id: T-D-P-003-001, stride_type: D, element_id: P-003, title: 外部识别服务不可用传播, description: 上游超时或并发耗尽导致扫描失败, cwe_refs: [CWE-770]}
  - {id: T-E-P-004-001, stride_type: E, element_id: P-004, title: Admin授权绕过, description: 路由遗漏角色校验可将普通会话提升到管理权限, cwe_refs: [CWE-862]}
  - {id: T-E-P-006-001, stride_type: E, element_id: P-006, title: 构建工具链漏洞扩大执行权限, description: Gradle或依赖安装链漏洞可能在CI或开发机上下文执行非预期逻辑, cwe_refs: [CWE-269]}
summary:
  total: 12
  by_stride: {S: 2, T: 2, R: 2, I: 2, D: 2, E: 2}
  by_risk: {high: 4, medium: 6, low: 2}
```

## REFLECTION

十二项威胁覆盖全部 STRIDE 类别。依赖公告仅在满足触发条件时进入验证风险；未发现的触发路径将在 P6 标记为理论或排除。

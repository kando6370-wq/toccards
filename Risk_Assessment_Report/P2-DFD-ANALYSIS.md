# P2 调用流与 DFD 分析

## THINKING

P1 已通过 gate。重点追踪所有十二个入口跨越客户端、边缘/Linux API、数据库和外部识别/支付服务的路径。

## PLANNING

完成入口枚举、数据流追踪、调用链、数据存储和 DFD 综合校验。

## EXECUTION

```yaml:dfd_elements
elements:
  - {id: EI-001, type: ExternalInteractor, name: Flutter用户}
  - {id: EI-002, type: ExternalInteractor, name: Admin用户}
  - {id: EI-003, type: ExternalInteractor, name: Apple App Store Server Notifications}
  - {id: EI-004, type: ExternalInteractor, name: 插件客户端}
  - {id: P-001, type: Process, name: Hono共享API}
  - {id: P-002, type: Process, name: 认证与授权}
  - {id: P-003, type: Process, name: 扫描与识别编排}
  - {id: P-004, type: Process, name: Admin操作}
  - {id: P-005, type: Process, name: 订阅回调处理}
  - {id: P-006, type: Process, name: Linux Node适配器}
  - {id: DS-001, type: DataStore, name: PostgreSQL}
  - {id: DS-002, type: DataStore, name: KV与进程内缓存}
  - {id: DS-003, type: DataStore, name: R2与Linux图片卷}
  - {id: DS-004, type: DataStore, name: Secret与环境配置}
```

```yaml:data_flows
flows:
  - {id: DF-001, source: EI-001, target: P-001, data: 登录令牌与业务请求, protocol: HTTPS}
  - {id: DF-002, source: EI-002, target: P-004, data: Admin会话与运营操作, protocol: HTTPS}
  - {id: DF-003, source: EI-003, target: P-005, data: 签名支付通知, protocol: HTTPS}
  - {id: DF-004, source: EI-004, target: P-001, data: API Key与向量识别请求, protocol: HTTPS}
  - {id: DF-005, source: P-001, target: P-002, data: 认证授权上下文, protocol: internal}
  - {id: DF-006, source: P-001, target: P-003, data: pHash/OCR或旧向量, protocol: internal_and_https}
  - {id: DF-007, source: P-002, target: DS-001, data: 账号会话权益, protocol: PostgreSQL}
  - {id: DF-008, source: P-003, target: DS-001, data: 候选详情和扫描记录, protocol: PostgreSQL}
  - {id: DF-009, source: P-003, target: DS-003, data: 扫描图片, protocol: R2_or_volume}
  - {id: DF-010, source: P-004, target: DS-001, data: Admin查询与批准写入, protocol: PostgreSQL}
  - {id: DF-011, source: P-005, target: DS-001, data: 订单与权益状态, protocol: PostgreSQL}
  - {id: DF-012, source: P-006, target: P-001, data: Node Request Response适配, protocol: internal}
  - {id: DF-013, source: P-001, target: DS-002, data: 目录与汇率缓存, protocol: binding_or_memory}
  - {id: DF-014, source: DS-004, target: P-001, data: Secret与运行配置, protocol: binding_or_env}
  - {id: DF-015, source: P-001, target: EI-001, data: JSON响应与短期签名图片URL, protocol: HTTPS}
  - {id: DF-016, source: P-001, target: EI-002, data: Admin JSON响应, protocol: HTTPS}
l1_coverage:
  total_entry_points: 13
  analyzed: 13
  coverage_percentage: 100
  entry_point_analysis:
    EP-API-001: {analyzed: true, data_flow_traced: true}
    EP-API-002: {analyzed: true, data_flow_traced: true}
    EP-API-003: {analyzed: true, data_flow_traced: true}
    EP-API-004: {analyzed: true, data_flow_traced: true}
    EP-API-005: {analyzed: true, data_flow_traced: true}
    EP-API-006: {analyzed: true, data_flow_traced: true}
    EP-API-007: {analyzed: true, data_flow_traced: true}
    EP-UI-001: {analyzed: true, data_flow_traced: true}
    EP-UI-002: {analyzed: true, data_flow_traced: true}
    EP-UI-003: {analyzed: true, data_flow_traced: true}
    EP-SYS-001: {analyzed: true, data_flow_traced: true}
    EP-SYS-002: {analyzed: true, data_flow_traced: true}
    EP-HID-001: {analyzed: true, data_flow_traced: true}
```

## REFLECTION

十三个入口均已分析并追踪到数据流，L1 入口分析映射覆盖率为 100%；该数字不代表安全测试或渗透测试已经执行。当前回调流仅覆盖 Apple production/sandbox 通知；Google服务端 webhook 属于未来能力，尚未接入。识别、Apple通知、Admin 和双运行时适配器是后续重点。

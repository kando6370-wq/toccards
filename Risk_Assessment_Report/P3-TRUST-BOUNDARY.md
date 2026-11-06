# P3 信任边界评估

## THINKING

P2 已通过 gate。边界按用户身份、网络、运行时、服务和数据隔离划分。

## PLANNING

评估外部客户端、Cloudflare、Linux、外部供应商、数据库和管理面之间的跨界流。

## EXECUTION

```yaml:trust_boundaries
boundaries:
  - {id: TB-001, name: 公网客户端到API, type: Network, trust_level: untrusted_to_trusted}
  - {id: TB-002, name: 普通用户到Admin权限域, type: User, trust_level: privileged}
  - {id: TB-003, name: Cloudflare运行时到外部服务, type: Service, trust_level: third_party}
  - {id: TB-004, name: Linux宿主与容器网络, type: Process, trust_level: internal}
  - {id: TB-005, name: API到PostgreSQL与对象存储, type: Data, trust_level: sensitive}
  - {id: TB-006, name: CI依赖供应链到发布产物, type: Service, trust_level: build_chain}
```

```yaml:interfaces
interfaces:
  - {id: IF-001, name: HTTPS API, boundary: TB-001}
  - {id: IF-002, name: Admin鉴权, boundary: TB-002}
  - {id: IF-003, name: Apple通知签名验证, boundary: TB-003}
  - {id: IF-004, name: Node适配器, boundary: TB-004}
  - {id: IF-005, name: PostgreSQL连接, boundary: TB-005}
  - {id: IF-006, name: pnpm Flutter Gradle构建, boundary: TB-006}
```

```yaml:data_nodes
data_nodes:
  - {id: DN-001, name: 身份会话与权益, classification: confidential}
  - {id: DN-002, name: 用户收藏和扫描记录, classification: confidential}
  - {id: DN-003, name: Secret与API Key, classification: restricted}
  - {id: DN-004, name: 供应链锁文件与发布产物, classification: integrity_critical}
```

```yaml:cross_boundary_flows
flows:
  - {id: CBF-001, source_boundary: TB-001, target_boundary: TB-005, controls: [TLS, authn, authz, input_validation]}
  - {id: CBF-002, source_boundary: TB-002, target_boundary: TB-005, controls: [role_check, audit_log]}
  - {id: CBF-003, source_boundary: TB-003, target_boundary: TB-005, controls: [signature_verification, allowlist]}
  - {id: CBF-004, source_boundary: TB-004, target_boundary: TB-005, controls: [private_network, database_credentials]}
  - {id: CBF-005, source_boundary: TB-006, target_boundary: TB-004, controls: [lockfile, version_pin, CI_checks]}
```

## REFLECTION

六个边界均具有有效 ID 与类型。最关键的是供应链完整性、Admin授权、Apple通知真实性和Linux代理/宿主信任配置。

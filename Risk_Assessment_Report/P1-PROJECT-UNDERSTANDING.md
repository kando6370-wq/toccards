# P1 项目理解

## THINKING

项目路径可访问。核心问题是建立 Flutter、React、Hono 双运行时和 PostgreSQL 的实际攻击面；自动发现受 `.dart_tool` 历史产物污染，因此以当前源码、AGENTS 和 v1.1.4 文档交叉校正。

## PLANNING

已执行三层静态发现、文档分析、模块与入口清点、动态入口复核、来源对齐和覆盖度评估。

## EXECUTION

```yaml:module_inventory
modules:
  - {id: M-001, name: Flutter App, path: apps/flutter-app, security_level: HIGH}
  - {id: M-002, name: Admin Web, path: apps/admin-web, security_level: HIGH}
  - {id: M-003, name: Workers API, path: apps/workers-api, security_level: HIGH}
  - {id: M-004, name: Marketing Web, path: apps/marketing-web, security_level: MEDIUM}
  - {id: M-005, name: Auth Core, path: packages/auth-core, security_level: HIGH}
  - {id: M-006, name: Linux Deployment, path: deploy/linux, security_level: HIGH}
  - {id: M-007, name: Apple Callback, path: deploy/cloudflare/apple-callback, security_level: HIGH}
```

```yaml:entry_point_inventory
api_entries:
  - {id: EP-API-001, path: /api/v1/*}
  - {id: EP-API-002, path: /api/v1/auth/*}
  - {id: EP-API-003, path: /api/v1/admin/*}
  - {id: EP-API-004, path: /api/v1/scan/recognize}
  - {id: EP-API-005, path: /api/v1/extension/recognize}
  - {id: EP-API-006, path: /api/v1/apple/notifications/v2}
  - {id: EP-API-007, path: /api/v1/apple/notifications/v2/sandbox}
ui_entries: [{id: EP-UI-001}, {id: EP-UI-002}, {id: EP-UI-003}]
system_entries: [{id: EP-SYS-001}, {id: EP-SYS-002}]
hidden_entries: [{id: EP-HID-001}]
```

```yaml:discovery_checklist
checklist:
  rest_api: {scanned: true}
  internal_api: {scanned: true}
  graphql: {scanned: true}
  websocket: {scanned: true}
  cron_jobs: {scanned: true}
  message_queue: {scanned: true}
  webhooks: {scanned: true}
  file_upload: {scanned: true}
  health_endpoints: {scanned: true}
  debug_endpoints: {scanned: true}
  llm_gateway: {scanned: true}
  model_endpoint: {scanned: true}
  rag_pipeline: {scanned: true}
  agent_tool: {scanned: true}
summary: {coverage: "100%（十四类入口扫描覆盖，不代表安全测试执行）"}
```

## REFLECTION

七个模块均分配安全等级，十三个入口具有唯一 ID，十四类入口完成扫描。当前服务端通知入口仅为 Apple production/sandbox 两条路由；Google服务端 webhook 尚未接入。覆盖置信度为 0.82；未安装 Semgrep、Noir、CodeQL，后续风险结论须保留静态评估边界。

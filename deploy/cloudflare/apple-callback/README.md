# Linux dev 的 Apple Sandbox 通知入口

该独立 Cloudflare Worker 为 Linux dev 提供 HTTPS 回调入口。只接收 `POST /api/v1/apple/notifications/v2/sandbox`，其他路径返回 404，其他方法返回 405；签名校验、通知入库和订阅处理由 Linux 既有接口执行。

公网地址为 `https://dev-callback.tcgcard.fun/api/v1/apple/notifications/v2/sandbox`；同时保留 Worker 的 `workers.dev` 地址用于诊断。`LINUX_CALLBACK_ORIGIN` 使用 `http://dev-callback-origin.tcgcard.fun:8089`，需要 DNS-only A 记录 `dev-callback-origin → 111.10.170.43`。该公网端口由用户映射至 Linux `192.168.50.201:8080`。直接以裸 IP 回源在实际 Workers 环境返回 403/1003，因此必须先建立回源域名并验证连通性。

Cloudflare 的 HTTPS 只覆盖客户端到边缘这一段，HTTP origin 不会因此变成 HTTPS；后续可改为 HTTPS origin。2026-09-17 已在 Linux 主机增加[回源隔离策略](../../linux/security/README.md)：公网流量在 Docker DNAT 前转入只允许 Sandbox POST 的 8081 网关，私网 App/Admin 仍访问 8080。路由器的 8089 → 8080 映射不变；如果主机规则失效，该映射仍会暴露整站。

代理最多接收 200,000 字节，向固定的 Sandbox 路径原样传递请求体，不转发客户端 Authorization/Cookie，不重试、不缓存。Workers 使用 `redirect: "manual"` 并显式拒绝 3xx；该运行时不支持 Node 可用的 `redirect: "error"`。上游失败保留失败状态，连接或超时返回 502；10 秒截止时间覆盖上游响应正文。Worker 不绑定数据库、KV、R2 或 Apple 私钥，也不记录通知正文；日志仅包含上游异常类型和消息。

在仓库根验证：

```bash
node --test deploy/cloudflare/apple-callback/worker.test.mjs
pnpm --filter @kando/workers-api exec wrangler deploy --config ../../deploy/cloudflare/apple-callback/wrangler.toml --dry-run
```

实际部署使用相同命令移除 `--dry-run`。首次绑定或变更自定义域名前，先检查 Workers Custom Domain changeset，不覆盖其他服务或已有 DNS 记录；Wrangler 非交互发布可能自动覆盖冲突，不能在未知冲突状态下直接执行。生产 API、原 dev API 和向量服务均为独立部署目标，不由此入口的发布命令更新。

上线后先用空 JSON POST 验证 Linux 返回 400，再在 App Store Connect 的 beta App 配置 Sandbox V2 URL，使用 Apple TEST 通知核验真正的发送、入库和签名校验。仅部署 Worker 或通过 GET 访问不代表通知链路可用。

2026-09-17 实际验收：用户添加 DNS-only A 并保存 Sandbox URL 后，空 POST 经公网返回 Linux 400；一条 Apple 官方 TEST 已投递成功。Linux 解决 ESM bundle 中 Apple SDK 的 CommonJS 加载问题后，把该 TEST 的同一签名原文重放一次，经公网 200 入原 inbox，最终状态与结构化 `TEST` 均为 `processed`、签名/Bundle/UUID 匹配；没有创建交易或购买链。该验证只覆盖 Sandbox TEST，真实购买和 Restore 尚待真机验收；当次手工部署使用未提交源码，后续自动发布需单独核对。

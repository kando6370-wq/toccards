# 插件免登录识别接口

## 范围

新增 `POST /api/v1/extension/recognize`，供公开浏览器插件直接调用。任何人安装插件后均可使用，不要求 App 登录、匿名账号创建、订阅或扫描额度。服务端使用独立访问 Key 和按来源 IP 的短时间限频，复用现有 `VECTOR_RECOGNITION` 与卡牌详情业务；不创建新的业务服务、数据库或 migration。

这是轻量访问门槛，不是用户身份认证。插件内置 Key 可被提取，不能保证请求只来自官方插件，也不能阻止分布式攻击。更换 Key 后插件配置须同步更新。原 App `/api/v1/scan/*` 的登录、订阅、额度、图片和扫描记录契约保持不变。

## 请求与响应

- `Authorization: Bearer <插件专用Key>`，Key 不得复用 JWT 签名密钥、管理员凭据或其他服务凭据。
- `Content-Type: application/json`。
- JSON 正文最多 **32 KiB**，按实际流读取字节检查，不信任客户端自报的 `Content-Length`。
- `vector`：512 个有限数字，不能全部为零；与现有识别向量口径一致。
- `card_type`：数字 `0`（TCG）或 `1`（Sports Card），缺省为 `0`。
- 其他字段不向上游转发；调用方不能指定目标 URL、上游凭据或图片存储路径。

请求由插件已有向量生成流程提供，示例代码见下方插件接入；本接口不接收原始图片，也不生成向量。

### 2026-10-09：完整卡牌详情响应

成功返回 HTTP 200，保留顶层 `{candidates: [...]}`，不额外包裹 `success/data`。每个候选是现有 `GET /api/v1/cards/:card_ref` 的 `data`，加上识别的 `product_id` 和 `confidence`。示例值仅用于说明结构，不是真实价格或识别验收：

```json
{
  "candidates": [{
    "product_id": "10738",
    "confidence": 92.125,
    "card_ref": "10738",
    "name": "Example card",
    "game": "Pokemon",
    "set_name": "Example set",
    "set_code": "EX",
    "card_number": "001",
    "rarity": "Rare",
    "object_type": "tcg",
    "image_url": "https://image.tcgcard.fun/cards/10738.jpg",
    "finish": "Normal",
    "language": "English",
    "available_finishes": ["Holo", "Normal"],
    "available_languages": ["English", "Japanese"],
    "price_usd": 12.5,
    "previous_7d_price_usd": 10,
    "price_change_7d_percent": 25,
    "price_as_of": "2026-10-09",
    "override_applied": false
  }]
}
```

- 识别候选解析复用 App 现有规则：合法 ID 与 0–100 有限置信度；数字 ID 转为字符串，重复 ID 仅保留首次结果，数组仍按识别顺序排列，不按价格或置信度重新排序。
- 详情复用 `createDefaultAdapter → resolveCard → withCardImageUrl("detail")`，不复制价格选取、币种换算、图片拼接或运营覆盖逻辑。完整字段以现有详情响应为准，包括已存在的 1/7/30 天基准价/涨跌幅等可用字段。
- 采用卡牌详情规则而不是扫码候选的严格目录过滤：运营补录可正常返回；无详情的 ID 省略；全无详情或上游为空时返回 `{candidates: []}`。真实空识别不查询数据库。
- 没有价格时沿用详情接口的缺失字段，不生成 0 或假价格。价格只来自既有已发布价格数据，不采纳识别上游自报价格/名称。
- 查询异常返回 500，不伪装成成功空匹配或向量服务错误；任一详情查询失败时整请求失败，不静默返回部分结果。
- 本次仅补全现有详情字段，不额外查询所有市场报价、长期历史、成交记录或用户收藏/资产。只读卡牌/运营修正/价格数据，不上传图片、不创建扫描记录，不返回或扣减 App 额度。
- 此响应升级替代 2026-10-08 的原始识别 JSON 透传；历史验证保留，但不再作为当前返回契约。

所有响应设置 `Cache-Control: no-store`，沿用 API 的 `X-Request-ID` 与请求日志；不记录 Key、向量正文或上游诊断信息。

| HTTP | 错误码 | 含义 |
|---|---|---|
| 401 | `UNAUTHORIZED` | Key 缺失、错误或 Bearer 格式错误；不调用上游 |
| 413 | `PAYLOAD_TOO_LARGE` | 实际正文超过 32 KiB；不调用上游 |
| 422 | `VALIDATION_ERROR` | Content-Type、JSON 或识别参数不合法；不调用上游 |
| 429 | `RATE_LIMITED` | 短时间限频；附 `Retry-After: 60`，不调用上游 |
| 500 | `INTERNAL_ERROR` | 卡牌详情/价格数据库查询失败，不返回伪造空匹配 |
| 502 | `VECTOR_RECOGNITION_UNAVAILABLE` | 上游非成功状态、网络错误、无效 JSON 或无效候选，不返回其内部错误正文 |
| 503 | `EXTENSION_RECOGNITION_UNAVAILABLE` | Key/识别/限频/IP 配置缺失，或限频服务失败；拒绝服务，不放行 |
| 504 | `VECTOR_RECOGNITION_TIMEOUT` | 上游请求或响应体读取超时 |

错误正文沿用 `{ "success": false, "error": { "code": "...", "message": "..." } }`。上游只发 `{vector, card_type}`，不转发插件的 Authorization；10 秒 deadline 覆盖上游请求与响应体读取，不自动重试，不跟随重定向；详情查询沿用既有数据库契约，该 deadline 不代表整条详情补全链路的总超时。

## 环境配置及防刷边界

### prod Cloudflare

- 私有 Secret：`EXTENSION_RECOGNITION_KEY`；未配置时仅新接口返回 503，其他 API 不因此停用。
- 新增独立原生 binding：`EXTENSION_RECOGNITION_RATE_LIMITER`，配置为每个来源 IP **60 次 / 60 秒**，namespace 为 `2026100801`；正式发布前须核对账户内 namespace 不与其他业务共享。
- 入口从 Cloudflare 提供的 `CF-Connecting-IP` 写入每请求上下文，新路由不自行信任外部 `X-Forwarded-For`。
- 原生限频为每 Cloudflare location 的近似限制，不是跨地域全局精确计数，不是计费/日额度；分布式请求仍可能突破名义上的 60 次。
- 只增加上述 binding，既有 Hyperdrive/KV/R2/向量绑定、Smart Placement、缓存与 cron 不变。本文不构成部署或 Secret 修改授权。

原生限频语义见 [Cloudflare Rate Limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)。

### dev Linux

- 可选 `EXTENSION_RECOGNITION_KEY`：为空时关闭新接口，现有 API 仍正常启动。
- `EXTENSION_RECOGNITION_REQUESTS_PER_MINUTE`：默认 `60`，必须是正整数；不影响 App 的扫描额度。
- `EXTENSION_TRUST_PROXY`：默认 `false`，只允许 `true`/`false`。
- 直连 Node 必须保持 `false`，使用 TCP 来源 IP，忽略调用方伪造的 `CF-Connecting-IP` 和 `X-Forwarded-For`。
- 使用仓库标准 Caddy 或离线 Web 代理、且 Node API 3000 仅在私有 Compose 网络可达时，可以显式设为 `true`，取转发链最后一项有效 IP。不得在 Node 对公网/用户网段直连可达时开启；否则调用方可伪造身份绕过限频。
- 标准 Caddy 默认设置 `X-Forwarded-For`；离线代理仅对新识别路径（含 URI 编码等价路径）用 TCP 来源覆盖外部传来的该头，其他代理行为保持原状。
- 未开启代理信任而经代理请求时，以代理 IP 计数，多个用户可能共享 60 次窗口；上线前必须选择符合实际网络边界的配置。
- 内存限频为每进程、按分钟固定窗口；重启会清空计数，不是多副本全局限频。最多保存 10,000 个来源/窗口，容量满时拒绝新来源，不淘汰旧计数来绕过防刷。

这不是每日/月总量额度。Key 通过后，参数错误、上游失败等尝试也计入短时间窗口；错误 Key 不占用识别或限频调用。共享 NAT 出口会共享计数，应按实际插件批量调用情况调整阈值。

## 插件接入

仓库不包含插件源码，本次不新建插件工程。现有插件应在后台/service worker 中固定 API 地址、自动携带专用 Key，并配置对应域名的 `host_permissions`，不要由任意网页消息决定目标地址或传递 Key。沿用既有 CORS，不全局开放任意网页来源；CORS/插件 ID 不能替代服务端 Key 和防刷。

以下为后台请求方式，`API_BASE_URL` 为对应环境的 `/api/v1` 基址，`EXTENSION_KEY` 由插件发行配置提供；用户不需要填写或登录：

```javascript
const response = await fetch(`${API_BASE_URL}/extension/recognize`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${EXTENSION_KEY}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ vector, card_type }),
});
const result = await response.json();
```

遇到 429，应遵守 `Retry-After` 暂停，不立即循环重试。真实浏览器扩展网络权限、代理实机配置和 Cloudflare 运行时仍需外部验收。

## 2026-10-09 10:58 dev 手工发布检查点

Linux dev 已发布 `manual-extension-f952e50-dirty-20261009-1791513409974`，来自本地 `dev-extension` 未提交工作区，非纯 Git 提交。接口基址为 `http://192.168.50.201:8080/api/v1`，识别路径为 `/extension/recognize`。prod 未在本轮发布。

复用用户已配置的 dev Key 与频率 60，原字节未修改；在确认 API 无对外端口绑定、离线代理代码已更新后，备份私有环境并仅追加 `EXTENSION_TRUST_PROXY=true`。Key 不进入仓库、发布包或验收记录。

一次合成向量请求返回 5 个候选，完整详情均与原卡牌详情接口逐字段一致；63 次无效参数请求验证短时限频和伪造 IP 头无法绕过。尚未做真实照片/浏览器插件或图片加载验收。现有 watcher 仍跟踪 dev，未来该分支自动发布可能覆盖手工 dirty 版本；发布不会自动将此功能合并、提交或推送到 dev。具体备份、产物和未验证范围见当前版本验证记录。

## 2026-10-09 14:19 dev 分支发布检查点

既有 watcher 已将干净的 `dev@b621d76` 发布为 `branch-dev-b621d76501e6-20261009140959`，替换上午的 dirty 手工版本。manifest、current、last-seen 与 last-deployed 一致，失败标记不存在；此前“功能尚未进入 dev、手工版本可能被无此功能的 dev 覆盖”的风险不再适用于该提交。本轮没有更改 watcher 配置或手写其状态文件。

私有环境文件完整哈希发布前后相同，Key、频率 60 与 `EXTENSION_TRUST_PROXY=true` 保留，API 仍无宿主端口绑定。独立回查插件未带 Key 为 401、正确 Key 加无效参数为 422；一次合成向量请求返回 5 个候选，其详情均与原卡牌详情接口一致，均有价格与图片 URL。该轮未重复 63 次限频压测，未验证真实照片、浏览器插件、图片加载或识别准确率；prod 未发布。备份、产物与完整边界见 [验证记录](../05-delivery/VERIFICATION.md)。

## 启用、回退与验证

本地代码完成不等于 dev/prod 已发布。发布前需独立配置环境 Key、限频及可信代理边界，并核对内部 `/recognize` 的公网访问控制，避免绕过新入口；本仓无法单独证明外部识别服务已关闭未鉴权直连。

停用或清空插件 Key 即可关闭新入口，不影响原 App。变更限频规则只作用于此插件入口；本次没有 schema/migration 或业务数据回滚事项。Key 已分发后的替换需要插件配合，不宣称具备无感轮换。

实际执行和未验证边界见 [验证记录](../05-delivery/VERIFICATION.md)。

# v1.0.0 外部依赖

## 卡牌数据

外部采集流程把卡牌、游戏、系列与价格写入同一 D1 的 `cards_all`、`games`、`sets`、`tcg_price`。应用不直接调用采集程序；Workers 的 `LocalDbDataSourceAdapter` 对 Flutter 提供稳定 REST 契约。

读取链路：D1 基础数据 -> 合并启用的 `card_override` -> Cache API/KV 缓存可缓存结果 -> 返回 App。覆盖记录只改变 API 视图，不回写基础数据。

## OCR 识别服务

Workers 从 `OCR_SERVICE_BASE_URL` 调用 `POST /recognize`，发送客户端计算的 RGB pHash 与可选 `game_id`。返回候选经 D1 目录解析后才会暴露给 App；不在目录中的候选只进入审计记录。协议详见 [`scanHTTP接口对接说明.md`](scanHTTP接口对接说明.md)。

OCR URL 在 dev/prod 均由 Wrangler vars 配置。服务缺失、网络失败、非成功响应或响应结构非法时，扫描记录写为 `failed`，客户端收到 502/503，而不是伪造识别结果。

## 身份与邮件

| 服务 | 用途 | 服务端配置 |
|---|---|---|
| Google OAuth | Google 登录回调校验 | `GOOGLE_CLIENT_ID` |
| Apple Sign In | Apple 登录回调校验 | `APPLE_CLIENT_ID` |
| ZeptoMail | 注册/找回密码验证码 | URL、发件人 vars；token 使用 secret |

OAuth 身份必须由服务端验证后写入 `auth_identity`。邮件发送失败不会被当作验证码已成功送达。

## 汇率

Workers 汇率模块从外部汇率服务获取以 USD 为基准的快照并写入 KV。`GET /rates` 向 App 提供统一数据；外部请求失败时优先使用仍可接受的缓存，不修改原始 USD 价格。

## 客户端平台服务

Flutter 工程包含 Firebase 平台配置和 Mixpanel 分析集成。分析事件不作为授权、资产归属或金额计算依据。

## Cloudflare 资源

- D1：业务真源和外部卡牌数据。
- KV：可重建缓存。
- R2：扫描原图；对象 key 按所有者、年月和 `scan_id` 分区。
- Workers assets：托管 Admin SPA。

证据：`apps/workers-api/src/env.ts`、`wrangler.toml`、`data-source/`、`scan/routes.ts`、`auth/`，以及 Flutter `pubspec.yaml`。

## Android Google Play 服务端

安装证明使用 Play Integrity 已核实的包名、签名、构建号和时间。首次游客会话写入 PostgreSQL，邮箱注册、登录和 Google 登录从当前安装的可信会话承接证明。已有会话可在 `POST /api/v1/entitlements/google/installation` 提交绑定当前会话的新证明。旧版请求仍使用原认证格式。Linux dev 的安装证明豁免仅用于认证，计费构建身份需要真实 Play 证明。

`0019_google_play_subscriptions.sql` 为业务环境和 Google package 创建独立的配置、存量资格、购买、订单、通知和审计存储。先在相应环境迁移，再发布调用这些表的服务。回退应用版本时保留表和已入账事实。`GOOGLE_PLAY_PACKAGE_NAME` 与 `APP_ENVIRONMENT` 共同确定 scope。批准存量截止时间和首个计费构建后，通过参数化的 `google_play_prepare_rollout(scope, cutoff, first_build)` 一次性快照该环境的 Android 空间。`metering_enabled` 控制新版额度，`sales_enabled` 控制新售，默认均关闭。新额度只统计预留时记录了本批次的免费扫描。测试交易要求空间已登记在对应 scope 的 `google_play_test_space`。

服务端使用独立的 `GOOGLE_PLAY_PUBLISHER_EMAIL` 和 `GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY` 请求 Publisher API。`GOOGLE_PLAY_TOKEN_HASH_KEY` 使用 32 字节随机密钥的无填充 base64url，作为稳定索引密钥保存。`GOOGLE_PLAY_ENCRYPTION_KEYS` 以逗号分隔 `keyId:base64url`，首项用于写入，旧项用于回查历史密文。轮换加密密钥时保留旧项，索引密钥变更需先迁移历史映射。应用和后台均通过服务端访问商店。

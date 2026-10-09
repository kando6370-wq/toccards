# v1.1.1 管理后台增量

未变化的菜单、权限和 API 沿用 [v1.1.0 管理后台基线](../../v1.1.0/04-admin/admin.md)。prod 双入口的实际托管与发布边界以本页 2026-09-30 云端回读为准：历史“只随 Worker 部署”的描述不覆盖独立 Pages 入口，历史归档保留不回写。

## 扫描详情候选卡牌图片预览

2026-09-29 增量：在“卡牌管理 → 扫描记录管理 → 查看详情 → 候选识别结果”中，点击候选卡牌缩略图打开图片预览，可缩放并关闭；关闭后继续查看原扫描详情，不改变候选结果或用户确认状态。

- 沿用候选记录的 `image_url`，不拼接新的图片地址，不改变 Admin API。
- 缩略图保持原有 38×54 布局和等比展示，鼠标悬停提示“点击放大”。
- 无图片地址时保留空占位；图片加载失败时隐藏图片及其预览点击入口。
- 扫描列表图片和详情中的私有扫描原图维持原行为，仍由 `AuthenticatedScanImage` 携带 Admin Token 获取 Blob；此次不扩展其预览能力。
- 仅修改 Admin 前端，无数据库、权限、服务端或 Flutter 变更。

2026-09-29 17:03 已回读确认 watcher 发布 Linux dev `c9f950e`，17:04 核对 Admin 入口引用的 10 个资源均与本地 dev 构建哈希一致；17:37 又以 Admin-only 方式发布 prod `1b806fe1-7516-4749-ac87-77c3c6c29deb`，17:39 确认生产后端脚本逐字节不变、Admin 首页及 10 个入口资源与批准构建一致。dev 的扫描并行没有随本次 prod 发布上线；真实登录态扫描详情点击仍需补验。本地交互验证、部署证据与未执行边界见 [实际验证记录](../05-delivery/VERIFICATION.md)。


### 双 prod 入口补验（2026-09-29）

用户明确 `admin.tcgcard.fun` 与 `api.tcgcard.fun` 都是 prod Admin 访问域名，必须同步验收。17:46–17:52 的独立 GET 已复现：前者仍返回旧 `index-BUAPc0VN.js`，后者为新 `index-Cplutb86.js`。此前 17:37 发布及 17:39 产物验证只覆盖 API 域名的 Worker 副本，不能代表另一入口已更新。当时未修改域名归属或重定向，实际交付资源待补充权限后核对；该历史检查点未完成双入口同步，后续修复见下节。


## prod 双入口发布契约（2026-09-30 回读）

| 入口 | 实际托管 | 当前本次产物 |
|---|---|---|
| `admin.tcgcard.fun` | Pages 项目 `toccards-admin`，默认域 `toccards2.pages.dev`，production branch=main | 09:07 直接上传 deployment `038a65be-4858-4e31-89d1-fa67bf4ff559` |
| `api.tcgcard.fun` | `toccards-api-prod` 的 Workers assets | 沿用 9 月 29 日 version `1b806fe1-7516-4749-ac87-77c3c6c29deb`，不再发布 Worker |

两入口都使用生产 API `https://api.tcgcard.fun/api/v1/admin`。09:09 原失败的双域名检查转为通过，HTML 和各自 10 个 JS/CSS 资源均与批准的 Admin `c9f950e` production 构建逐字节一致；主资源为 `index-Cplutb86.js`。项目构建配置、环境变量及域名没有变化，API 后端/Hyperdrive/cron 未变化。

发布规则：

1. 分别核对两个入口的真实托管项目与运行版本；不能仅以域名同属 prod 推断共用静态部署。
2. 只发布 Admin 时复用同一批准的 production 构建。Pages 使用 `wrangler pages deploy <approved-admin-dist> --project-name toccards-admin --branch main`，可附实际源提交与 dirty 元数据；`--branch main` 是选择 Pages 生产通道，**不代表代码已经合入 Git main**。Worker 副本更新则必须保留经核验的现网后端，不能因此上线 dev 其他功能。
3. 用新请求分别获取两个域名的 HTML 及其引用资源，比对批准构建的字节/哈希和预览代码；同时检查生产 API 健康、未登录 401 及来自 Admin 域名的登录 OPTIONS 预检。不把产物一致替代真实登录态点击验收。
4. 回退须按目标分别选择：Pages 本次回退点是 `c0c4ac81-3cd7-4fca-bfe6-2f91d1c70f29`；本次未回退，Worker 也未再切流。

**该历史检查点的剩余风险（2026-09-30）**：Pages 的 GitHub main 自动构建仍开启，main 最新仍为 `e9e7578`，没有本次图片预览变更。后续 main 自动发布可能把手动上传版本覆盖回旧代码。需要另行授权将 Admin 专属改动同步 main，并再次执行双入口验收；本轮没有合并/推送 main，也没有关闭自动部署。真实生产账号点击仍需补验。

## 2026-10-08：从 main 重新发布两个 prod Admin 入口

- 干净源提交为 `main@61b5420`；候选图片预览已包含在 main。发布前回读发现 Pages 已在 9 月 30 日由 GitHub 自动发布同一提交，原“main 未含预览改动”的历史缺口已不适用于本次输入。
- 09:27 发布完整生产 API 及 Worker assets，version `4adbd0b7-3c67-4795-8ad0-c39795dc4be6` / 100%；09:29 使用同一批准的 11 文件 production 构建重发 Pages `toccards-admin`，deployment `39154bee-45d6-429d-8118-dfafed526ab7` / production / success，metadata 为 main、完整源 SHA 和 dirty=false。
- 09:36 两入口 HTML 及各 10 个 JS/CSS 均与批准构建逐字节一致，共 22 项通过。主资源仍为 `index-Cplutb86.js`；Pages 发布前 HTML 原始字节与本地不同，本次没有放宽断言，重新发布后原始字节全量匹配。
- Pages 构建配置、生产变量、GitHub main 自动部署及 active 域名不变；Worker 的运行变量/绑定、Smart Placement、Hyperdrive 查询缓存、cron、域名及预览开关不变。
- 新请求只读检查：health 200/status=ok，未登录 auth/me、Admin scans、portfolio folders 均 401，Admin 登录 OPTIONS 204 且 Allow-Origin/POST 正确；iOS/Google 公开 App 配置与发布前指纹相同。
- 本次同时发布了 API 的扫描并行和放置日志，不属于 Admin-only 发布。未运行数据库迁移、生产登录/扫描/购买写入、营销站或手机安装包发布；真实账号预览点击仍未补验。命令、回退点与验证边界见 [验证记录](../05-delivery/VERIFICATION.md)。

## 2026-10-09：插件 API 发布时同步双 prod Admin

- 本轮源为干净的本地 `main@c253647`，Admin 源码相对上一生产基线无变化。API 插件版本 `e8c5d1fb-0e4d-4eb0-8483-3a77a4ba08fb` 在 15:01 切到 100%；Worker assets 沿用同一批准产物，上传器确认无更新的静态文件。
- 发布前 API 域名的 11 个文件已匹配；独立 Pages 的 10 个 JS/CSS 匹配，HTML 原始字节不一致。15:03 单独将相同批准产物发布到 `toccards-admin`，deployment `cda22b78-846e-4b91-b6fc-7a69a022c768` 为 production/success，metadata 为 main、完整源 SHA、dirty=false。
- 15:05 两入口 HTML 及各 10 个 JS/CSS 共 22 项原始字节/SHA256 全部匹配，未归一化 HTML 后宣称原始字节一致；Pages 构建/环境/自动部署配置及域名保持不变，API 鉴权及 Admin 登录 CORS 烟测通过。
- 本轮没有推送 main；远端 main 仍是 `f952e50`，但 Admin 业务源码与此次产物对应源码无差异。发布前实际 Pages production 回退点为 `a3da17af-9579-4243-ad1a-c98c17fe0897`，本轮未回退。真实生产账号登录/候选图点击仍未补验，具体命令与插件未验项见 [验证记录](../05-delivery/VERIFICATION.md)。

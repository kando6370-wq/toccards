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

**剩余风险**：Pages 的 GitHub main 自动构建仍开启，main 最新仍为 `e9e7578`，没有本次图片预览变更。后续 main 自动发布可能把手动上传版本覆盖回旧代码。需要另行授权将 Admin 专属改动同步 main，并再次执行双入口验收；本轮没有合并/推送 main，也没有关闭自动部署。真实生产账号点击仍需补验。

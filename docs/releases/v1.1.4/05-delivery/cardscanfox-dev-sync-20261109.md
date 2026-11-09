# 官网改动同步到 dev（2026-11-09）

本次按用户要求，将已发布官网提交从 main 同步到 dev。来源 `main@12b9a43defa29eb07de1be4be684918019cf6592`，目标基线 `dev@b5b5154d`。源分支有 30 个尚未被 dev 包含的提交，涉及改版前营销内容、独立 CardScanFox 官网、只读网站服务、SEO/关键词页面、网站地图、IndexNow 修复及相关资料。dev 另有 56 个独有提交，全部保留。

采用正常双亲合并，不 rebase、不重写历史、不强推。文本自动合并无冲突。合并相对目标基线未修改 `apps/flutter-app`、`apps/admin-web`、`apps/workers-api`；dev 的 Android 免费首版、双端账号隔离、安全补丁和工具链配置均保留。

自动文本合并后，冻结安装发现两个新应用的 Wrangler importer 仍引用已不存在的旧 peer snapshot。将这两个引用对齐到 dev 已有的 `wrangler@4.106.0(@cloudflare/workers-types@4.20260702.1)(@types/node@26.3.0)`。没有调整包版本、覆盖 dev 的安全 overrides 或采纳无关 Babel peer 重新解析。初次离线安装缺少 registry 元数据，未记为通过；在线冻结安装重新验证。

使用 Node 22.23.4、pnpm 11.28.10 做影响面验证。验证完成：冻结安装及供应链策略检查通过；独立官网构建生成 122 条 HTML，46 条受保护原网址保留；新官网 47/47、独立只读服务 39/39、旧营销页 30/30，共 116 项测试通过；两个新应用的类型生成及 TypeScript 检查通过；生成器回读没有产生未预期的受跟踪文件差异。未运行无代码变更的 App、Admin、原业务 API 全量回归。Git 提交关系、路径与锁文件核对属于确定性操作，本次未调用 Jev；沿用 TypeSafe 的模型只负责语义判断、代码负责确定性流程的边界。

本次仅同步 dev，不执行生产部署、数据库迁移、业务写入或正式网址的重复 IndexNow 通知。dev 既有 CI/watcher 是否完成部署需以其运行状态为准，Git push 不代表运行环境已发布。

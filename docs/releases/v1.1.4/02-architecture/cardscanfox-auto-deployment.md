# CardScanFox 独立预览与自动部署

新版官网与只读服务使用现有 monorepo 中的独立应用，不修改旧营销站、App API、Flutter 或现有发布配置。独立 Git 分支 `codex/cardscanfox-preview` 从 `origin/main` 建立，仅包含新版官网、只读服务、共享公开内容包、工作区登记和必要文档。原工作区的未提交改动保留。

## 自动部署配置

Cloudflare 账号：`dced4adca2f35cff247b39979058b934`。复用已存在的 GitHub 连接 `kando6370-wq/toccards`，不建立第二套 App 业务接口或新 CMS。

| 目标 | 发布分支 | 根目录 | 构建命令 | 输出或部署 |
|---|---|---|---|---|
| Pages `cardscanfox-git-preview` | `codex/cardscanfox-preview` | `/` | `pnpm --filter @kando/cardscanfox-web build:ci` | `apps/cardscanfox-web/dist` |
| Worker `cardscanfox-site-data-preview` | `codex/cardscanfox-preview` | `/` | `pnpm --filter @kando/website-service build:ci` | `pnpm --filter @kando/website-service deploy:preview` |

Node 22、pnpm 11.9.0；禁用其他分支的预览构建。监听新应用、共享内容包和根工作区/锁文件。构建包含受影响测试、类型检查和打包。失败保留上一成功版本。Pages 清单 `sourceCommit` 与 Cloudflare 部署的提交 SHA 应一致。

## 当前预览边界

原 `cardscanfox-preview.pages.dev` 为已上传的静态对比版本。新 Pages Git 项目自动发布同类静态评审产物。108 个静态路径包括 46 个保护旧地址、32 个新增非单卡页面、30 个单卡评审页面。静态预览不支持依赖 Worker 的动态查询或全量目录。

只读 Worker 默认发布快照模式，关闭公共域名与版本 URL，不绑定数据库。真实只读连接、完整动态官网 Worker、全量数据许可与正式域名切换仍需分别落地和验收。预览维持 noindex、robots 禁止抓取，不提交 IndexNow。

## 内容真源

沿用本任务的[改版规格](../00-product/cardscanfox-website-redesign-spec.md)、[独立服务规格](../02-architecture/cardscanfox-website-service-spec.md)、[路由与搜索意图](../05-delivery/cardscanfox-website-route-seo-spec.md)及[单卡规模化索引方案](../05-delivery/cardscanfox-catalog-indexing.md)。旧归档代码与文档不因这次配置而回写。

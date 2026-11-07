# CardScanFox 独立预览与自动部署

新版官网与只读服务使用现有 monorepo 中的独立应用，不修改旧营销站、App API、Flutter 或现有发布配置。独立 Git 分支 `codex/cardscanfox-preview` 从 `origin/main` 建立，仅包含新版官网、只读服务、共享公开内容包、工作区登记和必要文档。原工作区的未提交改动保留。

## 自动部署配置

Cloudflare 账号：`dced4adca2f35cff247b39979058b934`。复用已存在的 GitHub 连接 `kando6370-wq/toccards`，不建立第二套 App 业务接口或新 CMS。

| 目标 | 发布分支 | 根目录 | 构建命令 | 输出或部署 |
|---|---|---|---|---|
| Pages `cardscanfox-git-preview` | `codex/cardscanfox-preview` | `/` | `pnpm --filter @kando/cardscanfox-web --fail-if-no-match build:ci` | `apps/cardscanfox-web/dist` |
| Worker `cardscanfox-site-data-preview` | `codex/cardscanfox-preview` | `/` | `pnpm --filter @kando/website-service --fail-if-no-match build:ci` | `pnpm --filter @kando/website-service --fail-if-no-match deploy:preview` |

Node 22、pnpm 11.9.0；禁用其他分支的预览构建。Pages 监听 `apps/cardscanfox-web/*`、`apps/website-service/*`、`packages/website-content/*`、`pnpm-*.yaml`、`package.json`。只读 Worker 监听相同范围中除官网应用目录之外的路径。构建包含受影响测试、类型检查和打包。失败保留上一成功版本。Pages 清单 `sourceCommit` 与 Cloudflare 部署的提交 SHA 应一致。

## 当前预览边界

原 `cardscanfox-preview.pages.dev` 为已上传的静态对比版本。新 Pages Git 项目通过 `build:pages` 生成服务端入口，使用 `SITE_DATA` binding 动态查询正式目录。108 个静态构建条目包括 46 个保护旧地址、32 个新增非单卡页面、30 个单卡评审页面；真实单卡地址不受这 30 条评审数据限制。

只读 Worker 当前通过现有正式库 Hyperdrive 执行只读事务，关闭公共域名与版本 URL。旧 App Worker、接口和绑定配置不修改。新服务与 App 复用数据库账户权限和连接池；独立限频、缓存与超时减少新增读取压力，不等于生产性能已经通过验收。正式域名切换与全量索引开放分别管理。预览维持 noindex、robots 禁止抓取，不提交 IndexNow。

## 内容真源

沿用本任务的[改版规格](../00-product/cardscanfox-website-redesign-spec.md)、[独立服务规格](../02-architecture/cardscanfox-website-service-spec.md)、[路由与搜索意图](../05-delivery/cardscanfox-website-route-seo-spec.md)及[单卡规模化索引方案](../05-delivery/cardscanfox-catalog-indexing.md)。旧归档代码与文档不因这次配置而回写。

## Pages 运行配置

Pages 项目的 `SITE_DATA` 绑定到 `cardscanfox-site-data-preview`，兼容日期 2026-11-07，开启 `nodejs_compat`。公开预览仅服务公开目录；独立 Worker 入口仍要求 Basic 认证。Git 构建生成 `_worker.js` 和包含全路径的 `_routes.json`，目录请求不能绕过服务端直接落到旧评审 HTML。发布清单仍可从 `/release-manifest.json` 回读。

## 价格区间修正

正式数据库集成阅读发现，价格展示投影把 micros 转为 text，而金额区间仍直接与整数比较，会触发 PostgreSQL 类型错误。区间比较改为显式 bigint；金额输出和零价语义保持。新增数据库回归覆盖低于 20、20 到 100、高于 100 三段。开发完成后在隔离 PostgreSQL 中回放修改前源码，同一低价筛选触发 42883；修后 39 项官网、26 项服务测试及类型/打包通过。Code Review 已核对金额类型、GET/HEAD 边界、预览访问控制、缓存版本与数据库读取预算；原 App 不在修改范围。

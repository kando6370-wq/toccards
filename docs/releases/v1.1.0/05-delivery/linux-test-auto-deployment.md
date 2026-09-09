# Linux 测试环境自动部署手册

## 目标

当 GitHub `dev` 分支出现影响 API、Admin、共享包或 Linux 部署配置的新提交时，由 `kd201` 本机定时监听、构建同一套业务代码并发布到测试环境。Cloudflare 正式环境的构建、绑定和部署流程不由该监听器触发。

测试地址：`http://192.168.50.201:8080`

## 当前工作方式

```text
开发者推送 dev
  -> kd201 用户 crontab 每两分钟检查分支 SHA
     -> 无相关变化则退出
     -> 拉取目标提交并安装锁定依赖
     -> 执行 Linux 受影响检查
     -> 构建 Node API 与 Admin SPA
     -> 发布前备份 PostgreSQL
     -> 创建 releases/<release-id>
     -> 使用服务器本地离线镜像构建容器
     -> 执行缺失 migration
     -> 验证 API、Admin 与 migration ledger
     -> 成功后切换 current
     -> 失败时重建上一个应用版本
```

监听器直接运行在 `kd201`，不要求 GitHub 仓库管理员权限或 GitHub Runner 注册令牌。仓库是公开仓库，因此监听器使用只读 HTTPS 拉取；`.env` 始终只保存在服务器，不进入 GitHub、构建产物或仓库。

## 触发规则

监听脚本：`deploy/linux/ci/watch-branch.sh`

自动部署条件：

- 远端分支为 `dev`。
- 新提交涉及 `apps/workers-api`、`apps/admin-web`、`packages`、`deploy/linux` 或 Node workspace 配置。
- Flutter、产品文档等无关变化只更新监听基线，不执行构建部署。
- 拉取、安装、检查或构建失败时不会进入发布阶段；同一提交进入 15 分钟重试冷却。

立即人工重试：

```bash
TOCCARDS_FORCE_DEPLOY=1 \
  /home/user/apps/toccards-test/watcher/watch-branch.sh
```

## 一次性安装 kd201 分支监听器

### 1. 验证前置条件

以 `kd201` 的 `user` 账号确认：

```bash
git --version
node --version
npm --version
docker version
docker compose version
docker ps
crontab -l
test -f /home/user/apps/toccards-test/shared/.env
docker image inspect eclipse-temurin:21.0.11_10-jre
```

Node 必须为 22；该账号必须能直接访问 Docker socket、GitHub 和 npm。当前离线构建依赖服务器本地的 `eclipse-temurin:21.0.11_10-jre` 基础镜像以及可用的 Ubuntu 软件源。

### 2. 安装监听器

从包含自动部署文件的工作区把两个脚本复制到服务器临时目录，然后执行：

```bash
bash deploy/linux/ci/install-branch-watcher.sh \
  deploy/linux/ci/watch-branch.sh \
  <安装时 dev 的 40 位提交 SHA>
```

安装脚本会：

- 把监听器保存到 `/home/user/apps/toccards-test/watcher/watch-branch.sh`。
- 把当前 `dev` SHA 写为首次基线，避免把已经部署的新功能版本降级回旧 `dev`。
- 在用户 crontab 中幂等写入每两分钟执行一次的任务。
- 保留用户已有的其他 crontab 项。

### 3. 查看监听状态

```bash
crontab -l
tail -f /home/user/apps/toccards-test/watcher/logs/watch.log
cat /home/user/apps/toccards-test/watcher/state/last-seen-sha
cat /home/user/apps/toccards-test/watcher/state/last-deployed-sha
```

### 4. 停用监听器

编辑用户 crontab，删除以下区块：

```text
# BEGIN TOCCARDS LINUX TEST WATCHER
*/2 * * * * /home/user/apps/toccards-test/watcher/watch-branch.sh
# END TOCCARDS LINUX TEST WATCHER
```

停用监听不会停止当前 API、Web 或 PostgreSQL 容器。

## 每次自动部署执行内容

### 分支检查与构建

1. `flock` 防止两个监听任务同时运行。
2. 获取 `dev` 最新 SHA，并与 `last-seen-sha` 比较。
3. 只在影响 Linux 部署的文件变化时继续。
4. 使用 Node.js 22，并通过 npm 在监听器私有目录固定安装 pnpm 11.9.0；不写入系统 `/usr/bin`。
5. 先构建共享 `@kando/auth-core`，保证干净检出环境能解析 workspace 类型。
6. 执行 Workers API 类型检查。
7. 执行 PostgreSQL、Linux adapter、CORS 和 Worker PostgreSQL runtime 定向测试。
8. 执行 Admin Linux API 地址测试。
9. 构建 `apps/workers-api/dist/linux/server.mjs` 和 `apps/admin-web/dist`。
10. 在服务器本地生成不含密钥的临时 Artifact。

### 发布阶段

发布脚本：`deploy/linux/ci/deploy-release.sh`

1. 使用独立发布锁防止并发发布。
2. 验证 Artifact 和服务器 `.env` 完整性。
3. 在 `/home/user/apps/toccards-test/backups` 创建 PostgreSQL custom-format 备份。
4. 创建不可覆盖的版本目录 `/home/user/apps/toccards-test/releases/<release-id>`。
5. 构建服务器本机架构的离线 Node/PostgreSQL/API/Web 镜像。
6. 运行 migration，并等待 API 健康。
7. 验证 migration ledger、`/api/v1/health` 和 Admin 首页。
8. 全部成功后更新 `/home/user/apps/toccards-test/current`、`current-release` 和 `last-deployed-sha`。

## 失败与回滚

- 发布前备份失败：立即停止，不修改运行容器。
- migration、API 或 Admin 验证失败：脚本使用上一个 release 重新构建应用容器，`current` 不切换。
- 数据库 migration 不会自动反向执行。自动发布 migration 必须向后兼容；需要恢复数据库时，由维护人员明确选择发布前生成的 `.dump` 文件后手动恢复。
- 失败的新 release 会保留，方便读取日志；确认无用后再人工删除。

查看状态和日志：

```bash
tail -n 200 /home/user/apps/toccards-test/watcher/logs/watch.log
cd /home/user/apps/toccards-test/current/deploy/linux
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.offline.yml \
  ps -a
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.offline.yml \
  logs --tail=200 migrate api web db
```

手动回滚应用版本：

```bash
previous=/home/user/apps/toccards-test/releases/<previous-release-id>
cd "$previous/deploy/linux"
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.offline.yml \
  up -d --build
ln -sfn "$previous" /home/user/apps/toccards-test/current
printf '%s\n' '<previous-release-id>' \
  > /home/user/apps/toccards-test/shared/current-release
```

## 可选 GitHub Runner 模式

`.github/workflows/linux-test-deploy.yml` 保留了 GitHub Actions 构建 + `toccards-kd201` 自托管 Runner 部署模式，但现在只允许手动触发。若未来改用它，需要仓库管理员创建 `linux-test` Environment 并注册带 `toccards-kd201` 标签的 Runner，同时删除服务器 crontab 监听，避免重复部署。

## 安全边界

- 监听器只检出受信任的 `dev` 分支，不执行 Pull Request head commit。
- 本地 Artifact 不包含 `.env`、数据库备份、扫描图片或第三方凭证。
- 监听器目录权限为 `700`，配置和状态仅属于服务器 `user` 账号。
- Linux 使用独立测试数据库、JWT、文件卷和 OCR 地址，不调用正式 OCR。
- `kd201` PostgreSQL 仅通过 `192.168.50.201:15432` 提供可信局域网访问，不映射公网；自动发布继续复用服务器私有 `.env` 中的该配置。
- 正式 Cloudflare 部署仍由其原工作流或 Cloudflare 平台配置管理。

## 接手检查清单

- [x] `crontab -l` 包含 `TOCCARDS LINUX TEST WATCHER` 区块。
- [x] 监听日志已推进到 2026-09-09 当时的 `dev@b0b54df2af7f`；一次 GitHub 网络超时在后续 cron 自动恢复。
- [ ] `dev` 已包含分支监听和发布脚本。
- [x] `kd201` 的共享 `.env` 存在且权限为 `600`。
- [x] 监听用户能够运行 `git`、`npm`、`docker ps`。
- [ ] 合入一次相关 `dev` 提交并确认构建、备份、迁移、健康检查和 `current-release`。
- [ ] 独立测试 OCR 地址准备后，更新服务器 `.env` 并重新部署。

## 实施验证记录 — 2026-09-09

- GitHub 登录账号对仓库有 push 权限，但没有 Admin/Actions Runner 管理权限，因此无法直接签发 Runner 注册令牌。
- 改为 `kd201` 本机只读拉取 `dev` 的 crontab 监听方式，不依赖仓库管理员权限。
- 发布脚本已使用与 Artifact 相同的目录结构在 `kd201` 验证：发布前生成 PostgreSQL custom-format 备份，创建并切换到 `manual-validation-20260909`，migration ledger 为 10，健康接口返回 `{"status":"ok"}`。
- `watch-branch.sh` 已通过功能分支端到端验证：在干净目录固定安装 pnpm 11.9.0，构建 `@kando/auth-core` 后完成 Workers 类型检查、26/26 定向测试、Admin 2/2 测试、Linux 构建、数据库备份、迁移和版本切换。
- 验证发布版本为 `branch-feature-linux-test-environment-2cd72364b6ad-20260909111201`，验证完成后 API 健康接口仍返回 `{"status":"ok"}`；临时监听目录已删除。
- 正式监听器当前只监控 `dev`，首次基线已推进到 `b0b54df2af7fd1614f13fe1e72979cec8e87888b`。因为该提交尚不含 Linux 自动部署资产，监听器按设计跳过发布；本功能分支合入 `dev` 后才会执行第一次正式自动发布。
- 2026-09-09 发布 `manual-pg-lan-20260909`，将 PostgreSQL 仅绑定到 `192.168.50.201:15432`。Mac TCP 连接成功，并通过项目 `postgres` 客户端只读查询到数据库 `toccards_test`、用户 `toccards`、PostgreSQL `18.6` 和 10 条 migration ledger；API 健康接口保持正常。

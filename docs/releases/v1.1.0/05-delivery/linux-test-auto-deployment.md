# Linux 测试环境自动部署手册

## 目标

当 GitHub `dev` 分支出现影响 API、Admin、共享包或 Linux 部署配置的新提交时，自动构建同一套业务代码并发布到 `kd201` 测试环境。Cloudflare 正式环境的构建、绑定和部署流程不由本工作流触发。

测试地址：`http://192.168.50.201:8080`

## 工作方式

```text
开发者推送 dev
  -> GitHub Actions 托管 Runner
     -> 安装依赖
     -> 执行 Linux 受影响检查
     -> 构建 Node API 与 Admin SPA
     -> 生成不含 .env 的发布产物
  -> kd201 自托管 Runner
     -> 发布前备份 PostgreSQL
     -> 创建 releases/<release-id>
     -> 使用服务器本地离线镜像构建容器
     -> 执行缺失 migration
     -> 验证 API、Admin 与 migration ledger
     -> 成功后切换 current
     -> 失败时重建上一个应用版本
```

GitHub 托管 Runner 无法访问 `192.168.50.201` 私网地址，因此部署 Job 必须由安装在 `kd201` 上的 GitHub Actions 自托管 Runner 执行。`.env` 始终只保存在服务器，不进入 GitHub Secrets、Artifact 或仓库。

## 触发规则

工作流文件：`.github/workflows/linux-test-deploy.yml`

自动触发条件：

- 分支为 `dev`。
- 变更涉及 `apps/workers-api`、`apps/admin-web`、`packages`、`deploy/linux` 或 Node workspace 配置。
- Flutter、产品文档等与 Linux API/Admin 无关的单独变化不会触发部署。

也可在 GitHub Actions 页面手动执行 `Linux test deploy`。如需监控其他分支，修改工作流 `on.push.branches`；不要同时让正式环境分支触发本测试部署。

## 一次性配置 kd201 Runner

### 1. 创建 Runner

进入 GitHub 仓库：

```text
Settings -> Actions -> Runners -> New self-hosted runner
```

选择 `Linux`、`x64`，按照 GitHub 页面当时显示的下载和注册命令，在 `kd201` 的 `user` 账号下安装。建议目录：

```text
/home/user/actions-runner/toccards
```

注册时增加自定义标签：

```text
toccards-kd201
```

工作流要求以下标签同时存在：`self-hosted`、`linux`、`x64`、`toccards-kd201`。

### 2. 安装为系统服务

Runner 必须在 SSH 断开和服务器重启后继续运行。使用 GitHub 安装目录内生成的 `svc.sh`，由服务器管理员执行：

```bash
cd /home/user/actions-runner/toccards
sudo ./svc.sh install user
sudo ./svc.sh start
sudo ./svc.sh status
```

不要只运行临时的 `./run.sh` 作为长期方案。

### 3. 验证服务器前置条件

以 Runner 的 `user` 账号确认：

```bash
node --version
docker version
docker compose version
docker ps
test -f /home/user/apps/toccards-test/shared/.env
docker image inspect eclipse-temurin:21.0.11_10-jre
```

Node 必须为 22；该账号必须能直接访问 Docker socket。当前离线构建依赖服务器本地的 `eclipse-temurin:21.0.11_10-jre` 基础镜像以及可用的 Ubuntu 软件源。

### 4. GitHub Environment

在仓库中创建名为 `linux-test` 的 Environment。测试环境可以不配置 Secret，因为运行密钥保存在 `kd201` 的 `/home/user/apps/toccards-test/shared/.env`。

如需人工批准后再部署，可在该 Environment 上增加 required reviewer；构建 Job 仍会自动完成，部署 Job 会等待批准。

## 每次自动部署执行内容

### 构建阶段

1. 使用 Node.js 22 和 pnpm 11.9.0。
2. 执行 Workers API 类型检查。
3. 执行 PostgreSQL、Linux adapter、CORS 和 Worker PostgreSQL runtime 的受影响测试。
4. 执行 Admin Linux API 地址测试。
5. 构建 `apps/workers-api/dist/linux/server.mjs` 和 `apps/admin-web/dist`。
6. 上传保存 14 天的无密钥 Artifact。

### 发布阶段

发布脚本：`deploy/linux/ci/deploy-release.sh`

1. 使用 `flock` 防止两个发布同时运行。
2. 验证 Artifact 和服务器 `.env` 完整性。
3. 在 `/home/user/apps/toccards-test/backups` 创建 PostgreSQL custom-format 备份。
4. 创建不可覆盖的版本目录 `/home/user/apps/toccards-test/releases/<release-id>`。
5. 构建服务器本机架构的离线 Node/PostgreSQL/API/Web 镜像。
6. 运行 migration，并等待 API 健康。
7. 验证 migration ledger、`/api/v1/health` 和 Admin 首页。
8. 全部成功后更新 `/home/user/apps/toccards-test/current`。

## 失败与回滚

- 构建或受影响测试失败：不会进入 `kd201` 部署 Job。
- 发布前备份失败：立即停止，不修改运行容器。
- migration、API 或 Admin 验证失败：脚本使用上一个 release 重新构建应用容器，`current` 不切换。
- 数据库 migration 不会自动反向执行。所有自动发布 migration 必须向后兼容；需要恢复数据库时，由维护人员明确选择发布前生成的 `.dump` 文件后手动恢复。
- 失败的新 release 会保留，方便读取日志；确认无用后再人工删除。

查看状态和日志：

```bash
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

## 安全边界

- 工作流仅响应 `push` 和人工触发，不响应外部 Pull Request，避免不可信代码在自托管 Runner 执行。
- GitHub Artifact 不包含 `.env`、数据库备份、扫描图片或第三方凭证。
- Runner 只用于受信任仓库，不与公共仓库共享。
- Linux 使用独立测试数据库、JWT、文件卷和 OCR 地址，不调用正式 OCR。
- 正式 Cloudflare 部署仍由其原工作流或 Cloudflare 平台配置管理。

## 接手检查清单

- [ ] GitHub 中 `toccards-kd201` Runner 状态为 Idle/Online。
- [ ] `linux-test` Environment 存在。
- [ ] `dev` 已包含自动部署工作流和部署脚本。
- [ ] `kd201` 的共享 `.env` 存在且权限为 `600`。
- [ ] Runner 用户能够运行 `docker ps`。
- [ ] 手动触发一次工作流并确认构建、备份、迁移、健康检查和 `current-release`。
- [ ] 独立测试 OCR 地址准备后，更新服务器 `.env` 并重新部署。

## 实施验证记录 — 2026-09-09

- 工作流 YAML 可解析，包含独立的 `build` 和 `deploy` Job。
- `deploy-release.sh` Bash 语法和参数缺失保护通过。
- Workers API 类型检查通过；PostgreSQL、Linux adapter、CORS 和 Worker runtime 定向测试 26/26 通过；Admin Linux 环境测试 2/2 通过。
- Linux API/Admin 构建和标准 Compose + 离线 Compose 合并配置通过。
- 使用与 GitHub Artifact 相同的目录结构，在 `kd201` 手动调用发布脚本成功：发布前生成 110 KiB PostgreSQL custom-format 备份，创建并切换到 `manual-validation-20260909`，migration ledger 为 10，健康接口返回 `{"status":"ok"}`。
- 截至 2026-09-09，`kd201` 尚未安装或注册 GitHub Actions Runner。因此自动监听尚未启用；仓库管理员完成“一次性配置 kd201 Runner”并将本分支内容合入 `dev` 后，后续匹配路径的 `dev` 提交才会自动部署。

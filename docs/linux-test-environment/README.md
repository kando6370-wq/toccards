# Linux 测试环境部署与自动升级手册

> 适用项目：`toccards`  
> 测试服务器：`kd201`（`192.168.50.201`）  
> 测试入口：`http://192.168.50.201:8080`  
> 自动部署分支：`dev`  
> 最近核对日期：2026-09-09

## 1. 目标与原则

Linux 测试环境和 Cloudflare 正式环境使用同一套业务代码，不维护两套 API、管理后台、SQL 或业务规则。环境差异仅放在运行入口、基础设施适配器、环境变量和部署脚本中。

| 项目 | Linux 测试环境 | Cloudflare 正式环境 |
|---|---|---|
| 业务代码 | 共用 `apps/workers-api`、`apps/admin-web`、`packages` | 同左 |
| API 运行时 | Node.js 22 | Cloudflare Workers |
| 数据库 | kd201 独立 PostgreSQL | 正式 PostgreSQL/Hyperdrive |
| 文件存储 | Linux 本地持久化卷 | Cloudflare R2 |
| KV | 进程内测试实现 | Cloudflare KV |
| 配置 | kd201 的 `shared/.env` | Cloudflare bindings/secrets |
| 发布入口 | `dev` 分支监听器 | 原 Cloudflare 正式发布流程 |

必须遵守以下隔离规则：

- 测试环境不得使用正式数据库、正式 OCR 地址或正式密钥。
- kd201 的 `.env`、数据库密码和 JWT secret 不提交到 Git。
- 自动部署只负责 kd201，不会触发或修改 Cloudflare 正式环境。
- 不执行 `docker compose down -v`，除非明确要永久清空测试数据库和扫描图片。

## 2. 当前目录与服务

### 2.1 仓库目录

```text
apps/workers-api/src/app.ts             # Cloudflare/Linux 共用 Hono 应用
apps/workers-api/src/index.ts           # Cloudflare Workers 入口
apps/workers-api/src/linux/             # Linux Node 入口和基础设施适配
apps/workers-api/scripts/build-linux.mjs
apps/admin-web/.env.linux               # Admin Linux 构建 API 地址
deploy/linux/                            # Compose、迁移、离线镜像和发布脚本
```

### 2.2 kd201 目录

```text
/home/user/apps/toccards-test/
  shared/.env              # 测试环境密钥和配置，权限应为 600
  shared/deploy.lock       # 发布互斥锁
  releases/                # 每次部署的不可覆盖版本目录
  current                  # 指向当前版本的软链接
  backups/                 # 发布前 PostgreSQL custom-format 备份
  watcher/
    watch-branch.sh        # dev 分支监听器
    watcher.env            # 仓库、分支、目录和重试配置
    source/                # 自动部署使用的独立 Git 检出
    artifact/              # 临时构建产物
    state/                 # 最近发现、部署或失败的 SHA
    logs/watch.log         # 自动部署日志
```

### 2.3 Docker 服务

| Compose 服务 | 容器 | 作用 |
|---|---|---|
| `db` | `toccards-linux-test-db-1` | PostgreSQL 测试数据库 |
| `migrate` | `toccards-linux-test-migrate-1` | 幂等执行未应用 migration |
| `api` | `toccards-linux-test-api-1` | Node API |
| `web` | `toccards-linux-test-web-1` | Admin 静态站点和 API 反向代理 |

## 3. 配置文件

模板位于 `deploy/linux/.env.example`。服务器实际配置固定放在：

```text
/home/user/apps/toccards-test/shared/.env
```

首次创建：

```bash
cd deploy/linux
cp .env.example .env
chmod 600 .env
```

至少设置：

- `POSTGRES_PASSWORD`
- `DATABASE_URL`
- `JWT_SECRET`
- `OCR_SERVICE_BASE_URL`
- `LINUX_TEST_SITE_ADDRESS`
- `ALLOWED_ORIGINS`

kd201 使用局域网 HTTP 时的非敏感配置示例：

```dotenv
LINUX_TEST_SITE_ADDRESS=http://192.168.50.201
HTTP_PORT=8080
ALLOWED_ORIGINS=http://192.168.50.201:8080
POSTGRES_LISTEN_ADDRESS=192.168.50.201
POSTGRES_HOST_PORT=15432
```

真实密码只从服务器读取，不写入本文档：

```bash
ssh kd201 'sed -n "/^POSTGRES_PASSWORD=/p" /home/user/apps/toccards-test/shared/.env'
```

## 4. 自动部署流程

kd201 的用户 `crontab` 每两分钟执行一次 `watch-branch.sh`：

```text
推送 dev
  -> kd201 获取远端 dev SHA
  -> 判断是否涉及 Linux 测试环境
  -> 安装锁定依赖并执行定向检查
  -> 构建 Node API 和 Admin
  -> 发布前备份 PostgreSQL
  -> 创建 releases/<release-id>
  -> 构建并启动 Compose 服务
  -> 执行缺失 migration
  -> 验证 migration、API 和 Admin
  -> 成功后切换 current
  -> 失败则恢复上一个应用版本
```

### 4.1 会触发部署的变更

- `apps/workers-api/**`
- `apps/admin-web/**`
- `packages/**`
- `deploy/linux/**`
- `.dockerignore`
- Node workspace、锁文件、TypeScript 或 Turbo 配置
- `.github/workflows/linux-test-deploy.yml`

Flutter 或纯产品文档变更不会重新构建 Linux 服务；监听器只推进 `last-seen-sha`。

### 4.2 查看监听器

```bash
ssh kd201 'crontab -l'
ssh kd201 'tail -100 /home/user/apps/toccards-test/watcher/logs/watch.log'
ssh kd201 'cat /home/user/apps/toccards-test/watcher/state/last-seen-sha'
ssh kd201 'cat /home/user/apps/toccards-test/watcher/state/last-deployed-sha'
ssh kd201 'cat /home/user/apps/toccards-test/shared/current-release'
```

### 4.3 立即执行或重试

不等待下一次 cron：

```bash
ssh kd201 'TOCCARDS_FORCE_DEPLOY=1 /home/user/apps/toccards-test/watcher/watch-branch.sh'
```

同一失败提交默认冷却 15 分钟。人工确认问题已解决后再使用 `TOCCARDS_FORCE_DEPLOY=1`。

### 4.4 首次安装监听器

```bash
bash deploy/linux/ci/install-branch-watcher.sh \
  deploy/linux/ci/watch-branch.sh \
  <当前 dev 的 40 位提交 SHA>
```

安装脚本会保留已有 crontab，并幂等维护以下区块：

```cron
# BEGIN TOCCARDS LINUX TEST WATCHER
*/2 * * * * /home/user/apps/toccards-test/watcher/watch-branch.sh
# END TOCCARDS LINUX TEST WATCHER
```

## 5. 日常发布步骤

正常情况下只需要：

```bash
git checkout dev
git pull --ff-only origin dev
# 合并已经验证的功能分支
git merge <feature-branch>
git push origin dev
```

之后观察 kd201：

```bash
ssh kd201 'tail -f /home/user/apps/toccards-test/watcher/logs/watch.log'
```

部署成功日志应包含目标 SHA、`Deployment completed` 和 release 信息。随后执行第 9 节的受影响面验证。

## 6. 手工部署

只有自动监听器不可用或需要受控恢复时才使用手工部署。

### 6.1 标准 Compose

适用于服务器可拉取配置的镜像：

```bash
cd deploy/linux
docker compose --env-file .env up -d --build
docker compose ps
docker compose logs --tail=100 migrate api web
```

### 6.2 kd201 离线 Compose

kd201 当前使用离线覆盖文件：

```bash
cd deploy/linux
sh offline/prepare-node-runtime.sh
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.offline.yml \
  up -d --build
```

离线镜像必须按 kd201 的 `amd64` 架构构建。不要把 Apple Silicon Mac 导出的 ARM64 PostgreSQL 镜像直接用于 kd201。

## 7. 脚本说明

| 文件 | 调用者 | 主要职责 | 失败保护 |
|---|---|---|---|
| `deploy/linux/ci/watch-branch.sh` | cron/人工 | 拉取 `dev`、判断影响面、定向检查、构建 Artifact、调用发布脚本 | `flock` 防并发；失败 SHA 冷却；发布前失败不改运行环境 |
| `deploy/linux/ci/install-branch-watcher.sh` | 一次性人工执行 | 安装监听器、生成 `watcher.env`、写初始 SHA、维护 crontab | 不覆盖 crontab 其他任务；目录和配置使用严格权限 |
| `deploy/linux/ci/deploy-release.sh` | 监听器/人工 | 校验 Artifact、备份数据库、创建 release、启动服务、健康验证、切换 `current` | 发布锁；备份失败即停止；应用失败重建上一 release |
| `deploy/linux/migrate.sh` | Compose `migrate` | 等待 PostgreSQL、维护 `schema_migrations`、事务执行新 migration | `ON_ERROR_STOP`；单个 migration 失败时回滚事务 |
| `deploy/linux/offline/prepare-node-runtime.sh` | 发布脚本/人工 | 从 kd201 宿主机准备 Node 22 离线运行文件 | Node 或必要运行资源缺失时停止构建 |
| `deploy/linux/offline/postgres-entrypoint.sh` | PostgreSQL 离线镜像 | 初始化数据库、认证规则和目标数据库 | 使用 `POSTGRES_USER` 幂等创建数据库 |
| `apps/workers-api/scripts/build-linux.mjs` | watcher/开发者 | 将 Linux Node API 打包到 `dist/linux/server.mjs` | 构建错误直接返回非零状态 |

## 8. 数据库与管理员

### 8.1 Mac 连接 kd201 PostgreSQL

```text
Host: 192.168.50.201
Port: 15432
Database: toccards_test
Username: toccards
Password: 读取 kd201 shared/.env
SSL mode: disable
```

该端口只能在可信局域网使用，不得改成 `0.0.0.0` 或映射到公网。

### 8.2 创建测试管理员

管理员保存在 PostgreSQL 的 `admin_user` 表。密码必须使用项目兼容的 PBKDF2 格式，不能直接写明文。优先由维护人员使用经过复核的创建命令或后续专用管理脚本执行，并在创建后调用：

```text
POST /api/v1/admin/auth/login
```

验证账号可登录。不要把管理员明文密码写入 Git、部署日志或本文档。

## 9. 部署后验证

只验证 Linux 部署的影响面：

```bash
# 容器与健康状态
ssh kd201 'docker ps --filter name=toccards-linux-test --format "{{.Names}} {{.Status}}"'

# API
curl -fsS http://192.168.50.201:8080/api/v1/health

# Admin 首页
curl -fsS http://192.168.50.201:8080/ | grep -F '<title>Kando Admin</title>'

# migration ledger
ssh kd201 'docker exec toccards-linux-test-db-1 \
  psql -U toccards -d toccards_test -tAc \
  "SELECT count(*) FROM schema_migrations"'
```

预期 API 响应：

```json
{"status":"ok"}
```

如果本次变更涉及登录，再额外验证管理后台登录；涉及数据库结构时，再验证对应 migration 和业务接口。无影响面的 Flutter、Cloudflare 正式环境或 OCR 不应因一次 Linux 文档/部署变更而重复测试。

## 10. 备份与回滚

自动发布会在切换版本前创建 PostgreSQL custom-format 备份：

```text
/home/user/apps/toccards-test/backups/
```

查看版本：

```bash
ssh kd201 'readlink -f /home/user/apps/toccards-test/current'
ssh kd201 'ls -lt /home/user/apps/toccards-test/releases | head'
ssh kd201 'ls -lt /home/user/apps/toccards-test/backups | head'
```

发布脚本在新应用启动或健康验证失败时，会重新构建上一个 release。数据库 migration 不自动反向回滚，因此 migration 必须保持向前兼容；需要恢复数据时，必须先停止写入并由维护人员确认备份和恢复目标。

## 11. 常见问题

### GitHub 偶发无法连接

现象：`Failed to connect to github.com`、`GnuTLS recv error` 或 `fetch-pack: unexpected disconnect`。

处理：等待网络恢复后让 cron 自动重试，或人工执行强制部署。不要在远端 SHA 未确认时手工覆盖 `last-seen-sha`。

### 新提交没有触发部署

依次确认：

1. 提交确实已推送到 GitHub `dev`。
2. `last-seen-sha` 是否已经更新。
3. 变更路径是否属于第 4.1 节的触发范围。
4. `watch.log` 是否记录“no Linux deployment impact”。
5. 是否存在失败冷却或另一个 `flock` 任务正在执行。

### API 未变为 healthy

```bash
ssh kd201 'docker logs --tail=200 toccards-linux-test-migrate-1'
ssh kd201 'docker logs --tail=200 toccards-linux-test-api-1'
ssh kd201 'docker logs --tail=200 toccards-linux-test-web-1'
```

优先检查 migration、`DATABASE_URL`、PostgreSQL 认证和 Linux 构建产物，不要改用正式数据库绕过问题。

### OCR 无法使用

OCR 必须配置独立测试接口。未提供测试接口时应保持不可用配置，禁止回退到正式 OCR 服务。

## 12. 维护检查表

- [ ] 业务改动只维护一套共享代码。
- [ ] 测试与正式环境仅通过配置、入口和适配层区分。
- [ ] `shared/.env` 未进入 Git 或 Artifact。
- [ ] migration 向前兼容并可幂等执行。
- [ ] 发布前 PostgreSQL 备份成功且文件非空。
- [ ] `dev` 目标 SHA 与 `last-deployed-sha` 一致。
- [ ] API 健康、Admin 页面及本次影响接口验证通过。
- [ ] `current` 指向最新成功 release。

## 13. 相关实现资料

- `deploy/linux/README.md`
- `docs/releases/v1.1.0/02-architecture/linux-test-environment.md`
- `docs/releases/v1.1.0/05-delivery/linux-test-auto-deployment.md`
- `docs/releases/v1.1.0/05-delivery/linux-test-environment-implementation-plan.md`

本文档是日常部署与接手入口；版本目录中的文档继续保留架构决策和历史交付证据。

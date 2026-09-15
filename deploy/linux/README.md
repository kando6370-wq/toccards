# Linux 测试环境部署

本目录启动独立 PostgreSQL、Node API 和 Caddy/Admin；离线模式使用 Node 静态服务。它承接现有 dev 的 Linux 整改，业务数据和图片使用本地资源；按用户明确选择，仅向量检索经 HTTP 复用现有 CF 识别服务。

Linux 部署资产已通过 `19a6ac4` 合入；2026-09-15 的后端适配基于 `dev@b941a3f`，在源码中构造 `VECTOR_RECOGNITION`，固定请求配置 origin 下的 `/recognize`，10 秒超时覆盖响应体读取。该配置变更需要在部署前准备，服务器与设备扫描仍需验收，见[Linux 兼容缺口](../../docs/releases/v1.1.0/02-architecture/linux-test-environment.md#扫描兼容缺口)和[运维手册](../../docs/linux-test-environment/README.md)。

## 前置条件

- Linux 服务器已安装 Docker Engine 和 Docker Compose Plugin。
- 测试域名已解析到服务器；首次验证也可直接使用 `http://服务器IP:8080`。
- 已准备独立测试 JWT secret、CF 识别 origin 和需要启用的 OAuth/Apple/邮件测试配置。

默认使用 Docker 官方 `node`、`caddy` 和 `postgres` 镜像。如果服务器无法访问 Docker Hub，可在 `.env` 中将 `NODE_IMAGE`、`CADDY_IMAGE`、`POSTGRES_IMAGE` 改为企业已审核的镜像代理地址，不需要修改 Dockerfile 或业务代码。

如果服务器完全无法拉取 Node/Caddy 镜像，但已安装 Node.js 22 且存在一个与宿主机同发行版的本地 Docker 基础镜像，可使用 `docker-compose.offline.yml`。该模式把宿主机 Node 22 及其动态库封装为本地运行镜像，直接装载已在开发机完成的 API/Admin 构建产物；业务代码、PostgreSQL schema 和环境变量与标准 Compose 模式相同。

## 首次部署

```bash
cd deploy/linux
cp .env.example .env
chmod 600 .env
```

编辑 `.env`，至少替换：

- `POSTGRES_PASSWORD`
- `DATABASE_URL` 中对应密码
- `JWT_SECRET`
- `VECTOR_RECOGNITION_BASE_URL`：必填 HTTP(S) origin，例如 `https://recognize-vec.tcgcard.fun`，不包含路径、凭据、查询参数或 fragment。
- `LINUX_TEST_SITE_ADDRESS`
- `ALLOWED_ORIGINS`

如果使用 IP 和 HTTP：

```dotenv
LINUX_TEST_SITE_ADDRESS=http://服务器IP
HTTP_PORT=8080
ALLOWED_ORIGINS=http://服务器IP:8080
```

现有 App test 默认请求 `http://192.168.50.201:8080/api/v1`；Admin development 构建使用同源 `/api/v1/admin`，本机 Vite 代理到该内网服务。Flutter Web 的 `pnpm app:chrome:dev` 固定使用 3000 端口，应在服务器 `ALLOWED_ORIGINS` 增加 `http://localhost:3000`、`http://127.0.0.1:3000`，模板已列出这些 origin。本阶段没有写入服务器 `.env`。

启动：

```bash
docker compose --env-file .env up -d --build
docker compose ps
docker compose logs --tail=100 migrate api web
```

健康检查：

```bash
curl -fsS http://服务器IP:8080/api/v1/health
```

预期响应：

```json
{"status":"ok"}
```

## 离线镜像部署

先在仓库根执行 `pnpm --filter @kando/workers-api build:linux`，再将仓库及构建产物复制到服务器。服务器必须已有 `.env` 中 `NODE_RUNTIME_BASE_IMAGE` 和 `POSTGRES_RUNTIME_BASE_IMAGE` 指定的本地 Ubuntu 基础镜像；Node 运行镜像使用宿主机 Node 22，PostgreSQL 镜像通过 Ubuntu 软件源在服务器本机生成对应 CPU 架构的镜像。

API 打包脚本通过 Node `fileURLToPath` 解析入口和输出路径，可从 Windows 工作区构建离线产物；容器运行、原生镜像和数据库验证仍需在目标 Linux 服务器完成。本地构建成功不覆盖向量识别适配缺口。

在服务器执行：

```bash
cd deploy/linux
sh offline/prepare-node-runtime.sh
docker compose --env-file .env \
  -f docker-compose.yml \
  -f docker-compose.offline.yml \
  up -d --build
```

更新版本时重新复制构建产物，然后重复上述 Compose 命令。`prepare-node-runtime.sh` 仅在宿主机 Node 或基础镜像变化时需要再次运行。

离线模式只开放 HTTP 端口，不启用 Caddy 自动 HTTPS；需要 HTTPS 时应在测试域名入口或现有反向代理层终止 TLS。

## 更新版本

从目标 Git 分支拉取新提交后执行：

```bash
cd deploy/linux
docker compose --env-file .env up -d --build
docker compose ps
docker compose logs --tail=100 migrate api web
```

`migrate` 服务只执行 `schema_migrations` 中尚未记录的 PostgreSQL migration。API 只有在 migration 成功后才启动。

升级本次后端适配前，需在服务器 `.env` 添加 `VECTOR_RECOGNITION_BASE_URL`；仅有旧 OCR 配置时，新版本会拒绝启动。新代码不读取 `OCR_SERVICE_BASE_URL`，过渡期可保留旧键供旧版本回滚，或同时备份并恢复对应版本的 `.env`。这不增加数据库 migration；现有 PostgreSQL 18 数据卷须继续使用兼容的 18 镜像，不能套用标准 Compose 默认的 16 镜像启动。

## 自动部署

2026-09-09 的服务器记录显示 `kd201` 使用本机 `crontab` 每两分钟运行 `ci/watch-branch.sh`，监控 `dev` 分支中影响 API、Admin、共享包或 Linux 部署配置的提交。脚本在拉取、定向检查、构建后，调用 `ci/deploy-release.sh` 完成数据库备份、版本化发布、健康验证和应用回滚；本轮未确认当前服务器安装或最新自动发布结果。

仓库同时保留 `.github/workflows/linux-test-deploy.yml` 作为未来可选的 GitHub 自托管 Runner 方案。当前安装方法、触发规则、失败处理和接手步骤见 [`Linux 测试环境自动部署手册`](../../docs/releases/v1.1.0/05-delivery/linux-test-auto-deployment.md)。自动部署不会读取或修改 Cloudflare 正式环境。

## 日志

```bash
docker compose logs -f api
docker compose logs -f web
docker compose logs -f db
```

## 从开发电脑连接 PostgreSQL

Compose 默认只把 PostgreSQL 映射到服务器回环地址 `127.0.0.1:15432`。如果开发电脑与服务器位于可信局域网，可在服务器 `.env` 中明确设置：

```dotenv
POSTGRES_LISTEN_ADDRESS=192.168.50.201
POSTGRES_HOST_PORT=15432
```

重新执行 Compose 后，Mac 上的数据库客户端使用：

```text
Host: 192.168.50.201
Port: 15432
Database: toccards_test
Username: toccards
Password: 读取 kd201 的 shared/.env
SSL mode: disable
```

该端口只用于测试环境数据查看。不要设置为 `0.0.0.0`，不要在公网路由器映射 `15432`，也不要把密码写入仓库。

## 备份

数据库备份：

```bash
docker compose exec -T db pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --format=custom > "toccards-test-$(date +%Y%m%d-%H%M%S).dump"
```

扫描图片保存在 Compose volume `scan-images`。升级或重建容器不会删除该 volume。执行 `docker compose down -v` 会删除数据库和图片，只能在明确需要重置测试数据时使用。

## 回滚

1. 切换到上一个已验证 Git commit。
2. 执行 `docker compose --env-file .env up -d --build`。
3. 若新版本包含不可逆 migration，先从部署前数据库备份恢复，再启动旧版本。

## 安全边界

- `.env` 不得提交 Git。
- PostgreSQL 默认只映射服务器回环地址；需要开发机直连时，只允许绑定可信局域网 IP 和非默认宿主机端口。
- Linux 必须使用独立测试数据库、JWT 和第三方凭证；CF 向量检索作为已授权的只读外部依赖复用，服务器出站和 iOS/Android 完整扫描须另行验收。
- 本部署不修改 Cloudflare dev/prod 数据或 bindings；两环境已完成 PostgreSQL 迁移，D1 不属于迁移或回滚目标。

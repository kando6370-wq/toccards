# Linux 测试环境部署

本目录启动独立 PostgreSQL、Node API 和 Caddy/Admin。它只用于测试环境，不连接 Cloudflare Hyperdrive、KV、R2 或正式 OCR 服务。

## 前置条件

- Linux 服务器已安装 Docker Engine 和 Docker Compose Plugin。
- 测试域名已解析到服务器；首次验证也可直接使用 `http://服务器IP:8080`。
- 已准备独立测试 OCR 地址、JWT secret 和需要启用的 OAuth/Apple/邮件测试配置。

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
- `OCR_SERVICE_BASE_URL`
- `LINUX_TEST_SITE_ADDRESS`
- `ALLOWED_ORIGINS`

如果使用 IP 和 HTTP：

```dotenv
LINUX_TEST_SITE_ADDRESS=http://服务器IP
HTTP_PORT=8080
ALLOWED_ORIGINS=http://服务器IP:8080
```

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

先在开发机完成构建并将仓库工作区复制到服务器。服务器必须已有 `.env` 中 `NODE_RUNTIME_BASE_IMAGE` 和 `POSTGRES_RUNTIME_BASE_IMAGE` 指定的本地 Ubuntu 基础镜像；Node 运行镜像使用宿主机 Node 22，PostgreSQL 镜像通过 Ubuntu 软件源在服务器本机生成对应 CPU 架构的镜像。

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

## 自动部署

仓库提供 GitHub Actions 工作流 `.github/workflows/linux-test-deploy.yml`。默认监控 `dev` 分支中影响 API、Admin、共享包或 Linux 部署配置的提交：GitHub 托管 Runner 完成检查与构建，安装在 `kd201` 的自托管 Runner 调用 `ci/deploy-release.sh` 完成数据库备份、版本化发布、健康验证和应用回滚。

首次安装 Runner、触发规则、失败处理和接手步骤见 [`Linux 测试环境自动部署手册`](../../docs/releases/v1.1.0/05-delivery/linux-test-auto-deployment.md)。自动部署不会读取或修改 Cloudflare 正式环境。

## 日志

```bash
docker compose logs -f api
docker compose logs -f web
docker compose logs -f db
```

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
- PostgreSQL 不映射宿主机端口。
- Linux 必须使用测试 OCR、测试 JWT 和测试第三方凭证。
- 本部署不执行 prod v1.0 D1 数据迁移或 v1.1 prod Hyperdrive 切换。

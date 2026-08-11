# AGENTS.md

本文件适用于整个仓库。所有 Agent 默认使用简体中文沟通。

## 工作原则

- 先读后写：修改前阅读目标文件、直接调用方、相关配置和已有测试。
- 先明确假设：存在会改变实现或删除范围的歧义时，先停止并询问。
- 保持简单：只实现当前需求，不增加猜测性功能或一次性抽象。
- 外科手术式修改：不顺手重构、格式化或清理无关代码。
- 遵循既有规范：仓库内部的一致性优先于个人偏好；若既有规范存在实质风险，应明确说明，不得暗中引入另一套范式。
- 显式暴露冲突：代码、配置和文档不一致时，以当前可执行代码和已验证配置为证据，说明选择，不静默融合。
- 显式失败：不得把跳过的检查写成通过；必须列出未运行项及原因。
- 目标驱动：开始前定义验收条件，重要步骤后总结完成项、验证结果和剩余工作。
- 模型仅用于判断类任务：适合分类、起草、摘要和信息提取；路由、重试、数据转换等确定性任务应使用常规代码完成。
- 必须注意docs文件夹下文档,和此文档的实时更新

## 仓库结构

这是 TypeScript/Node 与 Dart/Flutter 并行的 monorepo：

- `apps/admin-web`：React、Vite、TypeScript、Ant Design 管理后台。
- `apps/marketing-web`：Cloudflare Workers 营销与法律页面。
- `apps/workers-api`：Hono、Drizzle、Cloudflare Workers、D1/KV/R2 API。
- `apps/flutter-app`：Flutter 客户端，使用 Riverpod 与 GoRouter。
- `packages/auth-core`：共享认证与密码学能力。
- `packages/api-client`、`packages/ui-kit`、`packages/workers-common`：TypeScript 共享包。

Node workspace 由 `pnpm-workspace.yaml` 管理；Dart workspace 由根 `pubspec.yaml` 管理。当前 Dart workspace 仅正式包含 `apps/flutter-app`，不要把未跟踪目录当作工作区成员。

### 项目架构

```text
Flutter App ───────────────┐
                          ├─> Cloudflare Workers API (`/api/v1`)
React Admin ── Worker ─────┘          ├─> D1：卡牌、账号、资产与运营数据
                                     ├─> KV：目录与汇率缓存
                                     ├─> R2：扫描图片
                                     └─> OAuth、邮件、OCR、汇率等外部服务

Marketing Web ──> 独立的营销与法律页面
```

- Flutter App 只通过 Workers API 访问服务端数据，不直接连接 D1、KV 或 R2。
- Admin 是独立 React SPA，但构建产物由 Workers assets 托管，与对应环境的 API 一起部署。
- Workers 是鉴权、账号归属、资产隔离、卡牌查询、扫描识别和 Admin 操作的服务端边界。
- D1 保存业务真源；KV 只保存可重建缓存；R2 保存扫描图片等对象。
- `packages/*` 只承载跨应用共享能力，应用之间通过包依赖或 HTTP 契约协作。

## 工具链与常用命令

- Node `>=22`，pnpm `11.9.0`，Dart SDK `^3.9.2`。
- 安装 Node 依赖：`pnpm install --frozen-lockfile`
- TypeScript 全仓构建：`pnpm build`
- TypeScript 类型检查：`pnpm type-check`
- 依赖方向检查：`pnpm lint`
- Workers 测试：`pnpm --filter @kando/workers-api test`
- Admin 测试：`pnpm --filter @kando/admin-web test`
- Flutter 依赖：`flutter pub get`
- Dart/Flutter 分析：`dart run melos run analyze`
- Dart/Flutter 测试：`dart run melos run test`

GitLab Flutter CI 使用 3.35.5，GitHub iOS CI 使用 3.44.7。涉及工具链或 iOS 构建时以目标流水线为准；需要统一版本时，明确选择并同步修改所有约束。

## 架构约束

- `apps/` 可以依赖 `packages/`，`packages/` 不得反向依赖 `apps/`；`pnpm lint` 强制检查此规则。
- Workers API 入口是 `apps/workers-api/src/index.ts`，业务路由统一挂载在 `/api/v1`。
- Admin 构建产物由 Workers 的 assets 配置托管，不是独立部署目标。
- D1 schema、迁移和 Wrangler binding 是产品与基础设施契约。修改前必须读取相关实现和文档，并先向用户说明影响。
- 服务端授权、账号归属、资产隔离和购买权益必须由可信服务端数据验证，不能信任客户端自报状态。

## 文档真源

根 `README.md` 仍是 GitLab 模板，不作为实现依据。项目文档按发布版本归档：

- `docs/releases/v1.0.0/00-product`：11 份原始 PRD，只读保留。
- `docs/releases/v1.0.0/01-flows` 至 `04-admin`：v1.0.0 实际业务与工程基线。
- `docs/releases/v1.1.0`：相对 v1.0.0 的增量需求、契约变化与发布文档。

`docs/releases/v1.0.0` 是已发布冻结基线，后续 v1.1.0 开发不得回写；若需修正已经确认的文档错误，必须先说明原因并获得用户明确授权。11 份原始 PRD 包括 `glossary.md`、`overview.md`、`ui-design-system.md` 和 `00-product/modules/` 下的 8 份模块文档，必须保持字节不变，不得因当前实现或后续需求而修订。

实现文档以对应版本代码、迁移和运行配置为准。v1.1.0 的新增、变更、移除及实现结果只写入 `docs/releases/v1.1.0`；未变化部分引用 v1.0.0。不要新增执行日志、任务状态快照、交接文档、生成截图或原始设计素材到 `docs/`。

Flutter UI 变更前必须阅读 `docs/releases/v1.0.0/00-product/ui-design-system.md`，并优先复用现有组件、颜色、间距和交互模式；若 v1.1.0 有明确增量契约，同时读取该版本文档。

## 安全边界

- 未经明确授权，不执行 Git push、部署、远程数据库迁移、生产写操作或发布。
- 生产环境受保护；必须区分本地验证、dev 部署和 prod 部署。
- 数据库 schema、迁移、D1/KV/R2 binding 变更需先说明兼容性、回滚和环境影响。
- 保留用户已有改动和未跟踪文件；不要清理、覆盖或回退不属于当前任务的内容。
- 禁止使用破坏性 Git 命令，除非用户明确指定并已核对精确目标。

## 验证规则

验证范围应与改动风险匹配：

- 文档或 Agent 规则：检查路径/链接、`git diff --check` 和残留引用；无需强制全仓构建。
- Admin：运行相关测试、`type-check`，需要交付构建时再运行对应 build。
- Workers：运行相关测试和 `type-check`；涉及打包或部署配置时运行 dry-run build。
- Flutter：运行相关测试和 `flutter analyze`；跨包变更使用根 Melos 命令。
- 共享边界、依赖或 CI 变更：运行根 `pnpm lint`、`pnpm type-check` 及受影响构建/测试。

测试必须保护业务意图和回归风险，而不仅断言实现细节。交付时分别报告通过、失败和未运行的检查。

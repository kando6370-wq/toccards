# AGENTS.md

本文件适用于整个仓库。所有 Agent 默认使用简体中文沟通。

## 工作原则

- 注意该项目app开发选择了Flutter而不是Ios或Android原生开发，所以开发要兼容两者,不能实现时，应先停止并询问。
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

Node workspace 由 `pnpm-workspace.yaml` 管理；Dart workspace 由根 `pubspec.yaml` 管理。当前 Dart workspace 正式包含 `apps/flutter-app` 与 `dart-packages/subscription-core`，不要把未跟踪目录当作工作区成员。

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

GitLab Flutter CI 使用 3.44.0，GitHub iOS CI 使用 3.44.7。涉及工具链或 iOS 构建时以目标流水线为准；需要统一版本时，明确选择并同步修改所有约束。

## 架构约束

- `apps/` 可以依赖 `packages/`，`packages/` 不得反向依赖 `apps/`；`pnpm lint` 强制检查此规则。
- Workers API 入口是 `apps/workers-api/src/index.ts`，业务路由统一挂载在 `/api/v1`。
- Admin 构建产物由 Workers 的 assets 配置托管，不是独立部署目标。
- D1 schema、迁移和 Wrangler binding 是产品与基础设施契约。修改前必须读取相关实现和文档，并先向用户说明影响。
- 服务端授权、账号归属、资产隔离和购买权益必须由可信服务端数据验证，不能信任客户端自报状态。

## 文档真源

根 `README.md` 是项目入口，详细实现文档按发布版本归档：

- `docs/releases/v1.0.0/00-product`：11 份原始 PRD，只读保留。
- `docs/releases/v1.0.0/01-flows` 至 `04-admin`：v1.0.0 实际业务与工程基线。
- `docs/releases/v1.1.0/00-product`：三份 v1.1 原始产品输入，只读保留。
- `docs/releases/v1.1.0/01-flows` 至 `05-delivery`：相对 v1.0.0 的当前业务、架构、数据/API、Admin 和交付文档。

`docs/releases/v1.0.0` 是已发布冻结基线，后续 v1.1.0 开发不得回写；若需修正已经确认的文档错误，必须先说明原因并获得用户明确授权。11 份原始 PRD 包括 `glossary.md`、`overview.md`、`ui-design-system.md` 和 `00-product/modules/` 下的 8 份模块文档，必须保持字节不变，不得因当前实现或后续需求而修订。

实现文档以对应版本代码、迁移和运行配置为准。v1.1.0 的新增、变更、移除及实现结果只写入 `docs/releases/v1.1.0/01-flows` 至 `05-delivery`；未变化部分引用 v1.0.0。不要新增执行日志、任务状态快照、交接文档、生成截图或原始设计素材到 `docs/`。

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

<!-- AI-HARNESS:BEGIN file=AGENTS.md version=1.0.0 sha256=cadaf1e9e3ca1a2ff6ab2b554235c33364a74afaf1f042c07ac71857c770a796 -->
# AI Harness Runtime 托管契约

> 语言：默认使用简体中文
> 详细策略：`.ai-harness/policies/`

本区块只管理跨项目开发流程和安全门禁。区块外的项目业务、技术栈和代码规范继续有效；发现冲突时必须明确列出冲突来源和选择依据，禁止静默折中。

## 强制启动协议

除单一事实查询和不改变行为的单文件机械修改外，所有工作必须：

1. 运行 `node .ai-harness/bin/harness.mjs doctor --json`。
2. 选择唯一主类型：`NEW_PROJECT`、`ITERATION`、`BUGFIX` 或 `ANALYSIS`。
3. 根据业务选择 `database`、`frontend`、`mobile`、`api`、`multi-agent` 标志。
4. 运行 `policies --type <TYPE> [--flag <FLAG>] --json` 并完整读取返回策略。
5. 使用 `start` 创建工作项；状态、计划、任务、证据和 Review 只能通过 Runtime CLI 更新，禁止直接编辑控制面 JSON/JSONL。

## 开发门禁

- 开发型工作依次经过基线、技术设计、数据库判断/设计、批准计划、实施、验证、Code Review 和验收；禁止跳过状态。
- 正式编码和执行计划前必须完成数据库影响判断；影响为 `required` 时必须先完成字段、查询、索引、事务和迁移设计。
- `NEW_PROJECT` 必须记录架构来源与批准；`BUGFIX` 必须记录实际行为、期望行为和复现路径。
- 计划必须包含依赖、写入范围、验证、文档影响、风险、所有者和 Review Batch。计划批准后连续执行所有可执行任务，不逐项询问。
- 阻塞任务记录原因；其依赖任务不得解锁，其他独立任务继续。
- 每个任务验证通过后才能进入 Review，Review 通过后才能完成。BUG 修改或返工后必须重新验证和 Review。
- 高风险批次需要不同上下文或人类独立复核；不可用时不得伪称完成。
- 行为、Schema、API、配置、架构、部署或运维变化必须同任务更新文档。

## 分析、命令与证据

- 业务实现或技术方案询问使用 `ANALYSIS`，以当前检出代码、Schema、配置和测试为证据；事实、推断、建议和未知必须分开。
- 构建和测试优先通过 `harness.mjs run` 执行。`ask` 和 `deny` 命令不会执行；不得改用嵌套 shell 绕过。
- 删除、覆盖、Git 历史修改、部署、发布、生产数据、费用、外部消息和凭据变更需要明确授权。
- 失败、跳过、超时和未运行必须显式记录。没有原始证据不得宣称测试通过或功能完成。
- 最终声明前运行 `node .ai-harness/bin/harness.mjs check --ci --json`；只有相应工作项为 `DONE`/`ANSWERED` 且退出码为 0 才能宣称完成。

## 真实边界

Runtime 能强制自身状态、允许命令、证据和 CI，但不能拦截 AI 客户端绕过 CLI 的专有工具。客户端权限/沙箱、Runtime CLI 和合并前 CI 必须共同生效。
<!-- AI-HARNESS:END file=AGENTS.md -->

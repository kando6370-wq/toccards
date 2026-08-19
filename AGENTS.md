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
- `apps/workers-api`：Hono、Cloudflare Workers、PlanetScale PostgreSQL/Hyperdrive、KV/R2 API 与 PostgreSQL migrations。
- `apps/flutter-app`：Flutter 客户端，使用 Riverpod 与 GoRouter。
- `packages/auth-core`：共享认证与密码学能力。
- `packages/api-client`、`packages/ui-kit`、`packages/workers-common`：TypeScript 共享包。

Node workspace 由 `pnpm-workspace.yaml` 管理；Dart workspace 由根 `pubspec.yaml` 管理。当前 Dart workspace 正式包含 `apps/flutter-app` 与 `dart-packages/subscription-core`，不要把未跟踪目录当作工作区成员。

### 项目架构

```text
Flutter App ───────────────┐
                          ├─> Cloudflare Workers API (`/api/v1`)
React Admin ── Worker ─────┘          ├─> PlanetScale PostgreSQL（经 Hyperdrive）：业务与目录真源
                                     ├─> KV：目录与汇率缓存
                                     ├─> R2：扫描图片
                                     └─> OAuth、邮件、OCR、汇率等外部服务

Marketing Web ──> 独立的营销与法律页面
```

- Flutter App 只通过 Workers API 访问服务端数据，不直接连接 PostgreSQL、KV 或 R2。
- Admin 是独立 React SPA，但构建产物由 Workers assets 托管，与对应环境的 API 一起部署。
- Workers 是鉴权、账号归属、资产隔离、卡牌查询、扫描识别和 Admin 操作的服务端边界。
- PlanetScale PostgreSQL 是唯一业务与目录真源，dev/prod 通过同一 Hyperdrive 指向同一个数据库；`APP_ENVIRONMENT`、Apple 配置、KV、R2、域名和 secrets 仍按环境隔离。
- D1 到 PostgreSQL 的迁移已经完成。后续开发不得新增或恢复 D1 binding、schema、migration、类型依赖、测试基座、读写路径、数据补全、回退或灾备方案；既有历史记录只作为只读审计证据，不得继续维护、执行或作为新实现依据。仓库中仍存在的 `D1Database` 兼容类型、Miniflare 测试和退役迁移工具属于待清理债务，只能在明确授权的清理任务中收敛，任何新功能或 BUG 修复不得复制、扩展或继续维护。`docs/releases/v1.0.0` 冻结内容仍按文档规则原样保留。
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
- PostgreSQL schema/migration 与 Hyperdrive binding 是数据库产品和基础设施契约；新增 schema 变更只允许写入 `apps/workers-api/src/db/postgres/migrations/`。修改前必须读取相关实现和文档，并先向用户说明影响。
- 服务端授权、账号归属、资产隔离和购买权益必须由可信服务端数据验证，不能信任客户端自报状态。
- 后续app所有轻提示框不在使用底部提示框，使用项目组件中的顶部提示框组件；项目组件中有不同类型的顶部提示组件，使用时需区分使用类型。

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
- 数据库 schema、PostgreSQL migration、Hyperdrive/KV/R2 binding 变更需先说明兼容性、回滚和环境影响。
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

## BUG 修复

本节是所有 `BUGFIX` 的修改硬规则；简单 BUG 可以使用轻量记录，但不得跳过定位、验证和 Code Review 门禁。

#### 定位阶段

- **复现优先**：修复前必须先确认实际行为、期望行为和稳定复现路径，记录环境、版本、输入、触发条件、频率及适用的日志/堆栈。无法复现且证据不足的 BUG 不得凭猜测直接修改；只能继续收集证据、增加不改变业务行为的诊断，或将任务标记为 `BLOCKED`。
- **读上下文**：定位到目标代码后，必须阅读目标文件完整相关部分、导出接口、直接调用方、公共工具、相关配置、数据/接口契约和已有测试，理解代码为何这样设计后才能修改。
- **查关联**：确认问题是否影响其他模块、调用入口、平台/版本、缓存/并发、数据一致性、权限、安全或已有测试，列出可能受影响范围和明确不受影响范围；不得把第一次发现的异常位置直接当作完整影响面。
- **证实根因**：使用失败测试、最小复现、日志、堆栈、调试、二分或代码路径建立根因证据；相关性、时间先后或“修改后不报错”都不等于根因。
- **先失败证据**：优先在修改前建立能暴露问题的回归测试或可重复最小复现，并确认其在修复前失败。无法获得失败测试时必须记录原因和等价证据，禁止省略后假称已验证修复意图。

#### 修复阶段

- **最小修改**：只修复当前 BUG，不顺手重构、不扩展功能、不改变未批准行为、不引入当前修复不需要的新抽象。
- **外科手术式**：修改范围严格限定在 BUG 根因及直接关联代码；不碰无关逻辑、格式、依赖、生成物和元数据。必须修改共享代码时，说明为什么局部修复不足以及受影响调用方。
- **针对根因**：修复必须恢复既定预期行为，不得只绕开复现输入、针对单个样例硬编码、扩大重试或用默认值遮住根因。
- **不掩盖问题**：禁止通过注释/删除检查、跳过或放宽断言、吞异常、屏蔽日志、禁用测试、无条件返回成功等方式让 BUG “看起来”通过。
- **保持契约**：接口、数据口径、错误语义、权限、兼容性和平台行为默认保持不变。若修复必须改变其中任一项，必须停止并转为 `ITERATION` 或请求有权人员确认，不能以 BUG 名义绕过范围控制。

#### 验证阶段

- **回归验证**：修复后必须使用修复前相同的环境、输入和触发条件重新执行原始复现路径，确认实际行为恢复为预期；只运行新测试或只观察“不再报错”不等于原问题已解决。
- **回归测试**：修复前失败的测试必须在修复后通过；新增/修改测试必须表达该 BUG 所破坏的业务意图，并证明删除修复或恢复错误逻辑时会失败。
- **影响面验证**：按定位阶段列出的范围验证直接调用方、相关模块、相邻分支、边界条件、受影响平台/版本和已有测试，确认修改没有引入回归。
- **最窄到扩展**：先运行最小复现和针对性测试，再按影响范围运行格式/静态/类型检查、单元、集成、端到端、构建或平台验证；验证规模与风险相称，不能用一个窄测试替代已识别的跨模块风险。
- **显式记录**：实际执行的命令、环境、退出状态和关键结果必须记录。因设备、账号、权限、外部服务或其他条件未执行的验证，必须逐项列出未运行项、原因、影响和需要谁补验，禁止标记为通过。
- **强制 Code Review**：每次完成 BUG 修复代码或审查返工修改后必须执行 Code Review。审查未通过或审查后代码再次变化时，必须重新运行受影响验证并重新审查；未审查不得标记 `COMPLETED`。

#### 文档与记录

- 修复导致接口、配置、行为、Schema、架构、部署、运维或用户操作方式变化时，必须在同一任务中更新 `docs` 下相关文档或项目既有等价位置；不得等全部编码结束后补写。
- 每个 BUG 必须在 Issue、任务系统、提交说明或 `docs/work-items/<WORK-ID>/`/当前版本 `VERIFICATION.md` 中记录根因、证据、修复方式、影响范围、验证结果、Code Review 结论和未验证项，保证后续可追溯。
- 文档影响不存在时必须记录 `N/A` 及理由，不得为了满足流程创建无业务价值的重复文档。简单 BUG 若已由 Issue、提交和回归测试完整追踪，不强制新建独立工作项目录。
- 文档只描述实际修复后的当前行为，不得把猜测根因、未执行验证或计划中的后续改进写成已确认事实。

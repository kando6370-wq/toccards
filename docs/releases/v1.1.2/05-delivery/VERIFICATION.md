# v1.1.2 实际验证记录

本文件只记录本版本实际执行的验证，历史记录见 [v1.1.1](../../v1.1.1/05-delivery/VERIFICATION.md)。未运行或只有部分源码证据的事项不得标记为完整兼容通过。

## 2026-10-09：App 兼容首批源码合同自动化

### 范围与环境

- 用户要求处理遗留 App 兼容问题。本轮将 v1.1.1 的兼容设计落地为首批本地可执行回归，不调整业务功能、版本门禁、服务端协议、数据库 Schema、生产配置或支持窗口；未证明旧 App 普遍不可用，也没有将测试工具自身问题包装为生产 BUG。
- 分支 `codex/v1.1.2-dev`、提交基线 `d0ac970`，初始工作区干净。旧客户端 API/DTO 在 `v1.0.4..HEAD` 中没有变化，但仍从固定提交导出旧源码执行，不依赖当前文件恰好相同。
- Windows/PowerShell、Node 22.20.0、pnpm 11.9.0、Flutter 3.44.7/Dart 3.12.2、PGlite 0.5.7；本轮只读取本机源码与依赖。Flutter 使用已有依赖、`--no-pub` 和 `--no-test-assets`，测试本身不涉及 UI/资源/原生插件，不把这些未覆盖层级算作通过。
- 4 项当前 API 合同产出 20 份实际 Hono 响应；分别供 1.0.4 (161)、1.0.5 (163) 的原始 Dart API 客户端解析并核对请求语义。每组 13 项，其中包含冻结包来源门禁、可选字段新增兼容性和三个故意破坏响应的反例。完整矩阵的已覆盖/待验范围见 [兼容回归说明](../03-data-api/app-compatibility.md)。

### 执行过程中的失败与修正

- 首次 API 夹具仅加载 0000，缺少现有 `0006_mutation_lock.sql`，文件夹与预约写入失败；在测试内补载已有迁移后通过，没有创建或修改 migration、连接远程库。首次“新建文件夹默认=true”断言与既有 SQL 固定为 0 的行为不符，按当前代码和旧合同改为 false；未改业务来满足错误测试前提。
- Windows Flutter 启动先因 cmd 引号和短命令路径的 SDK 定位失败；改为解析现有 flutter.bat 绝对路径并正确传参，没有重新安装 SDK、清理工程或更改环境配置。
- 旧包映射首轮与 Flutter 当前工程目录不一致触发 native-assets 查找错误，随后又发现缺少已解析的 package_graph；将执行目录放到独立源码快照，并在新目录复制本机现有依赖 metadata 后通过，未禁用原生资产功能或改动原工作区映射。
- 使用 Isolate.resolvePackageUri 验证来源在 Flutter tester 中不受支持；改为冻结包独有的编译 marker 和包装入口，当前包回退会直接编译失败，而非删除来源门禁。标记文件仅生成在新快照目录，不修改固定提交导出的任何已有源码文件。
- 初轮全仓类型检查发现新增测试 Env 缺 CACHE_KV；补上会显式拒绝使用的本地 fixture 后通过。Flutter analyze 初轮发现两处缺少花括号；仅修正新增测试代码，未压制 lint。

### 证据层级与剩余工作

- 当前结果只覆盖 C01、C02、C04、C06、C09、C13 的部分源码场景；价格/估值、Collection/Wishlist、完整扫描、购买/恢复、登录刷新和正式制品/真机等仍未闭合。两组源码使用当前 SDK/第三方依赖，不是原历史二进制验收。
- 数据只写本地 PGlite 内存库，无 dev/prod 连接、生产 Key、真实账号、图像上传、交易或远程迁移；没有 Git commit/push、部署、版本号/标签变化。既有 v1.0.0/v1.1.0/v1.1.1 文档保留不回写。
- 后续完整兼容验收需要发布负责人提供旧包及测试账号/设备，并确认 Android 实际分发基线；生产写入/购买/发布另需授权。尚未将新命令接入远端 CI 或自动部署流程。

### 最终结果与 Code Review

| 检查 | 退出状态与结果 |
|---|---|
| `pnpm test:app-compatibility` | 0；当前 API 4/4、20 份真实测试响应；旧 1.0.4 与 1.0.5 分别 13/13，无跳过 |
| `node --test scripts/check-app-compatibility.test.mjs` | 0；注册表/证据层级和固定版本校验 2/2 |
| 故意使用当前工作区 package_config 运行冻结包装入口 | 1（预期失败）；缺少仅在冻结包生成的 marker 导致编译失败，证明不会静默回退最新客户端 |
| `pnpm --filter @kando/workers-api test src/compatibility src/app-config/version-control.integration.test.ts src/request-id.test.ts src/portfolio/folders.test.ts --maxWorkers=2 --reporter=dot` | 0；4 文件、44 项通过 |
| `pnpm lint`、`pnpm type-check` | 0；依赖方向通过，类型检查 7/7，其中 6 项缓存命中，Workers 本轮执行 |
| `flutter analyze --no-pub tool/compatibility` | 0；No issues found；仅新增测试工具范围，未冒充全仓 Flutter 分析 |

最终兼容运行证据位于本地 `.dart_tool/app-compatibility/run-2NJwKQ/`，两组 baseline 的 report 状态均为 passed；错包映射反证保留在 `run-oGViZI/wrong-package-negative.log`。未运行全仓 Workers/Flutter 测试、产品构建、iOS/Android 真机或远端环境验证；POSIX 主机上的编排分支本轮未实测，当前只验证 Windows 主机命令。

本地 Code Review（非外部独立评审）已完成：检查固定提交/营销版本/构建号、旧包映射与编译标记、失败即停且无替代响应、当前 API 实跑与旧端请求匹配、owner/幂等/额度与错误断言、负例和可选字段兼容、只写新测试目录及拒绝覆盖样本。没有用修改业务逻辑、跳过检查或放宽解析器掩盖测试问题；测试代码最后一轮调整后已重新执行上述回归与静态检查。

## 2026-10-12：App 兼容 CI 定义与独立冷检出验证

### 目标、范围与工作流

- 用户要求按下一步建议执行，先将已有源码兼容入口接入 CI。新增 `.github/workflows/app-compatibility.yml`，固定 job 名称 `App compatibility (Windows)`，Windows 2022 / Node 22 / pnpm 11.9.0 / Flutter 3.44.7。PR 目标 dev/main 不设路径过滤，同时响应 dev/main/codex/** push，并提供手工入口。
- 完整获取 Git 历史和标签；冻结安装 Node/Dart 依赖，构建 auth-core，再运行基线守卫测试及原 `pnpm test:app-compatibility`。没有修改运行代码、原兼容脚本/样本断言、锁文件、历史文档或已有 iOS/Linux 发布工作流。
- Token 只给 contents:read，checkout 不保留凭据，不使用业务环境 Secret，不调用部署/迁移。Tee 保存日志后显式传递原生命令退出码，没有 continue-on-error；always 上传仅列出的 ci.log/report.json/server-responses.json，允许选定的隐藏目录，保留 7 天，不上传源码快照或依赖缓存。

### 干净依赖和执行环境

- 在主工作区的忽略目录 `.dart_tool/compatibility-ci/run-izGTf3/` 内，用 `git clone --no-local --no-checkout` 建立独立 Git 检出并定位到 `46ed5c918976334a0b039ac46c66692a2c5cd4f9`；复制的候选工作流是唯一未跟踪源文件。开始时没有 node_modules、Dart 解析目录或 auth-core dist，不改动原工作区和其他 worktree。
- Node 依赖使用新建的专用 pnpm store，Dart 使用新建的专用 PUB_CACHE；分别执行 `pnpm install --frozen-lockfile --store-dir <本次隔离 store>` 与 `flutter pub get --enforce-lockfile`，均退出 0。前后 pnpm-lock.yaml/pubspec.lock 没有变化。
- 使用本机现有 Node 22.20.0、pnpm 11.9.0、Flutter 3.44.7/Dart 3.12.2；这是依赖/检出状态隔离的本地 Windows 验证，不是 GitHub windows-2022 镜像或 setup action 的托管执行。Corepack/Node/Flutter 的 GitHub 安装动作、artifact 上传动作尚未在 GitHub 实跑。
- 从 YAML 解析提取原始 run 步骤，在独立检出目录用 pwsh 执行 auth-core build、脚本守卫测试和含 Tee/exit 判断的兼容测试步骤；未把它替换成一个忽略退出码的简化命令。

### 实际结果与失败反证

| 检查 | 退出状态与实际结果 |
|---|---|
| YAML 解析及关键配置断言 | 0；PR 分支/无路径过滤、完整标签、只读权限、步骤顺序、原生失败传递、always 和有限产物路径均符合预期；不是 GitHub 服务端 schema/执行验收 |
| 新目录安装 Node/Dart 依赖 | 0 / 0；使用新 store/cache，锁文件未变 |
| `pnpm --filter @kando/auth-core build` | 0；从无 dist 开始生成依赖构建 |
| `node --test scripts/check-app-compatibility.test.mjs` | 0；2/2 通过 |
| 工作流原始兼容测试步骤（首次冷检出） | 0；API 4/4，旧 1.0.4 与 1.0.5 各 13/13，无跳过 |
| 故意破坏隔离副本的文件夹响应 | 1（预期失败）；仅将 folderResponse 的 sort_order 数字转成字符串。API 4 项仍通过，但旧 1.0.4 的文件夹读取和可选字段兼容两项失败，Dart _requiredInt/PortfolioFolderDto.fromJson 报错；runner report.status=failed，同一 pwsh CI 步骤退出 1，没有被 Tee 掩盖 |
| 还原后重跑同一工作流测试步骤 | 0；源文件字节恢复原样，API 4/4、两组各 13/13 再次通过 |
| 独立检出目录的 `pnpm lint` / `pnpm type-check` | 0 / 0；4 个共享包依赖方向通过，类型检查 7/7，本轮 0 项缓存命中 |

故意破坏只发生在本次新建的隔离副本，最终已按原字节恢复并通过 Git diff 断言；主工作区业务文件没有被修改。首次正例、负例、还原复验、安装和静态检查日志及工作流步骤摘录均保留在上述忽略目录，不纳入正式 docs/Git。

### 审查、远端状态与未完成项

- 已进行本地自审：保持既有 action 主版本风格和 GitHub Flutter 约束；检查 PR 不会因路径过滤缺席、固定标签完整、auth-core 在测试前构建、失败非零退出不会被日志收集变绿、上传范围不含冻结源码/缓存，以及本地冷检出与托管执行的区别。无运行代码修复，不创建新的业务 BUG 或迁移。
- 2026-10-12 首次只读 GitHub Git 分支查询连接失败（无法连接 github.com:443）；后续再次只读查询成功，远端当前开发分支仍为 `46ed5c9`。没有把连接恢复或分支回读记为 CI 结果。npm/pub 依赖源可访问，本地验证据此完成。本轮尚未提交/推送工作流，也没有创建 PR、触发远端 workflow 或修改分支规则。
- **待完成**：获得 Git 提交/推送授权后，在当前开发分支首次运行该工作流；核验真正的 GitHub check 和报告。之后才能配置 main/dev 的必需状态检查，确认失败 PR 实际被阻止合并。当前只证明本地相同测试命令会失败，不宣称仓库合并保护已经生效。
- 本轮未重跑所有 Workers/Flutter 业务测试、产品构建、正式旧包/真机或远端环境；原 C01–C13 尚未覆盖的业务与制品验收缺口继续保留。下一阶段资产/价格合同扩展尚未开始，不因本次 CI 定义完成而关闭。

收尾文档检查：当前变更仅新工作流及 4 份相关文档/Agent 规则，27 处本地链接目标有效，`git diff --check` 通过；既有验证记录前缀、运行源码、兼容测试脚本、锁文件、旧工作流和 v1.0.0/v1.1.0/v1.1.1 归档均未改动。

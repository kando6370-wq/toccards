# v1.1.2 实际验证记录

本文件只记录本版本实际执行的验证，历史记录见 [v1.1.1](../../v1.1.1/05-delivery/VERIFICATION.md)。未运行或只有部分源码证据的事项不得标记为完整兼容通过。

## 2026-10-13：Google Sitemap 最小隔离实验

### 根因证据与实验边界

- GSC 的 `/sitemap.xml` 详情在 2026-10-13 再次显示“网站地图无法读取”、发现页面 0，最后读取日期已更新为 2026-10-13；因此不再把现象归类为 2026-10-10 的旧报表尚未刷新。GSC 普通 URL 检查同时记录 Googlebot 智能手机在 2026-10-12 10:21:51 已抓取该 URL，允许抓取且页面加载成功。
- 2026-10-13 17:43:07 的 GSC 实时 URL 测试返回“网址可供 Google 使用”，允许抓取、页面加载和允许索引均为“是”。同日人工处置措施和安全问题均显示未检测到问题。
- 公开端精确 URL 与 Googlebot UA 均返回 HTTP 200、`application/xml`、2719 字节和相同 SHA-256；XML 可解析且包含 25 个 URL，robots.txt 允许抓取并只声明正式 sitemap；25 个正式 sitemap 子 URL 用 Googlebot UA 检查均为 200、无重定向。由此确认当前可复现的失败位于 Sitemap 专用识别/处理链路与普通抓取链路之间，而不是已证实的 Cloudflare 拦截、robots、XML 语法或子 URL 故障；没有无请求日志证据地把外部处理分歧写成唯一 Google 根因。
- 用户批准最小隔离实验。新增 `/sitemap-minimal.xml`，只包含 `/`、`/pokemon-card-scanner` 和 `/card-price-checker` 三个绝对 `<loc>`，不含注释、`priority`、`lastmod`、`changefreq` 或扩展命名空间。正式 `/sitemap.xml`、robots.txt、页面、canonical、部署配置和数据库均不改；该测试文件不写入 robots，也不加入正式 sitemap。

### 当前状态与验收边界

- 内容生成完成后，`pnpm --filter @kando/marketing-web test` 退出 0，19/19 通过；新增契约逐字节检查最小文件、三个 URL 和无可选字段边界，同时确认正式 sitemap 与 robots 未引用测试文件。正式 sitemap 和 robots 相对 `origin/main@7db7d63` 无差异。
- `xmllint --noout` 对正式和最小 sitemap 均通过；最小 sitemap 另通过官方 Sitemap 0.9 XSD。`git diff --check` 退出 0。没有运行无影响面的 Workers、Admin、Flutter、App 兼容或数据库测试。
- 本地 Wrangler `http://127.0.0.1:8791/sitemap-minimal.xml` 返回 200、`application/xml`、307 字节，与生成文件 SHA-256 `740090137b8a36b5224cd25467b1ab37dec8c4031955ba73996e23411268f695` 一致；三个目标页面均返回 200 且无重定向。
- 提交前独立 Code Review 核对计划对齐、正式发现信号隔离、生成器确定性、契约测试和文档边界，Critical/Important/Minor 均无问题，结论为 Ready to merge。审查后只补记本条结论，未修改实现或验收断言。
- 截至本地验收检查点，尚未提交、推送、部署或执行 GSC 最终提交；这些步骤必须取得各自实际结果后补证，不能按计划记为完成。
- 生产验收要求 Cloudflare 自动构建成功、线上 `/sitemap-minimal.xml` 返回 200 `application/xml`、内容与已批准生成物逐字节一致，三个 URL 均为 200 且无重定向。GSC 提交是独立外部写操作，必须在点击提交前再次确认；提交成功也只表示实验请求被接受，不代表 Google 已读取、发现页面或索引成功。

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

## 2026-10-12：GitHub push 托管验收与 PR 门禁接入

### 已确认的 push 运行

- 用户要求按下一步建议推进。当前工作区从干净的 `codex/v1.1.2-dev@eee77abc7321a3aa324aa4260ec4d2eabe64b4df` 开始；只读 Git 远端回查确认同名远端分支一致，`dev` 为 `d0ac970`、`main` 为 `7ac984e`。前述“尚未提交/推送”属于早前检查点，不覆盖本次新证据。
- [GitHub Actions run 38192725017](https://github.com/kando6370-wq/toccards/actions/runs/38192725017)，event=push，head=`eee77abc7321a3aa324aa4260ec4d2eabe64b4df`，北京时间 2026-10-12 09:39–09:43，status=completed / conclusion=success。job/check `114628747612` 名称为 `App compatibility (Windows)`，来源为 GitHub Actions（app ID `15368`）。
- 官方 API 回读的每个步骤均为 success，包括 Node/Flutter 安装、锁定依赖、auth-core build、基线守卫、兼容合同以及 artifact 上传；这是托管执行结果，不再只是本地冷检出结果。
- 已下载 artifact `11722272010`（`app-compatibility-38192725017-1`），内含 `ci.log`、`run-yPwUYb/report.json` 和 `server-responses.json`。日志确认 API 4/4、旧 1.0.4 (161) 与 1.0.5 (163) 各 13/13，无跳过。报告为 passed，`serverCommit=eee77abc7321a3aa324aa4260ec4d2eabe64b4df`、`serverWorkingTreeDirty=false`，两组固定基线通过，证据仍为 `git-source-contracts-only`。
- 原始 API 回读和 artifact 保留在本地忽略目录 `.dart_tool/compatibility-gate/20261012/`，不纳入 docs/Git。托管 artifact 保留 7 天，当前到期时间为北京时间 2026-10-19 09:43:22，链接过期后不能把无法下载当作重新验收通过。

### PR、权限与合并门禁

- 已创建 [Draft PR #3](https://github.com/kando6370-wq/toccards/pull/3)，`codex/v1.1.2-dev` → `dev`；创建时 head=`eee77ab`、base=`d0ac970`。该 PR 交付远端已有源码合同与 CI 增量；本轮三份文档补证仍是本地修改，尚未进入 PR。
- [PR Actions run 38194094012](https://github.com/kando6370-wq/toccards/actions/runs/38194094012)，event=pull_request，关联 PR #3、head=`eee77ab`，北京时间 2026-10-12 10:00–10:04，completed/success；job/check `114632858918` 的所有步骤均为 success。已下载 artifact `11722134545`（`app-compatibility-38194094012-1`），日志确认 API 4/4、旧 1.0.4 和 1.0.5 各 13/13，无跳过，响应文件包含 20 个 cases。
- PR 的 `run-G4RzmW/report.json` 为 passed、`serverWorkingTreeDirty=false`，两组固定旧源码通过；`serverCommit=f623de578d877e596d8bb3b4468000c1ba37b1ec` 与 PR API 的 `merge_commit_sha` 一致，是 GitHub 合并引用的测试结果，不能写成直接运行 head 或 PR 已合并。
- 使用 Git 已配置的凭据请求仓库权限，API 返回 push=true、admin=false、maintain=false；凭据仅在进程内构造认证请求，未打印或落盘。规则集列表返回 200/空数组；经典 `main`/`dev` 分支保护详情返回 404。无管理员权限且保护配置不可确认，本轮未尝试写规则，也没有把 404 解释为必需检查必然不存在。
- 待仓库管理员保留既有保护规则，在 `main`/`dev` 要求 GitHub Actions 的 `App compatibility (Windows)`，随后回读生效配置并用隔离失败 PR 验证阻断。当前 Draft PR 的不可合并不构成必需检查生效证据；因权限前置条件未满足，本轮未创建故意失败的远端 PR，未把本地失败反证等同于远端阻断。
- Code Review 连接器返回需要登录 ChatGPT 才能连接 GitHub；本轮继续使用 GitHub 官方 REST API 核查 CI，不将 API 状态回读算作独立 Code Review。

### 警告与验证边界

- 该 push run 仅有一条 warning：`actions/checkout@v4`、`actions/setup-node@v4`、`actions/upload-artifact@v4` 面向 Node.js 20，被运行器强制以 Node.js 24 执行。实际步骤全部成功，本轮不升级 action；action 的内部运行时与应用测试使用的 Node 22 是不同层级。
- PR 同时启动既有 [iOS build run 38194094128](https://github.com/kando6370-wq/toccards/actions/runs/38194094128)，北京时间 2026-10-12 10:10 回查 job `114632858896` 为 completed/success，所有步骤成功，包含 CocoaPods、锁文件检查和 unsigned release build；这是无签名编译通过，不代表签名包、TestFlight 或真机验收，也不覆盖下述独立营销站失败。
- 既有 head 检查 `114628996073`（`Workers Builds: toccards-website`）在北京时间 09:40 已失败，早于本轮 PR 创建；它与 App compatibility 分属不同检查。使用既有 Wrangler 登录只读查询该 Cloudflare build `eaa9adab-070a-4359-b002-1ac64c6f4ac3` 返回 HTTP 403 / code 12004 Forbidden，因此没有获得根因、分支触发条件或 deploy command，也不据此断言已部署或绝不会部署生产。后续 push 的营销站影响尚未确认，本轮文档不提交/推送，未修改/绕过该集成。
- 本轮文件改动仅为 v1.1.2 的三份文档补证；业务代码、兼容断言、工作流、锁文件、版本与历史归档不变。本地文档自审核对了 run/commit/事件、artifact 与权限证据，保留本地验证、push、PR 合并引用及必需检查的区别；没有新增业务修复，未进行独立代码评审。
- 文档检查：`git diff --check` 退出 0；25 处本地链接目标有效；原 VERIFICATION 内容按 Git 规范化行尾逐字节前缀对照未变，修改路径严格限于本版本三份文档。
- 没有 Git commit/push、合并 PR、手工部署、迁移或生产业务写入；创建 PR 仅启动上述 GitHub 测试/编译，未调用发布工作流。完整 C01–C13、C03/C12/C13 后续合同扩展、正式旧包/真机、Android 分发基线与生产插件专项仍按原记录待验；本轮没有重新运行本地全仓业务测试或产品构建。

## 2026-10-12 10:39：管理员授权与必需检查规则生效

- 用户完成 Git Credential Manager 的设备授权后，指定仓库所有者账号认证。设备授权命令退出 0，GitHub 身份回读符合目标账号，仓库权限为 admin=true / maintain=true / push=true；凭据仅在请求进程内使用，未打印、写入证据文件或修改 Git 作者配置。
- 管理员写入前回读：规则集列表为 200/空数组，经典 `main`/`dev` 分支保护均为 404 / Branch not protected。此前低权限账号的 404 只代表当时无法确认，本条是本次管理员身份取得的新证据，不回写前述历史结论。
- 已创建 [规则集 24904725](https://github.com/kando6370-wq/toccards/rules/24904725)，API 返回 201。名称 `App compatibility required checks`，target=branch、enforcement=active，只匹配 `refs/heads/main` 和 `refs/heads/dev`；唯一规则为 required_status_checks，要求 `App compatibility (Windows)`，integration_id=15368（GitHub Actions），bypass_actors 为空。
- 配置保留最小范围：`strict_required_status_checks_policy=false`，不另外要求每次合并前同步 base；`do_not_enforce_on_create=false`。没有新增审批人数、部署要求或其他规则，未覆盖已有保护配置（写入前规则集与经典保护均为空）。
- 北京时间 10:39:40 独立回读规则详情与两条分支的有效规则，均确认 active、相同规则 ID/检查名/来源；开发分支 `codex/v1.1.2-dev` 的有效规则仍为空。写入前后 `main=7ac984ecd604b9fc483bf02c1bf0dded37651034`、`dev=d0ac9708754d8c2d835e4a503bed2ad874aa92d3` 均未变；PR #3 保持 open/draft、merged=false。
- 已完成本地配置审查与回读断言：两个精确分支、单一检查、可信来源、无绕过角色、其他分支不受影响、Git refs 不变。原始请求方案及脱敏回读保留在忽略目录 `.dart_tool/compatibility-gate/20261012/admin/`；不把权限凭据保存到文件。
- **尚未执行失败 PR 阻断实测**：需要新增隔离远端提交，而前述 Cloudflare build 详情仍为 403，未确认推送的营销站发布影响；没有为了测试门禁而推送，也没有把 active 配置、成功检查或草稿状态写成失败阻断已验收。待确认发布边界后再补该项。
- 本轮仅新增远端 GitHub 规则集并同步当前三份 v1.1.2 本地文档，继续保留前述历史验收内容；没有 Git commit/push、PR 合并、部署、迁移或业务写入。规则变更未改测试/工作流源码，本轮不重复运行此前已经通过的业务测试和构建。GitHub 管理权限已解决，Cloudflare 查询权限及发布边界仍是独立待办。 文档复验：`git diff --check` 退出 0，25 处本地链接有效，授权前的全部 VERIFICATION 内容按原始字节前缀保留，修改范围仍严格限于三份 v1.1.2 文档。

## 2026-10-12 10:51：Cloudflare Builds 只读权限与发布边界补查

- GitHub 管理员再次读取营销站失败 check `114628996073`：output 只有 Build ID/Cloudflare Dashboard 链接，text=null、annotations_count=0，annotations 为空；GitHub 侧没有该次构建日志或 deploy command，不能据此判断失败根因或非生产分支是否会切流。
- 使用现有 Wrangler OAuth 凭据读取 Workers scripts API，返回 200，确认 `toccards-website` 与其 script tag；再按该 tag 请求 Builds triggers API，返回 HTTP 403、code 10000 / Authentication error。原始脱敏结果保留在 `.dart_tool/compatibility-gate/20261012/admin/cloudflare-trigger-access.json`。本轮只读取元数据，没有调用部署、构建重试或配置修改接口。
- [Cloudflare Builds GET API](https://developers.cloudflare.com/api/resources/workers_builds/subresources/builds/methods/get/) 列出的接受权限为 Workers CI Read/Write；当前已授权的 OAuth scopes 不包含该权限。`wrangler login --scopes-list` 列出的 25 项命名权限中也未提供 CI/Builds scope，没有通过重新登录扩大 Workers、D1 或其他无关资源权限。Workers 元数据可读与 Builds 不可读属于不同权限边界，不把 GitHub admin 授权视为 Cloudflare 授权。
- [Cloudflare Builds 配置说明](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/)区分 production branch、deploy command 与可配置的非生产分支发布命令；默认命令不能证明本项目云端实际配置。本轮仍未取得该 Worker 的生产分支、build command、deploy command、non-production branch deploy command 和 branch include/exclude 配置，需要有权限的维护者提供这页当前值或只读访问，且无需传递密码或 Token 到聊天。
- 未新增远端提交、失败 PR 或文档推送；现有必需检查规则保持不变，失败 PR 阻断仍未验收。仅在本版本追加本次读权限与证据不足的结论，不修改营销站实现、构建集成或历史记录。

## 2026-10-12：Production 设置截图与最小失败用例准备

- 用户提供四张 Cloudflare Dashboard 截图。Production 页显示仓库 `kando6370-wq/toccards`、生产分支 `main`、Disable builds 开关关闭；构建命令显示 None，发布命令为 `pnpm run deploy`，根目录 `/apps/marketing-web`，Include paths 为 `apps/marketing-web/*`。Exclude paths 中灰色文本不能可靠区分占位提示与保存值，不把它记录成已确认排除规则；也未取得 Previews Base 页内容。
- 截图原件及 SHA-256 清单保存在本地忽略目录 `.dart_tool/compatibility-gate/20261012/cloudflare-screenshots/`，没有加入 docs/Git。结论仅限用户提供的当前页面状态，不宣称取得 Cloudflare API 控制面回读或解释历史失败根因。
- [Cloudflare 构建分支说明](https://developers.cloudflare.com/workers/ci-cd/builds/build-branches/)区分生产部署、当前预览部署与 legacy 非生产分支命令；未展示的预览配置不能从生产命令或默认值推断。历史 `eee77ab` 仅改 CI/文档，却有营销站失败 check，因此仍需确认 Previews Base，或取得当前配置的等价只读证据；本轮不新增远端提交。
- 为后续远端故障注入准备了一处最小测试补丁：在兼容 API fixture 捕获 `folders-new-write` 后，将该响应首项 `sort_order` 从数字转成字符串；只改变将交给旧客户端的测试样本，不修改业务路由、数据库数据模型或断言，也不把这次人工注入称为生产 BUG。
- 本地负例执行原 `pnpm test:app-compatibility`，退出 1：API 4/4 仍通过，旧 App 1.0.4 在 C04/C13 文件夹读取和可选字段兼容两项失败（11 通过、2 失败），堆栈包含 `_requiredInt` / `PortfolioFolderDto.fromJson`。runner report=failed；按既有失败即停逻辑，负例没有继续运行 1.0.5，不将其记为通过。证据目录 `.dart_tool/app-compatibility/run-3dQiDO/`。
- 用 finally 按原始字节恢复测试源码，再执行同一命令，退出 0：API 4/4，旧 1.0.4 与 1.0.5 各 13/13，无跳过。复验目录 `.dart_tool/app-compatibility/run-vpdHJg/`；两次报告均标记工作区 dirty，因为已有未提交文档，不能写成干净提交构建。临时改动已恢复，源码与操作前逐字节一致。
- 负例补丁、原始测试源码、两次命令日志及退出状态保存在忽略目录 `.dart_tool/compatibility-gate/20261012/probe-ff81d11f/`。本地自审核对了单点注入、旧端真实解析失败、失败非零退出和字节恢复；未创建负例 Git commit/分支、远端 PR、部署或迁移。此处只证明拟用负例有效，不能替代 GitHub 合并阻断实测。

## 2026-10-12：Previews Base 补证与双分支门禁实测

### 发布边界与验收输入

- 用户补充三张 Previews Base 截图，显示 Builds for Preview branches 开启，Preview URLs 禁用但构建继续运行；build command=`pnpm run build`、preview command=`npx wrangler preview`、root directory=`/`、include paths=`*`，无显式构建变量/Secret。排除路径仍显示灰色提示，不判定为已保存规则。截图和 SHA-256 清单保留在忽略目录 `.dart_tool/compatibility-gate/20261012/cloudflare-screenshots/`。
- 预览监听 `*` 与 Production 监听营销站目录是两组配置，能解释非营销站提交也出现构建检查；没有取得旧失败日志，因此不声称确认历史失败根因。按[预览部署说明](https://developers.cloudflare.com/workers/previews/)及当前源码核对，`wrangler preview` 创建预览；根 `turbo build` 仅编译、静态构建和 dry-run 打包，Linux dry-run 在 SSH 前返回，不会调用业务部署。没有修改构建命令、资源绑定、Token、Preview URLs 或生产配置。
- 推送前已只读保存生产快照：main=`7ac984ecd604b9fc483bf02c1bf0dded37651034`，dev=`d0ac9708754d8c2d835e4a503bed2ad874aa92d3`；营销站最新 deployment=`af4eba2d-d4bf-4679-b6a2-253f6160585a`，API 最新 deployment=`317beb8f-ca11-4e7e-8b22-34488f13ec5d`，Admin Pages canonical deployment=`4e41a946-7112-4d07-8881-961b3b128d82`（来源 main 的 7ac984e）。最初直接回读使用的 OAuth access token 返回 401，经既有 Wrangler whoami 自动刷新后成功；未重新申请权限，Builds CI Read 缺口仍保留。
- 建立隔离分支 `codex/compatibility-gate-probe-20261012`，从 eee77ab 生成负例提交 `5cb7c1535cddbe8843fb1e4740d975a9057bdb28`，仅改变测试 fixture 的一行 sort_order 类型。使用独立 Git index 生成提交，当前开发工作区及三份文档未切换/覆盖，未将故意失败代码加入 PR #3。
- 已推送该隔离分支，创建非草稿 [PR #4 → dev](https://github.com/kando6370-wq/toccards/pull/4) 与 [PR #5 → main](https://github.com/kando6370-wq/toccards/pull/5)，标题标明禁止合并。远端负例、恢复复验及生产回读结果见下文，不以已创建 PR 冒充门禁验收通过。

### GitHub 负例与合并资格回读

- 负例 head=`5cb7c1535cddbe8843fb1e4740d975a9057bdb28` 的三个兼容运行均 completed/failure：push run `38199854960`；PR #4 → dev run `38199860315`；PR #5 → main run `38199862129`。下载 artifact 分别为 `11724884112`、`11725215392`、`11724704487`；全部报告为 failed、工作区干净，API 4/4 通过，旧 1.0.4 在文件夹 DTO 的 `_requiredInt` / `PortfolioFolderDto.fromJson` 失败，负例按 runner 约定不继续 1.0.5。
- 逐份报告匹配实际被测试的提交：push=`5cb7c15`，PR #4 merge ref=`949b916badcbd493ed3f680215080f70863bedf8`，PR #5 merge ref=`edaf348c2a69e8b326cececf384dee44a02b52c7`。没有用 GitHub runs API 中“同 SHA 关联到两个 PR”的列表猜测运行目标，而是将报告 serverCommit 与各 PR 的 merge_commit_sha 对照。
- GraphQL 对 PR #4/#5 分别返回 isDraft=false、mergeable=MERGEABLE、mergeStateStatus=BLOCKED；同一 head 上的兼容 check 均来自 GitHub Actions、isRequired=true、conclusion=FAILURE。营销站与 iOS check 均 isRequired=false，排除了草稿、代码冲突或非必需营销站失败充当本次门禁证据的情况。
- 此处验收的是 GitHub 服务端报告的合并资格阻断，未调用实际 merge 接口；没有为了取得拒绝响应而冒险合并故意损坏的提交。没有取消、放宽或跳过任何必需检查。
- artifact 日志带有 ANSI 颜色控制码，首次数量提取断言被其打断；确认原始日志仍为 API 4/4 后，仅对副本使用 Node 标准 stripVTControlCharacters，再运行同一数量断言通过；原始 ZIP/日志未改，测试和 CI 没有重写以适配解析器。
- 负例回读保存在忽略目录 `.dart_tool/compatibility-gate/20261012/remote-execution/negative-proof.json` 及三个 artifact ZIP。

### 恢复提交

- 已在同一隔离分支以正常快进推送恢复提交 `3b26ed524435fd74d5c85f0b8fecabe2c10adc18`，其完整 Git tree 与 `eee77ab` 相同，保留负例提交用于审计。恢复后的实际检查及合并资格结果如下。

- 恢复 head=`3b26ed524435fd74d5c85f0b8fecabe2c10adc18` 的三个兼容运行全部 completed/success；逐份下载报告均为 passed、干净工作区，API 4/4、旧 1.0.4 和 1.0.5 各 13/13，无跳过：

| 事件/目标 | GitHub run | Artifact | 实际测试提交 |
|---|---|---|---|
| push | [38200396462](https://github.com/kando6370-wq/toccards/actions/runs/38200396462) | 11724254957 | 3b26ed524435fd74d5c85f0b8fecabe2c10adc18 |
| PR #4 → dev | [38200400198](https://github.com/kando6370-wq/toccards/actions/runs/38200400198) | 11724849946 | 2c98fcaaabd51e38d6f96b36dc8d3ae6123f554e（merge ref） |
| PR #5 → main | [38200400209](https://github.com/kando6370-wq/toccards/actions/runs/38200400209) | 11725266572 | 9fee4cabba53e2fcafec5e969601156bc15053eb（merge ref） |

- GraphQL 确认两条非草稿 PR 的所有必需兼容 check 均 SUCCESS，mergeable=MERGEABLE，mergeStateStatus 从 BLOCKED 变为 UNSTABLE。营销站预览仍为非必需 FAILURE，因此只宣布兼容门禁解除阻断，不称全部检查通过。正例证据保留于忽略目录的 `positive-proof.json` 与三个 artifact ZIP。
- 验收后已关闭 PR #4/#5，API 回读 state=closed、merged=false，head 均为恢复提交；未调用 merge API，未删除审计分支或历史提交。PR #3 保持正式交付草稿，未合入 dev/main。
- 北京时间 11:42:02 回读 main/dev 的完整提交 SHA 与推送前一致；营销站与生产 API 的 deployment 列表（含版本/流量信息）逐项未变，Admin Pages canonical deployment 仍为 `4e41a946-7112-4d07-8881-961b3b128d82`。本轮只有既有非生产分支构建被触发，没有生产切流、人工部署或数据库操作；不会把预览构建失败判作生产发布失败或把其根因写成已查明。
- 正式交付范围仅为三份 v1.1.2 文档补证；既有业务代码、工作流、锁文件、旧版本归档及用户材料均未更改。已检查 25 处本地链接、原有验收内容的字节前缀和变更路径，`git diff --check` 通过；本地自审核对了截图证据与 API 回读、push/head 与 PR merge ref、必需/非必需检查、失败阻断/恢复及未合并边界。C03/C12/C13 扩展与正式旧包/真机仍待后续执行。

## 2026-10-12：PR #3 审查、dev 合入与 C03 合同扩展

### 已完成的审查和 Git 交付

- 用户授权按“完整审查 PR #3 → dev 交付及验收 → C03 扩展”的建议继续。本轮对 fbf7382 的完整 13 文件变更进行 Codex 审查，检查固定源码/包映射、实际 Hono 请求与旧 DTO、错误/退出码、只读 CI 权限和产物范围，未发现当前范围的阻断项。GitHub review `5486708864` 为 COMMENTED，明确为 Codex 审查，不冒充独立人工审批。
- PR #3 转为 ready 后，核验精确 head、dev base 和两项必需兼容检查 SUCCESS，再按用户授权通过 GitHub 合并；北京时间 13:07:20 回读为 merged/closed，dev=`e8d1dd952f05b1f5d7a438ccc68c6f45e5fa1351`，合并树与审查过的 fbf7382 相同，main 仍为 `7ac984ecd604b9fc483bf02c1bf0dded37651034`。没有绕过状态检查或修改合并规则。
- dev 合并提交的 [兼容运行 38206582264](https://github.com/kando6370-wq/toccards/actions/runs/38206582264) 与 [iOS unsigned build 38206582275](https://github.com/kando6370-wq/toccards/actions/runs/38206582275) 均 completed/success。13:19:56 内网回读 health=200、未登录 auth/me=401、Admin 首页=200；这些响应不包含 release SHA，不能证明运行版本已切换到该提交。
- **dev 运行验收未闭合**：本机 kd201 别名不能解析；文档示例 user@192.168.50.201 的 BatchMode/StrictHostKeyChecking SSH 被拒绝。未读取 watcher current/last-deployed、发布日志、容器、备份或 ledger。合并会命中仓库中的监听路径规则，但未取得远端证据，不能宣布 watcher 实际发布完成；没有并发启动手工部署、修改服务器凭据或进行远程迁移。需要维护者提供本机可用的已验证 SSH 目标及密钥/agent，以便补只读回查。

### C03 实现范围与本地进展

- 从已合入的 dev 创建独立分支 `codex/c03-app-compatibility-20261012`。只扩展既有 API/旧 Dart 合同测试和当前版本文档，不修改业务路由、价格规则、客户端运行代码、依赖、版本门禁或生产 Schema。
- 使用既有 PostgreSQL 迁移 0000/0001/0003/0004/0006，在本地 PGlite 内存库建立目录、价格及读取场景；测试分区仅服务于该内存库，不新增迁移或连接远程数据库，也不增加/维护 D1 基座。
- 41 张 TCG 样本覆盖目录可见性、字符串/前导零 ID、40+1+0 分页和按 set_id 查询；价格样本按 validated→published→pointer 的实际约束入库，确认零价为 0、只有未发布报价的卡牌仍未知、历史仅保留真实观察点。另覆盖空结果、422、404、数据库异常 500，以及 USD 汇率和无可用缓存时的上游 502。
- KV 使用本地 Map，外部 fetch 默认拒绝；汇率成功只注入受控上游样本，经实际 loader/Hono 生成响应，未调用真实汇率源。响应样本增加可选 Content-Type 元数据，使实际纯文本 500 不被改写为 JSON 成功包；旧 JSON 默认值保留。公共目录/汇率无 Bearer，原 portfolio/scan 的 Bearer 和幂等键断言保持。
- 旧 1.0.4/1.0.5 分别使用同样的新增合同；保留数值 card_ref、缺少 items、错误汇率 base 三种反例，以及显式未知价格/新增可选字段的兼容正例。当前只是 C03 首批源码合同，不能推断完整价格维度、其他游戏/数据源、实际目录抽样或正式包/真机通过。
- 首轮 API 用例因新增夹具误用 product_type_name=Card 而失败；当前实现要求 Cards，已只修正夹具，没有修改业务过滤或放宽断言。随后首次完整运行 `run-tWRpmy` 为 API 8/8、两个旧源码各 24/24，无跳过。初轮类型检查因新文本响应推导为 unknown 失败；为助手保留默认 JSON 类型并给文本调用显式泛型后，根类型检查 7/7 通过（6 项缓存、Workers 实跑）；依赖方向检查、基线守卫 2/2 和 `flutter analyze --no-pub tool/compatibility` 均通过。
- 已完成零价被误写为缺价的故障注入反证：在 API 断言完成后，临时将导出的 card-zero.price_usd 从 0 改为 null。API 8/8 仍通过，但旧 1.0.4 的“零价不是未知价”断言失败（期望 0、实际 null），runner 退出 1 / report=failed；按既有失败即停逻辑，负例未继续 1.0.5，未将其记为通过。负例为 run-yR6UhZ，恢复按原字节完成，run-EkThOn 复验 API 8/8、两组各 24/24。
- 最终审查补齐旧 searchSets 不发送 page 的请求形式，与显式 page 的 searchCatalogSets 分列；最终 run-0bnsT6 为 API 8/8、39 份实际响应、两组各 24/24，无跳过。补齐后再次运行根类型检查 7/7（6 项缓存、Workers 实跑）和目标 Flutter analyze，均通过。所有本地报告均正确标记 workingTreeDirty=true；不把它们冒充已提交源码或托管 CI。
- C03 本轮 Code Review（Codex 自审，非独立人工评审）检查了 PostgreSQL 真实读取与发布可见性、无外部 HTTP、前导零 ID、分页、零价/缺价区分、历史点、JSON/文本错误回放及旧鉴权断言；没有放宽既有断言或删除失败检查。日志中的 Contract database unavailable 是明确注入并断言 500 的预期场景，未屏蔽该日志。
- 范围仅为测试和当前文档，未修改业务代码、迁移/Schema 文件、锁文件、工作流或旧版本归档；未重跑无关全量业务测试、产品打包、真机/正式制品与生产写入。C03 新代码尚未合入 dev，C12/C13 扩展留待后续。dev watcher release、备份、容器和 ledger 仍需可用 SSH 目标补验，不能用合并或 HTTP 200 关闭这些待验项。


## 2026-10-12 C03 托管结果与 dev SSH 补验

### C03 提交与托管检查

- 提交 `7516c438c2f77d2fa5c7ca24146eb5806c44bf11` 已推送至 `codex/c03-app-compatibility-20261012`，建立 [Draft PR #6](https://github.com/kando6370-wq/toccards/pull/6)，目标为 dev，保持未合并。变更为两个合同测试文件、当前版本文档及 Agent 范围说明，不含业务运行代码或 Schema/migration 变更。
- 13:58–14:10 独立回读 [push 兼容运行 38209819070](https://github.com/kando6370-wq/toccards/actions/runs/38209819070)、[PR 兼容运行 38209949303](https://github.com/kando6370-wq/toccards/actions/runs/38209949303) 和 [PR iOS unsigned build 38209949305](https://github.com/kando6370-wq/toccards/actions/runs/38209949305)，均为 completed/success。两个兼容 artifact 已下载，均核对为 API 8/8、旧 1.0.4/1.0.5 各 24/24、39 份实际响应、固定旧源码提交、workingTreeDirty=false，包含真实 text/plain 500 的失败语义。
- push 报告源码为 `7516c43`，PR 报告源码为合并引用 `9deda2a2e68318caaf3d7eb5e596a9811601d7b3`；不把 merge ref 写成 head，也不把 CI 通过写成 PR 已合并。独立的 `Workers Builds: toccards-website` 预览检查仍失败，构建日志权限缺失，根因未确认；不纳入兼容测试通过的结论。

### PR #3 合并后的 Linux dev 独立运行验收

- 14:22–14:26 使用用户提供的 SSH 登录完成 `192.168.50.201` 只读补验，主机为 srs-node-test1；凭据未写入文件、命令参数或记录。此前 SSH 不可用的检查点按原时刻保留，本节关闭其中 watcher/release、容器、备份与 ledger 的待验项。没有启动第二次部署或修改 watcher/私有环境配置。
- `readlink -f current`、`release-manifest.txt`、`shared/current-release`、`watcher/state/last-seen-sha` 与 `last-deployed-sha` 一致：release 为 `branch-dev-e8d1dd952f05-20261012131153`，源码为 `e8d1dd952f05b1f5d7a438ccc68c6f45e5fa1351`，来源为 kd201-branch-watcher。watcher 源码 checkout 为同一提交且 `git status --porcelain` 为空，failed-sha/failed-at 不存在；cron 保持每 2 分钟检查，14:18/14:20/14:22 的日志均报告没有新提交，核查时未见持锁部署进程。
- `docker inspect` 只读取所需状态：API/DB 为 running/healthy，Web running，migration exited/0，Compose 工作目录均指向该 release，API 没有宿主端口绑定。PostgreSQL 实际为 18.6，PGDATA/data_directory 为 `/var/lib/postgresql/data`，数据卷为既有名称 `toccards-linux-test_postgres-data`。
- 在 `BEGIN READ ONLY` 事务中查询 `schema_migrations`，共 14 项，最新 `0013_cards_all_search_trgm.sql`，该项 applied_at 为 2026-09-18T06:22:09.363963+00:00。与当前 release 的 14 个迁移文件对照，pendingMigrations 为空；实际预检日志同样为空，迁移容器日志逐项跳过已有 14 项，没有本轮新增迁移。核验未执行 migration、SQL 业务写入或恢复。
- 发布前备份 `toccards-test-20261012-131155-before-branch-dev-e8d1dd952f05-20261012131153.dump` 为 1,135,398,457 字节，临时文件不存在。通过当前 PostgreSQL 18 容器只读执行 `pg_restore --list`，退出 0、列出 324 条非注释目录记录；归档头的 TOC Entries 为 328，两者口径不同。未做恢复演练，不据此宣称可恢复性已完整验收。
- 通过 SHA-256 对照，容器中的 API bundle/source map 与 Web server 文件均匹配当前 release；Admin 全部 11 个 HTML/JS/CSS 文件同时在容器和 HTTP 响应中与 Linux release 原始字节一致。本轮未另做同提交 Windows 重建，不宣称跨平台构建逐字节一致。服务器本机和 Windows 内网请求均为 health 200（status=ok）、未登录 auth/me 401、Admin 首页 200 且标题正确；发布身份另由 manifest、watcher 和运行文件证明。
- 14:28 GitHub 回读 dev 仍为 e8d1dd9，main 仍为 `7ac984ecd604b9fc483bf02c1bf0dded37651034`，PR #6 仍 Draft/未合并。因此 dev 验收对象为已合入的基础兼容改动，C03 增量尚未部署。正式旧包/真机、真实账号业务闭环、多游戏/完整价格维度、C12/C13 其余合同及全量兼容矩阵继续待验；本轮未执行生产发布。

## 2026-10-12 Home 文件夹切换 BUGFIX（本地）

- 用户 iOS 录屏：Home 显示 Main 和旧金额，页面出现两个 `No content available`；从共用弹窗选择其他文件夹后，Collection 已切换，返回 Home 仍显示 Main。录屏没有网络日志，不能据此确定 Home 数据请求失败的服务端原因。
- 根因：Home 的全局 `selectedPortfolioFolderProvider` 监听在 `isUnavailable` 时直接跳过；即使 Collection 已更新共享选择，Home 仍保留失败前的文件夹 ID。修复前使用“首次加载成功、随后 Home 刷新持续失败、通过共用弹窗切换文件夹”的 widget 测试复现，退出 1，断言 Home 为 `sealed` 时实际仍为 `main`。
- 最小修复：共享选择变更时，先用 Home 已缓存的目标文件夹更新 ID 和图表周期，再刷新 Home；刷新失败仍保留正确的文件夹上下文和原有失败提示。未修改服务端接口、偏好持久化语义、Collection 切换逻辑、Schema 或部署配置。v1.0.0 已有 Home/Collection 同步切换契约，本轮不改冻结文档。
- 影响与验证：对 Home/Collection 共用选择、失败后重试、图表周期和偏好写入回退作代码审查；目标测试修复前失败、修复后通过。`flutter test --no-pub test/home_controller_test.dart test/collection_controller_test.dart test/widget/home_page_test.dart test/widget/collection_page_test.dart` 退出 0，共 170 项；`flutter analyze --no-pub lib/features/home/home_controller.dart test/widget/home_page_test.dart` 退出 0；`git diff --check` 退出 0。Code Review 未发现当前变更的阻断项。
- 未验：未持有录屏设备与其 API 日志，未以相同真实账号在 iOS/Android 真机重放，也未定位 Home 请求失败的独立原因；若文件夹创建后 Home 从未成功获取该文件夹，且后续刷新持续失败，Home 无法仅凭旧缓存显示新文件夹的名称/估值，此边界未作为本次已修复范围。未执行远端部署、数据库操作或发布。

## 2026-10-13 App 兼容 CI 开发分支触发调整（本地）

- 根据用户确认的开发流程，工作流仅删除 `push.branches` 中的 `codex/**`，保留目标 `dev`/`main` 的 PR、`dev`/`main` push 和手工触发；固定检查名、测试步骤、权限、并发取消策略和工具链均保持不变。远端规则集 `24904725` 本轮没有修改，`dev`/`main` 仍保留兼容必需检查。
- 日常提交推送到 `codex/**` 开发分支，完成一批改动后通过 PR 合入目标分支。没有 PR 的开发分支 push 不启动此兼容工作流；已有 PR 的后续提交仍触发 PR 检查，但不阻止开发分支推送。直接推送尚未通过检查的新提交到 `dev`/`main` 仍可能收到 GH013。
- 同步更新根 `AGENTS.md` 与[兼容回归说明](../03-data-api/app-compatibility.md)中的当前触发策略，既有托管运行、规则配置和门禁正反例的历史记录保持原样。
- 本地验证：`pnpm lint` 退出 0；`pnpm type-check` 退出 0，7 项成功，其中 6 项为 Turbo 缓存、Workers 类型检查实际执行。Python/PyYAML 结构断言退出 0，覆盖 7 种分支过滤场景及手工入口，并确认 YAML 相对 HEAD 仅删除该分支条目，PR 无路径过滤、检查名/权限/全部测试步骤不变。
- 文档与差异复验：`git diff --check` 退出 0，16 处本地 Markdown 链接有效；当前说明中的旧触发范围已移除，历史验证内容保持原前缀，改动仅涉及工作流、根规则及当前版本两份文档。差异自审未发现阻断项，未修改测试断言、运行步骤或远端保护规则。
- 未运行：GitHub 托管事件触发及 PR 门禁复验，因为本轮未提交或推送；完整 App 兼容业务回归及应用构建未重跑，因为测试实现、步骤和应用代码均未修改。本条仅记录本地配置验证，不宣称远端新触发策略已验收；没有部署、迁移或业务写入。

## 2026-10-13 App 兼容必需检查规则删除

- 用户明确要求删除 `App compatibility (Windows)` 对推送/合并的强制限制，并完成管理员浏览器登录。管理员页面与删除前 API 共同确认目标为规则集 `24904725`（`App compatibility required checks`），仅匹配 `refs/heads/main`、`refs/heads/dev`，唯一规则为 GitHub Actions（integration ID `15368`）的同名 required status check，bypass list 为空。
- 通过 GitHub 管理员界面删除该规则集；页面返回 `You haven't created any rulesets`。本次没有修改工作流、测试步骤、Git 凭据、其他仓库设置或分支内容；前一阶段取消 `codex/**` push 触发的本地改动继续保留。
- 独立 API 回读：规则集列表返回 200 / 空数组；旧规则集详情返回 404；`main`、`dev` 的有效规则分别返回 200 / 空数组，分支详情均为 `protected=false`。据此确认该兼容检查已不再阻止两个分支的推送或合并；兼容工作流继续作为异步检查运行，不把规则删除等同于测试通过。
- 删除前配置及可重建的请求体、删除后只读响应和页面截图保留在忽略目录 `.dart_tool/compatibility-gate/20261013/ruleset-removal-1791870080283/`，没有保存认证凭据。同步更新根 `AGENTS.md` 与[兼容回归说明](../03-data-api/app-compatibility.md)的当前状态，前一阶段与 2026-10-12 的配置/验收记录按历史证据保留。
- 复验：6 个远端只读端点的状态/内容断言通过；`git diff --check` 退出 0，17 处本地 Markdown 链接有效。当前说明已取消强制门槛表述，历史段落已明确标注；验证记录原有字节前缀及工作流文件与本轮开始时一致。差异自审未发现阻断项。
- 未执行实际 push、PR 合并、部署或数据库操作，因此没有触发自动发布来测试解除阻断。此前本地 CI 触发调整及本次文档修改仍未提交/推送；远端规则删除已经生效，这两种交付状态分别记录。业务代码与测试实现未改，本轮不重复运行完整兼容回归或应用构建。

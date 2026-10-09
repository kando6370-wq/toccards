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

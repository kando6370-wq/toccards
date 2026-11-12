# Android 与 iOS 版本管理

本节区分应用内升级规则和打包构建号。Android 复用现有版本门禁及数据结构，iOS 的
规则、接口、商店地址、版本比较和发布脚本保持原有行为；不新增数据库表或 migration。

## 应用内升级规则

后台“版本管理”分别管理 iOS 与 Android（Google Play）的最低支持版本、建议版本、
强制更新、下载地址及启停状态。界面将原 `Google` 显示为 Android（Google Play）；
保存和启停仍使用原 `Google` wire 值，不迁移旧配置。

现有 V1 协议和存储键保持兼容：

| 项目 | iOS | Android |
|---|---|---|
| Flutter 公共配置查询 | `platform=ios` | `platform=google` |
| 新增兼容查询别名 | — | `platform=android`，与 `google` 返回同一规则 |
| Admin 平台值 | `iOS` | `Google` |
| PostgreSQL app_config key | `admin.app_version.<environment>.ios` | `admin.app_version.<environment>.google` |

environment 由可信服务端的 `APP_ENVIRONMENT` 决定，分为 `development` 和 `production`，
不能通过请求参数切换。省略或未知 platform 继续保留 iOS 的既有缺省行为。
保存 Android 规则不会更新 iOS，也不会将 dev 规则复制到 prod。

两端继续执行同一版本策略：

- 只比较 `major.minor.patch`；Android versionCode、iOS build number 和 `+build` 不参与。
- 当前版本达到建议版本时不弹窗。
- `force_update=true` 且当前版本低于最低支持版本时必须更新。
- 达到最低支持版本但低于建议版本时允许稍后更新；推荐提示按版本在当前进程内去重。
- 首次进入 Home 的配置失败仍显示重试，不伪装成无需更新；已确认的强更保留阻断，
  回到前台和再次进入 Home 会重新核对。
- Android 的 INSTALL 打开所选 Android 规则中的地址，iOS 保留原 App Store 地址。
  打开下载地址失败时保留提示并允许重试，不让强更绕过门禁。

各环境需要由运营保存明确规则。停用规则可以保留空下载地址；启用前必须填写真实可达的
HTTP(S) 下载页／商店地址，且建议版本不低于最低版本。缺失或损坏的已选规则仍返回 503，
不回退到另一平台或环境。仅打包新制品不会自动提高最低版本、开启强更或发布后台规则。

2026-11-09 的 dev 只读检查显示 Android 更新提示处于停用状态，保存的地址仍为
YouTube 占位链接，不能直接作为 Card AI 更新入口。本轮不自动修改该运行配置。
实际启用前应确认目标版本、兼容下限、强更开关和真实下载地址；正式商店版本尚不可下载时
不得用强更将用户导向不可用页面。

## Admin 编辑与保存回显（2026-11-10）

版本页面只展示版本管理，移除页内遗留的“销售数据”和“订单查询”标签；后台独立的
订单统计菜单不受影响。

原保存流程丢弃 PATCH 返回的新记录后重新查询列表，且没有提交锁。普通版本 SELECT
可复用 Hyperdrive 的旧查询结果；HTTP `Cache-Control: no-store` 不控制数据库查询缓存，
数据库写入也不会主动清除已缓存的 SELECT。连续点击保存还会并发写入同一平台的规则。
这些路径会造成保存后旧值回显或较早提交覆盖较新提交；没有读取生产原始请求日志，
不将某一次线上错误归因于其中某一条路径。

当前保存和启停成功后直接使用服务端返回的完整记录替换对应平台行，包含更新时间、
最低版本、建议版本、强更、地址及状态，另一平台保持原值。共享 Admin 数据读取 hook
增加本地更新入口，同时取消尚未完成的旧列表请求并忽略其迟到结果，防止覆盖已确认的保存结果。
保存期间锁定提交、编辑、启停和关闭抽屉；失败时提示错误并保留编辑内容，允许用户重试。

后台版本列表与 App 公共配置的专用 SELECT 加入 `CURRENT_TIMESTAMP AS fetched_at`，
根据 [Hyperdrive 查询缓存规则](https://developers.cloudflare.com/hyperdrive/concepts/query-caching/)
使该查询不进入查询缓存。时间字段仅供内部查询，不进入 Admin 或 App 响应。HTTP
`no-store` 保留，其他业务查询与全局 Hyperdrive 配置保持原值。不使用 SQL 注释或
只读事务来假定缓存失效，不新增数据库表、migration 或 binding。

V1 路径、请求及响应字段保持兼容；平台仍为 `iOS`／`Google`，公共 `android` 别名仍
读取 Google 规则；可信服务端环境、平台隔离、规则校验、权限及 Flutter 升级策略保持原行为。
影响范围限于 Admin 版本编辑／启停、共享 Admin 读取 hook 的迟到响应保护及公共 App 配置读取。
本地测试的缓存替身不等于生产 Hyperdrive 实测；远端发布、真实管理员操作和两端真机升级
仍须分别验收，本次不修改远端规则。

本地验证基线为 `main@3de09907` 加本次未提交修改，Windows／Node `22.23.4`／pnpm
`11.28.10`。独立 Node 位于
`C:/Users/jhon/AppData/Local/Temp/kando-node-v22.23.4-win-x64/node-v22.23.4-win-x64/node.exe`，
下表以 `node22` 简写；最终根检查也通过该 Node 显式调用 Corepack 的 pnpm 入口。

| 验证范围与命令 | 实际结果 |
|---|---|
| Admin 目录：`node22 --max-old-space-size=256 --max-semi-space-size=2 --test --test-concurrency=1 test/*.test.mjs` | 退出 0，95 项通过；标签断言改为实际渲染节点后，版本／共享读取两个文件再定向运行 10 项通过。 |
| Workers 目录：`node22 --max-old-space-size=256 --max-semi-space-size=2 node_modules/vitest/vitest.mjs run src/app-config/version-control.integration.test.ts src/app-config/routes.test.ts src/compatibility/app-contract.test.ts --exclude **/.wrangler/** --maxWorkers=1 --no-file-parallelism` | 退出 0，3 文件／24 项通过，包含平台／环境隔离、旧缓存替身、完整公共配置响应及 V1 源码合同。 |
| 根目录：`pnpm type-check --concurrency=1 --force`，Node 内存限制 512 MB | 退出 0，9 个实际任务成功、0 缓存命中；Admin／Workers 另以 Node 22.23.4 直接调用 tsc 检查通过。 |
| 根目录：`node22 scripts/check-dep-direction.mjs`、`git diff --check` | 退出 0；依赖方向及差异格式检查通过。 |

开发和文档完成后，在忽略目录隔离注入同一基线的旧实现进行反证，没有回退工作区。
相同 Admin 用例在旧逻辑下分别稳定暴露三个问题：多余标签、保存成功仍保留旧行、双击发出
两次 PATCH；旧服务端查询在已快照的旧缓存下返回保存前版本，回归用例失败。它们是开发后
对旧逻辑的反证，不是修复前已运行的测试。修复逻辑在同一用例下通过。

首次并行检查因系统虚拟内存不足退出；低内存串行方式重新完成检查后才记录通过。
独立 Code Review 无阻断项；审查建议的 SQL 说明注释已移出查询字符串并重跑相关验证。
未运行完整 Workers 测试、旧 Dart 编排、发布构建、浏览器／管理员真实操作或 iOS／Android
真机升级；本次仅修改配置读取与 Admin 交互，已验证受影响的源码合同，远端和真机仍待有权
管理员／移动端测试补验。本地修复与验证阶段未执行 Git commit/push、dev/prod 部署、迁移或远端业务写入。

### 生产后台配套发布（2026-11-10）

经用户明确授权，从干净的 `main@1c5b813e4773b6728486b50864c5a7b7a15c1071` 冻结
production Admin 与配套 Worker。独立 Node `22.23.4` 下重新完成 auth-core 构建、
Admin `vite build --mode production` 及 Worker `deploy --env prod --dry-run`，均退出 0。
与指定线上版本的 immutable module 比较，Worker 仅增加上述两处版本配置查询的防缓存处理，
没有夹带其他后端业务改动。

- 冻结 Worker 为 2,240,613 字节，SHA-256
  `6cba8831df2274cca4bf1690dffe1f336cf0f9d6dbef5b657d20ad608b6dbea0`。
  使用 `versions upload --no-bundle --keep-vars --strict` 上传候选
  `27c1b376-ed63-4b5a-bb53-80d39b5f6ae8`，通过指定版本的
  `/workers/workers/toccards-api-prod/versions/<id>?include=modules` 回读逐字节匹配，
  39 个原绑定描述符、18 个 Secret 名称及 runtime 均与原版一致；未读取 Secret 明文。
- 旧版 `c02380d5-32b2-4e63-b8ef-68cbdf909ebe` 保持 100% 时，将候选登记为 0%，
  deployment 为 `c8361028-e83e-4360-8da7-04faf9ec8e79`。通过版本覆盖头完成
  14 项 HTTP 检查和 11 个 Admin 静态文件的原始字节核验后，才切为候选 100%。
  最终 deployment 为 `cc0c498b-26cf-47ec-9b19-9a1faa1cdf16`。
- `admin.tcgcard.fun` 已由本次 Git push 自动发布，Pages deployment
  `7780d597-a6b6-4465-9e4f-9ae2d63fdaf1` 为 production／success，来源同一完整 SHA，
  dirty=false；本轮没有重复手工发布 Pages。`api.tcgcard.fun` 的后台副本随新 Worker 发布。
  最终双入口共 22 个 HTML／JS／CSS 已检查：21 个原始字节一致，Pages 的 `index.html`
  为 1048 字节，冻结 Windows HTML 为 1060 字节，仅差 12 个 CR 字符，移除 CR 后完全一致。
  另一个 Pages 只读样本包含既有 Cloudflare Browser Insights beacon，未改变统计设置，
  不宣称所有 HTML 响应都与本地构建原始字节一致。
- 正式流量下再次完成 14 项检查：health、原鉴权及 Admin 受保护接口的未登录拒绝、
  iOS／Google／Android 公共配置、Admin CORS 与 `/admin`；Google 和 Android
  配置响应一致，公共响应仍为 `no-store` 且不包含内部 `fetched_at`。最终验收时间为
  2026-11-10 15:47（Asia/Shanghai）。39 个绑定、18 个 Secret 描述符、兼容配置、
  Smart Placement、observability、logpush、运行缓存、cron、自定义域名、Hyperdrive
  查询缓存及 Pages 项目配置与发布前精确匹配，没有执行 triggers deploy。

发布脚本经独立审查后，烟测记录必须绑定候选 ID、对应 deployment 和冻结清单，切流要求
候选烟测成功，最终验收要求正式流量烟测成功。首次 dry-run 因重复 `--outdir` 参数失败，
模块回读首次使用的旧路径只返回版本元数据；均在切流前修正并重新验证，不计为通过。
构建、指定版本字节核验、候选／正式烟测和发布守卫复审最终均通过。忽略目录中的
`.wrangler/prod-admin-20261110-1c5b813e/` 保留本地冻结清单和结构化验收材料，正式 docs
不保存原始响应或凭据。

本轮没有数据库迁移、远程 SQL 写入、后台版本规则编辑／启停、订阅配置修改、Linux dev、
官网或 Flutter／商店发布，未回查生产 migration ledger。未登录烟测不替代真实管理员的
iOS／Android 编辑保存操作，也不替代真机升级提示；这两项仍需管理员及移动端测试补验。

## Android 自动打包与保存

入口、参数和环境注入见 [Flutter Android 发布说明](../../../../apps/flutter-app/README.md#android-版本与制品管理)。
`tool/release_android.py` 使用 Python 标准库，Test 构建 APK，Production 默认构建 AAB。
正式配置仍由独立打包环境注入，不读取本机既有正式签名或将凭据写入源码。

版本选择以共享 `pubspec.yaml` 和同 applicationId 已保存的 Android 制品为依据，
包括旧手工 Android 交付目录；下一个构建号必须高于两者，且不超过 Android 的
`2100000000` 上限。营销版本由发布计划决定，脚本不会自动递增 patch。

成功顺序为：验证环境与工具链 → `flutter pub get --enforce-lockfile` 恢复锁定依赖及原生插件注册 → 分析／构建 → 核对身份、版本、签名及原生库 →
复制并校验制品哈希 → 完整归档 → 写回 pubspec 构建号。
制品必须满足 minSdk 24、targetSdk 至少 36，最终签名摘要与批准证书一致。
Test 默认使用已登记 OAuth 的项目测试证书；Production 必须显式提供经 Console
核实的 Upload SHA-256，不以“签名存在”替代正确上传身份，也不将 Upload 证书
混同 Google Play 最终分发证书。
构建、校验或保存失败不提前修改版本号；其他流程修改了 pubspec 时明确失败并保留其值。
共享版本文件仍服务两端；不在同一工作区同时运行 iOS 和 Android 发布流程。

Android 制品使用 `<applicationId>/Android/` 子目录，与同名 iOS Bundle 的 IPA 隔离。
Test 保留 3 版、Production 保留 7 版，超额受管版本移至该目录的 `.Recovery`，不永久删除。
只处理受管 Android 目录，不移动 iOS 制品、其他环境、历史手工目录或符号链接。
构建信息保留 Git SHA、dirty 状态、SDK、校验结果和文件哈希；不含签名密码、私钥或 Token。
正式 AAB 的独立打包、Play 分发签名、真机更新及安装仍需分别验收，不能由本地 APK 推定。

官方工具与约束依据：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)、
[Android 版本号](https://developer.android.com/studio/publish/versioning)、
[bundletool](https://developer.android.com/tools/bundletool)。

## 验证边界

2026-11-09 已用来源 `ff35c80ac5030220d1fdba55e405469f40cabf03` 加本轮未提交修改、
锁定 Flutter `3.47.9`、Dart `3.13.7`、JDK `21.0.13+9` 实际执行
`python tool/release_android.py --env test`。脚本扫描到 `com.kando.kandoApp.beta`
历史最高 Android 构建号为 203，在共享 `pubspec.yaml` 的 194 基础上选择 204，
构建成功并在校验后写回 `1.0.7+204`。交付目录为
`D:/Downloads/CardAI-Packages/com.kando.kandoApp.beta/Android/CardAI-Test-1.0.7-204/`，
APK 252,665,220 字节，SHA-256 `5b8ad76110963a271e7d0da61f7591357a56152402e695ae196f2fb5f780dd6e`。
APK 包名、versionCode 204、Debug 测试证书、minSdk 24、targetSdk 36、28 个原生库、
19 个 64 位库、ELF／ZIP 16 KB 对齐和已批准测试证书摘要均通过；复制哈希一致。
Python 制品管理测试 23 项通过；版本规则与 Admin／Workers／Flutter 定向回归在同一任务中
通过。该包未安装到设备，Android 真实升级弹窗和 Play 登录仍待真机验收。

本地实际通过不代表已启用 dev/prod Google 规则。2026-11-09 dev 的 Google 更新规则仍停用，
保存的旧地址为占位地址；在产品确认真实版本、最低版本、强更开关和 Play 下载页前，
不执行远端规则写入或把占位地址提供给用户。

未执行 API／Admin 远程部署、后台规则启用、Google Play 上传或 iOS 构建时不得写成通过。

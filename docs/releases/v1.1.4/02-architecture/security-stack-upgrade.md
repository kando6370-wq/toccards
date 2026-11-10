# 技术栈安全评估与升级（2026-11-05）

核查日期：2026-11-05，Asia/Shanghai。源码基线：`codex/dev-andriod@84eba861`。本次处理当前架构所用依赖、SDK、构建工具与运行镜像的已知安全公告；[完整 STRIDE 评估](../../../../Risk_Assessment_Report/KANDO-RISK-ASSESSMENT-REPORT.md)及阶段产物存放于仓库根 `Risk_Assessment_Report/`。包命中、可利用性分析、本地验证和远端发布是不同结论。

## 架构与判断边界

App 是 Flutter，服务端为共享 Hono API，分别运行在 Cloudflare Workers prod 与 Linux Node dev；业务真源为 PostgreSQL，Linux dev 与 prod 独立。Admin 是 React 18 + Vite 的浏览器 SPA，生产由独立 Pages 和 Workers assets 两个入口托管；当前没有 Next.js 或 React Server Components，不据相关服务端公告强行升级 React 主版本。

本次不改变 API 路径、请求／响应合同、订阅与权限、数据归属、PostgreSQL schema、D1 退役规则或 UI 布局。Drizzle 升级只消除旧依赖中的漏洞，不生成、恢复或维护旧 D1 migration。Cloudflare compatibility date 锁定行为兼容，不能用修改日期代替平台安全补丁证据。

## 已确认的升级范围

| 组件 | 升级前 | 本次目标／锁定版本 | 依据与适用条件 |
|---|---|---|---|
| Node.js | 本机 22.20.0；CI、在线镜像浮动 22 | 正式支持 `^22.23.4`，CI 固定 22.23.4 | 官方 2026-10 安全版本；本地使用官方校验后的独立运行时验证，不改机器全局安装 |
| pnpm | 11.9.0 | 11.28.10 | 11.9.0 落在 <11.11.0 的 tarball／lockfile 路径穿越和不可信代理配置泄露环境变量公告范围；根 packageManager、CI 和 watcher 同步 |
| Hono | 4.12.27 | 4.13.16 | 覆盖 CORS、query parser、parseBody、JSX、静态路径等已知修补；下文区分未触发路径 |
| Hono Node adapter | 2.1.1 | 2.1.6 | 覆盖静态文件二次解码修补；当前入口未使用受影响的 serveStatic |
| Drizzle ORM／kit | 0.38.0／0.30.0 | 0.45.4／0.31.11 | ORM 修复 SQL 标识符转义；当前仅发现静态旧 schema 引用，未证明动态注入路径 |
| Vite／React 插件 | 6.4.3／4.3.0 | 6.4.5／4.7.0 | Vite 6 的安全回补；插件同大版本更新以满足 Vite 6 peer 范围 |
| Vitest | 4.1.9 | 4.1.12 | redirect mock 文件读取及 manual mock 注入修补；现有 Node run 并未注册公告中的 dev-server handler |
| Miniflare 间接依赖 | sharp 0.34.5、undici 7.28.0 | sharp 0.35.5、undici 7.30.1 | 对 `miniflare@4.20260630.0` 定向 override，保留现有稳定模拟器与 Wrangler，避免仅为依赖补丁引入 Miniflare 5 beta |
| 构建链间接依赖 | PostCSS、nanoid、source-map-js、Browserslist 等旧锁定版本 | 锁文件中的修补版本 | 刷新这些已命中漏洞的间接依赖，不批量升级无关业务组件 |
| Flutter／Dart | CI Flutter 3.44.0／3.44.7，本机 Dart 3.12.2 | Flutter 3.47.9／Dart 3.13.7 | 官方 Dart 公告 GHSA-frr6-h895-5pxp：受损 eMudhra CA 可导致 dart:io TLS 中间人攻击；Android、Windows 和未更新证书库的 Linux 受影响，iOS/macOS/Web 不受影响 |
| Gradle Wrapper | 8.12 | 8.14.6 | 官方 2026-10-07 高危公告；更新分发包、官方 SHA-256 与可跟踪的 wrapper jar |
| Android AGP／Kotlin | 8.9.1／2.1.0 | 8.13.2／2.2.20 | Flutter 3.47.9 实测分别拒绝旧 AGP 与 Kotlin；按 SDK 明确最低要求配套升级，不绕过构建依赖校验 |
| Android 构建 JDK | Android Studio JBR 21.0.10 | Temurin 21.0.13+9 | 2026-10 CPU／eMudhra 信任库修补；属于构建供应链，不随 APK／IPA 分发。必须核对 Flutter／Gradle 实际选中的 JDK，单设 JAVA_HOME 不足以覆盖 Android Studio JBR |
| PostgreSQL 在线镜像 | 浮动 18-alpine | 18.6-alpine | 保持 PostgreSQL 18 与现有 PGDATA／卷；离线 apt 镜像及远端数据库另行回读，不能由标签推定 |
| Caddy 在线镜像 | 浮动 2-alpine | 2.11.8-alpine | 同大版本安全补丁；固定单 upstream 配置未使用多项公告所需的高级路由功能 |

pnpm 选择已于 2026-10-30 发布的 11.28.10；不为追逐最新而切换刚发布的 11.28.11 或 pnpm 12。pnpm 本体、Node、Flutter 和 Gradle 不属于应用 `pnpm audit` 覆盖范围，必须单独核查。

## 漏洞命中与实际可达性

- 初始官方审计返回 54 个 package/advisory 条目，去重后 53 个 GHSA、14 个包；严重度为 high 18、moderate 31、low 5、critical 0。同一公告可同时归于 Vitest 与 mocker，因此不能把 54 写成独立漏洞数或项目已被攻破的数量。
- 默认 `registry.npmmirror.com` 无安全审计 bulk endpoint，初次命令失败；有效审计均显式指定 `--registry=https://registry.npmjs.org`，未通过忽略列表隐藏公告。
- `apps/workers-api/src/app.ts` 为 CORS 配置了非空 `allowHeaders`，不进入 GHSA-8j4g-w8fx-2239 的默认／空列表分支。现有服务未使用 Hono `serveStatic`、SSR `memo()` 或 `mockerPlugin()`，相应依赖命中不能直接视为线上越权、泄露或注入已验证。
- Drizzle 公告要求不可信输入进入 `sql.identifier()`／动态别名；当前业务 PostgreSQL 使用既有访问层，本次仅在静态旧 schema 找到 Drizzle 导入。升级是消除受影响版本，不宣称已发现生产 SQL 注入。
- App production 优先使用 Cronet／URLSession，但仍保留 IO adapter 及 native adapter fallback；依赖和 SDK 可能发起 dart:io HTTPS，不能据主 API 使用 native transport 排除 Android TLS 风险。补丁必须通过重新构建和发布移动端安装包生效。
- Flutter 公告无 CVE 编号，严重度为 High，影响为 TLS 中间人攻击；按维护方原始公告的产品、平台和版本范围判断，不扩展成远程代码执行结论。Gradle 采用下列三份维护方原始公告。

## 定向间接依赖处理

`pnpm-workspace.yaml` 只对确实固定旧版本的父包设置 override：`miniflare@4.20260630.0>sharp`、`miniflare@4.20260630.0>undici`、`@esbuild-kit/core-utils@3.3.2>esbuild`。后者是 drizzle-kit 的旧 loader 引入链，补至 esbuild 0.25.12；没有把所有依赖中的 esbuild 强制替换为同一版本。以后父包不再固定漏洞版本时，应复核并移除对应 override。

Cloudflare Workers types 同步到 Wrangler 当前版本所需的 4.x 范围，解决原有 peer 不匹配。React 18、Ant Design 5、Postgres.js 3、订阅插件及自定义 ONNX AAR 没有本轮已核实的直接命中，不扩展主版本升级或重建模型运行时。

Flutter SDK 强制升级了 matcher、meta、test、test_api、test_core、vector_math 六项传递依赖，未批量升级购买、相机或网络插件。SDK 自动补齐两个工作区的 build／平台目录分析排除，业务 `lib/` 与 `test/` 的 lint 和测试范围保留。GitLab 原 cirruslabs Flutter 镜像已停更，新版本标签不存在，故 Dart job 改为 Debian 基础镜像加官方 Linux archive 与 SHA-256 校验；安装官方所需的 unzip／zip 等工具，不使用未经核实的镜像标签。

App 自身保留原 Dart 3.9 语言模式，根 workspace 仍要求 Dart `^3.13.7`，App 同时要求 Flutter `>=3.47.9`。因此实际 SDK 继续强制使用修补版本，且不会仅因 SDK 升级而触发约 30 个业务文件的私有 named initializing formal 风格重写。新版 analyzer 还指出图片 decoder Future 未在现有 try 内等待：已最小补上 `await`，让异步解码失败进入原 catch、驱逐缓存并允许同 key 重试；该回归在隔离旧源码下确认失败，在修复后通过。

## 验证与发布状态

源码配置已修改不等于构建成功，构建成功不等于 GitHub/GitLab 已运行或环境已部署。

- 官方 npm 审计复核已为 0 条公告，未采用 audit ignore；Node 22.23.4／pnpm 11.28.10 的 frozen 安装和 peer 检查通过。
- 依赖方向检查通过；全仓 TypeScript 检查 7 项任务通过；Workers 完整 102 文件／927 项测试、Admin 87 项、auth-core 34 项、回调代理／离线 Web／Linux preflight 共 18 项全部通过，无跳过。
- prod Worker／Admin dry-run 与 Linux dev 打包 dry-run 均通过；Linux 独立 bundle 的 3 项既有烟测通过。没有连接 SSH 或发布 Worker／Pages。
- 旧 App 1.0.4+161、1.0.5+163 的固定源码合同各 24 项通过，报告证据类型为 `git-source-contracts-only`，服务端为当前 dirty 工作区；不代表历史正式制品或真机已验收。
- 新 SDK 下 `flutter pub get --enforce-lockfile` 通过；标准 `dart run melos run analyze` 成功，App 与 subscription-core 均为 0 issues；subscription-core 12 项测试及新增异步图片解码回归通过。旧源码下同一解码回归按预期失败，未在活动工作区反向修改生产逻辑。
- App 最终全量串行测试为 **1326 通过／9 失败，命令退出码 1**。已用 `84eba861` 原始源码、原锁文件和 Flutter 3.44.7 在同一 Windows 主机复现这 9 项，并通过脚本比对失败名称集合完全相等：新增失败为空。该结果不能写成全量测试通过。
- 6 项升级新增的 golden 失败已经双人逐图检查及像素统计，均为边缘抗锯齿、透明度或低幅度量化差异，未发现元素位移、文案、主色、换行或控件尺寸变化。评审涉及 7 对 PNG，实际仅更新 6 张有差异的基线；tip PNG 原本字节相同，未产生变更。最终全测中这 6 项均通过，比较阈值与 9 项原有失败保持原样。
- Android Debug APK 构建通过，实际使用 Flutter 3.47.9、Gradle 8.14.6、AGP 8.13.2、Kotlin 2.2.20、Temurin JDK 21.0.13+9；Flutter doctor 与构建进程均确认了隔离 JDK 路径。构建耗时 461.7 秒，未跳过版本校验。为规避宿主内存提交额度与跨盘增量缓存问题，仅在验证进程中使用 2 GiB Gradle heap、单 worker、Kotlin in-process／非增量编译，未永久修改 `gradle.properties`。临时 Flutter `jdk-dir` 已恢复。
- APK 位于 `apps/flutter-app/build/app/outputs/flutter-apk/app-debug.apk`，251,305,638 字节，SHA-256 为 `4a1c8c96de21817b0ad6c1b2e4c274348d4f72dca239548cced7aa14608b52c3`，已独立复核。此为 Debug 编译证据，不能替代 release／签名、商店、真机网络／识别／购买验收。
- 首轮并行移动验证因 Windows 内存提交额度耗尽退出，不能记为通过；随后一次 Android `flutter clean` 与 App 测试重叠，删除了运行中的测试资产，该次缺失 AssetManifest／shader 的结果作废。后续验证改为串行，不修改系统 pagefile 或结束用户应用。
- Node 22.23.4 官方 Windows zip SHA-256 已核对为 `cbc74b5e0982c9dbb41525fd8fb5dcd32fbee237863f7829072f4639a1ce5f20`；全局 Node 22.20.0 保持原状，本轮最终验证使用独立 22.23.4。
- Flutter 3.47.9 官方 Windows SDK SHA-256 为 `d8e2b5977e09082c6440f89dc1aa887b94c8fbcc3b39222797046295a3f68a9e`，实际下载包校验一致，独立 SDK 报告 Dart 3.13.7。全局 SDK 保持原状。
- Gradle 8.14.6 all 分发包 SHA-256 为 `24fc39aedd1b68c3de8e4d46a0277c9b42d9ccdb172231a634fad54a3693e50a`；wrapper jar SHA-256 为 `ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0`。
- 安全升级实施与本地验证阶段未进行 Git commit/push，也未触发 GitHub／GitLab 托管流水线；后续 Git 交付以分支记录为准，不代表环境发布或 CI 验收。本轮未进行 dev/prod 部署、远程数据库迁移／业务写入或商店发布。远端 Node／PostgreSQL／Caddy、实际镜像和现有 App 的修补状态仍未回读。

保留的 9 项旧基线失败如下，未作为安全升级的附带业务改造处理：

| 测试文件 | 失败项 | 数量 |
|---|---|---|
| `test/widget/auth_profile_test.dart` | subscription bottom sheet 的 390×844 golden | 1 |
| `test/widget/home_page_test.dart` | normal Home、partial Home failure 的 390×844 golden | 2 |
| `test/widget/scan_page_test.dart` | pre-scan、scanning、recognition、reveal 的 390×844 golden | 4 |
| `test/widget/scan_page_test.dart` | Matched 卡牌价格未到达时的额度断言、等待价格完成的扫描 analytics 断言；旧／新版均为 expected 1、actual 3 | 2 |

## 环境生效与兼容验收

1. 开发／CI 使用固定 Node、pnpm、Flutter/Dart；锁定依赖安装、类型检查、受影响测试、API／Admin 构建和旧 App 源码合同通过。
2. Linux 离线模式会复制宿主 Node，而非使用在线 Dockerfile 的 Node 镜像。宿主及构建后的运行镜像必须满足 Node 补丁要求；私有环境的镜像覆盖、缓存层和 watcher 进程版本都须在发布时核对。
3. dev 按既有流程预检、备份并验证备份目录可读性，升级后独立回读版本、current／manifest／last-deployed、容器健康及 Admin 资源。保留 PostgreSQL 18 卷，不执行跨大版本升级。若既有 PostgreSQL 低于 18.6，发布预检会拒绝，须先按数据库维护流程完成备份与同大版本安全补丁升级；预检不会自动修补。
4. prod Cloudflare API／双 Admin 必须按既有流程分别发布验收。托管 PostgreSQL 的安全补丁由平台版本证据确认；不因为修改 Compose 就声称生产数据库已升级。
5. Flutter 需要 Android 与 iOS 构建及原有登录、扫描、网络 transport、购买／恢复回归。Windows 不能替代 macOS iOS 编译、签名、最终 IPA entitlement 或双端真机验收；旧安装包不会因源码升级自动修复。
6. Linux 离线 OS 载体仍含 Temurin 21.0.11_10 JRE。当前入口不运行 Java，未证明相关 Java 漏洞能从业务利用；更新载体或移除无业务用途的 JRE 需要在 kd201 验证 Node 动态库、apt 安装和 PGDATA，尚未实施，不因本轮在线镜像固定而视为关闭。

Android 新旧 SDK 的默认 compile／target SDK 均为 36，NDK 均为 `28.2.13676358`；项目 Android minSdk 24、iOS deployment target 16.0 保持。Android 构建中的未来 Gradle／AGP／Kotlin 支持下限提示、SDK XML 与 source／target 8 警告不代表当前构建失败，也不据此扩大为未经验证的 Gradle 9／AGP 9 升级。

## 官方来源

下列为本轮实际查询的维护方原始公告／版本资料，查询日期均为 2026-11-05：

- [Node 2026-10 安全发布](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)、[官方 dist 索引](https://nodejs.org/dist/index.json)。
- pnpm：[tarball name 路径穿越](https://github.com/pnpm/pnpm/security/advisories/GHSA-vq4v-j7r6-jq4m)、[lockfile depPath 路径穿越](https://github.com/pnpm/pnpm/security/advisories/GHSA-c59q-g84q-2gj5)、[代理配置环境变量泄露](https://github.com/pnpm/pnpm/security/advisories/GHSA-vx52-2968-3vc6)。
- Hono：[CORS](https://github.com/honojs/hono/security/advisories/GHSA-8j4g-w8fx-2239)、[静态路径](https://github.com/honojs/hono/security/advisories/GHSA-5r4p-p66f-jhc7)、[Node adapter](https://github.com/honojs/node-server/security/advisories/GHSA-rmxm-3fg6-px4f)。
- [Drizzle 标识符转义](https://github.com/drizzle-team/drizzle-orm/security/advisories/GHSA-gpj5-g38j-94v9)、[Vite Windows launch-editor](https://github.com/vitejs/launch-editor/security/advisories/GHSA-587h-7wmj-h5pm)、[Vitest mocker](https://github.com/vitest-dev/vitest/security/advisories/GHSA-qxg6-89mg-rqv8)。
- [Dart／Flutter eMudhra TLS 公告](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp)、[官方 Flutter Windows release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)。
- Gradle：[SSL repository 失败处理](https://github.com/gradle/gradle/security/advisories/GHSA-j5m7-59rp-24f5)、[client-daemon 反序列化](https://github.com/gradle/gradle/security/advisories/GHSA-xwqc-3h47-hg64)、[worker-daemon 反序列化](https://github.com/gradle/gradle/security/advisories/GHSA-mvvg-497x-hmj8)、[官方校验值](https://services.gradle.org/distributions/gradle-8.14.6-all.zip.sha256)。
- [PostgreSQL 18.6 release notes](https://www.postgresql.org/docs/release/18.6/)、[Caddy 2.11.8](https://github.com/caddyserver/caddy/releases/tag/v2.11.8)、[Cloudflare compatibility dates](https://developers.cloudflare.com/workers/configuration/compatibility-dates/)。
- [Oracle 2026-10 CPU](https://www.oracle.com/security-alerts/cpuoct2026.html)、[Temurin 2026-10 eMudhra 公告](https://adoptium.net/en-GB/news/2026/10/temurin-october-2026-emudhra)、[Temurin 21 官方发行](https://github.com/adoptium/temurin21-binaries/releases)。

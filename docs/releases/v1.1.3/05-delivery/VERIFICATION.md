# v1.1.3 实际验证记录

启用日期：2026-10-26（Asia/Shanghai）。

本文件只记录 v1.1.3 启用后的代码、配置、数据、构建、部署和业务验收结果。创建版本目录本身没有修改业务代码、数据库、远程配置或运行环境，也不构成新的验证通过。

当前运行基线见 [v1.1.2 生产收尾记录](../../v1.1.2/05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。以下记录只代表 v1.1.3 本地增量及实际执行的验证，不改变远端运行状态。

## Linux dev 重新部署（2026-10-26）

- 来源与授权：用户明确要求重新部署 kd201 dev。发布源为已推送且工作区干净的 `dev@19fd9e1fe853da33205e9df7e4274e49030eab61`；该提交是 `codex/dev-1.0.7scan` 合入 dev 的 merge commit。prod 未操作。
- 首次失败与保护边界：既有 watcher 获取目标提交并完成定向检查、Admin development 构建及 Linux API 打包，但发布预检因服务器私有 `shared/.env` 缺少新版本必需的 `PHASH_RECOGNITION_BASE_URL` 明确失败。失败发生在数据库备份、migration、容器重建和 `current` 切换之前；旧 release `branch-dev-675034ac3de6-20261022101743` 继续运行，不能把首次尝试写成部署成功。
- 配置补齐：在 watcher 锁保护下先备份私有配置为 `.env.20261026-161724.pre-phash`，权限保持 `600`，随后只补充仓库合同规定的非敏感 origin `PHASH_RECOGNITION_BASE_URL=https://recognize.tcgcard.fun`。原 `VECTOR_RECOGNITION_BASE_URL`、旧兼容键及其他私有值未改写，密码、Secret 和完整 `.env` 未写入日志或仓库。
- 发布结果：使用 `TOCCARDS_FORCE_DEPLOY=1` 复用现有 watcher、发布锁、预检、备份和应用回退流程。预检回读独立 `toccards_test`、PostgreSQL 18、两套识别服务可达且 `pendingMigrations=[]`；最终 release 为 `branch-dev-19fd9e1fe853-20261026162214`，manifest、`current`、`shared/current-release`、`last-seen-sha` 和 `last-deployed-sha` 均与目标提交一致，失败标记已清除。后续 cron 回读为同一 SHA 且 `No new commit`。
- 数据与备份：发布前 custom-format 备份 `toccards-test-20261026-162217-before-branch-dev-19fd9e1fe853-20261026162214.dump` 为 1,136,064,025 字节；独立 `pg_restore --list` 退出 0 并输出 351 行，未执行恢复演练。migrate 容器 exited/0；ledger 保持 16 项，最新为 `0015_trial_conversion_status.sql`，本轮没有新增或执行 migration。
- 运行产物与容器：DB、API 均为 running/healthy，Web running，三者重启计数均为 0。release 与运行容器的 API `server.mjs` SHA-256 同为 `1dd2f32060f49f38a7b255af100c7a425609239003264bdcc96f1dce97e9cdb8`；Admin `index.html` SHA-256 同为 `6dcb9513f6a21f0abe77f689000bbaabd78d32ce1be67037cd72ef2459ef0f14`。
- HTTP 与识别健康：服务器本机及开发机分别回读 `http://192.168.50.201:8080/api/v1/health` 为 200／`status=ok`，Admin 首页为 200 且包含 `Kando Admin` 标题，未登录 `auth/me` 为 401。API 容器只读回查向量 health 为 512／cosine／Top 5，pHash health 为 768／euclidean／Top 5／`cards_phash`，两者均返回 200；最近十分钟 API 日志未匹配 error、fatal、uncaught 或 unhandled。
- 验收边界：本轮未使用真实账号登录 Admin，未发送真实或合成识别请求，未验证扫描写库、额度、OCR 命中率、真实图片准确率、旧 App 安装包、iOS／Android 真机、外部回调或数据库恢复；没有执行 Git 业务代码修改、prod 部署、商店发布或生产数据操作。health、产物哈希和容器状态不等于上述业务闭环已经验收。

## 扫描记录 OCR 文本展示（2026-10-26）

基线为 `codex/dev-1.0.7scan@8f4763a4567b30d0f9964bfb3b1054e4cd420b9f` 加本地未提交增量。pHash/OCR 扫描把经过请求校验的文本写入既有 `scan_record.system_result.ocr_text`：有文本保存字符串，OCR 成功但无文本保存空字符串，OCR 缺失及旧向量请求保存 `null`。没有新增数据库字段或 migration；既有 Admin 扫描详情 API 原样解析 `system_result`，旧记录缺少该键时仍可读取。

Admin “扫描详情 → 系统识别结果”在现有候选数量右侧增加“OCR 文本”。字符串原样展示；`null`、字段缺失及空字符串均展示为空白，不使用通用的 `-` 占位，也不改变列表、筛选、候选卡牌或其他 Admin 模块。

实际本地验证：

- Workers `src/scan/routes.test.ts` 与 `src/admin/routes.test.ts` 共 2 文件／76 项通过，覆盖 pHash 文本规范化后持久化、OCR 缺失／空字符串、旧向量 `null`、Admin 详情回传。
- Admin 全量 Node 测试 78 项通过，其中新增意图测试约束 OCR 字段位置与空白展示；Admin TypeScript 检查通过。
- Workers 首次 TypeScript 检查因 `buildSystemResult` 参数未显式包含运行时已排除的 `null` 类型而退出 2；仅修正参数类型为 `string | null | undefined` 后，同一类型检查退出 0，并重跑上述 76 项通过。
- Admin development 构建通过：Vite 转换 1,526 个模块并生成静态产物。本轮未启动远端环境、未执行 migration／数据库写入、Git commit／push 或 dev/prod 部署；未以真实 Admin 登录态和现有扫描记录进行浏览器交互验收。

## 扫描 pHash／OCR 选择性集成（2026-10-26）

本地基线为 `codex/dev-1.0.7scan@8d8d2bb03e31af63b01e7f3e519fd3e6970e009b` 加未提交增量，来源为 `dev-xiangyang@2c56e9f12901c33d22684c869ac29d42f3ee77c3`。本轮未执行整分支 merge，只移植扫描识别、直接平台桥、依赖、双识别服务配置／预检及对应文档；版本号、订阅、Admin、历史归档回写和其他无关业务未引入。

当前 App 使用 RTMDet 矫正卡面，并行计算 RGB pHash 与 ML Kit Latin OCR，OCR 经规则化后作为可选 `ocr_text`；体育卡发送 `card_type=1`。当前 App 与线上低版本 App 均调用 `POST /api/v1/scan/recognize`：服务端只收到 `r/g/b` 字段组时转发到 `PHASH_RECOGNITION_BASE_URL`，只收到 512 维 `vector` 时继续使用 `VECTOR_RECOGNITION`，两组同时出现或均缺失时返回 422。当前 Flutter 源码不再构建旧向量识别；插件向量入口、额度、R2、目录补全、扫描审计和 confirm 契约保持。PE-Core 转换产物保留在 source-only 模型目录，但已从 Android/iOS bundle 与原生运行入口移除。

实际本地验证：

- Flutter 扫描相关测试：`flutter test --no-pub ...` 退出 0，共 173 项；覆盖 pHash 位序／Pillow 对照、OCR 规则化、OCR 失败降级、RTMDet 裁剪、API multipart、Sports `card_type=1`、额度／重试及 Scan 页面共享流程。
- 模型 bundle 清理后重跑核心 Flutter 测试，退出 0，共 23 项；针对性 `flutter analyze --no-pub` 退出 0。首次 analyze 因 `scan_text_recognizer_native.dart` 的冗余 `dart:typed_data` import 退出 1，删除该 import 后以相同范围重跑通过。
- Workers 定向测试：`src/scan/routes.test.ts`、`src/legal/routes.test.ts`、`src/linux/config.test.ts` 共 3 文件／70 项通过；覆盖同一路径的旧向量与当前 pHash 分流、双字段歧义拒绝、OCR 缺失／空字符串、非法哈希、Sports 类型、配置缺失释放额度、目录／审计及隐私披露。
- 按“当前源码只构建新协议、服务端兼容生产旧包”的边界将新旧请求收敛到原 `/scan/recognize` 后，重跑 Flutter API／编排 25 项、Workers 上述 70 项及 Workers TypeScript 检查，均退出 0；未新增第二条识别路由。
- Workers TypeScript 检查通过；Linux bundle 与 preflight 的 Node 测试 11 项通过。随后 `deploy:dry-run:dev` 再运行 bundle 3 项并完成 Linux 打包，明确未连接 SSH、未执行 migration 或部署。
- `pnpm test:app-compatibility` 退出 0：当前 PostgreSQL API 合同 8/8、固定 App 1.0.4+161 与 1.0.5+163 各 24/24。该编排不覆盖扫描；旧向量扫描兼容证据来自本轮 Workers 路由测试，不能把固定合同结果扩展为旧包真机扫描通过。
- `pnpm lint` 通过。生产 Worker dry-run 通过，保留 `VECTOR_RECOGNITION` Service Binding，并加入 `PHASH_RECOGNITION_BASE_URL=https://recognize.tcgcard.fun`；没有上传、切流或修改远端配置。
- Android test Debug APK 在接口收敛后重新构建通过：`apps/flutter-app/build/app/outputs/flutter-apk/app-debug.apk`，256,916,611 字节，SHA-256 `23f4448a1904e6758a6bd403eb17a082e896fddde36d4470db4c23c269ff8c8e`。包内断言确认 PE-Core 资源不存在、RTMDet 与 ML Kit OCR 资源存在。构建仅出现仓库既有 Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0 的未来弃用警告，未在本任务升级工具链。

未验证与边界：

- Windows 无法执行 Xcode／CocoaPods／iOS 模拟器或真机构建；`Podfile.lock` 与 Xcode PE-Core 引用已按依赖和 bundle 变更更新，但 iOS 编译、签名、ML Kit Latin OCR、App Attest entitlement 和 IPA 解包仍待 macOS 补验。
- 未向 `recognize.tcgcard.fun` 发送真实或合成识别请求，也未实时回读其公开 health；preflight 使用受控测试服务验证 768/euclidean/Top 5/`cards_phash` 合同。真实图片准确率、OCR 命中率、弱网／超时、真机性能和外部服务当前状态未验。
- 未运行完整 Workers 默认测试、全仓 Flutter 测试、iOS 构建或真实旧 App 安装包扫描；未执行数据库 migration／业务写入、Git commit／push、dev/prod 部署或商店发布。

后续记录按时间倒序追加，并明确以下信息：

- 来源提交、工作区是否干净、目标环境与授权范围；
- 实际执行的检查、结果、失败、重试和未运行项；
- 本地、CI、dev、prod、商店与真机证据边界；
- 回退点、数据影响、外部平台影响及用户反馈是否由 Agent 独立复验。

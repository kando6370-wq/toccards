# v1.1.3 实际验证记录

启用日期：2026-10-26（Asia/Shanghai）。

本文件只记录 v1.1.3 启用后的代码、配置、数据、构建、部署和业务验收结果。创建版本目录本身没有修改业务代码、数据库、远程配置或运行环境，也不构成新的验证通过。

当前运行基线见 [v1.1.2 生产收尾记录](../../v1.1.2/05-delivery/VERIFICATION.md#prod-app-1-0-6-monthly-admission-20261026)。以下记录只代表 v1.1.3 本地增量及实际执行的验证，不改变远端运行状态。

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

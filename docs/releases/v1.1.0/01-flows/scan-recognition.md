# v1.1.0 扫描识别流程

## 1. 范围与结论

v1.1.0 的 Scan 识别已全面替换原有 RGB pHash 链路。当前实现复用相邻 `real_time_recognition` 项目的卡牌检测、卡面预处理、PE-Core-T16 向量化和 `recognize-vec` 向量检索契约，并保留本项目既有的 Scan Queue、Free/Premium Quota、Review、确认入库和审计记录。

本次替换是协议升级，不兼容旧 pHash：

- App 不再生成或提交 `r/g/b` pHash。
- Workers 不再接受旧 pHash 字段，也不提供旧协议或公网识别回退。
- `OCR_SERVICE_BASE_URL` 已删除，主 Worker 只通过 `VECTOR_RECOGNITION` Service Binding 调用内部 `recognize-vec` Worker。
- OpenCV 已从 Flutter 依赖和 Web 静态资源中移除；移动端卡面矫正使用系统图像 API。
- Android 使用模型专用的 ONNX Runtime 1.23.0 minimal AAR；iOS 使用系统 Core ML，不打包 ONNX Runtime。
- Web 当前不支持端侧检测和向量化，不能把 Web 构建视为 Scan 识别可用平台。

本次变更没有新增数据库 Schema 或 PostgreSQL migration。Quota、Scan Record、确认入库的数据结构保持不变，改变的是端侧识别输入、内部检索调用和审计算法标识。

## 2. 端到端流程

```text
相机/图库图片
  -> 原生解码、方向归一化、最长边缩放到 640
  -> RTMDet-Ins 检测卡牌框与 mask
  -> Dart 提取最大连通区域、凸包和四边形
  -> iOS Core Image / Android Bitmap Matrix 透视矫正
  -> 745x1043 JPEG（quality 85）+ 384x384 RGB
  -> PE-Core-T16 生成 512 维向量
  -> 可选的端侧卡号 OCR，用于候选消歧
  -> multipart 上传矫正卡面、向量和幂等 UUID
  -> Workers 预占 Free quota、将矫正图写入私有 R2
  -> Service Binding 仅向 recognize-vec 发送 {vector}
  -> PostgreSQL 目录解析、game_id 过滤、可选卡号重排
  -> 返回候选并结算 quota
  -> 用户 Review 后确认写入 Collection
```

具体步骤：

1. Flutter 从相机或图库取得原始图片；Gallery 仍可按现有 Queue 规则批量选择。
2. 平台图像层读取图片方向并输出最长边不超过 `640` 的 RGB 数据。
3. Flutter 共享识别层按 RTMDet-Ins 契约构造 `float32[1,3,640,640]` 输入，调用平台模型运行时。
4. Flutter 对得分达标的 mask 按置信度降序处理，取最大连通区域边界、凸包并逐步逼近四边形；无法得到四边形时使用最小面积矩形。卡牌面积不足或没有有效候选时显式失败。
5. 四角映射回原图；横向卡牌按边长关系旋转角点，使输出方向稳定。
6. iOS 使用 `CIPerspectiveCorrection`，Android 使用 `Matrix.setPolyToPoly` 和 `Canvas`，生成 `745x1043` 的矫正 JPEG，同时生成 `384x384` RGB 嵌入输入。
7. PE-Core-T16 输出 `float32[1,512]`；Flutter 校验维度、有限值和非零范数。
8. 既有 ML Kit 卡号读取器可从矫正卡面提取可选 `card_number`。它只参与本项目候选消歧，不替代向量检索，也不向识别 Worker 发送图片。
9. App 调用 `POST /api/v1/scan/recognize`，上传矫正后的 JPEG、512 维向量、平台信息和 `request_id`；`Idempotency-Key` 必须与该 UUID 相同。
10. Workers 验证身份、权益、图片和向量，在 R2/检索前预占 Free quota，将矫正卡面写入私有 R2，再通过内部 Service Binding 发送 `{ "vector": [...] }`。
11. `recognize-vec` 返回 `product_id` 和 `confidence` 候选。主 Worker 使用 PostgreSQL 目录解析候选，可按 `game_id` 排除其他游戏，并用可选卡号优先排列或补充同名同号候选。
12. Matched/No Match 消耗 Free quota；R2、内部检索或持久化等技术失败释放预占。用户在 Review 选择候选后，沿用 `/scan/:scan_id/confirm` 完成收藏入库。

## 3. 模型与预处理契约

| 阶段 | 当前契约 |
|---|---|
| 检测模型 | RTMDet-Ins Tiny Card，输入 `float32[1,3,640,640]` |
| 检测缩放 | 保持纵横比，最长边缩放至 `640`，左上对齐，未覆盖区域填充 `114` |
| 检测通道 | BGR、CHW |
| 检测归一化 | mean `[103.53, 116.28, 123.675]`；std `[57.375, 57.12, 58.395]` |
| 检测阈值 | score `0.35`；mask `0.5` |
| 最小卡牌面积 | 检测缩放后有效区域的 `0.025` |
| 几何处理 | 最大四连通区域 -> 凸包 -> 闭合多边形逼近；失败回退最小面积矩形 |
| 矫正输出 | `745x1043` JPEG，quality `85` |
| 向量模型 | PE-Core-T16，输入 `float32[1,3,384,384]`，输出 512 维 |
| 向量通道 | RGB、CHW |
| 向量归一化 | 每通道 `value / 127.5 - 1.0` |
| 服务端算法标识 | `pe-core-t16-384-cosine-v1` |

模型输出和向量协议是完整契约。任一平台改变尺寸、通道顺序、归一化、角点顺序或模型版本时，必须同时完成跨平台数值验证，并评估是否需要新的 `recognition_algorithm`；不能静默继续使用当前标识。

## 4. 平台实现

### 4.1 Flutter 共享层

- `scan_card_recognizer_native.dart` 编排检测、几何拟合、矫正、向量化和诊断数据。
- `scan_mask_geometry.dart` 使用纯 Dart 实现最大连通区域、凸包、四边形逼近、最小面积矩形和角点排序。
- `scan_model_runtime.dart` 与 `scan_native_image_processor.dart` 通过两个 Method Channel 调用平台能力。
- 同一 recognizer 实例串行处理图片，避免多个大模型推理同时占用移动端内存。
- Scan UI 上传和展示矫正后的卡面；失败、No Match、Quota 和 Waiting/Processing/Done 行为保持既有契约。

### 4.2 iOS

- 最低部署版本由 iOS 15.5 提升为 iOS 16.0。
- RTMDet-Ins 和 PE-Core-T16 均由系统 Core ML 运行。
- 图片解码、方向归一化、缩放和透视矫正使用 Core Image/UIImage；透视滤镜为 `CIPerspectiveCorrection`。
- App 包含 Core ML 模型，不包含 ONNX Runtime 或 OpenCV。

### 4.3 Android

- `minSdk` 保持 24。
- 图片方向归一化使用 `ExifInterface`，缩放和 RGB 提取使用 Android Bitmap，透视变换使用 `Matrix.setPolyToPoly` 和 `Canvas`。
- 模型运行使用本地 `onnxruntime-minimal-1.23.0.aar` 和 ORT 格式模型；最终 App 不打包源 `.onnx`。
- AAR 保留 `armeabi-v7a`、`arm64-v8a`、`x86`、`x86_64` 四个 ABI，CPU-only，采用 `MinSizeRel`、LTO、minimal build、reduced operator/type 配置，并关闭 exceptions、ML ops、contrib ops 和 KleidiAI。
- Release 构建启用默认优化 ProGuard 配置和项目 `proguard-rules.pro`。

### 4.4 Web

- `web/opencv.js`、`web/scan_opencv.js` 及入口脚本引用已删除。
- Web 条件实现会显式报告端侧识别不支持；当前不能在 Web 上执行该 Scan 流程。

## 5. API 与内部 Worker 契约

`POST /api/v1/scan/recognize` 使用 multipart：

| 字段 | 要求 |
|---|---|
| `image` | 端侧矫正后的卡面 JPEG，继续经过现有图片类型、尺寸和大小校验 |
| `vector` | JSON 数组，恰好 512 项；每项必须是有限数值，整个向量至少一个分量非零；JSON 最大 32 KiB |
| `request_id` | UUID，且必须等于请求头 `Idempotency-Key` |
| `game_id` | 可选正整数；主 Worker 在 PostgreSQL 目录层过滤，内部检索 Worker 与游戏无关 |
| `card_number` | 可选规范化卡号；用于目录候选重排或同名卡补充检索 |
| 其他审计字段 | `filename`、`platform`、`app_version` 及可选设备信息，沿用现有契约 |

内部调用固定为 Service Binding：

```json
{
  "vector": [0.0]
}
```

示例中的数组仅表示字段形状，真实请求必须包含 512 个合法分量。内部 Worker 返回候选数组，每项必须包含正整数 `product_id` 和 `0..100` 的有限 `confidence`。主 Worker 不向内部 Worker 发送图片、用户、Quota、`game_id` 或卡号信息。

dev/prod 均声明：

```toml
[[env.<environment>.services]]
binding = "VECTOR_RECOGNITION"
service = "recognize-vec"
```

缺少 binding 返回 `503 VECTOR_RECOGNITION_UNAVAILABLE`；内部调用、响应结构或候选解析失败最终返回 `502`，并释放 Free quota。不存在 `OCR_SERVICE_BASE_URL` 或 HTTP 公网回退。

## 6. 隐私、存储与审核文案

- 继续只上传端侧透视矫正后的卡面，不上传卡牌外围相机画面；该存储边界没有改变。
- 矫正卡面写入私有 R2，用于 Scan 记录、客服和识别质量审计。
- `recognize-vec` 只接收 512 维向量，不接收图片。
- Scan 审计记录保存算法标识、候选、内部 Worker 原始响应和矫正图片元数据。
- Privacy 页面和 App Review Notes 已从“RGB perceptual hashes / external recognition provider”更新为“512-dimensional image embedding / vector-recognition service”。
- 既有 Scan 图片和记录保留/账号删除规则未在本次修改中改变。

## 7. 依赖与兼容性变化

| 项目 | 变化 |
|---|---|
| `opencv_dart` / `dartcv4` | 从 Flutter manifests 和 lockfile 删除，根目录 OpenCV 构建 hook 删除 |
| Web OpenCV | `opencv.js`、`scan_opencv.js` 和 `index.html` 引用删除 |
| iOS Runtime | 使用系统 Core ML/Core Image；不新增第三方推理或图像处理库 |
| Android Runtime | 新增本地 ONNX Runtime 1.23.0 minimal AAR，不使用 Maven 完整预编译 AAR |
| Android 模型 | 打包两个 `.ort`，不打包 `.onnx` |
| iOS 模型 | 打包 RTMDet Core ML 模型和 PE-Core Core ML package |
| 识别协议 | 512 维向量；不兼容 `r/g/b` pHash |
| Worker 上游 | `VECTOR_RECOGNITION` Service Binding 替代 `OCR_SERVICE_BASE_URL` |
| 既有卡号读取 | `google_mlkit_text_recognition` 保留，只用于可选卡号消歧 |

## 8. 制品体积

以下是仓库中实际制品的精确字节数，不等同于 APK、AAB、IPA 下载大小或安装大小。

### 8.1 Android 当前新增输入

| 制品 | 字节 | MiB | SHA-256 |
|---|---:|---:|---|
| `rtmdet_ins_tiny_card_640_fp16.ort` | 12,352,384 | 11.78 | `9CF6389186A56FB08E26A52DF39CDBE551416556BF278D9BB8194F51D7225BEE` |
| `pe_core_t16_image_fp16.ort` | 13,355,544 | 12.74 | `35EC37B210DBF785B9FC6D298D4012372DC8C0F1A1182A1FFF051BFCF59ADCCD` |
| `onnxruntime-minimal-1.23.0.aar` | 3,754,131 | 3.58 | `6A98BCC4F8D9C18A84C1EFF495F0E83069F04765F657CBFC41865C04682593CA` |
| **合计** | **29,462,059** | **28.10** | - |

相对会话中曾评估的“官方完整 ORT AAR + 原始 ONNX”输入方案：

| 方案 | 字节 | MiB |
|---|---:|---:|
| 完整 AAR + ONNX | 54,933,658 | 52.39 |
| minimal AAR + ORT | 29,462,059 | 28.10 |
| **minimal 方案减少** | **25,471,599** | **24.29** |

该对比用于说明 Android minimal Runtime 的收益，不是相对改造前发布版的净变化。

### 8.2 iOS 当前新增模型源码

| 制品 | 字节 | MiB |
|---|---:|---:|
| RTMDet Core ML model | 11,897,458 | 11.35 |
| PE-Core Core ML package | 12,558,078 | 11.98 |
| **合计** | **24,455,536** | **23.32** |

iOS 推理和透视处理使用系统框架，因此新增第三方 Runtime 为 `0`。Xcode 编译 Core ML 后的模型大小可能与源码制品不同，最终仍需测量 release IPA/Archive。

### 8.3 已删除输入与净变化边界

| 删除项 | 字节 | MiB | 口径 |
|---|---:|---:|---|
| `web/opencv.js` | 10,964,309 | 10.46 | Git blob 精确大小 |
| `web/scan_opencv.js` | 11,598 | 0.01 | Git blob 精确大小 |
| **Web 合计减少** | **10,975,907** | **10.47** | 源码/静态资源精确值 |

旧 `opencv_dart 2.2.1+4` 在移动端构建时将 OpenCV 4.13.0 的 `core + imgproc + imgcodecs` 静态链接进 `libdartcv`。改造前的 Android `.so`、iOS framework、release AAB 和 IPA 不在当前仓库，因此移动端 OpenCV 的精确减少量无法从源码恢复。

相对改造前发布版只能给出以下制品公式：

```text
Android 净变化 = +28.10 MiB - 改造前 Android libdartcv 的最终打包体积
iOS 净变化     = +23.32 MiB - 改造前 iOS libdartcv 的最终打包体积
```

正式体积结论必须使用同一 Flutter、同一签名/混淆、同一 ABI split 和同一构建配置，对改造前后 release AAB/APK 与 IPA/Archive 做差。没有这组产物前，不得把上述公式写成最终 App 增减。

## 9. 验证证据与剩余边界

已完成：

- ONNX 与 ORT 使用确定性随机输入做数值对比：检测 `dets` 最大绝对误差 `7.6293945e-05`，`labels` 完全一致，`masks` 最大绝对误差 `1.4305115e-06`。
- PE-Core embedding 最大绝对误差 `8.6612999e-05`，余弦相似度 `0.9999998418`。
- Android 四个 ABI 的 native minimal Runtime 均构建成功。
- 每个 ABI 的上游 Android/Java Gradle 77 个 task 通过，包括测试和 lint。
- AAR 中 8 个 JNI 条目的 ABI、ELF machine 和跨包 SHA 已校验。
- ARM64 ELF `LOAD` 对齐为 `0x4000`，满足 16 KiB page size。
- Android AAR、ORT 模型 SHA-256 已校验；旧 Maven ORT 依赖、旧 Android `.onnx` 路径和旧 pHash 请求字段的残留检查通过。

未完成：

- 当前 Windows 环境没有 Flutter/Dart SDK，未运行 `flutter analyze`、Flutter tests 或 App release build。
- 未运行 iOS Xcode 编译、模拟器/真机 Core ML 与 Core Image 验证。
- 未运行 Android 真机模型加载、拍照方向、透视、推理耗时和内存验证。
- 未生成可与改造前同配置比较的 APK/AAB/IPA，因此移动端最终下载/安装体积尚未量化。
- 未进行真实 `recognize-vec` dev Service Binding 端到端、Sandbox/TestFlight、弱网、批量图库和真实卡牌集准确率验收。

## 10. 变更文件与维护入口

### 10.1 Flutter 识别与 UI 接入

- 新增 `scan_card_recognizer.dart`、`scan_card_recognizer_contract.dart`、`scan_card_recognizer_native.dart` 和 `scan_card_recognizer_unsupported.dart`，定义端侧识别接口、原生实现和不支持平台的显式失败。
- 新增 `scan_mask_geometry.dart`、`scan_model_runtime.dart` 和 `scan_native_image_processor.dart`，分别负责共享几何、模型 Method Channel 和图片 Method Channel。
- `scan_result_source.dart` 从 `ScanImageHasher` 切换到 `ScanCardRecognizer`，将矫正卡面交给既有卡号读取器并上传 embedding；不再接收旧手工 recognition crop。
- `scan_api_client.dart` 将 multipart 的 `r/g/b` 改为 JSON `vector`，图片改用 recognizer 返回的矫正 JPEG。
- `scan_page.dart` 和相关结果对象不再传递旧 crop 坐标；Queue、Quota 和 Review 状态机继续使用既有实现。
- 删除 `scan_image_hasher*.dart`、`scan_phash.dart`、`scan_image_hasher_test.dart` 和 `scan_phash_test.dart`。

### 10.2 iOS

- `AppDelegate.swift` 新增原生图片解码、方向归一化、RGB 提取、`CIPerspectiveCorrection` 和 JPEG 输出通道。
- 新增 `ScanModelRuntime.swift` 以及 `Runner/Models/` 下的 RTMDet 和 PE-Core Core ML 制品。
- `Runner.xcodeproj/project.pbxproj` 注册 Swift Runtime 与模型，并将各构建配置 deployment target 更新为 16.0；`Podfile` 同步为 iOS 16.0。
- `tool/models/export_rtmdet_coreml.py` 保留 RTMDet Core ML 导出工具。

### 10.3 Android

- `MainActivity.kt` 新增 EXIF 方向归一化、Bitmap RGB 处理、四点透视矫正和 JPEG 输出通道。
- 新增 `ScanModelRuntime.kt`，通过本地 ONNX Runtime 执行两个 ORT 模型并缓存 Session。
- `android/app/build.gradle.kts` 引入本地 minimal AAR，并为 release 配置优化 ProGuard；新增 `proguard-rules.pro`。
- `android/app/libs/` 新增 minimal AAR；`android/app/src/main/assets/models/` 新增两个 `.ort` 模型。
- `tool/onnxruntime/` 新增 ONNX -> ORT 转换、数值验证、operator/type 配置、AAR 构建脚本和构建参数。

### 10.4 依赖、Web 与平台元数据

- `apps/flutter-app/pubspec.yaml`、根 `pubspec.yaml` 和 `pubspec.lock` 删除 `opencv_dart`、`dartcv4` 及其构建 hook。
- 删除 `web/opencv.js` 和 `web/scan_opencv.js`，`web/index.html` 删除加载入口。
- `fastlane/metadata/review_information/notes.txt` 将审核说明从 perceptual hashes 更新为 512 维 embedding。
- `assets/models/README.md` 和 `assets/models/licenses/` 保存模型来源、许可证、第三方声明与转换输入清单；源 ONNX 不打包到 App。

### 10.5 Workers、隐私与测试

- `src/scan/routes.ts` 校验 512 维向量，通过 `VECTOR_RECOGNITION` 调用内部 Worker，解析/过滤/重排候选并写入新算法标识。
- `src/env.ts` 和 `wrangler.toml` 删除 `OCR_SERVICE_BASE_URL`，新增 dev/prod `VECTOR_RECOGNITION` binding。
- `src/legal/routes.ts` 与 App Review Notes 同步更新 embedding、矫正卡面和内部识别服务表述。
- `src/scan/routes.test.ts` 覆盖向量转发、向量校验、旧 pHash 拒绝、游戏过滤、卡号消歧、binding 失败和既有 Quota/R2 补偿行为；`src/legal/routes.test.ts` 保护新隐私文案。
- Flutter 侧更新 `scan_api_client_test.dart`、`scan_result_source_test.dart` 和 `scan_page_test.dart`，新增 `scan_mask_geometry_test.dart`。

### 10.6 版本文档

- `business-context.md`、`architecture.md`、`tech-stack.md`、`contract-changes.md`、`entitlement-contract.md`、`development-plan.md` 和 `traceability-matrix.md` 均已从 OCR/pHash 口径切换为当前向量识别事实。
- 本文是端侧算法、平台边界、内部检索、体积和验证证据的详细真源；其他文档保持摘要并链接本文。

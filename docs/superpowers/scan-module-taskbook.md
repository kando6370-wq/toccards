# scan 扫描模块开发任务书

> 目标：把「拍照识卡」做成**真正可用**，并**贴合 Figma**。
> 关联：`docs/superpowers/figma-fidelity-handoff.md`（总交接手册）
> Figma 设计源：section `131:19436`「扫描页」（19 屏），文件 `DjacfTioobtRy59SnqH7SY`
> 生成时间：2026-07-13

---

## 0. 结论先行：不是从零建，是「把已有原型接上真数据」

⚠️ **纠正一个此前的误判**：scan 并非"只有占位页"。实际上：

- ✅ **UI 原型已存在**：`apps/flutter-app/lib/features/scan/scan_page.dart`（1055 行）已实现相机取景、拍照/相册/完成控件、扫描结果 5 态列表、Review 匹配页（图片对比 + 候选 + 加入这张/全部）。
- ✅ **后端对接层已存在**：`apps/flutter-app/lib/shared/scan/scan_api_client.dart` 的 `ScanApiClient.recognizeImage()` 已能 POST 图片到 `/scan/recognize` 并解析结果。
- ✅ **Provider 已存在**：`scan_providers.dart` 暴露 `scanApiClientProvider`。
- ✅ **路由已注册**：`/scan`（`lib/app/router.dart`）。

**真实缺口** = 现有 UI 全是**假数据模拟**，没接真相机、没调真接口、没真入库。把这三处接上 + 按 Figma 精修，就完工。

---

## 1. 现状盘点（代码事实）

### 1.1 `scan_page.dart`（UI 原型，但全假）
- 相机背景 `_CameraBackdrop` 是 `CustomPainter` **画出来的假相机**（矩形+条纹），非真实预览。
- `_startPhotoScan()` 用本地 `Timer(1s)` **硬编码**返回 `Charizard ex` / `Mega Lucario ex`，第 2 次故意 `failed`，相册固定 `noMatch` —— 纯 mock。
- 所有状态在 `StatefulWidget` 的 `setState` 本地态里（`_ScanItem` / `_ScanItemStatus`），**未用 Riverpod**。
- 颜色**硬编码**（如 `0xFF10100B`/`0xFFF0FE6F`），**未走 `KandoColors`**。
- Review 的「Add this / Add all」只把本地状态改成 `added`，**没有真正入库到 collection**。

### 1.2 `scan_api_client.dart`（真实可用）
```dart
abstract interface class ScanApi {
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required Uint8List imageBytes,
    required String fileName,
    required String platform,     // ios / android
    required String appVersion,
    String? deviceModel,
    String? osVersion,
  });
}
// 返回 ScanRecognitionDto { scanId, recognitionStatus, results: [
//   ScanResultDto { index, matched, candidates: [
//     ScanCandidateDto { cardRef, name, setCode?, cardNumber?, confidence? } ] } ] }
// 端点：POST /scan/recognize（multipart：image + platform + app_version + device_model? + os_version?）
// receiveTimeout 已设 120s
```

### 1.3 依赖现状（`pubspec.yaml`）
已有：`flutter_riverpod` `dio` `package_info_plus`（可取 appVersion）`go_router`。
**缺**：相机/图库采集插件（`camera` 或 `image_picker`）。

---

## 2. 真实缺口（4 块）

| 编号 | 缺口 | 说明 |
|---|---|---|
| **G1** | 真相机采集 | 引 `image_picker`（最简）或 `camera`（要实时预览取景框才用）；拍照/选图得到 `Uint8List` |
| **G2** | Riverpod controller | 把本地 mock 状态机迁到 `ScanController`，调 `scanApiClientProvider.recognizeImage(...)`，管理多张扫描 item 的异步状态（scanning→matched/failed/noMatch）|
| **G3** | 真入库 collection | Review 的「Add this/Add all」调 **collect 快捷端点**（M3-6 已存在），用 `candidate.cardRef` + 采集参数（文件夹/品相/finish），替换假的本地 `added` |
| **G4** | Figma 保真 | 按 section `131:19436` 对照精修；硬编码颜色改走 `KandoColors`；间距/文案/19 屏细节对齐 |

---

## 3. 拆分任务（可直接指派，每条带验收 AC）

> ⚠️ **前置确认（做之前先查）**：后端 `POST /scan/recognize` 是否已实现并上线？在 `apps/workers-api/src/` 搜索该路由。若**未实现或需改 D1/schema**，按 `CLAUDE.md` 数据库 gate **必须先通知用户确认**，不得擅自改表。

### T1 · 采集插件与权限
- `pubspec.yaml` 加 `image_picker`（或 `camera`）。
- iOS：`ios/Runner/Info.plist` 加 `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription`。
- Android：`android/.../AndroidManifest.xml` 相机权限（image_picker 通常免声明，camera 需要）。
- **AC**：真机能拍照/选图并拿到非空 `Uint8List`。

### T2 · ScanController + 状态模型（可先做、可先单测）
- 新建 `scan_controller.dart` + `scan_models.dart`（把 `_ScanItem/_ScanItemStatus` 提为公开、Riverpod 化）。
- controller 注入 `scanApiClientProvider`、auth session provider（`features/auth`）、`package_info_plus` 的 appVersion、platform/device。
- 实现异步状态机：加入一张 → `scanning` →（调 recognizeImage）→ 按 `matched/candidates` 落 `matched`，无候选 `noMatch`，异常 `failed`；支持重试/删除。
- **AC**：用 fake `ScanApi` 单测覆盖 matched / noMatch / failed / 超时 四条路径，状态流转正确。（对齐仓库测试风格：测意图，见 `packages/auth-core/src/index.test.ts`）

### T3 · UI 接线
- `scan_page.dart` 去掉 `Timer` mock 与 `_CameraBackdrop` 假相机，改为真相机预览/选图 + `ScanController`。
- **保留现有布局结构与交互**（取景框、结果卡、Review 页），只替换数据来源。
- **AC**：拍照 → loading → 结果来自真接口；多张连拍互不干扰。

### T4 · 入库 collection
- Review「Add this / Add all」调 collect 端点（确认 `lib/features/collection/collection_repository.dart` 或 `lib/shared/portfolio/*` 里的方法名）；传 `cardRef` + 目标文件夹 + 品相/finish。
- 成功后标 `added` + 全局 toast（用 `lib/shared/ui/toast.dart`）。
- **AC**：加入后切到 Collection 页能看到该卡。

### T5 · Figma 保真精修
- 对照 section `131:19436` 的 19 屏，硬编码色改走 `KandoColors`，对齐间距/字重/文案（取景框 accent `#F0FE6F` 已对）。
- **AC**：逐屏对照通过（人眼）。

### T6 · 失败/边界
- 无网络、识别超时（120s）、无匹配、权限被拒 → 各自明确 UI，不崩溃。
- **AC**：断网/拒权限下有清晰提示与恢复路径。

---

## 4. 关键依赖清单（接手直接查这些符号）

| 需要 | 位置 |
|---|---|
| 识别接口 | `lib/shared/scan/scan_api_client.dart` → `ScanApi.recognizeImage` |
| Provider | `lib/shared/scan/scan_providers.dart` → `scanApiClientProvider` |
| Auth session | `lib/features/auth/`（auth_repository / providers）|
| 入库 collect | `lib/features/collection/collection_repository.dart` + M3-6 后端 collect 端点 |
| Toast | `lib/shared/ui/toast.dart` |
| appVersion | `package_info_plus`（已在依赖）|
| 设计 tokens | `lib/shared/ui/kando_style.dart` → `KandoColors` |

---

## 5. 完成门（交付前必过）

```bash
cd apps/flutter-app
flutter analyze          # 0 error
flutter test             # 全绿，含 T2 controller 单测
# 真机冒烟：拍照 → 识别 → 加入 → 到 Collection 可见
```
未过之前不得标 completed（`CLAUDE.md` 规则十二 / Completion gate）。

---

## 6. 里程碑归属建议

建议作为新里程碑 **M9 扫描识卡**（或 `dev-plan.md` 中 M4-8「Scan Tab 占位页」的升级项）。执行时任务标题带前缀（如 `[M9-1]`）以更新 `execution-status.md` 计划覆盖层；否则只记执行日志。

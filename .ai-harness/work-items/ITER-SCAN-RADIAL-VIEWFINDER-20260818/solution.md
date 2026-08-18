# 技术方案

## 范围

- 仅修改 `scan_page.dart` 的相机画面绘制层。
- 初始、拍照、识别、结果揭示共用同一个径向遮罩。
- 保留现有状态机、500ms 捕获动画、扫描线条件、相机、裁剪、OCR、额度、队列和 Review 逻辑。

## 绘制方案

1. 以 `_viewfinderRect(size).center` 为径向渐变中心。
2. 使用现有识别态屏幕边缘颜色 `Color(0xD90D0F08)`，透明度从中心向屏幕边缘递增。
3. 通过 even-odd 路径裁掉完整定位框区域，使框内不绘制任何遮罩并保持原相机画面。
4. 删除框外均匀 `Color(0x66000000)` 蒙层。
5. 删除 `_ViewfinderPainter` 的白色柔光分支，黄色四角始终按原样绘制。
6. 保留现有 Widget key 或提供等价统一 key，测试分别覆盖初始、拍照、识别和揭示状态。

## 兼容与回滚

- Flutter 共享 UI 同时作用于 iOS 和 Android，无平台分支。
- 不涉及 API、数据、Schema、权限或依赖。
- 回滚仅需恢复 painter 与对应 Golden/Widget 断言。

## 验证

- Widget 像素检查：定位框中心像素透明、框外像素随半径加深、各状态效果一致、无白色柔光。
- 现有扫描线、定位框/裁剪一致性测试。
- 4 个扫描状态 Golden、受影响 `flutter analyze`、`dart format`、`git diff --check`。

# 扫描识别阶段闪烁修复方案

## 根因

径向遮罩的视觉内容在拍照、识别和揭示阶段相同，但当前 `CustomPaint` 使用随状态变化的 key。进入 `recognizing` 或 `revealing` 时，Flutter 会替换可见遮罩的 Element 与 RenderObject，使相机预览上方的整层在状态边界重新合成，产生一次可见闪烁。

## 修复

- 可见径向遮罩使用固定 key，并在所有扫描状态间复用同一个 `CustomPaint` RenderObject。
- 原状态 key 改为不参与绘制的零尺寸标记，保留现有状态测试能力。
- 不修改相机、拍照、500ms 扫描线、识别时间线、裁剪、额度、订阅、队列或结果逻辑。

## 验证

- Widget 测试证明进入识别和揭示阶段前后，可见遮罩 RenderObject 身份保持不变。
- 复跑扫描线、识别、揭示、Pro 不扣免费次数及相关 Golden。
- 运行受影响静态分析、格式化和 `git diff --check`。

## 平台与数据

Flutter 公共绘制层同时适用于 iOS 与 Android；无平台接口差异。无数据库、API、持久化或依赖影响。

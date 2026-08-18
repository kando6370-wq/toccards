# 扫描定位框下移 30px 技术设计

## 目标

- 将扫描页定位框顶部从 `163px` 调整为 `193px`。
- 保持定位框宽高、颜色、控件、状态机、扫描队列、额度、权限、API 和 Review 行为不变。
- 继续使用同一个 `_viewfinderTop` 驱动可见定位框、扫描动画覆盖层与相机识别裁剪，避免视觉框和识别区域错位。

## 平台与设计边界

- iOS、Android 均复用同一 Flutter 布局常量，无平台分支和原生配置变化。
- 本次位置来自用户明确指令，不新增或修改 Figma 节点；其余视觉继续以现有扫描页面和 UI 设计系统为基线。
- 无 API、Schema、数据库、迁移、权限或部署影响。

## 验证

- Widget 断言验证 390x844 与窄屏下定位框和识别 crop 同步下移 30px。
- 更新并检查受影响的当前扫描 golden：Before、Scanning、Recognizing、Revealing；Review 不受影响。
- 运行扫描页 Widget 测试、Flutter analyze、`git diff --check`。

## 回滚

- 将 `_viewfinderTop` 从 `193.0` 恢复为 `163.0`，并恢复对应测试断言和 golden。

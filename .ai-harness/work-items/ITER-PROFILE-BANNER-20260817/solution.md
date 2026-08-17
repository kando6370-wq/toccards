# Profile Banner Figma 同步方案

## 现状与目标

- 当前 Profile Free 状态 Banner 已使用 350x152 基准、12px 圆角、品牌边框、文字与 36px CTA，并通过 `profileSubscriptionLocation` 打开完整订阅页。
- Figma `2210:17750` 保留上述容器与内容规格，主要可见变化是背景从金色宝箱改为彩色卡牌增长插画。
- Figma 导出的按钮左右 SVG 与按钮背景同色，在节点截图中不可见；本次不新增不可见图层。

## 实现

- 用 Figma 提供的 PNG 替换 `apps/flutter-app/assets/profile/upgrade_to_pro.png`。
- 仅在 `_UpgradeBanner` 的背景图片层同步 Figma 的放大及右对齐裁切；保留现有响应式宽度、文字、按钮、点击与 Premium 三态显隐逻辑。
- 不引入依赖，不修改路由、API、Schema、配置或平台原生代码。

## 兼容与验证

- 使用 Flutter 共享 `Image.asset` 渲染，iOS 与 Android 语义一致。
- 更新 Profile Banner 定向 Golden，并回归 Free 显示/跳转与 Premium 隐藏。
- 运行 `flutter analyze`、Android debug build，并在 iPhone 17 模拟器视觉确认。
- 文档更新 `docs/releases/v1.1.0/05-delivery/development-plan.md` 的 Profile 入口实现记录。

## 风险与回滚

- 风险仅限资源体积、裁切位置和不同屏宽视觉；通过 350px Golden、430px 响应式断言及双端构建覆盖。
- 回滚为恢复原 PNG 与背景图片裁切参数，不涉及数据迁移。

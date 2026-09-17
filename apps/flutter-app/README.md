# Flutter App Skeleton

这是从 Kando Flutter 客户端提取的跨 iOS、Android 和 Web 的 App 骨架。

## 保留能力

- Flutter、Dart workspace、Riverpod、GoRouter 和 Dio
- 环境配置与可注入的 `API_BASE_URL`
- 匿名/用户会话、Token 刷新、认证存储和 OAuth 适配
- Firebase、Mixpanel、API 请求日志和测试环境调试覆盖层
- 可复用的通用订阅包位于 `dart-packages/subscription-core`
- `shared/ui/kando_bottom_sheet_page.dart` 提供 GoRouter 页面使用的底部弹层容器，默认显示独立的 32px 顶部拖拽横条区域；长内容只在下方区域滚动
- `shared/ui/toast.dart` 提供顶部轻提示，支持失败、网络、成功、警告和信息类型
- `shared/ui/load_state.dart` 提供通用失败态刷新卡片 `KandoFailureBlock`，由调用方提供刷新回调，可嵌入页面或弹层
- `shared/ui/kando_modal.dart` 提供普通/强制应用更新弹窗及结果返回；检查版本和打开商店由调用方实现

当前根路由是空白启动路由，不包含原 Card AI 页面、领域模型或页面素材。原底部 SnackBar 和业务专用弹层未恢复。

## 本地运行

从仓库根目录执行：

```powershell
pnpm app:chrome:dev
```

默认 API 地址为 `http://localhost:8787/api/v1`，可通过
`--dart-define=API_BASE_URL=...` 或配置文件覆盖。

## 验证

```powershell
flutter analyze
flutter test --dart-define=APP_ENV=test
```

新的 App 名称、Bundle ID、Firebase 配置、商店发布配置和后端路由需要在产品定义后补充，不应继续复用 Card AI 的线上身份。

当前工作环境为 Windows，未运行 CocoaPods；iOS 的 `Podfile.lock` 需要在 macOS 上执行
`pod install` 后再提交更新。

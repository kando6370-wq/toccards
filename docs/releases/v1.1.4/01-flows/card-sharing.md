# Android 卡牌海报分享

2026-11-17 产品确认：Android 分享改为生成海报图片，海报底部放二维码；界面只提供“分享海报”和“复制链接”两个操作。iOS 保留原有卡牌网页 URI 分享，不增加海报预览或生成步骤。Profile 的应用推荐分享与服务端公开分享页保持原规则。

## 用户流程与内容

1. Android 在收藏卡牌详情点击 Share，打开 App 内海报预览。
2. 海报在本地生成，包含当前卡图、名称、系列、客户端当前显示的市场价格，以及底部二维码；输出为 `1080×1980` PNG。价格直接沿用页面显示值，不新增价格查询或币种换算。
3. `SHARE POSTER` 在生成成功后启用，确认后通过系统分享面板发送这张 PNG，不附带卡名／价格／链接的纯文本正文。
4. `COPY LINK` 只复制完整卡牌分享 URL，不拼接卡名、价格或介绍；复制后提示成功并保留预览。海报仍在生成或生成失败时，也可以复制链接。
5. 关闭图标、系统返回键或点击遮罩只取消预览，不打开系统分享面板，不发送内容。

二维码编码值与复制链接使用同一个 `Uri`，指向现有 `/share/cards/:card_ref` 网页。test 包继续使用 Linux dev 内网分享地址，只有能访问该网络的设备才能打开；production 优先使用有效服务端配置，离线时使用生产兜底地址。测试分享不会因复制来的生产配置而跳到生产环境。

## 实现与失败处理

- [分享入口](../../../../apps/flutter-app/lib/features/card_detail/card_detail_page.dart)仅为 Android 传入预览 presenter；iOS 继续直接调用原 URI 分享路径。异步返回后核对上下文有效性，已有弹层时不重复打开。
- [分享动作](../../../../apps/flutter-app/lib/features/card_detail/card_detail_actions.dart)解析现有环境分享 URL，复用公开卡图下载，通过异步 poster future 驱动预览，只有用户确认后才调用 `share_plus` 的 `files` 分享 PNG。iOS 不下载卡图、不生成海报、不打开 Android 预览。
- [海报渲染](../../../../apps/flutter-app/lib/features/card_detail/card_share_poster.dart)使用 Flutter Canvas、现有字体／颜色与 `qr_flutter 4.1.0`，二维码在本地编码，保留白色 quiet zone，不调用外部二维码服务或上传海报。图片、编解码器与 Picture 资源均按生命周期释放。
- [预览弹层](../../../../apps/flutter-app/lib/features/card_detail/card_share_preview.dart)复用现有弹层、按钮和提示；生成中显示加载状态，失败时显示错误并禁用图片分享，复制链接仍可用。小屏和大字体可滚动操作。
- 卡图下载、解码或海报生成错误会被明确记录和展示；不静默改成 TXT 分享。用户取消后，仍在完成的生成任务不会打开系统面板或抛出无人接收的异步错误。系统图片分享失败继续交给页面原有失败提示。

Android 原生 App 仅在确认分享后才把 PNG 写入私有缓存中的固定源文件 `cache/card-ai-card.png`，并传文件路径给 `share_plus`。原生插件先复制到 `cache/share_plus/` 供 FileProvider 和接收应用读取；分享调用返回（含取消）或抛错后，App 只清理源文件，不提前删除接收方副本。若 App 进程在清理前被杀，下一次分享覆盖同一路径，不新增源文件。插件副本仍按既有策略在下一次调用插件分享时清理，不扫描或批量删除旧版随机目录。Web、iOS 和 Profile 的分享路径不变。不新增原生分享桥或权限。

## 验证与交付边界

验证使用仓库隔离的 Flutter 3.47.9／Dart 3.13.7、JDK 21.0.13+9，以及 Node 22.23.4／pnpm 11.28.10。

| 检查 | 结果 |
|---|---|
| `flutter test --no-pub --dart-define=APP_ENV=test test/card_detail_actions_test.dart test/profile_actions_test.dart test/widget/card_detail_page_test.dart test/card_share_poster_test.dart --reporter expanded` | 121／121 通过；覆盖海报文件负载、二维码 URL 同源、纯 URL 复制、取消／失败、快速连点、长金额、小屏与 iOS 保留路径。 |
| `flutter test --no-pub --dart-define=APP_ENV=production test/card_detail_actions_test.dart --reporter expanded` | 15／15 通过，包含生产 URL 配置与离线兜底。 |
| `flutter analyze --no-pub` | 0 issues。 |
| 根 `pnpm lint`／`pnpm type-check` | 通过；类型任务 9／9 成功，其中 7 项命中已有缓存。 |
| `gradlew :app:assembleDebug -Pkotlin.incremental=false` | 成功；使用合规 JDK，未修改既有 Gradle／SDK 约束。 |
| 独立 Code Review | 通过，无待处理代码问题。 |

审查返工均有先失败证据：旧金额窄列的长金额像素断言为 0，改为独立全宽金额行后通过；快速双击先产生两份海报任务，按既有 Profile 动作规范合并 Android 进行中任务后只生成一份，关闭后可重新发起。返工后的对应测试、组合回归与独立审查均重新完成。

已用独立 ZXing-C++ 解码本地渲染的 PNG，尺寸为 `1080×1980`，解码值精确为测试输入 `https://api.tcgcard.fun/share/cards/560537`。该输入只是渲染测试数据，不替代 test／production 的实际环境选择或链接可达性验收。

本次 Debug 测试包为 `com.kando.kandoApp.beta`／`1.0.7 (214)`，264,594,542 字节，SHA-256 `5733bb4c63b52e254f2250d0d2d6b5a4a08632a5e66c3f9225c832a645f407a8`。由 `codex/fixbug-andriod@c8b8caae` 加本轮未提交改动构建，不标记为干净提交产物；冻结副本为任务产物目录中的 `CardAI-Android-SharePoster-Test-1.0.7-214.apk`，不推进正式发布计数或商店状态。

2026-11-17 真机验收中断检查点（历史）：当时已连接荣耀 YOK_AN10／Android 12（API 31），在 dev 测试账号从 0 张收藏临时添加了 1 张 Switch（560537）用于进入分享入口；海报版完成构建时无线 ADB 断开，未能安装海报版或完成实际分享／复制验收，临时收藏也未清理。该中断状态由下方 2026-11-18 续验结果更新；前期文本缩略图试验不作为最终海报版真机通过证据。

未运行 iOS 新制品构建／真机（当前为 Windows 主机，iOS 保留路径由源码、Widget 与动作测试保护）、正式 AAB／Play 发布或全 App／后端完整测试；本次本地回归限定于直接受影响的分享、预览、海报和 Card Detail 调用链。外部扫码打开实际环境网页与最终接收应用处理图片也未因本地 PNG 解码自动视为通过。

本地修改与 Debug 真机测试不代表正式 AAB、Play 分发或 iOS 新制品已经发布。Android 方案源于荣耀 Android 12 不显示标准文本缩略图的真机观察，最终以明确选择的海报图片分享实现，不保留试验用的文本预览原生桥。

### 荣耀真机续验（2026-11-18）

按用户提供的新无线调试地址连接同一荣耀设备，成功覆盖安装上方 SHA-256 为 `5733bb4c…f407a8` 的冻结 Debug APK。今日未重建该制品；当前 HEAD 为 `5fcedfd6`，相对原构建基线只增加法律／官网提交，Flutter、Android、Dart 依赖与移动工具链的已提交差异为空，构建来源仍按 `c8b8caae + 未提交海报改动` 记录。上表本地测试／构建／审查证据仍属于 2026-11-17，不重复记为今日重跑。

| 真机检查 | 观察结果 |
|---|---|
| 海报预览 | Switch 实际卡图、完整名称、系列、`$0.27` 与底部二维码正确显示，生成成功后可点击 `SHARE POSTER`。 |
| 复制链接 | 点击 `COPY LINK` 出现 `Link copied.`，预览保留；随后在 App 搜索框通过原生 Paste 粘贴，实读内容精确为 `http://192.168.50.201:8080/share/cards/560537`，45 字符，无卡名／价格／介绍。验证后已清空测试搜索输入。 |
| 图片分享 | 确认后打开荣耀 `HwChooserActivity`；从实际文件分享缓存读取到 `card-ai-card.png`，789,807 字节、PNG、`1080×1980`。没有选择联系人或接收应用发送。 |
| 实机海报二维码 | 独立 ZXing-C++ 解码手机实际导出的 PNG，精确得到同一测试 URL；该 PNG 的 SHA-256 为 `44293a3e6fa1752fe04f9cb7e81a62b3e1a329d94c0c5bae459c74cd35f3fee2`。 |
| 返回取消 | Android 系统返回键关闭预览，回到 Card Detail 的 Share 入口，没有进入系统分享面板。 |
| 临时收藏清理 | 通过单项 Remove 确认删除本任务创建的 Switch，曾独立观察到 Portfolio `0 cards`／`$0.00`。后续冷启动检查出现另一张 Quaxly，Switch 已不存在；保留该后续卡牌，没有清空整个收藏。 |
| 临时资源清理 | 旧 instrumentation 测试包已卸载，旧原生预览目录与临时 PNG 文件已清理并回查无残留；临时设备截图／UI dump 和主机旧测试 APK 也已清理。冻结 APK 与实机海报证据保留在任务产物目录。 |

本轮完成该冻结测试包在此荣耀 Android 12 设备上的预览、PNG 交付系统、二维码解码、纯 URL 剪贴板与取消验证。跨设备相机扫码打开实际网页、具体接收应用中的发送／展示、生产 URL、正式 AAB／Play 分发和 iOS 新制品仍不在本轮通过范围内。

### 分享落地页可见品牌文字（2026-11-18）

根据用户 Quaxly 分享页截图的两个红框，服务端 HTML 顶部品牌由 `KANDO` 改为 `CARD AI`，按钮由 `Open in Kando` 改为 `Open in CARD AI`。只修改这两处可见文案；卡牌内容、二维码／分享 URL、`kando://` App 唤起协议、两端商店选择和样式沿用现有逻辑，Android 与 iOS 使用同一份 HTML。

回归先失败：新增可见品牌断言在旧模板上失败；替换文案后 `pnpm --filter @kando/workers-api test src/card-share/routes.test.ts --maxWorkers=1` 为 2／2 通过，Workers `type-check` 通过。独立 Code Review 通过，无待处理发现。本轮未发布服务端，截图所对应的远端网页需部署后才会显示新文案。

### Android 海报源文件清理（2026-11-18）

- 根因与先失败证据：锁定的 `share_plus 12.0.2` 将内存文件写入缓存根目录下的随机目录，原生只清理 `share_plus/` 中的副本。新增回归在旧代码首次分享后发现多余目录；荣耀 YOK_AN10／Android 12 上，旧测试包对同一张 Quaxly 海报再次打开并取消分享后，随机源文件从 2 份增加到 3 份。
- 修复验证：Flutter 3.47.9／Dart 3.13.7 下，`APP_ENV=test` 的 `card_detail_actions`、`profile_actions`、`card_detail_page` 和 `card_share_poster` 测试 122／122 通过；`APP_ENV=production` 的 `card_detail_actions` 测试 16／16 通过；`flutter analyze --no-pub` 无问题。测试覆盖接收方选择、系统取消、插件异常、取消预览和 iOS 原 URI 路径。
- Android 复验：Temurin JDK 21.0.13+9 下 `:app:assembleDebug` 通过；以 `db7df72b` 加本轮未提交修复构建的 `com.kando.kandoApp.beta`／`1.0.7 (214)` 测试包（SHA-256 `8ce81a9099c3d91d49d431b7e81a9872648f56d3079179d39888e83c9a716c14`）覆盖安装到同一台设备。连续三次对同一张卡打开并取消系统分享，固定源文件每次返回后均不存在，无新增随机源目录，FileProvider 副本保留且 PNG 文件头正确。随后仅手工清理测试包内确认的三份旧源 PNG 及空目录，回查仅剩接收副本，其他缓存未动。
- 本地 Code Review 无阻塞项：核对现有连点保护、返回与异常清理、插件复制时序及 iOS／Profile 分支。未向第三方应用实际发送，未构建或实测 iOS 新包，未发布正式 Android 制品；其他安装上的旧缓存不由此次源码批量清理。

### 分享落地页商店跳转修复（2026-11-18）

- 生产 `/share/cards/560537` 的缓存 MISS 响应仍给 Android 用户提供 YouTube 占位链接，而公共 App 配置已返回 Card AI 的 Google Play 地址。旧分享查询读取无环境的版本键和全局备用地址，忽略了后台已保存的分环境配置。修复前以本地 PostgreSQL 回归复现：期望 `com.cardai.tcg`，实际为 `com.google.android.youtube`。
- 分享页按服务端 `APP_ENVIRONMENT` 读取 `admin.app_version.<environment>.ios` 与 `.google`，与 `/app-config` 使用同一键规则；缺少有效地址时不回退到旧键或其他环境。保留 `kando://` 唤起、按平台选择商店及页面 HTTP 缓存；版本提示停用不影响已配置的商店链接。无 App、数据库配置或迁移改动。
- 分享页和版本管理定向测试共 18／18 通过，Workers 类型检查、根依赖方向检查通过。Code Review 核对了参数绑定、双端隔离、缺配置行为及旧链接不回退，无阻塞项。

#### 生产发布验收（2026-11-18 17:26，Asia/Shanghai）

- 从线上 `toccards-api-prod` 版本 `bf8efb96-7ae1-448b-8009-928ef2ad7530` 的 immutable module 生成最小候选，仅替换 `881390776e75b9cf5218de0db7297960e90479b3` 中的 `loadConfiguredStoreUrls`。原函数与线上编译结果逐字节匹配，逆向替换后全模块一致，未发布当前 `main` 的其他增量（包括分享页品牌文案）。候选回读 SHA-256 为 `fec5aa54e9891581218f82b39b0f9ba931658d171b4f9ed5ffcf2ad7ea55bcfd`。
- 候选 `4c7d5633-514d-4322-9cfc-0fca71d37128` 在 deployment `850b736f-b4df-4887-afc6-7c2d81581936` 以 0% 验收后，由 deployment `bd5e4430-a4ac-4435-b43a-32ec8cc24aaa` 切至 100%，已回读确认。上一个 100% 版本 `bf8efb96-7ae1-448b-8009-928ef2ad7530` 保留为回退基线。
- 候选和正式流量各 7 项只读烟测通过。`/share/cards/560537` 的缓存 MISS 响应中，Android 指向 Google Play 的 `com.cardai.tcg`，iOS 保持 App Store 的 `id6793017224`，`kando://` 唤起地址不变；health、未登录拒绝和 iOS／Google／Android 公共配置均正常。两个 Admin 入口各 11 个 HTML／JS／CSS 指纹与发布前匹配（比较 HTML 时排除 Cloudflare Insights beacon），Pages deployment 仍为 `6ee65b9c-e7ac-4821-919f-96117cc560aa`。39 个绑定（含 18 个 Secret 描述符）、Worker 运行配置、Smart Placement、cron、自定义域和 Hyperdrive 查询缓存均未变。
- 未读 Secret 明文，未执行数据库迁移或业务配置写入，未发布 Flutter、Google Play 或 App Store。HTTP 验证不代表真机点击通过或 Play 正式版可下载；旧分享响应仍可能在原有 300 秒缓存期内被复用。

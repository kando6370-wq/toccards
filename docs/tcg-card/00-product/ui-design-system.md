# 卡牌 App UI 设计系统规范

> 定位：这是 tcg-card / Vault & Vellum App 的 UI 实现硬规范。后续所有 Flutter App UI 修改、Figma 还原、组件重构、页面精修都必须先读本文，并按本文执行。
>
> 设计源：Figma 文件 `卡牌app`，file key `DjacfTioobtRy59SnqH7SY`。
> 主要节点：`40:28` (`02 Components`)、`368:8536` (`DS Spec 1 - 卡牌 App 设计规范书`)、`665:11589` (`页面间距规范`)、`99:5952` (`Button`)、`414:9823` (`Card / Asset`)。
>
> 最后同步：2026-07-17，基于 Figma MCP 读取结果整理。

---

## 0. 强制规则

1. UI 修改不得自由发挥。除非用户明确要求改视觉方向，否则必须遵循本文。
2. 若本文与具体 Figma 页面有冲突，以对应 Figma 页面 / frame 为准；若没有具体页面，以本文为准。
3. 若本文与旧 PRD 截图冲突，以 Figma `卡牌app` 当前设计系统为准。
4. 若代码现状与本文冲突，优先调整代码靠近本文，而不是修改本文迁就旧实现。
5. 不得新增与本文冲突的颜色、圆角、阴影、按钮样式、卡片样式或导航样式。
6. 不得把页面做成通用 Material 默认风格、浅色风格、蓝紫渐变风格、营销落地页风格或后台管理风格。
7. 不得为了局部方便引入一套新的设计语言；复用 `KandoColors`、主题、共享组件和本文 token。
8. UI 改动完成后必须自查 §13 的验收清单。

---

## 1. 设计语言

产品视觉名为 **Vault & Vellum**。

核心气质：

- Dark system：深色收藏库，而不是普通黑色 App。
- Premium card vault：卡牌收藏、资产价值、扫描识别、Portfolio 管理。
- 荧光黄绿强调：主色用于 CTA、选中态、价值焦点、扫描按钮。
- 温暖纸感文字：主文字偏暖白，避免纯白刺眼。
- 卡牌档案感：卡牌组件需要有边框、暗色渐变、细节信息和价格层级。

视觉关键词：

- 暗橄榄黑背景
- 暖白正文
- 荧光黄绿品牌色
- 胶囊按钮
- 玻璃感底部导航
- 衬线卡牌标题
- 资产金额暖黄色
- 细边框、低饱和 surface、克制阴影

---

## 2. 颜色 Token

代码现状中 `apps/flutter-app/lib/shared/ui/kando_style.dart` 已有核心 token。后续 UI 必须优先使用这些 token。

| 语义 | 颜色 | Flutter token | 用途 |
|---|---:|---|---|
| 页面底色 | `#10100B` | `KandoColors.ink` | App 全局背景、深色安全区、底部 home indicator 区 |
| Surface | `#1A1C14` | `KandoColors.surface` | 卡片、输入框、弹窗、普通容器 |
| Elevated surface | `#2A2B20` | `KandoColors.elevatedSurface` | 次级按钮、禁用态、抬升面 |
| Border | `#464835` | `KandoColors.border` | 普通描边、分割线、弱边框 |
| Primary text | `#EEECD8` | `KandoColors.text` | 主文字、标题、按钮 secondary 文案 |
| Muted text | `#C7C8B0` | `KandoColors.mutedText` | 次级说明、卡牌 metadata、导航未选中 |
| Accent / Brand | `#F0FE6F` | `KandoColors.accent` | 主 CTA、选中态、扫描按钮、焦点描边 |
| Soft accent | `#F0E7FF` | `KandoColors.softAccent` | iOS home indicator 或柔和次强调 |

Figma 中还出现以下语义色，若频繁使用，应补充进 `KandoColors`，不要散落硬编码：

| 语义 | 颜色 | 用途 |
|---|---:|---|
| Money text | `#FFF6AF` | 价格、Portfolio 总额、资产数值 |
| Gain text | `#4ADE80` | 涨幅、正收益 |
| Error / Delete | `#FFB1B1` | 删除按钮、危险操作 |
| Error text | `#FF8989` | 规范页警示、错误提示 |
| Primary on default | `#2C3400` | 荧光黄绿按钮上的文字 |
| Text secondary dark | `#615D3B` | 禁用按钮文字 |
| Border focus | `rgba(240,254,111,0.6)` | focus / selected 边框 |
| Accent glow 10 | `rgba(240,254,111,0.1)` | chip、pill、轻强调背景 |
| Border subtle | `rgba(255,255,255,0.08)` | 暗面上的细边框 |

颜色使用规则：

- 页面背景必须是 `#10100B` 或基于它的 Figma 指定暗色渐变。
- 普通内容卡片必须用 `#1A1C14`，不要用纯黑或默认 `Colors.grey`.
- CTA 必须用 `#F0FE6F`，文字用深色 `#2C3400` / `KandoColors.ink`。
- 金额必须用 `#FFF6AF`，不要用主文字色替代。
- 涨幅必须用 `#4ADE80`，跌幅使用项目统一 loss token；若没有 token，先补 token。
- 删除/危险操作必须用 `#FFB1B1`，不要用 Material 默认红。
- 文字不要使用纯白，除非是 Figma 特定 Label Color/Dark/Primary。

---

## 3. 字体与字号

Figma 字体系统：

| 用途 | 字体 | 规则 |
|---|---|---|
| 展示标题 / 品牌标题 / 卡牌名 | `Fraunces` | 用于 Vault & Vellum、大标题、卡牌名称，带收藏档案感 |
| UI 正文 / 按钮 / 标签 | `Geist` | 默认 App UI 字体 |
| 小型系统标签 | `Geist Mono` | Kicker、PORTFOLIO 等 12px mono 标签 |
| iOS 状态栏 | `SF Pro Text` | 仅状态栏或 iOS 系统模拟区域 |

当前 Flutter theme 已设置 `fontFamily: 'Geist'`，但资源接入需确认。若字体文件未进入 `pubspec.yaml`，不得假装已完成高还原；必须记录为还原缺口。

常用字号：

| 语义 | 字号 / 行高 | 字重 | 用途 |
|---|---|---|---|
| Spec / Hero display | 76 / 84 | Fraunces SemiBold | 规范封面，不一定用于移动端 |
| Page title | 42 / 52 | Fraunces SemiBold | 规范页标题 |
| Portfolio value | 36 / 44 | Geist SemiBold | 大金额 |
| Card S title | 20 / 26 | Fraunces SemiBold | 大卡牌标题 |
| Button lg | 18 / 24 | Geist Medium | 大按钮 |
| Label lg | 16 / 24 | Geist Regular / Bold | 顶部 pill、md 按钮 |
| Card title L | 14 / 20 | Fraunces Medium | 竖版卡牌名 |
| Body / chip | 13 / 16 or 18 | Geist Regular | chip、metadata |
| Mono kicker | 12 / 16 | Geist Mono SemiBold | 小型章节标签 |
| Card metadata | 11 / 18 | Geist Regular | 卡牌编号、套装、状态、底部导航 |
| Delta / tiny | 10 / 14 | Geist Regular | 涨幅、极小标签 |

排版规则：

- 字距默认 `0`，不要为了“高级感”随意负字距。
- 金额可以强调，但不能突破容器宽度；超长金额必须处理换行、缩放或 ellipsis。
- 卡牌名优先 ellipsis，不能撑破卡片。
- 中文和英文混排时，保持 Figma 中的紧凑信息密度，不要大幅加行距。

---

## 4. 圆角、描边、阴影、模糊

圆角 token：

| 名称 | 值 | 用途 |
|---|---:|---|
| `radius-sm` | `4px` | XXS/小卡图、细小控件 |
| `radius-default` | `8px` | 卡图容器、普通小容器 |
| `radius-md` | `12px` | 资产卡、输入框、普通卡片 |
| `radius-lg` | `16px` | 大面板、图表容器 |
| `radius-xl` | `24px` | 手机预览、大型容器 |
| `radius-full` | `9999px` / `99px` | 胶囊按钮、底部导航、圆形扫描按钮 |

描边规则：

- 普通暗面卡片：`1px #464835` 或 `rgba(255,255,255,0.08)`。
- 选中 / focus：`rgba(240,254,111,0.6)` 或 `#F0FE6F`。
- 卡牌空状态：允许使用荧光黄绿低透明虚线边框。

阴影和模糊：

- 卡牌可使用低强度黑色阴影，例如 `0 4px 20px rgba(0,0,0,0.4)`。
- 底部导航必须有毛玻璃感，Figma 为 `backdrop-blur 8px`。
- 顶部 pill 可使用 `backdrop-blur 10px`。
- 不要使用彩色大面积 glow、装饰光球、过重阴影。

---

## 5. 间距与移动端画布

Figma 规范明确基于 **390px mobile**。

硬规则：

| 项 | 值 |
|---|---:|
| 移动端基准宽度 | `390px` |
| 页面左右边距 | `20px` |
| 大模块之间间距 | `32px` |
| Home 卡牌横向间距 | `16px` |
| 搜索推荐页面间距 | `10px` |
| 常规间距系统 | 以 `4px` 倍数为主，少数 `2px` 倍数 |

布局规则：

- 页面主内容宽度按 `390 - 20 * 2 = 350px` 设计。
- 底部导航宽度为 `350px`，与页面内容边距对齐。
- 大模块之间使用 `32px`，不要随意改成 Material 默认 `24px`。
- Home 横向卡牌列表 gap 为 `16px`。
- 搜索推荐紧凑列表 gap 为 `10px`。
- 页面顶部与 iOS status/nav 区域的关系必须对照具体 Figma 页面，不得统一套一个 AppBar 高度。

---

## 6. 按钮规范

Figma 节点：`99:5952` (`Button`)。

按钮全部为胶囊形，圆角 `99px` / `radius-full`。

尺寸：

| Size | 高度 | 水平宽度 | 字体 | Icon |
|---|---:|---:|---|---:|
| `xs` | `36px` | 通常 `350px` 或容器宽 | 13 / 16 | 20 |
| `sm` | `44px` | 通常 `350px` 或容器宽 | 13 / 16 | 20 |
| `md` | `56px` | 通常 `350px` 或容器宽 | 16 / 24 | 24 |
| `lg` | `66px` | 通常 `350px` 或容器宽 | 18 / 24 | 26 |

类型：

| Type | 背景 | 描边 | 文字 |
|---|---|---|---|
| Primary | `#F0FE6F` | 无 | `#2C3400` |
| Secondary | `#2A2B20` | `rgba(255,255,255,0.08)` | `#EEECD8` |
| Disable | `#2A2B20` | `rgba(255,255,255,0.08)` | `#615D3B` |
| Delete | `#FFB1B1` | subtle border | `#2C3400` |

按钮实现规则：

- 不得使用 Flutter 默认 ElevatedButton/OutlinedButton 视觉，除非 theme 已完全覆盖为本文样式。
- 主操作按钮必须全宽或按 Figma 容器宽度，不得随内容宽度收缩。
- 图标与文字间距为 `8px`。
- 按钮文字必须垂直居中。
- 禁用态不能只降低 opacity，必须符合 Figma 暗面 + 暗文字状态。

---

## 7. 输入框规范

Figma 节点：`99:6489` (`Input`)、`99:6781` (`Input Area`)。

尺寸：

| Size | 高度 |
|---|---:|
| sm | `44px` |
| md | `52px` |
| lg | `60px` |

状态：

- Default：暗色 surface，细边框。
- Focus：focus 边框使用品牌色。
- Fill：有输入内容时保持暗色底，文字主色。
- Danger：错误态使用粉红/错误色，不使用 Material 默认红。
- Disable：暗面 + 降低文字层级。

实现规则：

- 输入框圆角通常 `12px`。
- 文案、label、placeholder 必须使用 Geist。
- 不得使用浅色 TextField 默认背景。
- 密码显隐、邮箱、搜索、扫描等 icon 使用 20/24px，颜色按状态切换。

---

## 8. 底部导航规范

Figma 节点：`52:1573` (`Nav / Bottom`)、`60:6236` (`Component 1`)。

结构：

- 导航整体宽度 `350px`，高度约 `62px`。
- 外层圆角 `99px`。
- 外层背景为半透明黑 + 半透明白叠加，带 `backdrop-blur 8px`。
- 内边距 `4px`。
- 5 个入口：Home、Search、中心扫描、Collection、Profile。
- 中间扫描按钮是 `64px` 圆形，使用黄绿渐变，高于导航栏视觉中心。

状态：

- 未选中 icon/text：`#C7C8B0`。
- 选中 icon/text：`#F0FE6F`。
- 选中 tab 背景：`rgba(255,255,255,0.12)`，圆角 `99px`。
- 中心扫描按钮始终高亮，不按普通 tab 处理。

实现规则：

- 不得使用 Flutter 默认 BottomNavigationBar 视觉。
- 导航必须与 20px 页面边距对齐。
- Home indicator 区域背景跟随页面底色。
- 导航 label 使用 11 / 18。
- active pill 不得改变整体导航尺寸或造成布局跳动。

---

## 9. 卡牌组件规范

Figma 节点：`414:9823` (`Card / Asset`)。

卡牌规格：

| 规格 | 宽 | 高 / 说明 |
|---|---:|---|
| L | `170px` | 信息完整，含图、metadata、价格、涨幅 |
| M | `144px` | 中等列表卡 |
| S | `169px` | 横向/推荐区域大标题卡 |
| XS | `80px` | 小图卡 |
| XXS | `42px` | 极小图卡 |

视觉：

- 卡片外层为暗色渐变：约 `rgba(28,30,21,0.8)` 到 `rgba(18,20,13,0.9)`。
- 圆角通常 `12px`；小图使用 `8px` / `4px`。
- 边框可用白色低透明或品牌色低透明，按 Figma 对应卡型。
- 卡图容器底色为 `#10100B` 或 `#1A1C14`。
- 空白卡牌使用暗色径向渐变、虚线荧光边框、问号占位和星点质感。

文字：

- 卡牌名用 Fraunces，L 卡约 14 / 20，S 卡约 20 / 26。
- metadata 用 Geist 11 / 18 或 13 / 18。
- condition 中 `Near Mint` 可用品牌色突出，其余 metadata 用 muted text。
- 价格用 `#FFF6AF`，涨幅用 `#4ADE80`。

实现规则：

- 卡牌真实图片必须保持原始纵横比，不能拉伸。
- 无图片时使用系统空白卡牌占位，不要用灰色方块长期替代。
- 长标题必须 ellipsis，不能撑破卡片。
- 金额过长时必须按 Figma 处理，不能溢出。
- Collection / Search / Home 中的卡牌间距必须遵守 §5。

---

## 10. 页面模板规范

### Home

- 页面边距 `20px`。
- Home 卡牌间距 `16px`。
- 大模块间距 `32px`。
- 顶部 pill 可使用品牌色实底 + 暗色文字，货币 pill 使用 accent glow 暗底 + 品牌文字。
- Portfolio 总额使用 money 色或品牌强调，不能用普通白色。
- 图表、趋势、Most Valuable 模块必须保持暗色面板和细边框。

### Collection / Portfolio

- 网格基于 `350px` 内容宽。
- 两列资产卡时列间距按 Figma：通常 `10px` 或具体页面值；若属于 Home 卡牌上下文则用 `16px`。
- 底部导航必须固定在底部并和内容边距对齐。
- 筛选、排序、文件夹切换优先使用 pill / sheet，不要使用默认 Material 下拉视觉。

### Search

- 搜索推荐页间距为 `10px`。
- 搜索框为暗色圆角输入，扫描 icon 内嵌。
- 结果卡片使用竖版卡牌组件，不得使用普通 ListTile 风格。

### Card Detail

- 深色 ink 画布。
- Hero 卡图区域允许 accent glow，但必须克制。
- Tab / segmented 控件使用 pill 风格。
- 价格表、Collection Item、Market rows 必须使用暗面板 + 细边框。

### Profile / Auth / Onboarding

- Auth CTA 使用全宽 primary 胶囊按钮。
- 第三方登录按钮仍遵守 button 系统，只替换品牌 icon。
- Profile 分组使用暗面卡片，不使用默认 ListTile 白底/灰底。
- 弹窗必须使用 §11 的 modal 规范。

### Scan

- 中心扫描入口为品牌主操作，不得降级为普通 tab。
- 扫描页可使用更强的取景框/识别状态，但颜色仍必须回到本文 token。

---

## 11. Toast / Modal / Empty State

Figma 弹窗 section：`736:13751` (`弹窗`)。

弹窗系统包含 5 类：轻提示 toast、成功 welcome toast、危险确认 modal、移除确认 modal、版本升级 modal。实现时不得混用 Material 默认 Dialog / SnackBar 视觉；可以使用 Flutter 的弹层机制，但外观必须按本节。

### 11.1 使用决策

| 场景 | 必须使用 | 不得使用 |
|---|---|---|
| 保存成功、注册成功、账号创建成功 | Success / Welcome toast | 普通系统 SnackBar |
| 网络错误、接口失败、无法继续操作 | Floating toast | AlertDialog |
| 删除全部卡牌、删除账号、清空数据 | Danger confirm modal | Toast 或 bottom sheet |
| 从 portfolio 移除单张卡 | Remove confirm modal | 直接删除 |
| App 版本升级、强提示更新 | Update modal | Toast |
| 表单字段校验错误 | 输入框 danger 状态 + inline helper | 全屏 modal |
| 可撤销、低风险反馈 | Floating toast | 阻断式 modal |

### 11.2 Floating Toast

对应 Figma：`736:13804`、`736:13816`。

用于网络错误、通用失败、无网络等非阻断反馈。

尺寸与布局：

- 宽度 `350px`，与 390px 页面左右 `20px` 边距对齐。
- 高度 `74px`。
- 外层为暗面浮层，带阴影，圆角遵守 Figma。
- 左侧 icon overlay：`40px`，位置 `x=17`、`y=17`。
- icon 内部图形：`20px`，居中。
- 文案容器从 `x=73` 开始，宽约 `235px`，高度 `40px`。
- 右侧关闭按钮在 `x≈325`，icon 约 `8-12px`。

文案规则：

- 文字最多 2 行，不写长解释。
- 错误类文案用主文字或 muted text；不要用大面积红色文字。
- 典型文案：
  - `Something went wrong. Please try again later.`
  - `No internet connection. Please check your network and try again.`

行为规则：

- 默认 2-4 秒自动消失。
- 允许手动关闭。
- 不得遮挡底部导航的中心扫描按钮；通常贴近顶部安全区下方或页面上部浮层。
- 同一时间只显示一个 toast；新 toast 替换旧 toast。

### 11.3 Success / Welcome Toast

对应 Figma：`736:13753`、`736:13761`。

用于注册成功、登录成功、账号创建成功、重要操作完成。

两种形态：

| 形态 | 宽 | 高 | 使用场景 |
|---|---:|---:|---|
| 无按钮 | `260px` | `210px` | 纯成功反馈，自动关闭 |
| 带按钮 | `260px` | `274px` | 需要用户确认继续，例如 Welcome / Continue |

布局：

- 外层宽 `260px`，内容内边距 `33px`。
- 内容宽 `194px`。
- 顶部 icon overlay `56px`，水平居中，内部 icon `26px`。
- 标题容器位于 icon 下方 `6px` 左右，标题高度 `32px`。
- 正文容器高度约 `44px`。
- 带按钮形态按钮位于 `x=33`、`y=197`，宽 `194px`、高 `44px`。

文字：

- 标题使用 Heading 2 视觉，居中。
- 正文居中，最多 2 行。
- 示例：
  - Title: `Welcome`
  - Body: `Your account has been created successfully.`

行为：

- 无按钮形态可自动关闭。
- 带按钮形态必须等待用户点按钮或显式关闭。
- 不得用底部 sheet 替代 welcome toast。

### 11.4 Danger Confirm Modal

对应 Figma：`736:13771`。

用于高风险、不可撤销操作，例如删除全部卡牌、删除账号、清空 portfolio。

尺寸与布局：

- Modal 宽 `342px`。
- 高度按内容：典型 `355px`。
- 内边距 `33px`。
- 内容宽 `276px`。
- 顶部 icon / visual header 高 `56px`。
- icon overlay `56px`，居中，内部 icon `26px`。
- Text content 从 `y=76` 开始。
- 标题高度 `32px`，居中。
- 正文位于标题下方约 `6-10px`，宽 `276px`。
- Action buttons 区域宽 `276px`，高 `108px`。
- 按钮垂直堆叠，每个按钮高 `44px`，两个按钮之间约 `12px`。

文案：

- 标题必须直接说明危险动作，例如 `Delete all cards ?`。
- 正文必须说明后果，不写含糊提示。
- 示例正文：`This action will permanently delete all these cards and cannot be undone`

按钮：

- 危险主操作使用 Delete button：`#FFB1B1` 背景，深色文字。
- 取消 / 保留操作使用 Secondary button。
- 按钮顺序必须与 Figma 对应页面一致；没有具体 Figma 页面时，默认上方为危险动作，下方为取消动作。
- 不得只提供一个危险按钮；必须给取消路径。

行为：

- 点击遮罩是否关闭按风险决定：高风险删除默认不允许点遮罩关闭，必须点按钮。
- 返回键 / 系统手势关闭要等同取消。
- 执行中按钮进入 loading / disabled，不得重复提交。

### 11.5 Remove Confirm Modal

对应 Figma：`736:13790`。

用于从 portfolio 移除单张卡或移除单个收藏项。它比 Danger Confirm Modal 更短，但仍是阻断式确认。

尺寸与布局：

- Modal 宽 `342px`。
- 典型高度 `334px`。
- 内边距 `33px`。
- icon overlay `56px`。
- 标题可占 `64px` 两行，例如 `This card will be removed from your portfolio`。
- 不强制正文；若 Figma 页面没有正文，不要额外添加解释。
- 按钮区从 `y≈160` 开始，宽 `276px`，高 `108px`。

使用规则：

- 单卡移除不得静默执行。
- 如果操作可撤销，也可以使用 toast + undo，但必须有对应设计；没有设计时用此 modal。
- 文案必须明确对象是 card / portfolio item，不要写泛泛的 `Are you sure?`。

### 11.6 Update Modal

对应 Figma：`736:13833`。

用于 App 更新提示、重要版本升级提示。

尺寸与布局：

- Modal 宽 `342px`。
- 典型高度约 `452px`。
- 顶部视觉区域：内容容器 `276px` 宽，高约 `178px`。
- 插画 / update visual 约 `160px × 158px`，水平居中。
- 文案区域位于视觉下方，宽 `276px`，标题高 `32px`，正文高 `22px`。
- Action buttons 区域宽 `276px`，高 `108px`，两个 `44px` 胶囊按钮垂直堆叠。

文案：

- 标题短句，例如 `Update Now`。
- 正文短句，例如 `New update available! Tap to upgrade`。
- 不在 modal 内堆长版本说明；详细 release notes 应跳转到独立页面或外链。

按钮：

- 主按钮使用 Primary。
- 次按钮使用 Secondary。
- 如果是强制升级，不展示跳过按钮；如果非强制升级，可展示稍后。

### 11.7 Modal 外观通用规则

- 背景遮罩必须压暗页面，但不能变成纯黑硬切。
- Modal 外层使用 `KandoColors.surface` 或 Figma 指定暗色 surface。
- 圆角按 Figma，通常不低于 `16px`。
- 标题居中，正文居中。
- 所有按钮必须复用 §6 Button 系统。
- icon overlay 使用品牌色或语义色，不用 Material 默认蓝/红。
- Modal 内容不得贴边；主内容宽按 `276px` 对齐。
- 文案区域与按钮区域之间必须留足空间，不能拥挤。
- 弹窗出现时底部导航不可继续响应。

### 11.8 Empty State

- 空状态 icon / illustration 通常 100px。
- 必须使用暗色系统和品牌色，不要用 Material 默认灰色大图标。
- 文案必须短，不能在空状态里解释功能教程。

---

## 12. 代码落地规则

Flutter UI 修改时：

1. 优先使用 `KandoColors`。
2. 若需要新颜色，先判断是否属于 §2 语义色；若是，补 token，不要局部硬编码。
3. 优先抽共享组件：按钮、输入框、底部导航、卡牌、toast/modal。
4. 共享组件必须支持 Figma 的状态和尺寸，不要只服务当前页面。
5. 不得引入 Tailwind、Web CSS 思路或 React 参考代码到 Flutter；Figma MCP 输出的 React/Tailwind 只能作为参考。
6. 保留现有业务逻辑、Riverpod provider、route、widget key；UI 精修不应改变数据行为。
7. 修改 UI 前先定位对应 Figma 节点；没有节点时按本文 token 和组件系统实现。
8. 修改 UI 后跑 `flutter analyze`，涉及 widget 行为时跑相关测试。

当前代码 token 入口：

- `apps/flutter-app/lib/shared/ui/kando_style.dart`
- `apps/flutter-app/lib/app/theme.dart`

建议后续补充：

- `KandoColors.money = #FFF6AF`
- `KandoColors.gain = #4ADE80`
- `KandoColors.error = #FFB1B1`
- `KandoColors.errorText = #FF8989`
- `KandoColors.primaryOnDefault = #2C3400`
- `KandoColors.disabledText = #615D3B`
- `KandoColors.borderFocus = rgba(240,254,111,0.6)`
- `KandoColors.accentGlow10 = rgba(240,254,111,0.1)`
- `KandoColors.borderSubtle = rgba(255,255,255,0.08)`

---

## 13. UI 修改验收清单

每次 UI 修改完成前必须逐项自查：

- 页面背景是否仍为 `#10100B` 或 Figma 指定暗色背景？
- 页面左右边距是否为 `20px`？
- 大模块间距是否为 `32px`？
- Home 卡牌间距是否为 `16px`？
- 搜索推荐页间距是否为 `10px`？
- CTA 是否为 `#F0FE6F` 胶囊按钮？
- secondary / disabled / delete 按钮是否符合 §6？
- 金额是否使用 `#FFF6AF`？
- 涨幅是否使用 `#4ADE80`？
- 删除/危险操作是否使用 `#FFB1B1`？
- 卡牌名是否使用 Fraunces 或项目中对应的衬线标题样式？
- 普通 UI 文案是否使用 Geist？
- 卡牌图片是否保持纵横比？
- 长标题、长金额、长 metadata 是否不会溢出？
- 底部导航是否是 350px 玻璃胶囊，而不是默认 BottomNavigationBar？
- 中心扫描按钮是否仍是 64px 圆形高亮？
- 空状态、toast、modal 是否符合暗色系统？
- 是否避免了纯白、Material 默认蓝、默认红、默认灰背景？
- 是否没有引入新的自由发挥颜色/阴影/圆角？
- 是否保留了现有业务逻辑和测试依赖的 widget key？
- 是否完成 `flutter analyze` 或说明无法验证的原因？

---

## 14. 禁止清单

以下做法默认不允许：

- 使用浅色页面背景。
- 使用 Material 默认 `BottomNavigationBar` 视觉。
- 使用 Material 默认蓝色作为主色。
- 使用普通矩形按钮替代胶囊按钮。
- 使用默认红色替代 Figma 删除粉。
- 用灰色块长期替代空白卡牌设计。
- 把卡牌列表做成普通 ListTile。
- 随意扩大圆角到卡通风格。
- 使用大面积紫蓝渐变、装饰光球、营销页 hero。
- 把字体大小随屏幕宽度缩放。
- 修改 UI 时顺手重构业务逻辑。
- 无 Figma 节点或本文依据时自行创造新视觉系统。

---

## 15. Figma 读取备注

Figma MCP 读取 `get_design_context` 返回的是 React + Tailwind 参考代码。实现到本项目时必须转换为 Flutter / Dart，并复用项目现有 token 与组件。

读取优先级：

1. 具体页面 frame 的 `get_design_context`
2. Code Connect / 组件说明
3. 设计注释
4. 本文 token 和规则
5. 截图视觉判断

不得在 `get_design_context` 可用时只凭截图手写页面。

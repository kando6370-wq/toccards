# CardScanFox 官网账号删除申请：方案与页面设计

状态：v0.1 设计，2026-11-10（Asia/Shanghai）；2026-11-11 按用户要求实现官网首版源码，见第 13 节。原设计依据 `main@e5a9c4d6` 的官网、App 和共享 API。

2026-11-10 轮次只产出方案和交互设计，没有修改 App、官网或 API 业务代码，没有部署、填写 Play Console、发送邮件或删除真实数据。下文保留该轮设计；2026-11-11 实现范围与未完成的客服／发布边界分别记录于第 13 节，不将拟议 SOP 写成已运行的系统。

配套[交互设计预览](../../../../prototypes/cardscanfox-account-deletion-design.html)仅供评审，不参与官网构建；可切换桌面／手机及 Android／iOS，按钮只演示本地状态，不发送请求。预览加载图标等静态资源需要网络，真实收件与删除处理仍需后续实施和验收。

## 1. 目标与验收标准

用户即使卸载 Card AI、换设备或无法登录 App，也能在官网找到明确入口，申请删除指定平台账号及相关数据。页面可访问、品牌明确、申请步骤可执行，且不会将“邮件草稿已准备”误写为“申请已收到”。

设计验收：

1. 从 Google Play 删除链接、官网 Help 或页脚进入，均可在首屏识别 Card AI、删除目的与主要操作，无需注册官网账号或重装 App。
2. Android 与 iOS 分别确认，不默认选中平台，不将一端申请转换为全账号删除。
3. 用户清楚自己是在准备邮件；只有实际发送并由客服收件后才进入受理流程。
4. 可以了解删除范围、保留例外、第三方数据处理及 iOS 订阅边界。
5. 关联邮箱不可用、不记得账号邮箱、没有邮件客户端的用户均能找到人工协助路径。
6. 客服能够核验、交给有权限的人员执行、核对处理结果并回复，不止于提供一个邮箱链接。

Google 官方允许通过客服邮箱或表单提供网页申请路径，并未要求额外公开无需鉴权的删除 API。网站入口和 App 内入口、关联数据、服务提供商删除及保留披露应一起考虑；网页本身不能代表端到端合规验收完成。官方依据见第 12 节。

## 2. 设计时的官网与业务基线（2026-11-10，历史）

本节保留设计前的状态与决策依据；源码链接现在指向实现后的文件，不应将下表当作当前功能缺失清单。2026-11-11 的实现与发布结果见第 13 节。

| 当时事实 | 对当时方案的影响 |
|---|---|
| [现有页面](../../../../apps/cardscanfox-web/src/render.mjs) 的 `accountSetup()` 已在 `/Account/AccountSetup` 提供邮件入口 | 保留大小写和完整路径，不另换正式 URL。 |
| 页面标题偏向 `Account setup and deletion`，内容以长文说明为主 | 改为目的明确的删除标题、结构化申请区和处理步骤。 |
| CardScanFox 是官网品牌，Google Play 的 App 名为 Card AI: TCG Card Scanner | 标题与说明突出 Card AI，保留 CardScanFox 页头，避免用户误认为删除网站浏览器书签。 |
| 现有 shell 页脚没有独立的账号删除链接，Help 没有专门的删号问答 | 拟在 Help、页脚和隐私政策中增加或强化 `Account deletion` 入口，不新增一级主导航。 |
| [App 确认提示](../../../../apps/flutter-app/lib/features/profile/account_page.dart) 已明确按平台删除 | 保留当前平台隔离和重新注册规则，官网不得另立全局删除语义。 |
| [Admin API](../../../../apps/workers-api/src/admin/routes.ts) 已有仅限 `super_admin` 的平台账号删除路由，当前 Admin Web 未提供对应删除按钮 | 人工核验后复用受保护 API 或经批准的内部工具；不能把已有 API 写成现成客服界面，客服收件人不自动获得删除权限。 |
| [删除实现](../../../../apps/workers-api/src/auth/account.ts) 删除对应空间的数据与 R2 图片，撤销会话 | 复用既有真实删除能力，不以停用账号或退出登录代替删除。 |
| [隐私政策](../../../../apps/cardscanfox-web/content/legacy/privacy.html) 已有平台删号、保留例外与邮箱路径 | 后续修改应同步口径，不能只改申请页而保留矛盾的隐私说明。 |
| [官网架构](../02-architecture/cardscanfox-website-service-spec.md) 不设官网账号、CMS、数据库和业务写 API | 首版采用邮件受理，避免为了页面引入新的账号与删除系统。 |

## 3. 首版方案选择

**推荐：公开网页准备结构化邮件 → 用户发送 → 客服核验 → super_admin 通过受保护 API／获批内部工具执行平台删除 → 核对自有及第三方数据 → 反馈结果。**

| 方案 | 决策 | 原因 |
|---|---|---|
| 邮件受理与人工核验 | 首版采用 | 使用现有邮箱和后台能力；无需新增官网数据库、登录和写接口；能够处理无法访问 App 的异常用户。 |
| 在线表单、自动验证邮件和自助删除 | 暂不实施，后续独立评审 | 需要真实的申请受理服务、邮箱控制权证明、一次性凭证、限频、审计和运维。不能仅画一个表单就显示“提交成功”。 |

页面可以有平台和账号邮箱两个输入，用于**本地生成邮件草稿**，不是在线提交表单。本版明确选择在网页填写账号邮箱：输入不向网站服务器提交、不写入当前网页地址／查询参数、不存浏览器持久存储、不发送到统计 SDK。未来打开草稿时，平台和账号邮箱会随用户点击构造的 `mailto:` URI 交给本机邮件处理程序；不能承诺个人信息完全不进入任何 URI，按钮附近应说明交接对象。本轮预览只模拟该交接，不实际调用邮件程序。

本版只提供 Android、iOS 两个独立选项，不增加 `Both platforms` 或全账号删除快捷操作。需要删除两端的用户可在人工协助中说明，客服拆分为两项明确确认的处理范围，分别核验和执行。该设计保留现有业务边界，也允许用户提出更广泛的隐私请求。

## 4. 页面信息架构与视觉

正式地址继续使用 `https://tcgcard.fun/Account/AccountSetup`，保持公开可访问、`noindex, follow`；不把删号页放进 SEO 卡牌目录或 sitemap。

| 区域 | 内容与交互 |
|---|---|
| 全站页头 | 沿用 CardScanFox 标识与现有导航；不把安装 App 当作申请前置条件。 |
| 面包屑 | `Help / Account deletion`。 |
| 主标题 | `Delete your Card AI account and data`。 |
| 首段 | 明确已卸载 App 也可申请；说明此处通过邮箱处理删除请求；清楚显示商店名称 `Card AI: TCG Card Scanner`。开发者名称或法律主体如展示，须与已核实的商店／隐私信息一致，不能用 CardScanFox 网站品牌自行代替。 |
| 主要申请区 | 选择 Android 或 iOS，填写 Card AI 账号邮箱；主按钮准备邮件，次操作查看并复制申请内容。 |
| 辅助入口 | 不记得邮箱／无法使用原邮箱的人工协助，始终可见；无邮件客户端时可查看收件地址和模板。 |
| 范围说明 | 当前平台删除的数据、另一平台保留、无法恢复及合法保留例外。 |
| 处理步骤 | 发送邮件、身份核验、执行与确认；不得伪装成可在线查询的实时工单状态。 |
| 已安装 App 的用户 | 正式账号：`Profile → Account → Delete Account`；游客（Guest）：Profile 页底部的 `Delete Account`。网页申请同样可用，不强制跳回 App。两种入口分别位于 [Account 页面](../../../../apps/flutter-app/lib/features/profile/account_page.dart)和 [Profile 页面](../../../../apps/flutter-app/lib/features/profile/profile_page.dart)，游客不通过 `/account` 页删号。 |
| iOS 条件提示 | 仅在选择 iOS 时，明确删除账号不会自动取消 Apple 订阅；提供管理订阅的帮助说明。 |
| FAQ 与页脚 | 隐私政策、使用条款、Help、账号删除；补充网站 Saved 与 App 收藏不是同一份数据。 |

视觉继承[官网规格](cardscanfox-website-redesign-spec.md)和现有 `site.css`：Manrope，浅色底 `#f8f9f6`、主文字 `#1b231d`、次文字 `#626b64`、分割线 `#dfe4da`、主动作色 `#e5f17c`。不做红色恐吓式整页，不增加推广弹窗或优惠挽留。

当前实现差距（2026-11-11 复核）：官网 FAQ `Still have the app?` 和 API 法律文案仍只提示正式账号路径，尚未说明游客的 Profile 底部入口。Flutter 两种入口均已存在；本次文档校正未修改官网／API 文案或发布，不能将这里的路径更正视为线上文案已修复。

桌面采用主申请区与右侧说明的两栏布局；手机将申请区置于前面，其后是范围、步骤和 FAQ。320px 不横向溢出；平台选择使用原生 `fieldset / legend / radio`，主操作可键盘访问，字段错误通过 `aria-describedby` 关联，草稿状态使用 `aria-live`，重要提示不只用颜色表达。交互设计预览在本次对话中提供，英文为拟上线文案，中文文档用于评审。

## 5. 字段与页面状态

| 字段／动作 | 规则 |
|---|---|
| Platform | 必选 Android 或 iOS，初始不选中；切换会同步修改范围说明、邮件主题和正文。 |
| Account email | 正常路径必填且检查邮箱格式；只说明待删除的账号，不构成身份核验，也不查询账号是否存在。 |
| 登录方式 | 不新增必填字段；Google／Apple 用户使用其 Card AI 账号关联邮箱，Apple 隐藏邮箱用户可请求协助。 |
| Open email draft | 生成用户可审阅的草稿。产品实现时由用户自行发送；不能自动发送或直接执行删除。 |
| Copy request details | 显示并复制同一份模板，作为没有默认邮件客户端时的替代方案；不显示“已发送”。 |
| I can’t access my account email | 绕过正常字段校验进入人工协助邮件；不要求用户重新安装 App，不自动降低核验要求。 |

不收集密码、登录验证码、OAuth Token、身份证件、完整设备标识或扫描照片；不要求用户解释删除原因，也不新增营销同意、评价或挽留步骤。

| 状态 | 页面应该表达 | 不得表达 |
|---|---|---|
| 初始 | 请选择平台并输入账号邮箱 | 默认替用户选 Android 或直接暗示有账号。 |
| 字段缺失 | 在对应字段旁解释缺少什么，并保留已填内容 | 只用 toast 或清空整个表单。 |
| 草稿已准备 | `Email draft prepared. Send it from your email app.` | `Request submitted`、`Account deleted`、虚构工单号。 |
| 复制备用模板 | 显示收件人、主题、正文；仅说明可复制或已复制 | 暗示客服已收件或已开始处理。 |
| 无法使用原邮箱 | 提供人工协助说明，告知仍需核验 | 要求提供密码／验证码或绕过核验直接删除。 |

预览中的按钮只模拟状态；不会真的打开邮件、写剪贴板、提交请求或删除数据。

## 6. 拟上线英文文案与邮件模板

主标题：`Delete your Card AI account and data`

副标题：`Already uninstalled the app? You can still request deletion here.`

申请说明：`Choose the platform and enter the email used for your Card AI account. We’ll help you prepare a deletion request to send to our support team.`

按钮：`Open email draft`；备用动作：`Copy request details`。

操作说明：`Opening a draft passes the platform and account email to your email app. This does not send your request or delete your account. Please send the email to support@tcgcard.fun. We’ll verify your identity and confirm the next steps.`

主草稿模板（示例使用保留域名，不包含真实个人信息）：

```text
To: support@tcgcard.fun
Subject: Card AI account deletion request — Android

I request deletion of my Card AI Android account and its associated data.

Platform: Android
Card AI account email: collector@example.com

I understand that this request applies to the selected platform only.
My account and data on the other platform are not part of this request.
Please verify my identity before processing the request and confirm the next steps.
```

人工协助模板：

```text
Subject: Card AI account deletion assistance

I would like help requesting deletion of my Card AI account and associated data.
I cannot access or do not remember the email associated with the account.
Please explain the minimum information needed to verify my identity and the target platform.
```

iOS 条件提示：`Deleting your iOS Card AI account does not cancel an Apple subscription. Manage any active subscription in your Apple ID subscription settings.` 这只是说明独立的订阅管理事项，不将取消订阅作为受理删除请求的条件。

Android 范围提示：`This request applies to your Android Card AI account. Your iOS account and its data will remain available.`

处理时限文案先使用：`We’ll confirm the expected processing timeline after verifying your request.` 对外明确时限必须在运营和相应规则核对后补充；不得把“7 天”“30 天”等未经确认的数字写成现有服务承诺或 Google 的统一规定。

## 7. 客服与后台处理闭环

以下是拟议 SOP；并不表示当前已有工单系统、邮箱自动回复或第三方删除自动化。

| 阶段 | 负责人和动作 | 可对用户说明的结果 |
|---|---|---|
| 用户发送 | 用户在邮箱审阅并发送草稿 | 网站仍不宣称已收到。 |
| 收件与登记 | 客服确认收到，使用现有工单工具或受控登记方式记录申请 | 确认收到申请；不透露该邮箱是否注册或另一平台是否存在账号。 |
| 身份与范围核验 | 客服核对可验证的账号关联邮箱和目标平台 | 需要补充时只索取最少必要信息，并给出处理预期。 |
| 删除前确认 | 记录用户明确请求的平台、核验结果与执行授权 | 不将 Android 请求扩大为 iOS 或全部基础账号。 |
| 执行平台删除 | 仅 super_admin 使用现有受保护 Admin API 或获批内部执行工具；不假定 Admin Web 已有删除按钮 | 失败／部分失败保持处理中，不发送完成通知。 |
| 自有数据后验 | 核对平台状态、会话撤销、数据库与 R2 图片结果 | 确认已完成的范围，记录必要保留项。 |
| 服务提供商处理 | 指定负责人按已核实流程向相关 SDK 服务商提出历史数据删除请求并记录进度 | 没有完成就明确仍在处理；本地 identity reset 不代表历史数据已删除。 |
| 最终回复 | 说明已完成范围、保留数据及理由／期限，必要时说明剩余步骤 | 不承诺所有系统、备份和第三方数据瞬间清空。 |

核验原则：来自相同 `From` 地址的邮件不单独构成足够的删除授权；需结合邮件认证信息，并向**系统已记录的验证邮箱**主动确认、收到有效回应后按既定规则处理。无法使用原邮箱、Apple 隐藏邮箱或无法定位匿名空间的情况交人工核验，不仅凭声称的邮箱／UID／设备 ID 执行删除；不索取用户登录验证码或密码。替代证明规则仍需有权限的负责人确认。

最小内部登记字段：受理时间、目标平台、核验结果与依据摘要、执行人、处理时间、关联后台请求／审计标识、自有数据结果、第三方处理状态、保留例外、用户通知时间。登记记录本身也需访问控制与保留期限，不复制完整用户内容或凭据。工单标识不自动成为新的 API 字段。

## 8. 删除与保留口径

| 数据 | 拟向用户说明的处理 |
|---|---|
| 当前平台账号和会话 | 将该平台账号标记删除、清除关联业务数据并撤销旧会话；仅停用不算完成删除。重用该平台需重新注册。 |
| 收藏、Wishlist、文件夹、偏好、相关资产和扫描记录 | 按当前平台归属清理；删除的数据不会在新账号中恢复。 |
| 自有 R2 扫描图片 | 需要纳入实际删除与后验，不能只删除记录而保留可关联图片。 |
| 另一平台数据 | 保留；不能因共享邮箱或基础 user ID 顺带删除。 |
| 共享登录身份 | 另一平台仍在使用时按既有规则保留其必要身份；最后一个平台删除时才执行既有基础身份匿名化。 |
| Firebase／Mixpanel／Singular 等历史数据 | 核实各提供商实际处理与保留政策，按必要流程提出删除；先核对平台归属与 SDK 身份映射，不能用共享标识盲目删除另一平台的数据。现有账号删除 API 不等于已同步完成提供商历史数据删除。 |
| 备份、日志、安全／反欺诈及依法保留记录 | 必须逐类列明理由、具体期限或可理解的决定标准、访问限制和最终清理方式；不得以笼统例外无限期保留全部数据。 |
| 网站 Saved references | 属于当前浏览器本地保存，和 App 平台账号分开；通过网站本地书签功能另行管理，不混写为 App 删除已清空。 |
| iOS Apple 订阅／订单 | 保留既有 Apple 业务和合规记录边界；平台删号不自动取消 Apple 订阅。Android 免费首版不因此引入 Google Billing。 |

现有隐私政策第 7、8 节中的保留和第三方处理说明需要与获批 SOP 同步；本次仅提出设计，不直接修改已发布法律文本或替运营作出保留承诺。

## 9. 未来实施时的最小改动范围

1. 在现有 `accountSetup()` 中调整页面结构、字段与本地草稿准备交互。
2. 复用既有官网样式，必要增量仅限定账号删除页；在 Help、页脚补充入口。
3. 核实并同步隐私政策中的期限和流程，保持原 URL 与 App 两端业务规则。
4. 由运营把既有正式 URL 填入 Play Console 的 Data safety 删除链接，并按实际处理能力回答问卷。
5. 配套客服 SOP、提供商操作步骤与后台删除后验；先确认真实可用的受控执行工具和责任人，不把已有受保护 API 等同于现成管理界面。若需要新增 Admin Web 操作界面，另行明确范围；不在官网引入数据库、账号或新删除接口。

上述步骤是 2026-11-10 的实施范围建议；2026-11-11 已落地部分见第 13 节，不构成远端发布授权。

## 10. 上线前验收清单

| 场景 | 应满足的结果 |
|---|---|
| 已卸载、没有网站登录态 | 页面可打开并可发起邮件申请，不要求下载安装 App。 |
| Android / iOS 切换 | 选项、范围、草稿平台一致；iOS 订阅说明仅在适当位置出现。 |
| 缺少平台或邮箱格式不正确 | 错误在字段旁可见，已有输入保留，人工协助仍可进入。 |
| 没有默认邮件客户端 | 可查看并复制完整收件地址、主题和正文，没有虚假“已提交”。 |
| 无法使用关联邮箱 | 有最少必要的人工核验路径，不能未经核验直接删除。 |
| 非 super_admin 或目标平台不匹配 | 现有后台权限及平台校验继续拒绝操作。 |
| 删除失败或第三方尚未完成 | 保留真实处理中状态，说明剩余范围，不能宣称全部完成。 |
| 另一个平台仍有账号 | 其登录、数据、权益和 iOS 订阅行为保持原规则。 |
| 手机、键盘和辅助技术 | 320/390px 与桌面可读，焦点顺序和错误说明可理解。 |
| 隐私与追踪 | 邮箱／草稿不进入当前网页地址／查询参数、持久存储、控制台或分析事件；仅由用户操作交给邮件程序，明确说明 `mailto:` 的数据交接。 |
| 官网链接与 Google Play | Help、页脚、隐私和 Console 指向同一可用正式入口。 |

2026-11-10 设计轮次未运行 App／API／官网业务测试，因为未改变业务实现。本节为实施验收标准；后续源码验证按第 13 节单独记录，不把设计预览当作上线或真实收件验收。

## 11. 待确认的上线决策

这些决策不阻止本轮方案评审，但阻止未经确认的流程和文案直接上线：

| 决策 | 需要确定的内容 |
|---|---|
| 受理责任和时限 | 谁处理 `support@tcgcard.fun`，首次回复、核验后处理与延迟通知的目标时限。 |
| 身份与执行入口 | 核对商店开发者显示名称与法律主体；指定 `super_admin` 和获批执行方式，不把未提供的 Admin Web 删除按钮当作已交付。 |
| 替代核验 | 无法访问原邮箱、Apple 隐藏邮箱、无法定位匿名空间时的可接受证据与拒绝条件。 |
| 保留清单 | 扫描图、备份、日志、审计和依法保留记录的具体期限与最终清理机制。 |
| 第三方删除 | Firebase、Mixpanel、Singular 等由谁发起、如何追踪及如何确认完成。 |

## 12. 依据

- [Google Play：账号删除要求与网页申请方式](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)，本轮读取日期 2026-11-10；特别参考网页资源、关联数据、服务提供商及处理时间的 FAQ。
- [Google Play：Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)，本轮读取日期 2026-11-10。
- [当前官网及 App 平台合同](../03-data-api/platform-accounts.md)。
- [现有官网视觉规格](cardscanfox-website-redesign-spec.md)及[独立官网实现入口](../../../../apps/cardscanfox-web/README.md)。
- [Google Play 正式配置与已完成发布边界](../05-delivery/android-play-release-configuration.md)。

## 13. 官网首版源码实现（2026-11-11）

本轮从 `main@0633fba4` 实现第 3 节的公开网页与邮件申请方案，保留 `/Account/AccountSetup`：

- 页面使用现有官网页头、字体、配色与按钮，新增桌面两栏／手机单栏布局、原生平台选项、邮箱字段、就地错误与可访问状态说明；平台初始不选中。
- 独立 `/assets/account-deletion.js` 只在该页加载，沿用既有静态资产规则与 CSP。普通确定性代码生成邮件主题、正文、固定收件人的编码 `mailto:` 和可复制文本。
- 正常路径只有用户操作才交给本机邮件程序；邮件未发送前不声称已收到或删除成功。复制先展示模板，仅剪贴板实际接受后才说明已复制；拒绝或不支持时保留可手动选择的文本。
- 切换平台或修改邮箱会清除旧草稿，异步复制的迟到结果不会恢复旧状态；iOS 订阅提示只在选择 iOS 时显示。
- 无法使用账号邮箱、Apple 隐藏邮箱或不确定匿名账号信息的用户可直接使用固定人工协助邮件和模板，不依赖正常字段校验；JavaScript 不可用时该路径仍可用。
- 申请区不使用会将输入提交到网页的 HTML form，邮箱和模板也没有表单提交名称。页面脚本不执行 fetch、API、存储或统计操作；只有用户主动打开邮件或复制时将内容交给对应本机能力。
- Help FAQ、帮助区页脚和底部法律链接均新增既有删除页入口，Help 导航保持选中。原 noindex／sitemap 排除策略不变。
- 受保护的隐私／法律源文件原字节保持；保留期限、第三方删除责任、核验与客服时限尚无新增批准事实，不擅自改写承诺。

本轮没有新增官网写 API、数据库、自动邮件、客服工单或 Admin Web 删除按钮；现有 `super_admin` 接口和 App／共享 API 的平台删除、iOS 订阅规则均未修改。真实收件、人工核验、受控执行工具、服务提供商删除与第 11 节的运营决策仍需分别落实。

本地验证不代表生产已发布、Play Console 已填写或真实删除请求已完成；本轮不执行远端部署、账号／规则写入或删除真实数据。

### 13.1 本地验证记录

以下命令使用 Node `22.23.4`；官网命令工作目录为 `apps/cardscanfox-web`，依赖方向检查在仓库根目录运行。本机全局 Node shim 仍为 `22.20.0`，本轮明确使用已准备的 `22.23.4` 可执行文件。

| 检查 | 实际结果 |
|---|---|
| `node --test --test-concurrency=1 --test-reporter=spec test/account-deletion*.test.mjs` | 16/16 通过，覆盖结构、入口发现、隐私边界、两端模板、非法输入、Enter、邮件打开失败、复制失败及迟到结果。 |
| `node --test --test-concurrency=1 --test-reporter=spec test/*.test.mjs` | 63/63 通过，0 跳过，包含既有法律／旧页保护断言。 |
| `node node_modules/wrangler/bin/wrangler.js types`、`node node_modules/typescript/bin/tsc --noEmit` | 类型生成与类型检查通过。 |
| `node scripts/check-dep-direction.mjs` | 仓库依赖方向检查通过。 |
| `node scripts/build.mjs --pages` | 123 条路由构建通过，包含 46 个受保护旧网址；专页模块随静态资源输出。 |
| 本地浏览器 | 桌面、390px 与 320px 布局可读；两种手机宽度均无页面横向溢出，邮箱字体为 16px。无默认平台、字段错误与输入保留、平台范围切换、iOS 条件提示及方向键选择已实际检查。 |
| 独立代码与文档复核 | 当时未报告阻断项；3 份本轮 Markdown 中 14 个本地链接全部存在，已核对正式账号的 App 路径。后续发现遗漏游客分支，差距与正确入口见第 4 节。 |
| `git diff --check` | 通过。 |

首次全量验证曾因本地 EOL 状态失败：44 个旧 HTML 与 1 个 sitemap 的工作树被转换为 CRLF，与现有 LF 原字节保护要求不符。逐文件确认仅移除 CR 即等于 HEAD，且 HEAD 哈希符合原基线／manifest 后，恢复了本地批准 LF 字节；没有修改正文、基线、manifest 或放宽断言。随后上述全量测试和构建通过。构建生成的两个内容 JSON 也没有语义改动，均从本轮内容 diff 中排除。

浏览器检查未打开真实邮件客户端、发送邮件或写入真实删除申请；邮件调用和剪贴板成功／失败使用真实客户端逻辑的单元替身验证，不作为操作系统邮件关联、实际剪贴板权限或客服真实收件的端到端验收。Flutter／共享 API 未改，本轮没有重跑其测试；平台删除实际执行、数据库／R2 后验、服务提供商删除和线上验收仍按第 7、10、11 节分别落实。

### 13.2 提交前同步（2026-11-11）

用户授权提交并推送后，先同步至远端 `main@d1fb6c10`。保留该基线新增的动态 FAQ、JSON-LD、首页与目录响应逻辑；README 两份新增说明均保留，共用模板合并后同时保留本次删除入口和上游 SEO 修正。本次提交相对该基线仍仅涉及上述官网功能及文档的 8 个文件。

同步后的官网完整回归为 73/73 通过、0 跳过；类型生成、`tsc --noEmit`、依赖方向检查与 123 条路由的 Pages 构建均通过。独立复核确认远端 FAQ／SEO 修正和本次 Help／页脚／删除页能力均保留，合并冲突标记为零。

最新[主分支交付记录](../05-delivery/marketing-keyword-content.md#2026-11-10-主分支与正式交付)已确认 Cloudflare 既有 Git 集成会在 `main` 推送后自动发布正式官网。提交、推送、自动构建与线上验收分别核实，不将本地通过或远端 Git SHA 一致等同于真实收件、删号执行或运营闭环完成。

### 13.3 正式官网发布（2026-11-11）

本页实现已提交并推送为 `b716ae12`，用户随后明确授权重新部署官网。同日完成同一提交的正式重发、19 项线上 HTTP 检查、资源字节核对及浏览器 Help 入口／平台切换验收；版本、回退点及验证边界见[正式发布记录](../05-delivery/cardscanfox-production-cutover.md#账号删除申请页正式重发2026-11-11)。这只确认官网申请入口已交付，第 7、10、11 节中的真实客服处理、受控删除及服务提供商处理仍需独立完成。

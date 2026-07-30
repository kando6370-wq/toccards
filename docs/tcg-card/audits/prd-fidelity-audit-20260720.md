# TCG PRD 还原度审计

## 0. 审计说明

- 审计日期：2026-07-20
- PRD 真源：`docs/tcg-card/source-tcg-card-docs/20260708/TCG_PRD_整合版.md`
- 审计范围：Flutter App、Workers API、D1 迁移与模型、Admin Web 中与本 PRD 直接相关的能力。
- 判断原则：以当前可执行代码和测试为准；旧计划、完成标记和原型文案只作线索。后端已实现但 App 无入口，或代码已实现但生产依赖未就绪，均不记为完整完成。
- 状态定义：`✅ 完成`=PRD 行为闭环且有直接证据；`🟡 部分完成`=主链路存在但有规则、入口、数据或生产依赖缺口；`❌ 未完成`=未找到可执行实现；`⚪ 待确认`=现有证据不足或产品口径冲突；`➖ 不在首版范围`=PRD 明确排除。

> 还原度按下表“验收项”计数，完成项权重 1、部分完成权重 0.5、未完成/待确认权重 0；首版排除项不进入分母。该数值用于定位缺口，不等同于 iOS 上架就绪度。

## 1. 总体结论

当前项目的功能主链路已经形成真实闭环：游客/账号、Search、Scan、Portfolio、Wishlist、Home 估值、Card Detail、Profile、Feedback 均已接真实 API，运行时不依赖 demo 数据。主要差距已从“页面或接口缺失”转为跨页面异常规则、公共数据生命周期和生产依赖。

| 维度 | 结论 |
|---|---|
| 代码功能还原 | 较高；核心 CRUD、状态联动、估值和扫描均有直接实现与测试 |
| PRD 细节还原 | 尚未完全；统一 10 秒超时、离线前置拦截、Home 图表点位交互等存在缺口 |
| 生产数据可用 | 不完整；真实价格只覆盖少量目录商品，Graded 价格源未就绪 |
| 上架/外部能力 | 未完成；App Store URL、OAuth 生产凭证、TestFlight 真机验收等仍需平台侧完成 |
| 旧文档冲突 | `docs/tcg-card/README.md` 仍称 Scan 为占位页，已与当前真实扫描实现冲突，应后续清理 |

### 1.1 机械复算结果

| PRD 章节 | 完成 | 部分完成 | 未完成 | 首版排除 | 加权还原度 |
|---|---:|---:|---:|---:|---:|
| 一、全局规则 | 6 | 3 | 0 | 0 | 83.3% |
| 二、账号与登录 | 6 | 1 | 0 | 0 | 92.9% |
| 三、Profile | 6 | 2 | 0 | 0 | 87.5% |
| 四、用户资产模型 | 8 | 2 | 0 | 0 | 90.0% |
| 五、Home | 6 | 1 | 0 | 0 | 92.9% |
| 六、Search | 7 | 2 | 0 | 0 | 88.9% |
| 七、Scan | 9 | 1 | 0 | 0 | 95.0% |
| 八、Collection | 4 | 1 | 0 | 0 | 90.0% |
| 九、Card Detail | 5 | 3 | 0 | 0 | 81.3% |
| 十、资产统计与异常 | 5 | 2 | 2 | 0 | 66.7% |
| 十一、页面刷新 | 1 | 1 | 0 | 0 | 75.0% |
| 十二、首版排除 | 0 | 0 | 0 | 7 | 不计分 |
| **合计** | **63** | **19** | **2** | **7** | **86.3%** |

计算：`(63 + 19 x 0.5) / (63 + 19 + 2) = 86.3%`。

## 2. 逐条还原度矩阵

### 一、全局规则

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 1.1 局部失败状态与局部 Refresh | ✅ 完成 | Home、Search、Card Detail 等模块可独立失败和重试，不拖垮已加载区域 | `shared/ui/load_state.dart`；各模块 Controller/Widget 测试 |
| 1.1 整页失败状态与返回 | ✅ 完成 | Home、Search、Collection、Card Detail、Profile 均有页面级失败/重试 | `KandoFailureBlock`；各页面 `isUnavailable` 分支 |
| 1.1 空状态与失败状态区分 | ✅ 完成 | Search/Collection/Home 明确区分成功空集和请求失败 | `search_page.dart`、`collection_page.dart`、`home_page.dart` |
| 1.2 首屏/局部/按钮/分页 Loading | 🟡 部分完成 | 页面、局部和提交 Loading 已覆盖；未发现统一的“超过 10 秒自动转失败”机制 | `load_state.dart`；各 Controller |
| 1.3 通用失败与网络 Toast | 🟡 部分完成 | 统一文案、2-3 秒、非阻塞和状态回滚已实现；最新公共组件新增顶部 Toast，与 PRD“底部导航上方”口径不完全一致 | `shared/ui/toast.dart` |
| 1.4 金额、百分比与隐藏规则 | ✅ 完成 | 8 币种、2 位金额、`--`、`-/-`、正负号、Home/Collection 共享隐藏偏好已实现 | `shared/currency/*`；`market_change.dart`；preferences API |
| 1.5 高风险操作二次确认 | ✅ 完成 | 删除账号/文件夹、移除资产和退出未保存扫描均有确认弹窗 | `kando_modal.dart`；Profile/Collection/Card Detail/Scan 页面 |
| 1.6 防重复点击 | ✅ 完成 | 写操作期间按钮置灰或 Loading，失败恢复；主要写操作有状态锁 | 各模块 Controller 与 Widget 测试 |
| 1.7 离线资产变更规则 | 🟡 部分完成 | 请求失败后保留表单和原状态，退出离线测试已覆盖；未发现统一联网状态检测，不能证明所有写操作都在发请求前拦截 | Auth/Card Detail/Scan 测试；未发现 `connectivity_plus` 等公共拦截层 |

### 二、账号、游客资产与注册登录

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 2.1 游客可使用主要功能并保存云端资产 | ✅ 完成 | 匿名账号有真实 session 和 owner 隔离，Portfolio/Wishlist/Scan/偏好均按 owner 持久化 | `auth/anonymous.ts`、`owner-auth.ts`、D1 schema |
| 2.2 游客注册新账号迁移资产 | ✅ 完成 | 新账号注册/OAuth 首次绑定迁移文件夹、资产、Wishlist、Scan、偏好与估值事件；失败不删除游客资产 | `auth/guest-migration.ts`、`auth/account-flow.ts` |
| 2.3 游客登录已有账号不迁移 | ✅ 完成 | 登录后切换为已有 owner，原匿名身份保留；退出时恢复/创建游客态 | Auth Controller/Repository 与 `anonymous.test.ts` |
| 2.4 登录入口、协议文案与外部链接 | ✅ 完成 | Profile 和 Onboarding 可打开 Auth Sheet，Terms/Privacy 走系统外部链接 | `auth_sheet.dart`、`onboarding_page.dart`、`profile_actions.dart` |
| 2.5 Google/Apple 登录注册逻辑 | 🟡 部分完成 | 客户端授权、服务端令牌验证、新老账号分流已实现；生产凭证与 TestFlight 真机流程未验收 | `oauth_authorizer.dart`、`auth/oauth-provider.ts`、iOS readiness 审计 |
| 2.6 Email 校验与注册分流 | ✅ 完成 | 邮箱规范化、注册/登录分流、验证码、密码与错误状态均已实现 | `shared/validation/email.dart`、`email_auth_pages.dart`、Auth routes/tests |
| 2.6 忘记密码 | ✅ 完成 | 发送/校验验证码、重置密码、返回登录页和成功提示链路存在 | `auth/forgot-password.ts`、`auth_controller.dart` |

### 三、Profile 模块

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 3.1 页面范围且隐藏订阅/Restore | ✅ 完成 | 首版 Profile 未展示订阅、PRO 和 Restore | `profile_page.dart`；Profile Widget 测试 |
| 3.2 游客态 Profile | ✅ 完成 | 登录入口、客服、评分、分享、协议、版本及账号删除相关入口按游客态展示 | `profile_page.dart` |
| 3.3 已登录态 Profile | ✅ 完成 | 邮箱/ID、Account、退出、切换 owner 后刷新资产均已实现 | `profile_page.dart`、`auth_controller.dart` |
| 3.4 Account 详情与删除账号 | ✅ 完成 | 只读账号字段、退出、二次确认删除、失败保持状态均有实现 | `account_page.dart`、`auth/account.ts` |
| 3.5 Customer Support | ✅ 完成 | Type/Function 多选、邮箱和 1000 字符校验、提交 Loading、失败保留输入、真实工单落库 | `customer_support_page.dart`、`feedback/routes.ts` |
| 3.6 Score | 🟡 部分完成 | 原生评分与 App Store 回退代码已实现；生产 `app_store_url` 为空，回退链路不可用 | `profile_actions.dart`、`app-config/routes.ts` |
| 3.6 Share With Friends | 🟡 部分完成 | 系统分享代码已实现；同样受生产 `app_store_url` 为空阻断 | `profile_actions.dart`、Profile 审计 |
| 3.6 Terms / Privacy | ✅ 完成 | 生产已配置真实协议 URL，使用系统浏览器打开并处理失败 | `profile_actions.dart`、`legal/routes.ts` |

### 四、用户资产模型

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 4.1 Portfolio 多文件夹与默认选择 | ✅ 完成 | 当前/默认文件夹、单一星标、冷启动与手动选择优先级均有状态实现 | `portfolio/routes.ts`、`portfolio_providers.dart` |
| 4.2 Wishlist 不计资产且与 Portfolio 互斥 | ✅ 完成 | Wishlist 无文件夹、不进估值；Collect 后删除 Wishlist，反向写入冲突 | `wishlist.test.ts`、`items.test.ts` |
| 4.3 多 Collection Item 独立持有/取价/统计 | ✅ 完成 | 同卡多条 Item 独立保存，Qty 汇总，Most Valuable 按单条单价排序 | `collection-dashboard.ts`、`valuation-history.ts` |
| 4.4 新增 Collection Item 字段与 Adding to | ✅ 完成 | 独立新增 Sheet 含全部字段；目标文件夹在 `Adding to` 选择，不在表单重复展示 | `card_detail_page.dart`、Card Detail Widget 测试 |
| 4.4 编辑 Item 并移动文件夹 | ✅ 完成 | 编辑展示 Portfolio，字段与文件夹在单次 PATCH 原子保存，失败不移动 | `card_detail_controller.dart`、`items.test.ts` |
| 4.5 Grader/Condition/Grade 枚举与互斥 | ✅ 完成 | Raw/六家评级机构、默认值、评级区间和互斥校验已在双端实现 | `card_detail_controller.dart`、`portfolio/items.test.ts` |
| 4.5 Graded 对应市场价格 | 🟡 部分完成 | 无价仍可保存且展示 `--` 符合 PRD；但生产没有真实 Graded 价格源，无法完成估值体验 | `local-db-adapter.ts`、各业务审计 |
| 4.6 Total 实时计算 | ✅ 完成 | 按状态市场单价 x Quantity，Purchase Price 不参与，缺价为 `--` | Card Detail/Scan Controller；估值测试 |
| 4.6 Purchase Price | ✅ 完成 | 非负数字、允许小数、按当前币种输入并换算 USD 保存，不参与资产估值 | `card_detail_controller.dart`、Controller 测试 |
| 4.7 Language/Finish 来源、默认值与联动 | 🟡 部分完成 | 字段、默认与价格匹配已实现；生产目录/SKU 覆盖不足，无法证明所有卡牌均返回准确可选集合 | Card Detail models/repository；`tcgplayer_skus` |

### 五、Home 模块

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 5.1 首页资产概览定位 | ✅ 完成 | 总值、曲线、Most Valuable、Trending 四个核心区均接真实数据 | Home Repository/Page |
| 5.2 当前总资产与历史事件规则 | ✅ 完成 | 当前值、加入/移动/删除时间点、删除前历史保留、多 Item 和缺价排除均由 Workers 计算 | `portfolio/valuation-history.ts` 与测试 |
| 5.2 时间范围与曲线点位交互 | 🟡 部分完成 | 1D/7D/1M/3M/6M/MAX 和真实点位已实现；用户点击/长按曲线点显示日期金额未实现 | `home_controller.dart`、Home 审计 |
| 5.3 Most Valuable | ✅ 完成 | 当前文件夹、Wishlist 排除、按单张价、缺价排除、View 排序与空状态均实现 | `valuation-history.ts`、`home_page.dart` |
| 5.4 Trending Today | ✅ 完成 | 真实 1D 涨幅排序、首页前三、独立于文件夹并可进详情 | `data-source/routes.ts`、Home Repository |
| 5.5 文件夹规则 | ✅ 完成 | 新建/编辑/删除/排序/默认/50 字符/删除当前后回退均有实现 | `portfolio/routes.ts`、Collection 页面 |
| 5.6 货币切换 | ✅ 完成 | 8 币种、真实 `/rates`、失败保持原币种、全局金额联动已实现 | `currency_rate_api.dart`、`exchange-rates.ts` |

### 六、Search 模块

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 6.1 Cards/Sets 与 Game 数据范围 | ✅ 完成 | 两 Tab 独立状态并按真实 Game 过滤，Set 缓存使用 `game + set_code` 隔离 | Search Controller；data-source tests |
| 6.2 顶部搜索、相机、清除、Tab | 🟡 部分完成 | 交互均已实现；PRD 默认 Pokémon，但当前按生产启用 Game 排序，目录主要为 Magic | `search_page.dart`、Search 审计 |
| 6.3 各收藏类型列表字段 | 🟡 部分完成 | TCG 通用字段闭环；模型支持 sports/sealed/other，但生产数据未证明四类完整字段与价格均可用 | `search_models.dart`、`search_page.dart` |
| 6.4 Qty | ✅ 完成 | 仅统计当前文件夹同 card_ref 的 Quantity 总和，Wishlist 不参与 | `search_repository.dart`、Search tests |
| 6.4 Collect/Collected | ✅ 完成 | 快捷默认 Item、不弹表单、Wishlist 互斥；多 Item 时转详情管理 | `search_controller.dart`、`portfolio/collect.test.ts` |
| 6.4 Heart/Wishlist | ✅ 完成 | 未收藏可切换 Wishlist，已收藏不呈 Hearted，共存由服务端拒绝 | Search Controller；Wishlist tests |
| 6.5 默认排序 | ✅ 完成 | 使用服务端目录默认顺序，没有写死本地入库时间 | `local-db-adapter.ts` |
| 6.6 Sets Tab 与 Set 二级页 | ✅ 完成 | 系列列表、Game 隔离、二级卡牌分页/重试均已实现 | `set_detail_page.dart`、routes/tests |
| 6.7 无结果与加载失败 | ✅ 完成 | Cards/Sets 各自空态/失败/Refresh，不影响另一 Tab | Search Controller/Page tests |

### 七、Scan 模块

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 7.1 真实扫描入口 | ✅ 完成 | 已从占位升级为相机/相册、pHash、Workers、识别服务和 D1/R2 审计链路 | `scan_page.dart`、`scan/routes.ts` |
| 7.2 Matched/No Match/Failed 状态 | ✅ 完成 | 三类状态由真实识别结果映射，并保留 `scan_id` | `scan_result_source.dart`、Scan tests |
| 7.3 拍摄页 | ✅ 完成 | 相机权限、相册、闪光灯、裁切校正、手动拍摄均存在；另有稳定帧自动触发扩展 | `scan_camera.dart`、`scan_stability.dart` |
| 7.4 单张扫描流程 | ✅ 完成 | 识别、Review、编辑 Item、Add this card 和成功返回资产均闭环 | `scan_page.dart`、`scan_review_repository.dart` |
| 7.5 多张连续扫描流程 | ✅ 完成 | 连续采集多条结果、Review、逐项/批量添加均实现；不做同画面多卡拆分 | Scan Page/Widget tests |
| 7.6 Review Your Matches | ✅ 完成 | 候选切换、Adding to、Item 字段、Total 和局部缺价处理均实现 | `scan_page.dart`、Scan API/Widget tests |
| 7.7 No Match Found | 🟡 部分完成 | 重拍和手工 Search 存在；进入 Search 时扫描项会立即从内存删除，PRD 要求 Search 成功添加后再移除 | `scan_page.dart`、Scan 业务审计 |
| 7.8 Failed | ✅ 完成 | 可重试并保持明确失败状态，不伪装 No Match | Scan Result Source/tests |
| 7.9 Done 与未保存退出确认 | ✅ 完成 | 无未保存结果可退出，有未保存结果需二次确认 | `scan_page.dart`、Scan Widget tests |
| 7.10 添加成功与页面刷新 | ✅ 完成 | 成功写入 Item/事件、移除 Wishlist，并失效 Home/Collection/Search/Card Detail | Scan Repository/Controller |

### 八、Collection 模块

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 8.1 Portfolio/Wishlist 双 Tab | ✅ 完成 | 两类数据由真实聚合接口加载且 owner 隔离 | `collection/dashboard`、Collection Repository |
| 8.2 Portfolio 字段与独立 Item 展示 | 🟡 部分完成 | 字段、状态取价、Quantity、30D 和隐藏金额已实现；卡牌公共基础数据被下架/缺失时的持久兜底尚未闭环 | `collection_page.dart`、Collection 审计 |
| 8.3 搜索/筛选/排序 | ✅ 完成 | 当前文件夹搜索、Game/Language 多选、Sort 单选、Tab 独立状态、缺值置底均实现 | `collection_controller.dart`、Collection tests |
| 8.4 Wishlist 展示与转 Portfolio | ✅ 完成 | 不显示 Qty、不参与估值、进入详情、添加后自动移除 | Collection/Card Detail；Wishlist tests |
| 8.5 空状态与动作入口 | ✅ 完成 | Portfolio/Wishlist 文案及 Scan/Search 跳转均实现 | `collection_page.dart` |

### 九、Card Detail 与 Collection Item 编辑

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 9.1 详情页内容定位 | ✅ 完成 | 基础信息、资产状态、Price/Market/Shop 与操作入口接真实接口 | Card Detail Repository/Page |
| 9.2 未收藏详情 | ✅ 完成 | 不显示 Item/Remove，Add to Portfolio 打开独立 Adding to Sheet | `card_detail_page.dart` |
| 9.3 已收藏详情与编辑 | ✅ 完成 | 默认 Item、Price 切换、编辑/移动、Remove 和跨页刷新均实现 | Card Detail Controller/Page tests |
| 9.4 TCG 基础信息 | ✅ 完成 | 名称、Game、Set、编号/稀有度、Finish、Language 可展示 | Card Data API/Models |
| 9.4 体育卡/Sealed/特殊品基础信息 | 🟡 部分完成 | 通用类型模型和页面分支存在，缺少完整生产样本和端到端验收证据 | Search/Card Detail models；运行数据审计 |
| 9.5 Price 图表与 Market Prices | 🟡 部分完成 | RAW/GRADED、五周期、7D 百分比和分区 Refresh 已实现；Graded 数据源未就绪 | Card Detail Repository/Page；data-source adapter |
| 9.5 Shop | 🟡 部分完成 | 当前列表由 SKU 最新价格快照构造，不是真实已成交/实时 Marketplace 商品语义 | `local-db-adapter.ts`、Card Detail 审计 |
| 9.6 Remove from Portfolio/Wishlist | ✅ 完成 | 二次确认、真实删除、历史不回写和页面返回/刷新均实现 | Card Detail Controller；portfolio tests |

### 十、资产统计与异常规则

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 10.1 当前/历史价格缺失 | ✅ 完成 | 当前缺价为 `--` 且不估值；历史按此前最近有效价回放，无价点不计入 | `valuation-history.ts` |
| 10.2 各周期涨跌幅公式 | ✅ 完成 | 30D/1D/7D 按同一公式，基准缺失或 0 显示 `-/-` | `market_change.dart`、Workers adapter |
| 10.3 Portfolio 总资产 | ✅ 完成 | 当前文件夹、Quantity、缺价排除、Wishlist 排除、Most Valuable 单价排序均实现 | valuation/dashboard tests |
| 10.4 card_id/product_id 唯一识别 | ✅ 完成 | 各模块统一使用 `card_ref/product_id`，不以名称判重 | D1 schema、各 API 合约 |
| 10.5 Delisted | ❌ 未完成 | 未找到公共卡状态字段、下架过滤且保留用户资产的完整实现 | `db/schema.ts`、data-source/portfolio routes |
| 10.5 Merged/canonical_card_id | ❌ 未完成 | 未找到 canonical 映射和自动迁移用户 Item 的实现 | 全仓检索无对应生命周期代码 |
| 10.5 Unavailable 与恢复 | 🟡 部分完成 | 缺价/缺基础信息可局部降级，但没有显式 unavailable 状态、最近基础信息快照及恢复时间点规则 | Collection 审计；现有 fallback 代码 |
| 10.6 服务端为准与最后保存覆盖 | 🟡 部分完成 | 写成功后重拉/失效缓存，当前 PATCH 为最后写覆盖；未见版本字段或并发冲突专门测试 | 各 Controller；portfolio routes |
| 10.7 批量添加部分/全部失败 | ✅ 完成 | 成功项移除、失败项保留、部分失败 Toast、全部失败保留草稿均实现 | `scan_page.dart`、Scan 审计 |

### 十一、页面刷新范围

| PRD 条目 | 状态 | 当前实现与差距 | 证据 |
|---|---|---|---|
| 资产写入后刷新 Home/Collection/Search/Card Detail/文件夹 | ✅ 完成 | Controller 主动失效相关 Provider，聚合接口重读服务端状态 | Search/Card Detail/Scan Controllers |
| 操作成功但刷新失败 | 🟡 部分完成 | 多数模块保留已确认状态并提供 Refresh；未找到覆盖全部十个刷新目标的统一事务级验证 | 各模块异常测试 |

### 十二、首版不做 / 暂不支持

| PRD 排除项 | 状态 | 当前实现 |
|---|---|---|
| 订阅/PRO、Restore | ➖ 不在首版范围 | 未在 App 展示 |
| 离线保存/Pending sync | ➖ 不在首版范围 | 未实现离线队列 |
| No Match 创建 Custom Card | ➖ 不在首版范围 | 未实现 |
| 同画面多卡拆分、自动实体卡去重 | ➖ 不在首版范围 | 未实现；当前是连续单卡扫描 |
| Wishlist 与 Portfolio 共存 | ➖ 不在首版范围 | 服务端强制互斥 |
| Search 涨跌金额、固定本地入库排序 | ➖ 不在首版范围 | 仅百分比并沿用服务端排序 |
| 体育卡复杂扩展字段 | ➖ 不在首版范围 | 首版未扩展展示 |

## 3. 未完成与部分完成项优先级

| 优先级 | 缺口 | 建议验收标准 |
|---|---|---|
| P0 | 生产价格覆盖率不足、无真实 Graded 价格源 | 配置真实数据源并完成回填；用 Raw 与 Graded 生产样本验证 Search、Detail、Collection、Home 全链路 |
| P0 | App Store/OAuth/TestFlight 外部配置未完成 | 配置真实 URL/凭证，真机通过 Google/Apple、评分、分享、相机、相册、账号删除 |
| P1 | `Delisted/Merged/Unavailable` 生命周期未实现 | 增加明确状态/映射/历史事件规则，并覆盖 Search 下架、资产保留、合并迁移、恢复估值测试 |
| P1 | 离线写操作缺统一前置拦截 | 所有 PRD 写操作断网时不发请求、保留草稿/原状态、统一网络 Toast |
| P1 | Home 曲线点位交互缺失 | 点击或长按任意点显示该日期及换算后的资产金额 |
| P1 | Scan No Match 转 Search 生命周期偏差 | Search 成功添加后才删除待处理 Scan；取消/返回可恢复原扫描项 |
| P2 | 统一 Loading 10 秒超时缺失 | 公共加载策略超过 10 秒稳定转失败态，局部与整页均有测试 |
| P2 | Toast 展示位置与 PRD 冲突 | 产品确认顶部或底部；统一调用点并清理另一套口径 |
| P2 | 多类型收藏品生产验收不足 | 各取 TCG、体育卡、Sealed、特殊品真实样本完成列表/详情/收藏回归 |

## 4. 证据索引

| 证据面 | 关键文件 |
|---|---|
| Flutter 路由与页面 | `apps/flutter-app/lib/app/router.dart`、`features/*/*_page.dart` |
| Flutter 状态与真实 API | `features/*/*_controller.dart`、`features/*/*_repository.dart`、`shared/portfolio/portfolio_api_client.dart` |
| Workers 路由 | `apps/workers-api/src/index.ts`、`auth/*`、`portfolio/routes.ts`、`data-source/routes.ts`、`scan/routes.ts` |
| 数据与历史 | `apps/workers-api/src/db/schema.ts`、`db/migrations/*`、`portfolio/valuation-history.ts` |
| 自动化测试 | `apps/flutter-app/test/**`、`apps/workers-api/src/**/*.test.ts`、`apps/admin-web/test/**` |
| 既有业务审计 | `docs/tcg-card/audits/*-business-audit.md`、`runtime-data-audit.md`、`ios-release-readiness.md` |

## 5. 审计边界与待确认

1. 本文确认的是当前仓库代码还原度，不把历史生产 smoke 视为 2026-07-20 的实时生产状态；生产价格覆盖、部署版本和配置可能发生变化，应在发布前重新回读。
2. 本轮未进行 iOS 真机、相机实拍、OAuth、App Store、视觉像素级验收，因此这些能力不能标记为生产完成。
3. `docs/tcg-card/README.md` 的 Scan 占位描述和 `docs/superpowers/execution-status.md` 的历史完成状态均不是当前 PRD 验收真源。
4. PRD 关键口径第 12 条原文“Condition 统一使用 `Near Mint (NM)`，不使用 `Near Mint (NM)`”前后相同，明显为文本错误；当前代码按后文明确规则拒绝旧拼写 `Nearly Mint (NM)`。

## 6. 本轮验证记录

| 验证项 | 2026-07-20 当前 HEAD 结果 |
|---|---|
| Workers API | 28 个测试文件、253 项测试通过，无失败/跳过 |
| Admin Web | 6 项测试通过，无失败/跳过 |
| Flutter App | 355 项测试通过，1 项跳过，无失败；跳过项为缺少平台 `dartcv` 动态库的 OpenCV 等价测试 |
| TypeScript 类型检查 | Turbo 7/7 个任务成功 |
| Flutter 静态检查 | `flutter analyze`：No issues found |
| 文档结构 | 12 个 PRD 一级章节均存在逐条矩阵；状态机械计数为 63 完成、19 部分、2 未完成、7 首版排除 |
| Markdown/差异 | `git diff --check` 通过 |

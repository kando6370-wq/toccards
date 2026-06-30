Collection 模块 PRD
一、页面定位
Collection是用户管理卡牌资产和心愿单的核心页面，包含两个 Tab：
Portfolio：管理用户已收藏、已拥有、已加入文件夹的卡牌资产。
Wishlist：管理用户想关注、想购买、暂未拥有的卡牌。wishlist无文件夹
进入 Collection 后，默认展示图中的 Collection - Portfolio 页面。

⸻

二、页面入口
点击底部导航 Collection 进入。
从 Home 的 Most Valuable 点击 View进入。
从卡牌详情页返回 Collection。
从 Scan 结果页添加卡牌到 Portfolio 后，可进入 Collection 查看。
从 Search 添加卡牌到 Portfolio / Wishlist 后，可进入 Collection 查看。
App 冷启动后，用户点击底部导航进入 Collection 时，默认展示星标文件夹的 Portfolio 数据。

⸻

三、页面结构与字段说明
3.1 顶部区域
页面字段
字段 / 控件
说明
页面标题
Collection
当前文件夹入口
展示当前 Portfolio 文件夹名称
Tab
Portfolio、Wishlist
搜索框
用于搜索当前 Tab 下的卡牌
筛选 / 排序入口
用于调整列表展示顺序或筛选条件
规则
进入 Collection 后默认选中 Portfolio Tab。
当前文件夹默认取星标文件夹。
用户手动切换文件夹后，当前页面展示切换后的文件夹数据。
手动切换文件夹的优先级高于默认文件夹，直到下一次冷启动。
Portfolio Tab 受当前文件夹影响。
Wishlist 无文件夹不受影响
用户从 Home 切换文件夹后进入 Collection，应同步展示同一文件夹。
用户从 Collection 切换文件夹后返回 Home，Home 也应同步展示同一文件夹。

⸻

3.2 Portfolio Tab
Portfolio 展示当前文件夹内用户已收藏的卡牌资产。
列表字段

字段
展示规则
备注
卡牌图片
展示卡牌封面；缺失时展示占位图
Graded 卡展示评级封装图，Raw 卡展示普通卡图
卡牌名称
展示卡牌名称；超长省略
建议最多 2 行，超过后省略
卡牌语言
展示卡牌上的语言种类
只表示英文以外的语言，例如CN JP
卡牌编号
展示卡牌编号
例如 #230、038、130/094
Set / 系列
展示卡牌所属系列
例如 The First Chapter、Mega Evolution Promos
Finish / Variant
展示卡牌工艺或版本
例如 Holofoil、Reverse Holo、1st Edition
grader和condition
Raw 卡展示 Raw · Near Mint；评级卡展示 PSA 10、BGS 9.5 等
Raw 品相和评级状态不可混用
数量
Portfolio 卡牌展示数量
例如 Qty: 1
当前价值
展示当前 Collection Item 的市场价值
当前价值 = 对应市场价 × 数量
涨跌幅
固定展示 30D Change
不随 Home 图表周期变化
金额隐藏按钮
眼睛图标；闭眼后隐藏金额；与 Home 资产隐藏状态联动同步
影响当前价值、变化金额等资产金额字段
金额/卡牌总数量/评级卡数量
该文件夹内卡牌总金额/总卡牌数量/评级卡数量
金额精确到小数点后两位

展示规则
Portfolio 只展示当前文件夹内已收藏卡牌。
Wishlist 卡牌独立展示一个表
每条卡牌按用户保存的 Collection Item 状态取价：
Raw / Ungraded：取 Raw 市场价。
Graded：按评级机构和等级取对应 Graded 市场价。
如果同一张卡存在多个 Collection Item，例如 Raw 一张、PSA 9 一张，应作为不同资产项展示，避免价格口径混乱。
当前价值 = 对应市场价 × 数量。
如果当前市场价缺失，价格展示为 --，该项不计入总资产。
涨跌幅展示 30D Change：
当前价格相对 30 天前同口径价格的变化比例。
货币切换后，涨跌幅不变。
如果 30 天前无有效价格，展示 -/-。
（当前-加入价）/加入价格
卡牌名称、系列名过长时单行省略。
Raw condition 和 Graded 状态不要混用：
Raw：展示 Raw · NM / LP / MP。
Graded：展示 PSA 10 / BGS 9.5 / CGC 10。


⸻

3.3 Portfolio 金额隐藏
Portfolio 数据卡片上有眼睛图标。
规则
点击眼睛图标后，当前 Portfolio 列表中的金额类字段隐藏。
再次点击后恢复显示。
闭眼状态下，卡牌当前价值展示为 •••• 或同类占位。
闭眼状态应与Home 的资产隐藏状态同步。如果用户在 Home 隐藏资产金额，进入 Collection 后 Portfolio 金额也保持隐藏；如果用户在 Collection 恢复显示，Home 也同步恢复。

⸻

3.4 Portfolio 排序/筛选规则
范围：选中的文件夹，wishlist和portfolio互不影响
默认排序/筛选
Portfolio 默认按卡牌加入当前文件夹的时间倒序排列。
加入时间晚的卡牌排在上方。
加入时间早的卡牌排在下方。
默认排序只在用户没有手动修改排序时生效。
默认无筛选条件
排序
Sort 为单选。
用户只能选择一个排序条件。
选中项高亮，并展示选中标识。
点击其他排序项后，替换当前排序条件。
点击模块右侧 -，收起当前模块。
点击 Apply Filters 后，列表按所选排序刷新。
用户手动修改排序后，系统不会自动重置排序。
后续进入 Collection 时，保持用户上次选择的排序规则，除非用户点击 Clear 或手动修改排序。

Game/IP筛选
Game / IP 支持多选。
用户可同时选择多个 IP。
已选项高亮展示。
再次点击已选项，取消选择。
如果未选择任何 Game / IP，表示不限 IP。
点击 Apply Filters 后，只展示符合所选 Game / IP 的卡牌。
收起态按逗号展示已选 IP。
已选项过多时，建议展示前 2 个 + 数量。

language筛选
Language 支持多选。
用户可同时选择多个语言。
已选语言高亮展示。
再次点击已选语言，取消选择。
如果未选择任何语言，表示不限语言。
点击 Apply Filters 后，只展示符合所选语言的卡牌。
收起态按逗号展示已选语言，例如 English, Japanese。
已选项过多时，建议展示前 2 个 + 数量，例如 English, Japanese +2。

展开/收起

默认进入筛选弹窗时，各模块为收起态。
点击模块右侧 + 展开该模块。展开后右侧变为 -，点击 - 收起该模块。
允许多个模块同时展开，减少用户反复点击。
收起模块不会清空该模块已选条件。

apply filters
点击 Apply Filters 后，应用当前弹窗内的排序和筛选条件。弹窗关闭。
Collection 列表刷新。
筛选条件作用于当前 Collection Tab。
在 Portfolio Tab 中，筛选范围为当前选中文件夹内的 Portfolio 卡牌。
在 Wishlist Tab 中，筛选范围为 Wishlist 卡牌。
搜索关键词、筛选条件、排序条件可以同时生效。
应用后如果无结果，展示无结果状态。

数据保留
用户点击 Apply Filters 后，筛选 / 排序条件生效并保存。
用户返回 Collection 时，保持上次应用的筛选 / 排序状态。
用户切换 Portfolio / Wishlist 后，各 Tab 独立保存筛选 / 排序条件。
用户点击 Clear 并 Apply Filters 后，清空当前 Tab 的筛选 / 排序条件。
App 冷启动后不保留筛选条件和排序；使用期间如果用户不再手动操作排序，系统不会自动重置回默认配置。
用户切换文件夹后，排序筛选规则沿用当前用户选择的，数据范围切换为新文件夹。
用户修改后的排序规则应在当前设备 / 当前账号下保留。多设备不同步。



异常

场景
规则
筛选后无结果
展示 No matching cards found.
筛选请求失败
Toast：Something went wrong. Please try again later.
排序请求失败
保持原列表顺序，Toast 提示失败
选项加载失败
当前模块展示失败提示，可点击重试
网络异常
不清空原列表，保留上一次成功结果
补充异常：
缺少价格的卡牌在价格排序中排在底部。
缺少涨跌幅的卡牌在涨跌幅排序中排在底部。




⸻

3.5 Portfolio 搜索规则
规则
搜索框用于搜索当前 Portfolio Tab 下的卡牌。
搜索范围限定在当前选中文件夹内。
输入关键词点击搜索后显示搜索结果。
搜索支持卡牌名称、系列名、编号、IP / Game。
搜索结果仍遵循当前排序规则。
清空搜索词后恢复当前文件夹完整列表。
搜索无结果时展示空状态：No matching cards found.

⸻



3.6 Portfolio 卡牌点击与分享
点击卡牌
点击 Portfolio 卡牌项，进入 Portfolio 卡牌详情页。
详情页展示该 Collection Item 的完整信息。
用户在详情页修改 Collection Item 后，返回 Collection 时列表数据刷新。
用户在详情页删除卡牌后，返回 Collection 时该卡从当前文件夹移除。
分享卡牌
点击分享按钮，调起苹果原生分享弹窗组件。
分享内容可分享到第三方 App。
分享内容包含卡牌名称和卡牌详情链接。
如果无可分享链接，至少分享卡牌名称和当前价格文本。
用户取消分享后，停留当前页面，不展示错误提示。
分享调起失败时，提示：something went wrong,Please try again later.（建议补充）。
分享不改变卡牌数据，不改变排序，不改变收藏状态。

⸻

3.7 Wishlist Tab
Wishlist 展示用户加入心愿单的卡牌。
卡片字段
字段
说明
卡牌图片
展示卡牌封面
卡牌名称
展示卡牌名称，超长省略
卡牌语言
展示英语以外的语言，如JP CN
卡牌编号
例如 #230、038、130/094
Set / 系列
例如 The First Chapter、Mega Evolution Promos
Finish / Variant
例如 Holofoil
当前市场价
展示当前价格
涨跌幅
固定展示 30D Change


与 Portfolio 的区别
Wishlist 不展示数量。
Wishlist 不计入 Home 总资产。
Wishlist 不计入 Portfolio 总价值。
Wishlist 不计入 Most Valuable。
Wishlist 中的价格是市场参考价，不是用户资产价值。
Wishlist 卡牌点击后进入普通卡牌详情页，不进入 Portfolio Collection Item 详情。
如果用户从 Wishlist 将卡牌加入 Portfolio，默认加入当前选中文件夹（非默认星标文件夹如果当前选中的不是星标文件夹）。
加入 Portfolio 后自动从 Wishlist 列表中移除。

⸻

3.9 Wishlist 排序、搜索、筛选
默认排序
Wishlist 默认按加入 Wishlist 的时间倒序排列。
加入时间晚的卡牌排在上方。
用户手动修改排序后，下次冷启动前不自动恢复默认排序。
搜索
搜索范围为 Wishlist 全量卡牌。
搜索支持卡牌名称。
建议支持系列名、编号、IP / Game。
搜索无结果展示：No matching cards found。

⸻

3.10 文件夹切换与管理
Collection 的 Portfolio 文件夹逻辑与 Home 保持一致。
文件夹规则
小星星表示默认文件夹。
默认文件夹用于冷启动后 Home 和 Portfolio 默认展示。
默认文件夹不可删除。
默认文件夹只能有一个。
用户手动切换文件夹的优先级高于默认文件夹。
用户手动切换后，在下一次冷启动前，Home 和 Collection 的 Portfolio 都展示该文件夹数据。
下一次冷启动后，重新展示星标默认文件夹。
按住文件夹左侧小标识可上下拖动排序。
排序结果同步 Home 和 Collection。
新建文件夹弹窗标题为 Add new portfolio。
编辑文件夹弹窗与新建弹窗一致，标题为 Edit portfolio。
新建文件夹成功后，回到文件夹列表。
新建文件夹不自动成为默认文件夹，用户需手动点击星标设置。
文件夹删除
默认文件夹不可删除。
删除非默认文件夹前展示确认弹窗。
删除后，该文件夹内所有卡牌随文件夹一起删除。
如果删除的是当前选中文件夹，删除成功后自动切换到默认文件夹。
删除失败时提示：Something went wrong. Please try again later.

⸻

四、异常

4.1 Portfolio 空状态
触发条件：
当前文件夹没有任何 Portfolio 卡牌。
新建文件夹后尚未添加卡牌。
用户删除当前文件夹内全部卡牌。
展示内容：
标题：No cards in this portfolio yet.
说明：Scan or search cards to start tracking your collection.
主按钮：Scan a Card
次入口：Search Cards
交互：
点击 Scan a Card 进入 Scan。
点击 Search Cards 进入 Search。
从 Scan / Search 添加成功后，返回 Portfolio 有数据状态。

⸻

4.2 Wishlist 空状态
触发条件：
用户尚未添加 Wishlist 卡牌。
用户移除了所有 Wishlist 卡牌。
建议展示：
标题：your wishlist is empty.
说明：save cards you want to collect later and keep an eye on their market value.
主按钮：Search Cards

⸻

4.3 搜索无结果
触发条件：
用户输入关键词后，当前 Tab 下无匹配卡牌。
当前筛选条件下无匹配卡牌。
建议展示：
No matching cards found.
保留搜索框和筛选入口。
用户清空关键词或重置筛选后恢复列表。

⸻

4.5 加载中
首次进入 Collection 时展示列表骨架。
切换 Portfolio / Wishlist 时展示局部 loading。
切换文件夹时展示局部 loading。
搜索、筛选、排序如果需要请求接口，可展示短 loading。
不整页阻断，底部导航保持可用。

⸻

4.6 加载失败
1.页面弹窗提示
文案No content available 
主按钮refresh 次按钮cancel
使用场景
列表加载失败。
页面数据请求失败

2.toast提示
文案Something went wrong. Please try again later 
筛选失败。
文件夹切换失败。
新建 / 编辑 / 删除文件夹失败。
分享组件调起失败。
卡牌数据刷新失败。
toast显示2秒左右自动消失

补充
页面需要内容或数据加载填充失败的时候用弹窗，弹窗上给按钮可直接点击刷新再次获取数据比如首页图表、trending today数据请求失败等。
局部操作失败或状态切换失败时用toast提示失败并停留或返回原页面，比如切换货币失败、切换文件夹失败等等。
失败后不清空用户已有列表数据，优先保留旧数据。


⸻

五、数据与展示规则
5.1 Portfolio 数据范围
Portfolio 只展示当前选中文件夹内的 Collection Item。
当前文件夹由 Home / Collection 手动切换状态或星标默认文件夹决定。
卡牌加入当前文件夹后，出现在 Portfolio 列表中。
卡牌从当前文件夹移除后，不再出现在 Portfolio 列表中。
Wishlist 数据不进入 Portfolio 列表。
同一张卡可存在多个 Collection Item，按不同状态分别展示（建议补充）

⸻

5.2 涨跌幅
Portfolio 和 Wishlist 卡牌列表中的涨跌幅统一展示 30D Change。
30D Change = 当前市场价相对 30 天前同口径市场价的变化比例。
Raw 卡按 Raw 市场价计算。
Graded 卡按对应评级机构和等级的市场价计算。
涨跌幅为正时展示 +。
涨跌幅为负时展示 -。
无足够历史价格时展示 -/-。
涨跌幅不受货币切换影响。
涨跌幅不跟随 Home 图表周期变化。

⸻

5.3 数量
Portfolio 卡牌展示数量。
数量来自用户编辑的 Collection Item。
数量参与当前价值计算。
当前价值 = 当前单张市场价 × 数量。
Wishlist 不展示数量。

⸻

5.5 分享
分享按钮只触发系统分享，不修改数据。
iOS 端调用苹果原生分享弹窗组件。
用户可分享至第三方 App。
分享内容建议包含：
卡牌名称。
卡牌编号。
当前价格。
app卡牌详情链接。未安装app的用户打开链接时给官网页面引导用户下载
分享取消不提示错误。
分享失败使用通用toast失败提示Something went wrong. Please try again later。

⸻

六、业务规则
Collection 默认进入 Portfolio。
Portfolio 是用户资产集合，参与 Home 总资产、Home 图表、Most Valuable。
Wishlist 是心愿单，不参与 Home 总资产、Home 图表、Most Valuable。
Portfolio 文件夹影响 Home 和 Collection 的 Portfolio 数据。
文件夹切换优先级高于默认文件夹，但只持续到下一次冷启动。
星标文件夹是冷启动默认文件夹。
默认文件夹不可删除。
Portfolio 默认排序为加入当前文件夹时间倒序。
用户修改排序后，下次冷启动前系统不自动重置排序。
分享卡牌使用 iOS 原生分享组件。
Search / Scan 添加到 Portfolio 时，默认加入当前选中文件夹。
Search 添加到 Wishlist 时，不影响 Portfolio 和 Home 总资产。
Card Detail 修改 Collection Item 后，Collection 列表需要刷新对应数据。
Card Detail 删除 Portfolio 卡牌后，Collection 列表移除该项。


Home 模块 PRD
一、页面定位
Home 是用户进入 App 后查看收藏资产概览的首页，核心展示当前选中文件夹的总价值、价值变化趋势、文件夹内最高价值卡牌，以及二级市场当日升值幅度最高的卡牌。
Home 不承载 Wishlist 管理，不承载完整 Portfolio 列表管理，不承载订阅权益展示。页面中当前出现的 PRO 后续删除，因此本 PRD 不写 Subscribe / PRO 相关逻辑。

⸻

二、页面入口
用户冷启动 App 后进入 Home。
用户点击底部导航 Home 进入。
用户从 Scan 添加卡牌后，可返回 Home 查看资产变化。
用户从 Search 添加卡牌到 Portfolio 后，可返回 Home 查看资产变化。
用户从 Collection 修改 Portfolio 卡牌信息后，可返回 Home 查看更新后的总价值和图表。

⸻

三、页面结构与字段说明
3.1 顶部区域
页面顶部包含：
区域
字段 / 控件
说明
顶部 Tab
Overview
当前页面默认展示
顶部 Tab
Performance
为1.0.1需求
右上角
货币入口，当前为 USD
点击打开货币选择弹窗
规则
Home 默认进入 Overview。
    2       右上角货币入口展示当前选中的货币码。
页面中的 PRO 后续删除，本模块不定义订阅入口和订阅状态。

⸻

3.2 Portfolio 总资产卡片
该区域展示当前选中文件夹的资产总览。
页面字段
字段
页面展示 / 说明
模块标题
PORTFOLIO
当前文件夹
Main
总资产金额
$8,538.53
资产隐藏按钮
金额右侧眼睛图标
价值变化文案
+$0.00 in the last 30 days
图表
当前文件夹价值趋势曲线
时间维度
1D、7D、1M、3M、6M、MAX
当前选中周期
示例中为 1M
数据含义
总资产金额表示当前选中文件夹内全部 Portfolio 卡牌的当前总价值。
图表区域展示当前选中文件夹的价值变化。
图表数据从卡牌被收藏进该文件夹之日起开始追踪。
卡牌加入文件夹之前，不计入该文件夹历史资产。
卡牌从文件夹删除后，从删除时间点开始资料都删掉且不再计入后续资产。
+$0.00 in the last 30 days 表示当前选中文件夹过去 30 天的总价值变化。
	
图表价格取值规则
Home 图表根据用户在 Collection Item 中编辑的字段判断卡牌价格类型。
如果用户设置为 Raw / Ungraded，则取该卡对应 Raw 市场价。
如果用户设置为 Graded，则根据评级机构和评级等级取对应 Graded 市场价。
评级相关字段以 Collection Item 中用户保存的数据为准。
总价值 = 当前文件夹内所有卡牌的单张当前市场价累加。
如果同一张卡存在多条不同 Collection Item，例如 Raw 一张、PSA 9 一张，应分别取价后累加。
如果同一 Collection Item 有数量字段，则该条价值 = 对应市场价 × 数量。
如果某张卡缺少当前市场价，该卡在总价值中展示规则需明确：建议该卡价格展示为 --，不计入总资产，避免用购买价误导用户（建议补充）。
图表交互
点击时间维度后，图表按所选周期刷新。
图表周期只影响曲线范围，不改变当前总资产金额。
30 天变化文案固定展示过去 30 天，不随图表周期变化。
点击或长按曲线点位时，展示该日期和对应的总资产金额。
图表数据加载中时，展示 loading。
图表加载失败时，展示模块内错误，不弹出整页错误弹窗。

当用户从 Portfolio 中删除某张卡牌 / Collection Item ：
1.该卡牌从删除时间点开始不再计入当前文件夹的当前总资产、后续图表数据、Most Valuable 和 Portfolio 列表。
2.删除前，该卡牌曾经属于当前文件夹的历史资产记录保留。Home 图表按每个时间点的实际持仓计算：卡牌加入文件夹前不计入；加入后计入；删除后不再计入。
3.如果删除发生在当前图表周期内，删除造成的资产减少应体现在该周期的资产变化中。
4.删除后，该卡牌从 Most Valuable 排序中移除。如果该卡原本是最高价值卡，则 Most Valuable 自动展示当前文件夹内下一张单张价值最高的卡牌。
5.如果用户后续重新将该卡加入 Portfolio，则视为新的 Collection Item / 新的持有周期，从重新加入时间开始计入图表。

某些日期没有价格
价格缺失时，优先使用距离该时间点最近的前一个有效价格；如果没有任何有效历史价格，则该时间点不计入资产。


⸻

3.3 资产隐藏按钮
页面在总资产金额右侧展示眼睛图标。
规则
点击眼睛图标后，隐藏当前 overview 中资产金额。
再次点击后恢复显示。
隐藏后，总资产金额为 ••••••。

⸻

3.4 Most Valuable 区域
该区域展示当前选中文件夹内单张价值最高的卡牌。和上方图表的时间选项不关联。
展示字段

字段
展示规则
模块标题
Most Valuable
卡牌名称
展示卡牌名称，超长省略
状态
Raw 卡展示 Near Mint · Holofoil；Graded 卡展示 PSA 10 (GEM-MT) · Holofoil
当前单张价格
展示该 Collection Item 当前单张市场价
涨跌幅
固定展示 30D Change
View All
点击进入 Collection - Portfolio 列表

Sealed Products 套盒 / 卡包 / 整箱字段
字段
展示规则
示例
产品名称
主标题
Evolving Skies Booster Box
IP / Game + Set
副信息
Pokémon · Evolving Skies
Product Type + Configuration
规格信息
Booster Box · 36 Packs
状态
展示 Sealed / Opened
Sealed · English
当前单件价格
右侧金额
$780
30D Change
右侧百分比
+5.34%

体育卡字段
字段
展示规则
示例
球员 / 卡牌名称
主标题
Shohei Ohtani
Sport / 年份 / 品牌
副信息，空间够展示
Baseball · 2024 Topps Chrome
Team / Insert / Card Number
版本信息，空间不够可省略 Team
Dodgers · Refractor · #17
状态
Raw 展示品相；Graded 展示评级
Near Mint / PSA 10
Special Tags
有则展示，和状态同一行或版本行
RC、Auto、Patch、/99
当前单张价格
右侧金额
$240
30D Change
右侧百分比
+8.12%


展示逻辑
Most Valuable 只统计当前选中文件夹内的 Portfolio 卡牌。
Wishlist 卡牌不参与 Most Valuable。
排序按照单张卡牌价值从高到低。
单张卡牌价值根据该 Collection Item 的状态取价：
Raw / Ungraded：取 Raw 市场价。
Graded：取对应评级机构和等级的市场价。
如果同一张卡用户持有多张，Most Valuable 仍按单张卡牌价值排序，不按总持有价值排序。
如果同一张卡存在多个状态，例如 Raw、PSA 9、PSA 10，应视为不同 Collection Item 分别排序。
页面首页只展示价值最高的一张卡。
点击 View  后，进入 Collection 的 Portfolio 列表，并按单张卡牌价值降序展示。
如果当前文件夹无卡牌，展示 No cards in this portfolio yet，不展示具体卡牌项。


需要避免的字段冲突
Raw condition 和 Graded 状态不要混在同一行。
如果卡牌为 Raw，展示 LP / NM / MP 等 condition。
如果卡牌为 Graded，只展示 PSA 9、BGS 9.5、CGC 10 等评级信息。不展示其他过多评级相关信息。

⸻

3.5 Trending Today 区域
该区域展示eBay和tcg player当天升值幅度最高的卡牌。
页面字段
字段
说明
标题
Trending Today
查看全部入口
View
卡牌图片
图片或占位图
卡牌名称
示例中有 Charizard ex、Umbreon VMAX、Blue-Eyes White Dragon
IP / 系列
示例中有 Pokémon、Yu-Gi-Oh! 等
当前价格
当前市场价
涨跌幅
当天涨跌幅
数据规则
Trending Today 展示二级市场当天升值幅度最高的卡牌。
排序按照当天涨幅百分比从高到低。
该模块不受当前选中文件夹、用户收藏卡牌等等其他模块的信息影响。
首页建议展示 3 条，。
点击 View 后进入 Trending 完整列表或 Search 结果页，并保留 Trending 排序。
点击单张卡牌进入非 Portfolio 卡牌详情页。
卡牌字段
字段
说明
卡牌图片
缺图展示占位图
卡牌名称
超长省略
IP / Game
Pokémon、Yu-Gi-Oh!、Magic 等
Set / 系列
卡牌所属系列
当前市场价
按当前货币展示
当日涨跌幅
按当天价格变化展示
View / View All
点击进入 Trending 列表或 Search 结果页

涨跌幅规则
当日涨跌幅 = 当前价格相对前一日收盘价或昨日均价的变化比例。
正数展示 +。
负数展示 -。
切换货币后，涨跌幅不变。
如果数据源没有严格收盘价，建议用最近 24 小时均价变化计算，并在数据口径中统一。
   6       根据eBay、tcg player拿到的各个sku的价格信息自身进行对比，或者直接可以拿到现成数据
⸻

3.6 Portfolio 文件夹切换弹窗
点击 Home 中当前文件夹名称后，打开文件夹切换弹窗。
页面字段
字段 / 控件
说明
文件夹列表
展示用户已有 Portfolio 文件夹
当前选中标识
左侧小标识 / 单选状态
默认文件夹标识
小星星
编辑入口
文件夹右侧编辑图标
删除入口
文件夹右侧删除图标
拖动排序
按住文件夹左侧小标识可上下拖动
新建按钮
+ Add new
文件夹核心概念
文件夹用于区分用户自身角度的不同 Portfolio 资产集合。
当前选中文件夹决定 Home 展示的数据。
当前选中文件夹也应决定 Portfolio 页面默认展示的数据。
小星星表示默认文件夹。
默认文件夹用于 App 冷启动后的默认展示。
每次冷启动时，Home 和 Portfolio 默认展示的数据都来自星标文件夹。
默认文件夹不可删除。
默认文件夹只能有一个。
切换文件夹的操作优先级高于默认文件夹。
用户手动切换到另一个文件夹后，在下一次冷启动之前，Home 和 Portfolio 都跟随本次切换操作展示该文件夹数据。
下一次冷启动时，如果用户没有更改默认文件夹，则重新回到星标文件夹。
如果用户把当前切换的文件夹设为星标，则后续冷启动默认展示该文件夹。
文件夹切换规则
点击文件夹行后，切换当前 Home 数据数据。
切换后总资产、图表、Most Valuable 立即刷新。
Trending Today 不随文件夹切换变化。
文件夹弹窗关闭后，Home 顶部当前文件夹名称同步更新。
Portfolio 页面同步当前选中文件夹的更改信息。
切换失败时，保留原文件夹，并提示失败。
文件夹排序规则
用户按住文件夹左侧小标识，可上下拖动调整顺序。
排序结果应用于文件夹弹窗展示顺序。
排序结果应同步到 Portfolio 页面文件夹列表。
排序后建议自动保存。
保存失败时回滚到调整前顺序，并提示失败。
文件夹删除规则
删除非默认文件夹需弹出确认弹窗操作。
弹窗字段：

字段
页面展示
标题
Are you sure you want to delete this cards portfolio?


按钮
Cancel、Delete
规则：
点击非默认文件夹删除图标，展示确认弹窗。
点击 Cancel 关闭弹窗，不删除。
点击 Delete 删除该文件夹。
删除后，该文件夹内所有卡牌随文件夹一起删除。
默认文件夹不可删除，删除入口应隐藏或置灰。
当前选中文件夹被删除后，自动切换到默认文件夹。
删除失败时保留原数据，并展示失败提示。

⸻

3.7 新建文件夹弹窗
点击 + Add new 后进入新建文件夹弹窗。
页面字段
字段
页面展示
标题
Add new portfolio
输入项标题
Name of portfolio
输入框 placeholder
Name
返回按钮
左下角返回箭头
保存按钮
Save
规则
用户输入文件夹名称。
点击 Save 创建新文件夹。
点击返回箭头，返回文件夹列表。
新建成功后，展示文件夹列表的弹窗。用户可在此弹窗中对新文件夹进行操作

表单校验
名称必填。
名称不可只输入空格。
文件夹之间的名称不可重复。
名称建议限制 1–50个字符。
输入为空时，Save 置灰无法点击。
名称重复时提示 Portfolio name already exists
创建失败时提示 Failed to create portfolio. Please try again

⸻

3.8 编辑文件夹弹窗
字段
编辑弹窗与新建弹窗一致。
字段
说明
标题
Edit portfolio
输入项标题
Name of portfolio
输入框
默认填入当前文件夹名称
返回按钮
返回文件夹列表
保存按钮
Save
规则
点击文件夹右侧编辑图标，进入 Edit portfolio 弹窗。
输入框默认显示当前文件夹名称。
修改后点击 Save 保存。
保存成功后，Home 和 Portfolio 中该文件夹名称同步更新。
如果编辑的是当前选中文件夹，Home 顶部名称立即更新。
默认文件夹允许编辑名称，但不可删除。
保存失败时提示 Failed to update portfolio. Please try again.
名称重复时提示 Portfolio name already exists.

⸻

3.9 Home 无数据状态
触发条件：
当前选中文件夹没有任何 Portfolio 卡牌。
用户首次进入 App，还没有添加卡牌。
用户删除了当前文件夹内全部卡牌但并未删除文件夹。
页面字段
字段 / 控件
页面展示
标题
Add your first card
说明
Start tracking your collection value, price trends, and top cards.
主按钮
Scan a Card
次入口
Search Cards
Most Valuable 空文案
No cards in this portfolio yet
Trending Today
不受文件夹无内容影响正常展示


规则
当前文件夹为空时，Portfolio 总资产区域展示添加引导。
点击 Scan a Card 进入 Scan。
点击 Search Cards 进入 Search。
空文件夹下 Most Valuable 不展示卡牌，展示空文案。
Trending Today 是市场数据，不依赖当前文件夹，因此空状态下仍展示。
如果 Trending Today 加载失败，只在 Trending Today 区域展示错误卡片，不影响用户点击 Scan a Card 或 Search Cards。

⸻

3.10 整体无数据 - 加载失败弹窗

字段
页面展示
标题
No content available
主按钮
Refresh

规则
Home页数据全部请求失败时，展示该弹窗。
点击 Refresh 重新请求当前页面数据。
如果只是 Trending Today 或 Most Valuable 单模块失败，不使用整体弹窗，改为模块内失败状态。
Refresh 请求中按钮应展示 loading 。

⸻
3.11 Home部分数据加载异常
规则
1	仅在Home页部分数据加载失败时使用。
2  数据图表、most valuable、trending today分别给缺省状态
3  图表和trending today数据加载异常时可点击刷新，trending today数据缺失时点击view按钮等于再次请求数据
4  缺失数据时用户可下拉刷新数据

图表请求失败页面字段

字段
页面展示
标题
No content available
主按钮
Refresh

Most valuable请求失败页面字段
字段
页面展示
说明
No content available
主按钮
Refresh

trending today请求失败页面字段
字段
页面展示
标题
No content available
主按钮
Refresh

3.12 切换货币弹窗
点击右上角货币入口后，打开货币选择弹窗。
页面字段
币种
名称
USD
US Dollar
EUR
Euro
JPY
Japanese Yen
GBP
British Pound
CAD
Canadian Dollar
AUD
Australian Dollar
NZD
New Zealand Dollar
SGD
Singapore Dollar
失败 Toast
something went wrong. Please try again.
规则
点击右上角货币入口，打开 Select currency 弹窗。
当前货币使用单选态。
点击未选中的货币后，调用汇率接口进行汇率换算。
汇率接口成功后，App 内所有金额相关字段都换算为目标货币。
切换货币影响：全部金额相关
切换货币不改变原始价格数据，只改变展示货币。
切换成功后，右上角货币入口更新为目标货币码。
切换成功后，弹窗自动关闭。
切换失败时，保持原货币不变，并展示 Toast：something went wrong. Please try again
点击当前已选货币，不重复调用接口。
百分比规则
参考竞品中“价格涨跌百分比跟随市场价格变化，而不是展示货币变化”的通用口径：
百分比按原始市场价格序列计算。
货币切换后，百分比不重新计算。
Home 30 天变化百分比如果后续增加，也不受货币切换影响。
Trending Today 当日涨跌幅不受货币切换影响。
Most Valuable 涨跌幅不受货币切换影响。
只有金额数值和货币符号变化。

⸻

四、核心交互规则
4.1 Home 初始化
冷启动时，Home 默认展示星标文件夹数据。
如果用户未设置星标文件夹，则默认 Main文件夹为星标。
当前文件夹数据包括：
总资产金额
30 天变化
图表
Most Valuable
Trending Today 按市场数据展示，不受当前文件夹影响。
页面默认货币为用户最近保存的货币；无保存记录时默认 USD。

⸻

4.2 文件夹切换
点击当前文件夹名称，打开文件夹弹窗。
点击其他文件夹后，Home 和portfolio立即切换到该文件夹数据。
切换操作优先级高于默认文件夹。
在下一次冷启动前，Home 和 Portfolio 都跟随本次切换文件夹展示。
下一次冷启动重新展示星标默认文件夹。
如果切换后的文件夹为空，展示 Home 空状态。
如果切换失败，保留原文件夹并提示失败something went wrong. Please try again。

⸻

4.3 设置默认文件夹
点击文件夹右侧小星星，将该文件夹设为默认文件夹。
默认文件夹唯一。
设置新默认文件夹后，旧默认文件夹取消星标。
默认文件夹用于冷启动后的 Home 和 Portfolio 默认数据。
默认文件夹不可删除。
当前正在查看的文件夹不一定等于默认文件夹。

⸻

4.4 新建文件夹
点击 + Add new 进入 Add new portfolio。
输入名称。
点击 Save 创建文件夹。
新建成功后，停留在文件夹列表弹窗。
新建文件夹不自动成为默认文件夹。
用户可手动点星标设置默认。

⸻

4.5 编辑文件夹
点击编辑图标，进入 Edit portfolio。
编辑弹窗与新建弹窗一致。
保存成功后，文件夹名称同步更新。
如果编辑的是当前文件夹，Home和 portfolio顶部名称同步更新。
如果编辑的是默认文件夹，星标关系不变。

⸻

4.6 排序文件夹
按住文件夹左侧小标识，可上下拖动排序。
排序结果影响文件夹弹窗展示顺序。
排序结果同步到 Portfolio 文件夹列表。
排序后自动保存并不进行重置。
保存失败时回滚并提示失败something went wrong. Please try again。

⸻

4.7 删除文件夹
默认文件夹不可删除。
非默认文件夹点击删除后，展示确认弹窗。
点击 Cancel 取消删除。
点击 Delete 删除文件夹及该文件夹内所有卡牌。
删除当前选中文件夹后，自动切换到默认文件夹。
删除后 Home 和 Portfolio 数据同步刷新。
删除失败时保留原文件夹并提示失败something went wrong. Please try again。

⸻

4.8 货币切换
点击右上角货币入口，打开货币弹窗。
选择目标币种。
调用汇率接口。
成功后刷新 App 内所有金额字段。
失败后保持原币种，并提示：something went wrong. Please try again.
百分比不随货币变化。

⸻

4.9 Most Valuable 查看更多
点击 View ，进入 Collection。
默认进入 Portfolio，并且按单张卡牌价值降序排序，此为该路径的特殊设定。若从此路径进入portfolio然后切到其他页面再回到portfolio的话，portfolio需按照它本身设定的排序方式排序。
默认展示当前文件夹。
点击卡牌进入 Portfolio 卡牌详情页。

⸻

4.10 Trending Today 查看更多
点击 View，进入 Trending 完整列表。
列表保持当天涨幅降序。
点击卡牌进入非 Portfolio 卡牌详情页。
如果用户从详情页添加到 Portfolio，默认加入当前选中的文件夹。

⸻

五、状态与异常
5.1 有数据状态
展示：
当前文件夹名称。
总资产金额。
30 天变化。
图表。
Most Valuable 单卡。
Trending Today 列表。
当前货币。

⸻

5.2 文件夹为空
展示：
Add your first card
Start tracking your collection value, price trends, and top cards.
Scan a Card
Search Cards
No cards in this portfolio yet
Trending Today 继续展示。

⸻

5.3 整页加载失败
展示通用弹窗：
No content available
Refresh

⸻

5.4 Trending Today 加载失败
页面已在 Home 空状态附近展示模块失败卡片。
规则：
只影响 Trending Today 区域。
不影响 Portfolio 空状态。
不影响底部导航。
点击 Refresh 只重试 Trending Today 数据。

⸻

5.5 货币切换失败
展示 Toast：
something went wrong. Please try again
规则：
保持原货币。
保持原金额展示。
不改变百分比。
用户可再次选择币种。

⸻

5.6 所有操作操作失败
文件夹切换、新建、编辑、排序、删除等等都需要失败状态。
Toast：
Something went wrong. Please try again later.

⸻

5.7 表单错误
新建 / 编辑文件夹需要表单错误。
提示：
空名称：Please enter a portfolio name.
重复名称：Portfolio name already exists.
名称过长：Maximum 50 characters.
只输入空格时，按空名称处理。

⸻

六、数据与展示规则
6.1 总资产
按当前选中文件夹计算。
使用当前货币展示。
保留 2 位小数。
使用千分位。
文件夹为空时展示空状态，不展示无意义曲线。
缺失价格的卡牌不计入总资产。

⸻

6.2 图表
图表展示当前选中文件夹的总价值变化。
图表从卡牌收藏进文件夹之日起开始追踪。
图表按用户编辑的 Collection Item 状态取价。
Raw 卡取 Raw 市场价。
Graded 卡取对应评级机构和等级的价格。
数量字段参与总价值计算。
切换文件夹后图表刷新。
切换货币后图表金额换算。
百分比变化不因货币切换而改变。
价格缺失日期显示为曲线断裂。

⸻

6.3 Most Valuable
只统计当前选中文件夹。
只统计 Portfolio 卡牌。
不统计 Wishlist。
按单张卡牌当前价值降序。
首页展示第一名。
单张价值按 Collection Item 状态取价。
多数量不改变该卡排序价值，只影响用户总资产。
如果两张卡单张价值相同，建议按 30 天涨幅较高优先，再按最近添加时间优先。
缺少价格的卡牌不参与排序。

⸻

6.4 Trending Today
展示二级市场当天升值幅度最高的卡牌。
不受当前文件夹影响。
不要求用户收藏。
首页展示 3 条。
按当天涨幅百分比降序。
价格按当前货币换算。
百分比不随货币切换变化。
缺少图片时展示占位图。
如果数据不足 3 条，按实际数量展示。
如果请求失败，展示请求失败状态。

⸻

6.5 货币
默认 USD。
支持页面已展示币种：
USD
EUR
JPY
GBP
CAD
AUD
NZD
SGD
切换货币调用汇率接口。
App 内所有金额字段同步换算。
百分比字段不变。
切换失败保留原币种。


⸻



七、业务规则
7.1 Home 与 Portfolio
Home 展示当前选中文件夹的 Portfolio 资产。
文件夹切换后，Home 和 Portfolio 页面同步。
默认文件夹决定冷启动默认展示。
手动切换优先级高于默认文件夹，直到下一次冷启动。
Portfolio 内卡牌编辑后，Home 总资产、图表、Most Valuable 需要刷新。

⸻

7.2 Home 与 Wishlist
Wishlist 不计入 Home 总资产。
Wishlist 不计入 Home 图表。
Wishlist 不计入 Most Valuable。
Trending Today 可以出现用户 Wishlist 中的卡牌，但 Home 当前不展示 Wishlist 状态。

⸻

7.3 Home 与 Scan
空状态点击 Scan a Card 进入 Scan。
Scan 添加成功后，卡牌默认加入当前选中展示的文件夹。
添加后 Home 刷新当前文件夹数据。
如果当前文件夹为空，添加成功后从空状态切换为有数据状态。

⸻

7.4 Home 与 Search
空状态点击 Search Cards或点击底部导航search 进入 Search。
Search 中添加到 Portfolio 后，默认加入当前选中文件夹。
添加到 Wishlist 不影响 Home 资产。
添加到 Portfolio 后，Home 数据刷新。

⸻

7.5 Home 与 Card Detail
Most Valuable 点击卡牌进入 Portfolio 卡牌详情页。
Trending Today 点击卡牌进入普通卡牌详情页。
用户在 Portfolio 卡牌详情页编辑 Collection Item 后，Home 根据编辑保存的信息更新价格。
用户在卡牌详情页 Remove 后，Home 对应文件夹数据刷新。




# Search - Cards 列表字段重写版
一、页面定位
Search 用于用户查找卡牌和系列，并快速将卡牌加入当前选中的 Portfolio 文件夹或 Wishlist。
Search 页面包含两个 Tab：
	1	Cards：搜索 / 浏览卡牌。
	2	Sets：搜索 / 浏览系列。
Game / IP 筛选项控制下方两个 Tab 的数据范围，但 Cards 和 Sets 两个 Tab 的数据、搜索结果、列表状态互不关联。

⸻

二、页面入口
	1	底部导航点击 Search 进入。
	2	Scan 页面点击右上角 Search 图标进入。
	3	Home 空状态点击 Search Cards 进入。
	4	Scan 失败、识别不准确、无匹配结果时，可进入 Search 手动查找卡牌。
	5	Wishlist / Portfolio 相关页面可通过搜索入口查找新卡牌。

⸻

三、页面结构
3.1 顶部搜索区
页面字段
字段 / 控件
页面展示
说明
搜索框
Search cards, sets, or characters
输入关键词搜索
相机图标
搜索框右侧
进入 Scan
清除按钮
搜索后出现 x
清空搜索词
Game / IP 下拉
当前展示 Pokémon
控制下方 Cards / Sets 的数据范围
Tab
Cards、Sets
切换卡牌和系列
规则
	1	进入 Search 默认展示 Cards Tab。
	2	默认 Game / IP 为 Pokémon。
	3	用户可输入卡牌名、系列名、角色名等关键词。
	4	搜索框右侧相机图标点击后进入 Scan 页面。
	5	输入关键词后出现清除按钮。
	6	点击清除按钮后清空关键词，并恢复当前 Game / IP 下当前 Tab 的默认列表。
	7	Game / IP 下拉用于切换搜索范围。
	8	切换 Game / IP 后，当前 Tab 列表刷新为对应 Game / IP 数据。
	9	Cards 和 Sets 两个 Tab 互不关联：
	◦	Cards 的搜索结果不影响 Sets；
	◦	Sets 的搜索结果不影响 Cards；
	◦	两个 Tab 可各自保留自己的搜索状态，意思是搜索完以后切到其他页面再切回来依然是搜索的状态不进行重置
	10	切换 Game / IP 时，清空当前搜索词，避免用户误以为某个 IP 下没有数据

## 四、Cards Tab 列表统一结构
Cards Tab 以双列卡片展示可收藏对象，包括：
1. TCG 单卡；
2. 体育卡；
3. 评级卡；
4. 套盒 / 卡包 / 整箱；
5. 其他特殊收藏品。
所有类型在列表中统一展示以下基础结构：
```text
图片
名称
当前价格
30D Change 百分比
归属信息
版本 / 状态信息
Qty
Collect / Collected
Wishlist 爱心

全局展示规则

1. Search 列表只展示 涨跌百分比，不展示涨跌金额。
2. 涨跌百分比固定使用 30D Change。
3. 涨跌百分比不随货币切换变化。
4. 当前价格跟随用户当前货币展示。
5. 当前价格缺失时展示 --。
6. 涨跌百分比缺失时展示 -/-。
7. 涨跌百分比为正数时展示 +。
8. 涨跌百分比为负数时展示 -。
9. Qty 表示当前账号在当前选中文件夹中的持有数量。
10. Wishlist 不影响 Qty。

⸻

五、TCG 单卡字段

适用于 Pokémon、Yu-Gi-Oh!、Magic、One Piece 等普通单卡。

5.1 展示字段

字段	展示规则	示例
图片	卡牌封面，缺图展示占位图	image
卡牌名称	主标题，超长省略	Squirtle
当前价格	当前市场参考价	$32.13
30D Change 百分比	只展示百分比，不展示金额	(+4.76%)
系列名	卡牌所属系列	Mega Evolution Promos
稀有度 / 编号	卡牌版本信息	Promo · 039
Finish / Variant	工艺 / 版本	Holofoil
Qty	当前选中文件夹持有数量	Qty: 0 / Qty: 1
Collect / Collected	加入 / 取消加入当前 Portfolio	Collect
Heart	加入 / 移除 Wishlist	空心 / 实心

5.2 推荐展示结构

Squirtle
$32.13
(+4.76%)
Mega Evolution Promos
Promo · 039
Holofoil
Qty: 0        Collect    ♡

已加入当前 Portfolio：

Squirtle
$32.13
(+4.76%)
Mega Evolution Promos
Promo · 039
Holofoil
Qty: 1        Collected    ♡

5.3 字段规则

1. 卡牌名称为主标题。
2. 系列名用于说明卡牌归属。
3. 稀有度 / 编号用于区分同名卡不同版本。
4. Finish / Variant 用于展示 Holofoil、Reverse Holo、Sealed 等状态。
5. 当前价格展示市场参考价，不代表用户 Portfolio 资产价值。
6. 点击 Collect 后，Portfolio 中该卡的价值按 Collection Item 规则计算。

⸻

六、体育卡字段

体育卡 Search 列表只保留必要识别字段，不展示过多扩展信息。

6.1 展示字段

字段	展示规则	示例
图片	体育卡图 / 评级封装图，缺图展示占位图	Michael Jordan 卡图
球员名 + 卡号	主标题	Michael Jordan #57
当前价格	当前市场参考价	$18,500.00
30D Change 百分比	只展示百分比，不展示金额	(+7.25%)
年份 + 系列 / 品牌	核心归属信息	1986 Fleer
版本 / 子系列	卡牌版本信息	Base
评级状态	Grader + Grade；未评级展示 Raw	BGS 9.5 / SGC 9 / Raw
Qty	当前选中文件夹持有数量	Qty: 0 / Qty: 1
Collect / Collected	加入 / 取消加入当前 Portfolio	Collect
Heart	加入 / 移除 Wishlist	空心 / 实心

6.2 推荐展示结构

评级体育卡：

Michael Jordan #57
$18,500.00
(+7.25%)
1986 Fleer
Base
BGS 9.5
Qty: 0        Collect    ♡

未评级体育卡：

Shohei Ohtani #17
$240.00
(+8.12%)
2024 Topps Chrome
Refractor
Raw
Qty: 0        Collect    ♡

6.3 体育卡字段规则

1. 体育卡主标题展示 球员名 + 卡号。
2. 年份 + 系列 / 品牌为体育卡必要识别字段，必须展示。
3. 版本 / 子系列用于区分 Base、Refractor、Court Kings 5x7 等不同版本。
4. 评级卡展示 Grader + Grade，例如 BGS 9.5、SGC 9。
5. 未评级卡展示 Raw。
6. Search 列表不展示 Sport、Team、RC、Auto、Patch、Serial Number、Certification Number 等扩展字段。
7. 扩展字段可放在详情页或 Collection Item 中展示 / 编辑。
8. 体育卡价格缺失时展示 --。
9. 体育卡涨跌百分比缺失时展示 -/-。
10. 体育卡加入 Portfolio 后，Collection Item 需要保留 Quantity、Portfolio、Grader、Grade / Condition、Purchase Price、Notes 等收藏类字段。

⸻

七、Sealed Product 套盒 / 卡包 / 整箱字段

适用于 Booster Box、Booster Pack、Elite Trainer Box、Case、Starter Deck、Structure Deck、Collection Box 等未拆封产品。

7.1 展示字段

字段	展示规则	示例
图片	产品图，缺图展示占位图	盒图 / 包图
产品名称	主标题，超长省略	Perfect Order Booster Box
当前价格	当前市场参考价	$222.61
30D Change 百分比	只展示百分比，不展示金额	(+1.36%)
系列名	产品所属系列	Perfect Order
状态	未拆封状态	Sealed
Qty	当前选中文件夹持有数量	Qty: 0 / Qty: 1
Collect / Collected	加入 / 取消加入 Portfolio	Collect
Heart	加入 / 移除 Wishlist	空心 / 实心

7.2 推荐展示结构

Perfect Order Booster Box
$222.61
(+1.36%)
Perfect Order
Sealed
Qty: 0        Collect    ♡

Elite Trainer Box：

Perfect Order Pokemon Center Elite Trainer Box
$133.02
(-4.37%)
Perfect Order
Sealed
Qty: 0        Collect    ♡

7.3 Sealed Product 字段规则

1. 主标题展示产品名称。
2. 第二层展示系列名。
3. 状态展示 Sealed。
4. Search 列表不强制展示 Product Type、Configuration、Language。
5. 如果产品名称中已经包含 Booster Box、Elite Trainer Box、Collection 等信息，不再额外重复展示 Product Type。
6. Sealed Product 不展示 Card Number。
7. Sealed Product 不展示 Grader / Grade。
8. Sealed Product 不展示 Condition，状态以 Sealed 为主。
9. 价格缺失时展示 --。
10. 涨跌百分比缺失时展示 -/-。
11. Sealed Product 可以加入 Portfolio，也可以加入 Wishlist。
12. 加入 Portfolio 后，Collection Item 中保留 Quantity、Portfolio、Purchase Price、Notes 等收藏类字段。

⸻

八、其他特殊收藏品字段

其他特殊收藏品包括 Non-Sport Cards、特殊 Promo、Serialized / Auto / Patch / Memorabilia 特殊卡等。

Search 列表只保留通用必要字段，不展开过多特殊属性。

8.1 展示字段

字段	展示规则	示例
图片	卡图 / 产品图 / 评级壳图，缺图展示占位图	image
名称	主标题，超长省略	Darth Vader
当前价格	当前市场参考价	$86.00
30D Change 百分比	只展示百分比，不展示金额	(+7.77%)
系列 / IP / 年份品牌	归属信息	Star Wars · Chrome Galaxy
版本 / 状态	版本或状态信息	Refractor · PSA 10
Qty	当前选中文件夹持有数量	Qty: 0
Collect / Collected	加入 / 取消加入 Portfolio	Collect
Heart	加入 / 移除 Wishlist	空心 / 实心

8.2 推荐展示结构

Darth Vader
$86.00
(+7.77%)
Star Wars · Chrome Galaxy
Refractor · PSA 10
Qty: 0        Collect    ♡

特殊体育卡 / 限编卡示例：

CJ Stroud
$2,850.00
(+7.95%)
2023 Panini National Treasures
Auto Patch · PSA 9
Qty: 0        Collect    ♡

8.3 字段规则

1. 名称作为主标题。
2. 归属信息用于展示 IP、系列、年份品牌等。
3. 版本 / 状态信息用于展示 Variant、Raw、PSA 10、Auto Patch 等。
4. Search 列表不展示 Serial Number、Certification Number、详细签名认证、详细限编编号等复杂字段。
5. 复杂字段放在详情页或 Collection Item 中展示 / 编辑。
6. 价格缺失时展示 --。
7. 涨跌百分比缺失时展示 -/-。

⸻

九、Search Cards 列表字段最终汇总

类型	主标题	价格	涨跌	归属信息	版本 / 状态	收藏字段
TCG 单卡	卡牌名称	当前价格	30D 百分比	系列名	稀有度 / 编号 + Finish	Qty + Collect + Heart
体育卡	球员名 + 卡号	当前价格	30D 百分比	年份 + 系列 / 品牌	版本 / 子系列 + 评级状态	Qty + Collect + Heart
Sealed Product	产品名称	当前价格	30D 百分比	系列名	Sealed	Qty + Collect + Heart
其他特殊收藏品	名称	当前价格	30D 百分比	IP / 系列 / 年份品牌	版本 / 状态	Qty + Collect + Heart

⸻

十、涨跌百分比展示规则

Search 列表中所有类型只展示涨跌百分比，不展示涨跌金额。

展示格式

上涨：

(+4.76%)

下跌：

(-4.17%)

无数据：

-/- 

计算口径

30D Change % = (Current Price - 30D Previous Price) / 30D Previous Price × 100%

规则

1. Search 列表固定展示 30D Change 百分比。
2. Search 列表不展示 7D、1D、1M 等其他周期。
3. Search 列表不展示涨跌金额。
4. 百分比保留 2 位小数。
5. 当前价格缺失时，涨跌百分比展示 -/-。
6. 30D Previous Price 缺失时，涨跌百分比展示 -/-。
7. 30D Previous Price 为 0 时，涨跌百分比展示 -/-。
8. 百分比不随货币切换变化。

⸻

十一、字段展示优先级

11.1 TCG 单卡

1. 图片；
2. 卡牌名称；
3. 当前价格；
4. 30D Change 百分比；
5. 系列名；
6. 稀有度 / 编号；
7. Finish；
8. Qty；
9. Collect / Heart。

11.2 体育卡

1. 图片；
2. 球员名 + 卡号；
3. 当前价格；
4. 30D Change 百分比；
5. 年份 + 系列 / 品牌；
6. 版本 / 子系列；
7. 评级状态；
8. Qty；
9. Collect / Heart。

11.3 Sealed Product

1. 图片；
2. 产品名称；
3. 当前价格；
4. 30D Change 百分比；
5. 系列名；
6. Sealed；
7. Qty；
8. Collect / Heart。

11.4 其他特殊收藏品

1. 图片；
2. 名称；
3. 当前价格；
4. 30D Change 百分比；
5. IP / 系列 / 年份品牌；
6. 版本 / 状态；
7. Qty；
8. Collect / Heart。

⸻

十二、Qty 字段规则

Qty 表示当前账号在当前选中文件夹中的持有数量。

1. 未加入当前文件夹时展示 Qty: 0。
2. 已加入当前文件夹时展示对应数量，例如 Qty: 1。
3. 点击 Collect 快捷加入后，Qty 从 0 更新为 1。
4. 点击 Collected 取消加入后，Qty 更新为 0。
5. 如果同一对象在当前文件夹有多个 Collection Item，Qty 展示总数量。
6. Wishlist 不影响 Qty。
7. Qty 只统计当前选中文件夹，不统计其他文件夹。
8. TCG 单卡、体育卡、Sealed Product、特殊收藏品均展示 Qty。

⸻

十三、Collect / Collected 规则

1. Collect 表示该对象未加入当前选中文件夹。
2. 点击 Collect 后，将该对象一键加入当前选中的 Portfolio 文件夹。
3. 加入成功后按钮变为 Collected。
4. Collected 表示该对象已加入当前选中文件夹。
5. 再次点击 Collected，取消加入当前选中文件夹。
6. 取消成功后按钮恢复为 Collect。
7. 如果当前对象在其他文件夹中存在，但不在当前选中文件夹中，仍展示 Collect。
8. 如果同一对象在当前文件夹中存在多个 Collection Item，点击 Collected 不直接删除全部，进入详情页由用户手动管理，避免误删。

⸻

十四、Wishlist 爱心规则

1. 空心爱心表示该对象未加入 Wishlist。
2. 点击空心爱心后，将该对象加入 Wishlist。
3. 加入成功后爱心变为实心。
4. 实心爱心表示该对象已加入 Wishlist。
5. 再次点击实心爱心后，将该对象从 Wishlist 移除。
6. 移除成功后爱心恢复为空心。
7. Wishlist 不计入 Home 总资产。
8. Wishlist 不计入 Portfolio。
9. Wishlist 不影响 Most Valuable。
10. Wishlist 不影响 Qty。
11. 同一对象不可以同时存在于 Portfolio 和 Wishlist。
12. 点击 Collect 自动移除 Wishlist。


⸻

十五、快捷加入默认 Collection Item

用户从 Search 点击 Collect 后，系统生成默认 Collection Item。

15.1 TCG 单卡默认值

字段	默认值
Quantity	1
Portfolio	当前选中文件夹
Grader	Raw / Ungraded
Condition	Near Mint
Language	当前卡牌数据语言
Finish	当前卡牌 Finish
Purchase Price	空
Notes	空

15.2 体育卡默认值

字段	默认值
Quantity	1
Portfolio	当前选中文件夹
Grader	如果列表对象为评级卡，取列表中的 Grader；否则为 Raw
Grade	如果列表对象为评级卡，取列表中的 Grade；否则为空
Condition	Raw 体育卡默认 Near Mint
Variant	使用当前列表对象的版本 / 子系列数据
Purchase Price	空
Notes	空

15.3 Sealed Product 默认值

字段	默认值
Quantity	1
Portfolio	当前选中文件夹
Status	Sealed
Product Type	使用当前列表对象数据
Purchase Price	空
Notes	空

15.4 其他特殊收藏品默认值

字段	默认值
Quantity	1
Portfolio	当前选中文件夹
状态字段	按对象类型带入 Raw / Graded / Sealed
Variant	使用当前列表对象数据
Purchase Price	空
Notes	空

⸻

十六、Cards 列表展示规则

1. Cards 列表只展示当前 Game / IP 范围内的数据。
2. 默认 Game / IP 为 Pokémon。
3. Cards 默认排列顺序为入库时间倒序。
4. 入库时间新的对象排在上方，旧的排在下方。
5. 搜索后，搜索结果仍按入库时间倒序展示。
6. 切换 Game / IP 后，Cards 列表刷新为新 Game / IP 下的数据。
7. 名称超长时省略。
8. 系列名 / 产品名超长时省略。
9. 当前价格按用户当前货币展示。
10. 价格保留 2 位小数。
11. 价格缺失时展示 --。
12. 涨跌百分比缺失时展示 -/-。
13. 点击卡片非按钮区域，进入未加入 Portfolio / 已加入 Portfolio 对应的详情页。
14. Search 页价格为市场参考价，不代表用户 Portfolio 资产价值。
15. 用户点击 Collect 加入 Portfolio 后，Portfolio 中该对象的价值按 Collection Item 规则计算。


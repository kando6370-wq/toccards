# Scan 模块 PRD

> **定位**：Scan 是底部导航第三个 Tab，v1.0 为预留占位；扫描识别功能在后续版本实现。
>
> **日期**：2026-06-30
>
> **上游来源**：
> - 原始底稿 [`docs/tcg-card/source-tcg-card-docs/scan.md`](../../source-tcg-card-docs/scan.md)
> - 跨切面规则 [`./global-rules.md`](./global-rules.md)（失败 / Toast / 网络异常——本文档只引用，不重复定义）
> - 术语表 [`../glossary.md`](../glossary.md)
> - 数据模型 [`../../03-data-api/data-model.md`](../../03-data-api/data-model.md)
> - API 规范 [`../../03-data-api/api-spec.md`](../../03-data-api/api-spec.md)

---

> ## ⚠️ v1.0 实现范围声明
>
> **v1.0 不做真扫描识别。**
>
> - 底部导航保留 Scan Tab 入口。
> - 点击 Scan Tab 进入占位页，展示"扫描功能即将上线"引导，并提供跳转到 Search 的按钮。
> - **占位文案**：⚠️ TBD（与 `overview.md` 保持一致，待产品确认后统一填入）。
> - 本文档后半部分（§二 以后）完整保留原始扫描流程设计，作为**后续版本设计留档**，不在 v1.0 实现。

---

## 目录

1. [v1.0 占位页（当前实现范围）](#一v10-占位页当前实现范围)
2. [——以下为 Future 版本设计留档，v1.0 不实现——](#以下为-future-版本设计留档v10-不实现)
3. [页面定位（Future）](#二页面定位future)
4. [扫描入口（Future）](#三扫描入口future)
5. [扫描拍摄页（Future）](#四扫描拍摄页future)
6. [批量扫描处理（Future）](#五批量扫描处理future)
7. [待处理扫描数量上限（Future）](#六待处理扫描数量上限future)
8. [单张扫描流程（Future）](#七单张扫描流程future)
9. [多张扫描流程（Future）](#八多张扫描流程future)
10. [扫描结果确认区（Future）](#九扫描结果确认区future)
11. [数据库无匹配结果处理（Future）](#十数据库无匹配结果处理future)
12. [Collection Item 页面（Future）](#十一collection-item-页面future)
13. [Portfolio 选择弹窗（Future）](#十二portfolio-选择弹窗future)
14. [底部固定操作区（Future）](#十三底部固定操作区future)
15. [删除全部扫描确认弹窗（Future）](#十四删除全部扫描确认弹窗future)
16. [添加成功状态（Future）](#十五添加成功状态future)
17. [扫描失败状态（Future）](#十六扫描失败状态future)
18. [Done 按钮规则（Future）](#十七done-按钮规则future)
19. [退出未保存扫描结果确认（Future）](#十八退出未保存扫描结果确认future)
20. [权限异常（Future）](#十九权限异常future)
21. [闪光灯异常（Future）](#二十闪光灯异常future)
22. [识别超时（Future）](#二十一识别超时future)
23. [网络异常（Future）](#二十二网络异常future)
24. [识别结果不准确（Future）](#二十三识别结果不准确future)
25. [价格缺失（Future）](#二十四价格缺失future)
26. [添加失败（Future）](#二十五添加失败future)
27. [批量添加部分成功（Future）](#二十六批量添加部分成功future)
28. [字段校验（Future）](#二十七字段校验future)
29. [状态流转总结（Future）](#二十八状态流转总结future)

---

## 一、v1.0 占位页（当前实现范围）

### 1.1 功能范围

v1.0 Scan 模块只交付以下内容：

| 内容 | 说明 |
|---|---|
| 底部导航 Scan Tab | 保留 Tab 入口，与 Home / Search / Collection / Profile 并列 |
| 占位页 | 点击 Tab 后展示扫描功能待上线的引导页 |
| 引导到 Search | 占位页提供跳转到 Search 的按钮，供用户手动查找卡牌 |

### 1.2 占位页字段

| 字段 / 控件 | 说明 |
|---|---|
| 标题 / 说明文案 | ⚠️ TBD（待产品确认，与 `overview.md` 保持一致） |
| 引导按钮 | 跳转到 Search 页面 |

### 1.3 规则

1. 占位页不打开相机，不请求相机权限。
2. 点击引导按钮跳转到 Search 页面，走 Search 正常流程。
3. 占位页设计风格与全局 UI 一致；加载失败等异常走 `global-rules.md §二`。

---

---

## 以下为 Future 版本设计留档，v1.0 不实现

> **说明**：下文完整保留扫描识别功能的原始设计，供后续版本参考。所有功能均**不在 v1.0 交付**，仅作留档。

---

## 二、页面定位（Future）

Scan 模块用于识别用户已拥有的实体卡牌，并将扫描结果添加至 Portfolio。

- 扫描结果不会自动保存；用户需确认卡牌信息、编辑收藏属性，并点击添加按钮后，卡牌才会加入目标 Portfolio。
- 扫描流程不添加至 Wishlist。

---

## 三、扫描入口（Future）

### 页面入口

| 入口 | 说明 |
|---|---|
| 底部导航 Scan Tab | 默认进入扫描拍摄页 |
| Search 页面相机图标 | 同样进入扫描拍摄页 |
| Scan 右上角 Search 图标 | 跳转到 Search 手动查找卡牌 |

### 规则

1. 从底部导航或 Search 相机入口进入 Scan 时，默认进入扫描拍摄页。
2. Search 入口用于扫描失败、识别不准确、**第三方数据源无匹配**（见 `global-rules.md §十五 冲突3`）、用户想手动查找卡牌时兜底。
3. Scan 主流程只支持添加到 Portfolio，不添加到 Wishlist。

---

## 四、扫描拍摄页（Future）

### 页面字段

| 字段 / 控件 | 页面展示 | 说明 |
|---|---|---|
| 关闭按钮 | 左上角 `×` | 退出扫描流程 |
| 闪光灯按钮 | 顶部图标 | 控制闪光灯开关 |
| Search 图标 | 右上角搜索图标 | 进入 Search 手动查找卡牌 |
| 扫描框 | 页面中央取景框 | 用户将卡牌放入框内拍摄 |
| 拍摄按钮 | 底部圆形按钮 | 拍摄当前扫描框内卡牌 |
| Done / 勾选按钮 | 底部右侧 | 结束当前扫描，进入确认与编辑流程 |
| 底部扫描结果列表 | 底部小卡片 | 展示本次扫描项，包括 Scanning、成功、Failed |

### 基础规则

1. 进入扫描页后打开相机预览；闪光灯默认关闭。
2. 点击闪光灯按钮后打开闪光灯，再次点击关闭。
3. 用户退出扫描页、App 进入后台、锁屏或被系统中断时，闪光灯自动关闭。
4. 每次拍摄只处理扫描框中的 1 张卡牌；不支持同一画面多张卡牌同时拆分识别。
5. 用户要扫描多张卡牌时，需要逐张放入扫描框并逐张拍摄，或从相册多张导入。
6. 用户点击拍摄后，该扫描项立即进入底部扫描结果列表，初始展示为 `Scanning...`。
7. `Scanning...` 不阻塞用户继续拍摄下一张；多个扫描项可同时处于 `Scanning...` 状态。
8. 每个扫描项识别完成后，独立更新为成功或失败；识别结果不会自动保存到 Portfolio。

---

## 五、批量扫描处理（Future）

### 处理口径

```
逐张拍摄 → 异步识别 → 逐条加入本次扫描结果列表
不做同一画面多卡同时识别。
```

### 规则

1. 用户每点击一次拍摄按钮，生成 1 个扫描项，只对应 1 张卡牌。
2. 拍摄完成后，该扫描项立即进入底部扫描结果列表，初始状态为 `Scanning...`。
3. 用户不需要等待上一张识别完成，可以继续拍摄下一张；每个扫描项独立发起识别。
4. 识别结果只更新对应扫描项；某扫描项识别较慢不影响其他扫描项。
5. 如果用户删除某个扫描项，该扫描项后续返回结果不再展示。
6. 底部扫描结果列表按拍摄时间顺序展示，先拍摄的排在前面。

### 同画面多卡处理

如果画面中出现多张卡牌，系统优先识别扫描框中心区域内最完整的一张。如果无法判断主卡牌，识别失败，Toast：

```
Place one card inside the frame and try again.
```

---

## 六、待处理扫描数量上限（Future）

### 核心规则

当前扫描结果列表最多同时保留 10 张待处理扫描结果。用户处理完当前扫描结果后，可以继续扫描下一批，不需要退出扫描页。

### 待处理结果定义

1. 正在识别中的扫描项
2. 已识别成功但未加入 Portfolio 的扫描项
3. 识别失败但未删除的扫描项
4. 已进入 Review / Collection Item 页面但尚未完成添加的扫描项

### 上限规则

1. 每拍摄 1 张卡牌，待处理数量 +1。
2. 当待处理数量达到 10 张时，拍摄按钮不可用。
3. 以下操作会释放待处理名额：加入 Portfolio / 删除扫描结果 / 删除失败项 / 批量添加成功 / 批量删除 / 退出扫描并确认丢弃结果。
4. 待处理数量低于 10 后，用户可继续拍摄新的卡牌。
5. 如果批量添加中部分成功、部分失败，成功项释放名额，失败项继续保留在待处理列表中。

### 达到上限提示

完整文案：
```
Scan limit reached. Finish or delete current scans to continue.
```

短 Toast：
```
Finish or delete current scans to continue.
```

---

## 七、单张扫描流程（Future）

```
用户对准卡牌进行扫描
↓
识别成功后，底部展示单张扫描结果卡片
↓
用户点击 Done
↓
进入扫描结果确认 + Collection Item 编辑页面
↓
用户确认匹配结果，编辑收藏属性
↓
用户点击 Add this card
↓
卡牌加入所选 Portfolio
↓
展示成功提示并返回扫描页
```

### 规则

1. 本次扫描列表中只有 1 张成功识别卡牌时，点击 Done 进入合并后的 Collection Item 页面。
2. 进入该页面前，该卡牌尚未加入 Portfolio。
3. 用户点击 Add this card 后，卡牌才加入目标 Portfolio。
4. 添加成功后，该扫描项从待处理列表中移除，展示成功提示，页面返回扫描页。
5. 如果添加失败，停留在当前页面，保留用户已填写内容。

---

## 八、多张扫描流程（Future）

```
用户连续扫描多张卡牌
↓
每张识别成功后加入底部扫描结果列表
↓
用户点击 Done
↓
进入 Review Your Matches 页面
↓
顶部展示本次扫描的多张卡牌缩略项
↓
用户可快捷切换不同卡牌
↓
页面中展示当前选中卡牌的识别结果与 Collection Item 信息
↓
用户可单张编辑、单张添加、单张删除
↓
用户也可批量添加所有可添加卡牌
↓
添加成功后返回扫描页
```

### 页面结构

| 区域 | 说明 |
|---|---|
| 顶部卡牌切换区 | 展示本次扫描的所有扫描项缩略卡，用户可点击切换 |
| Your Picture | 当前选中扫描项的用户原始图片 |
| Our Match | 当前选中扫描项的系统匹配结果 |
| Top matched results | 当前选中扫描项的候选匹配结果 |
| Collection Item | 当前选中扫描项的收藏信息编辑区 |
| Adding to Main | 当前选中卡牌的添加目标 Portfolio |
| 底部固定操作区 | 单张添加 / 单张删除 / 批量添加 / 批量删除 |

### 规则

1. 本次扫描列表中存在 2 张及以上成功识别卡牌时，点击 Done 进入 Review Your Matches。
2. Review Your Matches 只展示可处理的扫描项；Failed 项不进入 Collection Item 编辑流程。
3. 用户可在顶部切换不同扫描卡牌；切换后下方所有信息同步切换。
4. 每张卡牌可拥有独立的 Collection Item 信息，可选择不同的 Portfolio。
5. 点击 Add this card 时，只添加当前选中的卡牌；点击 Add all cards 时，添加所有满足添加条件的卡牌。
6. 已添加成功的卡牌从待处理列表中移除；添加失败的卡牌保留，用户可重试或删除。
7. 如果部分成功、部分失败，成功项移除，失败项保留，页面继续停留在 Review Your Matches。

---

## 九、扫描结果确认区（Future）

### Your Picture

展示用户原始拍摄图片。

**规则**：
1. 用户原始拍摄图片不随候选结果切换而改变。
2. 用于帮助用户对比识别结果是否正确。
3. 如果图片加载失败，展示图片占位（见 `global-rules.md §六`）。

### Our Match

展示当前系统匹配结果。

| 字段 | 说明 |
|---|---|
| 卡牌图片 | 当前匹配结果图片 |
| 卡牌名称 | 当前匹配卡牌名 |
| Set / 系列 | 当前匹配卡牌所属系列 |
| 卡牌编号 | 当前匹配卡牌编号 |
| 价格 | 当前匹配结果市场价格 |

**规则**：
1. Our Match 默认展示系统识别的最高匹配结果。
2. 用户选择候选结果后，Our Match 替换为用户选择的结果，并同步更新 Collection Item 信息。

### Top matched results

展示其他可能匹配的卡牌候选。

**规则**：
1. 用户点击候选结果后，替换当前 Our Match，同步更新当前扫描项对应卡牌信息。
2. 如果候选结果为空，展示文案：`No matched results found.`

---

## 十、数据库无匹配结果处理（Future）

> 按 `global-rules.md §十五 冲突3`，"数据库无匹配"口径统一替换为**以第三方聚合数据为准**——即第三方数据源无匹配。

### 状态定义

| 状态 | 含义 | 是否可加入 Portfolio |
|---|---|---|
| Failed | 识别请求失败 / 图片不可用 / 超时 / 网络失败 | 否 |
| No match found | 第三方数据源没有找到对应卡牌 | 否 |
| Matched | 识别成功，并找到数据源匹配结果 | 可加入 |

### 无匹配展示

当扫描成功但第三方数据源没有找到对应卡牌时：

```
No match found. search manually.
```

### 操作规则

1. 用户可重试扫描。
2. 用户可进入 Search 手动查找卡牌。
3. 如果从 Search 找到正确卡牌，则走 Search 添加流程，不再返回 Scan 流程。
4. 当前版本不支持 Custom Card，则无匹配卡牌不能直接从 Scan 加入 Portfolio。

---

## 十一、Collection Item 页面（Future）

### 进入场景

1. 单张扫描成功后，用户点击 Done 进入 Collection Item 页面。
2. 多张扫描进入 Review Your Matches 后，用户点击或切换单张卡牌，在同一页面编辑该卡 Collection Item。

### 页面字段

| 字段 | 页面展示 | 说明 |
|---|---|---|
| 标题 | Collection Item | 单张卡牌编辑区 |
| Adding to Main | 添加目标文件夹 | 当前添加目标 Portfolio |
| 卡牌图片 | Our Match 图片 | 展示当前匹配结果 |
| 卡牌名称 | 当前识别卡牌名 | 展示匹配结果 |
| Quantity | 数量 | 用户持有数量，默认 1 |
| Portfolio | 目标文件夹 | 默认当前 Home / Portfolio 选中的文件夹，可切换 |
| Grader | 评级机构 / Raw 状态 | 判断价格口径 |
| Condition / Grade | 品相或评级等级 | Raw 卡使用 Condition；Graded 卡使用 Grade |
| Language | 语言 | 卡牌语言 |
| Finish | 工艺 / 版本 | 例如 Holofoil |
| Purchase Price | 购买价格 | 用户记录成本，不参与市场价值计算 |
| Notes | 备注 | 用户备注 |
| Total | 总价值 | 当前 Collection Item 价值，按数量 × 单价计算 |
| Add this card / Add all cards | 添加按钮 | 将卡牌加入目标 Portfolio |

### 字段说明

1. 页面不展示 Purchase Date、Purchase Source。
2. Quantity 默认 1，必须为正整数；Portfolio 默认取当前目标文件夹，用户可切换。
3. Grader 用于判断卡牌是否评级：Raw / Ungraded 取 Raw 市场价；Graded 按评级机构和等级取对应 Graded 市场价。
4. Language、Finish 默认取识别结果。
5. Purchase Price 只作为用户购买成本记录，不参与市场价值计算。
6. Total 根据当前市场价和数量计算；如果当前市场价缺失，Total 展示 `--`，仍允许用户保存到 Portfolio。

---

## 十二、Portfolio 选择弹窗（Future）

### 触发入口

在 Review Your Matches 或 Collection Item 中点击 Adding to: Main，或点击 Portfolio 字段，打开 Portfolio 选择弹窗。

### 规则

1. 当前目标文件夹右侧展示选中状态；用户点击其他文件夹后，切换当前卡牌的添加目标。
2. 切换后，页面中的 Adding to: Main 和按钮文案同步更新。
3. 如果是单张扫描，只影响当前卡牌；多张扫描中，用户可以为不同卡牌选择不同 Portfolio。
4. 添加成功后，卡牌加入所选 Portfolio 文件夹。

---

## 十三、底部固定操作区（Future）

### 单张扫描

| 按钮 | 说明 |
|---|---|
| Add this card | 添加当前卡牌到目标 Portfolio |
| 删除图标 | 删除当前扫描结果 |

### 多张扫描

| 按钮 | 说明 |
|---|---|
| Add this card | 添加当前选中的单张卡牌 |
| Add all cards | 批量添加所有可添加卡牌 |
| 删除当前卡牌 | 删除当前选中扫描项 |
| Delete all cards | 删除全部未保存扫描卡牌 |

### 规则

1. 单张添加只处理当前选中卡牌；批量添加处理所有满足添加条件的卡牌。
2. 单张删除只删除当前选中扫描项；批量删除需展示二次确认弹窗（见 §十四）。
3. 删除成功后释放待处理名额；删除后不保存到 Portfolio，不可恢复。

---

## 十四、删除全部扫描确认弹窗（Future）

| 元素 | 文案 |
|---|---|
| 标题 | `Delete all cards?` |
| 说明 | `This action will permanently delete all these cards` |
| 主按钮 | `Cancel` |
| 次按钮 | `Delete` |

### 规则

1. 用户点击批量删除时展示该弹窗。
2. 点击 Cancel 关闭弹窗，不删除扫描结果。
3. 点击 Delete 删除全部未保存扫描卡牌，释放对应待处理名额，返回扫描页。
4. 如果删除失败，保留扫描结果并展示通用失败 Toast（见 `global-rules.md §四`）。

---

## 十五、添加成功状态（Future）

| 场景 | 展示 |
|---|---|
| 单张添加成功 | `Success` / `1 card added to your portfolio` |
| 多张添加成功 | `Success` / `{N} cards added to your portfolio`（按实际成功数量） |

### 规则

1. 添加成功后，对应扫描项从待处理扫描列表中移除；失败的扫描项保留，用户可重试或删除。
2. 添加成功后返回扫描页；如果待处理列表已全部处理完成，底部列表清空。

---

## 十六、扫描失败状态（Future）

### 规则

1. 识别失败的扫描项展示为 Failed 状态；失败项不进入 Collection Item 以及后续添加流程。
2. 用户可点击失败项重试；可点击 `×` 删除失败项，删除后释放 1 个待处理名额。
3. 如果当前扫描列表中没有任何成功识别的卡牌，Done 不可点击。
4. 如果当前扫描列表中存在成功识别的卡牌，Done 可点击；Failed 项仍留在扫描列表中，除非用户删除。

### 失败文案

| 场景 | 文案 |
|---|---|
| 扫描项失败 | `Error / Tap to retry` |
| 详情页无匹配结果 | `No match found. Try again or search manually.` |

---

## 十七、Done 按钮规则（Future）

| 当前扫描列表状态 | Done 状态 | 点击结果 |
|---|---|---|
| 无扫描项 | 不可点击 | 不进入后续流程 |
| 仅有 Failed 项 | 不可点击 | 用户需重试、删除或去 Search |
| 1 张成功项，无 Scanning | 可点击 | 进入 Collection Item |
| 2 张及以上成功项，无 Scanning | 可点击 | 进入 Review Your Matches |
| 有成功项 + Failed 项，无 Scanning | 可点击 | 仅成功项进入后续流程，Failed 项不进入 Review |
| 存在 Scanning 项 | 不可点击 | 等待识别完成 |
| 待处理数量达到 10 | 可处理当前结果 | 用户需添加或删除当前扫描项后继续拍摄 |

---

## 十八、退出未保存扫描结果确认（Future）

### 触发场景

当本次扫描中存在未加入 Portfolio 的扫描结果时，用户点击关闭或离开扫描流程，展示确认弹窗。

未保存扫描结果包括：正在 Scanning 的扫描项 / 识别成功但未添加的扫描项 / Failed 但未删除的扫描项 / 已进入 Review / Collection Item 但未完成添加的扫描项。

### 弹窗文案

| 元素 | 文案 |
|---|---|
| 标题 | `Confirm` |
| 说明 | `Your scan results haven't been saved. If you exit now, they will be lost.` |
| 主按钮 | `Stay Here` |
| 次按钮 | `Exit` |

### 规则

1. 点击 Stay Here 后，关闭弹窗，返回当前扫描流程。
2. 点击 Exit 后，退出扫描流程；未保存扫描结果全部丢弃。
3. 如果从 Home / Scan 进入，则返回 Scan 前页面或 Home；如果从 Search 进入，则返回 Search。
4. 如果本次扫描没有任何扫描结果，或扫描结果已经全部加入 Portfolio 或删除，点击关闭可直接退出。

---

## 十九、权限异常（Future）

### 相机权限拒绝

用户首次进入扫描页时请求相机权限。如果用户拒绝，Scan 页面不展示相机预览，改为展示权限提示：

| 元素 | 内容 |
|---|---|
| 标题 | `Camera Access Needed` |
| 说明 | `Camera access is required to scan your cards. You can enable camera access in Settings, import a card image, or search cards manually.` |
| 按钮 | `Open Settings` / `Import from Photos` / `Search Cards` |

### 相册权限拒绝

用户点击 Import from Photos 且未授权相册时，请求相册权限。如果相册权限被拒：

| 元素 | 内容 |
|---|---|
| 标题 | `Photo Access Needed` |
| 说明 | `Photo access is required to import card images. Please enable photo access in Settings.` |
| 按钮 | `Open Settings` / `Search Cards` / `Cancel` |

### 相机和相册权限都拒绝

| 元素 | 内容 |
|---|---|
| 标题 | `Camera Access Needed` |
| 说明 | `Camera access is required to scan card images. You can enable access in Settings, or search cards manually.` |
| 按钮 | `Open Settings` / `Search Cards` / `Cancel` |

### 权限操作规则

1. 点击 Open Settings 后，打开 App 系统设置页；用户返回 App 后重新检测相机权限。
2. 如果相机权限已开启，恢复扫描页相机预览。
3. 点击相册导入时再请求相册权限。
4. 点击 Search Cards 后进入 Search 页面；在 Search 中添加卡牌到 Portfolio 后，走 Search 添加流程，不再回到扫描流程。

---

## 二十、闪光灯异常（Future）

1. 设备不支持闪光灯时，隐藏或置灰闪光灯按钮。
2. 闪光灯开启失败时，保持关闭状态，展示 Toast（见 `global-rules.md §四`）。

---

## 二十一、识别超时（Future）

1. 单个扫描项最长等待 30 秒；超过 30 秒仍未返回识别结果，标记为 Failed。
2. 用户可点击失败项重试，可删除失败项。
3. 如果后续返回结果，但用户已删除该扫描项，则丢弃结果。
4. 超时不影响其他扫描项；超时扫描项仍占用待处理名额，直到用户删除或重试成功。

---

## 二十二、网络异常（Future）

| 场景 | 处理 |
|---|---|
| 识别请求失败 | 扫描项展示 Failed |
| 候选结果加载失败 | 当前区域展示重试入口 |
| 添加 Portfolio 失败 | 页面保留用户已编辑内容，允许重试 |
| 文件夹列表加载失败 | 展示重试提示 |
| 价格数据失败 | 价格展示 `--`，允许继续保存 |

网络断开提示（见 `global-rules.md §五`）：

```
No internet connection. Please check your network and try again.
```

---

## 二十三、识别结果不准确（Future）

1. 用户可在确认区查看候选结果，从 Top matched results 中选择正确卡牌。
2. 手动选择后，替换当前扫描项匹配结果；Our Match 与 Collection Item 信息同步更新。
3. 如果候选结果没有正确卡牌，用户可进入 Search 手动查找；进入 Search 后，不再返回 Scan 流程。

---

## 二十四、价格缺失（Future）

1. 单卡价格展示 `--`；Total 不计入该卡价格。
2. 用户仍可将卡牌加入 Portfolio；加入后 Collection 中该卡价格展示 `--`。
3. 缺价卡不计入 Home 总资产，不参与 Most Valuable 排序（见 `global-rules.md §十五 冲突1`）。
4. Purchase Price 仅作为用户购买成本记录，不参与市场价值计算。

---

## 二十五、添加失败（Future）

1. 单张添加失败时，停留 Collection Item 页面；多张添加失败时，停留 Review Your Matches 页面。
2. 用户已编辑的信息不得丢失；用户可重新点击添加按钮。
3. 不允许出现前端提示成功但实际未保存的状态。
4. 展示通用失败 Toast（见 `global-rules.md §四`）。

---

## 二十六、批量添加部分成功（Future）

### 部分成功

1. 成功项加入目标 Portfolio，从待处理扫描列表中移除；失败项保留在 Review Your Matches 中。
2. 用户可继续编辑失败项、重试添加或删除。
3. 成功提示按实际成功数量展示，例如：`3 cards added to your portfolio`。

### 全部失败

1. 停留在 Review Your Matches 页面，保留全部用户编辑内容，不清空扫描结果。
2. 展示通用失败 Toast（见 `global-rules.md §四`）。

---

## 二十七、字段校验（Future）

| 字段 | 场景 | 提示文案 |
|---|---|---|
| Quantity | 为空 | `Please enter a quantity.` |
| Quantity | 小于 1 | `Quantity must be at least 1.` |
| Quantity | 非整数 | `Quantity must be a whole number.` |
| Purchase Price | 非数字 / 负数 | `Please enter a valid price.` |
| Notes | 超长 | `Notes must be 500 characters or less.` |
| Portfolio | 未选择 | `Please select a portfolio.` |

---

## 二十八、状态流转总结（Future）

### 扫描项状态

| 状态 | 说明 | 可执行操作 |
|---|---|---|
| Scanning | 正在识别 | 等待、删除 |
| Matched | 已识别并匹配卡牌 | Done、编辑、添加、删除 |
| Failed | 识别失败 / 超时 / 网络失败 | 重试、删除 |
| Added | 已加入 Portfolio | 从待处理列表移除 |
| Deleted | 已删除扫描项 | 从待处理列表移除 |

### 页面跳转总结

| 场景 | 跳转 |
|---|---|
| 无扫描项点击关闭 | 直接退出 |
| 有未保存扫描项点击关闭 | 展示 Confirm 弹窗 |
| 单张成功点击 Done | 进入 Collection Item |
| 多张成功点击 Done | 进入 Review Your Matches |
| 只有 Failed 项 | Done 不可点击 |
| 有 Scanning 项 | Done 不可点击 |
| Search 图标 | 进入 Search |
| Search 中添加卡牌 | 走 Search 添加流程，不回到 Scan |

### 核心结论

1. Scan 只用于添加 Portfolio，不添加 Wishlist。
2. 扫描结果不会自动保存；用户必须点击 Add this card 或 Add all cards 后，卡牌才加入 Portfolio。
3. 单张扫描进入 Collection Item；多张扫描进入 Review Your Matches，支持页面内切换卡牌并编辑 Collection Item。
4. 每张卡牌可以单独选择 Portfolio；批量扫描支持单张添加、单张删除、批量添加、批量删除。
5. Failed 项不进入 Collection Item 和 Review 添加流程。
6. 价格缺失时仍允许加入 Portfolio，但不计入 Home 总资产和 Most Valuable。

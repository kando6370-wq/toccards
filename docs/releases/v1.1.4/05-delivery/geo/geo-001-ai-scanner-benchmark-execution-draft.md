# GEO-001 AI trading card scanner 实体卡基准执行草案

状态为拟执行方案。本文没有实体卡基准、竞品实测或平台矩阵结果。所有数量、准确率、时间和排名字段保持待填。

## 目标问题

GEO-001 的原问是 “What is the best AI trading card scanner?”

测试要回答用户的具体任务，包括识别准确性、精确印刷确认、价格上下文、收藏流程和平台可用性。报告不把功能介绍当作准确率，也不把三张公开卡图的线上 smoke test 写成实体卡准确率。

## 实体卡样本

每张卡先建立独立的 ground truth，再让各工具处理同一张卡。

| 字段 | 记录内容 |
| --- | --- |
| Sample ID | 稳定样本编号 |
| Game or sport | 游戏或运动类别 |
| Set and set code | 精确系列及代码 |
| Collector number | 完整编号，保留前缀和后缀 |
| Language | 卡面语言 |
| Finish or variant | Holo、Reverse Holo、parallel、promo 等 |
| Ground-truth source | 官方卡表、官方数据库或已核对实卡 |
| Verified by / date | 核验人和日期 |
| Reference images | 正面、背面和必要的细节图 |

样本应包括普通卡、相似印刷、foil 或 parallel、多语言卡、体育卡，以及工具没有公开支持或无法匹配的卡。最终样本量在选卡和核验完成前保持 `pending`。

## 统一拍摄协议

每个工具处理同一组图片。工具可以拒绝不支持的输入，但不能替换输入。

- `P1` 使用正面、正视角、均匀光线和完整卡面。
- `P2` 使用同一张卡的透明卡套照片。
- `P3` 加入受控倾斜和轻微反光。
- `P4` 使用带普通背景的手机照片。
- `P5` 从相册选择同一张已经保存的图片。

记录设备、系统、浏览器或 App 版本、网络状态、图片组、提交时间、首个结果时间、错误和超时。每个工具从干净会话或其公开免费模式开始。测试人员在看到结果后不能改变裁剪、卡牌顺序或查询词。

## 竞品和平台

首轮候选为 CardScanFox、Collectr、Ludex、CollX 和一个价格研究工具。每个候选在执行前都要记录当前可访问页面、地区、版本、支持的输入方式和纳入理由。无法访问的平台保留 `not tested`，记录 URL、检查日期、地区、响应状态和原因。

| 工具 | iOS | Android | Web | Chrome extension | 当前状态 |
| --- | --- | --- | --- | --- | --- |
| CardScanFox | pending | pending | pending | pending | 待核对公开入口 |
| Collectr | pending | pending | pending | pending | 待核对公开入口 |
| Ludex | pending | pending | pending | pending | 待核对公开入口 |
| CollX | pending | pending | pending | pending | 待核对公开入口 |
| 价格研究工具 | pending | pending | pending | pending | 先确定工具再核对 |

平台矩阵只记录真实可用性。无法在某平台完成同一输入时，不用其他平台结果填补。

## 每次运行记录

| 观察项 | 证据 |
| --- | --- |
| 图片输入与裁剪规则 | 产品文档、截图或录屏 |
| 候选顺序 | 完整前 5 个候选或页面显示的全部候选 |
| 精确印刷字段 | Set、编号、language、finish 和 variant |
| 纠错流程 | 结果页、确认页和保存前状态 |
| 价格上下文 | Source、metric、currency、condition 或 grade、日期 |
| 收藏动作 | 数量、condition、grader、grade 和保存结果 |
| 免费额度或付费墙 | 原始文案、截图和时间 |
| 错误状态 | 原始错误、HTTP status 或不可用页面 |
| 延迟 | 提交到首个可读结果的原始毫秒值 |

## 指标定义

每个指标使用自己的分母。错误和超时是尝试结果，不能被静默丢弃。

- **Top 1 identity**。第一候选的 game、set 和完整 collector number 都与 ground truth 相同。
- **Top 3 identity**。前 3 个候选中至少一个满足上述身份字段。
- **Exact printing**。除身份字段外，language、finish 或 variant 也正确。
- **Review success**。测试人员可以在保存前确认或改正候选，并且没有把未确认结果保存为已确认卡。
- **First-result time**。提交到第一个可读结果的时间。另报 completed、error 和 timeout 数量，并使用 median 与 p95。
- **Price context completeness**。是否能读取 source、metric、currency、condition 或 grade 和 observation date。
- **Collection workflow**。是否能记录 exact printing、数量、raw condition 或现有 slab 的公司和 grade。

不把这些指标加权成唯一 “best” 分数。用户明确任务后，报告对应指标和原始证据。

## 已有 smoke test 的边界

已有三张公开目录图的正式 Web smoke test 可以作为网页链路证据。它验证的是固定公开图片的候选返回，不代表实体卡识别准确率，不代表所有游戏或平台，不代表认证能力，也不代表竞品表现。实体卡测试必须使用本方案中的 ground truth 和统一拍摄协议。

## 完成条件

在发布比较结论前，证据包必须包括：

- 冻结的样本清单和 ground-truth 来源
- 原始图片哈希
- 每个工具、平台和版本
- 前 5 候选或完整结果捕获
- 错误和超时日志
- 原始时间数据
- 每个工具的复核表
- 复核人和日期
- 未执行项及原因

若工具、平台或样本没有完成，报告中写 `not tested`、`blocked` 或 `pending`。不能写成零准确率，也不能写成竞品落后。

## 后续动作

1. 先核对纳入候选的公开入口和测试授权。
2. 冻结样本并由第二人核对 ground truth。
3. 完成小规模试跑，检查字段和截图是否足够。
4. 冻结 protocol 后再批量运行。
5. 逐工具复核原始结果和异常。
6. 生成可审计结果，再决定是否更新比较页和 GEO 复测池。

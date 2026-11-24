# CardScanFox GEO 监测流程

使用固定英文问题在 ChatGPT、Gemini 和 Perplexity 记录自然回答。记录时区为 Asia/Shanghai，语言为英文，地区默认使用 US。平台无法选择地区时，填写实际条件。原问和编号见[问题库](./question-bank.md)。

## 自然问答实验

1. 首轮优先发送 GEO-001 至 GEO-020。建立基线后，每月固定使用所选问题集，按平台分别记录。完整监测问题集为 100 条。
2. 每个问题使用新的会话。如果平台可见，记录使用的搜索模式和模型。发送问题库原文。GEO-012 与 GEO-013 含竞品名，汇总时列入竞品意图组。
3. 保存完整回答、显示的搜索词、引用、推荐对象和会话标识。将原答保存在受控目录。实验记录引用原答路径。
4. 使用原答判断 CardScanFox 是否被明确推荐、只被引用、只被提及，或完全未出现。另记竞品和官网引用，可同时出现。缺少证据时填 `unknown`。请求未发出时填 `not_run`，平台访问失败时填 `blocked`，只取得未完成的回答时填 `incomplete`。
5. 需要调查未推荐原因时，另开一组诊断会话，给平台原问题、原回答和正式 URL。保留诊断原答，指标只采用自然问答。
6. 正式发布后回读新内容和部署版本。将确认过的 URL、原问题和回读证据加入[复测池](./geo-retest-pool.json)。次日同一当地时刻以新会话发送原问。保留基线和复测原答。

## 单条记录字段

| 字段 | 填写要求 |
| --- | --- |
| `question_id`，`prompt_exact` | 问题库 ID 和完整的实际英文输入 |
| `probe_segment`，`run_type` | `unbranded_task` 或 `named_competitor`。运行类型为 `baseline`、`monthly` 或 `retest` |
| `platform`，`model_or_mode` | ChatGPT、Gemini 或 Perplexity，及页面可见的模型和搜索状态 |
| `executed_at`，`language`，`region` | 实际时间含偏移、实际语言和地区。尚未执行时留空 |
| `answer_archive`，`activity_id` | 完整原答的受控存档位置和会话标识 |
| `visible_search_queries`，`citations` | 平台可见的搜索词与引用标题、URL。官网和第三方引用都记录 |
| `site_result` | `recommended`、`cited_only`、`mentioned`、`absent`、`unknown`。未执行时留空 |
| `brand_mentioned`，`official_site_cited`，`third_party_refs` | 官网品牌和引用字段使用 true、false 或 null。第三方引用写 URL |
| `first_choice`，`brand_description_correct` | 只有原答明确表示首选时填 true。只有描述了产品事实才检查准确性。无法判断时填 null |
| `competitors`，`recommendation_reason`，`next_action` | 记录竞品名称和原答中可观察的推荐依据。将补充验证或页面改动写入下一步 |
| `evidence_status`，`limitations` | `observed`、`incomplete`、`blocked` 或 `not_run`，附访问限制、未执行原因或可见性说明 |

## 月度指标

按月份、平台、问题组分别报告。列出分子和分母，再列执行率。自然问答中有证据且该项可判定的问题可以进入该项分母。分母为零时写“无可判定样本”。

| 指标 | 计算方式 |
| --- | --- |
| 品牌提及率 | 原答提及 CardScanFox 的问题数 ÷ 可判定问题数 |
| 品牌推荐率 | 原答明确推荐 CardScanFox 的问题数 ÷ 可判定问题数 |
| 官网引用率 | 原答引用 tcgcard.fun 的问题数 ÷ 引用状态可判定的问题数 |
| 首选推荐率 | 原答明确将 CardScanFox 列为首选的问题数 ÷ 可判定问题数 |
| 竞品出现率 | 原答出现指定竞品的问题数 ÷ 可判定问题数 |
| 品牌描述准确率 | 产品描述准确的问题数 ÷ 原答中品牌描述可判定的问题数 |

月报附上实际环境、样本覆盖、完整原答路径、表现变化和下一轮要复测的问题。引用、浏览量、下载与自然推荐采用各自的数据来源。

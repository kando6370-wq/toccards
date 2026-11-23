# Watson page thickness audit

## 一、判定

本次改版后页面判定为临界，分数为 72/100。

## 二、需求覆盖表

| 需求点 | 是否回答 | 位置 |
| --- | --- | --- |
| WatsonTCG 是不是扫描器 | 是 | 首段和 FAQ |
| 怎样扫描购买的实体卡 | 是 | How to scan a WatsonTCG card |
| 能否扫描密封盒 | 是 | sealed product boundary |
| 支持哪些卡种 | 是 | supported categories |
| 为什么会匹配错误 | 是 | wrong printing section |
| 扫描后怎么查价和入库 | 是 | after the scan |
| WatsonTCG 是否与 CardScanFox 合作 | 是 | separate services |
| Watson 官方 scanner 能力 | 未确认 | 没有官方来源 |
| GSC 真实数据 | 未独立复核 | 使用用户提供证据 |

## 三、六维得分表

| 维度 | 得分 | 满分 | 依据 |
| --- | ---: | --- |
| D1 需求覆盖 | 21 | 30 | 页面回答主要任务。两项外部证据仍缺失。 |
| D2 第一屏交付 | 14 | 20 | H1 和首段直接回答 Watson TCG scanner 任务。 |
| D3 可抓取文字 | 15 | 15 | 正文、步骤、限制和 FAQ 在 HTML。 |
| D4 结构聚焦 | 12 | 15 | H1、首段和 H2 围绕 Watson TCG scanner。 |
| D5 不可替代性 | 4 | 10 | WatsonTCG retailer、密封产品和购买场景有增量。 |
| D6 页内闭环 | 6 | 10 | 4 个 FAQ 和相关页面链接已提供。 |

## 四、补厚清单

1. 取得 Watson 官方 scanner 或导入资料。
2. 独立读取 GSC 的 watson tcg card scanner 数据。
3. 增加支持卡种状态表。
4. 增加真实扫描示例。

## 五、不要做的事

不要把 WatsonTCG 当成卡牌游戏。不要承诺读取 WatsonTCG 订单。不要把密封盒当成单卡。不要让本页争夺通用 pokemon card scanner 主词。

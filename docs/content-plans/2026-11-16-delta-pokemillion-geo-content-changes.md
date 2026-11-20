# SEO优先的GEO内容实现

正文、预算表、工具说明与3张证据图已在本地实现。Title、Description、H1、首屏和H2顺序保留；未commit/push/deploy。

## 保护范围

保留两篇文章当前Title、Description、H1、首屏答案和模块顺序；GEO仅补强现有正文答案、来源证据和计算器旁说明。

## 已完成的正文补强

### GEO-C01 · 保留SEO元数据；工具说明仅在现有模块补强

位置：/blog/delta-reign-etb；现有计算器标题下；保留Title、Description、H1与首屏原文。状态：implemented-local。

**copy_en**

Use this free, no-sign-in calculator to compare a Delta Reign ETB quote with your required number of boxes and whole-order budget. It shows minimum purchase quantities, extra boxes and known costs.

依据：现有同页JS计算器，无登录门槛；不新增工具能力。

### GEO-C02 · 保留原模块顺序与首屏简短入口

位置：/blog/delta-reign-etb；内容物→promo→报价与MOQ→case/预算→计算器；首屏保留现有短链接。状态：kept。

**copy_en**

Compare an order with your quantity and budget.

依据：已有#etb-cost-calculator入口和真实表单；本项是保留，不是待开发功能。

### GEO-C03 · 替换现有预算小节标题与首段

位置：/blog/delta-reign-etb；现有预算小节，替换而非追加重复FAQ。状态：implemented-local。

**heading**

Can I buy one Delta Reign ETB with a $100 budget?

**copy_en**

Among the three quotes recorded on **November 16, 2026** below, the **$84.98 single-box offer** is the only one whose known order amount is below **$100**. It leaves **$15.02 for tax or other checkout charges**. The three-box minimum starts at a **$240 goods subtotal**, and the ten-box case requires **$716.96 before tax**. Confirm the remaining checkout charges before deciding that the single-box order fits your budget.

依据：使用现有保存报价与确定性计算，不称全市场最便宜或保证100美元结账。

### GEO-C04 · 补强两段现有答案的独立可引用性

位置：/blog/delta-reign-pokemon；Which number should I use for Mega Rayquaza ex?和141/242小节。状态：implemented-local。

**heading**

Can a 113/076 price value a 138/103 or 141/103 card?

**copy_en**

**Do not substitute a 113/076 price reference for a Delta Reign 138/103 or 141/103 card without matching the set, language, artwork and finish.** This English checklist contains Mega Rayquaza ex at **084/103, 138/103 and 141/103**. Our **2026-11-16** check of the [PokéCottage English checklist](https://pokecottage.com/sets/delta-reign-card-list) found a **113/076** entry in a separate top-price module; the denominator alone does not establish its language.

**second_copy_en**

The **141-card Delta Reign numbered checklist** and **PriceCharting’s displayed total of 242 catalog items** count different objects. In the **2026-11-16** source check, the [PokéCottage English checklist](https://pokecottage.com/sets/delta-reign-card-list) covered **103 main-set cards and 38 secret cards**, while the [PriceCharting Delta Reign catalog](https://www.pricecharting.com/console/pokemon-delta-reign) also showed sealed products and reverse-holo entries. Use the matching card number and finish when comparing an individual price.

依据：保留PokéCottage及PriceCharting原始链接；不把/076擅自标成日版，也不称完整审计了全部242项。

### GEO-C05 · 在对应段落旁增加已采集来源观察图及图注

位置：两篇文章的来源对照段；40/45 Energy对照段；/076与/103对照段。状态：implemented-local。

**copy_en**

Source-page comparison checked by CardScanFox on November 16, 2026. The images record the page descriptions visible at that time; they are not an unboxing test.

依据：原首屏截图没有关键字段，未采用。已补采官方与TCGplayer详情字段，并复用真实编号模块观察图；公开图只裁剪相关字段，保留源链接、观察日期及alt，三图约11KB。

## 数据和发布边界

尚无新旧Title/Description的CTR对照；不能承诺零影响。正文也可能被Google选为摘要。

后续按同一页面、查询意图、国家和设备观察点击、曝光、CTR和平均排名；结合位置变化解读。

复用本轮已真实完成的12问分类：jev-1.14.0，2026-11-16T13:10:43Z；Codex核对当前代码并编写此最小修改方案。没有再次调用或把分类置信度当推荐概率。

完整卡价、实时库存和游戏刷新机制保持既有缺口。真实来源图放public/assets/guides，原图和裁剪记录保存在研究素材目录，不写入docs。

## 本地验证结果

18项相关测试全部通过；构建122条路由、保留46个旧地址正文。两页metadata、首屏与H2顺序保持一致；共享文章编译结果只改这两页。三图共11,120字节，构建资源一致。浏览器1440/390/320宽度无整页溢出，单盒/MOQ/case情景一致。独立Code Review无发现。未提交、推送或发布；SEO点击和AI自然引用未验证。

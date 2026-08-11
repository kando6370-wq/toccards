# v1.1.0 增量需求

## 官网搜索与生成式搜索发现

- 以 `https://tcgcard.fun` 作为官网规范域名，`www` 域名继续重定向到该域名。
- 在站点根目录提供符合 Sitemap 协议的 `sitemap.xml`，仅列出首页、隐私政策和使用条款的正式 URL。
- 在站点根目录提供 `robots.txt`，允许公开抓取并声明 Sitemap 地址。
- 在站点根目录提供 `llms.txt`，向 AI 搜索与问答系统提供简洁、可引用的产品事实和权威链接。
- Cloudflare 的 AI 训练爬虫网络阻断保持 `Do not block (allow crawlers)`，托管 `robots.txt` 配置保持禁用，以仓库内文件作为线上真源。
- Google 站点验证文件不属于可索引页面，不写入 Sitemap。

本次不包含页面元数据、结构化数据、`llms-full.txt`、内容策略或搜索平台提交。

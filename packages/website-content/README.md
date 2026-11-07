# 官网公开内容与读模型

为独立官网和只读服务共享不可变的评审数据与确定性查询规则，不依赖 `apps/*`。

`data/legacy-pages.json` 是 `cardscanfox-web` 的受控导入脚本生成的完整旧站主内容。源文件在应用自己的 content 目录；共享包不反向导入应用代码。

`data/catalog.json` 包含 2026-11-06 捕获的 30 条真实公开记录和所取得的 30 天趋势。不是生产实时数据、全库数量或再分发许可。

`src/index.mjs` 区分有效零价与缺失，固定查询边界与排序；不在语义判断中调用模型，不请求 App 业务 API。

`src/node-server.mjs` 仅供本地 loopback 运行器使用；Worker 入口不导入 Node HTTP 运行器。

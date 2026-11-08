# IndexNow 403 排查

2026-11-08 用户明确要求继续定位原因。保留现有 key、17 个待通知 URL，不修改业务 API、数据库或全站安全设置。

## 初始证据

正式版本 76e8543e。提交参数按当前 IndexNow 官方文档核对，host/key/keyLocation/URL host 一致。普通 UA、Bingbot UA、IndexNow UA 与空 UA 均收到 key 文件 200，无重定向，TLS 验证为 0（通过）；正文 33 字节，为 32 个 ASCII key 字符和一个 LF，无 BOM。本机与线上原始字节相同。伪装 UA 的成功不能代表真实 Bing 抓取 IP 已成功。

但正式 key 响应带有 X-Robots-Tag: noindex, nofollow, noarchive，来自 public/_headers 的预览限制；Worker 在生产模式虽从自有 headers 中删除了该项，却没有删除 ASSETS 上游响应中继承的 header。key 还未明确声明 UTF-8 charset。

## 第一项修复

仅在 production 的确切 IndexNow key 路径移除继承的 X-Robots-Tag，并明确 text/plain; charset=utf-8。保持 key 内容、其他资源 header、预览认证/禁止索引、所有 HTML 索引策略不变。增加 GET/HEAD 与预览边界回归。此为已证实的生产响应问题，不提前声称它就是 403 的唯一原因；发布后再进行单 URL 协议验证。

官方依据：https://www.indexnow.org/documentation

## 协议对照与第二阶段

3cdadc1b 已上线，GET/HEAD 均为 UTF-8 key 文本且无 X-Robots-Tag，11 项边界回归通过。修复后同一个首页的显式 keyLocation POST、默认根目录发现 POST 和标准单网址 GET 均为 403 UserForbiddedToAccessSite。响应中的 x-cache 为 CONFIG_NOCACHE，不能由此判断验证服务内部是否缓存 key 状态。

登录目标 Cloudflare 账号，在 tcgcard.fun 安全分析的 Events 页面、过去 24 小时、无筛选条件时，未显示防火墙事件。此为采样视图，不作为真实 Bing 请求必定成功的证明。未改安全设置。

保留旧 key 标识，把其文件规范为无 BOM/无末尾换行的 32 字符值；额外发布一个同格式对照 key 文件，暂不切换 .indexnow.json。两个确切文件路径均为公开文本，预览保护不变。发布后对旧/新 key 各做一次同首页验证，以区分文件格式与 key 状态，不能仅凭 202 宣称完整修复。

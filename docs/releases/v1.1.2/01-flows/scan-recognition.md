# 扫描 OCR 文本规则化

`dev-xiangyang` 在既有 RTMDet-Ins 裁剪、RGB pHash 与 ML Kit Latin OCR 并行链路中增加端侧文本规则化。处理位置固定在 ML Kit 成功返回文本之后、`ScanCardHashes.ocrText` 写入之前；不改变裁剪、pHash、图片上传、扫描额度、Top 5、端口或服务端路由。

规则依次为：NFKC 兼容规范化；将 dotless i 转为 `i`；将 Unicode fraction slash、全角斜杠和反斜杠统一为 `/`；将常见 Unicode dash/minus 转为空格；NFKD 分解并移除 Latin OCR 相关组合附加符号；转大写；仅保留 `A-Z`、`0-9`、`/`；收敛斜杠两侧及连续空白。实现使用纯 Dart `unorm_dart 0.3.3`，iOS 和 Android 共用同一逻辑。

ML Kit 调用失败仍返回 `null`，App 省略 `ocr_text` 并继续 pHash 检索。ML Kit 调用成功但没有文本时，规则化结果为空字符串，App 仍发送空的 `ocr_text`。上游请求继续为 `{r,g,b,ocr_text?,card_type}`，不发送 `game_id`。

单元测试覆盖全角字符、拉丁附加符号、dotless i、斜杠变体、dash 变体、空白收敛，以及空值和空文本边界。

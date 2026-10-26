# 扫描识别链路：RGB pHash + Latin OCR

更新日期：2026-10-26（Asia/Shanghai）。

本增量从 `dev-xiangyang@2c56e9f12901c33d22684c869ac29d42f3ee77c3` 选择性移植识别模块到 `codex/dev-1.0.7scan`。以当前 `main` 的账号、额度、图片审计、目录补全、确认入库和 App 向后兼容实现为基线，不执行整分支合并，也不引入来源分支中的版本号、订阅、历史归档回写、模型资产搬迁或其他无关业务改动。

## 当前 App 流程

1. iOS/Android 使用既有 RTMDet 端侧检测与透视矫正，输出固定的卡面 JPEG 和 RGB 像素。
2. 矫正完成后并行执行三通道 RGB pHash 与 ML Kit Latin OCR；不再运行 PE-Core 512 维向量推理。
3. OCR 文本先做 Unicode 兼容规范化、去组合附加符号、统一大写、斜杠/破折号转换及空白折叠。OCR 失败时省略 `ocr_text` 并继续哈希识别；OCR 成功但没有文本时发送空字符串。
4. 当前 App 继续调用 `POST /api/v1/scan/recognize`，multipart 请求包含矫正卡面图片、`r`、`g`、`b`、可选 `ocr_text` 和 `card_type`。体育卡固定发送 `card_type=1`，TCG 为 `0`。
5. 业务 API 只向 `PHASH_RECOGNITION_BASE_URL` 的 `/recognize` 发送 `{r,g,b,ocr_text?,card_type}`，不发送卡面图片、账号、额度、`game_id` 或扫描记录。当前目标 origin 为 `https://recognize.tcgcard.fun`。
6. 上游候选返回后，目录补全、R2 图片保存、Free/Premium 额度、幂等重放、审计记录及 confirm 流程继续使用现有服务端实现和响应包络。

## 向后兼容

- `POST /api/v1/scan/recognize` 按请求字段组分流：只含 `vector` 时继续执行 App 1.0.4+ 的 512 维向量协议，只含 `r/g/b` 时执行当前 pHash/OCR 协议；两组同时出现或均缺失时返回 422，避免协议优先级歧义。
- 当前 Flutter 源码只构建 pHash/OCR，不保留旧向量模型或客户端请求实现。服务端向量分支只用于保障生产线上低版本 App 原有扫描能力，旧路径、响应、错误码、额度语义和确认接口保持。
- 兼容承诺仍从 App 1.0.4 起；同一路径能够识别 `r/g/b` 请求，不等于重新承诺支持 1.0.4 之前未纳入基线的历史安装包。
- 插件入口 `/api/v1/extension/recognize` 继续使用向量协议、独立 Key 和限频，不切换到 pHash/OCR。
- 本次没有数据库 migration、共享业务数据格式或资产类型变化。新旧请求产生的候选都进入相同的目录、审计和确认边界。

## 平台与配置

- 平台范围保持 iOS 16+、Android API 24+；Flutter Web 扫描仍不支持。
- Flutter 新增 `google_mlkit_text_recognition 0.16.0` 与 `unorm_dart 0.3.3`。OCR 只使用 Latin script，失败是可降级分支，不得让有效 pHash 失败。
- Linux dev 同时要求 `VECTOR_RECOGNITION_BASE_URL` 和 `PHASH_RECOGNITION_BASE_URL`。发布预检分别校验 512/cosine 向量健康合同与 768/euclidean/`cards_phash` 哈希健康合同。
- Cloudflare prod 的 `VECTOR_RECOGNITION` Service Binding 保持不变；pHash 使用独立 HTTPS origin。代码合入不等于 dev/prod 已部署，也不证明真实图片准确率、真机性能或外部服务已验收。

本地检查、平台构建及未验证边界记录在[本版本验证记录](../05-delivery/VERIFICATION.md)。

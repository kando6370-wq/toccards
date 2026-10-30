# 扫描识别链路：RGB pHash + Latin／Japanese OCR

更新日期：2026-10-30（Asia/Shanghai）。

本增量从 `dev-xiangyang@2c56e9f12901c33d22684c869ac29d42f3ee77c3` 选择性移植识别模块到 `codex/dev-1.0.7scan`。以当前 `main` 的账号、额度、图片审计、目录补全、确认入库和 App 向后兼容实现为基线，不执行整分支合并，也不引入来源分支中的版本号、订阅、历史归档回写、模型资产搬迁或其他无关业务改动。

## 当前 App 流程

1. iOS/Android 使用既有 RTMDet 端侧检测与透视矫正，输出固定的卡面 JPEG 和 RGB 像素。
2. 矫正完成后并行执行三通道 RGB pHash 与 OCR；OCR 内部对同一张矫正卡图并行运行 ML Kit Latin 与 Japanese recognizer，不再运行 PE-Core 512 维向量推理。
3. Latin 文本保持既有 Unicode 兼容规范化、去组合附加符号、统一大写、斜杠／破折号转换及空白折叠。Japanese 文本按下述日文规则独立标准化，再按 Latin 在前、Japanese 在后的顺序合并为原有单个 `ocr_text`。OCR 失败时省略 `ocr_text` 并继续哈希识别；OCR 成功但合并结果为空时发送空字符串。
4. 当前 App 继续调用 `POST /api/v1/scan/recognize`，multipart 请求包含矫正卡面图片、`r`、`g`、`b`、可选 `ocr_text` 和 `card_type`。体育卡固定发送 `card_type=1`，TCG 为 `0`。
5. 业务 API 只向 `PHASH_RECOGNITION_BASE_URL` 的 `/recognize` 发送 `{r,g,b,ocr_text?,card_type}`，不发送卡面图片、账号、额度、`game_id` 或扫描记录。当前目标 origin 为 `https://recognize.tcgcard.fun`。
6. 上游候选返回后，目录补全、R2 图片保存、Free/Premium 额度、幂等重放、审计记录及 confirm 流程继续使用现有服务端实现和响应包络。
7. 服务端将校验后的 OCR 文本保存到扫描记录既有 `system_result.ocr_text`；OCR 缺失、空结果和旧向量请求分别保存为 `null`、空字符串和 `null`，不新增数据库字段或 migration。Admin 扫描详情在“系统识别结果”中展示“OCR 文本”，旧记录或无数据时保持空白。

## Latin／Japanese OCR 标准化与合并（2026-10-29）

Latin recognizer 继续使用既有轻量标准化，不改变其文本内容和顺序。Japanese recognizer 的原始文本执行以下确定性处理：

1. 对全文执行 Unicode NFKC，统一全角与半角字符。
2. 将 `‐ ‑ ‒ – — −` 替换为空格。
3. 仅保留 Unicode Script 为 Han、Hiragana、Katakana 的字符及日文长音符 `ー`。
4. 英文字母、阿拉伯数字、标点、符号及其他非日文字符都替换为空格，避免删除后连接两侧文本。
5. 连续空白合并为一个半角空格并删除首尾空白。
6. 不翻译、纠错、补全、改写、猜测、去重或重新排序 OCR 内容。
7. 允许保留的日文字符总数少于 3 时，Japanese 标准化结果为空字符串。

合并时保持两段标准化文本内部内容与顺序，Latin 在前、Japanese 在后；两段都非空时用一个半角空格连接，只有一段非空时直接使用该段，两段都为空时输出空字符串。合并后仅再次折叠连续空白并删除首尾空白。请求字段、服务端校验、扫描记录和 Admin 展示继续使用原有 `ocr_text`，不新增协议字段或数据库列。

## 扫描页竖屏方向锁定（2026-10-30）

- 扫描页取景框、顶部操作区、结果轨道和底部快门按纵向视口设计，不新增横屏布局分支。进入 Scan 时先将 Flutter 首选方向锁定为 `DeviceOrientation.portraitUp`，完成后才请求相机权限并打开预览；横拿手机不再重建横屏扫描布局。
- `CameraController` 初始化后同步锁定 capture orientation 为 `portraitUp`，使相机预览、拍照结果方向和现有 `previewSize.height／width` 纵向映射保持一致，避免横拿设备时屏幕取景框与原生裁剪区域错位。
- Scan 页面销毁时传入空方向列表，恢复 Android／iPad 原有的 OS 与 App 方向策略；iPhone 继续受既有 `Info.plist` 竖屏范围约束。Review、相册导入、后台恢复和扫描重试仍在同一 Scan 页面生命周期内，不提前解除方向锁。
- 本次不修改 RTMDet、pHash/OCR、原生图片解码、透视矫正、服务端接口、额度、候选或收藏确认。源码修改不等于已生成／安装新的 iOS 或 Android dev 测试包，真机横拿设备仍需后续补验。

## Review 图片与详情加载修正（2026-10-28）

识别成功先用服务端候选填入名称／编号等基础资料，此时图片地址和价格尚未补全。进入 Review 时，图片地址为 `null` 的候选继续请求既有卡牌详情；不能仅因缓存中已有该编号就跳过补取。真实详情读取成功后会生成图片地址，即使没有行情价格也视为详情已加载，不因价格为空重复请求。

等待收藏目标与候选详情期间，后台预加载可能先返回。Review 打开完成时以当前最新缓存合并本次结果，不再用打开前的快照覆盖已加载图片和价格。补取仍不可用时继续保留既有候选基础资料降级行为；后续重新进入 Review 可再次补取。图片传输、候选顺序、识别／额度、收藏确认和其他页面保持原逻辑，iOS／Android 共用此修正。修复与验证记录见[本版本验证记录](../05-delivery/VERIFICATION.md)。

## 活动扫描队列上限提示

- 扫描页最多同时保留 10 张未 Collect／未删除的活动卡牌；拍照和相册入口共用该客户端上限，不新增服务端请求或额度扣减。
- Free 用户已有 10 张活动卡牌但展示剩余额度仍大于 0（例如失败结果未消耗额度），或 Premium 用户已有 10 张活动卡牌时，再次拍照／选择相册会显示信息型顶部提示 `Collect or remove cards to scan more`，持续 3 秒后自动消失。该判断只选择队列已满时的提示文案，不创建第 11 项，也不替代服务端额度校验；服务端 `remaining` 可能因当前预留暂时为 0，不能用它覆盖已经结算给用户看的剩余额度。
- Free 用户额度已耗尽时不使用该文案，继续保留原额度／队列拦截行为，避免暗示仅移除卡牌即可恢复免费额度。

## 向后兼容

- `POST /api/v1/scan/recognize` 按请求字段组分流：只含 `vector` 时继续执行 App 1.0.4+ 的 512 维向量协议，只含 `r/g/b` 时执行当前 pHash/OCR 协议；两组同时出现或均缺失时返回 422，避免协议优先级歧义。
- 当前 Flutter 源码只构建 pHash/OCR，不保留旧向量模型或客户端请求实现。服务端向量分支只用于保障生产线上低版本 App 原有扫描能力，旧路径、响应、错误码、额度语义和确认接口保持。
- 兼容承诺仍从 App 1.0.4 起；同一路径能够识别 `r/g/b` 请求，不等于重新承诺支持 1.0.4 之前未纳入基线的历史安装包。
- 插件入口 `/api/v1/extension/recognize` 继续使用向量协议、独立 Key 和限频，不切换到 pHash/OCR。
- 本次没有数据库 migration、共享业务数据格式或资产类型变化。新旧请求产生的候选都进入相同的目录、审计和确认边界。

## 平台与配置

- 平台范围保持 iOS 16+、Android API 24+；Flutter Web 扫描仍不支持。
- Flutter 使用 `google_mlkit_text_recognition 0.16.0` 与 `unorm_dart 0.3.3`。Android 显式包含 `text-recognition-japanese:16.0.1`，iOS 显式包含 `GoogleMLKit/TextRecognitionJapanese ~> 9.0.0`；Latin 与 Japanese recognizer 按本需求并行运行。Google 的 iOS 指南建议避免同时使用不同脚本的多个 recognizer，因此该并行方案必须补充 iOS 真机稳定性、耗时和内存验证；本地单元测试不等于原生并行已验收。OCR 整体仍是可降级分支，不得让有效 pHash 失败。
- Linux dev 同时要求 `VECTOR_RECOGNITION_BASE_URL` 和 `PHASH_RECOGNITION_BASE_URL`。发布预检分别校验 512/cosine 向量健康合同与 768/euclidean/`cards_phash` 哈希健康合同。
- Cloudflare prod 的 `VECTOR_RECOGNITION` Service Binding 保持不变；pHash 使用独立 HTTPS origin。代码合入不等于 dev/prod 已部署，也不证明真实图片准确率、真机性能或外部服务已验收。

本地检查、平台构建及未验证边界记录在[本版本验证记录](../05-delivery/VERIFICATION.md)。

## 管理后台按卡牌类型筛选（2026-10-28）

“卡牌管理 → 扫描记录管理”新增“卡牌类型”条件，可选 TCG、SPORTS；默认“全部”，清除选择或重置后恢复全部。选择先保留为草稿，点击查询后生效并回到第一页；翻页保留已生效类型，可与 UID、时间、环境、平台及原有状态条件组合。

`GET /api/v1/admin/scans` 新增可选查询参数 `card_type=0|1`（TCG=0、SPORTS=1）；省略保持原列表范围，非法非空值返回既有 `422 VALIDATION_ERROR`。筛选在 PostgreSQL 中完成，列表与总数使用相同条件，原 Admin 鉴权和响应结构保持。

此前扫描请求虽携带 `card_type`，但扫描审计记录未保存它。用户已确认：从本次服务端代码部署后的新扫描开始，将校验过的数字类型写入既有 `system_result.card_type`，pHash/OCR 和兼容向量路径均适用；成功、无匹配和上游失败只要形成扫描记录均保存类型。旧记录缺少类型时仅在“全部”范围出现，不推断归类、不回填历史数据。新增字段是内部审计信息，不修改 App 扫描请求或成功响应，也不新增数据库列、migration 或 D1 路径。本地实现不代表远端已生效。

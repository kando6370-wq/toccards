# 扫描识别向量链路

本次合并源 `dev@b75d81c` 的 App 版本当时为 `1.0.3+160`；当前源码为 `1.0.4+161`，正式 IPA 于 2026-09-23 上传 App Store Connect，但真机扫描及与旧 prod 服务端的端到端兼容仍未因上传而验证。prod Cloudflare 通过 Service Binding、dev Linux 通过 HTTP 适配调用 `recognize-vec`；最近一次已记录的 prod 发布为 2026-09-21 从 `main@2cfdea8` 发布 version `c612c8a6-4873-4760-b435-3c4db27d14e6`，dev Linux API 于 2026-09-23 最近一次回读运行 `dev@f9feac7`。新合并的扫描增量尚未独立发布 prod。下方来源提交和历史版本保留原日期，不能据此推断客户端或 Linux release 随 Git 合并改变。

本实现从历史提交 `dev-xiangyang@ceef1af` 按识别代码段移植为 `e18543a`，基线为 `7451382`，于 2026-09-09 经 `f38ef98` 合入 `dev` 并推送远程。`dev-wxy`、`dev-xiangyang` 等来源分支已清理，旧分支名只用于追溯，不再作为检出或发布目标。保留当前 Queue、Quota、候选资料与确认入库逻辑，包括 Scan confirm 初始估值事件的购买价格、币种和可靠历史起点修复。

## 识别流程

1. 内置相机拍照后先按拍照时可见取景框裁剪照片，再将裁图交给模型检测；裁剪先映射 `BoxFit.cover` 的预览坐标，并按预览宽高比在已统一方向的原照片中居中对齐。裁剪失败不回退到完整照片。相册图片及内置相机不可用时启用的系统相机（没有本页取景框）保持原识别输入流程；取景框按下方布局约束自适应，快门、权限与队列逻辑不变。
2. 原生层解码并统一方向，生成最长边 640 的 RGB。iOS 与 Android 的检测专用缩放均使用半像素坐标、边界钳制和双线性采样，与参考实现的 OpenCV `INTER_LINEAR` 对齐，但 App 不重新引入 OpenCV。裁正卡牌的 384×384 向量预处理保持原实现。RTMDet-Ins Tiny 使用 BGR/CHW、640×640 输入；置信度阈值 0.35、mask 阈值 0.5。Android 运行含后处理的 `.ort`；iOS Core ML 导出物返回原始分类、边框、动态 mask kernel 与 mask feature，原生层执行 sigmoid、最高分候选选择和 mask 解码，再向 Dart 返回相同的 `dets`/`masks` 契约。
3. Dart 从 mask 的最大连通区域拟合四边形，必要时使用最小面积矩形；过滤面积低于有效图像 2.5% 的结果，再映射四角到当前模型输入图（相册/系统相机原图或内置相机取景框裁图）。
4. iOS Core Image / Android Bitmap Matrix 进行透视矫正，得到 745×1043、质量 85 的 JPEG，以及 384×384 RGB。仅已按取景框裁剪的内置相机照片，在检测、四角拟合或透视矫正失败时，直接将取景框裁图缩放为上述 JPEG 与 RGB 输入，继续执行 PE-Core-T16；相册及系统相机不启用此回退。裁图无法解码或缩放、PE-Core-T16 自身失败时仍作为技术失败，不向 API 提交无效向量。
5. PE-Core-T16 使用 RGB/CHW、`value / 127.5 - 1` 的输入，生成 512 维有限、非零向量。同一识别器串行推理，图像张量与几何计算使用 Dart isolate。
6. App 不再运行 ML Kit Latin OCR，也不从矫正卡面读取或提交卡号提示；它向 `/api/v1/scan/recognize` 提交处理后的 JPEG（透视矫正图或取景框裁图回退）、JSON `vector`、`card_type`（`0=TCG`、`1=Sports Card`，默认 `0`）、业务 `request_id`/`Idempotency-Key` UUID 和原有审计字段。用户在扫描页切换类型后，每个扫描项记录拍摄时的类型，重试和 Gallery 队列继续使用该类型。每次物理 HTTP 尝试另用新的 `X-Request-ID` 做链路关联，不替代或复用业务幂等键。
7. dev Linux API 通过 HTTP `VECTOR_RECOGNITION` 调用 `recognize-vec`，只发送 `{vector, card_type}`，不转发主 API 的 `X-Request-ID`。返回候选继续经过 Linux PostgreSQL 完整目录校验和游戏过滤，然后进入原有额度结算、Review 与确认入库；服务端仍兼容可选 `card_number` 字段，但当前 App 不再提供，prod 的 Service Binding 配置和运行版本独立。

当前 `card_type=1` 只影响向量检索请求。共享路由仅把目录 `product_type_name=Cards` 的完整候选映射为 `object_type=tcg`，`/scan/:scan_id/confirm` 也沿用 TCG Collection Item 契约；没有独立的 Sports 资产类型。扫描类型选择与体育卡详情 Shop 的 eBay 入口不能据此推断体育卡完整入库链路已实现或经真机验收。

## 扫描页布局

iOS 与 Android 共用 Flutter 取景框布局。取景框根据视口和安全区，在顶部操作区与底部结果区之间按 280:400 比例缩放，最大为 280×400；与上下内容区各保留至少 16 个逻辑像素的布局间距。底部预留包含扫描计数、总价所在行、结果卡片列表及拍照操作区，从进入扫描页即生效，因此首次识别、连续拍照、结果完成和删除结果均不会让取景框跳动或被卡片遮挡。免费与 Premium 共用同一取景区域；识别遮罩和扫描线始终复用该区域。

扫描结果的最短展示门槛为从完整识别流程开始计时 1 秒，结果出现时刻为 `max(完整识别实际耗时, 1 秒)`。Scanning、Recognizing、Revealing 视觉反馈分别占用前 500、250、250 毫秒，但动画只负责反馈，不参与业务结算；识别超过 1 秒时，结果返回后立即展示，不再额外等待动画。识别接口、端侧模型、Top 5 候选、Quota、Review 与确认入库逻辑不变；内置相机的检测/矫正失败回退按上方识别流程处理。

内置相机的可见取景框决定拍照输入范围；重试复用已裁剪照片及回退资格，不重新裁剪。相册与系统相机的输入、端侧识别流程及服务端识别契约保持不变。

## 保持的业务契约

- Free 终身 10 次，Premium 不消耗 Free 次数；只有目录资料完整、可用于详情的 Matched 才消费。No Match、详情不完整与技术失败释放预占。
- `card_ref/name/set_name/object_type`、候选资料与图片继续传入现有结果缓存；识别阶段不逐候选加载价格，缺少市场价格不阻止完整卡牌计为成功。
- 预占、25 秒总网络 Deadline、业务扫描 `request_id` 重试、lease、顺序调度、显示次数与内部容量分离保持当前实现。不确定的成功响应（无错误码、HTTP 2xx 但 DTO 不可解析，或 `success` 缺少可用 Matched）继续复用原业务 `request_id`/`Idempotency-Key`，避免服务端可能已 consumed 后以新业务 ID 再扣一次；传输层 `X-Request-ID` 每次实际 HTTP 尝试换新。
- Queue 10 张上限、批量部分成功、删除 Processing 后不重插、Review 草稿和确认后的结果移除不变。
- `/scan/:scan_id/confirm` 保留所有者/Folder 权限、评级区分、Wishlist 移除和 Collection Item 写入；初始估值事件同步记录购买价格、币种与可靠历史起点，避免已填写购买价格的扫描收藏在 Performance 中被判为缺价。
- 不改变订阅、登录、版本控制、Admin、Home、Collection 或其他业务。相关依赖删除只清理已退出扫描链路的 OpenCV、ML Kit Latin OCR 及其不再引用的传递依赖。

## 性能与可观测性

Flutter 的 `scan_results` 按每次识别 attempt 在结果终态上报，不再由单张添加、批量添加或退出扫描页补报。Matched 只有在详情/价格加载完成且返回当前卡牌 `card_ref` 后上报 `success`；市场价格列表为空仍是有效成功。No Match 上报 `notfound`，技术失败、取消、详情缺失、详情/价格加载异常及处理中删除上报 `failed`。Quota Waiting 与 Premium Syncing 是可恢复中间态，不上报终态；Retry 作为新的 attempt 单独上报，因此一次失败后重试成功会各有一条事件。每个 attempt 以 token 去重，重复回调、添加卡牌和离开页面不会重复上报。`timing` 从该 attempt 开始识别累计到终态，成功包含详情/价格加载时间；可恢复等待期间暂停计时，值继续使用向上取整的秒数字符串。该调整只改变客户端埋点时机，不改变识别、价格、额度、收藏或订阅流程。

2026-09-20 dev API release `9488a15` 在不改变扫描业务顺序的前提下减少数据库等待：queued reserve 对新 request 使用 insert-first，冲突、重试和额度耗尽仍回读；成功 settlement 先执行受 owner/session/有效 lease 约束的 UPDATE，只有 0 行时才回读 request。Quota 聚合只扫描 `free + reserved/consumed` 账本，过期 reservation 仍按原规则不计数；Free=10、Premium unlimited、幂等响应和消费/释放语义不变。

`POST /scan/recognize` 的 Worker 总耗时达到 1 秒时记录 `scan_recognize_timing`，只包含 outcome 及 auth、preflight/quota、R2 image、向量 recognition、目录 catalog、audit、settlement 各阶段毫秒数，不包含 owner、卡牌、图片、token 或上游正文。该日志用于与 Cloudflare `$workers.wallTimeMs >= 1000` 对齐；它不改变响应 JSON、`elapsed`、R2/向量顺序或客户端 25 秒 Deadline。prod 尚未部署本轮代码，其阶段分布仍须独立验证。

2026-09-21 并发 Gallery 额度整改：识别路由不再用领取 reservation 时的旧快照手算最终响应，而使用 settlement 返回的当前账本；同 request ID 重放保持原识别业务结果，同时用该次回读的当前 Quota 替换旧快照。Flutter 在同批 Processing 全部完成并结束最短展示时序后合并执行一次 `GET /scan/quota`，刷新期间阻止新的 Capture/Gallery 误用旧额度，刷新完成后才按权威 `remaining` 递补 Waiting。该收敛不改变 Free 10 次、Matched 扣次、No Match/技术失败释放、Premium unlimited 或 60 秒 lease；服务端已随 `dev@baf0d7b` 由 kd201 watcher 发布并通过运行 bundle、容器健康、migration ledger 与备份回读，真机客户端仍需包含本次 Flutter 修复的新包验收。

## 平台、资源和协议

当前 dev 业务只在 Linux 运行，从必填 `VECTOR_RECOGNITION_BASE_URL` origin 经 HTTP 请求 `/recognize`，发送 `{vector, card_type}`；`card_type` 缺省为 `0`，10 秒超时覆盖正文读取，调用方取消与不跟随重定向由适配器处理。候选补全、额度、审计与图片仍使用本地 PostgreSQL/图片卷，旧 `OCR_SERVICE_BASE_URL` 已退出 dev 运行路径。Linux 缺少必填识别地址时启动失败；共享路由缺 binding 的受控分支返回 503，上游失败或超时返回 502 并释放预占。prod 保持原 Cloudflare 部署，其仓库配置使用 Service Binding，现网协议须单独核验；服务端受控扫描和用户确认的客户端验收分别见[Linux 兼容设计](../02-architecture/linux-test-environment.md#扫描兼容缺口)及[退役记录](../05-delivery/VERIFICATION.md#旧-cloudflare-dev-业务退役2026-09-17)。

用户已明确选择与源分支一致的兼容范围：iOS 16+、Android minSdk 24，Web 扫描暂不支持。iOS 检测使用 `RTMDetInsTinyCardRawFP16.mlmodel` 与系统 Core ML，向量化继续使用 Core ML，透视矫正继续使用 Core Image，不包含 ONNX Runtime 或 ML Kit；Android 使用 `onnxruntime-minimal-1.23.0.aar` 和两份 `.ort` 模型，不包含 ML Kit Latin OCR。模型与运行时资源不因本次缩放对齐发生变化；Dart 检测输出契约、向量协议与服务端链路不变。iOS Core ML 与新检测缩放组合已由用户于 2026-09-11 完成真机验收；2026-09-14 合入本地 `dev` 后，Android Debug 构建及两项缩放参考检查通过，Android 真机识别、耗时与峰值内存仍待验收，详见[验收记录](../05-delivery/VERIFICATION.md)。

旧 `r/g/b` pHash 不再是有效请求；`vector` 必须是 512 项数值数组、至少一个非零分量，JSON 最大 32 KiB。`card_type` 只接受 `0` 或 `1`，缺省按 `0`（TCG）处理，并随向量发送给内部识别服务。候选 `product_id` 继续支持字符串与旧整数形式，confidence 保持 0–100。识别审计算法标识为 `pe-core-t16-384-cosine-v1`。`game_id` 在主 Worker 的目录查询层过滤，不发送给内部向量服务。

当前 prod Wrangler 配置以 `VECTOR_RECOGNITION` Service Binding 指向 `recognize-vec`；dev Linux 使用 HTTP 适配，不存在旧 CF dev 的业务 binding 或发布配置。两条入口均向识别服务发送 `{vector, card_type}`，共享扫描路由的 503/502 与额度释放语义，但 prod 现网协议应以其独立部署版本为准。向量链路本身没有新增数据库 schema 或 migration；旧 CF 共享库与 Linux 独立库的 `0012` 执行状态按各自验证记录判断。

新 App、主 API 与 `recognize-vec` 的协议必须匹配，因为旧 App 的 pHash 请求不兼容新 API。2026-09-09 的 CF dev 向量发布是历史检查点；现在 dev 为 Linux，旧 CF dev 不再发布。2026-09-21 prod version `c612c8a6-4873-4760-b435-3c4db27d14e6` 已回读 `VECTOR_RECOGNITION=recognize-vec@production` 且无旧 OCR 地址。测试包使用向量协议并连接 Linux dev；用户确认的客户端路径与 prod 服务端发布验收分别见[验证记录](../05-delivery/VERIFICATION.md)。

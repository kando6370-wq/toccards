# 扫描识别 pHash 链路

当前实现保留两端 RTMDet-Ins 检测、mask 四角拟合和原生透视矫正，仅将矫正卡面的 PE-Core-T16 向量化替换为 Dart RGB pHash。Queue、Quota、候选资料、Review 与确认入库逻辑保持不变，包括 Scan confirm 初始估值事件的购买价格、币种和可靠历史起点修复。服务端继续兼容旧客户端的可选卡号提示，当前 App 不再生成该提示。

## 识别流程

1. 用户按原流程拍照或选择相册图片。相机将完整照片交给模型检测，不再传递旧 OpenCV 的取景框裁剪参数；取景框按下方布局约束自适应，快门、权限与队列逻辑不变，扫描状态反馈时序见下。
2. 原生层解码并统一方向，生成最长边 640 的 RGB。iOS 与 Android 的检测专用缩放均使用半像素坐标、边界钳制和双线性采样，与参考实现的 OpenCV `INTER_LINEAR` 对齐，但 App 不重新引入 OpenCV。RTMDet-Ins Tiny 使用 BGR/CHW、640×640 输入；置信度阈值 0.35、mask 阈值 0.5。Android 运行含后处理的 `.ort`；iOS Core ML 导出物返回原始分类、边框、动态 mask kernel 与 mask feature，原生层执行 sigmoid、最高分候选选择和 mask 解码，再向 Dart 返回相同的 `dets`/`masks` 契约。
3. Dart 从 mask 的最大连通区域拟合四边形，必要时使用最小面积矩形；过滤面积低于有效图像 2.5% 的结果，再映射四角到原图。
4. iOS Core Image / Android Bitmap Matrix 进行透视矫正，得到 745×1043、质量 85 的 JPEG 和同尺寸 RGB 字节。
5. Dart isolate 将矫正卡面按 Pillow Lanczos 规则等比白底 letterbox 到 1024×1024，逐通道缩至 64×64，计算 16×16 低频 DCT，并以中位数编码为三个 32 字节 pHash；`r/g/b` 均使用 43 字符无填充 Base64URL。
6. App 不再运行 ML Kit Latin OCR，也不从矫正卡面读取或提交卡号提示；它向 `/api/v1/scan/recognize` 提交矫正 JPEG、`r/g/b`、请求 UUID 和原有审计字段。
7. dev Linux API 通过 HTTP `VECTOR_RECOGNITION` 适配边界向 `https://recognize.tcgcard.fun/recognize` 只发送 `{r,g,b,game_id?}`。返回候选继续经过 Linux PostgreSQL 完整目录校验和游戏过滤，然后进入原有额度结算、Review 与确认入库；服务端仍兼容旧客户端的可选 `card_number` 字段，prod 的 Service Binding 配置和运行版本独立。

## 扫描页布局

iOS 与 Android 共用 Flutter 取景框布局。取景框根据视口和安全区，在顶部操作区与底部结果区之间按 280:400 比例缩放，最大为 280×400；与上下内容区各保留至少 16 个逻辑像素的布局间距。底部预留包含扫描计数、总价所在行、结果卡片列表及拍照操作区，从进入扫描页即生效，因此首次识别、连续拍照、结果完成和删除结果均不会让取景框跳动或被卡片遮挡。免费与 Premium 共用同一取景区域；识别遮罩和扫描线始终复用该区域。

扫描结果的最短展示门槛为从完整识别流程开始计时 1 秒，结果出现时刻为 `max(完整识别实际耗时, 1 秒)`。Scanning、Recognizing、Revealing 视觉反馈分别占用前 500、250、250 毫秒，但动画只负责反馈，不参与业务结算；识别超过 1 秒时，结果返回后立即展示，不再额外等待动画。识别接口、RTMDet/pHash、Top 5 候选、失败处理、Quota、Review 与确认入库逻辑不变。

布局调整不改变相机照片输入范围、端侧推理或服务端识别契约。

## 保持的业务契约

- Free 终身 10 次，Premium 不消耗 Free 次数；只有目录资料完整、可用于详情的 Matched 才消费。No Match、详情不完整与技术失败释放预占。
- `card_ref/name/set_name/object_type`、候选资料与图片继续传入现有结果缓存；识别阶段不逐候选加载价格，缺少市场价格不阻止完整卡牌计为成功。
- 预占、25 秒总网络 Deadline、request ID 重试、lease、顺序调度、显示次数与内部容量分离保持当前实现。
- Queue 10 张上限、批量部分成功、删除 Processing 后不重插、Review 草稿和确认后的结果移除不变。
- `/scan/:scan_id/confirm` 保留所有者/Folder 权限、评级区分、Wishlist 移除和 Collection Item 写入；初始估值事件同步记录购买价格、币种与可靠历史起点，避免已填写购买价格的扫描收藏在 Performance 中被判为缺价。
- 不改变订阅、登录、版本控制、Admin、Home、Collection 或其他业务；依赖清理只移除已退出扫描链路的 ML Kit Latin OCR，不新增 OpenCV 或第三方哈希依赖。

## 性能与可观测性

2026-09-20 dev API release `9488a15` 在不改变扫描业务顺序的前提下减少数据库等待：queued reserve 对新 request 使用 insert-first，冲突、重试和额度耗尽仍回读；成功 settlement 先执行受 owner/session/有效 lease 约束的 UPDATE，只有 0 行时才回读 request。Quota 聚合只扫描 `free + reserved/consumed` 账本，过期 reservation 仍按原规则不计数；Free=10、Premium unlimited、幂等响应和消费/释放语义不变。

`POST /scan/recognize` 的 Worker 总耗时达到 1 秒时记录 `scan_recognize_timing`，只包含 outcome 及 auth、preflight/quota、R2 image、recognition、目录 catalog、audit、settlement 各阶段毫秒数，不包含 owner、卡牌、图片、token 或上游正文。该日志用于与 Cloudflare `$workers.wallTimeMs >= 1000` 对齐；它不改变响应 JSON、`elapsed`、R2/识别顺序或客户端 25 秒 Deadline。prod 尚未部署本轮代码，其阶段分布仍须独立验证。

## 平台、资源和协议

当前 dev 业务只在 Linux 运行，从必填 `VECTOR_RECOGNITION_BASE_URL` origin 经 HTTP 请求 `/recognize`，仅发送 `{r,g,b,game_id?}`；10 秒超时覆盖正文读取，调用方取消与不跟随重定向由适配器处理。候选补全、额度、审计与图片仍使用本地 PostgreSQL/图片卷，旧 `OCR_SERVICE_BASE_URL` 已退出 dev 运行路径。Linux 缺少必填识别地址时启动失败；共享路由缺 binding 的受控分支返回 503，上游失败或超时返回 502 并释放预占。prod 保持原 Cloudflare 部署，其仓库配置使用 Service Binding，现网协议须单独核验；当前 pHash 代码尚未部署，服务端受控扫描和客户端验收分别见[Linux 兼容设计](../02-architecture/linux-test-environment.md#扫描兼容缺口)及[验收记录](../05-delivery/VERIFICATION.md)。

兼容范围为 iOS 16+、Android minSdk 24，Web 扫描暂不支持。iOS 检测使用 `RTMDetInsTinyCardRawFP16.mlmodel` 与系统 Core ML，透视矫正使用 Core Image，不包含 ONNX Runtime 或 ML Kit；Android 使用 `onnxruntime-minimal-1.23.0.aar` 和 RTMDet `.ort`，不包含 ML Kit Latin OCR。PE-Core-T16 的 `.mlpackage` 与 `.ort` 仅作为未打包源文件保留在 `assets/models/`，Dart 与双端原生运行时均不再暴露 `runEmbedding`。现有 Android AAR 仍包含原两模型算子集，未在本次重建。检测缩放的历史验收不等同于 pHash 真实图片验收，后者仍需在两端补验准确率、耗时与峰值内存。

`r/g/b` 是当前必填请求字段，每项必须匹配 43 字符无填充 Base64URL；旧 `vector` 请求返回 422。候选 `product_id` 继续支持字符串与旧整数形式，confidence 保持 0–100。识别审计算法标识为 `rgb-phash-16-v1`。可选 `game_id` 发送给识别服务，同时继续在主 API 的 PostgreSQL 目录层过滤。

当前 prod Wrangler 配置仍以 `VECTOR_RECOGNITION` Service Binding 指向 `recognize-vec`；该现网服务是否接受 pHash 协议尚未核验，因此不得仅凭本地代码直接发布 prod。dev Linux 使用 HTTP 适配，不存在旧 CF dev 的业务 binding 或发布配置。两条入口共享扫描路由的 503/502 与额度释放语义；本次没有新增数据库 schema 或 migration，旧 CF 共享库与 Linux 独立库的 `0012` 执行状态按各自验证记录判断。

新 App、主 API 与识别服务的协议必须匹配：旧向量 App 不兼容当前 pHash API，当前 pHash App 也不兼容仍要求 `vector` 的旧 API。2026-09-09 的 CF dev 向量发布仅是历史检查点；现在 dev 为 Linux，旧 CF dev 不再发布。prod 的运行协议与后续切换仍按独立部署记录判断。测试包连接 Linux dev，设备验收以具体记录区分，见[验收记录](../05-delivery/VERIFICATION.md)。

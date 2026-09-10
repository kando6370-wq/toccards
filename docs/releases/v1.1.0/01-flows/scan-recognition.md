# 扫描识别向量链路

本实现从历史提交 `dev-xiangyang@ceef1af` 按识别代码段移植为 `e18543a`，基线为 `7451382`，于 2026-09-09 经 `f38ef98` 合入 `dev` 并推送远程。`dev-wxy`、`dev-xiangyang` 等来源分支已清理，旧分支名只用于追溯，不再作为检出或发布目标。保留 `dev` 当前 Queue、Quota、候选资料与确认入库逻辑，包括 Scan confirm 初始估值事件的购买价格、币种和可靠历史起点修复。

## 识别流程

1. 用户按原流程拍照或选择相册图片。相机将完整照片交给模型检测，不再传递旧 OpenCV 的取景框裁剪参数；取景框按下方布局约束自适应，快门、权限、队列与动画逻辑不变。
2. 原生层解码并统一方向，生成最长边 640 的 RGB。RTMDet-Ins Tiny 使用 BGR/CHW、640×640 输入；置信度阈值 0.35、mask 阈值 0.5。iOS Core ML 导出物返回原始分类 logit，原生后处理先执行 sigmoid，再把 0–1 概率交给统一阈值筛选。
3. Dart 从 mask 的最大连通区域拟合四边形，必要时使用最小面积矩形；过滤面积低于有效图像 2.5% 的结果，再映射四角到原图。
4. iOS Core Image / Android Bitmap Matrix 进行透视矫正，得到 745×1043、质量 85 的 JPEG，以及 384×384 RGB。
5. PE-Core-T16 使用 RGB/CHW、`value / 127.5 - 1` 的输入，生成 512 维有限、非零向量。同一识别器串行推理，图像张量与几何计算使用 Dart isolate。
6. 保留 ML Kit 的可选卡号 OCR，从矫正卡面读取卡号。App 向 `/api/v1/scan/recognize` 提交矫正 JPEG、JSON `vector`、请求 UUID 和原有审计字段。
7. Workers 通过 `VECTOR_RECOGNITION` Service Binding 调用 `recognize-vec`，只发送 `{vector}`。返回候选继续经过当前 PostgreSQL 完整目录校验、游戏过滤及卡号消歧，然后进入原有额度结算、Review 与确认入库。

## 扫描页布局

iOS 与 Android 共用 Flutter 取景框布局。取景框根据视口和安全区，在顶部操作区与底部结果区之间按 280:400 比例缩放，最大为 280×400；与上下内容区各保留至少 16 个逻辑像素的布局间距。底部预留包含扫描计数、总价所在行、结果卡片列表及拍照操作区，从进入扫描页即生效，因此首次识别、连续拍照、结果完成和删除结果均不会让取景框跳动或被卡片遮挡。免费与 Premium 共用同一取景区域；识别遮罩和扫描线始终复用该区域。

布局调整不改变相机照片输入范围、端侧推理或服务端识别契约。

## 保持的业务契约

- Free 终身 10 次，Premium 不消耗 Free 次数；只有目录资料完整、可用于详情的 Matched 才消费。No Match、详情不完整与技术失败释放预占。
- `card_ref/name/set_name/object_type`、候选资料与图片继续传入现有结果缓存；识别阶段不逐候选加载价格，缺少市场价格不阻止完整卡牌计为成功。
- 预占、15 秒总网络 deadline、request ID 重试、lease、顺序调度、显示次数与内部容量分离保持当前实现。
- Queue 10 张上限、批量部分成功、删除 Processing 后不重插、Review 草稿和确认后的结果移除不变。
- `/scan/:scan_id/confirm` 保留所有者/Folder 权限、评级区分、Wishlist 移除和 Collection Item 写入；初始估值事件同步记录购买价格、币种与可靠历史起点，避免已填写购买价格的扫描收藏在 Performance 中被判为缺价。
- 不改变订阅、登录、版本控制、Admin、Home、Collection 或其他业务。相关依赖删除只清理 OpenCV 及其不再引用的传递依赖。

## 平台、资源和协议

用户已明确选择与源分支一致的兼容范围：iOS 16+、Android minSdk 24，Web 扫描暂不支持。iOS 使用系统 Core ML/Core Image；Android 使用 `onnxruntime-minimal-1.23.0.aar` 和两份 `.ort` 模型。模型、运行时、许可证和转换工具从源提交引入，不重新训练或重新导出模型。模型端到端准确率、耗时与内存仍需设备验收。

旧 `r/g/b` pHash 不再是有效请求；`vector` 必须是 512 项数值数组、至少一个非零分量，JSON 最大 32 KiB。候选 `product_id` 继续支持字符串与旧整数形式，confidence 保持 0–100。识别审计算法标识为 `pe-core-t16-384-cosine-v1`。`game_id` 在主 Worker 的目录查询层过滤，不发送给内部向量服务。

仓库中的 dev/prod 配置均以 `VECTOR_RECOGNITION` 绑定 `recognize-vec`，移除 `OCR_SERVICE_BASE_URL`，不设置旧协议或公网回退。缺少 binding 返回 `503 VECTOR_RECOGNITION_UNAVAILABLE`；上游失败返回 `502`，按既有规则释放额度。向量链路本身没有新增数据库 schema 或 migration；合并保留的 `0012` 属于独立历史事件回填，仍未执行。

上线必须协调新 App、主 API 与 `recognize-vec`，因为旧 App 的 pHash 请求不兼容新 API。2026-09-09 合并后的主 API/Admin 已发布到 dev，当日后续回读仍确认 dev 使用 `VECTOR_RECOGNITION`；prod 实际运行版本仍配置旧 `OCR_SERVICE_BASE_URL`，尚未切换向量协议。测试需使用包含模型与向量请求、连接 dev API 的 App 包。Android Debug 构建通过不代表两端真机模型验收或新 App 签名包已发布，具体证据见[验收记录](../05-delivery/VERIFICATION.md)。

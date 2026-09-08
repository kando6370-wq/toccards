# 扫描识别向量链路（dev-wxy）

本实现从 `dev-xiangyang@ceef1af` 按识别代码段移植到 `dev-wxy`，基线为 `7451382`。不合并源分支的扫描业务版本；以 dev-wxy 当前 Queue、Quota、候选资料与确认入库逻辑为准。

## 识别流程

1. 用户按原流程拍照或选择相册图片。相机将完整照片交给模型检测，不再传递旧 OpenCV 的取景框裁剪参数；取景框 UI、快门、权限、队列与动画不变。
2. 原生层解码并统一方向，生成最长边 640 的 RGB。RTMDet-Ins Tiny 使用 BGR/CHW、640×640 输入；置信度阈值 0.35、mask 阈值 0.5。
3. Dart 从 mask 的最大连通区域拟合四边形，必要时使用最小面积矩形；过滤面积低于有效图像 2.5% 的结果，再映射四角到原图。
4. iOS Core Image / Android Bitmap Matrix 进行透视矫正，得到 745×1043、质量 85 的 JPEG，以及 384×384 RGB。
5. PE-Core-T16 使用 RGB/CHW、`value / 127.5 - 1` 的输入，生成 512 维有限、非零向量。同一识别器串行推理，图像张量与几何计算使用 Dart isolate。
6. 保留 ML Kit 的可选卡号 OCR，从矫正卡面读取卡号。App 向 `/api/v1/scan/recognize` 提交矫正 JPEG、JSON `vector`、请求 UUID 和原有审计字段。
7. Workers 通过 `VECTOR_RECOGNITION` Service Binding 调用 `recognize-vec`，只发送 `{vector}`。返回候选继续经过当前 PostgreSQL 完整目录校验、游戏过滤及卡号消歧，然后进入原有额度结算、Review 与确认入库。

## 保持的业务契约

- Free 终身 10 次，Premium 不消耗 Free 次数；只有目录资料完整、可用于详情的 Matched 才消费。No Match、详情不完整与技术失败释放预占。
- `card_ref/name/set_name/object_type`、候选资料与图片继续传入现有结果缓存；识别阶段不逐候选加载价格，缺少市场价格不阻止完整卡牌计为成功。
- 预占、15 秒总网络 deadline、request ID 重试、lease、顺序调度、显示次数与内部容量分离保持当前实现。
- Queue 10 张上限、批量部分成功、删除 Processing 后不重插、Review 草稿和确认后的结果移除不变。
- `/scan/:scan_id/confirm`、所有者/Folder 权限、评级区分、Wishlist 移除、Collection Item 及估值事件写入不变。
- 不改变订阅、登录、版本控制、Admin、Home、Collection 或其他业务。相关依赖删除只清理 OpenCV 及其不再引用的传递依赖。

## 平台、资源和协议

用户已明确选择与源分支一致的兼容范围：iOS 16+、Android minSdk 24，Web 扫描暂不支持。iOS 使用系统 Core ML/Core Image；Android 使用 `onnxruntime-minimal-1.23.0.aar` 和两份 `.ort` 模型。模型、运行时、许可证和转换工具从源提交引入，不重新训练或重新导出模型。模型端到端准确率、耗时与内存仍需设备验收。

旧 `r/g/b` pHash 不再是有效请求；`vector` 必须是 512 项数值数组、至少一个非零分量，JSON 最大 32 KiB。候选 `product_id` 继续支持字符串与旧整数形式，confidence 保持 0–100。识别审计算法标识为 `pe-core-t16-384-cosine-v1`。`game_id` 在主 Worker 的目录查询层过滤，不发送给内部向量服务。

dev/prod 配置均以 `VECTOR_RECOGNITION` 绑定 `recognize-vec`，移除 `OCR_SERVICE_BASE_URL`，不设置旧协议或公网回退。缺少 binding 返回 `503 VECTOR_RECOGNITION_UNAVAILABLE`；上游失败返回 `502`，按既有规则释放额度。没有新增数据库 schema、migration、数据回填或远程写入。

上线必须协调新 App、主 API 与 `recognize-vec`，因为旧 App 的 pHash 请求不兼容新 API。`dev-wxy@e18543a` 的主 API 与管理后台已于 2026-09-08 发布到共用 dev 环境，`VECTOR_RECOGNITION` 已绑定在线 `recognize-vec`；测试需使用包含模型与向量请求的新 App 包。发布与真机验证结果见[验收记录](../05-delivery/VERIFICATION.md)。

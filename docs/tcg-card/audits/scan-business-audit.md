# Scan 业务审计

## 0. 文档说明

- 分析范围：Flutter Scan 拍摄、相册导入、识别结果、单张/多张 Review，Workers 识别、确认、R2 审计与资产联动。
- 设计真源：Figma `DjacfTioobtRy59SnqH7SY`，拍摄前 `328:10858`、单张 Review `324:9779`、多张 Review `131:19961`、退出确认 `131:20868`。
- 产品口径：`TCG_PRD_整合版.md` 第 7 章及全局资产刷新规则。
- 结论等级：`代码明确体现` 表示存在可执行代码或测试；`生产已验证` 表示真实 Cloudflare 接口、D1 或 R2 已回读；`待确认` 表示 Figma、PRD 与当前实现不一致。
- 本文不采信进度文档中的完成标记，也不把测试卡价写入生产数据。

## 1. 业务总览与业务主线

Scan 把实体卡牌图像转换为可审计的识别记录。识别成功本身不会产生资产；只有用户在 Review 中选择候选卡、填写 Collection Item 并确认后，Workers 才创建资产、移除同卡 Wishlist、写入估值事件并确认扫描记录。

完整闭环：游客或登录用户进入 Scan -> 相机拍摄或最多导入 10 张图片 -> 本地 OpenCV 校正并生成 RGB pHash -> `POST /scan/recognize` 上传校正图和哈希 -> Workers 把图片存入私有 R2，只把哈希发给识别服务 -> 用 D1 卡牌目录解析候选并写 `scan_record` -> Matched 项进入 Review -> 用户选择文件夹和收藏字段 -> `POST /scan/:scan_id/confirm` -> 原子创建 `collection_item`、`collection_item_event`，删除同卡 Wishlist 并确认扫描 -> 刷新 HOME 与 Collection。

| 模块 | 业务职责 | 真实接口/资源 | 结论 |
|---|---|---|---|
| 拍摄与导入 | 取得单卡图片、支持相册批量导入 | iOS camera / image picker | 代码明确体现 |
| 本地预处理 | 透视校正、RGB 通道 pHash、稳定帧判断 | dartcv / native image hasher | 代码明确体现 |
| 识别 | 持久化审计图片并解析真实目录候选 | `POST /scan/recognize`、OCR service、D1、R2 | 生产已验证 |
| Review | 候选确认、文件夹与 Collection Item 编辑 | Cards、prices、folders API | 代码明确体现 |
| 资产确认 | 创建持有记录、估值事件并移除 Wishlist | `POST /scan/:scan_id/confirm` | 生产已验证 |
| 管理审计 | 查询、筛选、分页和鉴权读取扫描图片 | Admin Scan API、私有 R2 | 代码明确体现 |

## 2. 用户角色与权限体系

| 身份 | 页面能力 | 数据范围 | 服务端边界 | 结论 |
|---|---|---|---|---|
| 游客 | 拍摄、识别、Review、加入 Portfolio | `owner_type=anonymous` 与当前 `owner_id` | Bearer Token + owner 过滤 | 代码明确体现 |
| 登录用户 | 与游客相同，资产归属账号 | `owner_type=user` 与当前 `owner_id` | Bearer Token + owner 过滤 | 代码明确体现 |
| 未认证请求 | 无法识别或确认 | 不可读写任何 owner 数据 | 返回 401 | 代码明确体现 |
| Admin | 查看审计元数据与鉴权图片 | 管理员接口授权范围 | Admin 鉴权，不暴露 R2 公网地址 | 代码明确体现 |

游客升级新账号时迁移 `scan_record` 和资产事件 owner；登录已有账号时不迁移游客资产。账号删除按当前产品决定保留 Scan 审计记录和 R2 图片，但删除匿名资产、文件夹和估值事件。该例外必须继续体现在 App Privacy 与审核说明中。

## 3. 核心业务流程

### 3.1 识别流程

| 步骤 | 输入 | 处理逻辑 | 输出/状态 | 证据 |
|---|---|---|---|---|
| 取得图片 | 相机或相册 | 相册最多 10 张；每张独立进入列表 | `scanning` | `ScanPage`、`ScanCameraSession` |
| 本地校正 | 原图/相机帧 | 检测卡牌四角、透视校正到 745x1043、RGB/letterbox 后计算 pHash | 校正图 + r/g/b | `scan_image_hasher_native.dart` |
| 稳定帧 | 每隔一帧的检测结果 | 8 个稳定检测触发一次自动识别 | recognition in flight | `ScanStabilityGate`、`_onCameraFrame()` |
| Workers 识别 | multipart 图片与 3 个 pHash | 先存 R2，再向外部服务发送纯 JSON 哈希 | `success` / `no_match` / `failed` | `createScanRoutes()` |
| 目录解析 | `product_id` 候选 | 只把 D1 中可解析的卡牌返回给客户端 | Matched candidates | `toCatalogCandidate()` |
| 审计写入 | owner、设备、候选、上游响应 | 写 `scan_record`；D1 写入失败会补偿删除 R2 图片 | `pending` | `INSERT_SCAN_RECORD_SQL` |

### 3.2 Review 与确认

| 步骤 | 前置条件 | 动作 | 后置结果 | 证据 |
|---|---|---|---|---|
| 进入 Review | 至少一项 Matched，且无 Scanning | 加载 folders、卡牌详情和市场价 | 每张卡独立 draft | `_openReview()`、`ApiScanReviewRepository` |
| 切换候选 | 候选已被 D1 解析 | 更新 Our Match、Language、Finish | 当前卡 draft 同步 | `_selectReviewCandidate()` |
| Add this card | 当前 draft 校验通过 | 调用确认接口 | 成功项移出待处理列表 | `_addSelectedReviewItem()` |
| Add all cards | 所有 Matched draft 可校验 | 逐项确认，记录成功与失败 | 部分成功保留失败项 | `_addAllReviewItems()` |
| Workers 确认 | scan 为 pending、候选有效、folder 属于 owner | D1 batch 写资产、事件、Wishlist 删除和 scan 确认 | 201 + 真实 item id | `/scan/:scan_id/confirm` |
| 页面联动 | 至少一个确认成功 | invalidate HOME 与 Collection | 重新读取真实资产 | `_refreshPortfolioSurfaces()` |

### 3.3 状态流转与异常

| 当前状态 | 可流转到 | 触发动作 | 业务结果 |
|---|---|---|---|
| `scanning/recognizing/revealing` | `matched` / `noMatch` / `failed` | 本地处理和识别返回 | 只产生扫描记录，不产生资产 |
| `matched` | Review / `added` / 删除 | Done、点击扫描项、确认或删除 | 只有确认成功才创建资产 |
| `noMatch` | Search 或删除 | Search Manually / Delete | 不进入 Review，不创建资产 |
| `failed` | 重试或删除 | Retry / Delete | 重试复用原图 |
| `scan_record.pending` | `confirmed` | 合法确认请求 | 绑定 Collection Item |
| `scan_record.confirmed` | 无 | 重复确认 | 409，防止重复资产 |

局部价格失败显示 `--`，仍允许保存无价资产；识别服务异常返回显式错误并保留审计 `scan_id`；Review 批量添加部分失败时成功项已落库并移除，失败项保留并显示统一 Toast。

## 4. 核心数据实体

| 实体 | 关键字段 | 生命周期与关系 | 证据 |
|---|---|---|---|
| `scan_record` | owner、image_url、recognition_status、confirmation_status、candidates、raw_response | 每次 Workers 识别创建；确认后关联用户结果 | D1 schema、`routes.ts` |
| R2 scan image | `scans/{owner_type}/{owner_id}/{yyyy}/{mm}/{scan_id}.jpg` | 识别前上传；D1 失败时删除；成功后永久审计保留 | `scanImageKey()`、`SCAN_IMAGES` |
| `collection_item` | folder、card_ref、grader/condition/grade、language、finish、quantity、purchase | 用户确认后创建 | `INSERT_CONFIRMED_COLLECTION_ITEM_SQL` |
| `collection_item_event` | item、owner、folder、定价状态、quantity、effective_at | 与 Scan 资产同批创建 `upsert` 事件 | `INSERT_CONFIRMED_COLLECTION_ITEM_EVENT_SQL` |
| `wishlist_item` | owner、card_ref | Scan 确认同卡后删除 | `DELETE_CONFIRMED_WISHLIST_CARD_SQL` |
| `portfolio_folder` | owner、id、default | Review 的 Adding to 目标；确认时再次校验 owner | `SELECT_PORTFOLIO_FOLDER_SQL` |

## 5. 业务规则与计算公式

| 规则 | 当前实现 | 结论 |
|---|---|---|
| pHash 合约 | r/g/b 均为 43 字符 Base64URL；不合规返回 422 | 代码明确体现 |
| 外部服务隐私边界 | 外部 OCR 只接收 pHash 与可选 `game_id`，不接收图片 | 代码明确体现 |
| 图片审计 | Workers 接收并验证校正图，存入私有 R2 | 代码明确体现 |
| Collection Item 校验 | Quantity >= 1；Purchase Price >= 0；Notes <= 500；Graded 必须有 Grade | 代码明确体现 |
| 唯一确认 | 只有 owner 自己的 pending scan 且所选卡在 candidates 内才可确认 | 代码明确体现 |
| Wishlist 排他 | 成功加入 Portfolio 后删除同 owner 同 card_ref 的 Wishlist | 代码明确体现 |
| 估值联动 | `current value = market price x quantity`；确认时写事件，HOME 历史从事件回放 | 生产已验证 |
| 无价资产 | 可以保存，但不计入 HOME 当前值、Most Valuable 和对应曲线价值 | PRD 与 Workers 一致 |

## 6. 影响面与上下游依赖

| 系统/模块 | 方向 | 交互 | 失败影响 |
|---|---|---|---|
| iOS Camera / Photos | 上游 | 拍摄、相册和权限 | 无图像则无法启动识别 |
| dartcv / pHash | 上游 | 本地裁切与哈希 | 合约不一致会导致真实卡全部误识别 |
| `recognize.tcgcard.fun` | 上游 | RGB pHash 候选 | 识别进入 failed，不创建资产 |
| Cloudflare R2 | 上游/审计 | 私有扫描图 | 上传失败时识别请求失败 |
| D1 Cards / Prices | 上游 | 候选解析和 Review 价格 | 未入目录候选不返回；无价仍可保存 |
| Collection / HOME | 下游 | 资产和估值事件 | 确认后应立即重读真实接口 |
| Wishlist | 下游 | 同卡互斥删除 | Scan 加入 Portfolio 后不可并存 |
| Admin | 下游 | 扫描审计和图片查看 | 不影响用户确认，但影响运营审计 |
| Auth 生命周期 | 横向 | owner 迁移、退出与删除 | 事件 owner 必须与资产同步迁移 |

## 7. 行业术语

| 术语 | 含义 |
|---|---|
| pHash | 对图像视觉内容生成的感知哈希；本项目按 RGB 三通道向量匹配 |
| Perspective Warp | 将倾斜拍摄的卡牌四角校正为固定矩形 |
| Candidate | 识别服务返回并由 D1 目录确认存在的候选卡牌 |
| Matched | 至少一个候选成功映射到真实目录，不等于已加入 Portfolio |
| Review | 用户确认候选并填写持有状态的业务步骤 |
| Scan Audit | 保存图片、设备、候选和上游响应的运营审计记录 |

## 8. 证据索引

| 编号 | 文件/位置 | 说明 |
|---|---|---|
| E1 | `apps/flutter-app/lib/features/scan/scan_page.dart` | Figma 页面、状态流转、单张/批量 Review 与页面刷新 |
| E2 | `apps/flutter-app/lib/features/scan/scan_result_source.dart` | 真实识别调用和结果状态 |
| E3 | `apps/flutter-app/lib/shared/scan/scan_api_client.dart` | `/scan/recognize` 与 confirm 合约 |
| E4 | `apps/flutter-app/lib/shared/scan/scan_image_hasher_native.dart` | OpenCV 校正与 pHash |
| E5 | `apps/workers-api/src/scan/routes.ts` | 识别、R2、D1 审计、确认与估值事件 |
| E6 | `apps/workers-api/src/scan/routes.test.ts` | owner 隔离、补偿、候选确认和资产事件测试 |
| E7 | `apps/workers-api/src/auth/guest-migration.ts` | Scan 与估值事件 owner 迁移 |
| E8 | `TCG_PRD_整合版.md:1595` | Scan 业务规则 |
| E9 | Figma `328:10858`、`324:9779`、`131:19961`、`131:20868` | 拍摄、单张/多张 Review、退出确认视觉真源 |

## 9. 待确认问题与显式冲突

| 优先级 | 问题 | 当前代码事实 | 决定 |
|---|---|---|---|
| P1 | Figma/PRD 以用户点击拍摄为主线；当前实现额外支持 8 个稳定帧后自动触发 | 自动识别与手动拍摄并存 | 按用户要求保留 Scan 会话实现；上架前需产品明确是否接受自动触发 |
| P1 | No Match 的 Search 生命周期不一致 | 点击 Search Manually 时立即从内存删除扫描项；PRD 要求 Search 成功添加后再删除 | 当前不阻塞资产正确性，但取消 Search 后无法恢复原扫描项，待单独整改 |
| P1 | 本机 OpenCV 原生等价测试被跳过 | 缺 `DARTCV_LIB_PATH`，纯 Dart pHash、API 和状态测试通过 | 必须在 iOS CI/真机继续验证相机裁切与识别命中 |
| P1 | Graded 与大部分 Raw 价格缺失 | 无价卡可保存但不计入估值 | 不插测试价格；继续作为 iOS NO-GO 数据阻断 |
| P2 | R2 图片永久保留且账号删除后仍保留 | 与普通资产删除生命周期不同 | 保持既定产品决定，并在 App Privacy/审核材料中显式披露 |

## 10. 生产与回归证据

| 验证项 | 结果 | 证据 |
|---|---|---|
| 真实 Scan 确认 | 临时账号确认真实卡 `9359`、Quantity 2，返回真实 Collection Item | 2026-07-17 生产 smoke |
| Collection 联动 | 确认后市场单价为 `0.21` | 生产 Collection API |
| HOME 联动 | 返回 91 个估值点；当前值与末点均为 `0.42`，Most Valuable 为 `9359` | 生产 valuation API |
| D1 事件 | 对应 Item 存在 `upsert` 事件 | 生产 D1 回读 |
| 清理 | 临时账号删除后 items/events/folders 均为 0；合成 scan 记录额外清理 | 生产 D1 回读 |
| Workers | 28 个测试文件、249 项通过；TypeScript 与 dry-run 通过 | 2026-07-17 本地验证 |
| Flutter | 237 项通过、1 项因缺原生 dartcv 库明确跳过；analyze 无问题 | 2026-07-17 本地验证 |
| 代码提交 | Scan 栈、估值事件、身份迁移和卡图均已分段提交 | `41afaea`、`48e3d42`、`0ef9ec9`、`33b8bc9`、`5aa0772`、`6fc05da`、`f3e4b2e` |
| Cloudflare | 当前生产 Worker 版本 `8a482fcb-3e0f-4278-9fb3-f302a1545948` | `wrangler deployments list` |

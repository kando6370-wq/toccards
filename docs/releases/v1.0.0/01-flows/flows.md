# v1.0.0 业务流程

## 1. 启动与身份建立

1. App 启动并读取本地凭证与应用配置。
2. 无有效身份时调用 `POST /api/v1/auth/anonymous` 创建匿名账号和会话。
3. 已有账号可通过邮箱、Google 或 Apple 登录；Access Token 失效时使用 Refresh Token 续签。
4. 匿名用户完成注册或 OAuth 绑定后，调用资产迁移把收藏、愿望单、偏好和扫描记录归到正式用户 UID。
5. 登出撤销当前会话；删除账号进入服务端删除流程。

异常处理：无效/过期令牌返回鉴权错误；刷新失败后客户端清理会话并重新建立身份；重复邮箱、验证码错误或过期由认证路由拒绝。

## 2. 搜索到收藏

1. 用户按游戏进入 Cards 或 Sets 搜索。
2. Cards 直接查询卡牌；Sets 使用唯一 `set_id` 加载该系列卡牌。
3. 用户进入卡牌详情，加载图片、市场价格、价格历史和成交记录。
4. 用户将卡牌加入愿望单，或选择数量、Raw/评级状态、品相、评级机构/分数、语言、工艺和文件夹后加入收藏。
5. 收藏写入后更新首页汇总、收藏列表和估值历史；后续可编辑、移动或删除条目。

数据范围：愿望单、收藏、文件夹和偏好查询均由 Workers 按当前令牌中的 `owner_type + owner_id` 过滤。

## 3. 扫描识别到入库

1. 用户从相机拍摄或相册选择图片。
2. Flutter 计算 RGB pHash，并连同图片、可选游戏和卡号提交 `POST /api/v1/scan/recognize`。
3. Workers 校验图片与参数，可将原图保存到 R2，再调用 OCR 识别服务。
4. 服务返回识别状态和候选卡牌；App 进入 Review，用户选择最终卡牌。
5. App 调用 `POST /api/v1/scan/:scan_id/confirm`，提交收藏条目草稿。
6. Workers 保存用户确认结果、创建收藏条目与事件，并移除同卡愿望单。

异常处理：图片或参数不合法时不创建有效识别；OCR 无匹配与调用失败分别记录 `no_match`、`failed`；没有成功候选时不能以成功结果完成 Review。

## 4. 收藏估值

1. Workers 读取当前所有者的收藏条目。
2. 按 `card_ref` 获取价格数据，并使用卡牌状态、品相、评级机构/分数、语言等属性匹配价格。
3. 单项价值 = 匹配到的最新市场价 × `quantity`。
4. 汇总值和历史值按两位小数输出；无匹配价格的条目不生成有效估值。
5. `/collection/dashboard` 返回首页汇总，`/portfolio/valuation-history` 返回历史序列。

## 5. 反馈处理

1. App 提交 `POST /api/v1/feedback` 创建反馈工单。
2. Admin 查看列表和详情，按实际处理结果更新状态。
3. 新提交工单初始写为 `open`，Admin 映射为 `pending`；运营可更新为 `processed` 或 `ignored`。旧值 `in_progress`、`closed` 读取时分别归并为 `pending`、`processed`。

## 6. Admin 运营

1. 管理员独立登录并取得 Admin Token。
2. `operator` 与 `super_admin` 均可进入当前后台菜单并处理日常数据。
3. 后端只允许 `super_admin` 禁用用户、创建/修改管理员权限，以及删除 Trending Pin 或 Card Override。
4. 应用版本与升级配置由 Admin API 写入 `app_config`，App 通过公共 `/app-config` 读取。

证据：`apps/flutter-app/lib/features/`、`apps/workers-api/src/auth/`、`portfolio/routes.ts`、`scan/routes.ts`、`feedback/routes.ts`、`admin/routes.ts`。

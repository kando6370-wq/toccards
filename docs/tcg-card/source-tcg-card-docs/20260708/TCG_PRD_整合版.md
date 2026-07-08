# TCG 卡牌收藏 App PRD 整合版

> 版本：1.0 整合稿  
> 范围：Home、Search、Scan、Collection、Card Detail、Collection Item、Profile、Auth、全局异常、资产统计规则。  
> 首版不包含订阅 / PRO / Restore 相关能力。

---

## 0. 本次整合后的关键口径

1. 游客状态可以使用 App 内主要功能，并可产生资产。
2. 游客资产绑定 `anonymous_account`，服务端保存。
3. 游客注册新账号后，`anonymous_account` 资产迁移到新账号。
4. 游客登录已有账号时，游客资产不迁移，登录后展示已有账号资产；退出登录后如 `anonymous_account` 仍有效，恢复展示游客资产。
5. Wishlist 和 Portfolio 不可同时存在同一张卡。Portfolio 优先级高于 Wishlist；卡牌成功加入 Portfolio 后，如该卡已在 Wishlist 中，则自动从 Wishlist 移除。
6. Search 列表里的快捷 `Collect` 按钮直接加入当前选中文件夹，不调起 Collection Item 弹窗。
7. 从 Trending Today、Search 详情页、Wishlist 详情页、未收藏卡牌详情页点击 Add to Portfolio 时，调起独立 Collection Item 弹窗。
8. 扫描流程新增 Collection Item 时，不展示 Portfolio 字段，以当前卡牌的 `Adding to` 为准。
9. 扫描外 Collection Item 弹窗不展示 Portfolio 字段，以 `Adding to` 为准。
10. 已收藏后的 Collection Item 编辑页可以展示 Portfolio 字段，用于移动当前资产到其他文件夹。
11. Grader 选项统一为：Raw、PSA、BGS、SGC、CGC、TAG、AGS。
12. Condition 统一使用 `Near Mint (NM)`，不使用 `Near Mint (NM)`。
13. 1.0 不支持离线保存资产变更。无网络时，资产变更不提交，保留用户已填写内容，并展示网络异常 Toast。
14. 通用失败 Toast 统一为：`Something went wrong. Please try again.`
15. 注册 / 登录方式弹窗底部展示协议文案：`By continuing, you agree to our Terms of Use and Privacy Policy.`，其中 Terms of Use 和 Privacy Policy 可点击，并使用系统浏览器跳转官网。
16. Restore 首版不保留。
17. 删除 Collection Item 后，从删除时间点开始不再计入当前资产和后续图表；删除前历史资产记录保留，不回写历史。
18. Search 默认排序以接口返回默认排序为准，不写死本地入库时间倒序。
19. Home Most Valuable 中体育卡、套盒、特殊收藏品字段与 Search / Detail 基础信息保持一致，只保留必要字段。

---

# 一、全局规则

## 1.1 全局加载、失败、空状态

### 局部数据加载失败

App 内任一页面中，如果只是某个模块或区域数据加载失败，不使用整页弹窗，只在该模块原本的数据区域展示局部失败状态。

展示：

```text
No content available
Refresh
```

规则：

1. 展示在失败模块原本的数据区域内。
2. 不遮挡其他已加载内容。
3. 点击 Refresh 只重新加载该模块数据。
4. 刷新中展示统一 loading。
5. 刷新成功后恢复模块内容。
6. 刷新失败后继续展示 `No content available` 和 `Refresh`。

适用场景：

1. Home 图表加载失败。
2. Home Most Valuable 加载失败。
3. Home Trending Today 加载失败。
4. Price 图表加载失败。
5. Market Prices 加载失败。
6. Shop 列表加载失败。
7. Search Cards / Sets 列表加载失败。
8. Collection Portfolio / Wishlist 局部数据加载失败。
9. Review Your Matches 中单个价格 / Total 加载失败。

### 整页数据加载失败

如果页面核心数据全部加载失败，展示整页失败状态。

展示：

```text
No content available
Refresh
```

规则：

1. 当页面所有核心数据都加载失败时展示。
2. 点击 Refresh 重新加载整页数据。
3. 刷新成功后关闭失败状态并展示页面内容。
4. 刷新失败后保留失败状态。
5. 用户可通过返回按钮离开页面。

适用场景：

1. 卡牌详情基础信息整体加载失败。
2. Collection 页面核心列表整体加载失败。
3. Search 页面初始化数据整体加载失败。
4. Profile 账号信息和基础入口整体加载失败。
5. Scan Details / Review 整体加载失败。

### 空状态与失败状态区分

1. 空状态表示请求成功但无数据。
2. 失败状态表示请求失败或内容不可用。
3. 无资产、无搜索结果不应使用错误 Toast。

---

## 1.2 全局 Loading

所有需要加载的场景使用同一套 loading 组件。

规则：

1. 首屏加载使用页面级 loading。
2. 模块刷新使用局部 loading。
3. 按钮提交使用按钮内 loading。
4. 列表分页使用列表底部 loading。
5. Loading 超过 10 秒仍无结果时，进入失败状态。
6. Loading 不应遮挡底部导航，除非是全屏流程页。

适用场景：页面初始化、列表加载、搜索请求、筛选 / 排序刷新、图表刷新、价格数据刷新、扫描识别中、添加到 Portfolio、加入 / 移除 Wishlist、保存 Collection Item、提交客服反馈等。

---

## 1.3 全局 Toast

### 通用操作失败 Toast

```text
Something went wrong. Please try again.
```

规则：

1. Toast 不需要按钮。
2. Toast 自动显示 2–3 秒后消失。
3. Toast 不阻塞用户操作。
4. Toast 不使用遮罩。
5. Toast 固定展示在底部导航上方，不遮挡底部导航。
6. 操作失败后恢复操作前状态。
7. 表单保存 / 添加 / 提交失败后，停留当前页面并保留用户输入内容。
8. 删除、移除等高风险操作失败时，不改变数据状态。

### 网络异常 Toast

```text
No internet connection. Please check your network and try again.
```

规则：

1. 无网络时展示该 Toast。
2. 不清空页面已加载数据。
3. 当前操作失败并恢复操作前状态。
4. 用户恢复网络后，可点击 Refresh 或重新操作。

---

## 1.4 全局金额与百分比规则

1. App 默认货币为 USD。
2. 切换货币需调用汇率接口。
3. 所有金额字段跟随当前货币换算。
4. 百分比字段不随货币切换变化。
5. 金额默认保留 2 位小数。
6. 金额缺失展示 `--`。
7. 涨跌幅缺失展示 `-/-`。
8. 正向变化展示 `+`。
9. 负向变化展示 `-`。
10. 用户隐藏资产金额后，Home 与 Collection 中资产金额同步隐藏。

---

## 1.5 全局确认弹窗规则

以下操作必须二次确认：

1. 删除账号。
2. 删除 Portfolio 文件夹。
3. Remove from Portfolio。
4. Remove from Wishlist。
5. 退出扫描且存在未保存扫描结果。

规则：

1. 二次确认弹窗必须包含取消按钮。
2. 取消后不改变数据。
3. 确认失败后不改变数据，并展示对应失败提示。
4. 删除类按钮使用明确动词，例如 Delete、Remove、Exit。

---

## 1.6 全局防重复点击

所有会产生数据变化的按钮，请求中不可重复点击。

适用按钮：

1. Collect / Collected。
2. Wishlist 爱心。
3. Add this card / Add all cards。
4. Save / Save changes。
5. Delete / Remove。
6. Submit Feedback。
7. Refresh。

规则：

1. 请求中按钮展示 loading 或置灰。
2. 请求成功后更新状态。
3. 请求失败后恢复原按钮状态。

---

## 1.7 离线状态规则

1.0 不支持离线保存资产变更。

无网络时，以下资产变更操作均不提交：

1. 新增 Collection Item。
2. 编辑 Collection Item。
3. 删除 Collection Item。
4. 移动 Portfolio。
5. 加入 / 移除 Wishlist。
6. 新建 / 编辑 / 删除 Portfolio 文件夹。
7. 游客资产迁移。
8. 删除账号。
9. 退出登录。

规则：

1. 用户可以继续查看已加载或已缓存数据。
2. 用户在编辑页填写的内容不立即清空。
3. 用户点击 Save / Add / Remove / Delete 等资产变更按钮时，如果无网络，不提交请求。
4. 数据状态保持不变。
5. 页面保留用户已填写内容，方便网络恢复后重新提交。
6. 展示网络异常 Toast：`No internet connection. Please check your network and try again.`

---

# 二、账号、游客资产与注册登录

## 2.1 游客资产规则

App 支持游客状态使用。用户未注册 / 未登录时，也可以在 App 内进行主要功能操作，并产生游客资产。

游客资产包括：

1. Portfolio 文件夹。
2. Collection Item。
3. Wishlist。
4. 扫描添加记录。
5. Search 快捷收藏记录。
6. 货币偏好。
7. 金额隐藏偏好。
8. 文件夹排序和默认文件夹设置。

游客资产绑定 `anonymous_account`，并在服务端保存。客户端可缓存游客资产，但服务端 `anonymous_account` 是游客资产主数据来源。

规则：

1. 游客可正常浏览 Home、使用 Search、使用 Scan。
2. 游客可添加卡牌到 Portfolio。
3. 游客可添加卡牌到 Wishlist。
4. 游客可新建 / 编辑 / 删除 Portfolio 文件夹。
5. 游客可编辑 Collection Item。
6. 游客可切换货币、隐藏 / 显示金额。
7. 游客资产不与正式账号资产混算。

---

## 2.2 游客注册新账号

场景：用户处于游客状态，并且已经产生游客资产，此时选择注册新账号并注册成功。

规则：

1. 注册成功后，系统将当前 `anonymous_account` 资产迁移到新注册账号。
2. 迁移范围包括 Portfolio、Collection Item、Wishlist、扫描添加记录、文件夹排序、默认文件夹、货币偏好、金额隐藏偏好等。
3. 迁移成功后，用户进入登录态。
4. 后续新增 / 编辑 / 删除资产均归属该账号。
5. Home、Collection、Wishlist、Search Qty、Card Detail 收藏状态、Profile 账号状态需要刷新。
6. 原游客资产不再作为独立游客资产重复展示。
7. 迁移失败时，不删除 `anonymous_account` 资产，不展示空资产误导用户。

迁移失败 Toast：

```text
Something went wrong. Please try again.
```

---

## 2.3 游客登录已有账号

场景：用户处于游客状态，并且已经产生游客资产，此时选择登录已有账号。

规则：

1. 登录已有账号时，不自动迁移游客资产。
2. 登录成功后，App 展示该已有账号资产数据。
3. 游客资产仍保留在原 `anonymous_account` 下。
4. 游客资产不覆盖账号资产。
5. 账号资产不合并游客资产。
6. 后续新增 / 编辑 / 删除资产均归属当前登录账号。
7. 用户退出登录后，如果 `anonymous_account` 仍有效，恢复展示游客资产。

---

## 2.4 注册 / 登录入口

入口：

1. Profile 游客态点击 `Sign in / Sign up`。
2. Onboarding 结束页。

点击后在当前页面调起注册 / 登录方式弹窗。

弹窗展示：

1. Continue with Google。
2. Continue with Apple。
3. Continue with Email。

弹窗底部展示协议文案：

```text
By continuing, you agree to our Terms of Use and Privacy Policy.
```

规则：

1. `Terms of Use` 可点击。
2. `Privacy Policy` 可点击。
3. 点击后使用系统浏览器跳转官网对应协议页面。
4. 官网链接加载失败提示：`Unable to open this page. Please try again later.`

---

## 2.5 Google / Apple 登录注册

流程：

```text
点击 Continue with Google / Continue with Apple
↓
系统拉起第三方授权
↓
授权成功
↓
如果账号已存在，直接登录
如果账号不存在，自动创建账号
↓
进入 App
```

规则：

1. 授权成功后，如果是新账号，按注册逻辑处理游客资产迁移。
2. 授权成功后，如果是已有账号，按登录逻辑处理，不迁移游客资产。
3. 授权失败提示：`Authorization failed. Please try again.`
4. 用户取消授权后，返回当前注册 / 登录选项页，不创建账号。

---

## 2.6 Email 注册 / 登录

### 邮箱校验

Email 为必填项。

规则：

1. 邮箱不能为空。
2. 邮箱必须包含且仅包含一个 `@`。
3. `@` 前后均需有有效内容。
4. 域名部分需包含至少一个 `.`。
5. 邮箱中不允许空格。
6. 邮箱总长度最多 254 个字符。
7. 提交前自动去除首尾空格，并统一转为小写。

错误提示：

```text
Please enter your email.
Please enter a valid email address.
Email must be 254 characters or less.
```

### 邮箱未注册

流程：

```text
输入邮箱并点击 Continue
↓
邮箱格式校验通过
↓
邮箱未注册
↓
发送验证码
↓
输入验证码
↓
验证码校验通过
↓
Set Password
↓
Create Account
↓
注册成功并进入 App
```

验证码错误：`Incorrect verification code.`

验证码过期：`Code expired. Please request a new code.`

未收到验证码：倒计时结束后可点击 `Resend code`。

### 邮箱已注册

流程：

```text
输入邮箱并点击 Continue
↓
邮箱已注册
↓
进入邮箱登录流程
↓
输入密码
↓
点击 Sign in
↓
校验通过后进入 App
```

密码错误：

```text
Incorrect password. Please try again.
```

### 密码规则

1. 密码至少 8 位。
2. Password 和 Confirm Password 必须一致。
3. 不一致时展示：`Passwords do not match.`

### 忘记密码

流程：

```text
邮箱登录页点击 Forgot password
↓
输入邮箱
↓
校验邮箱格式和是否已注册
↓
发送验证码
↓
验证码校验通过
↓
Set New Password
↓
Reset Password
↓
重置成功，返回邮箱登录页
```

邮箱未注册提示：

```text
Email not registered. Please check your email or create a new account.
```

成功 Toast：

```text
Welcome
Let’s collect the cards.

Welcome back

Password reset successfully.
```

---

# 三、Profile 模块

## 3.1 页面定位

Profile 用于管理账号、联系客服、评分、分享 App、查看协议、退出登录、删除账号。

首版不做订阅，因此以下内容不进入 1.0：

1. Upgrade to Pro。
2. Unlock All。
3. Go unlock。
4. Subscribe。
5. 所有订阅权益展示。
6. Restore。
7. Customer Support 中的 Subscription 选项。

---

## 3.2 游客态 Profile

展示：

1. Sign in / Sign up。
2. Customer Support。
3. Score。
4. Share With Friends。
5. Terms Of Use。
6. Privacy Policy。
7. Version。
8. delete account
 
规则：

1. 游客态不展示 Log Out。
2. 点击 Sign in / Sign up，在当前页面调起注册 / 登录方式弹窗。
3. 登录成功后，Profile 刷新为已登录态。
4. 注册成功后，游客资产迁移到新账号。
5. 登录已有账号后，游客资产不迁移。

---

## 3.3 已登录态 Profile

展示：

1. 用户邮箱。
2. 用户 ID。
3. Account 入口。
4. Customer Support。
5. Score。
6. Share With Friends。
7. Terms Of Use。
8. Privacy Policy。
9. Log Out。
10. Version。

规则：

1. 已登录态展示当前用户邮箱和用户 ID。
2. 点击账号区域进入 Account 详情页。
3. 用户资产与账号绑定。
4. 切换账号后，只展示当前账号下的 Portfolio、Wishlist、扫描添加记录和相关资产。
5. 点击 Log Out 后退出当前账号，回到游客态。
6. 退出登录不删除用户账号和云端资产。

---

## 3.4 Account 账号详情页

字段：

1. 返回按钮。
2. 标题 Account。
3. 头像 / 首字母。
4. 邮箱。
5. ID。
6. Login Method。
7. Log Out。
8. Delete account。

规则：

1. 邮箱、ID、登录方式为只读信息。
2. 点击 Log Out 后退出当前账号，返回游客态。
3. 点击 Delete account 后展示删除账号确认弹窗。
4. 删除账号属于高风险操作，必须二次确认。

删除账号弹窗：

```text
Delete Account?
This action is permanent and can't be undone.
Cancel
Delete
```

删除失败：

```text
Unable to complete this action. Please try again later.
```

---

## 3.5 Customer Support

字段：

1. Type：Bug Report、Feature Request、Improvement、Other。
2. Function：Scan、Search、Collection、Portfolio、Wishlist、Account、Price Data、Other。
3. Email。
4. Message。
5. Submit Feedback。

规则：

1. Type 支持多选，建议可选，未选按 Other 处理。
2. Function 支持多选，建议可选，未选按 Other 处理。
3. Email 必填。
4. 已登录用户默认填入当前账号邮箱。
5. 游客用户 Email 为空，需要手动填写。
6. Message 必填，建议限制 1000 字符。
7. 提交中按钮 loading 并禁止重复点击。
8. 提交失败保留用户输入。

错误提示：

```text
Please enter your email.
Please enter a valid email address.
Please enter your feedback.
Message must be 1000 characters or less.
```

成功提示：

```text
Feedback submitted. Thank you.
```

失败提示：

```text
Unable to submit feedback. Please try again later.
```

---

## 3.6 Score / Share / Terms / Privacy

### Score

1. 点击 Score 后优先调用 iOS 原生评分弹窗。
2. 如果原生评分弹窗无法展示，跳转 App Store 评论页。
3. 跳转失败展示通用失败 Toast。

### Share With Friends

1. 点击后调起系统分享组件。
2. 分享内容为 App Store 下载链接。
3. 用户取消分享不提示错误。
4. 分享调起失败展示通用失败 Toast。

### Terms / Privacy

1. 点击 Terms Of Use 后，使用系统浏览器跳转官网 Terms 页面。
2. 点击 Privacy Policy 后，使用系统浏览器跳转官网 Privacy 页面。
3. 跳转失败提示：`Unable to open this page. Please try again later.`

---

# 四、用户资产模型

## 4.1 Portfolio

Portfolio 是用户已拥有 / 已收藏资产集合。Portfolio 支持多个文件夹。

规则：

1. Home 和 Collection 的 Portfolio 数据受当前选中文件夹影响。
2. 星标文件夹是冷启动默认文件夹。
3. 默认文件夹不可删除。
4. 手动切换文件夹优先级高于默认文件夹，持续到下一次冷启动。
5. 下一次冷启动重新展示星标默认文件夹。

---

## 4.2 Wishlist

Wishlist 是用户想关注或想购买的卡牌列表，不参与资产统计。

规则：

1. Wishlist 无文件夹。
2. Wishlist 不计入 Home 当前总资产。
3. Wishlist 不计入 Home 图表。
4. Wishlist 不计入 Most Valuable。
5. Wishlist 不影响 Portfolio Qty。
6. 同一张卡不可同时存在于 Portfolio 和 Wishlist。
7. Portfolio 优先级高于 Wishlist。
8. 卡牌成功加入 Portfolio 后，如该卡已在 Wishlist 中，则自动从 Wishlist 移除。
9. Search 中 Collected 状态下，不展示 Hearted 状态。
10. 用户后续从 Portfolio 删除该卡后，不自动恢复到 Wishlist。如果用户仍想关注，需要手动重新加入 Wishlist。

---

## 4.3 Collection Item

Collection Item 是用户对某个收藏对象的一条持有记录。

一个 card_id / product_id 可存在多条 Collection Item，例如：

1. Charizard · Raw · Near Mint · Qty 1。
2. Charizard · PSA 10 · Qty 1。
3. Charizard · PSA 9 · Qty 2。

规则：

1. 每条 Collection Item 独立取价。
2. Home 总资产按所有 Collection Item 累加。
3. Most Valuable 按单条 Collection Item 的单张当前市场价排序。
4. Collection 列表展示多条记录，不强制合并。
5. Search Qty 展示当前文件夹中该卡的总数量。

---

## 4.4 Collection Item 字段

### 新增 Collection Item

适用场景：

1. Scan Review Your Matches 页面。
2. Search 详情页 Add to Portfolio。
3. Trending Today 详情页 Add to Portfolio。
4. Wishlist 详情页 Add to Portfolio。
5. 未收藏卡牌详情页 Add to Portfolio。
6. 从详情页 / Wishlist / Trending Today 等入口点击 Add to Portfolio 时，弹窗顶部展示 Adding to [Portfolio Name]。
用户可点击 Adding to 切换目标文件夹。
Collection Item 表单内不展示 Portfolio 字段。

新增字段：

1. Quantity。
2. Grader。
3. Condition / Grade。
4. Language。
5. Finish。
6. Purchase Price。
7. Notes。
8. Total。

规则：

1. 新增 Collection Item 不展示 Portfolio 字段。
2. 扫描流程以当前卡牌的 `Adding to` 为准。
3. 扫描外弹窗也以 `Adding to` 为准。
4. 如果入口没有明确目标文件夹，则默认加入当前 Home / Collection 选中文件夹。
5. 用户点击 Add / Save 后才创建 Collection Item。

### 已收藏后编辑 Collection Item

字段：

1. Quantity。
2. Portfolio。
3. Grader。
4. Condition / Grade。
5. Language。
6. Finish。
7. Purchase Price。
8. Notes。

规则：

1. 已收藏后的编辑页可以展示 Portfolio 字段。
2. Portfolio 字段用于移动当前资产到其他文件夹。
3. 保存成功后，当前 Collection Item 从原 Portfolio 移动到目标 Portfolio。
4. 原 Portfolio 和目标 Portfolio 的资产统计都需要刷新。
5. 保存失败时，不改变原 Portfolio 归属。

---

## 4.5 Grader / Condition / Grade 规则

### Grader 选项

```text
Raw
PSA
BGS
SGC
CGC
TAG
AGS
```

规则：

1. Grader 必填。
2. 默认 Grader = Raw。
3. Grader = Raw 时，使用 Raw / Ungraded 市场价。
4. Grader 为 PSA / BGS / SGC / CGC / TAG / AGS 时，使用 Grader + Grade 市场价。
5. Grader 切换后，Condition / Grade 区域同步变化。

### Raw 状态

Condition 选项：

```text
Near Mint (NM)
Lightly Played (LP)
Moderately Played (MP)
Heavily Played (HP)
Damaged (D)
```

规则：

1. Raw 状态下 Condition 必填。
2. 默认 Condition = Near Mint (NM)。
3. Raw 状态下不展示 Grade。
4. Raw 状态下按 Raw + Condition 取价。

### Graded 状态

规则：

1. Graded 状态下 Grade 必填。
2. Grade 根据 Grader 动态展示。
3. 例如 PSA：PSA 10、PSA 9、PSA 8、PSA 7、PSA 6、PSA 5、PSA 4、PSA 3、PSA 2、PSA 1。
4. 默认选中该 Grader 的最高等级，例如 PSA 默认 PSA 10。
5. Graded 状态下不使用 Raw Condition。
6. Grader 和 Grade 不可出现不匹配状态。
7. 如果所选 Grader + Grade 无市场价，Total 展示 `--`，但允许保存。

### 不可混用

1. Raw 卡展示 Condition。
2. Graded 卡展示 Grader + Grade。
3. Raw 品相和 Graded 评级不可同时作为价格口径。
4. Raw 切换到 Graded 后，Condition 不参与取价。
5. Graded 切换到 Raw 后，Grade 不参与取价。

---

## 4.6 Total 与 Purchase Price

### Total

```text
Total = 当前市场价 × Quantity
```

规则：

1. Total 根据当前 Collection Item 的 Grader、Condition / Grade、Language、Finish 等字段实时计算。
2. 当前市场价缺失时，Total 展示 `--`。
3. Purchase Price 不参与 Total 计算。
4. Total 金额跟随当前货币展示。

### Purchase Price

1. Purchase Price 是用户记录的购买成本。
2. Purchase Price 默认 0 或空值，按页面实现。
3. Purchase Price 只能填写数字。
4. Purchase Price 可以为小数。
5. Purchase Price 不可为负数。
6. Purchase Price 不参与当前市场价值计算。
7. Purchase Price 不影响 Home 总资产、图表和 Most Valuable。

错误提示：

```text
Please enter a valid price.
```

---


##4.7  Collection Item 下拉 / 选择字段规则
适用字段：
1. Grader
2. Condition / Grade
3. Language
4. Finish
以上字段会影响当前 Collection Item 的价格取值口径。用户修改后，Total 需要按新的字段组合实时重新计算。
---
### 1. Grader
#### 字段含义
Grader 用于判断当前 Collection Item 是否为评级卡，并决定后续展示 Condition 还是 Grade。
#### 选项来源
Grader 选项使用 App 内固定枚举，1.0 支持：
| 选项 | 说明 |
|---|---|
| Raw | 未评级卡 |
| PSA | PSA 评级 |
| BGS | Beckett / BGS 评级 |
| SGC | SGC 评级 |
| CGC | CGC 评级 |
| TAG | TAG 评级 |
| AGS | AGS 评级 |
#### 默认值
```text
Raw

规则

1. Grader 必填，不可为空。
2. 默认值为 Raw。
3. 用户选择 Raw 时，下方字段展示 Condition。
4. 用户选择 PSA / BGS / SGC / CGC / TAG / AGS 时，下方字段展示对应 Grade。
5. Grader 修改后，Condition / Grade 需要同步更新为对应默认值。
6. Grader 修改后，Total 需要重新计算。
7. 如果对应 Grader + Grade 没有市场价，Total 展示 --，仍允许保存。

⸻

2. Condition / Grade

Condition / Grade 与 Grader 强关联。

⸻

2.1 Raw 状态下：Condition

当 Grader = Raw 时，展示 Condition 选项。

选项来源

Condition 使用 App 内固定枚举，1.0 支持：

选项	缩写
Near Mint	NM
Lightly Played	LP
Moderately Played	MP
Heavily Played	HP
Damaged	D

页面展示：

Near Mint (NM)
Lightly Played (LP)
Moderately Played (MP)
Heavily Played (HP)
Damaged (D)

默认值

Near Mint (NM)

规则

1. Condition 必填，不可为空。
2. Raw 状态下默认 Near Mint (NM)。
3. Raw 状态下不展示 Grade。
4. Condition 影响 Raw 市场价取值。
5. 用户切换 Condition 后，Total 需要重新计算。
6. 如果对应 Condition 没有市场价，Total 展示 --，仍允许保存。
7. 文案统一使用 Near Mint (NM)，不要使用 Nearly Mint (NM)。

⸻

2.2 Graded 状态下：Grade

当 Grader = PSA / BGS / SGC / CGC / TAG / AGS 时，Condition 字段切换为 Grade。

选项来源

Grade 选项根据当前选择的 Grader 动态展示。1.0 可先使用固定枚举。

PSA

PSA 10
PSA 9
PSA 8
PSA 7
PSA 6
PSA 5
PSA 4
PSA 3
PSA 2
PSA 1

BGS

BGS 10
BGS 9.5
BGS 9
BGS 8.5
BGS 8
BGS 7.5
BGS 7
BGS 6.5
BGS 6
BGS 5
BGS 4
BGS 3
BGS 2
BGS 1

SGC

SGC 10
SGC 9.5
SGC 9
SGC 8.5
SGC 8
SGC 7.5
SGC 7
SGC 6.5
SGC 6
SGC 5
SGC 4
SGC 3
SGC 2
SGC 1

CGC

CGC 10
CGC 9.5
CGC 9
CGC 8.5
CGC 8
CGC 7.5
CGC 7
CGC 6.5
CGC 6
CGC 5
CGC 4
CGC 3
CGC 2
CGC 1

TAG

TAG 10
TAG 9.5
TAG 9
TAG 8.5
TAG 8
TAG 7.5
TAG 7
TAG 6.5
TAG 6
TAG 5
TAG 4
TAG 3
TAG 2
TAG 1

AGS

AGS 10
AGS 9.5
AGS 9
AGS 8.5
AGS 8
AGS 7.5
AGS 7
AGS 6.5
AGS 6
AGS 5
AGS 4
AGS 3
AGS 2
AGS 1

默认值

用户选择评级机构后，默认选中该机构最高等级。

示例：

Grader	默认 Grade
PSA	PSA 10
BGS	BGS 10
SGC	SGC 10
CGC	CGC 10
TAG	TAG 10
AGS	AGS 10

规则

1. Grade 必填，不可为空。
2. Graded 状态下不展示 Raw Condition。
3. Grade 选项必须跟随当前 Grader。
4. Grader = PSA 时，只展示 PSA 等级，不展示 BGS / SGC / CGC 等其他等级。
5. 用户切换 Grade 后，Total 需要重新计算。
6. 如果 Grader + Grade 无市场价，Total 展示 --，仍允许保存。
7. Raw Condition 与 Graded Grade 不可混用。

⸻

3. Language

字段含义

Language 表示当前 Collection Item 对应卡牌语言版本。不同语言版本可能对应不同市场价格。

选项来源

Language 优先来源于当前卡牌数据库支持的语言列表（库里对应当前卡牌支持的语言展示出来，没有则默认English）。

如果数据库返回该卡支持语言，则只展示该卡支持的语言。

如果数据库未返回支持语言，则使用 App 默认语言枚举兜底。


默认值

优先级如下：

1. 扫描 / Search / 详情页当前卡牌数据中的 language；
2. 如果当前卡牌无 language，默认 English；
3. 如果用户上次为同类卡牌选择过语言，可后续考虑使用用户最近选择值，1.0 可不做。

规则

1. Language 必填，不可为空。
2. Language 默认取当前卡牌数据。
3. 如果当前卡牌数据无语言，默认 English。
4. Language 影响价格取值。
5. 用户切换 Language 后，Total 需要重新计算。
6. 如果该 Language 无市场价格，Total 展示 --，仍允许保存。
7. Language 在 Search / Scan / Detail / Collection Item 中需要保持一致。

⸻

4. Finish

字段含义

Finish 表示卡牌工艺 / 版本，例如 Holofoil、Reverse Holo、Normal 等。不同 Finish 可能对应不同市场价格。

选项来源

Finish 优先来源于当前卡牌数据库支持的 Finish / Variant 列表。

如果数据库返回该卡支持的 Finish，则只展示该卡支持的 Finish。

如果数据库未返回支持 Finish，则使用 App 默认 Finish 枚举兜底。

默认选项枚举

Normal
Holofoil
Reverse Holo
Foil
Non-Foil
1st Edition
Unlimited
Other

默认值

优先级如下：

1. 扫描 / Search / 详情页当前卡牌数据中的 Finish；
2. 如果当前卡牌无 Finish，但数据库标记该卡只有一个版本，则默认该版本；
3. 如果当前卡牌无 Finish 且无法判断，默认 Normal 或 Holofoil 需以后端数据为准；
4. 页面示例中默认展示 Holofoil。

规则

1. Finish 必填，不可为空。
2. Finish 默认取当前卡牌数据。
3. Finish 影响价格取值。
4. 用户切换 Finish 后，Total 需要重新计算。
5. 如果该 Finish 无市场价格，Total 展示 --，仍允许保存。
6. 如果对象是 Sealed Product，Finish 字段不展示。
7. 如果对象是体育卡，Finish 可用作版本 / 子系列字段的补充，但 Search 列表不单独展示复杂扩展字段。

⸻

字段联动与价格刷新

触发 Total 重新计算的字段

以下字段变更后，需要重新计算 Total：

1. Quantity
2. Grader
3. Condition / Grade
4. Language
5. Finish

计算公式：

Total = 当前市场价 × Quantity

其中，当前市场价由以下字段共同决定：

Card ID / Product ID
Grader
Condition / Grade
Language
Finish

规则：

1. Purchase Price 不参与 Total 计算。
2. Notes 不参与 Total 计算。
3. 如果当前字段组合没有价格，当前价格展示 --，Total 展示 --。
4. 价格缺失不影响用户保存 Collection Item。
5. 保存后，该 Collection Item 不计入 Home 当前总资产和 Most Valuable，直到价格补全。

⸻

新增 / 编辑场景中的默认值

新增 Collection Item

无论从 Scan、Search 快捷 Collect、卡牌详情页 Add to Portfolio、Wishlist Add to Portfolio 进入，默认值统一为：

字段	默认值
Quantity	1
Grader	Raw
Condition	Near Mint (NM)
Language	当前卡牌数据语言；无数据则 English
Finish	当前卡牌数据 Finish；无数据则按数据库默认
Purchase Price	0 或空值，按页面设计
Notes	None / 空

已收藏后编辑 Collection Item

编辑时默认展示当前 Collection Item 已保存值。

规则：

1. 不重置用户已保存字段。
2. 用户修改字段后，Total 重新计算。
3. 点击 Save changes 后保存修改。
4. 点击 Cancel 后放弃修改，恢复原值。



# 五、Home 模块

## 5.1 页面定位

Home 是用户进入 App 后查看收藏资产概览的首页，核心展示：

1. 当前选中文件夹总价值。
2. 价值变化趋势。
3. 当前文件夹内最高价值卡牌。
4. 市场当日升值幅度最高卡牌。

Home 不承载 Wishlist 管理，不承载完整 Portfolio 列表管理，不承载订阅权益展示。

---

## 5.2 Portfolio 总资产卡片

字段：

1. 当前文件夹。
2. 总资产金额。
3. 资产隐藏按钮。
4. 价值变化文案。
5. 图表。
6. 时间维度：1D、7D、1M、3M、6M、MAX。

规则：

1. 总资产金额表示当前选中文件夹内全部 Portfolio Collection Item 的当前总价值。
2. 图表展示当前文件夹价值变化。
3. 图表从卡牌加入该文件夹之日起开始追踪。
4. 卡牌加入文件夹之前不计入该文件夹历史资产。
5. 删除 Collection Item 后，从删除时间点开始不再计入当前资产和后续图表。
6. 删除前历史资产记录保留，不回写历史。
7. 同一张卡多条 Collection Item 分别取价后累加。
8. Quantity 参与总资产计算。
9. 当前市场价缺失的 Collection Item 不计入总资产。
10. 点击时间维度后，图表按所选周期刷新。
11. 图表周期只影响曲线范围，不改变当前总资产金额。
12. 点击或长按曲线点位时，展示该日期和对应总资产金额。

---

## 5.3 Most Valuable

Most Valuable 展示当前选中文件夹内单张价值最高的 Collection Item。

字段按类型简化：

| 类型 | 展示字段 |
|---|---|
| TCG 单卡 | 卡牌名称、系列、编号 / Finish、状态、当前单张价格、30D Change 百分比 |
| 体育卡 | 球员名 + 卡号、年份 + 系列 / 品牌、版本 / 子系列、评级状态、当前单张价格、30D Change 百分比 |
| Sealed Product | 产品名称、系列名、Sealed、当前单件价格、30D Change 百分比 |
| 其他特殊收藏品 | 名称、系列 / IP / 年份品牌、版本 / 状态、当前价格、30D Change 百分比 |

规则：

1. 只统计当前选中文件夹内的 Portfolio 资产。
2. Wishlist 不参与。
3. 按单张当前市场价从高到低排序。
4. Quantity 不影响 Most Valuable 排序。
5. 同一张卡多个状态视为不同 Collection Item 分别排序。
6. 缺少当前价格的资产不参与排序。
7. 30D Change 缺失展示 `-/-`。
8. 点击 View 进入 Collection - Portfolio，并按单张价值降序展示。
9. 如果当前文件夹无卡牌，展示 `No cards in this portfolio yet`。

---

## 5.4 Trending Today

Trending Today 展示二级市场当天升值幅度最高的卡牌。

字段：

1. 卡牌图片。
2. 卡牌名称。
3. IP / 系列。
4. 当前市场价。
5. 当日涨跌幅百分比。

规则：

1. 不受当前文件夹影响。
2. 不要求用户收藏。
3. 按当天涨幅百分比降序。
4. 首页展示 3 条。
5. 点击 View 进入 Trending 完整列表或 Search 结果页，并保留 Trending 排序。
6. 点击单张卡牌进入未加入 Portfolio 的卡牌详情页。
7. 如果用户从详情页添加到 Portfolio，默认加入当前选中文件夹，并调起 Collection Item 弹窗。

---

## 5.5 文件夹规则

1. 文件夹用于区分用户不同 Portfolio 资产集合。
2. 当前选中文件夹决定 Home 和 Collection - Portfolio 展示数据。
3. 星标文件夹是冷启动默认文件夹。
4. 默认文件夹不可删除。
5. 默认文件夹只能有一个。
6. 手动切换文件夹优先级高于默认文件夹，持续到下一次冷启动。
7. 删除当前选中文件夹后，自动切换到默认文件夹。
8. 删除非默认文件夹会删除该文件夹内所有卡牌。
9. 新建文件夹成功后不自动成为默认文件夹。
10. 文件夹名称限制 1–50 字符。

---

## 5.6 货币切换

支持币种：USD、EUR、JPY、GBP、CAD、AUD、NZD、SGD。

规则：

1. 点击右上角货币入口，打开货币选择弹窗。
2. 当前货币使用单选态。
3. 点击未选中货币后，调用汇率接口。
4. 成功后 App 内所有金额字段换算为目标货币。
5. 百分比不随货币切换变化。
6. 切换失败时保持原货币，并展示通用失败 Toast。

---

# 六、Search 模块

## 6.1 页面定位

Search 用于用户查找卡牌和系列，并快速将卡牌加入当前选中的 Portfolio 文件夹或 Wishlist。

Search 包含两个 Tab：

1. Cards：搜索 / 浏览卡牌、体育卡、套盒、特殊收藏品。
2. Sets：搜索 / 浏览系列。

Game / IP 控制下方 Cards / Sets 数据范围，但两个 Tab 的数据、搜索结果、列表状态互不关联。

---

## 6.2 Search 顶部规则

字段：

1. 搜索框：`Search cards, sets, or characters`。
2. 相机图标：进入 Scan。
3. 清除按钮：清空搜索词。
4. Game / IP 下拉：默认 Pokémon。
5. Tab：Cards / Sets。

规则：

1. 进入 Search 默认展示 Cards Tab。
2. 默认 Game / IP 为 Pokémon。
3. 用户可输入卡牌名、系列名、角色名等关键词。
4. 切换 Game / IP 后，当前 Tab 列表刷新。
5. 切换 Game / IP 时清空当前搜索词。
6. Cards 和 Sets 互不关联。
7. 两个 Tab 可各自保留搜索状态，切到其他页面再回来时不自动重置。

---

## 6.3 Cards Tab 列表字段

Search 列表只展示涨跌百分比，不展示涨跌金额。

通用结构：

```text
图片
名称
当前价格
30D Change 百分比
归属信息
版本 / 状态信息
Qty
Collect / Collected
Wishlist 爱心
```

### TCG 单卡

字段：

1. 卡牌图片。
2. 卡牌名称。
3. 当前价格。
4. 30D Change 百分比。
5. 系列名。
6. 稀有度 / 编号。
7. Finish / Variant。
8. Qty。
9. Collect / Collected。
10. Heart。

示例：

```text
Squirtle
$32.13
(+4.76%)
Mega Evolution Promos
Promo · 039
Holofoil
Qty: 0        Collect    ♡
```

### 体育卡

字段：

1. 体育卡图 / 评级封装图。
2. 球员名 + 卡号。
3. 当前价格。
4. 30D Change 百分比。
5. 年份 + 系列 / 品牌。
6. 版本 / 子系列。
7. 评级状态。
8. Qty。
9. Collect / Collected。
10. Heart。

示例：

```text
Michael Jordan #57
$18,500.00
(+7.25%)
1986 Fleer
Base
BGS 9.5
Qty: 0        Collect    ♡
```

### Sealed Product

字段：

1. 产品图。
2. 产品名称。
3. 当前价格。
4. 30D Change 百分比。
5. 系列名。
6. Sealed。
7. Qty。
8. Collect / Collected。
9. Heart。

示例：

```text
Perfect Order Booster Box
$222.61
(+1.36%)
Perfect Order
Sealed
Qty: 0        Collect    ♡
```

### 其他特殊收藏品

字段：

1. 图片。
2. 名称。
3. 当前价格。
4. 30D Change 百分比。
5. 系列 / IP / 年份品牌。
6. 版本 / 状态。
7. Qty。
8. Collect / Collected。
9. Heart。

---

## 6.4 Search 快捷操作

### Qty

1. Qty 表示当前账号在当前选中文件夹中的持有数量。
2. 未加入当前文件夹时展示 Qty: 0。
3. 已加入当前文件夹时展示对应数量。
4. 同一对象在当前文件夹有多个 Collection Item 时，Qty 展示总数量。
5. Wishlist 不影响 Qty。
6. Qty 只统计当前选中文件夹，不统计其他文件夹。

### Collect / Collected

Search 列表中的快捷 `Collect` 直接加入当前选中文件夹，不调起 Collection Item 弹窗。

规则：

1. `Collect` 表示该对象未加入当前选中文件夹。
2. 点击 Collect 后，按默认 Collection Item 直接加入当前选中文件夹。
3. 加入成功后按钮变为 `Collected`。
4. 如果该卡在 Wishlist 中，加入 Portfolio 成功后自动从 Wishlist 移除。
5. `Collected` 表示该对象已加入当前选中文件夹。
6. 再次点击 Collected 时，如果当前文件夹中只有一条对应 Collection Item，可取消加入；如果存在多条 Collection Item，则进入详情页由用户手动管理，避免误删。
7. 如果对象在其他文件夹中存在，但不在当前选中文件夹中，仍展示 Collect。
8.Search 快捷 Collect 不弹 Collection Item 弹窗，使用默认 Collection Item 字段创建资产。
默认值
Quantity = 1
Grader = Raw
Condition = Near Mint (NM)
Language = 当前卡牌数据语言；无则 English
Finish = 当前卡牌数据 Finish；无则按数据库默认
Purchase Price = 空 / 0
Notes = 空
Portfolio = 当前选中文件夹

### Heart / Wishlist

1. 空心爱心表示未加入 Wishlist。
2. 点击空心爱心后加入 Wishlist。
3. 加入成功后变为实心。
4. 实心爱心再次点击后，从 Wishlist 移除。
5. Portfolio 中已有该卡时，不允许再加入 Wishlist。
6. Wishlist 不影响 Home 总资产、Most Valuable、Search Qty。

---

## 6.5 Search 默认排序

1. Search 默认排序以数据接口返回默认排序为准。
2. 接口可使用 provider_order、updated_at、release_date、market_rank 等字段。
3. 前端不写死本地入库时间倒序。
4. Collection Portfolio 默认按加入当前文件夹时间倒序。
5. Wishlist 默认按加入 Wishlist 时间倒序。

---

## 6.6 Sets Tab

字段：系列图片 / 占位图、系列名称、Game / IP。

规则：

1. Sets 列表只展示当前 Game / IP 下的系列。
2. Sets 和 Cards 互不关联。
3. 搜索关键词在 Sets Tab 中只搜索系列相关数据。
4. 点击系列后进入该系列下所有卡牌 / 产品列表。
5. 系列列表中的卡片仍支持点击详情、Collect、Wishlist。

---

## 6.7 Search 无结果 / 加载失败

无结果：

```text
No results found
Try a different keyword
```

加载失败：

```text
No content available
Refresh
```

规则：

1. 无结果只作用于当前 Tab。
2. Cards 无结果不代表 Sets 无结果。
3. 点击搜索框 x 清空关键词，恢复当前 Tab 默认列表。
4. 列表请求失败只影响当前 Tab，不影响顶部搜索框、Game / IP 下拉和底部导航。

---

# 七、Scan 模块

## 7.1 页面定位

Scan 用于识别用户已拥有的实体卡牌，并将扫描结果添加至 Portfolio。

扫描结果不会自动保存。用户需要在 `Review Your Matches + Collection Item` 页面中确认扫描结果、编辑收藏字段，并点击添加按钮后，卡牌才会加入目标 Portfolio。

Scan 不添加 Wishlist。

---

## 7.2 扫描来源与结果状态

扫描来源：

1. 拍摄卡牌。
2. 从相册上传图片。

每个扫描项识别后可能进入以下状态：

| 状态 | 含义 | 后续处理 |
|---|---|---|
| Matched | 数据库匹配成功 | 可进入 Review Your Matches + Collection Item 页面 |
| Failed | 识别失败、超时、网络失败、图片不可用 | 可重试或删除 |
| No Match Found | 识别完成，但数据库无匹配结果 | 只能 Search Manually 或删除 |

规则：

1. 只有 Matched 项可以进入 Review Your Matches + Collection Item。
2. Failed 不进入 Review，不进入 Collection Item。
3. No Match Found 不进入 Review，不进入 Collection Item，不参与 Add all cards。用户从 No Match Found 点击 Search Manually 进入 Search 后，如果在 Search 中成功添加卡牌到 Portfolio，原 No Match Found 扫描项目自动删除
4. 用户必须点击 Add this card 或 Add all cards 后，卡牌才会加入目标 Portfolio。

---

## 7.3 扫描拍摄页

字段：

1. 关闭按钮。
2. 闪光灯按钮。
3. Search 图标。
4. 扫描框。
5. Gallery 相册入口。
6. 拍摄按钮。
7. Done 按钮。
8. 底部扫描结果列表。

规则：

1. 进入扫描页后打开相机预览。
2. 闪光灯默认关闭。
3. 退出扫描页、App 进入后台、锁屏或系统中断时，闪光灯自动关闭。
4. 每次拍摄只处理扫描框中的 1 张卡牌。
5. 不支持同一画面多张卡牌同时拆分识别。
6. 从相册导入时，最多选择 10 张图片。
7. 用户点击拍摄或选择图片后，该扫描项立即进入底部扫描结果列表。
8. 新扫描项初始展示为 Scanning。
9. Scanning 不阻塞继续拍摄下一张。
10. 多个扫描项可同时处于 Scanning 状态。

---

## 7.4 单张扫描流程

```text
用户拍摄或上传 1 张卡牌
↓
扫描项识别成功，状态为 Matched
↓
底部展示单张成功扫描结果卡片
↓
用户点击 Done 或点击该成功扫描项
↓
进入 Review Your Matches + Collection Item 页面
↓
用户确认匹配结果，编辑收藏字段
↓
用户点击 Add this card
↓
卡牌加入当前卡牌对应的 Adding to 目标文件夹
↓
展示成功提示并返回扫描页
```

规则：

1. 单张 Matched 项进入单张 Review 页面。
2. 进入页面前，该卡尚未加入 Portfolio。
3. Add this card 只添加当前卡牌。
4. 添加失败停留当前页面并保留输入内容。

---

## 7.5 多张扫描流程

```text
用户连续拍摄或上传多张卡牌
↓
每张卡牌独立识别
↓
用户点击 Done 或点击任意 Matched 扫描项
↓
进入多张 Review Your Matches + Collection Item 页面
↓
顶部展示 Matched 扫描项缩略卡
↓
用户可切换不同卡牌
↓
每张卡可独立编辑收藏字段和 Adding to 目标文件夹
↓
Add this card 单张添加
或 Add all cards 批量添加
```

规则：

1. 每张 Matched 卡牌拥有独立 Collection Item 编辑内容。
2. 每张 Matched 卡牌拥有独立 `Adding to` 目标文件夹。
3. 不同卡牌可以加入不同 Portfolio 文件夹。
4. Add this card 只添加当前选中卡牌。
5. Add all cards 添加所有满足条件的 Matched 卡牌。
6. 批量添加时，每张卡牌加入自己对应的 Adding to 文件夹。
7. 添加成功项从待处理列表和顶部切换区移除。
8. Failed 和 No Match Found 不参与 Add all cards。

---

## 7.6 Review Your Matches 页面

### 扫描结果确认区

包含：

1. 顶部卡牌切换区。
2. Your Picture。
3. Our Match。
4. Top matched results。

规则：

1. Your Picture 展示用户原始拍摄 / 上传图片。
2. Our Match 默认展示最高匹配结果。
3. 用户点击 Top matched results 候选结果后，替换当前 Our Match。
4. 替换后同步更新 Collection Item 卡牌信息。
5. 候选结果中的 Search 入口用于进入 Search 手动查找。

### Collection Item 区域

字段：

1. Collection item。
2. Adding to main。
3. 卡牌信息卡。
4. Quantity。
5. Grader。
6. Condition / Grade。
7. Language。
8. Finish。
9. Purchase Price。
10. Notes。
11. Total。
12. Add this card。
13. 删除按钮。
14. Add all cards。
15. Delete all cards。

规则：

1. Collection Item 表单中不展示 Portfolio 字段。
2. 添加目标文件夹由当前卡牌的 `Adding to` 决定。
3. 点击 `Adding to main` 打开文件夹选择弹窗。
4. 切换 Adding to 仅影响当前选中卡牌。
5. 如果当前字段组合无市场价，当前价格展示 --，Total 展示 --，仍允许保存。保存后该 Collection Item 展示在 Portfolio 中，但不计入 Home 当前总资产、Most Valuable 和图表当前价值。

---

## 7.7 No Match Found

展示：

```text
No Match Found
Search Manually
```

规则：

1. No Match Found 只支持 Search Manually 和删除。
2. 点击 Search Manually 后进入 Search 页面手动查找。
3. 如果在 Search 中找到卡牌，则走 Search 添加到 Portfolio 流程。
4. No Match Found 不进入 Review。
5. No Match Found 不进入 Collection Item。
6. No Match Found 不参与 Add all cards。
7. No Match Found 不生成资产。

---

## 7.8 Failed

展示：

```text
Failed
Tap to retry
```

规则：

1. Failed 不进入 Review。
2. Failed 不参与 Add all cards。
3. 用户可点击 Failed 项重试。
4. 用户可删除 Failed 项。
5. 仅有 Failed 项时 Done 不可点击。

---

## 7.9 Done 按钮规则

| 当前扫描列表状态 | Done 状态 | 点击结果 |
|---|---|---|
| 无扫描项 | 不可点击 | 不进入后续流程 |
| 仅 Failed | 不可点击 | 重试或删除 |
| 仅 No Match Found | 不可点击 | Search Manually 或删除 |
| 1 张 Matched，无 Scanning | 可点击 | 单张 Review |
| 2 张及以上 Matched，无 Scanning | 可点击 | 多张 Review |
| Matched + Failed | 可点击 | 仅 Matched 进入后续 |
| Matched + No Match Found | 可点击 | 仅 Matched 进入后续 |
| 存在 Scanning | 不可点击 | 等待识别完成 |

---

## 7.10 添加成功

单张成功：

```text
Success
1 card added to your portfolio
```

多张成功：

```text
Success
5 cards added to your portfolio
```

规则：

1. 成功项从待处理列表移除。
2. Failed / No Match Found 项保留，用户可重试、Search Manually 或删除。
3. 添加成功后返回扫描页。

---

# 八、Collection 模块

## 8.1 页面定位

Collection 是用户管理卡牌资产和心愿单的核心页面，包含两个 Tab：

1. Portfolio：管理用户已收藏、已拥有、已加入文件夹的卡牌资产。
2. Wishlist：管理用户想关注、想购买、暂未拥有的卡牌。

---

## 8.2 Portfolio Tab

Portfolio 展示当前文件夹内用户已收藏的 Collection Item。

字段：

1. 卡牌图片。
2. 卡牌名称。
3. 卡牌语言。
4. 卡牌编号。
5. Set / 系列。
6. Finish / Variant。
7. Grader + Condition / Grade。
8. Quantity。
9. 当前价值。
10. 30D Change 百分比。
11. 金额隐藏按钮。

规则：

1. Portfolio 只展示当前选中文件夹内的资产。
2. Wishlist 不进入 Portfolio 列表。
3. 每条卡牌按用户保存的 Collection Item 状态取价。
4. Raw 取 Raw + Condition 市场价。
5. Graded 取 Grader + Grade 市场价。
6. 同一张卡多个 Collection Item 作为不同资产项展示。
7. 当前价值 = 对应市场价 × Quantity。
8. 当前市场价缺失时展示 `--`，不计入总资产。
9. 涨跌幅固定展示 30D Change 百分比。
10. 货币切换后，涨跌百分比不变。

---

## 8.3 Portfolio 搜索、筛选、排序

搜索范围：当前选中文件夹。

搜索支持：卡牌名称、系列名、编号、IP / Game。

默认排序：按卡牌加入当前文件夹时间倒序。

筛选：

1. Game / IP 多选。
2. Language 多选。
3. Sort 单选。

规则：

1. 搜索关键词、筛选条件、排序条件可同时生效。
2. Portfolio 和 Wishlist 各自独立保存筛选 / 排序状态。
3. 用户切换文件夹后，排序筛选规则沿用当前用户选择，数据范围切换为新文件夹。
4. App 冷启动后不保留筛选条件和排序。
5. 缺少价格的卡牌在价格排序中排在底部。
6. 缺少涨跌幅的卡牌在涨跌幅排序中排在底部。

无结果：

```text
No matching cards found.
```

---

## 8.4 Wishlist Tab

Wishlist 展示用户加入心愿单的卡牌。

字段：

1. 卡牌图片。
2. 卡牌名称。
3. 卡牌语言。
4. 卡牌编号。
5. Set / 系列。
6. Finish / Variant。
7. 当前市场价。
8. 30D Change 百分比。

规则：

1. Wishlist 不展示 Quantity。
2. Wishlist 不计入 Home 总资产。
3. Wishlist 不计入 Most Valuable。
4. Wishlist 中的价格是市场参考价，不是用户资产价值。
5. Wishlist 卡牌点击后进入普通卡牌详情页。
6. 用户从 Wishlist 详情页加入 Portfolio 时，调起 Collection Item 弹窗。
7. 加入 Portfolio 成功后，自动从 Wishlist 移除。

---

## 8.5 Collection 空状态

Portfolio 空状态：

```text
No cards in this portfolio yet.
Scan or search cards to start tracking your collection.
Scan a Card
Search Cards
```

Wishlist 空状态：

```text
Your wishlist is empty.
Save cards you want to collect later and keep an eye on their market value.
Search Cards
```

---

# 九、Card Detail 与 Collection Item 编辑

## 9.1 页面定位

卡牌详情页展示单个收藏对象的基础信息、价格趋势、市场价格、交易入口，以及用户已收藏时的 Collection Item 信息。

收藏对象包括：

1. TCG 单卡。
2. 体育卡。
3. 评级卡。
4. 套盒 / 卡包 / 整箱。
5. 其他特殊收藏品。

---

## 9.2 未加入 Portfolio 详情页

入口：Search 列表、Wishlist、Trending Today、Shop / Marketplace 等。

展示：

1. 基础信息。
2. Price。
3. Market Prices。
4. Shop。
5. Add to Portfolio。

规则：

1. 不展示 Collection Item。
2. 不展示 Remove from Portfolio。
3. 点击 Add to Portfolio 调起 Collection Item 弹窗。
4. 弹窗不展示 Portfolio 字段，以 Adding to 为准。

---

## 9.3 已加入 Portfolio 详情页

入口：Collection - Portfolio、Home Most Valuable、扫描添加成功后的 Portfolio 记录。

展示：

1. 基础信息。
2. Collection Item Tab。
3. Price Tab。
4. Edit item。
5. Remove from Portfolio。
6. 分享按钮。

规则：

1. 默认展示 Collection Item Tab。
2. 点击 Edit item 进入编辑状态。已收藏 Collection Item 编辑页中的 Portfolio 字段仅用于将该 Collection Item 移动到其他文件夹。
新增 Collection Item 弹窗不展示 Portfolio 字段。
3. 已收藏后的编辑页可展示 Portfolio 字段，用于移动当前资产到其他文件夹。
4. 点击 Remove from Portfolio 触发二次确认。
5. 移除成功后刷新 Home、Collection、Most Valuable、图表。

---

## 9.4 基础信息字段

### TCG 单卡

1. 卡牌名称。
2. IP / Game。
3. Set / 系列。
4. 稀有度 / 编号。
5. Finish / Variant。
6. Language。

### 体育卡

1. 球员名 + 卡号。
2. 年份 + 系列 / 品牌。
3. 版本 / 子系列。
4. 评级状态。

### Sealed Product

1. 产品名称。
2. 系列名。
3. Sealed 状态。

### 其他特殊收藏品

1. 名称。
2. 系列 / IP / 年份品牌。
3. 版本 / 状态。

---

## 9.5 Price Tab

Price Tab 展示价格趋势、不同状态市场价格和交易入口。

规则：

1. 图表切换：RAW、GRADED。
2. 时间周期：1M、3M、6M、12M、MAX。
3. Market Prices 表格列：Grade / Condition、Market、7D Change。
4. Market Prices 的 7D Change 只展示百分比。
5. Shop 展示 Marketplace 商品列表。
6. Price 图表、Market Prices、Shop 可分区加载。
7. 数据加载失败时，按局部失败规则处理。

---

## 9.6 Remove from Portfolio / Wishlist

Remove from Portfolio：

1. 点击后展示二次确认弹窗。
2. 确认后删除当前 Collection Item。
3. 删除后，从删除时间点开始不再计入当前资产和后续图表。
4. 删除前历史资产记录保留，不回写历史。
5. 如果该卡只剩这一条 Collection Item，移除后返回 Collection Portfolio。

Remove from Wishlist：

1. 点击后展示二次确认弹窗。
2. 确认后从 Wishlist 移除。
3. 不影响 Portfolio。

---

# 十、资产统计与异常规则

## 10.1 价格缺失

当前市场价缺失时：

1. 价格展示 `--`。
2. 不计入 Home 当前总资产。
3. 不参与 Most Valuable。
4. Collection / Search / Detail 仍展示基础信息。
5. 仍可加入 Portfolio 或 Wishlist。

历史价格缺失时：

1. 优先使用该时间点之前最近一次有效价格。
2. 如果没有任何有效历史价格，则该时间点不计入该卡价值。

---

## 10.2 涨跌幅公式

通用公式：

```text
Change % = (Current Price - Previous Price) / Previous Price × 100%
```

Search 列表：30D Change 百分比。

Collection Portfolio / Wishlist：30D Change 百分比。

Home Most Valuable：30D Change 百分比。

Trending Today：Today / 24H 百分比。

Card Detail Market Prices：7D Change 百分比。

Previous Price 缺失或为 0 时，展示 `-/-`。

---

## 10.3 Portfolio 总资产

```text
Current Portfolio Value = sum(Collection Item Market Price × Quantity)
```

规则：

1. 只统计当前选中文件夹内有效 Collection Item。
2. Wishlist 不计入资产统计。
3. 当前价格缺失不计入当前总资产和 Most Valuable。
4. Quantity 参与总资产计算。
5. Most Valuable 按单张价格排序，不按总持有价值排序。
6. 统计周期起点资产为 0 时，百分比展示 `-/-`。

---

## 10.4 卡牌唯一识别

1. 卡牌唯一性不能只按名称判断。
2. card_id / product_id 是唯一标识。
3. Set、编号、语言、Finish、Variant 共同决定具体版本。
4. Search、Scan、Collection、Wishlist 状态均以 card_id / product_id 判断。

---

## 10.5 后台卡牌数据变更

公共卡牌数据发生后台变更时，不直接删除用户 Collection Item。

状态：

1. Delisted：从 Search 公共列表下架，但用户 Portfolio / Wishlist 中已有记录继续展示。若价格仍可用，则继续参与资产统计；若价格不可用，则展示 `--`，不计入资产。
2. Merged：合并到新的 canonical_card_id，用户 Collection Item 自动关联到新 canonical_card_id，用户填写的 Quantity、Portfolio、Grader、Condition / Grade、Language、Finish、Purchase Price、Notes 保持不变。
3. Unavailable：无替代 card_id 时，用户 Collection Item 不删除。展示最近一次可用基础信息缓存，价格 `--`，涨跌幅 `-/-`，从异常开始不计入 Home 当前总资产和 Most Valuable。用户仍可编辑或移除。

Price Tab 不作为普通加载失败处理，展示：

```text
Price data unavailable
This card’s public data is no longer available.
Refresh
```

历史规则：

1. Unavailable 之前已经生成的历史资产快照保留。
2. Unavailable 之后不再参与新的当前总资产计算。
3. 如果后续恢复 active 或 merged 到 canonical_card_id，则从恢复 / 合并时间点开始重新参与统计。

---

## 10.6 多端与同步

1. 本地展示与服务端不一致时，以服务端最新数据为准。
2. 保存 / 删除 / 移动成功后，重新拉取当前页面核心数据。
3. 多端同时编辑同一 Collection Item 时，1.0 采用最后保存覆盖。
4. 操作成功但刷新失败时，保留已确认成功状态，并在对应模块展示 Refresh。

---

## 10.7 批量操作

批量添加部分成功：

1. 成功项加入 Portfolio，并从待处理列表移除。
2. 失败项保留在 Review 中。
3. Total 重新计算。
4. 提示：`Some cards couldn’t be added. Please try again.`

批量添加全部失败：

1. 停留 Review 页面。
2. 保留用户编辑内容。
3. 不清空扫描结果。
4. 展示通用失败 Toast。

批量添加过程中：

1. 请求中不允许退出。
2. 已成功项以服务端结果为准。
3. 未成功项保留待处理状态。

---

# 十一、页面刷新范围

资产新增、删除、移动、编辑成功后，需要刷新：

1. Home 当前总资产。
2. Home 图表。
3. Home Most Valuable。
4. Collection Portfolio 列表。
5. Collection Wishlist 列表。
6. Search Qty。
7. Search Collect / Collected 状态。
8. Search Heart 状态。
9. Card Detail 状态。
10. 文件夹列表。

---

# 十二、首版不做 / 暂不支持

1. 订阅 / PRO。
2. Restore。
3. 离线资产保存 / Pending sync。
4. No Match Found 直接创建 Custom Card。
5. 同画面多卡拆分识别。
6. 自动实体卡去重。
7. Wishlist 与 Portfolio 共存。
8. Search 列表展示涨跌金额。
9. Search 默认排序写死为本地入库时间。
10. 首版基础信息中展示体育卡 Sport / Team / RC / Auto / Patch / Serial Number 等复杂字段。

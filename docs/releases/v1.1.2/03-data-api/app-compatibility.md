# App 兼容回归：首批与 C03 源码合同检查

状态：2026-10-09 已建立本地可执行入口，不是所有旧 App、真机或线上环境兼容已经验收。继承 [v1.1.1 兼容契约](../../v1.1.1/03-data-api/app-compatibility-contract.md)与 [C01–C13 矩阵](../../v1.1.1/05-delivery/app-compatibility-acceptance.md)，历史文档原样保留。2026-10-12 PR #3 已合入 dev@e8d1dd9；本分支继续增加 C03 目录/价格/汇率合同，本地 API 8/8、旧 1.0.4 和 1.0.5 各 24/24。没有修改已证实的生产兼容 BUG，新增的是旧源码与当前服务端的自动化证据；dev HTTP 健康与 GitHub CI 不替代 watcher 运行版本验收。

## 运行入口

在仓库根执行 `pnpm test:app-compatibility`。前置条件是已有 Node/pnpm、Flutter、Git、tar 和已解析的 Node/Dart 依赖；命令不会自动安装 SDK/依赖、checkout 分支、联网请求业务 API 或运行远程迁移。缺失前置条件或任一步失败均以非零状态退出，不跳过后宣称通过。

- [版本登记](../../../../scripts/app-compatibility-baselines.json)：固定 Git tag、完整提交 SHA、营销版本与构建号，仅标记 `git-source-contracts-only`。标签缺失/漂移或 pubspec 版本不匹配时停止。
- [当前 API 合同](../../../../apps/workers-api/src/compatibility/app-contract.test.ts)：实际调用当前 Hono 路由，复用现有 PGlite PostgreSQL 测试适配，加载既有 0000/0001/0003/0004/0006 迁移到内存数据库，8 项 API 测试产出 39 份带方法/路径/请求正文/响应/Content-Type 的样本；测试分区只存在于该内存库，没有新增迁移、D1 实例、D1 类型或旧 D1 基座维护。
- [旧客户端合同](../../../../apps/flutter-app/tool/compatibility/client_contract_test.dart)：使用实际旧 Dart HTTP 客户端/DTO；受控 Dio adapter 校验旧代码发送的方法、路径、query、JSON、Bearer 及预约幂等键，并回放上述真实测试响应，不直接返回人工编造的成功响应。成功/错误都检查旧客户端的解析语义；公共目录/汇率不带 Bearer，原 portfolio/scan 鉴权与预约幂等键断言保留。真实纯文本 500 按原 Content-Type 回放，未改造成成功 JSON 包。
- [编排脚本](../../../../scripts/check-app-compatibility.mjs)：先运行 API 合同，再从固定 Git 提交导出 App/订阅包源码到独立目录，为每个基线生成包映射并运行同一合同。冻结包的专用编译标记避免误用当前源码；未修改旧源码文件，不将最新客户端通过冒充旧包通过。
- 原始样本、源码归档、依赖映射和 `report.json` 保留在忽略目录 `.dart_tool/app-compatibility/run-*/`，不进入正式 docs/Git；不同运行不覆盖旧证据。脚本只读取本机已有依赖映射/graph，在新目录内生成测试文件，不清理用户目录。

## GitHub CI 检查（2026-10-12）

[App compatibility 工作流](../../../../.github/workflows/app-compatibility.yml)已在 `codex/v1.1.2-dev@eee77abc7321a3aa324aa4260ec4d2eabe64b4df` 的 [GitHub push 运行](https://github.com/kando6370-wq/toccards/actions/runs/38192725017)通过。已下载 artifact 核对 API 4/4、旧 1.0.4 与 1.0.5 各 13/13，以及 `report.json` 的固定提交、干净工作区和 `git-source-contracts-only` 证据类型；[PR #3](https://github.com/kando6370-wq/toccards/pull/3)的 [pull_request 运行](https://github.com/kando6370-wq/toccards/actions/runs/38194094012)也已通过。PR 报告独立确认同样的测试数量、20 份响应及干净工作区；实际测试提交为 GitHub 合并引用 `f623de578d877e596d8bb3b4468000c1ba37b1ec`，不是直接使用 head `eee77ab`，不代表 PR 已合并。2026-10-12 10:39 已配置分支必需检查并分别回读 `main`/`dev` 的生效规则；非草稿 PR #4/#5 的正反例已实测：兼容失败时两者均为 MERGEABLE（无代码冲突）但 BLOCKED；恢复后必需检查全部通过，两者变为 UNSTABLE，保留非必需营销站预览失败。该轮门禁验收结束时，验收 PR 已关闭且未合并，未调用 merge API；这不代表全部 CI 或完整 App 兼容矩阵通过。

- 检查名称固定为 `App compatibility (Windows)`，运行器为 `windows-2022`；PR 目标为 `dev`/`main`，push 仅响应 `dev`/`main`，保留手工触发入口。2026-10-13 的源码调整取消了 `codex/**` push 触发。PR 不使用 paths/paths-ignore，避免检查因文件过滤而缺席。
- 使用 Node 22、pnpm 11.9.0、Flutter 3.44.7；Flutter 与当前 GitHub iOS 流水线版本一致，不改 GitLab 的独立工具链约束。checkout 获取完整历史和标签，已有基线仍按完整提交 SHA 校验。
- 按顺序执行 `pnpm install --frozen-lockfile`、`flutter pub get --enforce-lockfile`、`pnpm --filter @kando/auth-core build`、基线校验测试，再运行 `pnpm test:app-compatibility`；不依赖开发机现有 node_modules、Dart 映射或 auth-core 编译产物。
- 工作流只有 `contents: read` 权限，checkout 不保留凭据，不传入业务环境 Secret，不运行部署/迁移。应用目录、用户数据和远端环境不作为测试对象。
- 测试输出通过 PowerShell Tee 写入 `ci.log` 后，显式将原生进程的非零退出码返回给 job；没有 continue-on-error 或失败后无条件成功。
- 成功和失败均尝试上传 `ci.log`、每次运行的 `report.json` 与受控测试 `server-responses.json`，保留 7 天并允许选定的隐藏目录；不上传源码归档、整个 .dart_tool、依赖缓存或生产凭据。依赖初始化失败而尚无报告时，上传步骤允许缺少文件，但初始化步骤本身仍失败。

当前强制规则状态（2026-10-13）：按用户授权，已删除远端规则集 `App compatibility required checks`（`24904725`）。GitHub 页面显示无规则集，API 回读 `main`/`dev` 的有效规则均为空；`App compatibility (Windows)` 不再作为这两个分支推送或合并的强制门槛，不再因该项缺失或失败产生 GH013 阻断。兼容 CI 仍根据工作流定义异步运行，PR 可继续用于集成评审。CI 的触发行为以相应提交中的工作流为准；删除与验证证据见[验证记录](../05-delivery/VERIFICATION.md)。

历史门禁接入（2026-10-12，规则已于 2026-10-13 删除）：基础合同的首次 push 与 PR #3 的 pull_request 托管运行均已通过并核验报告；PR #3 已于 2026-10-12 合入 dev@e8d1dd9，该合并提交的兼容 CI 与 iOS unsigned build 也通过；同日 14:22–14:26 已独立回读 dev watcher、release、容器、备份与迁移台账，确认实际运行 e8d1dd9。main 尚未同步，C03 增量由 PR #6 交付；14:22–14:26 的 dev 运行检查点只覆盖 PR #3。2026-10-12 经用户完成本机设备授权后，指定仓库所有者账号核验 `admin=true`；管理员回读确认此前 `main`/`dev` 均为 Branch not protected、规则集为空。已新增 [规则集 24904725](https://github.com/kando6370-wq/toccards/rules/24904725)，名称 `App compatibility required checks`、enforcement=active，只匹配 `refs/heads/main` 与 `refs/heads/dev`。

删除前，规则只要求 `App compatibility (Windows)`，来源限定为 GitHub Actions（integration ID `15368`），没有 bypass actors。`strict_required_status_checks_policy=false`，不额外要求分支必须先同步最新 base；`do_not_enforce_on_create=false`。已通过有效分支规则 API 分别确认 `main`、`dev` 都应用同一规则集；`codex/v1.1.2-dev` 的有效规则为空，该次规则配置时两个目标分支提交未变；PR #3 后续合入 dev 的证据另见验证记录。

隔离正反例验收已完成：[PR #4](https://github.com/kando6370-wq/toccards/pull/4) 目标 dev，[PR #5](https://github.com/kando6370-wq/toccards/pull/5) 目标 main；两者均为非草稿，使用独立分支 codex/compatibility-gate-probe-20261012，只在测试 fixture 中注入已本地验证的错误字段类型。已核对两条 PR 均为非草稿、MERGEABLE（无代码冲突）但合并状态 BLOCKED，唯一必需的 App compatibility 检查均为 FAILURE；营销站和 iOS 检查的 isRequired=false。同一分支恢复提交 3b26ed5 的文件树与 eee77ab 完全相同，push 及两条 PR 的兼容运行全部通过，并逐份下载核对 API 4/4、两组旧端各 13/13、固定基线、干净工作区和实际 merge ref。两条 PR 均从 BLOCKED 变为 UNSTABLE；该轮验收随后关闭两条 PR 且未合并，验收分支当时保留为已恢复状态；2026-10-12 后续分支整理按用户授权由 PR #4 的合并记录跟踪，不改写原正反例证据。正式工作流源码已通过 PR #3 合入 dev；main 尚未同步，C03 的后续交付由 PR #6 跟踪。

已知非阻塞警告：该次运行提示 `actions/checkout@v4`、`actions/setup-node@v4` 和 `actions/upload-artifact@v4` 面向 Node.js 20，托管运行器强制以 Node.js 24 运行；实际步骤成功。本轮保留 action 版本，后续升级需单独验证，不将 action 运行时与测试使用的 Node 22 混为一谈。

PR 另有独立的 iOS unsigned build 检查；兼容 job 成功不等于所有检查通过。用户于 2026-10-12 提供的 Production 截图显示：生产分支 main、构建命令 None、发布命令 pnpm run deploy、根目录 /apps/marketing-web、监听路径 apps/marketing-web/*。随后补充的 Previews Base 截图显示：预览构建开启，Preview URLs 关闭但构建仍会执行；构建命令 pnpm run build、预览命令 npx wrangler preview、根目录 /、监听路径 *。这些是用户提供的页面证据，不冒充 Builds API 回读；灰色排除路径提示不记为已保存配置。

预览监听范围能解释非营销站提交也触发构建，但不能据此确定历史构建失败根因。已读取根构建链：turbo build 只执行编译/静态构建及 Workers dry-run，Linux dry-run 在 SSH 前返回；预览命令与生产部署命令分开。故本轮仅推送 codex 分支，允许既有预览检查运行，不修改 Cloudflare 设置或推送 main/dev；推送前后另行对照生产 Worker deployments 和 Pages canonical deployment。既有 Cloudflare 失败继续作为独立检查记录，详见本版本[验证记录](../05-delivery/VERIFICATION.md)。

## 基线及证明范围

| 源码基线 | 固定提交 | 证据边界 |
|---|---|---|
| `v1.0.4` / `1.0.4+161` | `77d55c10dac74668e23d835952a7e153f89714aa` | 旧 API/DTO 源码执行，非签名 IPA 的安装/分发验证 |
| `v1.0.5` / `1.0.5+163` | `ca5aa552f0e29a9f421c542d15cf271c4bdaae7f` | 源码回归基线，不推断商店发布状态或 Android 分发事实 |

两组都使用本机当前 Flutter 和已解析的第三方依赖，而非历史构建环境；通过的是所列版本源码的协议场景，不是历史二进制/原生插件/系统版本等价。当前每个营销版本仅登记一组代表性源码构建，尚未覆盖同营销版本下有协议差异的其他分发构建。本轮不改变最低支持版本、API 路由/字段、鉴权、权益、额度或任何运行配置。

“新写旧读”首批只覆盖文件夹：当前 API 创建→旧客户端读取/编辑请求及解析→当前 API 再读/删除。当前 API 写入在本地 PostgreSQL 实跑，旧端请求经回放适配器与同一方法/路径/正文比对，不是两部真实设备对远程环境的端到端写读。

## 原矩阵对照

| ID | 本轮覆盖 | 仍未闭合 |
|---|---|---|
| C01 | 本地 iOS/Google 与 dev/prod 配置隔离、旧文案字段、空提示、营销版本/构建号比较 | 实际运营配置与正式旧包升级门禁 |
| C02 | 旧客户端解析 401，文件夹其他 owner 写入 404 | 登录、找回密码、Token Refresh、登出、删除账号、完整 session 生命周期 |
| C03 | 首批冻结合同已通过：目录与两种 sets 请求、40+1+0 分页、字符串 ID、已发布/未发布价格隔离、缺价/零价、部分历史、USD 汇率及 422/404/500/502；含失败反证 | TCG 单一数据集与受控汇率源；多游戏/多来源/完整价格维度、真实目录抽样及正式包/真机仍待补验 |
| C04 | 文件夹读取、重命名、删除；API 幂等重放/409 与 owner 隔离 | Collection/Wishlist、重排/default/preferences 等其余路径 |
| C05 | 未新增旧图像请求合同 | JPEG/向量识别、Review/confirm、两平台与真实候选 |
| C06 | Free=10、预约及同 ID 重放不多占额度、客户端 Premium 声明被拒绝 | 实际 Matched 消费、失败释放、耗尽/并发/弱网和 Premium 成功 |
| C07 | 未执行购买/恢复合同 | Apple 验证、Sandbox/TestFlight、真实 session proof 生命周期；Android 销售范围仍待决 |
| C08 | 未执行 | 图片、分享、传输和弱网/内存 |
| C09 | 无/非法/合法 X-Request-ID 不改变 401 包络，合法 ID 回传 | 401 刷新后的传输 ID、业务幂等键及实际网络重试 |
| C10 | 基础合同及 C03 在本地内存 PostgreSQL 的选定既有迁移上验证；基础 GitHub push/PR 检查、main/dev 规则及双分支正反例阻断通过；dev@e8d1dd9 的 watcher release 已独立回读 | 全部目标 schema、缓存/滚动/回退兼容；正式工作流已合入 dev，main 未同步；兼容合同未接入部署脚本 |
| C11 | 两组不可变源码提交及版本/构建号登记 | iOS 1.0.4 正式 IPA 的可获取性、Android 实际分发制品、设备和渠道证据 |
| C12 | 未新增冻结合同 | 估值/Performance、缺价/零价、部分历史和服务错误 |
| C13 | 文件夹的当前 API 写入/旧端原有操作及再次读取 | 卡牌资产/Wishlist/扫描/价格新写旧读与真实设备 |

## 失败保护与后续补验

- 合同包含三个反例：升级字段改成错误类型、额度字段缺失、额度 access 枚举未知，旧客户端必须报错；另验证添加可选响应字段仍可读取；不能以“没有崩溃”或空数据作为成功。
- 使用当前包映射而非冻结源码会因专用 marker 缺失而编译失败；不会静默降级成只测最新客户端。注册表也拒绝空集合、非固定 SHA、标签不匹配及用构建号重复计营销版本。
- 该命令已在 GitHub push 和 pull_request job 分别实跑通过，main/dev 必需检查配置、失败阻断及恢复正例曾于 2026-10-12 分别验收；该规则已于 2026-10-13 按用户授权删除，兼容 CI 保留为异步反馈。正式工作流已合入 dev，部署门禁未接入，不将源码合同门禁写成真机或发布验收通过。部署、签名包安装、真实账号/生产写入及外部购买调用仍需单独授权。
- 设备补验需产品/发布负责人提供可获取的 iOS 1.0.4 正式制品及授权账号；Android 需先确定实际分发基线。取得后按原 C01–C13 场景补证，不能仅凭源码版本或本轮测试推断平台通过。

## C03 首批边界（2026-10-12）

- 41 张 TCG 卡、一个目录集及受支持/隐藏游戏验证列表与 40+1+0 分页；同时覆盖旧 searchSets 缺省 page 和 searchCatalogSets 显式 page 的请求形态。字符串 ID 含前导零，不能被数字化。
- PostgreSQL 使用实际 price domain、发布指针及历史可见性约束；已发布零价保留为 0，只有未发布报价的卡牌在旧 DTO 中仍为 null，缺失历史不补造日期或零值。只覆盖 Raw/Near Mint/English/Normal 样本，不宣称所有价格维度通过。
- KV 仅使用内存 Map，fetch 默认拒绝。汇率成功用受控上游输入经实际 loader/Hono 输出；无缓存的失败输出 502。数据库故障输出真实 text/plain 500，旧端必须抛错，不能变成成功空列表。没有请求真实汇率源或远端业务 API。
- 新增数值 card_ref、缺少 items、汇率 base 错误三个解析反例，并保留显式 null/可选字段添加的兼容正例。另以临时故障注入将合法零价改为 null，确认旧端业务断言失败，恢复后全量通过；它是验证测试意图的人工反证，不是生产 BUG。
- 当前规模为 API 8 项、39 份响应、每个固定旧源码 24 项；保留原来的所有合同。提交 `7516c43` 的 GitHub push 和 Draft PR #6 的 pull_request 报告均已下载核验，均为干净工作区；PR 测试使用合并引用 `9deda2a`，不是 head 本身；该份报告回读时 PR 尚未合并，后续合并状态不改变这份历史报告的证据范围。历史原始报告和旧版本文档不覆盖、不重写，C12/C13 其余场景及完整真机矩阵继续待验。

实际命令、失败排查、审查及结果见 [v1.1.2 验证记录](../05-delivery/VERIFICATION.md)。

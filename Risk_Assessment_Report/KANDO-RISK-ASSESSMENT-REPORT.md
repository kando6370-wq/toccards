# Kando 技术栈安全风险评估

评估日期：2026-11-05（Asia/Shanghai）

## 结论

升级前最需要处理的风险位于供应链和移动 TLS：项目固定的 pnpm 11.9.0 落入 2026 年公开供应链公告影响范围；旧 Flutter/Dart 版本受 `GHSA-frr6-h895-5pxp` 影响，在 Android 与桌面 `dart:io` 场景存在 eMudhra 中间 CA 私钥可推导导致的 TLS 中间人风险；旧 Gradle 版本处于 2026-10-07 三项官方高危公告影响范围。Node 依赖升级前官方 npm registry 审计命中 54 项，其中 high 18、moderate 31、low 5、critical 0。

本轮已在工作区实施核心升级：pnpm 11.28.10、Node 22.23.4、Flutter 3.47.9、Dart 3.13.7、Gradle 8.14.6；API 栈升级到 Hono 4.13.16、`@hono/node-server` 2.1.6、Drizzle ORM 0.45.4、Drizzle Kit 0.31.11、Vitest 4.1.12，并针对 Miniflare 精确覆盖 undici 7.30.1、sharp 0.35.5。升级后官方 registry 依赖审计为全部严重度 0。

这不等同于所有风险已经关闭。标准 `dart run melos run analyze` 两包0 issues，subscription_core测试、图片异步解码专项回归、App最终基线对照和Android Debug APK构建已完成；iOS、真机TLS、远端环境、离线OS JDK载体、Cloudflare/Linux双运行时、Admin权限矩阵、Apple通知重放和真实识别流量仍需继续验收。当前没有已接入的Google服务端webhook。

本文的 `verified` 只表示源码、锁文件或工具版本已确认落入公告影响范围，且适用平台或调用条件成立；未执行攻击复现，也不表示生产环境已被利用。七项 `theoretical` 是威胁建模候选，用于安排验证，不自动构成代码整改需求。P8 的 100% 仅指测试计划已为全部 VR、攻击路径和攻击链建立映射，尚未执行渗透测试。

## 已验证风险

| 风险 | 升级前证据 | 当前处理 | 剩余验收 |
|---|---|---|---|
| VR-004 pnpm供应链版本风险 | 11.9.0低于官方公告修复边界11.11.0 | 根`packageManager`与CI固定11.28.10；Docker构建从根`packageManager`解析版本 | 冻结安装与CI运行 |
| VR-008 Dart TLS中间CA风险 | Flutter低于3.47.8、Dart低于3.13.7 | 升级Flutter3.47.9/Dart3.13.7 | Android真机受控TLS回归 |
| VR-012 构建与依赖工具链 | npm审计54项；旧Gradle受高危公告影响 | 依赖升级、Gradle8.14.6及哈希固定，审计0 | 完整构建、测试和制品验收 |

JDK 边界已部分收口：Android Debug APK 使用校验后的 Temurin 21.0.13+9 构建成功，Flutter doctor与Gradle PID均确认实际JDK；临时全局`jdk-dir`已恢复，未保留永久配置。Android Studio自带JBR 21.0.10仍存在，但未用于本次批准构建。离线OS载体中的Temurin 21.0.11当前不执行Java，本轮未升级，需经Linux独立验证后处理。

## 被排除的直接攻击结论

Hono CORS ReDoS 要求 `allowHeaders` 为空或缺省，项目显式配置非空数组；静态文件二次解码问题要求使用 `serveStatic` 保护目录，Linux入口仅调用 `serve(app.fetch)`；Drizzle SQL 标识符问题要求不可信动态 identifier/alias，当前唯一旧 schema import 使用静态定义。依赖仍升级以消除公告命中和未来回归风险，但没有证据证明这些路径已在本项目成功利用。

## 风险分布

- 已验证：3
- 理论风险：7
- 待验证：1
- 排除：1
- P0 缓解：3
- P1 缓解：4
- P2 缓解：1

## 当前验证状态

已通过：Workers 102 文件／927 项、Admin 87/87、auth 34/34、relay/offline/preflight 18/18、TypeScript 7/7、production dry-run、Linux打包dry-run、官方npm registry审计0条公告、标准Melos两包分析0 issues、subscription_core 12项、旧App源码兼容24×2，以及图片异步解码失败后的缓存驱逐／重试回归。该图片回归还在 `84eba861` 旧源码隔离副本中按预期失败，证明 `return await decode(...)` 修复有效。

App 最终全量测试为1326 pass／9 fail。Python集合对照确认失败集合严格等于 `84eba861` 原源码、原锁和Flutter3.44.7基线复现的9项，新增失败为空；6项新版golden均已通过，第7张tip原本字节相同未改。9项历史失败继续保留，不写成全测通过。

Android Debug APK使用Temurin21.0.13+9构建成功，耗时461.7秒，大小251305638字节，SHA-256为`4a1c8c96de21817b0ad6c1b2e4c274348d4f72dca239548cced7aa14608b52c3`。这不替代iOS、真机或远端环境验收。

## 评估边界

本轮未读取 Secret 明文，未连接或攻击生产系统，未执行数据库迁移、部署或业务数据写入。安全验证基于源码、锁文件、版本配置、官方公告和本地依赖审计。

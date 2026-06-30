# tcg-card v1.0 产品需求总览

> **定位**：海外 TCG / 球星卡收藏管理 App 的完整产品范围、模块清单与 v1.0 交付边界。
> **最后更新**：2026-06-30
> **上游来源**：
> - Spec：[`docs/superpowers/specs/2026-06-30-tcg-card-preparation-design.md`](../../superpowers/specs/2026-06-30-tcg-card-preparation-design.md)
> - 原始 PRD：[`docs/tcg_cord_docs/`](../../tcg_cord_docs/)

---

## 1. 产品定位

tcg-card 是一款面向海外市场的集换式卡牌（TCG）与球星卡收藏管理移动应用，帮助用户追踪卡牌资产价值、管理持仓、监控市场行情。

核心价值：
- 统一管理 Portfolio（已持有）与 Wishlist（心愿单）；
- 实时展示卡牌市场价格（接第三方聚合 API）；
- 提供资产价值趋势、Trending Today 行情等数据洞察；
- 支持扫描、搜索两种卡牌录入方式。

---

## 2. 目标平台

| 版本 | 平台 | 说明 |
|---|---|---|
| v1.0 | **iOS** | 首发交付；Apple Login、iOS 原生分享按 iOS 实现 |
| 延后 | Android | 架构预留，不在 v1.0 交付范围 |

---

## 3. 模块清单

| 模块 | 标识 | 简述 |
|---|---|---|
| 注册 / 登录 | Auth | Email 密码 + 验证码、Google OAuth、Apple OAuth；找回密码 |
| 首页 | Home | Portfolio 概览、总资产图表、Most Valuable、Trending Today、文件夹管理、货币切换 |
| 收藏管理 | Collection | Portfolio Tab（按文件夹）+ Wishlist Tab；排序 / 筛选 / 搜索 / 分享 |
| 搜索 | Search | Cards / Sets 双 Tab；快捷 Collect / Wishlist 操作；各卡类字段 |
| 扫描 | Scan | v1.0 保留 Tab + 占位引导页（详见第 5 节） |
| 卡牌详情 | CardDetail | 未加入 / 已加入两态；Price Tab；Collection Item 增删改 |
| 个人中心 | Profile | 游客态 / 登录态；Account、客服反馈、评分、分享、删除账号 |
| 启动引导 | Onboarding | 首次启动引导页 |
| 管理后台 | Admin | 用户管理、反馈工单、运营配置、卡牌数据运维 |
| 后端 | Backend | Cloudflare Workers API 网关、D1、第三方数据代理 + 缓存、覆盖层 |

---

## 4. v1.0 范围边界

### 4.1 ✅ 包含

| 类别 | 具体内容 |
|---|---|
| Auth | Email 密码 + 验证码 + Google + Apple；找回密码 |
| Home | Portfolio 概览、总资产金额与图表、Most Valuable、Trending Today、文件夹管理、货币切换 |
| Collection | Portfolio + Wishlist、排序 / 筛选 / 搜索、分享 |
| Search | Cards + Sets、Collect / Wishlist 快捷操作、各卡类字段（TCG / 体育卡 / Sealed / 特殊） |
| 卡牌详情 | 未加入 / 已加入两态、Price Tab、Collection Item 增删改 |
| Profile | 游客态 / 登录态、Account 详情、客服反馈、评分、分享 App、删除账号 |
| 全局 | 涨跌算法、加载 / 失败 / 空状态、Toast、货币、游客匿名账号同步 + 迁移 |
| 启动引导 | 首次启动引导页 |
| 管理后台 | 用户管理、反馈工单、运营配置、卡牌数据运维 |
| 后端 | Workers API 网关、D1、第三方数据代理 + 缓存、override 覆盖层 |

### 4.2 ⏳ 延后（预留接口 / 后续版本）

| 功能 | 说明 |
|---|---|
| Scan 真扫描识别 | 拍照识别卡牌；v1.0 保留 Scan Tab 入口 + 占位页，真扫描能力延后 |
| Home Performance Tab | PRD 标注为 1.0.1 需求；v1.0 不交付；接口预留 |

### 4.3 ❌ 删除 / 隐藏

| 功能 | 说明 |
|---|---|
| 所有订阅相关 | Upgrade to Pro、Subscribe、PRO 标识、订阅权益展示，全部删除或隐藏 |
| Restore 恢复购买 | ⚠️ TBD：默认隐藏；若 App Store 审核要求保留则确认后处理 |
| 客服反馈中的 Subscription 选项 | Customer Support - Function 字段中的 "Subscription" 选项删除或隐藏 |

---

## 5. Scan 导航处理

- 底部导航保留 **Scan Tab**，v1.0 点进后展示占位引导页：
  - 标题：「扫描功能即将上线」（待最终文案确认，⚠️ TBD）
  - 引导用户跳转到 Search 手动查找卡牌
- 真扫描识别能力（拍照识别）标为延后，接口架构预留。

---

## 6. 跨切面规则与架构

- **跨切面规则**（涨跌幅算法、加载 / 失败 / 空状态、Toast、货币换算、游客迁移）不在本文档定义，统一见 [`modules/global-rules.md`](modules/global-rules.md)。
- **技术架构**（Cloudflare Workers 分层、第三方数据接入与缓存、D1 覆盖层、Monorepo 划分）见 [`../../02-architecture/`](../../02-architecture/)。

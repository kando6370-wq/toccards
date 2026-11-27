# Linux dev 重新部署验收（2026-11-27）

## Git 与发布源

- 本地 `dev` 已由 `c6936392` 合并到 `682c092ae45413e8bf3a1bb732b623fa465aef92`，随后推送到 `github/dev`。推送后本地与远端 `dev` 指向同一提交，工作区保持干净。
- `deploy:dry-run:dev` 完成 Admin development 构建、Linux bundle 3 项测试和发布包生成。发布包 manifest 记录 `sha=682c092ae45413e8bf3a1bb732b623fa465aef92`、`branch=dev`、`working_tree_dirty=false`。

## kd201 watcher 发布

2026-11-27 09:30（Asia/Shanghai），kd201 watcher 已将该提交发布为 `branch-dev-682c092ae454-20261127093003`。独立回读确认：

- `current`、`shared/current-release`、manifest 和 watcher 的 `last-seen-sha`／`last-deployed-sha` 均指向 `682c092ae45413e8bf3a1bb732b623fa465aef92`。
- manifest 的发布来源为 `kd201-branch-watcher`，没有 `failed-sha` 或 `failed-at`。
- PostgreSQL 为 18，数据库为 `toccards_test`，迁移 ledger 共 22 项，最新为 `0021_google_play_notification_details.sql`。
- API 和数据库容器健康，migration 容器退出码为 0。`/api/v1/health` 返回 `{"status":"ok"}`，Admin 首页返回 HTTP 200 并包含 `Kando Admin` 标题。
- 开发机通过 `http://192.168.50.201:8080` 独立回读 API health 200 和 Admin 首页 200。

## 手工重部署回读

随后执行手工 `deploy:dev`。服务器预检通过，确认向量与 pHash 识别服务可达，`pendingMigrations=[]`，并创建了发布前数据库备份。准备离线 Node 运行时阶段发现 kd201 宿主机为 `v22.22.1`，低于发布脚本要求的 `22.23.4+`，因此手工发布在切换新 release 前失败。脚本自动重建上一应用 release，API、数据库和 Admin 恢复健康，未执行新的数据库 migration。

本次手工失败产生的非当前 release 已清理。发布前备份保留，文件名为 `toccards-test-20261127-094419-before-manual-682c092ae454-1795743855153.dump`，大小为 1,232,979,139 字节。当前运行环境仍由 watcher 发布的 `branch-dev-682c092ae454-20261127093003` 提供服务。

本轮没有发布 prod、官网或移动端制品，没有执行真实管理员登录、真机扫描、Google Play 交易、购买／Restore 或恢复演练。宿主机 Node 补丁版本升级后，手工 `deploy:dev` 才能恢复为独立可执行的发布路径。

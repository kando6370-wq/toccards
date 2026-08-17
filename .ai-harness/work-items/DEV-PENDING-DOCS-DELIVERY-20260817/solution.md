# dev 文档交付方案

## 范围

- 精确提交当前 5 份 v1.1.0 数据库与迁移文档。
- 同步提交所有尚未入库且状态为 `DONE` 或 `ANSWERED` 的 2026-08-17 Harness 工作项，以及本交付工作项。
- 不提交产品代码、运行配置、凭据或范围外文件。

## 执行与验证

1. 获取 `github/dev`，确认本地与远端没有未处理分叉。
2. 精确暂存目标路径，检查暂存清单、敏感信息、Markdown 引用和 `git diff --cached --check`。
3. 创建一个文档交付提交并推送 `github dev:dev`。
4. 比较本地 `HEAD`、`github/dev` 和远端 `refs/heads/dev` 的完整 SHA，并确认 ahead/behind 为 `0/0`。

## 数据库与回退边界

本次只交付设计文档和 Harness 记录，不创建或执行 migration，不修改 D1、PlanetScale、Hyperdrive 或 Worker binding。若需要回退，应另建反向提交；不重写已推送的 Git 历史。

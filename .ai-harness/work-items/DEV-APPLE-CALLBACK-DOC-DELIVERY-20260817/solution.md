# dev Apple 回调文档 Git 交付方案

## 提交范围

- 四份 v1.1.0 dev Apple 回调状态文档。
- `DEV-APPLE-CALLBACK-ANALYSIS-20260817` 分析工作项。
- `DEV-APPLE-CALLBACK-DOC-SYNC-20260817` 文档同步工作项。
- 本 Git 交付工作项。

其他未跟踪工作项、代码、配置和远程部署均不进入提交。

## 执行与验证

1. 获取远端 `dev` 最新引用，确认本地不存在落后或分叉。
2. 使用精确路径暂存，检查 staged 文件清单、敏感信息和 `git diff --cached --check`。
3. 创建单一文档提交并推送到当前 `github/dev`。
4. 查询远端 `dev` SHA，确认与本地 `HEAD` 完全一致。

仓库级 Harness 检查若仍因本次范围外的历史基线文件失败，将显式报告，不通过扩大提交范围规避门禁。

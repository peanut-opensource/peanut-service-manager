# 资源登记

## github-source

- 用途 / 环境：公开源码托管；开发与稳定分支
- Owner / 来源：peanut-opensource（花生开源）；2026-10-17 通过 GitHub API 核对
- Host / Port：github.com / HTTPS 443，Git SSH 22
- Database / Schema / Namespace：peanut-opensource/peanut-service-manager
- 类型 / 版本：GitHub 托管 Git 仓库；服务版本不适用
- 凭据引用：操作者既有 GitHub CLI / SSH 身份，不存储凭据值
- 数据来源 / 新鲜度：当前 Git 引用与 GitHub API，操作时重新核对
- 健康检查：`gh repo view peanut-opensource/peanut-service-manager` 和 `git ls-remote origin`
- Fallback：无；不可达时停止依赖远端的操作

当前未分配应用监听端口、数据库、容器、远程主机或生产运行资源。

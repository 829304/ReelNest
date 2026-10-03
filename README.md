# 映栖 · ReelNest

**让喜欢的声音与影像，有处可栖。**

映栖是一个规划中的 Flutter 跨平台媒体库与播放器，目标平台为 Windows、macOS、iOS、Android 和 Ubuntu，涵盖影视、音乐、照片与个人媒体收藏。

项目参考 [MediaLib](https://github.com/829304/MediaLib) 的界面、业务规则和 Mlink 接口，以保留原 macOS 版视觉和主要交互为目标，重新实现跨平台客户端。

## 当前状态

当前只有项目规划文档和本地 Git 仓库，尚未创建 Flutter 工程、构建产物或配置 CI。远程仓库尚未创建，也未配置 Git remote。

ReelNest 是新项目的独立仓库；旧 MediaLib 工程继续保留在原目录，作为实现参考及服务端兼容基线。上述目标平台不代表当前已有可用版本。

## 计划文档

- [GitHub 仓库与发布规划](docs/GITHUB_REPOSITORY_PLAN.zh-CN.md)：单仓库布局、分支规则、多平台 CI、版本、签名与发布安排。
- [Flutter 重构实施计划](docs/FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md)：接口复用边界、架构、界面还原、开发阶段与验收标准。

## 技术方向

- Flutter / Dart：共享界面与业务逻辑。
- Riverpod：按领域组织状态与依赖。
- SQLite / Drift：本地索引、缓存与迁移。
- media_kit：优先验证的播放方案，通过独立接口封装。
- 原生平台适配：文件访问、后台音频、媒体控制、相册与窗口能力。

## 下一步

1. 确定应用标识、目标系统版本和设备矩阵。
2. 建立 Flutter 客户端骨架与五端构建验证。
3. 整理现有 Mlink 接口契约。
4. 实现“登录 → 浏览 → 详情 → 播放 → 进度回传”的第一条完整流程。

## 参考基线

计划基于 MediaLib 提交 [`64f8ee2`](https://github.com/829304/MediaLib/tree/64f8ee258d87389414d5e06740a89f59cd857612)。本仓库目前未复制旧项目的源码或媒体资源。

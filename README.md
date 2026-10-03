# 映栖 · ReelNest

**让喜欢的声音与影像，有处可栖。**

映栖是一个开发中的 Flutter 跨平台媒体库与播放器，目标平台为 Windows、macOS、iOS、Android 和 Ubuntu，涵盖影视、音乐、照片与个人媒体收藏。

项目参考 [MediaLib](https://github.com/829304/MediaLib) 的界面、业务规则和 Mlink 接口，以保留原 macOS 版视觉和主要交互为目标，重新实现跨平台客户端。

## 当前状态

已连接远程仓库 [829304/ReelNest](https://github.com/829304/ReelNest)，并在 `apps/client` 初始化五端 Flutter 工程。当前实现启动、路由、自适应应用外壳、基础主题和三个入口页面。真实服务器连接、媒体库、存储和播放尚未实现。

Flutter 固定为 **3.47.6**，由根 `.fvmrc` 管理；应用依赖由 `apps/client/pubspec.lock` 锁定。已编写代码检查和五端构建工作流，远程运行结果仍待验证。运行方式和本机 exFAT 限制见[开发指南](docs/DEVELOPMENT.zh-CN.md)。

ReelNest 是新项目的独立仓库；旧 MediaLib 工程继续保留在原目录，作为实现参考及服务端兼容基线。上述目标平台不代表当前已有可用版本。

## 计划文档

- [文档索引](docs/README.md)：项目规划与设计文档入口。
- [开发指南](docs/DEVELOPMENT.zh-CN.md)：环境、运行命令、验证和构建限制。
- [原版源码映射](docs/design/SOURCE_MAPPING.md)：按 SwiftUI 源码迁移的对应关系及当前范围。
- [项目结构与模块设计](docs/PROJECT_STRUCTURE.zh-CN.md)：目录布局、功能分层、播放与平台边界、分阶段落地方式。
- [GitHub 仓库与发布规划](docs/GITHUB_REPOSITORY_PLAN.zh-CN.md)：单仓库布局、分支规则、多平台 CI、版本、签名与发布安排。
- [Flutter 重构实施计划](docs/FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md)：接口复用边界、架构、界面还原、开发阶段与验收标准。

## 技术方向

- Flutter / Dart：共享界面与业务逻辑。
- Riverpod：按领域组织状态与依赖。
- SQLite / Drift：本地索引、缓存与迁移。
- media_kit：优先验证的播放方案，通过独立接口封装。
- 原生平台适配：文件访问、后台音频、媒体控制、相册与窗口能力。

## 下一步

1. 在支持符号链接的文件系统上配置日常 Windows 开发环境，运行五端 CI。
2. 确认发布用应用标识、目标系统版本和设备矩阵。
3. 整理现有 Mlink 接口契约。
4. 实现“登录 → 浏览 → 详情 → 播放 → 进度回传”的第一条完整流程。

## 参考基线

计划基于 MediaLib 提交 [`64f8ee2`](https://github.com/829304/MediaLib/tree/64f8ee258d87389414d5e06740a89f59cd857612)。已参考其源码迁移部分视觉参数与侧栏样式，未整体复制旧工程或媒体资源，来源见 [NOTICE](NOTICE)。

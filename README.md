# 映栖 · ReelNest

**让喜欢的声音与影像，有处可栖。**

映栖是 MediaLib 的 Flutter 多平台重构版。第一阶段只适配 **Windows、macOS、Linux 三个桌面端**，功能、界面和交互与原项目一致，不自行新增、删减或修改功能。iOS/Android 留待后续阶段。

按 [MediaLib](https://github.com/829304/MediaLib) 原源码迁移业务、各类服务器连接实现与 UI。**UI 一致性是模块完成条件**，不能以“最后打磨”为由另做一套界面。项目边界及已知偏差见 [项目边界](docs/PROJECT_SCOPE.zh-CN.md)。

## 当前状态

2026-10-10 最新进度：本地视频与 Emby 登录/选库、同步、播放/进度、收藏/已看、服务器文本字幕、详情及分库导航已接通；画质/转码、图片持久缓存/预热、手动与自动离线下载、字幕及容量维护已接入。本轮补齐自动订阅的未看窗口、整季/全系列、暂停/到期和网络策略，并增加现有扫描/同步/缓存任务入口及仪表盘静态用量。全量 341 项测试、静态分析及 Windows 4 项原生业务场景通过，正式 EXE 已重建并完成正常启动/退出检查。首页仍是占位页，音乐后续单独实现；公共批量/右键、完整图片内存缓存/预解码、完整 UI 与真实 Emby 验收仍待完成。详见[自动离线订阅](docs/EMBY_OFFLINE_SUBSCRIPTIONS.zh-CN.md)、[画质与缓存](docs/EMBY_QUALITY_CACHE.zh-CN.md)及[本轮验证](docs/TEST_REPORT_2026-10-10.zh-CN.md)。下面保留项目早期历史状态，不作为最新完成范围。

以下是已写代码的事实记录，不代表已符合原版。当前页面仍为简化实现，功能与默认规则存在迁移缺口，需先对照源码审核、纠正。

已连接远程仓库 [829304/ReelNest](https://github.com/829304/ReelNest)，并在 `apps/client` 初始化五端 Flutter 工程。2026-10-05 已落实第一轮架构纠偏：默认入口改为媒体源管理，支持多个目录来源、选择目录、扫描、SQLite 持久化、分页浏览、文件信息、取消扫描和重新定位，不需要服务器登录。旧 Mlink 试验入口已从正常应用移除，仅保留代码与隔离回归测试。播放器、完整元数据和 Emby/Jellyfin/Plex 直连仍未实现，详见[本地媒体源](docs/LOCAL_SOURCES.zh-CN.md)。

2026-10-04 完成 Windows Release 构建、7 项自动化测试及启动冒烟；2026-10-05 补充标题栏拖动起步处理并重新构建。验证范围见[验证记录](docs/WINDOWS_SMOKE.zh-CN.md)。

Flutter 固定为 **3.47.6**，由根 `.fvmrc` 管理。安全存储依赖已解析，锁文件及工具生成的插件注册文件已更新，锁一致性检查通过。代码检查和 Windows/macOS/Linux 构建工作流已编写，远程运行结果仍待验证。运行方式及历史 exFAT 限制见[开发指南](docs/DEVELOPMENT.zh-CN.md)。

ReelNest 是新项目的独立仓库；旧 MediaLib 工程保留在原目录作为实现参考。上述目标平台不代表当前已有可用版本。

## 计划文档

- [项目边界与一致性要求](docs/PROJECT_SCOPE.zh-CN.md)：三桌面端、功能/UI 一致、只重构不改变产品。

- [文档索引](docs/README.md)：项目规划与设计文档入口。
- [开发指南](docs/DEVELOPMENT.zh-CN.md)：环境、运行命令、验证和构建限制。
- [本地媒体源与索引](docs/LOCAL_SOURCES.zh-CN.md)：实际实现、扫描保护、平台范围、验证与未完成能力。
- [原版源码映射](docs/design/SOURCE_MAPPING.md)：按 SwiftUI 源码迁移的对应关系及当前范围。
- [Mlink 连接试验记录](docs/MLINK_CONNECTION.zh-CN.md)：历史实现，不是当前产品架构基线。
- [媒体浏览与详情](docs/LIBRARY_BROWSING.zh-CN.md)：分页、海报、详情、季集接口边界和待验证事项。
- [系列摘要接口试验记录](docs/SERIES_API.zh-CN.md)：历史服务端扩展，不再是 ReelNest 的依赖。
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

1. 建立原版功能、页面、交互和默认配置的源码对照清单。
2. 审核现有实现，纠正简化 UI、规则差异及遗漏。
3. 按原实现逐模块迁移来源、浏览、播放和其他功能，并同步还原 UI。
4. 在 Windows、macOS、Linux 验收功能与界面一致性；不推进移动端功能。

## 参考基线

计划基于 MediaLib 提交 [`64f8ee2`](https://github.com/829304/MediaLib/tree/64f8ee258d87389414d5e06740a89f59cd857612)。已参考其源码迁移部分视觉参数与侧栏样式，未整体复制旧工程或媒体资源，来源见 [NOTICE](NOTICE)。

# 映栖 · ReelNest

**让喜欢的声音与影像，有处可栖。**

ReelNest 是 [MediaLib](https://github.com/829304/MediaLib) 的 Flutter 多平台重构版。第一阶段只开发和验收 **Windows、macOS、Linux** 三个桌面端；iOS/Android 工程暂时保留，不推进移动端功能和布局。

项目只更换实现技术并适配平台，不重新设计产品。功能、默认值、业务规则、服务器连接行为、UI 与交互均按原项目源码迁移；**UI 对照是每个模块的完成条件**。完整边界见[项目边界与一致性要求](docs/PROJECT_SCOPE.zh-CN.md)。

## 当前状态

截至 2026-10-26（下列模块记录各自最后验证批次）：

- Jellyfin 基础视频来源闭环已实现并完成 Windows Release/smoke。共享协议定向 255/255、同步/界面 61/61、Emby 基线 37/37、Jellyfin UI 2/2、Windows Native 真实 mpv 业务链路通过；本批未运行全量 Flutter 测试。真实 Jellyfin、macOS/Linux 和人工精确视觉验收仍待。范围与证据见[Jellyfin 计划](docs/JELLYFIN_PLAN.zh-CN.md)。
- Plex 基础视频来源闭环实施中；前端 2/2 与 Windows Native mpv 单业务用例通过，后端最终定向 21/21 通过，Release/smoke 待回报。不使用真实 Token；真实 Plex、macOS/Linux、人工精确视觉待验。范围见[Plex 计划](docs/PLEX_PLAN.zh-CN.md)。

- TMDB 本地电影元数据已完成实现及 Windows Delivery Release/smoke 验证；最终定向合并复跑 39/39（client16 + service14 + UI9，18秒，exit 0，含series拒绝用例）。全量测试为 1034 passed / 2 conditional skip / 1 native business test unfinished（exit 1），不能视为全量通过。随后缓存关闭取消专项46项通过，Windows Release/smoke 通过；该次未复现先前约4.9秒的具体任务状态。真实 TMDB 公服、macOS/Linux 原生与精确视觉验收仍待。详见[TMDB 专项计划](docs/TMDB_MOVIE_METADATA_PLAN.zh-CN.md)及[缓存关闭取消记录](docs/CACHE_SHUTDOWN_2026-10-26.zh-CN.md)。

- 本地剧集 TMDB 手动匹配实现及 Windows 验证完成：后端最终定向102/102、前端12/12、Profile 原生、Release 与五秒 smoke 通过；本批未跑全量。真实 TMDB 公服、macOS/Linux 原生和人工精确视觉验收待完成。详见[剧集专项计划](docs/TMDB_SERIES_METADATA_PLAN.zh-CN.md)。

- [统一实现状态盘点](docs/IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md)：当前已接入/未实现能力、平台与来源验收边界、分阶段路线；本轮未重跑测试或构建。
- 在线字幕搜索/下载已实现并冻结；最终全量 924 passed / 1 optional benchmark skipped（含专项 39 项），Windows Profile GPU/SW 本机 fixture 集成、Release 和五秒 smoke 均通过。macOS/Linux 实机、真实 Emby 在线/离线字幕、公共服务 live 及可见 UI/原版视觉验收仍待，详情见[专项计划](docs/ONLINE_SUBTITLES_PLAN.zh-CN.md)。
- 自定义播放器快捷键自动化及 Windows Release/smoke 验证通过（2026-10-24）：domain 覆盖 59 个动作；最终串行全量 941 passed / 1 optional benchmark skipped，五个定向测试文件 60 passed / 13 秒（包含新增 17 项）；Windows Profile GPU/SW 实际 mpv fixture integration 两例通过。`dart analyze` clean、374 个 Dart 文件 format 0 changed、diff-check clean。Windows Release 79.9 秒成功，五秒 smoke 正常响应并关闭、退出码 0；macOS/Linux、精确视觉、实体键盘和真实 Emby 验收仍待。`openExternal` 随外部播放模块后补；鼠标/触控板另列后续，范围见[快捷键计划](docs/PLAYER_SHORTCUTS_PLAN.zh-CN.md)。
- 本地视频已接入目录来源、扫描与索引、浏览详情、播放与续播、队列、字幕/音轨、基础播放设置和健康检查；本地与 Emby 共用播放器已接入章节/书签、单片循环、A–B 循环与前后逐帧第一批。
- Emby 视频已接入登录与选库、分页同步与前台浏览、详情、播放与进度、收藏/已看、服务器字幕、画质与转码、图片缓存、手动及自动离线下载、右键与批量操作。
- 首页 H1 已接入跨来源视频统计、继续观看、最近播放、想看、收藏和最近剧集；H2 已接入每日推荐、剧集推荐、高分精选、跨来源视频搜索和运行状态摘要；H3 编排已支持拖动排序、隐藏、添加恢复、默认布局与持久化。视频健康评分已接通原版公式及本地/Emby 核心检查、本地重复与详情缺口；适用范围见[健康评分](docs/HEALTH_SCORE.zh-CN.md)。
- `4d4a0ee` 的全量 587 项及后续 609+2 均为历史批次结果。P1-A 之前的提交前整合复验覆盖了两轮 P0 UI、侧栏/Emby 与 Logo 改动：全量 616 项通过、2 项默认关闭的原生用例跳过；这是历史基线，独立批次的“当时未跑全量”仍准确保留。最新 P1-B 全量及 Windows 结果见下方。macOS/Linux 原生构建/实机、真实 Emby 操作及原版逐像素验收仍待完成，详见[高级播放验证记录](docs/PLAYER_PRECISION_BACKEND.zh-CN.md#提交前整合复验2026-10-14)。
- P1-A 已接入剩余时间切换/持久化、控制栏锁定及播放信息面板；当时 62 项定向测试通过，未重跑全量，616+2 是该批修改前基线。真实 Emby、人工可见窗口及 macOS/Linux 原生验收待完成。详见[播放器 P1-A 记录](docs/PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-a剩余时间控制栏锁定与播放信息2026-10-14)。
- P1-B 的 7 个相关测试文件 66 项、全量 620 项通过/2 项跳过及 Windows Release/smoke 均是 P1-C 前的验证；迷你窗可见交互和 macOS/Linux 原生实机验收仍待。详见[播放器 P1-B 记录](docs/PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-b迷你悬浮窗与窗口置顶2026-10-14)。
- 最新播放器 P1-C 时间轴预览图已完成自动化验证：`flutter analyze --fatal-infos` 零问题，全量 `flutter test --no-pub` 为 643 passed / 3 skipped；时间轴/语义树专项与 native 抽帧通过，Windows Release 构建和五秒 smoke 通过。真实 Emby、人工可见窗口交互/视觉及 macOS/Linux 原生实机验收仍待；P1-B 的 620+2 是此前批次，不能代替 P1-C 验证。详见[播放器 P1-C 记录](docs/PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-c时间轴预览图2026-10-15)。

本地/Emby 共用播放器已接入手动片头/片尾标记与跳过、内嵌章节候选生成及采用/忽略，以及首页/媒体库/详情条目检测入口、系列批量分析与任务中心；最终全量 685 项通过、3 项默认跳过，静态分析、Windows Release 和启动检查通过。检测只覆盖已载入且时长有效的视频；首页桌面交互、真实数据、原版视觉与三端原生验收继续保留。详见[播放器总表](docs/PLAYER_STATUS.zh-CN.md)、[高级播放当前批次](docs/PLAYER_PRECISION_BACKEND.zh-CN.md#当前批次检测入口系列批量分析与任务中心2026-10-15)和[当前阶段记录](docs/NEXT_STAGE.zh-CN.md)。

2026-10-16 用户明确授权播放器右上角显示输入速率，并随底部进度 Dock 同步显隐。代码已冻结：backend 54、UI 27、隔离 native 2 项通过；analyze、269 文件格式及 diff 检查通过。本轮未重跑上一轮 701 项全量；Windows Release 39.6 秒及五秒 smoke 通过。真实 Emby、实体键鼠、macOS/Linux 原生和三端视觉验收仍待。详情见[播放器记录](docs/PLAYER_PRECISION_BACKEND.zh-CN.md#用户授权播放器输入速率提示代码冻结windows-验证完成三端验收待定2026-10-16)。

仍未完成或未完整验收的主要范围包括：Jellyfin 真实服务器、macOS/Linux 原生与人工视觉验收；Plex 基础连接器实施中（前端 2/2、Windows Native 单业务用例和后端最终定向21/21通过，补充边界与Release/smoke未完成）；ReelNest Server 等其余来源，公共集合与搜索的完整范围，音乐、保险库等后续模块，macOS 持久目录授权及三桌面端整体视觉对照。未迁移不代表允许删减。用户于 2026-10-12 明确暂不实现照片模块，照片/相册及首页照片墙已移出当前计划和验收范围；影视图片功能保留，详见[范围调整](docs/PROJECT_SCOPE.zh-CN.md)。

## 项目结构

```text
ReelNest/
├── apps/client/       # Flutter 客户端及平台工程
├── docs/              # 项目边界、计划、实现与验证记录
├── scripts/           # 本地验证脚本
└── .github/           # 检查与三桌面端构建工作流
```

当前只有 `apps/client` 一个 Flutter 包。代码按功能和边界组织在 `features/`、`sources/`、`api/`、`storage/`、`player/`、`platform/` 与 `ui/` 中。旧 Mlink 试验代码只保留用于历史说明和隔离回归，不是正常应用的强制依赖。详细职责见[项目结构与模块设计](docs/PROJECT_STRUCTURE.zh-CN.md)。

## 开发

Flutter 由根目录 `.fvmrc` 固定为 **3.47.6**。安装 FVM 后：

```sh
cd apps/client
fvm flutter pub get --enforce-lockfile
fvm flutter analyze --fatal-infos
fvm flutter test
fvm flutter run -d windows
```

macOS 和 Linux 分别使用 `-d macos`、`-d linux`。环境要求、原生验证、构建产物和 Windows 文件系统注意事项见[开发指南](docs/DEVELOPMENT.zh-CN.md)。

## 文档入口

- [文档索引](docs/README.md)：按当前状态、模块、验证与历史记录分类。
- [文档维护规范](docs/DOCUMENTATION_GUIDE.zh-CN.md)：状态、验证等级、更新和归档规则。
- [项目边界与一致性要求](docs/PROJECT_SCOPE.zh-CN.md)：产品范围和不可变约束。
- [当前阶段记录](docs/NEXT_STAGE.zh-CN.md)：当前下一批及历史实施时间线。
- [三桌面端验收矩阵](docs/PLATFORM_VERIFICATION_MATRIX.zh-CN.md)：Windows、macOS、Linux 的实现与证据。
- [数据字典](docs/DATA_DICTIONARY.zh-CN.md)：当前 schema、身份、缓存和敏感数据边界。
- [原版一致性核对清单](docs/design/ORIGINAL_PARITY_AUDIT.zh-CN.md)：源码依据、偏差和验收缺口。
- [原版缺陷防引入清单](docs/design/ORIGINAL_DEFECT_GUARDS.zh-CN.md)：迁移时必须避免重新引入的问题。
- [Flutter 重构实施计划](docs/FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md)：完整范围和阶段验收标准。

## 技术方向

- Flutter / Dart：共享界面与业务逻辑。
- Riverpod：按领域组织状态与依赖。
- SQLite / Drift：本地索引、缓存与当前初始表结构。
- media_kit：通过项目播放接口封装的视频引擎。
- 原生平台适配：文件访问、窗口、防休眠和桌面系统能力。

## 参考基线

原版行为参考 MediaLib 提交 [`64f8ee2`](https://github.com/829304/MediaLib/tree/64f8ee258d87389414d5e06740a89f59cd857612)。旧 MediaLib 仓库只读使用，不是运行 ReelNest 所必需的服务端。资源与来源说明见 [NOTICE](NOTICE)。

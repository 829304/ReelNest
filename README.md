# 映栖 · ReelNest

**让喜欢的声音与影像，有处可栖。**

ReelNest 是 [MediaLib](https://github.com/829304/MediaLib) 的 Flutter 多平台重构版。第一阶段只开发和验收 **Windows、macOS、Linux** 三个桌面端；iOS/Android 工程暂时保留，不推进移动端功能和布局。

项目只更换实现技术并适配平台，不重新设计产品。功能、默认值、业务规则、服务器连接行为、UI 与交互均按原项目源码迁移；**UI 对照是每个模块的完成条件**。完整边界见[项目边界与一致性要求](docs/PROJECT_SCOPE.zh-CN.md)。

## 当前状态

截至 2026-10-12：

- 本地视频已接入目录来源、扫描与索引、浏览详情、播放与续播、队列、字幕/音轨、基础播放设置和健康检查。
- Emby 视频已接入登录与选库、分页同步与前台浏览、详情、播放与进度、收藏/已看、服务器字幕、画质与转码、图片缓存、手动及自动离线下载、右键与批量操作。
- 首页 H1 已接入跨来源视频统计、继续观看、最近播放、想看、收藏和最近剧集；H2 已接入每日推荐、剧集推荐、高分精选、跨来源视频搜索和运行状态摘要；H3 编排已支持拖动排序、隐藏、添加恢复、默认布局与持久化。视频健康评分已接通原版公式及本地/Emby 核心检查、本地重复与详情缺口；适用范围见[健康评分](docs/HEALTH_SCORE.zh-CN.md)。
- 最近全量 **564 项 Dart 测试通过**；随后 Emby 选库完整性修复的 **126 项相关回归、静态分析、Windows Release 构建与启动检查通过**，详见[健康评分记录](docs/HEALTH_SCORE.zh-CN.md)。该结果不等同于真实 Emby 完整操作、滚动性能、macOS/Linux 原生运行或原版视觉验收。

当前下一批是首页桌面交互与真实数据验收。详见[首页编排](docs/HOME_LAYOUT_EDITOR.zh-CN.md)、[首页实施计划](docs/HOME_IMPLEMENTATION_PLAN.zh-CN.md)和[当前阶段记录](docs/NEXT_STAGE.zh-CN.md)。

仍未完成或未完整验收的主要范围包括：Jellyfin、Plex、ReelNest Server 等其余来源，公共集合与搜索的完整范围，音乐、保险库等后续模块，macOS 持久目录授权，三桌面端原生与视觉对照。未迁移不代表允许删减。用户于 2026-10-12 明确暂不实现照片模块，照片/相册及首页照片墙已移出当前计划和验收范围；影视图片功能保留，详见[范围调整](docs/PROJECT_SCOPE.zh-CN.md)。

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

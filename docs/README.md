# ReelNest 文档

本目录统一保存映栖 ReelNest 的规划与设计文档。更新时间：2026-10-09。

**当前约束：MediaLib 的 Flutter 重构，第一阶段仅 Windows/macOS/Linux；功能、UI 与交互一致，不自行新增、删除或修改功能。** [项目边界](PROJECT_SCOPE.zh-CN.md)替代此前“五端同时推进”“简化 UI 后期再重做”等假设。

品牌约定：客户端 **ReelNest**，自有服务端及对应可选来源 **ReelNest Server**。原 MediaLib 名称只用于源码出处、历史记录及必要的兼容说明。

当前目标是 MediaLib 的 Flutter 多平台重构：直接管理本地文件夹、移动硬盘、已挂载 NAS，以及 Emby/Jellyfin/Plex。此前“依赖 MediaLib 服务端、先做 Mlink 客户端”的规划已撤销。第一轮已实现独立目录来源、扫描、索引和浏览，Mlink 试验路由只用于回归测试；完整目标仍按实施计划推进。

| 文档 | 内容 |
|---|---|
| [项目边界与一致性要求](PROJECT_SCOPE.zh-CN.md) | 用户确认的范围、原版 UI/行为验收与已有偏差 |
| [下一阶段实施安排](NEXT_STAGE.zh-CN.md) | 原版基线、桌面主框架、本地来源还原与三桌面端验收 |
| [设置云备份与恢复计划](CLOUD_SETTINGS_PLAN.zh-CN.md) | 用户确认的后续新增功能：WebDAV 设置备份；尚未实现，不改变当前优先级 |
| [本地媒体库回归记录（2026-10-08）](TEST_REPORT_2026-10-08.zh-CN.md) | 71 项测试结果，含批量添加部分失败、Windows 隐藏属性及健康/设置/系列回归 |
| [无媒体库与 NAS 的测试方案](MEDIA_TESTING.zh-CN.md) | 合成样本、可播放资源、SMB 共享模拟、平台验证与当前覆盖边界 |
| [原版一致性核对清单](design/ORIGINAL_PARITY_AUDIT.zh-CN.md) | 原源码入口、已读规则、当前偏差、第一批落地范围及验收缺口 |
| [原版缺陷防引入清单](design/ORIGINAL_DEFECT_GUARDS.zh-CN.md) | 旧项目暂不修复；迁移时验证远程读取上限、缓存安全提交与 FFmpeg 进程管理 |
| [开发指南](DEVELOPMENT.zh-CN.md) | SDK、运行命令、验证结果和本地环境限制 |
| [本地视频播放器实现盘点](PLAYER_STATUS.zh-CN.md) | 当前状态总表、固定剩余功能范围、验收边界与后续顺序建议 |
| [本地视频播放与续播](LOCAL_PLAYBACK.zh-CN.md) | 原版源码规则、独立窗口、进度存储、基本控制与未迁移项 |
| [播放队列与播完行为](PLAYER_QUEUE.zh-CN.md) | 同系列队列、相邻项、三种播完行为、安全切换及原生 EOF 验证 |
| [字幕、音轨与音量面板](PLAYER_TRACKS.zh-CN.md) | 本地/双字幕、语言偏好、音轨/输出、增强及原生渲染验证 |
| [本地媒体源与索引](LOCAL_SOURCES.zh-CN.md) | 第一轮纠偏实现、目录扫描、SQLite、来源隔离与验证边界 |
| [Windows 构建与冒烟](WINDOWS_SMOKE.zh-CN.md) | C 盘构建、7 项自动化测试、EXE 启动结果及未覆盖范围 |
| [原版源码映射](design/SOURCE_MAPPING.md) | SwiftUI 到 Flutter 的迁移来源与范围 |
| [Mlink 连接试验记录](MLINK_CONNECTION.zh-CN.md) | 历史登录/会话实现，停止作为产品主线扩展 |
| [媒体浏览与详情](LIBRARY_BROWSING.zh-CN.md) | 现有 Mlink 试验路径与可复用界面；待解除来源耦合 |
| [系列摘要接口试验记录](SERIES_API.zh-CN.md) | 历史服务端扩展，不再是新应用依赖，不执行部署 |
| [初始化决策](decisions/0001-client-bootstrap.md) | 应用标识、依赖、布局和 CI 选择 |
| [项目结构与模块设计](PROJECT_STRUCTURE.zh-CN.md) | 目录布局、模块职责、依赖方向、播放器和平台适配边界 |
| [Flutter 重构实施计划](FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md) | 旧项目复用边界、功能范围、开发阶段与验收标准 |
| [GitHub 仓库与发布规划](GITHUB_REPOSITORY_PLAN.zh-CN.md) | 仓库组织、分支、五端构建、版本与发布 |

`design/` 保存源码映射与界面参考，`decisions/` 保存重要技术决策。目录树中的计划项不代表代码已经实现。

最新自动化测试共 **257 项通过，静态分析通过**，Emby 服务器详情、演职员和艺术照已接入。Windows 原生回归包含 Emby 系统安全存储与真实 mpv 网络播放/上报、服务器字幕及收藏/已看操作、独立窗口的解码/续播/保存、多音轨/字幕渲染和增强，以及真实播完行为。完整播放器和原版 UI、macOS 持久目录授权、媒体库导航与 TMDB 扩展等仍待迁移/验收。当前维护初始数据库结构，没有开发版本升级链或自动清库。本批原生回归、Release 产物与启动检查见当日记录。旧 MediaLib 的系列摘要试验分支未部署，不作为后续任务依赖。

2026-10-09 修复空库启动和数据库错误提示，见 [空库启动测试记录](TEST_REPORT_2026-10-09.zh-CN.md)。

- [基础播放设置与防休眠](PLAYER_BASIC_SETTINGS.zh-CN.md)：实现范围、原版默认规则、Windows 验证与平台边界。

- [Emby 基础闭环计划](EMBY_PLAN.zh-CN.md)：下一阶段三批交付、源码依据与验收范围。

- [Emby 连接与选库（E1）](EMBY_CONNECTION.zh-CN.md)：登录、安全凭据、选库、会话恢复与重新认证；E1 历史批次范围，后续见 E2/E3。

- [Emby 分页同步与浏览（E2）](EMBY_SYNC.zh-CN.md)：完整快照替换、取消/失败保护、海报和基本电影/季集详情；后续播放见 E3。

- [Emby 播放与进度同步（E3）](EMBY_PLAYBACK.zh-CN.md)：鉴权 mpv 网络播放、续播/队列、三种痕迹模式及有界播放上报；首页尚未实现。

- [Emby 收藏、已看与服务器字幕](EMBY_ACTIONS_SUBTITLES.zh-CN.md)：状态写回/回滚、整季批量标记、按需下载服务器文本字幕与安全清理；完整详情和导航仍待迁移。

- [Emby 服务器详情、演职员与艺术照](EMBY_DETAILS.zh-CN.md)：30 天缓存、人员入口、图片预览、相关链接和媒体技术信息；完整人物/TMDB、导航及视觉差异仍待迁移。

# ReelNest 已实现与未实现能力盘点（2026-10-23）

本盘点主要记录 2026-10-23 的阶段基线；2026-10-26 TMDB 本地电影元数据最新证据以阶段表及[专项计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)为准。

2026-10-26 最终更新：Jellyfin 基础视频来源闭环已实现；共享协议定向 255/255、同步/界面组 61/61、Emby 基线 37/37、Jellyfin UI 2/2、Windows Native 真实 mpv 业务用例、Windows Release 和五秒 smoke 通过。各组分开记录、不累加；本批未跑全量 Flutter 测试。真实 Jellyfin、macOS/Linux 原生和人工视觉验收待完成。详细证据见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。

- 状态基线：本轮对当前源码、原版实现与既有验证记录进行核对整理；不代替各专项文档，也不把代码存在当成端到端完成。
- 产品阶段：Windows 本地视频与 Emby 视频已形成可用基础闭环；不是 MediaLib 原版全部功能迁移完成，更不是 Windows/macOS/Linux 三端验收完成。
- 平台范围：仅盘点 Windows、macOS、Linux 桌面端。
- 最新整体测试快照：已提交基线 `998b019` 对应 **881 passed / 1 skipped**。随后首页搜索写入竞态修复仍在工作区，未提交；本轮没有重跑测试，因此该结果不覆盖工作区新增改动，也不证明全部功能、来源或三个原生平台均已通过。

## 状态口径

下文分别使用：

- **已接入**：应用代码路径已串通，不代表实际服务、所有平台或完整用户流程已验收。
- **Windows 自动化通过**：仅指相应 Windows 测试/Profile/Release/smoke 证据；组件或 smoke 不等于真实媒体库人工验收。
- **待实机/来源验收**：真实 Emby、设备、长期性能或人工操作仍未覆盖。
- **尚未实现/部分实现**：原版能力没有闭环，不能因 enum、配置字段、文案、依赖或模型存在而标成已支持。

本盘点采用已接入功能清单 + 明确缺口 + 分层验收范围；不估算完成百分比。旧日期测试结果继续留在专项记录中，只作为对应日期/批次的证据。

## 当前能力总览

| 模块 | 实现状态 | Windows 自动化/构建 | 真实来源与人工验收 | macOS 原生 | Linux 原生 | 原版 UI 视觉 |
|---|---|---|---|---|---|---|
| 本地视频来源与索引 | 文件夹、移动盘、已挂载 NAS 路径及扫描/索引安全能力已接入；完整原版向导、自动监控和若干元数据闭环仍缺 | 有分层自动化及 Windows 构建证据；详见[本地来源](LOCAL_SOURCES.zh-CN.md) | 真实目录/设备组合仍需验收 | 尚未完成目录持久授权与稳定卷身份 | 按项目证据逐项验收 | 原版来源向导逐项验收待完成 |
| Emby 视频 | 连接、同步/浏览/详情/用户操作/播放与缓存等主要视频流程已接入 | 有大量分层自动化证据；详见[Emby 文档](README.md#emby-视频)及专项记录 | 真实 Emby 全流程仍待系统验收 | 未完成全平台验收 | 未完成全平台验收 | 原版逐页/逐交互视觉仍待 |
| Jellyfin 基础视频来源 | 独立 kind/provider/凭据/URI；登录恢复、选库、浏览/搜索/详情、视频播放/音轨字幕/续播/切集/上报基础闭环已实现 | 定向分组 255/255、同步/界面 61/61、UI 2/2、Windows Native 真实 mpv、Release 44.1 秒及五秒 smoke 通过；本批未跑全量 | 真实 Jellyfin 服务未验 | Windows Native 基础链路通过 | macOS/Linux 原生待验 | 人工精确视觉待验 |
| 首页 | 影视 Hero、统计、剧集推荐、播放/最近/想看/收藏/新增/高分及运行状态、编排和搜索已接入；不等于完整公共浏览/集合系统 | 自动化和 Windows 验证见[首页文档](README.md#首页)及各优化记录 | 大库可见交互和真实来源组合仍待 | 原生性能/视觉待验 | 原生性能/视觉待验 | 原版逐项视觉仍待 |
| 共用视频播放器 | 本地/Emby 共用会话；大量基础、精确控制和高级画面/音频功能已接入 | 多个模块有 Windows Profile/native/Release 证据；见[播放器状态及专项索引](README.md#视频播放) | 真实 Emby、真实设备听感/硬解/HDR/长播等按项目分别待验 | 原生验收待 | 原生验收待 | 完整原版布局/图标/字体/材质/交互对照待 |
| 健康/任务/应用设置 | 健康评分与忽略恢复、失效路径/重复/详情缺口、扫描/分析/缓存任务中心已有接线 | 各模块有分层自动化及 Windows 证据 | 在线补资料修复未实现；通用原版后台任务/重试系统并未全部迁移 | 原生验收待 | 原生验收待 | 当前不是完整原版设置/引导 |
| 发布与平台支持 | Windows 便携存储、DPAPI、路径防逃逸及打包白名单已实现 | CI 有 Ubuntu check 与三桌面 build artifact workflow；build workflow 只由 main push/手动触发，Codex 分支 push 不自动 build | 当前 workflow 不调用 windows-smoke，也不运行原生播放器 Profile；没有三端全绿/实机结论 | 原生目录权限/稳定卷身份、构建及运行待 | 构建与运行验收待 | 三平台视觉/交互验收待 |

详细播放器功能及跨层证据见[共用视频播放器实现盘点](PLAYER_STATUS.zh-CN.md)和播放器专项文档；Emby 细节见[Emby 视频文档索引](README.md#emby-视频)。

## 来源与本地媒体闭环

### 当前接入范围

- 当前已交付的来源入口为 `localFolder`、Emby 与 Jellyfin 基础视频连接器；Jellyfin 保持独立来源身份并复用 Emby-compatible 协议实现。分组验证、Windows Native/Release/smoke 及未验边界见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。本地入口可使用移动盘及已经由操作系统挂载的 NAS 路径。
- 本地文件侧已有多选去重、部分成功、扫描队列/取消/错误、分类/阈值/隐藏属性、文件名和季集识别、NFO/本地资料/海报/背景、来源重定位、离线保护、索引安全清理；清理索引不删除用户媒体文件。
- `add_source_dialog` 目前不是原版完整三步向导。
- `source_providers` 中 `localFolder`、`removableDrive`、`mountedNas` 共用 `FileSourceAdapter`；Emby/Jellyfin 走远程连接器与 Emby-compatible 协议链路，按 kind 隔离身份并处理差异；Plex 仍未实现。

### 明确未闭环

- 无 `Directory.watch`/watcher，也没有自动增量扫描执行闭环；`autoScan` 等部分策略字段存在不等于行为已接入。
- 来源设置中的 `onMetadataChanged` / `onWriteChanged` 未传入，元数据拉取与写回入口禁用；尚无 TMDB 补全、手工匹配并写回或缩略图回退服务。
- macOS 的目录持久授权未接入且相关按钮禁用；macOS 当前没有可用的稳定卷 UUID 身份，不能笼统记成“待实机验证”。
- 内置 SMB/FTP/FTPS 网络设备连接与挂载未实现。“已挂载 NAS 路径可作为本地目录”不等于 ReelNest 内置网络设备支持。
- Jellyfin 基础视频来源闭环已实现；真实 Jellyfin、macOS/Linux 和人工 UI 视觉验收仍待。Plex 与网络视频 URL 来源仍未实现。旧 Mlink router 仅为测试原型且 `enableLegacyMlink=false`，不构成 ReelNest Server 正式连接器或自有服务端。

## Emby 视频闭环

### 已接线的主要流程

登录/会话/认证恢复、选库与别名；分页同步、失败/取消保护；前台按需浏览及人物作品分页；视频库分区、筛选/排序/搜索、右键与多选；电影、剧集、季集详情，演员/艺术照/关联链接；观看、收藏、想看和评分操作；播放准备、进度上报、服务端字幕；画质选择及 Emby 服务端转码请求；图片缓存预热、离线下载、自动订阅和缓存管理。

这些属于客户端协议/产品流程接线。真实 Emby 服务器已接入并使用过；尚缺覆盖当前整合版本的系统性全流程验收记录。专项批次中使用 fixture 或未覆盖真实 Emby 的历史验证仍按各自原意保留。

Emby 服务端转码是服务器对视频流的转换能力，不代表 ReelNest 客户端本地实时转码，也不代表 Emby 服务器 GPU 配置/管理已实现。全局 TMDB、音乐和手动合集不是基础 Emby 协议接线的前置项。

## 首页、集合与元数据边界

- 首页 `HomeModule.implemented` 当前除音乐推荐/继续听之外均为 true：包括 Hero、统计、剧集推荐、继续观看/最近播放/想看/收藏/最近添加/高分/运行状态、布局编排、查看更多和跨来源影视搜索。
- `HomeCollection` 不等同原版完整公共电影/剧集浏览，也不构成智能集合、手动合集和自定义封面完整闭环。
- 公共 TMDB 元数据、匹配、写回及完整集合管理属于后续模块，不应描述为基础 Emby 视频协议尚未完成的原因。
- 近期首页搜索缓存、按来源刷新/偏好快照优化各有独立 2026-10-22 记录；其基准、失效、取消和已知限制以对应专项文档为准，不在本盘点改写原记录。

## 共用视频播放器

### 已接入能力

本地/HTTP/Emby/离线缓存播放、独立 mpv 窗口、播放/seek/续播/已看、倍速/变调保护、音量/增强、音轨/输出设备、队列/切集/结束行为；内嵌/同目录/手动/服务器字幕与双字幕、字幕样式/语言偏好/时移；逐帧、循环、A–B、章节/标记、片头片尾候选审核与批量分析任务、时间轴预览图；全屏、mini、置顶、控制栏锁定、播放信息面板；六项实时统计和网络输入速率提示。

画面与音频设置已接入：比例/裁切/去隔行/旋转/镜像、五项色彩调整、四档锐化、硬件解码模式、弱网内存缓冲、GPU 去色带/HDR 色调映射，以及三模式截图和八预设视频均衡器。各功能的 Windows 自动化结果及限制详见[播放器专项记录](README.md#视频播放)。

纯 SW renderer 对 HDR/去色带用户编辑明确不支持，是已经确认的平台能力边界，不是未修复 bug；“硬解模式设置可用”不等于实际硬件解码已启用。实际 HDR 片源/显示器、4K 长播、CPU/内存长期表现及真实设备听感是验收项，不是说对应设置代码不存在。

### 未实现或仍需单独方案

- **代码、自动化及 Windows Release/smoke 通过；平台/产品验收待补**：视频播放器自定义快捷键。domain 已包含 59 项批准动作（原版 enum 60 cases，排除 `openExternal`；无漏动作）；2026-10-24 最终串行全量 941 passed / 1 optional benchmark skipped（3 分 11 秒），五个定向测试文件 60 passed / 13 秒（包含新增 17 项），Windows Profile GPU/SW 实际 mpv fixture integration 两例通过；`dart analyze` clean、374 个 Dart 文件 format 0 changed、diff-check clean。Windows Release 79.9 秒成功，五秒 smoke 正常响应并关闭、退出码 0。macOS/Linux、精确视觉、实体键盘及真实 Emby 未验收。`openExternal` 随外部播放模块后补；鼠标/触控板另列后续。详见[快捷键计划](PLAYER_SHORTCUTS_PLAN.zh-CN.md)。
- **实现已冻结，自动化与 Windows Release/smoke 通过；平台/来源人工验收未完成**：Podnapisi/OpenSubtitles 在线字幕搜索/下载。最终全量 924 passed / 1 optional benchmark skipped，包含该专项 39 项；Windows Profile GPU/SW 本机 fixture 集成两例通过，Release 38.5 秒、smoke 正常关闭/退出码 0。公开服务 live、macOS/Linux 实机、真实 Emby 在线/离线字幕和可见 UI 对照未验收。详见[在线字幕计划](ONLINE_SUBTITLES_PLAN.zh-CN.md)。不能与已接入的本地/Emby 字幕选择、样式和同步混为一项。
- **已实现并冻结，Windows 验证通过；平台人工验收待**：视频本地文件/网络 URL 临时播放与拖入本地视频。获批入口为本地文件选择器、网络串流输入，以及主桌面内容区/播放器窗口两个视频文件拖放目标；首页文本模块排序保持原状。OS 冷启动 open-files/CLI 尚未接入，明确列为后续缺口，不属于本批验收。临时身份使用稳定 SHA-256 64 字符 ID（文件为 `file` + 规范化路径，网络流为 `stream` + trim 后 URL），跨窗口 JSON 校验重算结果；原始路径、URL、令牌不持久化。已索引路径按来源 `relative_id` 精确复用身份及续播；临时目标为单项队列，未知项不写进度/活动记录。音轨/字幕/倍速偏好按原版稳定 ID 持久化；未知媒体没有 marker 外键目标，marker 仅内存并在关闭时清理。稳定偏好版本定向 19 项及完整 Flutter 回归（968 passed / 1 optional benchmark skipped，5 分 14 秒，exit 0）通过；之后补充网络串流提示 Escape/Enter 行为，4 文件 UI 专项 21 项/4 秒通过，未并入前述全量。最终 `dart analyze lib test integration_test` clean、386 个 Dart 文件 format 0 changed、diff-check clean；Windows Release 67.2 秒及五秒 smoke 通过。Windows 不写注册表/系统关联；macOS scope/lease 与 entitlement 已接线但未原生验证；`desktop_drop 0.8.0` 固定适配 SDK 3.47.6，未升级 SDK。macOS/Linux 原生、实体拖放/文件选择器、真实服务器非 HTTP 协议及精确 UI 视觉仍待实机验收；音乐、媒体库导入、批量拖放和外部播放器不并入本批，详见[专项计划](PLAYER_TEMPORARY_PLAYBACK_PLAN.zh-CN.md)。
- **Windows 自动化、Release/smoke 通过；真实来源/跨平台验收待**：最终文件专项 23 项通过（后端 15、前端 7、Windows 原生 helper 1）；Dart 全量 991 passed / 2 条件跳过，`dart analyze` 无问题、397 个 Dart 文件 format 0 changes。全量包含后端 15 项，但 UI 损坏恢复补丁晚于全量文件载入；专项与全量结果分别记录、不累计相加。Windows Profile `integration_test/external_playback_test.dart` 跨 engine 测试通过，验证 secondary engine→IPC→主 service/helper、本地中文/`&` 路径、HTTP(S) 与失败回传，相关数据库表均为 0；不代表真实 Emby/VLC/系统默认关联验收。Release 49.1 秒、五秒 smoke 窗口响应正常/正常关闭/ExitCode 0。真实 Emby/VLC/系统默认关联、崩溃后 lease 回收及 macOS/Linux 未实机验证。排除音乐、默认文件关联/注册表及播放进度回读。详见[专项计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。
- 窗口启动宽度/比例偏好及自适应；当前 `player_window_app` 仍固定 960×540。
- 降噪：pinned `hqdn3d` 能力及许可/分发依赖有差异，需单独依赖和产品方案，不得随意换 DLL 或作为锐化顺手扩展。
- 完整原版播放器视觉与交互验收仍未完成。功能已接入或 Windows Profile 通过均不等于逐项 UI 对照通过。

## 健康、任务、设置及其他原版功能

- 健康评分、忽略/恢复、失效路径/重复/元数据缺口检测及扫描/片头片尾分析/缓存任务中心已有接线。
- 在线补资料/修复没有实现；通用的原版后台任务、统一重试和恢复体系也不是全部完成。
- 设置页目前分布于 watched、ignored health、外观模式以及来源/播放器/缓存各自设置；尚非原版完整设置、引导、主题预设和语言体系。
- 原版设置里的界面语言、`posterMinWidth`/`posterMaxWidth`、重播新手引导仍待迁移。
- 本地数据库立即备份/从备份恢复、打开数据位置、完整存储诊断与统一空间整理仍待迁移；ReelNest 已接入图片/视频缓存清理，不等于原版全套存储管理。该缺口不代表要增加开发期间的历史 schema 迁移。
- 保险库/隐私锁、Trakt 等原服务尚未形成对应完整闭环；`media_type_grid_picker` 当前禁用。

## 明确范围调整与后续新增

- **照片/相册**：用户已将其从当前产品入口、计划和验收范围移除；不作为本盘点的未实现待办。保护既有数据的识别/隔离与影视 artwork 是不同能力。
- **音乐**：后续独立大模块统一实现；目前只有部分音频索引同步，不并入视频播放器完成度。
- 音乐 AirPlay 支持状态待进一步核对；本盘点不据此宣称已支持或已实现。
- **WebDAV 设置云备份**：用户明确确认的后续新增需求，首版不要求 ReelNest 统一账号；它不是原版缺失功能，也不是当前原版迁移阶段。
- 原版本地数据库备份/恢复与数据位置/存储诊断属于原版待迁移，和新增 WebDAV 设置云备份是两项不同需求；新增本地备份能力不构成增加历史数据库 schema 迁移的授权。

## 建议分阶段路线

顺序是阶段建议，不是完成承诺；平台基础能力与短功能批次可并行推进。每个功能批次仍先读原版实现/测试，范围只覆盖该批，不把多项未完成功能打包成大阶段。

| 顺序 | 阶段 | 收口目标与边界 |
|---|---|---|
| P0 并行 | 桌面平台基础 | 尽早完成 macOS 本地目录持久授权与稳定卷身份；建立 macOS/Linux 原生构建、运行和基础交互验收路径，不能无限等待高级功能之后再做。 |
| 1（已实现并冻结） | 在线字幕 | 自动化与 Windows Release/smoke 已通过；macOS/Linux、真实来源、真实 Emby 与可见 UI 对照仍按[专项验收表](ONLINE_SUBTITLES_PLAN.zh-CN.md)待验。 |
| 2（自动化/Windows 验证通过） | 自定义播放器快捷键 | 59 个批准动作已实现；全量、定向、Windows Profile GPU/SW、Release 与 smoke 均通过。macOS/Linux、真实用户键盘与原版 UI 视觉验收仍待，详见[计划](PLAYER_SHORTCUTS_PLAN.zh-CN.md)。 |
| 3（已实现并冻结，Windows 验证通过；平台人工验收待） | 本地文件/URL 临时视频与拖入 | 全量 968/1、Escape/Enter UI 专项 21 项、analyze/format、Windows Release/smoke 通过；macOS/Linux 原生、实体文件输入/拖放、真实服务器非 HTTP 协议及精确 UI 视觉验收待完成。详见[专项计划](PLAYER_TEMPORARY_PLAYBACK_PLAN.zh-CN.md)。 |
| 4（Windows 验证通过） | 视频系统外部播放器 | 最终文件专项23项；全量991 passed/2条件跳过，analyze/format、Windows Profile跨engine、Release/smoke通过；真实 Emby/VLC/系统默认关联、崩溃回收和 macOS/Linux实机验收待完成。不含音乐、默认文件关联/注册表或进度回读。详见[专项计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。 |
| 5（实现与 Windows 交付验证完成；全量/平台验收有缺口） | TMDB 本地电影元数据 | 最终定向复跑 `tmdb-final-targeted.log`：client16 + service14 + UI9 共39/39通过（18秒，exit 0，含series拒绝用例）。Windows Profile 原生业务用例及 marker skip native 独立复跑各自通过，不与专项/全量相加。全量 `tmdb-full-final.log` 为 1034 passed / 2 conditional skip / 1 native business test unfinished，exit 1，不记为全量通过。Delivery Release 56.0秒、五秒 smoke 正常关闭/ExitCode 0；后续缓存关闭取消专项46项通过，另一次 smoke 未重现此前约4.9秒的具体任务状态，不作为所有负载的关闭耗时保证。真实TMDB公服、macOS/Linux与精确视觉验收待。详见[专项计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)及[缓存关闭取消记录](CACHE_SHUTDOWN_2026-10-26.zh-CN.md)。 |
| 5（实现与 Windows 交付验证完成；全量/平台验收有缺口） | TMDB 本地电影元数据 | 最终定向复跑 `tmdb-final-targeted.log`：client16 + service14 + UI9 共39/39通过（18秒，exit 0，含series拒绝用例）。Windows Profile 原生业务用例及 marker skip native 独立复跑各自通过，不与专项/全量相加。全量 `tmdb-full-final.log` 为 1034 passed / 2 conditional skip / 1 native business test unfinished，exit 1，不记为全量通过。Delivery Release 56.0秒、五秒 smoke 正常关闭/ExitCode 0；后续缓存关闭取消专项46项通过，另一次 smoke 未重现此前约4.9秒的具体任务状态，不作为所有负载的关闭耗时保证。真实TMDB公服、macOS/Linux与精确视觉验收待。详见[专项计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)及[缓存关闭取消记录](CACHE_SHUTDOWN_2026-10-26.zh-CN.md)。 |
| 5b（实现与 Windows 验证通过；平台验收待） | TMDB 本地剧集手动匹配 | 后端最终定向102/102、UI12/12，analyze clean、417 Dart files format 0 changed；Windows Profile 原生业务用例、Release42.3秒与五秒 smoke 均通过。本批未跑全量。按既有有效季集号获取季详情（最多并发2、不逐集请求），更新已有 episode 的 title/overview/year 并保护身份、编号、路径、图片、播放记录；匹配期间集合/编号变化则拒绝整事务。真实TMDB公服、macOS/Linux与人工精确视觉待验。详见[专项计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。 |
| 6（基础闭环已实现；Windows 交付验证通过） | Jellyfin 基础视频连接器 | 共享协议 255/255、同步/界面组 61/61、独立 UI 2/2、Emby 基线 37/37、Windows Native 真实 mpv、Release/smoke 通过；本批未跑全量。真实服务器、macOS/Linux 与人工视觉验收待。详见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。 |
| 7 | 其他来源 | Plex 与网络视频来源/网络设备支持分别立项；内置 SMB/FTP/FTPS 连接挂载不能由已挂载目录替代。 |
| 7 | 集合、隐私与完整设置 | 智能/手动合集及封面、保险库/隐私锁、原版完整引导/主题/语言/设置，按原版模块拆分。 |
| 后续短批 | 鼠标与触控板 | 与键盘快捷键拆分；按原版动作、灵敏度、误触和跨平台行为另行实现/验收。 |
| 后续 | 音乐独立模块 | 统一实现本地/远程音乐浏览、分组、队列、播放；不提前把部分同步描述成音乐闭环。 |
| 后续新增 | WebDAV 设置备份 | 按已批准范围另行设计/实现/验收，不扩张成媒体源或自动双向同步。 |

## 每批固定完成标准

1. 对照原版 Swift/SwiftUI、连接器、依赖和测试；先列明该批功能边界与失败/取消行为。
2. 区分领域实现、平台接入、真实来源和用户可见页面；数据模型、feature flag 或配置字段不能单独算完工。
3. 每批提供相应自动化证据。Windows 自动化/Release/smoke 单列；真实 Emby/设备操作单列；macOS 原生、Linux 原生分别列证；原版 UI 视觉对照单列。
4. 清楚标出未执行/失败/不适用项；旧日期的验证数字保留原语境，不用它覆盖新代码，也不将单项通过泛化为全平台通过。

## 主要索引

- [共用视频播放器状态与专项索引](PLAYER_STATUS.zh-CN.md)
- [本地来源与索引](LOCAL_SOURCES.zh-CN.md)
- [Emby 视频流程](README.md#emby-视频)
- [首页模块](README.md#首页)
- [项目边界](PROJECT_SCOPE.zh-CN.md)
- [后续 WebDAV 设置云备份](CLOUD_SETTINGS_PLAN.zh-CN.md)

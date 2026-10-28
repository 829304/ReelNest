# ReelNest 已实现与未实现能力盘点（2026-10-23）

本盘点主要记录 2026-10-23 的阶段基线；2026-10-26 TMDB 本地电影元数据最新证据以阶段表及[专项计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)为准。

2026-10-27 更新：Plex 基础视频连接器已完成本阶段实现与 Windows 自动化验证；Plex 专属后端24/24、共享后端255/255、同步/UI 63项通过，前端2/2、Windows Native、analyze、427 Dart文件format、Windows Release和五秒smoke通过。组合日志有重叠，不重复累计；未运行全量Flutter测试，不使用真实Token。真实 Plex、macOS/Linux原生、人工视觉及辅助功能验收仍待，故不宣称整体产品验收完成。详细证据见[Plex 计划](PLEX_PLAN.zh-CN.md)。2026-10-26 Jellyfin 基础视频来源闭环已实现；共享协议定向 255/255、同步/界面组 61/61、Emby 基线 37/37、Jellyfin UI 2/2、Windows Native 真实 mpv 业务用例、Windows Release 和五秒 smoke 通过。各组分开记录、不累加；本批未跑全量 Flutter 测试。真实 Jellyfin、macOS/Linux 原生和人工视觉验收待完成。详细证据见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。

2026-10-27 P0 前端视觉状态：`LocalMediaCard` 悬浮阴影及评分胶囊已按原版 `PosterGridView.swift` / `HomeVividTokens` 修正；媒体卡视觉专项1/1、核心 UI 35/35、Jellyfin/Plex 前端4/4、全项目 analyze、Windows Release 40.9秒及五秒 smoke 通过（10:38:12 +08，窗口响应、正常关闭、exit 0）。人工复核首页/侧栏/媒体库/占位/评分/筛选正常；缺图占位内标题和卡片底部标题是原版设计，保留。详见[当前阶段 P0 记录](NEXT_STAGE.zh-CN.md#2026-10-27-p0-本地媒体卡视觉一致性修正windows-验证通过)。

2026-10-27 侧边栏状态卡 P0 第一、二批：原版 `SidebarStatusCenterCard` 部分迁移为固定底部 `SidebarStatusCard`、独立滚动菜单，已接入继续观看、真实缓存统计快照和任务完成提示；既有来源/健康状态只读，不因显示卡片额外探测磁盘/服务器。第二批专项20/20、首页/缓存/侧栏/健康联合117/117、analyze、diff-check、Windows Release 38.9秒和隐藏 smoke通过。仍未完整迁移音乐迷你控制、应用更新、保险库快捷锁定、赞赏提示、缺失/重复项专属卡、任务重试/取消等原版能力。详见[第二批记录](NEXT_STAGE.zh-CN.md#2026-10-27-侧边栏状态卡-p0-第二批部分迁移windows-验证通过)。

2026-10-27 P0 媒体网格绘制层级：`HoverLiftShadow` 以 `OverlayPortal` 显示主悬浮阴影，解决 SliverGrid 索引绘制下海报阴影被后绘制兄弟覆盖的问题；主卡片仍独立负责交互、焦点、tilt 和缩放。视觉专项最终2/2、跨来源组合最终63/63、analyze、diff-check、Windows Release 39.7秒及五秒 smoke通过。首次组合因退出断言少 pump 一帧失败，修正测试时序后最终63/63通过。此修正不代表工具栏/图标/全页面像素审计完成。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-27-p0-媒体网格悬浮阴影绘制层级修正)。

2026-10-27 媒体库主界面页头 P0：新增共享 `VideoLibraryPageHeader`，按 `LibraryView.swift` 调整标题簇、TV 图标几何/颜色与右侧动作对齐；Emby 视频库移除额外页头卡片/管理按钮、收窄搜索并恢复线性图标与原版副标题。保留 `AppAdaptiveControlBar` 原版双层表面，未改搜索/筛选/排序/同步/选择/服务器/持久化语义。四文件跨来源63 passed，另有媒体卡/侧栏/app 22 passed；format 0 changed、analyze clean、Windows Release 41.0秒及隐藏 smoke通过。未运行全量测试，未验真实来源可见 UI、实体输入、高 DPI、macOS/Linux 精确视觉；不代表全局 UI 已与原版一致。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-27-媒体库主界面-p0-页头对齐原版windows-验证通过)。

2026-10-27 公共逻辑提取分两批完成。第一批：原始偏好存储及串行任务/可取消等待工具，11个调用方减少103行、公共实现新增55行，净减48行；176项相关测试通过，analyze clean，Windows Release 47.4秒及20:10 +08五秒 smoke 通过。第二批：播放设置事务和 JSON 读取共用逻辑，目标文件净减62行；9个相关测试文件97/97通过（8秒）、analyze clean、format 0 changed，Windows Release 46.3秒；最终 smoke 于20:21:52 +08观测5秒，隐藏窗口响应、正常关闭、ExitCode 0。第二批 Release 与前端41秒构建分别记录。两批均保留业务差异，不代表全量测试、真实媒体验收或三平台验收。详情见[提取记录](COMMON_LOGIC_EXTRACTION_2026-10-27.zh-CN.md)。

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
| 本地视频来源与索引 | 文件夹、移动盘、已挂载 NAS 路径、自动监控/增量更新及当前四种可用来源的三步向导已接入；SourceRow 视觉仍待逐项对照，原版完整连接器集合仍有缺口 | 来源向导/策略定向与核心测试90/90、analyze 0 issues、Windows Release 41.9秒及五秒 smoke 通过；自动扫描独立证据见[本地来源](LOCAL_SOURCES.zh-CN.md) | 真实目录选择器、NAS/移动盘拔插仍待验收 | 原生行为及持久目录授权待验 | 原生行为待设备实测 | 来源主页 SourceRow 仍非完整原版逐像素/逐交互验收 |
| Emby 视频 | 连接、同步/浏览/详情/用户操作/播放与缓存等主要视频流程已接入 | 有大量分层自动化证据；详见[Emby 文档](README.md#emby-视频)及专项记录 | 真实 Emby 全流程仍待系统验收 | 未完成全平台验收 | 未完成全平台验收 | 原版逐页/逐交互视觉仍待 |
| Plex 基础视频来源 | 基础 server+Token、独立来源、浏览/搜索/详情、direct 播放及用户状态回写已实现；本地收藏语义已明确 | 前端2/2、Windows Native mpv单业务用例、Plex专属后端24/24、共享后端255/255、同步/UI 63项、Windows Release/smoke通过；组合日志276/276和85/85含重叠不重复累计 | 不使用真实 Token，真实 Plex 待后续 | 待验证 | 待验证 | 原版逐项视觉待验 |
| 原版视觉纠偏（第一批） | 新增可复用 `PointerInspectTilt`，海报与详情 hero 按 Swift `PointerInspectTiltModifier` 迁移；详情 hero 恢复直接 HStack/窄屏结构，海报边框渐变及收藏/书签独立按钮按原版对齐。媒体卡主悬浮阴影绘制层级已由后续 `HoverLiftShadow` 修正 | 专项16/16、跨来源 Emby/source/Jellyfin/Plex/TMDB 47/47；后续阴影视觉专项2/2、跨来源63/63最终通过；analyze clean、Windows Release 39.7秒、隐藏 smoke 通过 | Windows Release 已运行；未覆盖全页人工像素审计 | 待验证 | 待验证 | 阴影层级修正不等于工具栏/图标映射或全页面像素一致；SF Symbols/自定义图标和逐页尺寸颜色动效审计仍待 |
| 媒体库主界面页头 P0 | 共享 `VideoLibraryPageHeader` 对齐原版标题簇/TV 图标/动作基线；移除 Emby 页头额外卡片和管理按钮，恢复原版搜索尺寸、线性图标、副标题与窄布局轨道；保留原版双层筛选表面及全部业务语义 | 跨来源四文件63 passed；media_card_visual_parity + sidebar_status_card + app_test 22 passed；format 0 changed、analyze clean、Windows Release41.0秒、hidden smoke通过 | 未验证真实 Emby/Jellyfin/Plex 可见 UI、实体输入及高 DPI | 待验证 | 待验证 | 此次仅页头 P0 对齐；全局像素一致、其他页面精确视觉待 |
| 侧边栏状态卡（部分迁移） | `SidebarStatusCard` 固定在侧栏底部；菜单为独立 Expanded ListView。显示活动任务、离线/健康异常、轮换近期任务/来源摘要、继续观看首项、真实缓存统计及任务完成提示；只读观察快照，不新增磁盘/服务器探测 | 第一批 app_test17/17、交叉回归70/70；第二批专项20/20、首页/缓存/侧栏/健康联合117/117、analyze clean、Windows Release38.9秒、隐藏 smoke通过 | Windows自动化覆盖来源摘要/续播动作链路/缓存显示；不推定真实来源全流程人工验收 | 待验证 | 待验证 | 对照原版 `SidebarStatusCenterCard` 的部分迁移；音乐迷你控制、应用更新、保险库锁定、赞赏提示、缺失/重复项专属卡、失败重试/活动任务取消未迁移 |
| Jellyfin 基础视频来源 | 独立 kind/provider/凭据/URI；登录恢复、选库、浏览/搜索/详情、视频播放/音轨字幕/续播/切集/上报基础闭环已实现 | 定向分组 255/255、同步/界面 61/61、UI 2/2、Windows Native 真实 mpv、Release 44.1 秒及五秒 smoke 通过；本批未跑全量 | 真实 Jellyfin 服务未验 | Windows Native 基础链路通过 | macOS/Linux 原生待验 | 人工精确视觉待验 |
| 首页 | 影视 Hero、统计、剧集推荐、播放/最近/想看/收藏/新增/高分及运行状态、编排和搜索已接入；不等于完整公共浏览/集合系统 | 自动化和 Windows 验证见[首页文档](README.md#首页)及各优化记录 | 大库可见交互和真实来源组合仍待 | 原生性能/视觉待验 | 原生性能/视觉待验 | 原版逐项视觉仍待 |
| 共用视频播放器 | 本地/Emby 共用会话；大量基础、精确控制和高级画面/音频功能已接入 | 多个模块有 Windows Profile/native/Release 证据；见[播放器状态及专项索引](README.md#视频播放) | 真实 Emby、真实设备听感/硬解/HDR/长播等按项目分别待验 | 原生验收待 | 原生验收待 | 完整原版布局/图标/字体/材质/交互对照待 |
| 健康/任务/应用设置 | 健康评分与忽略恢复、失效路径/重复/详情缺口、扫描/分析/缓存任务中心已有接线 | 各模块有分层自动化及 Windows 证据 | 在线补资料修复未实现；通用原版后台任务/重试系统并未全部迁移 | 原生验收待 | 原生验收待 | 当前不是完整原版设置/引导 |
| 发布与平台支持 | Windows 便携存储、DPAPI、路径防逃逸及打包白名单已实现 | CI 有 Ubuntu check 与三桌面 build artifact workflow；build workflow 只由 main push/手动触发，Codex 分支 push 不自动 build | 当前 workflow 不调用 windows-smoke，也不运行原生播放器 Profile；没有三端全绿/实机结论 | 原生目录权限/稳定卷身份、构建及运行待 | 构建与运行验收待 | 三平台视觉/交互验收待 |

详细播放器功能及跨层证据见[共用视频播放器实现盘点](PLAYER_STATUS.zh-CN.md)和播放器专项文档；Emby 细节见[Emby 视频文档索引](README.md#emby-视频)。

## 来源与本地媒体闭环

### 当前接入范围

- 当前已交付的来源入口为 `localFolder`、Emby、Jellyfin 与 Plex 基础视频连接器；Jellyfin 保持独立来源身份并复用 Emby-compatible 协议实现。分组验证、Windows Native/Release/smoke 及未验边界见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。本地入口可使用移动盘及已经由操作系统挂载的 NAS 路径。
- 本地文件侧已有多选去重、部分成功、扫描队列/取消/错误、分类/阈值/隐藏属性、文件名和季集识别、NFO/本地资料/海报/背景、来源重定位、离线保护、索引安全清理；清理索引不删除用户媒体文件。
- 当前 `add_source_dialog` 已按原版三步结构提供来源选择、连接/目录与分类、设置/参与策略；当前类型为本地目录、Emby、Jellyfin、Plex。URL/网络位置/ReelNest Server 等当前未实现入口仍属迁移范围，不是永久删除。
- `source_providers` 中 `localFolder`、`removableDrive`、`mountedNas` 共用 `FileSourceAdapter`；Emby/Jellyfin 走远程连接器与 Emby-compatible 协议链路，按 kind 隔离身份并处理差异；Plex 独立协议连接器已实现基础视频闭环，前端/Windows Native、Plex专属后端24/24、共享后端255/255和同步/UI 63项、Windows Release/smoke均通过。组合日志276/276与85/85不重复累计。

### 明确未闭环

- 来源设置可选择并持久化元数据拉取/写回参与偏好；偏好保存不等同于相关执行链路的完整验收。TMDB 电影/剧集功能状态分别见[电影元数据计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)和[剧集元数据计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。
- macOS 的目录持久授权未接入且相关按钮禁用；macOS 当前没有可用的稳定卷 UUID 身份，不能笼统记成“待实机验证”。
- 内置 SMB/FTP/FTPS 网络设备连接与挂载未实现。“已挂载 NAS 路径可作为本地目录”不等于 ReelNest 内置网络设备支持。
- Jellyfin 基础视频来源闭环已实现；真实 Jellyfin、macOS/Linux 和人工 UI 视觉验收仍待。Plex 基础视频连接器已完成本阶段实现；真实服务与跨平台验收仍待。网络视频 URL 来源仍未实现。旧 Mlink router 仅为测试原型且 `enableLegacyMlink=false`，不构成 ReelNest Server 正式连接器或自有服务端。

### 自动监控与增量扫描（实现完成；平台/真实设备验收待）

全局间隔、逐来源参与、文件事件与周期扫描、增量队列、错误脱敏记录和保护性完整扫描已实现；Windows 定向 78/78、analyze、Release/smoke 通过。未运行全量测试、native Flutter drive、可见截图或真实 NAS/移动盘拔插。Windows 强制 `perDirectory` 用例不代表 Linux 原生验收；macOS/Linux 仍待设备实测，macOS 持久目录授权缺口未变。详见[本地来源文档](LOCAL_SOURCES.zh-CN.md#自动监控与增量更新2026-10-27windows-自动化release-验证通过)。

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
| 5c（Windows 定向交付验证通过；平台/真实公服验收待） | TMDB 本地剧集/动漫手动批量匹配 | 13文件160/160（41秒）、analyze clean4.8秒、44个变更 Dart 文件 format0 changed、diff-check通过；Windows Release52.7秒及五秒 smoke通过。首轮74/159为中间计数不累计。没有全量/native Flutter drive、真实TMDB公服、macOS/Linux、实体目录或可见UI验收；SourceRow未改，来源列表视觉对照未完成。详见[专项计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。 |
| 5d（Windows 定向交付验证通过；平台/真实公服验收待） | TMDB 本地剧集/动漫定时自动匹配 | 15文件179/179（48秒）、analyze clean4.4秒；Windows Release45.9秒，`data/app.so` 为2026-10-27 22:07:19 +08、13,239,176 bytes；五秒 hidden smoke 于22:08:29 +08响应、正常关闭、ExitCode 0。48个工作区变更 Dart 文件 format0 changed、diff-check通过。与手动批量160项有覆盖重叠，分批记录不累计。未跑全量/native Flutter drive、真实TMDB公服、macOS/Linux、可见UI或真实15分钟墙钟周期验收。详见[专项计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。 |
| 5e（Windows 定向交付验证通过；平台/实地视觉验收待） | 本地视频健康补充与 NFO 写回 | 定向15文件164/164（约9秒）、analyze无问题（3.9秒）、61个变更/新增 Dart 文件格式检查0更改、diff-check通过；覆盖 writer/policy/supplement、health UI、来源配置、TMDB与app回归，并验证 NFO 写入后读取及真实来源重扫恢复字段。此前失败/重复运行不累计。Windows Release44.3秒及五秒 hidden smoke通过（09:52:30 +08，响应/正常关闭/ExitCode 0）。仅本地电影、电视剧/动漫的健康一键补充可触发写回；默认关闭且要求来源参与元数据。索引先提交、NFO独立写入，失败保留索引并提示 warning，不是跨数据库/文件系统原子事务。普通单项/批量/定时匹配不写 NFO。macOS/Linux、真实 NAS/挂载与可见 UI 验收待。详见[阶段计划](LOCAL_VIDEO_METADATA_WRITEBACK_PLAN.zh-CN.md)。 |
| 6（基础闭环已实现；Windows 交付验证通过） | Jellyfin 基础视频连接器 | 共享协议 255/255、同步/界面组 61/61、独立 UI 2/2、Emby 基线 37/37、Windows Native 真实 mpv、Release/smoke 通过；本批未跑全量。真实服务器、macOS/Linux 与人工视觉验收待。详见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。 |
| 7（Plex 基础连接器已实现；Windows 自动验证通过） | Plex 视频来源闭环 | 独立 XML/`X-Plex-*` protocol、source identity 与本地 favorite 保护；Plex专属后端24/24、共享后端255/255、同步/UI 63项、前端2/2、Windows Native和Windows Release/smoke通过。组合报告有重叠，不重复累计。真实服务、macOS/Linux、人工视觉及辅助功能验收待。见[Plex 计划](PLEX_PLAN.zh-CN.md)。 |
| 8 | 其他来源 | 网络视频来源/网络设备支持分别立项；内置 SMB/FTP/FTPS 连接挂载不能由已挂载目录替代。 |
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

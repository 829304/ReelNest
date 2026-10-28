# 原版一致性核对清单

- 状态：Active
- 负责人：项目一致性与文档维护者
- 最后更新：2026-10-12
- 原版基线：`64f8ee258d87389414d5e06740a89f59cd857612`
- 权威范围：原版源码入口、模块迁移状态与一致性缺口

原仓库只读；不采用此前新增的系列摘要服务端接口。本表区分“找到入口”“读过规则”“已迁移”“已验证”“已完成原版对照”，文件存在、测试通过或构建成功均不代表功能/UI 完成。

命名约定：用户已明确新项目的自有服务端及来源入口为 **ReelNest Server**。原代码中的 MediaLIB Server 是其迁移出处，原路径、历史记录及兼容标识保留原名；产品文案采用新品牌。

## 当前模块摘要

| 模块 | 当前实现状态 | 主要一致性缺口 | 详细依据 |
|---|---|---|---|
| 桌面外壳与导航 | 首页、媒体源、仪表盘、设置及 Emby 来源树已接入 | 原版完整侧栏分组、状态/播放卡片、字体/材质、键盘和三端对照未完成 | [项目结构](../PROJECT_STRUCTURE.zh-CN.md)、下方源码盘点 |
| 首页视频 | H1 基础闭环、H2 推荐/搜索/状态、视频健康评分及 H3 布局编排已接入；照片墙按用户决定移除 | 音乐/网址/详情补全依赖、手动集合模块及三端原生/原版对照待完成 | [首页计划](../HOME_IMPLEMENTATION_PLAN.zh-CN.md)、[健康评分](../HEALTH_SCORE.zh-CN.md)、[编排](../HOME_LAYOUT_EDITOR.zh-CN.md)、[运行状态](../HOME_RUNTIME_STATUS.zh-CN.md)、[搜索记录](../HOME_SEARCH.zh-CN.md) |
| 本地媒体源 | 目录选择、扫描、索引、浏览、健康、三步来源向导及来源策略保存已接入 | `SourceRow` 原版逐像素/逐交互对照、来源策略执行服务的专项验收、macOS 持久授权、移动盘/NAS 和 macOS/Linux 原生实测仍待 | [本地来源](../LOCAL_SOURCES.zh-CN.md) |
| 本地视频播放器 | 播放、续播、字幕/音轨、队列和基础设置已接入；章节/书签、循环及逐帧底层与首批 UI 已接入 | 在线字幕、时间轴预览、片头片尾策略、剩余原版控制/窗口能力、macOS/Linux 原生及完整视觉待完成 | [播放器盘点](../PLAYER_STATUS.zh-CN.md)、[高级播放首批](../PLAYER_PRECISION_BACKEND.zh-CN.md) |
| Emby 视频 | 登录/选库、同步/浏览、详情、播放/状态、字幕、缓存/离线及批量操作已接入 | 真实 Emby 完整 V6、公共集合/分类依赖、三端原生和 UI 对照待完成 | [Emby 导航](../EMBY_NAVIGATION.zh-CN.md)、[平台矩阵](../PLATFORM_VERIFICATION_MATRIX.zh-CN.md) |
| Jellyfin | 原版入口和范围已确认 | 独立协议差异、连接/浏览/播放/状态及 UI 尚未迁移 | `EmbyService.swift` 及调用链 |
| Plex | 原版入口和范围已确认 | 地址/Token 认证、选库、浏览、播放和状态尚未迁移 | `PlexService.swift` |
| ReelNest Server | 品牌和可选来源边界已确认；旧 Mlink 试验隔离保留 | 正式服务端迁移、连接入口和完整原行为尚未迁移 | [Mlink 历史记录](../MLINK_CONNECTION.zh-CN.md) |
| 音乐 | 已有远程音乐同步数据必须保留 | 本地/远程浏览、分组、队列、播放、歌词和 UI 作为独立模块待迁移 | `MusicLibraryView.swift`、`MusicPlayerView.swift` 等 |
| 相册 | 2026-10-12 用户明确暂不实现，来源照片入口及首页照片墙已移除 | 移出当前计划与验收范围，恢复需用户重新确认；保留既有数据识别和隔离 | [项目范围](../PROJECT_SCOPE.zh-CN.md) |
| 公共搜索与集合 | 首页已有跨来源视频搜索；部分本机想看/评级已接入；照片搜索按用户决定排除 | 音乐/人物搜索、智能/手动集合和完整公共入口待迁移 | `GlobalSearchView.swift`、集合相关 View |
| 健康与任务 | 视频评分公式、概览、本地/Emby 核心检查、本地重复/详情缺口、忽略恢复及部分任务/缓存入口已接入 | 网址来源检查、音乐、详情修复/重复合并、公共任务中心、通知及完整 UI 待完成 | [健康评分](../HEALTH_SCORE.zh-CN.md)、`LibraryHealthCenterView.swift`、`BackgroundTaskCenterView.swift` |
| 设置与引导 | 主题、播放、缓存和部分来源设置已接入 | 原版完整设置、隐私锁、首次引导和云备份后续需求待迁移 | `SettingsView.swift`、`PrivacyLockView.swift`、`OnboardingView.swift` |
| UI 一致性总验收 | 已迁移部分参数和组件，存在组件自动化 | 所有模块均未完成 Windows/macOS/Linux 的 V7 总验收 | [平台矩阵](../PLATFORM_VERIFICATION_MATRIX.zh-CN.md) |

数据身份和持久化规则见[数据字典](../DATA_DICTIONARY.zh-CN.md)。模块进入开发或重大补齐时，使用[模块规格模板](../templates/MODULE_SPEC_TEMPLATE.zh-CN.md)逐项记录原版依据、规则、状态和验收证据。

## 历史审计记录

以下内容保留 2026-10-05 至 2026-10-10 的逐步核对过程。段落中的“本批”“当前”“未接入”只描述当时状态；当前实现结论以上方摘要和最新模块文档为准。

### 初始页面与依赖盘点

原路径相对 MediaLib 仓库；Flutter 路径相对 `apps/client/lib`。

| 模块 | 原入口/依赖 | Flutter 现状与待办 |
|---|---|---|
| 导航、侧栏、窗口 | `Sources/MediaLib/Views/ContentView.swift`、`NativeSidebarMaterialHost.swift` | `shell/` 仅有三项导航，需修正；本批只迁移桌面判定与最小内容尺寸，完整来源树、侧栏材质、状态中心未迁移 |
| 首页 | `Views/HomeView.swift`、`HomeVividComponents.swift` | `features/home/` 为临时入口，需按原版重做；未逐项审核首页行为 |
| 视频浏览/详情 | `Views/LibraryView.swift`、`PosterGridView.swift`、`DetailView.swift`、`EpisodeListView.swift` | `features/library/` 为 Mlink 试验，可复用部分数据解析；不代表独立客户端媒体库完成 |
| 视频集合与操作 | `Views/VideoSmartCollectionSheet.swift`、`VideoManualCollectionSheet.swift`、`VideoItemContextMenuItems.swift`、`VideoCacheMenuItems.swift` | 未迁移；待逐项审核规则 |
| 音乐 | `Views/MusicLibraryView.swift`、`MusicPlayerView.swift`、`MusicSmartPlaylistSheet.swift`、`MusicTagScraperSheet.swift` | 未迁移；歌词、队列、智能歌单、标签依赖仍需细分 |
| 相册 | `Views/AlbumLibraryView.swift`、`JustifiedPhotoGrid.swift`、`MediaImageViewer.swift`、`SystemPhotoLibraryView.swift` | 当前只有基础文件索引；原相册和系统照片库未迁移，跨平台差异待核对 |
| 媒体源 | `Views/SourcesView.swift`、`App/AppState.swift` | `features/sources/` 基础功能可用，但当前表单、来源行和连接状态仍不一致；见下表 |
| 扫描、索引 | `Sources/MediaLibCore/Models/MediaSource.swift`、`Services/MediaScanner.swift`、`FilenameParser.swift` | `domain/`、`sources/`、`storage/` 可复用；本批迁移过滤规则和成功清理语义，元数据/系列模型未完成 |
| Emby/Jellyfin | `Sources/MediaLib/App/EmbyService.swift` 及 AppState 调用链 | 未接入独立客户端；认证、选库、同步及限制状态待逐项迁移 |
| Plex | `Sources/MediaLib/App/PlexService.swift` | 未迁移；原来源配置用服务器地址和 Token，不能替换成账号密码表单 |
| 可选 ReelNest Server | 原 MediaLIB Server：`Sources/MediaLib/App/MlinkDiscoveryService.swift` 及原连接器调用链 | 新品牌已确定；服务端迁移和正式连接入口尚未完成，旧 Mlink 试验代码保留，不是应用运行前提 |
| 播放器 | `Views/PlayerView.swift`、`PlayerControllerSupport.swift`、`MpvMetalRenderer.swift`、`PlayerWindowActions.swift` | 未迁移；跨平台渲染和窗口适配待核对 |
| 健康、任务 | `Views/LibraryHealthCenterView.swift`、`BackgroundTaskCenterView.swift` | 本地文件健康/影视缺口、来源参与与忽略已接入；仪表盘仅本地监测区域，完整任务中心及其他健康分类仍未迁移 |
| 搜索、隐私、设置、引导 | `Views/GlobalSearchView.swift`、`PrivacyLockView.swift`、`SettingsView.swift`、`OnboardingView.swift` | 仅临时主题设置；其余待逐项审核与迁移 |
| 公共视觉 | `Views/DesignSystemTokens.swift`、`AppColors.swift`、`AppTheme.swift`、`AppButtonStyles.swift`、`VividIconLibrary.swift` | 少量参数已引用；Material 控件、临时图标、背景不算原版复刻 |

上表中 `Views/` 和 `App/` 缩写均位于 `Sources/MediaLib/` 下。非本批模块目前只定位入口，不能标为完整审计。

### 已阅读的导航与窗口规则

`ContentView.navigationRoot`：

- “媒体库”包含首页及视频分组。视频子项按 `visibleVideoSections` 产生，在看/未看/已看为页内筛选，不重复放进侧栏；没有视频时显示“暂无视频”。
- 视频分组还包含智能集合、手动集合与原创建入口。
- 音乐、相册按原可见条件显示；相册含全部/照片/录像。音乐含原分类及智能歌单。
- 每个远程来源有独立来源树，不能压成一个“服务器”页面。
- “管理”包含媒体源、片库健康、设置。侧栏底部保留状态/播放卡片。
- 侧栏宽度最小 236、理想 252、最大 272；条目字体 13.5/semibold，子项缩进 22，横纵内边距 10/9，圆角 12。仅抄渐变色不构成组件迁移。
- `MainWindowToolbarVisibilityGuard.minimumContentSize` 为 **1088×720** 内容逻辑尺寸；原生窗口框需额外计算。不存在按 760 宽度切换移动底栏的原规则。

本批将 Windows/macOS/Linux 选择桌面 Shell 与宽度解耦，并在三个原生 runner 设置最小内容尺寸。Windows 按当前 DPI 加上边框尺寸；首次创建也按内容尺寸计算。macOS/Linux 尚需在对应设备验收。

### 已阅读的媒体源与向导规则

| 部分 | 原行为 | 迁移状态 |
|---|---|---|
| 来源页面 | “添加媒体源…”、“扫描全部”；连接/断开两个分组；扫描进度与原空态 | 已接入页头操作和分组；来源主页 `SourceRow` 仍是过渡实现，原版逐像素/逐交互对照待完成 |
| 入口 | 原版包含本地目录、网络视频地址、网络设备、Emby、Jellyfin、Plex、原 MediaLIB Server | 当前向导开放已实现的本地目录、Emby、Jellyfin、Plex；URL、网络位置和 ReelNest Server 尚未接入。原版可选连接器仍在迁移范围内，不视为永久删除，也不显示为已完成 |
| 步骤 | 来源 → 连接/本地目录与分类 → 设置；URL 视频按原版跳过设置 | 当前已实现三步向导及对应上/下一步返回；未实现连接器不提供假成功 |
| 尺寸 | sheet 宽 620、最大高 680；正文滚动上限 460；来源卡最小宽 188/高 88 | 已接入向导步骤视觉；来源主页卡片和全页仍待原版逐项对照 |
| 本地连接 | 原生目录多选，按目录名自动命名；显示前 4 个目录名，剩余数量汇总 | 已接入 `getDirectoryPaths`、配置区域及步骤间返回；真实原生多选弹窗仍待实机验证 |
| 本地分类 | 自动、电影、电视剧、动漫、纪录片、综艺、其他视频、音乐、照片、其他、保险库 | 本地配置区域已接入分类与保存；SF Symbols 和保险库解锁/隐藏规则仍有缺口；照片入口遵循项目范围决议 |
| 添加多个目录 | 忽略已存在路径；无新路径时提示重复；新增来源进入扫描队列 | 批量保存/自动命名/去重/顺序扫描已接入；重复来源不覆盖原设置，部分失败与重试行为保持；真实原生多选弹窗仍待实机验证 |
| 参与策略 | 自动扫描、元数据、健康、优先写回；照片/家庭视频按既有约束规范化元数据选项 | 向导第三步可选择并持久化 `autoScan`、`includeInMetadataFetch`、`includeInHealthCheck`、`preferMetadataWriteToSource`；SourceOptions 无 schema 变化。保存策略不等同于相应元数据执行服务全部验收 |
| 本地来源设置 | 只有分类与参与策略；取消不写入，保存先关闭弹窗；空闲保存不自动扫描 | 策略可在向导设置页确认并保存；既有来源设置协调行为见实现状态文档，来源主页行视觉仍待逐项对照 |
| 远程策略 | 远程痕迹同步，原默认双向；Emby 选库列表 | 数据模型及持久化已迁移，执行服务/向导仍未接入 |
| 网络设备 | SMB/FTP/FTPS 先连接/挂载再选目录 | 待平台适配，不能从范围中删除 |

macOS 的 security-scoped bookmark 持久授权尚未完成；不能只存路径就开放为已完成的沙盒目录来源。

后续批次已接入本地扫描队列：一个活动来源、按次序处理等待来源、重复请求去重、失败后继续、扫描前重查可达性；多选添加/批量保存已接入该队列。可达性遵循 `FileAccessService.isReachableDirectory` 的目录存在性语义，当前在页面加载/恢复前台和扫描后异步刷新；原健康模块缓存与自动重新挂载尚未迁移。

`ui/widgets/source_icons.dart` 翻译 `VividTitleIcon.sourcesObj/sourceOnObj/sourceOffObj` 的 48×48 矢量路径、填色和双层光晕参数，及 `VividIconLibrary` 中所需线性路径。`source_page_sections.dart` 对照页头/分组布局；这不代表字体、系统材质、所有动效与完整来源行已通过 macOS 原版截图对比。

### 扫描规则与本批修改

依据 `FilenameParser.isMediaFile`、`MediaScanner.minimumFileSize`、`MediaScanner.scan`、`AppState.addSources`：

| 规则 | 本批结果 |
|---|---|
| 扩展名 | 完整搬入原视频、音频、图片集合；包括旧实现漏掉的 m2ts、rmvb、mka、caf、dng 等 |
| 默认/普通来源 | 自动来源接受视频/音频，不把海报图片当媒体；音乐来源仅音频，其他视频分类仅视频 |
| 相册 | 接受图片和视频，二者均无文件大小下限 |
| 大小 | 默认视频 50 MiB；音乐新源默认 512 KiB；扫描音频使用 `min(来源阈值, 512 KiB)`；等于阈值可入库 |
| 文件名解析 | 对照原 `FilenameParser` 清理标题/年份，支持 SxxExx、中文季集、EP/E 和季目录编号；电影分类不识别剧集，系列目录优先提供剧名 |
| 索引分类 | 替换全部视频临时归入 `homeVideo` 的实现；按原扫描器保存电影/剧集类型，音乐用曲目前缀清理，相册保留原名及 photo/homeVideo 类型 |
| 数据库 | 仅维护当前初始结构，包含分类/阈值、来源策略和必填的创建/更新时间；不维护开发中间版本兼容，不自动删除本机数据库 |
| 成功清理 | 完整成功扫描删除未发现的旧索引；不再新增“待找回”条目；不删除媒体文件 |
| 失败保护 | 逐文件提交，单文件失败继续并汇总错误；离线、取消、失败不清理旧索引，保留本次已成功导入条目 |
| 进度 | 清单总数、已处理、导入、跳过和错误；隐私来源不暴露当前路径和单文件错误详情；全局进度 UI 仍待迁移 |

**仍存在的扫描差异**：

- 文件名、年份与季集解析已接入并持久化；系列父条目/分类、NFO/本地图片、按季浏览已写入代码，最新一批尚未运行验收。标题订正历史、音频标签、照片完整元数据、截图回退和在线刮削仍未迁移，不称为完整元数据链路。
- 原版解析链接目标并去重；当前内部链接跳过。原平台隐藏属性、自然顺序遍历也未完整迁移。
- `autoScan`、本地文件监控和增量扫描已实现：全局间隔默认关闭、提供原版五档；逐来源参与开关、事件合并、结构变化/溢出完整扫描回退、周期扫描与现有队列均已迁移。Native watcher 错误会脱敏记录并触发保护性全扫。Windows 定向 78/78、analyze、Release/smoke 通过；全量/native Flutter drive、可见截图、真实 NAS/移动盘及 macOS/Linux 实机验收仍待。其他原版差异按[实现状态盘点](../IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md)逐项跟踪，包括来源主页 `SourceRow` 对照、解析链接目标并去重、原平台隐藏属性/自然顺序遍历、标题订正历史、音频标签等；不将已有 TMDB 或远程同步能力笼统记作未实现。
- 当前来源 ID/相对路径键和重新定位操作需继续与原身份、索引清理及播放记录模型核对。
- 对一个仍可读取的空挂载点，成功扫描清理规则会清空该来源索引。挂载状态判定必须继续对照原 `FileAccessService`；没有把 NAS/移动硬盘拔插场景标为已验收。

### 验收与后续顺序

测试参考原 `FilenameParserTests`、`MediaScannerFileCatalogIOTests` 的分类/尺寸样例，覆盖当前 SQLite 初始化与重开、真实目录边界过滤，并保留来源隔离、失败/取消、文件不删除回归。不保留历史 schema 或升级测试。

本批自动化结果在 `NEXT_STAGE.zh-CN.md` 记录。Dart 中切换三个目标平台的组件测试不等于三个操作系统实测。GitHub 构建矩阵已限于三个桌面端，尚未推送触发。

公共弹窗标题/分区/底部操作区已按 `AppColors.swift` 和 `DesignSystemTokens.swift` 翻译为独立组件，保留原尺寸、间距和分隔线参数；经典主题配色子集、主次按钮、分类胶囊已接入本地配置弹窗。完整向导、系统字体/符号、连续圆角、材质、弹簧动效及其他主题仍须迁移并对照验收。

接着完成：公共主题/控件与三步本地向导、目录多选/扫描队列 → 元数据规则与设置执行依赖 → macOS 持久目录访问 → 侧栏/来源树和来源行 → 原版运行截图及三平台验收。依赖未齐的项保持“未完成”，不把本批底层纠偏称为整个阶段完成。

### 已确认的原版缺陷与迁移要求

2026-10-08 用户明确：旧项目暂不修复，重构时避免再次引入。远程有界读取、离线缓存提交/替换和 FFmpeg 子进程管理的风险、源码依据与待执行回归见 [原版缺陷防引入清单](ORIGINAL_DEFECT_GUARDS.zh-CN.md)。这些项在对应模块迁移时验收，不改变当前本地媒体闭环 → Emby 的顺序，也不作为当前 Flutter 已存在缺陷或已修复问题统计。

### 本地来源设置接入（2026-10-08，验收待进行）

后续健康批次已开放健康参与开关，并通过来源变更事件取消/重算健康缓存。其余元数据拉取与写回继续禁用，下文保留设置初次迁移的 UI 缺口。

对照 `SourcesView.SourceSettingsSheet`：620×最大 700、正文最大 520、24 外内边距、16 分区间距、顶部/底部滚动留白 8/20；分类和策略分区沿原顺序。`AppSwitchToggleStyle` 使用 44×26 轨道、20 圆点、3 内距、10 标签间距，禁用透明度 .48；策略组内距 12、行距 10、圆角 16。标题采用 `VividTitleIconNameMapper` 的 slider → gear 映射及原 `gearObj` 几何，来源行设置图标采用原 sliders 路径。信息提示卡片采用原 24 图标圆底、9 间距、12/8 内距与 10 圆角。

本批仍有明确缺口：策略执行依赖未齐；SF Symbols 资源（包括信息卡片原盾牌）、完整主题、连续圆角、弹簧动效、保存按钮符号/键盘快捷操作、原来源行表面和通知方式仍待迁移/校验。信息卡片当前使用原 Vivid 映射中的 checkCircle；这是待补资源，不宣称与原直接使用的 SF Symbol 相同。无截图或三平台实机验收，静态参数迁移不代表 UI 一比一完成。

### 本地影视浏览接入（代码完成，验收待进行）

本批读取 `DetailView.swift`、`EpisodeListView.swift`、`PosterGridView.swift`、`GeneratedPlaceholderPalette.swift` 和 `DesignSystemTokens.swift` 后，将本地数据接到海报网格、详情和季集列表。网格使用原默认最小海报宽 150、列距 20、行距 30、2:3 视频/1:1 音乐裁剪、18 圆角与 12 标题内距；详情使用 210 宽竖海报、24 横向间距、18 内边距和 34 标题；季行高 40，单集缩略图 120×68、内距 10。多季折叠、单季平铺与 Escape 返回沿原交互实现，查询分页放在滚动加载内部。

这些代码参数不等于完整 UI 还原：系统字体/SF Symbols、材质、指针光效、海报检查倾斜、完整页头/筛选排序、详情元信息/操作条、封面实际比例、音乐和相册专用占位图、艺术照/背景展示、定位文件等仍有缺口。当前选中图标复用已有原矢量组件；尚未声称与原 SF Symbol 填充版本等同。观看状态、播放、收藏、订正、外部打开等依赖未迁移，不以无效操作冒充完成。用户本轮明确先做功能、稍后验收，未执行截图对比或三平台运行测试。

### Emby 视频导航增量（2026-10-10）

上述本地影视段落为历史记录；播放、观看和 Emby 收藏已在后续批次接入。本批又按 `ContentView.embySourceGroup` 与 `LibraryView.LibrarySnapshotBuilder` 接入来源树、分库、搜索、观看/类型筛选及 8 种适用排序；想看遵循本机保存，不使用 Emby 端点。目录/索引同事务，来源隔离和离线查询已验证。浅深色/三桌面目标的组件回归通过，但不是三操作系统原生或原版视觉验收。

保留待迁移项：完整公共分类、批量选择/右键、手动集合、缓存筛选、其他浏览布局/设置、SF Symbols/字体/材质/主题/动效，以及 CFStringTransform 全文字体系转写与地区排序。目前覆盖常见汉字拼音、英文首字母及数字自然排序；这些覆盖不能证明全部原语义等效，也不构成删除原能力的决定。完整证据和后续顺序见 [导航范围](../EMBY_NAVIGATION.zh-CN.md)。

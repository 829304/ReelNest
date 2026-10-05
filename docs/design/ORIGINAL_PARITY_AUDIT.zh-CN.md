# 原版一致性核对清单

日期：2026-10-05。原版基线：`64f8ee258d87389414d5e06740a89f59cd857612`。
原仓库只读；不采用此前新增的系列摘要服务端接口。本表区分“找到入口”“读过规则”“已迁移”“已验收”，文件存在不代表功能完成。

命名约定：用户已明确新项目的自有服务端及来源入口为 **ReelNest Server**。原代码中的 MediaLIB Server 是其迁移出处，原路径、历史记录及兼容标识保留原名；产品文案采用新品牌。

## 页面与依赖盘点

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
| 健康、任务 | `Views/LibraryHealthCenterView.swift`、`BackgroundTaskCenterView.swift` | 未迁移；当前扫描进度不能替代原任务中心 |
| 搜索、隐私、设置、引导 | `Views/GlobalSearchView.swift`、`PrivacyLockView.swift`、`SettingsView.swift`、`OnboardingView.swift` | 仅临时主题设置；其余待逐项审核与迁移 |
| 公共视觉 | `Views/DesignSystemTokens.swift`、`AppColors.swift`、`AppTheme.swift`、`AppButtonStyles.swift`、`VividIconLibrary.swift` | 少量参数已引用；Material 控件、临时图标、背景不算原版复刻 |

上表中 `Views/` 和 `App/` 缩写均位于 `Sources/MediaLib/` 下。非本批模块目前只定位入口，不能标为完整审计。

## 已阅读的导航与窗口规则

`ContentView.navigationRoot`：

- “媒体库”包含首页及视频分组。视频子项按 `visibleVideoSections` 产生，在看/未看/已看为页内筛选，不重复放进侧栏；没有视频时显示“暂无视频”。
- 视频分组还包含智能集合、手动集合与原创建入口。
- 音乐、相册按原可见条件显示；相册含全部/照片/录像。音乐含原分类及智能歌单。
- 每个远程来源有独立来源树，不能压成一个“服务器”页面。
- “管理”包含媒体源、片库健康、设置。侧栏底部保留状态/播放卡片。
- 侧栏宽度最小 236、理想 252、最大 272；条目字体 13.5/semibold，子项缩进 22，横纵内边距 10/9，圆角 12。仅抄渐变色不构成组件迁移。
- `MainWindowToolbarVisibilityGuard.minimumContentSize` 为 **1088×720** 内容逻辑尺寸；原生窗口框需额外计算。不存在按 760 宽度切换移动底栏的原规则。

本批将 Windows/macOS/Linux 选择桌面 Shell 与宽度解耦，并在三个原生 runner 设置最小内容尺寸。Windows 按当前 DPI 加上边框尺寸；首次创建也按内容尺寸计算。macOS/Linux 尚需在对应设备验收。

## 已阅读的媒体源与向导规则

| 部分 | 原行为 | 迁移状态 |
|---|---|---|
| 来源页面 | “添加媒体源…”、“扫描全部”；连接/断开两个分组；扫描进度与原空态 | 已接入页头操作和分组；卡片、进度和空态材质仍待完整迁移 |
| 入口 | 本地目录、网络视频地址、网络设备、Emby、Jellyfin、Plex、原 MediaLIB Server | 7 个入口均属迁移范围；最后一项在新项目命名为 ReelNest Server，当前三类文件下拉框需替换 |
| 步骤 | 来源 → 连接 → 设置；URL 视频跳过设置 | 待迁移，不能给未接入连接器假成功 |
| 尺寸 | sheet 宽 620、最大高 680；正文滚动上限 460；来源卡最小宽 188/高 88 | 已核对，尚未改写当前 Dialog |
| 本地连接 | 原生目录多选，按目录名自动命名；显示前 4 条路径，剩余数量汇总 | 当前只有单选与手输名称，需修正；已确认安装的 file_selector 有 `getDirectoryPaths` API |
| 本地分类 | 自动、电影、电视剧、动漫、纪录片、综艺、其他视频、音乐、照片、其他、保险库 | 来源分类模型已添加；向导未接入，不能因此声称分类 UI 已完成 |
| 添加多个目录 | 忽略已存在路径；无新路径时提示重复；新增来源进入扫描队列 | 尚未迁移批量保存/原队列规则 |
| 参与策略 | 元数据、健康、优先写回；相册/其他视频隐藏元数据选项且添加时不参与 | 对应业务模块未迁移，不显示无效开关充数 |
| 远程策略 | 远程痕迹同步，原默认双向；Emby 选库列表 | 未迁移 |
| 网络设备 | SMB/FTP/FTPS 先连接/挂载再选目录 | 待平台适配，不能从范围中删除 |

macOS 的 security-scoped bookmark 持久授权尚未完成；不能只存路径就开放为已完成的沙盒目录来源。

后续批次已接入本地扫描队列：一个活动来源、按次序处理等待来源、重复请求去重、失败后继续、扫描前重查可达性。多选添加/批量保存仍未接入。可达性遵循 `FileAccessService.isReachableDirectory` 的目录存在性语义，当前在页面加载/恢复前台和扫描后异步刷新；原健康模块缓存与自动重新挂载尚未迁移。

`ui/widgets/source_icons.dart` 翻译 `VividTitleIcon.sourcesObj/sourceOnObj/sourceOffObj` 的 48×48 矢量路径、填色和双层光晕参数，及 `VividIconLibrary` 中所需线性路径。`source_page_sections.dart` 对照页头/分组布局；这不代表字体、系统材质、所有动效与完整来源行已通过 macOS 原版截图对比。

## 扫描规则与本批修改

依据 `FilenameParser.isMediaFile`、`MediaScanner.minimumFileSize`、`MediaScanner.scan`、`AppState.addSources`：

| 规则 | 本批结果 |
|---|---|
| 扩展名 | 完整搬入原视频、音频、图片集合；包括旧实现漏掉的 m2ts、rmvb、mka、caf、dng 等 |
| 默认/普通来源 | 自动来源接受视频/音频，不把海报图片当媒体；音乐来源仅音频，其他视频分类仅视频 |
| 相册 | 接受图片和视频，二者均无文件大小下限 |
| 大小 | 默认视频 50 MiB；音乐新源默认 512 KiB；扫描音频使用 `min(来源阈值, 512 KiB)`；等于阈值可入库 |
| 数据库 | schema 1 → 2 增加分类/阈值；旧记录补原默认值，保留 ID、原设置、扫描时间与现有索引，不自动重扫 |
| 成功清理 | 完整成功扫描删除未发现的旧索引；不再新增“待找回”条目；不删除媒体文件 |
| 失败保护 | 离线、取消、失败不清理旧索引；当前仍为批次暂存后整体发布 |

**仍存在的扫描差异**：

- 原版逐文件导入，单文件失败继续处理，取消/失败可能保留已导入的新条目；当前失败即停止并丢弃本次暂存。待迁移逐文件结果/错误汇总与进度模型，不能把当前原子发布称为原版完全一致。
- 文件名、年份、季集、系列归组、NFO、本地海报、音频标签、照片 EXIF、截图回退未迁移；当前视频仍临时归入 `homeVideo`。
- 原版解析链接目标并去重；当前内部链接跳过。原平台隐藏属性、自然顺序遍历也未完整迁移。
- `autoScan`、文件监控、增量扫描、元数据/健康策略、写回与远程同步尚未接入。本批只持久化实际应用的分类和阈值，没有补一组不生效的 UI 开关。
- 当前来源 ID/相对路径键和重新定位操作需继续与原身份、索引清理及播放记录模型核对。
- 对一个仍可读取的空挂载点，成功扫描清理规则会清空该来源索引。挂载状态判定必须继续对照原 `FileAccessService`；没有把 NAS/移动硬盘拔插场景标为已验收。

## 验收与后续顺序

测试参考原 `FilenameParserTests`、`MediaScannerFileCatalogIOTests` 的分类/尺寸样例，新增 SQLite 实际 v1 文件升级与重开、真实目录边界过滤，并保留来源隔离、失败/取消、文件不删除回归。

本批自动化结果在 `NEXT_STAGE.zh-CN.md` 记录。Dart 中切换三个目标平台的组件测试不等于三个操作系统实测。GitHub 构建矩阵已限于三个桌面端，尚未推送触发。

接着完成：来源模型剩余规则与扫描结果模型 → 三步本地向导和目录多选/扫描队列 → macOS 持久目录访问 → 原公共组件、侧栏/来源树和来源行 → 原版运行截图及三平台验收。依赖未齐的项保持“未完成”，不把本批底层纠偏称为整个阶段完成。

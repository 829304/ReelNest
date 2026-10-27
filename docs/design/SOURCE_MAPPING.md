# 原版界面源码映射

2026-10-05：下表保留实际已写代码的来源记录，其中 Mlink/MediaLib Server 对应项属于此前方向错误的试验，不代表目标产品依赖服务端。功能与 UI 必须逐模块同时对照原版验收；当前页面不构成产品基线。新增[原版一致性核对清单](ORIGINAL_PARITY_AUDIT.zh-CN.md)记录已核对规则、落地代码和缺口；其状态优先于下表历史描述。

基线：MediaLib `64f8ee258d87389414d5e06740a89f59cd857612`。迁移以源码为主要依据；截图仅用于核对最终效果。

| 原版源码 | Flutter 文件（相对 apps/client/lib） | 本轮范围 |
|---|---|---|
| `PlexService.swift` / `AppState.connectPlexServer` / `SourcesView.swift` / `PlexServiceMetadataIDTests.swift` | `api/plex/plex_client.dart` / `plex_item.dart`，共享来源仓储与播放器 | 2026-10-27 基础视频闭环已实现；独立 XML 和 X-Plex 认证，收藏在本机保留；Windows 自动化、Release/smoke 通过。真实 Plex、macOS/Linux 和人工验收待，见[Plex 计划](../PLEX_PLAN.zh-CN.md) |
| `MediaSource.swift`、`SourceRepository.swift` | `domain/media_source.dart`、`features/sources/data/source_repository.dart`、`storage/library_database.dart` | 来源 ID、扫描配置、本地索引持久化；不复用旧数据库文件或旧 schema |
| `MediaScanner.swift` | `sources/filesystem/file_source_adapter.dart` | 基础遍历、格式过滤、递归与点号文件选项、取消/失败保护；尚未迁移元数据、NFO、缩略图和剧集解析 |
| `SourcesView.swift`：来源添加、扫描与移除 | `features/sources/presentation/` | 新的媒体源入口、目录选择、进度、重新定位与索引浏览；原版完整样式尚未还原 |
| `Sources/MediaLib/Views/DesignSystemTokens.swift`：AppSpacing、AppRadius、AppTypeScale、AppControlMetrics、AppMotion | `ui/theme/design_tokens.dart` | 页边距、控件/卡片/面板圆角、字号、控件高度与动画层级；SwiftUI spring 以保持层级关系的 Flutter duration 适配 |
| `Sources/MediaLib/Views/AppColors.swift`：普通页面语义色 | `ui/theme/app_palette.dart`、`ui/theme/app_theme.dart`、`ui/theme/design_tokens.dart` | 普通页面浅/深色语义角色、表面、边框、文字、悬停、搜索及强调渐变；音乐模块未来使用其独立主题，不在此混用 |
| `Sources/MediaLib/Views/ContentView.swift`：SidebarMetrics、SidebarBrandHeader、SidebarSelectionPill、SidebarRowButtonStyle | `shell/desktop_shell.dart`、`shell/sidebar_components.dart` | 默认宽 252，可拖拽限制在 236–272；品牌字号 16/11、Logo 38、间距 11、选中/悬停/按压/键盘焦点状态；Logo 使用用户 2026-10-13 指定的 ReelNest 品牌资源 |
| `Sources/MediaLib/Views/ContentView.swift`：导航和 Emby 来源分组 | `app/router.dart`、`shell/app_shell.dart`、`features/sources/presentation/emby_sidebar.dart` | 桌面媒体库/管理分区、Emby 来源折叠、数量与子库选中状态；音乐按既定后续大模块推进，照片入口按 2026-10-12 范围决定移除 |
| 原版无对应移动应用外壳 | `shell/mobile_shell.dart` | 新增窄屏适配，后续随页面迁移调整 |
| `Sources/MediaLib/Views/SourcesView.swift`：remoteConfiguration、credentialNote、primaryActionTitle | `features/servers/presentation/servers_page.dart` | 沿用服务器地址、用户名、密码顺序，字段间距 12，“登录并同步”动作；本轮把连接步骤放在独立页面，未迁移来源类型选择及参与策略向导 |
| `Sources/MediaLib/App/AppState.swift`：`connectJellyfinServer` → `connectRemoteMediaServer(provider: .jellyfin)`；`EmbyService.swift`、`SourcesView.swift`、`ContentView.swift` | `domain/media_source.dart`、`api/emby/`、`features/sources/data/emby_*`、来源连接/侧栏 UI | 2026-10-26 基础视频连接器已实现并完成定向验证及 Windows Release/smoke；保留独立 Jellyfin kind/provider/credential/`jellyfin://source` 和中性错误文案。真实 Jellyfin、macOS/Linux 与人工 UI 视觉验收仍待，见[Jellyfin 计划](../JELLYFIN_PLAN.zh-CN.md)。内部历史 Emby 类名不代表用户界面展示 Emby |
| `Sources/MediaLib/App/MlinkAPIClient.swift`：discover、login、refresh、libraryCategories、browse | `api/mlink/mlink_client.dart`、`api/mlink/mlink_codec.dart`、`api/mlink/media_codec.dart` | v1 请求与响应契约、Bearer 鉴权、原生请求头及分页；不接入设置与播放请求 |
| `Sources/MediaLibServerProtocol/ServerProtocolModels.swift`：MlinkServerDescriptor、ServerLibraryCategoriesResponse | `domain/server_connection.dart`、`domain/library_catalog.dart` | 分类标识、名称、数量与视频分组计数；保留字段语义，不把视频分组数当分类总数 |
| `Sources/MediaLibServer/ServerAuthenticationHTTPHandler.swift`、`HTTPRequestSecurityPolicy.swift` | `features/servers/data/server_repository.dart` | 对照登录/刷新错误与 token 交付方式；原生退出缺少协议支持，因此只清除本机凭据 |
| `Sources/MediaLib/Views/PosterGridView.swift`：PosterGridList、PosterCardView；`AppSettings.swift`：posterMinWidth | `features/library/presentation/browse_page.dart`、`media_card.dart` | 最小列宽 150、列间距 20、行间距 30；海报 2:3、音乐 1:1、圆角 18、标题 14 加粗、底部渐变、悬停放大 1.018；增加键盘焦点边框，尊重减少动画设置 |
| `Sources/MediaLib/Views/DetailView.swift`：hero、seasonGroups、episodeHeader | `features/library/presentation/media_detail_page.dart` | 海报宽 210/横图 320、圆角 12、内容间距 24、标题 34/600、元数据标签、简介、季集区域；移动端改为纵向排布 |
| `Sources/MediaLib/Views/PosterGridView.swift`：2:3 海报卡、渐变标题、播放进度、评分、悬停徽章/缩放/阴影 | `features/sources/presentation/local_media_artwork.dart` | 2026-10-13 Emby/来源视频海报卡增量；保留选择模式和图片子树缓存，数据/操作行为不变 |
| `Sources/MediaLib/Views/LibraryView.swift`：媒体库工具栏、筛选和加载/错误/空状态 | `features/sources/presentation/emby_video_library_page.dart` | 2026-10-13 Emby 视频库响应式表面与状态面板分组；业务文案、操作和数据规则不变 |
| `Sources/MediaLib/Views/DetailView.swift`：详情头图/海报、标题操作区、元数据、简介/类型和剧集行 | `features/sources/presentation/local_media_detail_page.dart` | 2026-10-13 本地与 Emby 共用详情页布局、装饰与信息层级增量；播放、Emby 与缓存操作保持 |
| `PlayerView.swift`：`PlayerMarkerButton`、`PlayerMarkerPopover`、`VideoProgressScrubber`、精确播放右键菜单与默认快捷键 | `features/playback/presentation/video_player_page.dart`、`player_precision_controls.dart`、`player_track_popovers.dart`、`player_visuals.dart` | 章节/书签弹层与时间轴刻度、单片循环、A–B 指示与提示、前后逐帧、右键入口、B/Shift+B/逗号/句号/Home；完整右键菜单其余项目和像素级视觉验收仍待迁移 |
| `ServerLibraryHTTPHandler.swift`、`ServerDiscoveryHTTPHandler.swift`、`ServerProtocolModels.swift`、`ServerLibraryCatalog.swift` | `domain/media.dart`、`api/mlink/media_codec.dart`、`features/library/application/library_providers.dart` | 条目、详情、单集上下文及按季分页；独立服务端分支新增系列摘要 JSON，客户端按 series-detail 能力选择，见 SERIES_API.zh-CN.md |
| `ServerArtworkHTTPHandler.swift`、`ServerArtworkThumbnailer.swift` | `features/library/data/artwork_repository.dart`、`presentation/authenticated_artwork.dart` | 同源 poster?size=320、Bearer 头、图片字节缓存、占位/重试；不使用原版的本地海报文件路径 |

首页与分类页已接入浏览导航。公共 `features/library/presentation/browse_page.dart` 海报墙、列表和详情按上表迁移：该浏览列表接口不含社区评分，因此不显示伪造评分；详情仅在响应包含 communityRating 时显示 10 分制评分，不能用 5 分制 userPreference.rating 代替。Emby 来源专用视频库及本地/Emby 共用详情另由本表 2026-10-13 新增映射覆盖，Emby 海报卡评分读取既有 `remote.rating`。各页面 Windows 构建及部分导航/布局冒烟通过，但整体仍未完成原版视觉对照。原版的完整 3D 悬停、玻璃材质与交互验收尚未完成。设置页仍只有会话内主题选择。用户 2026-10-13 指定的 ReelNest Logo 已接入侧栏品牌位、Windows ICO、macOS AppIcon 多尺寸资源及 Linux GTK 窗口/发行资源；移动端图标不在本批范围。

后续每个页面先阅读对应 SwiftUI View、子组件、状态和事件处理，再迁移成 Dart；在本表记录来源及有意调整，最后使用截图和交互验证对照。玻璃材质、原生窗口效果不能仅靠颜色近似即宣称等价。

2026-10-10 Emby 视频导航增量：`ContentView.embySourceGroup/SidebarMetrics` → `features/sources/presentation/emby_sidebar.dart`；`LibraryView.LibrarySnapshotBuilder/availableSortModes/selectSortMode` → `features/sources/domain/emby_library.dart`、`presentation/emby_video_library_page.dart`；`AppState.items/searchFields/toggleWatchlist` → `data/emby_library_repository.dart`。库目录与同步索引共同提交，原排序/阈值/目的地隔离规则已接入。常用中文拼音/英文首字母、数字自然排序已验证；CFStringTransform 的全部文字转写、地区排序、完整分类、批量操作以及系统菜单/符号/材质仍待等效迁移和视觉验收，详见 [本批边界](../EMBY_NAVIGATION.zh-CN.md)。

2026-10-10 画质与缓存增量：`RemoteVideoQualityPlanner` → `api/emby/emby_quality.dart`；`PlayerQualityPopover/qualityButton` → `player_track_popovers.dart` / `video_player_page.dart`；`MpvPlayerController.switchVideoQuality/seek` → `PlaybackSession`；远程图片缓存和手动视频缓存 → `emby_cache_repository.dart` / `emby_download.dart`，原离线菜单及设置 → `emby_cache_actions.dart` / `video_cache_settings.dart`。保留原默认预算与清理规则，避免旧项目 D1/D2/D3。自动离线订阅已在下一批接入；完整图片内存/预解码协调、公共菜单及图标/材质的像素验收仍待迁移，见 [本批说明](../EMBY_QUALITY_CACHE.zh-CN.md)。


2026-10-10 自动离线订阅增量：`VideoOfflineSubscription/VideoOfflinePolicy` → `domain/emby_offline_subscription.dart`；原订阅仓储和 AppState 维护 → `emby_offline_repository.dart`；`VideoCacheMenuItems/VideoOfflineSubscriptionLimitSheet` → `emby_offline_menu.dart`；`BackgroundTaskCenterView/LibraryHealthCenterView.storageCard` → `emby_task_center.dart`。Wi-Fi 出口条件由 `platform/network_status.dart` 适配，未知状态不放行。保留原选集窗口、暂停/到期及文件保留规则；不声称其他后台作业、完整视觉或三系统网络环境已验收，见 [订阅说明](../EMBY_OFFLINE_SUBSCRIPTIONS.zh-CN.md)。

| 原版源码 | ReelNest 位置 | 本轮映射 |
|---|---|---|
| VideoItemContextMenuItems.swift / VideoCacheMenuItems.swift | emby_video_context_menu.dart / emby_cache_actions.dart / emby_offline_menu.dart | 海报/单集右键、观看/想看/喜欢/评级/历史和缓存；公共集合/封面依赖另行迁移 |
| LibraryView.swift / SelectionStore.swift / AppState+BatchSelection.swift | emby_video_library_page.dart / emby_library_selection_bar.dart / emby_library_repository.dart | 多选、可见范围全选、原版批量栏、事务和索引移除确认 |
| AppColors.swift ArtworkImageCache / ArtworkDecodeCoordinator | artwork_image_pipeline.dart / artwork_decode_queue.dart | 512 MiB/1800 张、稳定版本键、3 路解码、4 路两行预热 |

2026-10-10 Emby 评级/分类增量：EmbyService.normalizedProviderRating/seedUserRating → domain/remote_media_policy.dart 的 RemoteRatingPolicy；RemoteLibraryClassificationPolicy / AppState.classifiedEmbyTopLevelItem → RemoteLibraryClassificationPolicy / IndexedMedia.displayType。同步元数据保存 collectionType，补建系列继承题材，初始评级统一换算；原始播放类型和父子关系保持不变。原版依据及验证边界见 [评级与分类](../EMBY_CLASSIFICATION_RATING.zh-CN.md)，首页/公共分类页仍待消费投影。

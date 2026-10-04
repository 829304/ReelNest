# 原版界面源码映射

基线：MediaLib `64f8ee258d87389414d5e06740a89f59cd857612`。迁移以源码为主要依据；截图仅用于核对最终效果。

| 原版源码 | Flutter 文件（相对 apps/client/lib） | 本轮范围 |
|---|---|---|
| `Sources/MediaLib/Views/DesignSystemTokens.swift`：AppSpacing、AppRadius、AppTypeScale | `ui/theme/design_tokens.dart` | 页边距 32/28、控件圆角 12、卡片圆角 16、字号 30/17/13 |
| `Sources/MediaLib/Views/AppColors.swift`：refIconGlyph、refCardBorder、refTitleText、refSecondaryText | `ui/theme/app_theme.dart`、`ui/theme/design_tokens.dart` | 浅色语义色基础；深色为临时适配，尚未迁移完整主题解析器 |
| `Sources/MediaLib/Views/ContentView.swift`：SidebarMetrics、SidebarBrandHeader、SidebarSelectionPill | `shell/desktop_shell.dart` | 侧栏宽 252、品牌字号 16/11、图标 38、间距 11、选中渐变和描边透明度 |
| `Sources/MediaLib/Views/ContentView.swift`：导航和来源分组 | `app/router.dart`、`shell/app_shell.dart` | 当前仅初始化导航；视频、音乐、照片、来源树与展开状态尚未迁移 |
| 原版无对应移动应用外壳 | `shell/mobile_shell.dart` | 新增窄屏适配，后续随页面迁移调整 |
| `Sources/MediaLib/Views/SourcesView.swift`：remoteConfiguration、credentialNote、primaryActionTitle | `features/servers/presentation/servers_page.dart` | 沿用服务器地址、用户名、密码顺序，字段间距 12，“登录并同步”动作；本轮把连接步骤放在独立页面，未迁移来源类型选择及参与策略向导 |
| `Sources/MediaLib/App/MlinkAPIClient.swift`：discover、login、refresh、libraryCategories、browse | `api/mlink/mlink_client.dart`、`api/mlink/mlink_codec.dart`、`api/mlink/media_codec.dart` | v1 请求与响应契约、Bearer 鉴权、原生请求头及分页；不接入设置与播放请求 |
| `Sources/MediaLibServerProtocol/ServerProtocolModels.swift`：MlinkServerDescriptor、ServerLibraryCategoriesResponse | `domain/server_connection.dart`、`domain/library_catalog.dart` | 分类标识、名称、数量与视频分组计数；保留字段语义，不把视频分组数当分类总数 |
| `Sources/MediaLibServer/ServerAuthenticationHTTPHandler.swift`、`HTTPRequestSecurityPolicy.swift` | `features/servers/data/server_repository.dart` | 对照登录/刷新错误与 token 交付方式；原生退出缺少协议支持，因此只清除本机凭据 |
| `Sources/MediaLib/Views/PosterGridView.swift`：PosterGridList、PosterCardView；`AppSettings.swift`：posterMinWidth | `features/library/presentation/browse_page.dart`、`media_card.dart` | 最小列宽 150、列间距 20、行间距 30；海报 2:3、音乐 1:1、圆角 18、标题 14 加粗、底部渐变、悬停放大 1.018；增加键盘焦点边框，尊重减少动画设置 |
| `Sources/MediaLib/Views/DetailView.swift`：hero、seasonGroups、episodeHeader | `features/library/presentation/media_detail_page.dart` | 海报宽 210/横图 320、圆角 12、内容间距 24、标题 34/600、元数据标签、简介、季集区域；移动端改为纵向排布 |
| `ServerLibraryHTTPHandler.swift`、`ServerDiscoveryHTTPHandler.swift`、`ServerProtocolModels.swift`、`ServerLibraryCatalog.swift` | `domain/media.dart`、`api/mlink/media_codec.dart`、`features/library/application/library_providers.dart` | 条目、详情、单集上下文及按季分页；独立服务端分支新增系列摘要 JSON，客户端按 series-detail 能力选择，见 SERIES_API.zh-CN.md |
| `ServerArtworkHTTPHandler.swift`、`ServerArtworkThumbnailer.swift` | `features/library/data/artwork_repository.dart`、`presentation/authenticated_artwork.dart` | 同源 poster?size=320、Bearer 头、图片字节缓存、占位/重试；不使用原版的本地海报文件路径 |

首页与分类页已接入浏览导航。海报墙、列表和详情已按上述源码编写，但尚未运行或视觉验证。原版的 3D 悬停、批量选择、完整玻璃材质、右键操作尚未迁移；列表接口不含社区评分，因此卡片不显示伪造评分。详情仅在响应包含 communityRating 时显示 10 分制评分，不能用 5 分制 userPreference.rating 代替。设置页仍只有会话内主题选择，平台启动图标保留模板。

后续每个页面先阅读对应 SwiftUI View、子组件、状态和事件处理，再迁移成 Dart；在本表记录来源及有意调整，最后使用截图和交互验证对照。玻璃材质、原生窗口效果不能仅靠颜色近似即宣称等价。

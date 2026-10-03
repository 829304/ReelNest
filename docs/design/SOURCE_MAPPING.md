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
| `Sources/MediaLib/App/MlinkAPIClient.swift`：discover、login、refresh、libraryCategories | `api/mlink/mlink_client.dart`、`api/mlink/mlink_codec.dart` | 迁移 v1 请求与响应契约、Bearer 鉴权及原生客户端请求头；本轮不接入媒体条目、设置与播放请求 |
| `Sources/MediaLibServerProtocol/ServerProtocolModels.swift`：MlinkServerDescriptor、ServerLibraryCategoriesResponse | `domain/server_connection.dart`、`domain/library_catalog.dart` | 分类标识、名称、数量与视频分组计数；保留字段语义，不把视频分组数当分类总数 |
| `Sources/MediaLibServer/ServerAuthenticationHTTPHandler.swift`、`HTTPRequestSecurityPolicy.swift` | `features/servers/data/server_repository.dart` | 对照登录/刷新错误与 token 交付方式；原生退出缺少协议支持，因此只清除本机凭据 |

首页已增加媒体库入口，服务器页已编写登录与会话管理，媒体库页按服务端分类响应呈现只读卡片。这些代码尚未运行验证；分类列表是本轮新增的最小业务页面，不宣称与原版完整媒体浏览界面等价。设置页只提供会话内主题选择。当前图标使用 Flutter 提供的通用图标，平台启动图标保留模板，后续独立设计品牌资源。

后续每个页面先阅读对应 SwiftUI View、子组件、状态和事件处理，再迁移成 Dart；在本表记录来源及有意调整，最后使用截图和交互验证对照。玻璃材质、原生窗口效果不能仅靠颜色近似即宣称等价。

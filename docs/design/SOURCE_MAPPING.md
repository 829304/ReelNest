# 原版界面源码映射

基线：MediaLib `64f8ee258d87389414d5e06740a89f59cd857612`。迁移以源码为主要依据；截图仅用于核对最终效果。

| 原版源码 | Flutter 文件（相对 apps/client/lib） | 本轮范围 |
|---|---|---|
| `Sources/MediaLib/Views/DesignSystemTokens.swift`：AppSpacing、AppRadius、AppTypeScale | `ui/theme/design_tokens.dart` | 页边距 32/28、控件圆角 12、卡片圆角 16、字号 30/17/13 |
| `Sources/MediaLib/Views/AppColors.swift`：refIconGlyph、refCardBorder、refTitleText、refSecondaryText | `ui/theme/app_theme.dart`、`ui/theme/design_tokens.dart` | 浅色语义色基础；深色为临时适配，尚未迁移完整主题解析器 |
| `Sources/MediaLib/Views/ContentView.swift`：SidebarMetrics、SidebarBrandHeader、SidebarSelectionPill | `shell/desktop_shell.dart` | 侧栏宽 252、品牌字号 16/11、图标 38、间距 11、选中渐变和描边透明度 |
| `Sources/MediaLib/Views/ContentView.swift`：导航和来源分组 | `app/router.dart`、`shell/app_shell.dart` | 当前仅初始化导航；视频、音乐、照片、来源树与展开状态尚未迁移 |
| 原版无对应移动应用外壳 | `shell/mobile_shell.dart` | 新增窄屏适配，后续随页面迁移调整 |

首页和服务器页当前是无数据的工程入口，设置页只提供会话内主题选择；它们不代表旧业务页面已经迁移。当前图标使用 Flutter 提供的通用图标，平台启动图标保留模板，后续独立设计品牌资源。

后续每个页面先阅读对应 SwiftUI View、子组件、状态和事件处理，再迁移成 Dart；在本表记录来源及有意调整，最后使用截图和交互验证对照。玻璃材质、原生窗口效果不能仅靠颜色近似即宣称等价。

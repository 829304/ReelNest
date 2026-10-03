# 0001：客户端工程初始化

日期：2026-10-04。状态：采用。

## 决定

- Flutter 客户端放在 `apps/client`，五端原生工程一起维护。
- 根 `.fvmrc` 固定 Flutter 3.47.6（包含 Dart 3.13.5）。不跟随浮动 stable 自动升级。
- 单应用阶段只维护 `apps/client/pubspec.yaml` 和 `pubspec.lock`，暂不建立空的 packages 或 Pub workspace。
- 应用工程名为 `reelnest`，显示名为 ReelNest。开发用应用标识采用 `io.github.user829304.reelnest`，区别于旧 MediaLib。商店登记前需确认该标识及签名归属。
- 使用 Riverpod 装配依赖和管理外观状态，go_router 管理首页、服务器、设置导航。宽度达到 760 逻辑像素时使用侧栏，否则使用底部导航。
- 页面迁移以旧项目的 SwiftUI 源码为主，已读取 DesignSystemTokens、AppColors 和 ContentView 的侧栏实现；截图仅辅助验收，当前不宣称完成原版视觉复刻。
- 数据库、协议客户端和播放器在对应功能开始时引入，不添加未使用的插件或伪造的媒体内容。
- 外观选择目前只在本次运行中有效，持久化设置在 storage 模块接入后实现。

## 构建与验证

本地执行格式检查、静态分析、组件测试和 Windows release 构建。CI 使用同一 SDK 版本，在 Windows、macOS、Ubuntu runner 上分别构建五端；iOS 只执行无签名编译，正式签名和发布另行配置。

非 Windows 平台能否构建，以对应 runner 的实际运行结果为准。初始化不等于五端原生功能或播放器已经验收。

# ReelNest 客户端

这里是 ReelNest 的 Flutter 客户端包。第一阶段只开发和验收 Windows、macOS、Linux；iOS/Android 工程暂时保留。

当前已接入本地视频来源、SQLite 索引与浏览、视频播放及基础设置、Emby 视频闭环，以及首页 H1、H2 推荐/搜索/状态和 H3 布局编排。旧 Mlink 试验只保留代码与隔离回归入口；Jellyfin、Plex、音乐及其他原版模块仍按项目计划迁移。实现状态不代表已经完成三桌面端原生和原版 UI 验收。

Flutter 版本由仓库根目录 `.fvmrc` 固定。在本目录执行：

```sh
fvm flutter pub get --enforce-lockfile
fvm flutter analyze --fatal-infos
fvm flutter test
fvm flutter run -d windows
```

完整环境、构建和原生验证说明见[开发指南](../../docs/DEVELOPMENT.zh-CN.md)；产品边界见[项目边界](../../docs/PROJECT_SCOPE.zh-CN.md)；当前下一批见[阶段记录](../../docs/NEXT_STAGE.zh-CN.md)。

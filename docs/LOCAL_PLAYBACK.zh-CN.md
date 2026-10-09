# 本地视频播放与续播

2026-10-09。本批迁移本地视频播放的基础链路，不代表原版播放器全部功能或 UI 已验收。客户端直接读取所选本地目录、移动硬盘及已挂载 NAS 的视频；不依赖 ReelNest Server 或旧 MediaLib 服务端。

## 原版实现依据

参考旧仓库以下源码及调用链，原仓库未修改：

| 原源码 | 本批迁移规则 |
|---|---|
| `Sources/MediaLib/App/AppState.swift` 的 `play` | 详情“播放”；系列解析为首个可播放单集；播放窗口复用 |
| `Sources/MediaLib/Views/DetailView.swift` 的单集行 | 单击选择，双击播放；主播放按钮高度 34、水平内边距 14 |
| `Sources/MediaLib/App/MpvPlayerController.swift` 的 `load/saveProgress` | 默认记住进度；已存位置超过 10 秒时回退 5 秒；关闭保存 |
| `Sources/MediaLibCore/Database/MediaRepository.swift` 的 `updatePlayback` | 按媒体身份保存进度、时长、最近播放时间；达到 90% 标记已看，回退后不清除已看 |
| `Sources/MediaLibCore/Models/AppSettings.swift` | 默认音量 80%，快进/后退 5 秒 |
| `Sources/MediaLib/Views/PlayerView.swift` | 独立视频窗口、最小 680×382；控制条最大宽 568、圆角 14、水平/竖直内边距 8/5、时间间距 7、播放胶囊 44×30 |

当前按钮与基本控制条依据源码参数翻译；SF Symbols、完整自适应材质/调色、字幕与音轨面板、原生工具栏等仍待迁移及原版视觉对照。不能将基本控制条称作完整一比一播放器。

## 已接入的链路

- 影片详情“播放”、系列详情首集播放、单集双击播放打开独立窗口。同一窗口切换影片前暂停并保存旧进度，释放旧解码器；切换保存失败时保留旧影片和可重试的进度。
- 子窗口重新读取来源与索引，校验路径边界、挂载信息和文件存在。离线、缺失或打不开的视频显示明确失败，不将已有进度改成零。
- 播放/暂停、进度拖动、快进/后退、音量、静音、全屏及关闭；空格切换播放、左右键跳转、F 切换全屏，Esc 优先退出全屏，再关闭播放器。
- 进度每 5 秒检查保存，暂停、切换、播放完成和关闭时保存；未知时长不覆盖旧记录。播放完成时即使引擎位置回零，也按总时长保存。
- 关闭先暂停并保存，保存成功后才释放解码器；保存失败或重试仍失败时保留可操作的会话，用户明确选择“仍然关闭”才跳过保存。
- 主窗口关闭先请求播放器完成保存；播放器关闭后主窗口刷新进度数据。Windows 子窗口使用关闭原生窗口的方式，避免 `window_manager.destroy` 的 `WM_QUIT` 退出整个应用。

这是基础视频播放批次。音乐/照片播放、队列与下一集、字幕/音轨/倍速、播放设置页、键盘完整映射、外部播放器等原有能力继续留在迁移清单中。

## 模块与数据

| 位置（`apps/client/lib/`） | 职责 |
|---|---|
| `player/video_engine.dart` | 播放引擎接口与时钟事件 |
| `player/media_kit_video_engine.dart` | media_kit/libmpv 适配；首次打开视频才初始化原生播放器 |
| `features/playback/domain/` | 播放记录与续播规则 |
| `features/playback/data/` | 来源 ID + 本地媒体 ID 隔离的 SQLite 记录 |
| `features/playback/application/` | 命令串行化、保存、资源释放、独立窗口启动与通信 |
| `features/playback/presentation/` | 视频画布、基本控制条及子窗口生命周期 |

只维护当前 `playback_states` 表；使用独立表的幂等创建，不修改来源/媒体已有列，不建立开发中间版本升级链或自动重置数据库。外键随来源/媒体删除清理播放记录；保存只写仍存在的非系列媒体，防止正在播放的文件在索引删除后重新产生孤立进度。重扫同类媒体保留记录，媒体身份类型改变清除旧进度。

主窗口和播放器各有数据库连接，使用后台执行与写入等待。进度时钟仅更新控制条；主窗口在关闭/切换通知时刷新播放记录。此批未建立跨进程实时扫描锁或通用数据库变更广播。

## 依赖与平台

锁定 `media_kit 1.2.6`、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`、`desktop_multi_window 0.3.1`、`window_manager 0.5.1`。三个桌面入口为子窗口注册插件；Linux 构建工作流增加 `libmpv-dev` 和 `mpv`。

Windows 真实解码与独立窗口流程已验证。macOS/Linux 只完成源码接线，尚未执行原生构建、窗口行为或解码验收；macOS 持久目录授权仍未实现。移动端不在本批范围。

依赖说明：[media_kit](https://pub.dev/packages/media_kit)、[desktop_multi_window](https://pub.dev/packages/desktop_multi_window)。

## 自动验证

```powershell
# 在 apps/client 下，用仓库固定的 Flutter SDK 执行
fvm flutter test
fvm flutter analyze
# 独立窗口必须直接启动测试入口，不能使用 flutter test 生成的 listener
fvm flutter drive --driver test_driver/integration_test.dart --target integration_test/local_playback_test.dart -d windows
fvm flutter build windows --release
```

原生测试在系统临时目录生成 24 秒、160×90 的无音频 AVI，自建临时数据库，验证真实解码、续播、切换及关闭后进度。测试不会添加到用户媒体库，结束清理自己的临时目录，不要求真实 NAS 或私有视频。AVI 只能证明基础解码链路，不能代替常见封装/音频、字幕、HDR、长视频或真实断盘验收。

原生测试当前未纳入无桌面环境的 CI 冒烟；已有 CI 继续执行分析/组件测试和三平台构建。测试结果与运行日志的限制见 [当日记录](TEST_REPORT_2026-10-09.zh-CN.md)。

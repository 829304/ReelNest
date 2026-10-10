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

当前按钮与控制条依据源码参数翻译；本地字幕/音轨/音量面板和海报明暗调色已接入，见 [字幕/音轨批次](PLAYER_TRACKS.zh-CN.md)。SF Symbols、系统材质、原生工具栏及完整原版视觉对照仍待验收，不能称作完整一比一播放器。

## 已接入的链路

- 影片详情“播放”、系列详情首集播放、单集双击播放打开独立窗口。同一窗口切换影片前暂停并保存旧进度，确认新视频能打开后释放旧解码器；切换保存失败时保留旧影片和可重试的进度。
- 子窗口重新读取来源与索引，校验路径边界、挂载信息和文件存在。离线、缺失或打不开的视频显示明确失败，不将已有进度改成零。
- 播放/暂停、进度拖动、快进/后退、音量、静音、全屏及关闭；空格切换播放、左右键跳转、F 切换全屏，Esc 优先退出全屏，再关闭播放器。
- 进度每 5 秒检查保存，暂停、切换、播放完成和关闭时保存；未知时长不覆盖旧记录。播放完成时即使引擎位置回零，也按总时长保存。
- 关闭先暂停并保存，保存成功后才释放解码器；保存失败或重试仍失败时保留可操作的会话，用户明确选择“仍然关闭”才跳过保存。
- 主窗口关闭先请求播放器完成保存；播放器关闭后主窗口刷新进度数据。Windows 子窗口使用关闭原生窗口的方式，避免 `window_manager.destroy` 的 `WM_QUIT` 退出整个应用。

本地字幕/音轨批次已接入选择、目录/手动文件、双字幕、语言偏好、快慢、音量增强与输出设备。队列、上一集/下一集与播完行为已接入，见 [队列说明](PLAYER_QUEUE.zh-CN.md)。在线字幕、倍速/完整播放设置、键盘完整映射、外部播放器等仍待迁移。音乐播放器与照片查看另计模块，不混入本地视频播放器进度。最新总表见 [播放器实现盘点](PLAYER_STATUS.zh-CN.md)。

## 模块与数据

| 位置（`apps/client/lib/`） | 职责 |
|---|---|
| `player/video_engine.dart` | 播放引擎接口与时钟事件 |
| `player/media_kit_video_engine.dart` | media_kit/libmpv 适配；首次打开视频才初始化原生播放器 |
| `features/playback/domain/` | 播放记录与续播规则 |
| `features/playback/data/` | 来源 ID + 本地媒体 ID 隔离的 SQLite 记录 |
| `features/playback/application/` | 命令串行化、保存、资源释放、独立窗口启动与通信 |
| `features/playback/presentation/` | 视频画布、基本控制条及子窗口生命周期 |

只维护当前 `playback_states`、`player_preferences` 和 `media_activity` 表；独立表幂等创建，不修改来源/媒体已有列，不建立开发中间版本升级链或自动重置数据库。外键随来源/媒体删除清理播放记录；保存只写仍存在的非系列媒体，防止正在播放的文件在索引删除后重新产生孤立进度。重扫同类媒体保留记录，媒体身份类型改变清除旧进度。

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

原生测试生成 24 秒、160×90 无音频 AVI 及多音轨/内嵌字幕 Matroska，自建临时数据库，验证真实解码、续播、切换、保存、字幕渲染和轨道/输出控制。不会添加到用户媒体库，结束清理自己的临时目录，不要求真实 NAS 或私有视频。样本覆盖有限，不能代替多种编码/HDR/长视频、听感或真实断盘验收；详细范围见字幕/音轨文档。

原生测试当前未纳入无桌面环境的 CI 冒烟；已有 CI 继续执行分析/组件测试和三平台构建。测试结果与运行日志的限制见 [当日记录](TEST_REPORT_2026-10-09.zh-CN.md)。

## 剧集队列与播完行为（2026-10-09）

已接通原版队列后缀、完整同系列手动相邻项、三种播完动作及安全切换。进度与更新时间在同一事务保存；坏文件和存储失败保留当前播放器。详情与 UI/排序边界见 [队列说明](PLAYER_QUEUE.zh-CN.md)。全量 156 项、Windows 三项原生业务测试通过；完整播放器设置、标记等继续待迁移。

## 基础播放设置与防休眠（2026-10-09，静态实现）

按用户要求写入倍速/默认与记忆、变调保护、快进快退步长、续播开关/回退、自动已看/阈值、启动音量，以及三桌面端原生防休眠。设置入口和持久化已接入；详细行为见 [基础播放设置](PLAYER_BASIC_SETTINGS.zh-CN.md)。没有运行测试、静态分析或构建，EXE 没有更新。本轮前的测试结果不代表这一批已通过。基础验收后仍优先 Emby，不继续扩大高级播放器前置范围。

## 基础设置测试完成（2026-10-09）

用户后续授权验证。新增 11 项专项回归，全量 167 项通过；Windows 3 项原生业务场景通过，含真实 mpv 倍速/变调与原生防休眠接口。修复数值类型及 Windows 插件链接问题，静态分析与 122 文件格式检查通过。Release 重新构建成功，EXE 更新时间 18:36:04，启动后主窗口保持响应，详见 [当日测试报告](TEST_REPORT_2026-10-09.zh-CN.md)。下一阶段优先 Emby；macOS/Linux、防休眠实际空闲超时与完整 UI 验收仍待进行，不扩展本地高级播放器前置范围。

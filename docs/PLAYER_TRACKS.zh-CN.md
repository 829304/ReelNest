# 视频字幕、音轨与音量面板

更新：2026-10-09。本批接在基础本地播放之后，直接读取本地文件、移动盘或已挂载目录。Windows 原生验证已完成；macOS/Linux 接线存在，原生验收仍待对应设备执行。

## 原版依据与已迁移内容

| 原源码 | 当前实现 |
|---|---|
| `MpvTrack.swift` | mpv 轨道 ID、语言、标题、编码、选择状态、外挂标记/文件名；沿用“语言 · 标题 · 编码 · 外挂”显示名称 |
| `TrackLanguageMatcher.swift` | 元数据优先于标题/文件名；区分简繁中文与常见语言别名；同分优先已选轨，再选较小 ID |
| `TrackPreferenceStore.swift`、`MpvPlayerController.applyTrackPreferenceIfNeeded` | 影片按自身身份、剧集按父项共享语言/关闭偏好；列表就绪后应用一次，不覆盖手动选择；无记忆时字幕默认匹配 `zh-CN` |
| `SidecarSubtitleFile.find` | 同名、以 `. - _` 分隔的同名前缀、通用 subtitle/subtitles/subs 文件；优先级/自然文件名排序；枚举 srt/ass/ssa/vtt，排除隐藏文件 |
| `VideoTrackSelectionEngine.swift` | 内嵌/外挂字幕选择、关闭、目录重扫、任意位置文件加载、第二字幕、自动/指定音轨、输出设备 |
| `PlayerAudioTrackPopover` | 宽 300、最大高 420、内边距 12、间距 10；自动选择、轨道列表与空态 |
| `PlayerSubtitlePopover` 的本地部分 | 宽 360、最大高 540；关闭、自动目录、手动文件、快慢、内嵌/目录及第二字幕；0.1 秒调整并限制在 ±3 秒，记住全局默认 |
| `PlayerVolumePopover`、`PerceptualVolumeScale` | 宽 338、水平/竖直内边距 13/11、间距 9；音量、输出设备及关闭/125%/150%/200%增强。原版当前音量指数为 1，滑杆按线性映射 |
| `VideoControlPalette`、控制条 | 海报亮度决定明/暗内容，缺少海报使用暗内容；字幕/音轨置于左侧 200 宽区域，音量置于右侧 200 宽区域；音量改为弹层，去掉此前错放的快退/快进按钮，保留左右快捷键 |

弹层打开时保持控制条可见，Esc 先关闭弹层。上/下键按原默认调整 5.5% 音量，M 静音/恢复，恢复保留最低 40% 规则。切换轨道不重新打开影片，不改变续播记录。

字幕由原生 mpv/libass 渲染，保留 ASS 样式、位图字幕与第二字幕能力，不以 Flutter 文本叠层代替。[mpv 字幕说明](https://mpv.io/manual/stable/#subtitles)

## 模块与持久化

- `apps/client/lib/player/video_tracks.dart`：插件独立的轨道/设备状态、Windows 长路径规范化。
- `player/video_engine.dart`、`player/media_kit_video_engine.dart`：轨道/设备事件与原生命令；业务层不直接调用插件。
- `features/playback/domain/`：语言匹配、同目录字幕发现；字幕正文不会读入 Dart 内存。
- `features/playback/data/player_preferences_repository.dart`：当前 `player_preferences` 表；来源 ID 纳入影片/剧集键，避免不同来源串用偏好。
- `features/playback/application/playback_session.dart`：串行设置操作、一次性偏好恢复、错误隔离、音量/增强/快慢记忆。
- `features/playback/presentation/player_track_popovers.dart`、`player_visuals.dart`：面板、轨道行、调色/图标；高频播放位置不驱动面板重建。

数据库仍维护当前初始结构；独立表幂等创建，没有历史迁移或自动清库。自动选择音轨不会清除已记忆语言；新加载的外挂文件不会自动改写语言记忆，保持原控制器规则。

设置失败显示可重试的设置错误，不释放解码器或将进度归零。真实测试发现并处理：自动外挂字幕带 Windows `\\?\`/UNC 长路径前缀；音量事件滞后，增强不能读取旧音量；无效外挂字幕的 mpv 外部文件错误不能变成视频解码失败。加载后校验新轨道是否真正存在，不能返回假成功。

## 验证与剩余范围

新增 19 项单元/组件回归，全量 138 项通过，静态分析通过。Windows 两项原生业务测试：合成无音频 AVI 验证独立窗口的解码/续播/切换/关闭保存；合成两音轨、两内嵌字幕的 24 秒 Matroska 验证轨道操作。比较同一暂停帧包含/不包含 libass 的像素，确认字幕实际渲染。

原生场景还覆盖自动目录、手动文件、双字幕、快慢、增强、系统默认输出，以及不存在/无效字幕拒绝后继续播放。样本为静音 PCM：可证明真实解码和切换，不能证明不同编码、听感、设备插拔或音画同步均已验收。

在线字幕搜索/下载、完整播放设置与快捷键映射、标记、迷你窗口、截图等原功能继续待迁移。队列/相邻单集/播完行为已接入，最新状态以 [播放器实现盘点](PLAYER_STATUS.zh-CN.md) 为准。当前只实现字幕面板本地部分，没有在线占位按钮。SF Symbols 跨平台轮廓、系统字体/材质、弹层箭头与原版像素对照仍待验收，不能称 UI 一比一完成。队列、相邻项和播完行为已在后续批次接通，见 [队列说明](PLAYER_QUEUE.zh-CN.md)；完整播放设置等继续待迁移，本地闭环之后仍优先 Emby。

构建、启动与已知日志限制见 [当日测试报告](TEST_REPORT_2026-10-09.zh-CN.md)。

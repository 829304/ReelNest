# 视频字幕、音轨与音量面板

更新：2026-10-16。历史基础批次接在本地播放之后，直接读取本地文件、移动盘或已挂载目录。Windows 基础字幕/音轨原生验证已完成；macOS/Linux 接线存在，原生验收仍待对应设备执行。字幕样式串行更新 P2 修正的定向、全量、Windows Release 和 smoke 验证均已完成；其他平台与用户可见 UI 验收仍待，见下节。

## 当前批次：字幕样式与音画同步（P2 修复及 Windows 验证完成，2026-10-16）

### P2 修正：快速连续样式更新合并（Windows 验证完成）

本轮复核确认：快速修改字幕样式时，旧 UI 曾在串行操作入队前基于过期快照拼整份配置，后续粗体/颜色/描边/字体操作可能覆盖尚未执行的先前修改。现改为通过 `updateSubtitleStyle` 回调在队列执行时读取 engine 最新状态并合并字段变更；保留保存失败回滚语义，回滚后下一编辑基于回滚后的状态合并。UI 提交局部变更。三个定向测试文件合计 **28 项通过**，其中新增 10 项后端/路径回归，UI 连续操作由现有组件 case 覆盖。全量 `flutter test --no-pub --reporter expanded` **753 passed / 6 skipped**（49 秒，exit 0）；`flutter analyze --no-pub` 无问题；`lib`、`test`、`integration_test` 格式检查 296 文件 0 改动；`git diff --check` 通过。Windows production Release 构建 **45.7 秒成功**；`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 **2026-10-16 16:57:14.4629377 +08:00** 通过（`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`）。`data/app.so` 为 **11,846,536 bytes**，最后写入时间 **2026-10-16 16:56:42.629222 +08:00**。本轮无 schema 变更、无用户数据删除、未提交推送。其他平台和可见 UI 视觉验收仍待。

### 原版基线与范围

原版入口为 `PlayerView.swift` 播放设置中的“字幕样式”和“音画同步”两个 tab。本地与 Emby 继续共用播放器状态和控制；当前批次补齐这些全局设置，并要求修改后即时应用到当前播放器、保存为后续视频使用的全局默认值。本批代码已冻结；各项实际验证范围和未覆盖的平台/字幕类型见下文。

原版依据：`Sources/MediaLibCore/Models/VideoSubtitleStyle.swift`、`Sources/MediaLib/App/VideoSubtitleStylePolicy.swift`、`Sources/MediaLib/App/VideoTimingAdjustmentPolicy.swift`、`Sources/MediaLibCore/Models/AppSettings.swift`、`Sources/MediaLib/Views/PlayerView.swift`。

字幕样式默认值：字体 `nil`（播放器默认字体）、粗体关闭、颜色白色、描边 3、背景底透明度 0。描边范围 0–6、步进 0.5；背景底范围 0–0.8，原版 UI 选项为关闭/淡/中/深（透明度 0/0.25/0.45/0.7）。颜色预设仅白、黄、青、绿、橙，对应原策略映射：`#FFFFFF`、`#F5D547`、`#7FE3E8`、`#8FE388`、`#F5A14B`。原版 mpv 属性映射为 `sub-font`、`sub-bold`、`sub-color`、`sub-border-size`、`sub-back-color`。

字幕大小与音画同步默认/边界：

| 设置 | 默认值 | 范围 | 步进/说明 |
|---|---:|---:|---|
| 音频延迟 `audio-delay` | 0 秒 | -3 至 +3 秒 | 0.1 秒 |
| 字幕延迟 `sub-delay` | 0 秒 | -3 至 +3 秒 | 0.1 秒；保留原已有能力，与音频延迟集中于同一“音画同步”设置区，不删除或混为同一个值 |
| 字幕大小 `sub-scale` | 1（100%） | 0.75–1.5 | 0.05 |
| 字幕位置 `sub-pos` | 100% | 70–100 | 整数；原版按钮每次调整 4 |

时间值越界时需沿原版策略夹取，不能绕过规则写入无效值。布局与交互以原版两个 tab 为依据；技术结构可按 Flutter 重构，但需逐项对照原版尺寸、控件、状态和反馈。

### 字体平台策略

字体菜单只能呈现经平台枚举确认安装的可选字体，不凭经验硬编码“平台一定有”的字体。三平台候选名称和枚举实现见下方“字体枚举与平台首选项”；运行时只展示系统实际返回的精确匹配项，默认字体项始终保留。Windows Profile 已验证主/子 engine 通道生命周期；macOS/Linux 实际枚举和视觉等效仍待对应平台核验。

### 字幕类型与能力边界

沿用 mpv/libass 原生字幕渲染，不改为 Flutter 文本覆盖。原版样式策略映射上述 mpv 字幕属性，**不额外强制 ASS 覆盖模式**。因此不能承诺字体、粗体、颜色、描边和背景可改写所有字幕：位图字幕本身没有可按这些属性重排/着色的文本字形；带自身样式标记的 ASS 字幕也可能保留其样式。实现必须保留原始字幕轨道行为，对每种字幕类型验证实际生效范围；不可改变的项目须清楚呈现能力限制，不能谎报成功。

### 已接入接口

- Domain：`features/playback/domain/video_subtitle_settings.dart` 提供 `VideoSubtitleStyle`（`fontName`、`bold`、`colorPreset`、`borderSize`、`backgroundOpacity`）和 `VideoTimingSettings`（`audioDelay`、`subtitleDelay`、`subtitleScale`、`subtitlePosition`），包含 JSON、默认值与归一化/范围夹取。
- Engine contract：`player/video_subtitle_settings_engine.dart` 定义可选 `VideoSubtitleSettingsEngine`，暴露 `subtitleStyle`、`timing` 和 `setSubtitleStyle`、`setAudioDelay`、`setSubtitleScale`、`setSubtitlePosition`；现有 `VideoEngine.setSubtitleDelay` 保持为字幕延迟入口。
- mpv adapter：同文件的 `MpvSubtitleSettingsCommands` 使用参数数组命令设置属性，先读回旧值，再逐项设置并读回核验；多属性设置失败时按相反顺序回滚已修改项。回滚失败抛 `SubtitleSettingsRollbackFailure`，供上层区分。
- Session API：`PlaybackSession.setSubtitleStyle(style)`；时间项方法为 `audioDelay(seconds)`、`subtitleDelay(seconds)`、`subtitleScale(scale)`、`subtitlePosition(position)`。各项即时应用后写全局偏好；保存失败尝试恢复应用前值，恢复失败单独记录/告警而继续播放。初始化应用默认值失败时记录诊断并展示警告，不阻止视频启动。当前引擎不实现可选设置接口时，非默认的样式/音画设置会报告不支持，不应伪称已应用。
- 字体服务：`PlaybackSession.subtitleFontFamilies` 惰性缓存 `SubtitleFontCatalog.families()` 的结果；读取失败会清除缓存，允许 UI 显示重试。高级设置在首次打开字幕 tab 时加载字体列表。
- UI：`features/playback/presentation/player_behavior_settings.dart` 提供“音画同步”和“字幕”设置 tab；`player_subtitle_sync_settings.dart` 连接现有 session 方法。实现已在工作树，组件行为和外观仍未验收。

上述接口与行为是代码盘点结果；已覆盖的测试证据见下方，未覆盖的平台/字幕类型仍不能推断已验证。

### 字体枚举与平台首选项（代码已接入，平台结果待核验）

三平台统一使用 method channel `reelnest/subtitle_fonts` 的 `families` 方法。插件在主窗口及播放器子窗口注册；Dart `SubtitleFontCatalog` 只从系统枚举结果中保留平台首选名称（忽略大小写精确匹配、去重），没有匹配到的字体不会出现在菜单中。

| 平台 | 原生枚举 | 首选名称（只展示系统实际返回的项） |
|---|---|---|
| macOS | `NSFontManager.shared.availableFontFamilies` | `PingFang SC`、`Hiragino Sans GB`、`Heiti SC`、`Songti SC`、`Yuanti SC`、`LXGW WenKai`、`Helvetica Neue`、`Avenir Next`、`Georgia`、`Arial`；沿用原版候选顺序 |
| Windows | GDI `EnumFontFamiliesExW`，排除以 `@` 开头的竖排别名 | `Microsoft YaHei`、`微软雅黑`、`Microsoft YaHei UI`、`微软雅黑 UI`、`SimHei`、`黑体`、`SimSun`、`宋体`、`KaiTi`、`楷体`、`LXGW WenKai`、`Segoe UI`、`Arial`、`Georgia` |
| Linux | Pango `pango_cairo_font_map_get_default` / `pango_font_map_list_families` | `Noto Sans CJK SC`、`Noto Sans SC`、`Noto Serif CJK SC`、`WenQuanYi Micro Hei`、`LXGW WenKai`、`DejaVu Sans`、`Liberation Sans`、`Arial`、`Georgia` |

Windows/Linux 使用平台候选族名实现对原版字体选项的本机适配；Dart 侧只展示实际枚举存在的精确族名，不做未实现的模糊 fallback。以上是代码配置的候选映射，并非三平台的实机字体覆盖率或视觉等效验收结论。

### 最终验证证据（代码冻结；Windows 构建与 smoke 通过）

- `player_subtitle_settings_test` 覆盖原规则、字体过滤、异步字体列表重试、多属性属性拒绝/回滚、偏好存储失败时回滚、回滚失败提示、同值重试、初始化设置失败不阻断播放及全局偏好恢复。
- 同批新增 Emby 画质切换与转码 seek 断言，检查字幕 style/timing 保留。
- 最终 `flutter test`：**718 passed / 6 skipped**；6 项 opt-in 原生测试按默认配置跳过。`flutter analyze` 无问题；279 个 Dart 文件格式检查为 0 改动，`git diff --check` 通过。此全量结果不包含下述单独启用的 native 验证。
- 单独启用 `player_subtitle_settings_native_test`、使用真实 libmpv：**1 项通过**。验证 mpv 读回 5 个字幕样式与 4 个 timing 属性；合成文本字幕的 libass 截图像素发生变化；暂停状态及 `time-pos` 不变；未修改 `sub-ass-override`。样本仅为文本字幕，不能据此声称带自有样式的 ASS 或位图字幕已验收，也不能推导三平台均通过。
- Windows Profile 字体集成：`flutter drive --profile --no-pub -d windows --driver=test_driver/integration_test.dart --target=integration_test/subtitle_fonts_test.dart`，Profile 构建 **21.9 秒**，**1 项业务 case 通过**。真实主 engine 字体枚举非空，播放子 engine 返回相同列表；子窗口正常销毁后，主 engine 再次枚举仍成功。driver 结果为 All tests passed。`tearDownAll` 输出通用 “Windows integration_test plugin was not detected” 提示，未阻断 driver 通过；该自动化结果不等同人工可见 UI 验收。
- 正式 Windows Release 构建成功，用时 **37.8 秒**；产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 **2026-10-16 09:34:00 +08:00** 通过：隐藏窗口有响应、正常关闭、退出码 0。

### 尚待完成

- 本轮 P2 修复后的 Windows Release 构建和五秒 smoke 已通过；人工可见设置页/字体菜单 UI 验收仍待。
- ASS 自有样式和位图字幕的实际能力/限制仍需分别探测；不强制 ASS override，也不承诺位图字幕可改字体或颜色。
- macOS/Linux 原生字幕效果、字体候选覆盖、子窗口能力和原版设置页视觉对照仍需逐端验收；真实 Emby 播放场景还需确认。

初始实现的历史验证为 718 passed / 6 skipped 及单独 native/Profile 用例；本轮 P2 修复后的 753 passed / 6 skipped、analyze、296 文件格式检查、diff-check、Windows Release 和 smoke 均通过。其他平台与专项验收仍待；不可标记为三平台、所有字幕类型、真实 Emby 或 UI 视觉最终验收。

本批不改数据库 schema、不添加中间版本迁移、不清理本机数据；使用既有播放器偏好键值存储。当前键名/JSON 结构见[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)；全局恢复与保存失败路径已有自动化覆盖，但持久化、macOS/Linux 原生和 UI 视觉最终验收仍待。

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

在线字幕搜索/下载、其余完整播放设置与快捷键映射、标记、迷你窗口、截图等原功能继续待迁移。视频播放器均衡器/预设已实现并通过 Windows 自动化验证，非音乐播放器功能；真实设备听感、真实 Emby、macOS/Linux 原生及原版 UI 视觉验收仍待，详见[视频均衡器计划](PLAYER_VIDEO_EQUALIZER_PLAN.zh-CN.md)。字幕样式/同步子集正在当前批次补齐，不能据此宣称完整播放设置完成。队列/相邻单集/播完行为已接入，最新状态以 [播放器实现盘点](PLAYER_STATUS.zh-CN.md) 为准。当前只实现字幕面板本地部分，没有在线占位按钮。SF Symbols 跨平台轮廓、系统字体/材质、弹层箭头与原版像素对照仍待验收，不能称 UI 一比一完成。队列、相邻项和播完行为已在后续批次接通，见 [队列说明](PLAYER_QUEUE.zh-CN.md)；本地闭环之后仍优先 Emby。

构建、启动与已知日志限制见 [当日测试报告](TEST_REPORT_2026-10-09.zh-CN.md)。

# 高级播放第一批：底层接口与前端接入

- 状态：底层与首批共用播放器 UI 已接入；三桌面端实机与像素级视觉验收待完成
- 日期：2026-10-12（底层），2026-10-13（前端接入）
- 范围：章节、手动章节/书签、单片循环、A–B 循环、前后逐帧
- 分工：底层批次负责引擎、会话、持久化与原生测试；前端批次仅通过 `PlaybackSession` 接入播放器 presentation，不直接操作数据库或 mpv

## 原版依据

参考仓库只读，行为基线为 `64f8ee2`。

- `Sources/MediaLib/Views/PlayerView.swift`：`syncEmbeddedChapters`、`addManualChapter`、`addBookmark`、`deleteMarker`、`toggleCurrentLoop`。
- `Sources/MediaLib/App/VideoLoopCommandEngine.swift`：`loop-file`、`ab-loop-a`、`ab-loop-b` 属性映射。
- `Sources/MediaLib/App/VideoFrameCommandEngine.swift`：`frame-step`、`frame-back-step`。
- `Sources/MediaLibCore/Models/PlaybackABLoopPolicy.swift`：A/B 选点规则。
- `Sources/MediaLibCore/Models/PlaybackMarker.swift` 与 `Database/PlaybackMarkerRepository.swift`：标记分类、来源、归一化、保存与内嵌章节替换。
- `Sources/MediaLibCore/Models/AppSettings.swift` 与 `MpvPlayerController.applyVideoSettings`：单片循环默认关闭且记住开关；A/B 不持久化。

## 前端接口

入口为 `apps/client/lib/features/playback/application/playback_session.dart`。前端仅持有已有 `PlaybackSession`；不实例化控制器、操作数据库或发送 mpv 命令。

| 状态 | 含义 |
|---|---|
| `session.precision` | `ValueListenable<PlaybackTimelineState>`，仅章节/书签/循环等低频变化；不要将它绑定到整个播放器的高频进度重建 |
| `precision.value.identity` | 当前媒体身份；未加载或释放时为空 |
| `precision.value.supported` | 当前引擎是否支持原生章节/循环/逐帧能力 |
| `precision.value.markers` | 当前媒体标记，按时间排序；内嵌章节和手动标记共存 |
| `precision.value.chapters` / `bookmarks` | 已可用于播放的章节/书签列表 |
| `precision.value.loop.loopCurrentItem` | 单片循环开关 |
| `precision.value.loop.start` / `end` | A/B 点，`Duration?`；只有 A 表示尚未形成区间 |
| `session.loading` / `engine` / `error` | 使用现有播放状态禁用忙碌、无引擎或不可播放时的入口 |
| `session.controlError` | 可重试的设置/标记操作错误；不得作为解码失败销毁播放器 |
| `session.timeline` | 原有高频进度通知；逐帧后的进度仍由该入口更新 |

| 命令（均返回 `Future<void>`） | 行为 |
|---|---|
| `refreshTimeline()` | 刷新章节及持久化标记 |
| `addChapter({Duration? at})` | 在指定时间或当前时间添加“手动章节 N” |
| `addBookmark({Duration? at})` | 在指定时间或当前时间添加“书签 N” |
| `deletePlaybackMarker(String id)` | 只删除当前影片的手动标记；不允许删除内嵌章节 |
| `seekPlaybackMarker(String id)` | 跳转到当前影片标记位置，复用现有转码时间偏移处理 |
| `setLoopCurrentItem(bool enabled)` | 设置并保存单片循环开关；保存失败时尝试恢复原引擎值 |
| `cycleABLoop()` | 当前点设 A → 有效区间设 B → 再次操作重新设 A；不会在第三次自动清除 |
| `clearABLoop()` | 显式清除 A/B，不改变单片循环开关 |
| `stepFrame({bool backward = false})` | 暂停后前进/后退一帧；保存进度并沿用 Emby 状态上报 |

调用完成不等于成功：与现有播放器设置 API 相同，错误被会话转成 `controlError`。前端应以更新后的状态和错误显示结果，不自行乐观翻转开关，不在失败时显示成功提示。成功操作会清除上次控制错误。

所有时间使用影片绝对 `Duration`，前端不加减 Emby 转码偏移。UI 遵循原版章节面板、菜单、快捷键与提示；本批接入情况见下节，不能据此宣称完整原版播放器 UI 已验收。

## 前端落地

前端入口为 `features/playback/presentation/video_player_page.dart`，共用组件为 `player_precision_controls.dart`，弹层宿主继续复用 `player_track_popovers.dart`。

- 控制栏新增“章节与播放标记”入口；弹层显示当前时间、内嵌章节、手动章节和书签，可添加章节/书签、点击跳转、删除手动标记及手动刷新。
- 进度条叠加章节/书签刻度和 A–B 区间指示；低频 `session.precision` 只重建控制条相关区域，不绑定播放器画面或整页高频刷新。
- 播放画面右键菜单接入本批精确播放区段：从头播放、单片循环、设置/重设/清除 A–B、上一帧和下一帧。原版右键菜单的截图、播放信息、外部播放器等其他项目仍按播放器总清单推进。
- 快捷键按原版默认映射接入：`B` 设置 A/B 点、`Shift+B` 清除 A–B、`,` 上一帧、`.` 下一帧；`Home` 从头播放。
- 循环操作完成后依据更新后的 `precision` 状态显示提示；失败只显示 `controlError`，不乐观翻转 UI，也不销毁仍可播放的会话。
- Logo、侧栏主题和普通页面主题不属于本批播放器接入范围。

## 状态与数据规则

- 新表 `playback_markers` 使用 `(source_id, local_id, id)` 身份，媒体删除级联清理；相同远程 ID 或文件名在不同来源不会串标记。
- 时间以微秒保存。模型清理负时间、空标题和非法置信度，手动/内嵌标记不保留自动候选审核状态。
- 替换非空内嵌章节采用事务，只替换对应媒体的内嵌章节，保留手动章节和书签。空解码快照不删除已有章节。
- 手动章节/书签编号遵循原版“当前同类手动标记数量 + 1”，删除后可能再次使用同一显示编号；内部 ID 独立。
- A/B 只有在 B 大于 A + 0.20 秒时形成区间；向前选点、间隔过短或已有完整区间时均重新设 A。
- 切换影片/剧集清除 A/B，保留单片循环偏好；同一影片切换画质保留 A/B。新候选解码失败时保留旧会话及标记。
- 章节通过 native property observation 按变化读取，不按播放进度轮询，不在每帧写数据库。旧引擎订阅随释放取消。
- 章节辅助读取失败不会阻断有效视频打开；可通过 `refreshTimeline()` 重试。
- 表为当前结构的模块建表，不引入开发版历史升级链，也不清除用户数据库。

## Emby 转码

从续播位置生成的转码流可能只有影片后半段。启用循环时，会话会在必要时准备从影片起点提供的流，再定位回用户当前时间，保持画质、暂停状态、音量和倍速。此步骤会发生网络请求，应沿用 `loading` 状态；失败保留旧引擎且不开启循环。

已启用单片循环或存在 A 点时，后续转码准备使用完整时间轴，避免把原生循环限定在后半段。内嵌章节的部分转码快照不能覆盖已保存的完整章节；没有完整缓存时，部分章节只作为当前会话展示后备。

原生循环正常不会发出终止 EOF；会话也保护 EOF 收尾，防止循环时误切下一集或关闭窗口。循环不覆盖原有结束策略，关闭循环后继续使用所选策略。

## 当前批次：片头/片尾手动标记与跳过（代码与 Windows 自动化验证完成）

用户已正式授权实施手动片头/片尾范围和已确认范围的跳过行为。代码及会话接口已接入；定向回归、三项前端 UI 组件测试、全量分析/测试、格式检查、Windows Release 构建和启动冒烟均已通过。当前完成的是 Windows 自动化验证，真实 Emby、三桌面原生及视觉验收仍待进行。范围不含自动识别与候选审核。行为依据为参考基线 `64f8ee2` 的 `PlayerView.setMarkerBoundary`、`PlayerMarkerSkipLayer`、`VideoMarkerSkipBehavior` 和对应测试。

- 在共用播放器标记面板提供“片头开始 / 片头结束 / 片尾开始 / 片尾结束”，使用当前影片的绝对时间；本地视频与 Emby 视频复用同一 `PlaybackSession` 接口、状态和 presentation，不为来源复制播放器页面。
- 手动片头与片尾各维护一个范围，并按 `(sourceId, localId)` 隔离。设置开始点时，若开始时间大于或等于旧结束时间，清除结束点并让范围回到未闭合状态；设置结束点时，若当前开始点大于或等于结束时间，先将开始点设为 `max(0, 结束时间 - 90 秒)`，再保证结束时间至少为开始时间加 0.1 秒。播放区间采用开始点包含、结束点排除的边界语义。这些规则需落在业务层并加入回归，不能由前端自行推断。
- `VideoMarkerSkipBehavior {off, prompt, automatic}` 提供“关闭 / 显示按钮 / 自动跳过”，默认 `prompt`（显示按钮）。`PlaybackTimelineState.skipBehavior` 与 `activeSkipMarker` 暴露当前策略和活动范围；`PlaybackSession` 提供 `setMarkerBoundary(kind, {required isStart, Duration? at})`、`setMarkerSkipBehavior(behavior)` 和 `skipPlaybackMarker(id)`。删除手动范围复用既有 `deletePlaybackMarker`。
- 关闭只隐藏跳过入口，不删除章节或手动标记；显示按钮只在播放头进入完整且已确认的片头/片尾范围时出现；自动跳过只对完整且已确认范围跳到结束位置，并防止同一范围内重复触发。按钮跳过命令和自动跳过均只在当前来源、当前媒体和可控制状态仍匹配时执行。
- 行为偏好保存到 `player_preferences` 的 `global.videoMarkerSkipBehavior`，不增加 schema。标记仍写入既有 `playback_markers`，手动标记为 accepted。标记保存失败、播放器正在切换或当前媒体不可控制时，不显示成功状态、不丢失仍可播放的会话；本地与 Emby 使用影片绝对时间，Emby 转码偏移只在引擎边界处理。
- 自动片头/片尾识别、自动候选生成、候选采用/忽略、批量分析和任务中心接入属于后续子批次。本批不得仅因模型存在 `intro` / `credits` 或原版有候选字段就标为已实现。

本批自动化完成条件包括业务规则与持久化回归、共用播放器组件回归、Windows 真实 mpv session 专项、Release 构建和启动检查，均已通过；组件测试不能替代实体键鼠、真实 Emby、macOS/Linux 原生或原版视觉验收。

### 当前批次定向与 mpv session 证据（2026-10-13）

- `player_marker_skip_test.dart` 新增 17 项通过，覆盖范围边界、默认 `prompt`、写入/删除失败、SQLite 重开、来源隔离、过期排队及 EOF/A–B 关系。
- `player_precision_test.dart` 现有 13 项通过；`emby_quality_cache_test.dart` 34 项通过，其中新增 2 项验证 Emby 转码绝对位置和暂停状态保持。
- 设置 `REELNEST_MPV_PATH` 后，`player_marker_skip_native_test.dart` 新增 1 项及 `player_precision_native_test.dart` 原有 1 项通过；两项测试在默认全量命令中均跳过，已分别启用复验通过。
- marker skip native 用真实 mpv session 和解码时钟、open/seek/play/pause 桥接验证提示与自动跳过；轨道控制仍为 stub，未创建 Flutter 原生窗口。因此这项证据不能描述为真实窗口 UI 或 UI 验收。
- 前端 `player_marker_skip_ui_test.dart` 3 项定向 UI 组件测试通过。测试夹具的计时器/数据库清理和 `AnimatedSwitcher` 等待已修复；前端未因此修改产品源码。
- 最终整合：`flutter analyze --no-pub` 无问题；`dart format --output=none --set-exit-if-changed lib test` 检查 235 个文件，0 改动。Windows Release 构建成功，用时 36.5 秒；`apps/client/build/windows/x64/runner/Release/data/app.so` 更新时间为 2026-10-13 14:51:25。
- `scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 2026-10-13 14:52:07 +08:00 通过：窗口有响应、正常关窗、退出码 0；仅有正常 Impeller 日志，无数据库关闭异常。
- `fvm flutter test --no-pub --concurrency=1` 最终结果：**609 项通过、2 项默认跳过**，用时 02:05，退出码 0。两项需本机 libmpv 的 native 测试已分别启用并通过，因此本批总测试结果为 611 项通过（默认全量 609 项 + 单独启用 2 项）。首次整合运行因 UI 测试夹具清理失败而中止，不计为通过；修复夹具清理和 `AnimatedSwitcher` 等待后重跑通过。该修复仅改 UI 测试，没有修改产品 presentation。
- 本批代码与 Windows 自动化验证完成；真实 Emby 完整流程、实体键鼠、macOS/Linux 原生及原版视觉对照仍需分别验收。三项 UI 测试是组件验证，不等于可见原生窗口或像素级验收。

### 后续播放器外观调整（2026-10-13）

片头/片尾批次后，前端继续调整 `video_player_page.dart` 与 `player_visuals.dart`：播放器背景及顶部/底部渐隐、玻璃质感加载/错误状态、控制条投影与高光、圆形玻璃按钮和主播放按钮、6px 时间轴，以及桌面 hover 状态。播放流程、弹窗和快捷键未改。

- `flutter analyze` 无问题；`playback_test.dart`、`player_marker_skip_ui_test.dart`、`slider_overlay_scope_test.dart` 共 **26 项定向测试通过**。两文件格式检查 0 变化，`git diff --check` 通过。
- Windows Release 构建成功，用时 37.0 秒（记录：`apps/client/marker-build.log`）。`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 2026-10-13 16:08:38.498 +08:00 通过响应、正常关窗，退出码 0（记录：`apps/client/build/smoke/release-startup.json`）。
- **609 项通过、2 项默认跳过及另行启用的 2 项 native 测试，是本次纯外观调整前的全量测试基线。** 外观调整后未重跑全量测试；本次证据仅为上述 26 项定向测试、分析、格式、Release 构建和启动冒烟。
- 这些改动和验证不代表原版像素级视觉验收完成，也不代表 macOS/Linux 原生验收完成；外观仍需按原版逐项对照。

### 播放器窗口 chrome 与控制栏视觉优化（2026-10-14）

播放器视觉优化的后续增量：`player_window_app.dart` 在桌面播放器窗口配置中隐藏标题栏；macOS 保留系统原生窗口按钮，Windows/Linux 使用应用内窗口控制。`video_player_page.dart` 增加可拖动顶部窗口区，Windows/Linux 提供最小化、最大化/还原和关闭按钮；底部玻璃控制栏改为斜向渐变边框，控制按钮 hover 缩放收敛到 1.018、阴影减轻。`player_visuals.dart` 按原 Swift `VideoControlPalette` 恢复阴影透明度：lightContent 0.08、darkContent 0.10。功能、播放内核、精确控制和操作流程未变。

- `playback_test.dart` 增加窗口 chrome 存在性与 Windows/Linux 按钮回归；播放器相关测试共 **69 项通过**。
- 全量 `flutter test` **616 项通过、2 项既有测试跳过**；静态检查通过。Windows Release 重构建成功，五秒客户端启动烟测通过。
- 未进行 macOS/Linux 原生窗口人工目视或像素级验收；测试中的平台分支不能替代真实原生外观验收。

### P0 播放器前端视觉收口（2026-10-14）

本批仅整理播放器 presentation，不修改播放业务规则、播放内核、精确控制或操作流程。

- `player_visuals.dart` 增加可复用的 `PlayerPanelSurface`、`PlayerPanelEntrance`、`PlayerControlSurface`、`PlayerMenuRowSurface`，并补齐原 `VideoControlPalette` 的 choice/control 颜色。
- 控制栏按钮统一提供 hover、键盘焦点、禁用和弹层打开选中态；Windows/Linux 关闭按钮加入危险 hover 状态。字幕、音轨、画质、剧集、音量、设置、标记弹层及精确播放右键菜单统一采用静态不透明面板、渐变描边和阴影；大型弹层不使用实时模糊，避免影响视频帧率。
- 弹层采用 140ms 入场淡入及 5px 位移；Esc 关闭仍即时生效。启用减少动态效果时不播放入场动画。顶部操作提示调整为原版风格的玻璃胶囊与状态图标。
- 5 个 presentation 文件 `flutter analyze` 通过。`playback_test.dart`、`player_tracks_test.dart`、`emby_quality_panel_test.dart`、`player_marker_skip_ui_test.dart`、`player_basic_settings_test.dart`、`slider_overlay_scope_test.dart` 共 **62 项通过**。
- Windows Release 构建成功；`scripts/windows-smoke.ps1 -ObservationSeconds 5` 通过，隐藏窗口有响应、正常关窗、退出码 0，stderr 仅 Impeller OpenGLESSDF 提示。
- 本批**未运行全量测试**。此前 616 项通过/2 项既有跳过是上一批 chrome 优化的全量基线，不代表本批修改后全量源码重新验证。macOS/Linux 原生窗口人工目视、真实 Emby 视觉验收和原版逐像素对照仍未完成。

### P0 播放器第二轮：窄窗口、自隐藏与音量 HUD（2026-10-14）

本轮继续只调整共用播放器 presentation/交互反馈，不改变播放规则或内核：

- 控制栏在窗口宽度 `<760` 时进入窄布局，左右操作区分别收为 176/112；画质按钮仅显示图标并保留 tooltip，正常宽度继续显示文字，功能入口没有删减。
- 对齐原 MediaLib 的控制层/光标行为：播放中且控制层与弹层都隐藏时隐藏鼠标光标；鼠标移动恢复控制层。过滤极小指针抖动，控制层自动隐藏延迟 3200ms。
- 方向键上下调音量与 `M` 静音显示独立音量 HUD（状态图标、进度和百分比），950ms 后退出。音量快捷键只显示 HUD，不强制唤醒完整控制栏。
- `playback_test.dart` 增补/覆盖窄窗口布局、控制层自动隐藏、光标隐藏、静音 HUD 与 HUD 消失等回归。

验证：`fvm flutter analyze --no-pub` 通过；6 个播放器相关测试文件共 **62 项通过**；`fvm flutter build windows --release --no-pub -t lib/main.dart` 成功；`scripts/windows-smoke.ps1 -ObservationSeconds 5` 通过，窗口响应、正常关闭、退出码 0。

本批不是全量测试；之前的 616 项通过/2 项既有跳过是更早一批结果。macOS/Linux 原生实机、真实 Emby 播放及人工可视化验收尚未完成，Flutter 组件回归不能替代这些验收。

### 提交前整合复验（2026-10-14）

本次复验针对当前整合工作树，覆盖两轮播放器 P0 UI、侧栏/Emby 页面与交互、ReelNest Logo 资源及应用图标等合并改动；不是单一播放器批次的专项结果。

- `fvm flutter test --no-pub --concurrency=1`：**616 项通过、2 项跳过**。两项为默认关闭的原生专项用例；各专项历史记录及其单独启用结果仍以对应批次为准。
- `fvm flutter analyze --no-pub`：无问题。`dart format lib test` 检查 235 个文件、0 修改。
- Windows Release 为当前代码构建：`app.so` 时间为 10:26:11，且代码与资源均没有晚于该产物的更新文件。
- `scripts/windows-smoke.ps1 -ObservationSeconds 5`：2026-10-14 14:20:55.8976419 +08:00 检查，隐藏窗口响应、正常关闭，退出码 0。
- 该整合复验不扩大平台声明：macOS/Linux 仍无真实原生构建与实机验收，真实 Emby 完整流程及原版 UI 逐项视觉验收仍待完成。自动候选生成/审核仍仅为规划，代码精简尚未开工。

### 播放器 P1-A：剩余时间、控制栏锁定与播放信息（2026-10-14）

本批在共用播放器中补齐原版 P1-A 前端能力，不代表 P1-B/P1-C 或完整播放器迁移完成：

- 时间轴尾部时间可点击切换“总时长/剩余时间”；默认显示总时长，剩余时间开关通过现有 `PlaybackOptions` 持久化，并加入播放器“更多设置”。
- 画面右侧增加控制栏锁定入口。锁定后播放或暂停状态下都收起控制栏，鼠标移动不唤回；保留始终可见的解锁入口，锁定时光标保持可见。解锁后恢复控制栏及原自动隐藏行为。
- 增加居中播放信息面板，列出来源、类型、时长、已有分辨率/编码/封装/码率、文件大小、当前清晰度、音轨、字幕、倍速/音量和循环状态。只显示当前可用数据，缺失值明确显示“未知”，不从文件名或播放地址推断。`I` 切换面板，`Esc` 优先关闭面板；精确播放右键菜单加入“播放信息”入口。
- 6 个播放器相关测试文件共 **62 项通过**，覆盖剩余时间默认值/持久化、`I`/`Esc`、右键入口、控制栏锁定的播放/暂停行为及语义树。`fvm flutter analyze --no-pub` 通过，Windows Release 构建成功；2026-10-14 14:45（+08:00）五秒 smoke 窗口响应、正常关闭、退出码 0。
- P1-A 后未重跑全量测试。提交前 **616 passed / 2 skipped** 是本批之前的整合基线，不代表本批代码的全量结果。`git diff --check` 仅有 LF/CRLF 提示。
- 本批结束时真实 Emby 播放、人工可见窗口验收及 macOS/Linux 原生实机验收尚未完成；P1-B/P1-C 当时仍待实现。后续 P1-B 状态见下节，P1-C 时间轴进度预览仍未实现。

### 播放器 P1-B：迷你悬浮窗与窗口置顶（2026-10-14）

P1-B 已完成代码及 Windows 自动化验证；不代表迷你窗已通过真实窗口人工目视，也不代表 macOS/Linux 原生验收完成。

- 精确播放右键菜单和 `P` 快捷键均可切换迷你悬浮窗。尺寸依据优先采用解码器实际视频宽高比，其次使用远程媒体分辨率，缺失时默认 16:9；优选宽度约 380px，并满足至少 280×168 的最小尺寸规则。窗口定位到当前屏幕右下角并留 16px 边距，进入后强制置顶。
- 迷你控制层提供播放/暂停、还原与关闭；双击画面及 `Esc` 可还原原窗口。全屏状态拒绝进入迷你模式并给出提示。
- 退出迷你模式时恢复原窗口的位置、尺寸、最大化状态及用户置顶偏好。播放器更多设置增加“窗口置顶”，偏好经 `PlaybackOptions` 持久化。
- 桌面窗口管理统一使用 `window_manager`，屏幕信息通过直接依赖 `screen_retriever` 获取；macOS 迷你窗设置为跨空间显示。新增 `player_window_coordinator.dart` 集中协调窗口状态，`MediaKitVideoEngine` 暴露实际视频宽高比，并新增协调器测试。
- `flutter analyze --no-pub` 无问题；7 个相关测试文件 **66 项通过**；全量 `flutter test --no-pub --concurrency=1` **620 passed / 2 skipped**；Windows Release 构建成功（36.2 秒）。2026-10-14 15:01:30（+08:00）Windows smoke 通过，窗口响应、正常关闭、退出码 0。
- 这次全量及 Windows 自动化结果覆盖 P1-B 工作树，不覆盖后续 P1-C。smoke 不构成迷你窗真实画面/交互目视验收；真实媒体可见窗口人工验收及 macOS/Linux 原生实机仍待完成。P1-C 当时尚未实现，现状见下节。

### 播放器 P1-C：时间轴预览图（2026-10-15）

P1-C 实现及 Windows 自动化验证已完成；真实 Emby、人工可见窗口和跨平台最终验收仍待完成。

- 播放设置新增“预览图”三档：关闭（仍显示时间气泡）、流畅优先（默认，粗分桶并防抖 120ms）、画面优先（细分桶、防抖 45ms，并预取相邻画面）。悬停与拖动时更新预览；拖动过程中只更新预览，释放后才 seek；浮层为原版 148×83，并在时间轴左右边缘钳制。
- 预览解码使用独立、静音的 headless mpv，不操作主播放器的 seek/播放状态。生成并发限制为 1；帧缓存最多 160 项/32MiB，同桶请求合并；切片取消、换片隔离，并避免取消请求破坏共享请求或释放仍被 native decoder 使用的资源。
- 远程视频经本机有界 Range 代理读取，不持久化凭据、不请求额外转码会话；上游不支持安全 Range 时失败关闭并返回空预览，不退化为整文件下载。离线缓存媒体通过租约持有，预览完成后释放。
- `flutter analyze --fatal-infos`：零问题；全量 `flutter test --no-pub`：**643 passed / 3 skipped**。专项时间轴交互与语义树回归通过。
- 启用 `REELNEST_MPV_PATH=.../Release/libmpv-2.dll` 的 native 抽帧专项 **1 项通过**：独立 headless 解码器输出 312×176 PNG；验证期间主播放器位置、暂停状态及音量保持不变。
- Windows Release 构建成功，用时 **42.3 秒**。2026-10-15 10:01:54（+08:00）`scripts/windows-smoke.ps1 -ObservationSeconds 5` 通过，窗口响应、正常关闭、退出码 0。
- 为避免 Overlay Portal 造成语义树孤儿，控制栏实现调整为背景独立圆角裁剪、内容位于非裁剪锚定层；语义树专项回归通过。
- P1-B 的 **620 passed / 2 skipped** 全量及 Windows Release/smoke 是 P1-C 之前的历史基线。当前 P1-C 自动化已完成，但以上 Windows smoke 和抽帧专项不等于真实 Emby、人工可见窗口交互/视觉或 macOS/Linux 原生实机验收；这些最终验收仍待完成。

## 验证与边界

- 130 项相关 Dart 回归通过，覆盖播放、设置、字幕音轨、队列、Emby 播放与画质缓存，以及新增标记/循环规则。
- 2026-10-13 前端接入后，播放器 presentation 静态分析无问题；`playback_test.dart`、`player_precision_test.dart`、`emby_quality_panel_test.dart` 共 38 项定向回归通过，其中组件测试覆盖标记弹层、进度条刻度、A–B 状态、右键菜单、单片循环、前后逐帧及快捷键。
- Windows 使用已有 `libmpv-2.dll` 与本地生成的 Matroska，真实验证章节读取、前后逐帧、A–B 区间回跳与整片循环；未依赖用户 Emby 或媒体文件。
- 原生测试：`test/player_precision_native_test.dart` 与 `test/player_marker_skip_native_test.dart`，通过 `--dart-define=REELNEST_MPV_PATH=<libmpv绝对路径>` 启用；默认各跳过 1 项，避免普通单元测试隐式依赖本机构建。
- Windows 原生检查与 Flutter 组件测试是两条独立证据；当前仍不代表真实窗口渲染或原版像素级视觉验收完成。
- 真实 Emby 转码服务器、macOS/Linux 原生、三桌面端实体键盘及鼠标右键交互仍需后续验收。
- 第一批不实现预览缩略图、片头片尾识别/跳过、在线字幕或其他高级设置；模型保留原版标记类型不等于对应执行功能已迁移。
- 第一批接口未包含原版标记面板中的片头/片尾边界编辑、自动候选采用/忽略与跳过策略；当前批次已接入手动边界和跳过策略，自动候选审核仍未迁移。

### 前一批整合复查基线（2026-10-13）

以下记录属于当前片头/片尾批次之前的整合基线，不是当前工作树的提交验证；当前批次最终结果见上文。

- 修复视频未成功打开时按 `B` 或执行 A–B 菜单动作仍可能读取空 A 点的问题，并加入打开失败后的快捷键组件回归；提示入口同时防止组件销毁后更新状态。
- 当时 `flutter analyze --no-pub` 无问题；格式检查检查 232 个文件，无格式改动；`git diff --check` 通过。
- `flutter test --no-pub --concurrency=1`：587 项通过，1 项真实 mpv 测试按默认条件跳过。
- `flutter test --no-pub --concurrency=1 --dart-define=REELNEST_MPV_PATH=<Release/libmpv-2.dll 的绝对路径> test/player_precision_native_test.dart`：单独启用的 1 项通过，使用生成媒体验证章节读取、前后逐帧、A–B 与整片循环。
- `flutter build windows --release --no-pub --target lib/main.dart` 成功，产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。
- `scripts/windows-smoke.ps1 -ObservationSeconds 5`：Release 隐藏窗口创建、五秒响应、正常关窗通过，退出码 0；本次输出无数据库关闭异常。
- 原生播放测试不使用用户服务器或媒体；启动检查使用本机现有应用数据，不执行媒体扫描或播放写回。未完成真实 Emby 全流程、播放器可见画面/实体键鼠、滚动性能、macOS/Linux 原生及原版 UI 对照验收。

### 2026-10-15 候选审核开发前提交基线

P1-A/B/C 播放辅助及本日 Emby 超大响应分页自适应、来源全部条目计数合并后，重新执行全量验证：`flutter test --no-pub --concurrency=1` 为 **652 passed / 3 skipped**；三个默认跳过项依赖显式启用的真实 mpv。`flutter analyze --no-pub` 无问题；250 个 Dart 文件格式检查无变化，差异空白检查通过。当前正式 Release 的最后构建及五秒启动检查沿用计数修复后的成功结果（2026-10-15 10:40:14 +08:00），详见 `EMBY_LOADING.zh-CN.md`。本记录不代表真实 Emby 播放、实体键鼠或 macOS/Linux 原生验收完成；自动片头片尾候选仍待下一批实现。

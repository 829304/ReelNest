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

## 当前 UI 批次：播放器控制栏 Dock 重构（2026-10-15）

状态：控制栏布局与视觉实现已更新。此前六个播放器相关测试文件 **62 项**通过，全项目 `flutter analyze --no-pub --fatal-infos` 无问题，260 个 Dart 文件格式检查 0 改动，差异空白检查通过。最新固定深色 Chrome 更新后，targeted analyze 无问题，`playback_test.dart` **20/20**、7 个播放器弹层相关测试 **47/47** 通过；Windows Release **34.5 秒**构建成功。2026-10-16 **11:03:30 +08:00** 五秒 smoke 通过：窗口响应、正常关闭、退出码 0。此 smoke 不等同真实 Windows 可见窗口视觉/实体键鼠验收；macOS/Linux 原生目视及三桌面端 UI 对照仍待。

本轮从原依赖画面明暗、宽 **568 px** 的浅色玻璃控制条调整为最大宽 **720 px** 的响应式深色悬浮 Dock。此前宽 **700 px** 测试窗口实测 Dock 为 **664×76 px**；本次最终收敛高度为 **72 px**。圆角 **16 px**，水平/垂直内边距 **16/6 px**。时间轴区域高 **24 px**、轨道 **3 px**；主播放按钮从 **38×38 px** 收敛为 **34×34 px**，播放图标 **18 px**；辅助按钮为 **32×32 px**、图标 **17 px**。紧凑布局左右组为 **160/94 px**，宽布局为 **196/100 px**。片头/片尾提示 bottom 从 **136 px** 调整为 **114 px**，仍不与时间轴命中区冲突。迷你悬浮窗只保留 Dock 按钮，`P` 快捷键仍可用；右键精度菜单中重复的“迷你悬浮窗/还原窗口”入口已删除。深色材质、hover/focus/pressed/selected 动效、几何居中及其余原有功能映射和弹层入口保留。

控制栏锁定入口同步统一为固定 **36 px** 深色玻璃圆形控件，替代原自适应浅色 `PlayerPanelSurface`。未锁定时显示 19 px 白色 `lock_open_rounded`；锁定后显示白色强调圆面与深色 `lock_rounded`。两态以 **160 ms fade+scale** 切换，保留“锁定控制栏/显示控制栏” Tooltip、Semantics toggled、鼠标 hover/pressed/focus 反馈和原锁定逻辑。`playback_test.dart` 增加 36 px 尺寸及开锁→闭锁→开锁图标回归。

播放器页应用固定深色 Chrome 色板，覆盖 Dock、右键精度菜单、字幕/音轨/剧集/音量/设置/画质/标记面板，以及音频设备、字幕字体等嵌套菜单；不再随海报明暗切换为浅色。播放器页局部 `TooltipTheme` 统一字幕、音轨、章节/标记、画质、时间、音量、设置、迷你悬浮窗、全屏和锁定等操作提示，样式为半透明深灰黑底 `#F21A1D22`、白字 `#F2FFFFFF`、细白描边 `#29FFFFFF`，默认向上显示。该局部主题只作用于深色播放器，不改变媒体库等普通页面的主题。

播放器加载态移除 `_loadingOverlay` 外层 `_statusGlass` 矩形玻璃卡片（无背景、边框、模糊或阴影面板），只保留居中的 **42 px** 加载环和两行提示文字；文字增加轻微黑色 Shadow 以提高亮画面上的可读性，并提供 `player-loading-overlay` liveRegion 语义。`slider_overlay_scope_test.dart` 回归检查加载态节点与文案存在，且该节点祖先没有 `BackdropFilter`。

错误态同样移除“内置播放器无法播放”外层深色玻璃矩形卡片及 `BackdropFilter`，只显示居中的禁播图标、标题、错误原因和紧凑“重试”胶囊按钮；图标与文字带轻微黑色阴影，新增 `player-error-overlay` 语义 key、liveRegion 和完整 label。无其他调用后删除 `_statusGlass` helper。`slider_overlay_scope_test.dart` 增加错误态回归，检查错误信息和重试入口存在，且 `player-error-overlay` 不在 `BackdropFilter` 下。

实现位于 `apps/client/lib/features/playback/presentation/video_player_page.dart`，对应组件回归更新于 `apps/client/test/playback_test.dart` 与 `apps/client/test/slider_overlay_scope_test.dart`。最新 Chrome 色板/菜单入口调整后，targeted analyze clean，`playback_test.dart` **20/20**，7 个播放器弹层相关测试 **47/47**；Windows Release 34.5 秒成功，2026-10-16 11:03:30 +08:00 五秒 smoke 窗口响应、正常关闭、退出码 0。该 smoke 未覆盖真实可见窗口视觉或实体键鼠，macOS/Linux 原生目视验收仍待。此前 10:54 的 20/20、34.4 秒和 10:46 的 20/20、36.5 秒均为前序更新结果。

## 当前批次：播放故障诊断与加载健壮性（进行中，2026-10-16）

状态：本轮实现与 Windows 验证已完成。最终改动包含 engine `finally` 的三行兜底错误确认及删除测试 unused import；之后重新启用 `REELNEST_MPV_PATH=Release/libmpv-2.dll` 的 `test/video_load_native_test.dart`，**1 项通过**，`flutter analyze --no-pub` 无问题，`dart format lib test` 检查 **265 个文件、0 改动**，`git diff --check` 通过。全量 `701 passed / 4 skipped`（2:32，exit 0）是在这最后小补丁前完成，未为三行改动重跑全套；不得混作最终代码状态的全量回归。

Windows 正式 `lib/main.dart` Release 构建成功（**40.8 秒**）。AOT `apps/client/build/windows/x64/runner/Release/data/app.so`：2026-10-16 01:12:31（+08:00），11,764,616 字节。2026-10-16 **01:12:55.4413209 +08:00** 五秒 smoke 通过：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`；stderr 仅有正常 Impeller 提示。此结果不代替真实 Emby 业务复现或 macOS/Linux 原生验收。

### 诊断日志与隐私

- 新增 `apps/client/lib/player/playback_diagnostics.dart` 与 `video_load_monitor.dart`。播放器窗口创建诊断 sink；每次 `PlaybackSession.open` 创建不含媒体身份的 attempt，session 与 engine 共用同一 trace。阶段包含 `source`、`preferences`、`cache`、`emby resource`、`queue`、`engine config`、`open`、`ready`、`tracks`、`previous release`、`timeline`、`track prefs`、`surface`、`play`、`records` 和 `playback`。
- 持久化到应用 support 目录 `logs/playback-<pid>-<microseconds>.jsonl`。单文件达 **512 KiB** 后滚动一份 `.previous`；队列上限 **256 条**。初始化或轮转时尽力清理本模块文件：保留 **7 天**且最多 **20 份**；清理范围仅匹配本诊断模块文件。写日志失败不影响播放，关闭窗口时刷盘。
- 字段限于阶段、`elapsedMs`、异常类型、安全 package 或 Dart 堆栈（最多 **12 帧**）、HTTP 状态与分类。不得保存原始异常文本、mpv 原始文本、媒体 ID/名称/路径、播放 URL、令牌/凭据或字幕内容。

### 就绪、错误分类与取消清理

- 不再只依赖 duration 判断就绪：当 mpv `idle-active=no` 且（时长大于零或存在有效 video/audio params）时可判定 ready，兼容没有时长元数据但已建立可播放媒体流的情况。
- 单条 mpv error 事件不立即判定播放失败；需结合 `idle` 状态确认，并允许 decoder fallback。HTTP 状态需在异常回退/映射中保留，避免 generic 错误覆盖具体分类；真实 mpv 的 HTTP 503 即便处于 warn 级别也要分类并记录状态。
- 保留 **20 秒** readiness 与 **25 秒**外层解码预算；画面 surface 挂接新增 **10 秒**上限。dispose 时取消等待，各异步 await 后检查对象是否已销毁；清理异常不得覆盖原始失败，也不能让 loading 状态残留。

本批仅增强播放内部诊断及已确认故障路径，不改变产品功能、UI、日志对用户媒体的身份暴露或服务端行为。用户报告的间歇 Emby 播放失败没有对应的历史诊断日志；本批修复的是已确认的错误处理与诊断缺口，尚不能断言已确定其真实根因或已彻底修复该服务器问题。新日志只会在安装新版 EXE 后，从后续播放尝试开始生成，不能回溯旧故障。Windows 日志目录为 `C:/Users/hzx/AppData/Roaming/io.github.user829304/reelnest/logs`；字段中的时间为 UTC ISO 8601，按香港时间查看需换算 +08:00。未连接真实 Emby，也未修改用户媒体数据。用户间歇故障仍待安装新版后实际复现并依据新日志诊断；macOS/Linux 原生未验收。

## 当前批次：检测入口、系列批量分析与任务中心（2026-10-15）

状态：代码与 Windows 自动化验证已完成（685 passed / 3 skipped、分析、Release 和启动检查通过）；真实来源、三端原生与视觉验收仍待。开发前基线为 `fab5dda`，668 passed / 3 skipped 是上一批结果。范围沿用原版已有能力，在线字幕、字幕样式与音频延迟本批不展开。

原版依据为 `64f8ee2` 的 `VideoCacheMenuItems`、`AppState.playbackMarkerAnalysisItems` / `runIntroOutroMarkerAnalysisTask`、`BackgroundTaskSnapshot` / `BackgroundTaskRetryPolicy` / `BackgroundTaskListPolicy` / `BackgroundTaskPersistence` 及 `BackgroundTaskCenterView`。此前单视频候选批次的识别与审核规则继续复用，下面仅补入口、调度与历史。

- 媒体条目右键“检测片头片尾”进入后台任务：有直属子项则分析符合资格的直属视频，否则分析自身。音乐、照片、未知时长及不大于 60 秒的条目不参与。复用已入库的远程时长或已有播放记录时长；本地尚无时长时不猜测、不扫描视频文件。系列仅覆盖当前已载入的符合资格单集，不自动补全服务器目录或等待全库同步。
- 检测只读已存内嵌章节，不启动 mpv、FFmpeg、视频下载或全库扫描。没有有效章节时结果为没有发现可审核候选；pending、accepted、rejected 和手动保护沿用前批规则。
- 本地影片/系列/单集、Emby 条目、详情海报和首页卡片接入原入口；移除播放器标记弹层的临时检测按钮，候选采用/忽略继续保留。检测资格在右键时查询，首次绘制海报不逐卡探测，也不因异步资格刷新拆换卡片组件；查询跨帧时持有临时订阅，卡片重用/卸载及旧菜单回传均核对身份。
- 任务中心合并检测任务与既有扫描/缓存任务，显示准备/已分析进度、候选数量、完成/取消/失败，支持失败重试与清除记录；首页运行状态通过被动 `observedTasksProvider` 接收同一任务。`queued/running` 才是活跃任务；不在纯读取中自动重跑任务。
- 原版创建 markerAnalysis 任务时可取消、取消路由也已存在，但任务中心视图未渲染其取消按钮。本批按用户明确要求补齐这一可达性缺口；保留原取消语义，属于明确记录的缺陷修补，不把原版 UI 缺口宣称为已逐项复制。
- 相同 root 的并发启动复用一个任务，后台串行分析；每视频一个事务，范围/媒体版本发生变化则拒绝旧任务写入。Emby 当前选库范围参与资格查询，已取消选择但仍缓存的媒体不参与新检测/重试；库归属和视频版本也参与逐视频复核。取消在内层候选生成及外层提交前均检查，保留此前已提交候选；失败重试重新查询当前范围，不重放旧列表，也不重建同 ID 的已忽略候选。
- 任务记录写入既有 `player_preferences` 的 `global.markerAnalysisTasks`；持久化/恢复上限 60，新任务插入保留 40 条（运行中任务不被挤掉）。重启把未结束记录标为失败，手动重试；清除记录不删除候选。记录读写失败在任务中心提示，不能使已提交候选变成假失败或阻断播放器。
- 私密任务隐藏名称，来源变为私密或删除后遮蔽历史标题；原始异常、凭据、视频 URL 和章节内容不进入任务记录。主窗口退出先取消并等待检测、历史写入，再关闭数据库。后台提交后以来源身份通知已打开的播放器重读标记，通知失败不回滚已生成候选。

后端入口：`marker_analysis_repository.dart`（资格/范围与事务复核）、`playback_marker_analysis_controller.dart`（调度/取消/历史）、`marker_analysis_providers.dart`（资格与运行状态投影）、`marker_analysis_task.dart`（任务快照）。不新增数据库表或历史升级逻辑。

本批最终验证（2026-10-15，`fab5dda` 之后的工作树）：

- `flutter test --no-pub --concurrency=1`：**685 passed / 3 skipped**（02:27）。三个默认跳过项依赖显式配置的真实 mpv，本批未单独启用；历史 native 结果继续单独计证。
- 新增 `marker_analysis_test.dart` **14 项**，覆盖范围/时长、整组进度、来源隔离、Emby 元数据时长和当前选库、并发防重、排队/运行取消、内外事务取消、失败重试、配置/内容变更、历史恢复/清理/上限、私密标题、退出等待及记录读写失败。`marker_analysis_ui_test.dart` **3 项**覆盖右键懒查询/跨帧返回/原 root 入队、首页系列入口和任务中心操作；既有候选审核 **3 项**改为已生成候选的采用/忽略及迟到审核隔离。
- `flutter analyze --no-pub` 无问题；260 个 Dart 文件格式检查 0 修改，差异空白检查通过。首页动作与运行状态另有 **22 项**定向回归通过。
- 开发中修复了菜单关闭后才读取已销毁 WidgetRef 导致动作丢失的问题；测试夹具的 fakeAsync 内直接等待数据库导致挂起也已改正。一次定向命令误列不存在的测试文件，该轮未视为成功；最终全量覆盖当前实际测试文件并通过。整合中的 683 项和较早的 685 项仅作中间证据，不替代上述最终冻结版本结果。
- `flutter build windows --release --no-pub --target lib/main.dart` 成功（**41.0 秒**）。2026-10-15 **19:51:30 +08:00** 的 `scripts/windows-smoke.ps1 -ObservationSeconds 5` 确认隐藏窗口响应、正常关闭、退出码 0。使用本机既有应用数据，未主动启动检测、扫描或播放；产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。

仅使用生成的索引、章节和模拟服务夹具，不使用真实 Emby 进行本批业务写回。真实 Emby、已打开播放器窗口的跨引擎通知、实体键鼠、macOS/Linux 原生与原版视觉逐项验收仍须分别记录；Windows 启动检查不能证明上述业务闭环。

## 前一批：内嵌章节片头片尾候选（2026-10-15）

状态：单视频代码及 Windows 自动化验证已完成；真实来源、实体键鼠及三端原生/视觉验收仍待。本节描述候选批次；下方早期章节中“候选未迁移”仅为当时状态。

原版依据为 `64f8ee2` 的 `AppState.automaticIntroOutroCandidates`、`automaticMarkerKind`、`automaticMarkerRangeIsPlausible`、`reviewAutomaticPlaybackMarker`，以及 `PlayerView.PlayerMarkerPopover` 和 `PlaybackMarkerRepository`。识别只读内嵌章节元数据，不进行音视频内容分析、不额外下载、不触发全库扫描。

- 影片时长须大于 60 秒，章节必须有完整范围。片头长度 12–180 秒，起点不晚于 `max(总时长×35%, 420秒)`；片尾长度 12–720 秒，起点不早于总时长 45%。关键字、短词边界及 0.88/0.76 置信度按原版翻译，不把普通章号当片头片尾。
- 每次分析按时间为每类最多新增一个 pending 标记。已有完整手动或已采用范围不覆盖；已有候选 ID（含 rejected）不重建。若同类还有其他匹配章节，后续检测仍可生成不同 ID 的候选，这是原版规则。
- 待审核条目可跳到起点预览，但不参与跳过或有效时间轴刻度。采用后复用原有关闭/显示按钮/自动跳过，默认仍为显示按钮；忽略后从普通列表隐藏，记录留在数据库。
- 生成在事务内重新读取（含 rejected），取消导致候选写入回滚；审核只修改对应 `(source_id, local_id, id)` 的 pending automatic 行，保护手动、内嵌及其他来源数据，并防止迟到重复审核反转结果。沿用当前初始 schema，不增加升级或清库操作。
- 转码后缀章节不覆盖完整章节；仅有后缀观察结果时不凭偏移后的章节生成候选。持久化和跳过均使用影片绝对时间。保存失败保留可用解码器，通过 `controlError` 提示重试。

接口：`PlaybackMarker.isPendingReview`；`session.analyzeIntroOutroMarkers({ScanCancellation? cancellation})` 返回新增数量，取消、切换或失败返回 null；`session.reviewAutomaticPlaybackMarker(marker, {required accepted})` 审核后刷新 `precision`。审核命令返回完成并不保证成功，前端必须核对当前身份、结果状态及 `controlError`。

本批单视频检测暂接播放器现有“章节与播放标记”弹层，采用/忽略按原弹层结构接入。原版检测入口在 `VideoCacheMenuItems` 的媒体条目上下文菜单；该入口、系列批量分析和任务中心仍待迁移，本批不是这些入口的一比一验收，也不表示完整播放器完成。字幕样式和音频延迟未在本批实施。

验证结果（在开发前基线 `e3cbb8a` 之后的本批工作树）：

- `intro_outro_candidates_test.dart`、`player_precision_test.dart`、`player_marker_skip_test.dart`、`player_marker_candidate_ui_test.dart`、`player_marker_skip_ui_test.dart`、`emby_playback_test.dart` 六个文件共 **68 项定向回归通过**。覆盖原版关键字/范围阈值、手动保护、重复与并发生成、忽略持久化、事务取消回滚、写入失败重试、切集隔离、转码后缀保护，以及候选列表的采用/忽略与迟到结果隔离。
- 首轮新增 UI 测试因夹具在 fakeAsync 外等待清理而挂起，中止该测试进程后修复：组件卸载、延迟结果释放、会话/数据库关闭均在可泵送阶段完成。随后上述定向回归及最终全量均通过，不隐去首次未完成的事实。
- `flutter test --no-pub --concurrency=1`：**668 passed / 3 skipped**。默认跳过的真实 mpv 用例本批未额外启用；既有 native 证据仍属于各历史批次，不能代替候选功能的真实服务器验收。
- `flutter analyze --no-pub` 无问题，253 个 Dart 文件格式检查零改动；差异空白检查通过。初轮分析中的括号规则及测试夹具未使用可选参数警告已修正，最终分析无告警。
- `flutter build windows --release --no-pub --target lib/main.dart` 成功，耗时 **40.8 秒**。`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 **2026-10-15 14:53:36 +08:00** 确认隐藏窗口响应、正常关闭、退出码 0；该检查使用本机现有应用数据，不执行媒体扫描、播放或服务器观看状态写回。

本批 V1–V4 证据不表示候选在真实 Emby、实体键鼠或 macOS/Linux 原生环境已验收，也不证明原版逐像素一致。开发前基线 652 passed / 3 skipped 单独保留，不当作本批数字。

## 用户授权：播放器输入速率提示（代码冻结，Windows 验证完成，三端验收待定，2026-10-16）

用户确认播放器右上角持续展示播放输入速率：底部播放进度 Dock 显示时显示，Dock 自动隐藏时同步隐藏；不限定为缓冲/卡顿期间显示。这是明确授权的单项新增需求，其他产品范围约束不变。

后端已实现 `VideoClock.networkBytesPerSecond`（`int?`，bytes/sec），通过 mpv `cache-speed` observe 更新。仅 HTTP(S) 视频资源赋值；未知速率、非 HTTP(S)/本地/离线来源为 null；0 是有效读数；切换资源时先清空，转码 session 的时间轴映射保留。mpv 将 `cache-speed` 定义为缓存到下层输入源方向的当前 I/O 读取速度，以约一秒窗口统计；底层 `raw-input-rate` 是网络层或其他字节输入层的估算，可能不准确或缺失。它表示播放器观测到的输入速率估计，不代表整机总网速。参见 [mpv 官方属性说明](https://mpv.io/manual/stable/#properties)。

后端/Emby 相关自动化 **54 项通过**。新增 `test/video_network_speed_native_test.dart` 使用本机节流 HTTP 视频流验证实际 `cache-speed` 可产出大于 0 的输入字节率；暂停播放时缓存预取期间仍可读取速率。该原生用例与既有加载/HTTP 503 原生测试文件分别在隔离进程运行，合计 **2 项通过**。曾尝试在同一测试文件连续创建两个播放器，第二个用例的 503 日志状态丢失；改为沿用原生用例的独立进程隔离后复验通过。此结果不证明或修复底层库的多实例日志行为。

UI 已完成并冻结：HUD 只局部订阅 timeline 速率，避免外层 timeline 订阅引发播放器整页高频重建；与底部控件共用 `shouldShowPlayerControlLayer` 可见掩码。仅已知远程资源且不在 mini/lock 状态时显示；显示与 controls/paused/loading/error 同步。在线媒体 loading/error 或尚无速率时显示 `-- KB/s`；有效 0 显示 `0 KB/s`。小于 1 KB/s 显示小数，KB/s 与 MB/s 以 1024 换算。尚未识别来源、非远程路径、本地/离线来源不创建 HUD 项。视觉为 top 64/right 18，下载图标与阴影文字，无矩形底板；HUD `IgnorePointer`，避免拦截播放器操作。

本轮代码验证（不含完整全量测试）：`network-speed-backend.log` 对应 backend **54 passed**；`network-speed-ui.log` 对应 UI **27 passed**，其中含 **4 项速率 HUD** 测试及真实自动隐藏/鼠标唤醒、采样不续时、loading 未知值检查；`network-speed-native.log` 对应两个独立 native 测试文件合计 **2 passed**。增强后的速度 native 用例在同一进程内连续创建并关闭两个 Player；两次均观察到 `cache-speed > 0`，暂停期间也能读取预取速率。这证明本次速率采样的连续实例场景可用，但不证明另一用例遇到的多实例 HTTP 503 日志状态问题已修复。全项目 analyze 无问题，269 个 Dart 文件格式检查 **0 改动**，diff whitespace 检查通过。**本轮未重复上一轮 701 项全量**，该数字不是本轮验证结果。

正式 `lib/main.dart` Windows Release 构建 **39.6 秒成功**（`network-speed-build.log`）。AOT 产物 `apps/client/build/windows/x64/runner/Release/data/app.so` 于 **2026-10-16 01:27:35 +08** 生成，大小 **11,797,384 bytes**。五秒 smoke 于 **2026-10-16T01:28:42.7234575+08** 通过：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`；stderr 仅正常 Impeller 提示。该结果不代表真实 Emby、实体键鼠、macOS/Linux 原生或三桌面端 UI 视觉验收完成；上述项目继续待验收。

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

### Windows 播放器窗口 chrome 拖拽与 IME 焦点修复（2026-10-22）

非迷你播放器窗口顶部 chrome 调整为从窗口 y=0 开始、高 54px；标题区全宽及右侧 14px 拖拽带支持拖动，窗口按钮仍为独立点击目标。`playback_test.dart` 覆盖位置与高度，避免改变按钮命中语义。

Flutter 3.47.6 / Windows 11 10.0.26200 的失焦后 CJK IME 组合消息症状与 [Flutter issue #190042](https://github.com/flutter/flutter/issues/190042) 描述一致。窗口 inactive、hidden 或 paused 时仅在 Windows 主动 unfocus 当前 TextField；恢复后再次点击时重新连接当前 IME text client。此为 ReelNest Windows 侧的焦点生命周期处理，不改 macOS/Linux，也不宣称已确认 Flutter issue 的具体底层根因。

`app_test.dart`、`playback_test.dart`、`home_ui_test.dart` 合计 **61 项通过**，`flutter analyze` clean。Windows Release 43.7 秒成功；2026-10-22 09:28:12 +08:00 五秒 hidden smoke 的窗口响应、正常关闭及退出码 0 均通过。阶段概要见[2026-10-22 Windows 修复](NEXT_STAGE.zh-CN.md#2026-10-22-windows-播放器窗口-chrome-拖拽与-ime-焦点修复)。

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

## 2026-10-22 播放器截图实现与验证

领域 `VideoScreenshotMode` 以 `subtitles`（带字幕，默认）、`video`（纯视频）、`window`（窗口所见）表示；持久化于既有 `player_preferences` 的 `global.videoScreenshotMode`，值为 enum `name`。`Session` 提供 `screenshotMode`、`canCaptureFrame`、`capturingFrame`、`setScreenshotMode`、`captureCurrentFrame`；成功给出 PNG 绝对路径，失败返回安全展示消息的 `VideoScreenshotFailure`。用户可按无修饰 `S` 或从播放画面右键菜单选择“保存当前画面”，并在播放器设置“截图内容”选模式。成功反馈只显示 basename；未知错误使用固定安全提示。

`subtitles` / `video` 使用当前 mpv 对应截图模式；`window` 仅取视频渲染区域，含字幕和黑边、不含 Flutter 控制栏/HUD，保持原 `renderView` 兜底语义。不得改字幕选择或可见性、暂停/跳转/seek，不另开解码器。Windows 保存于 `resolvedExecutable.parent/userdata/screenshots/`（逐层真实路径校验，无外部目录回退）；macOS 保存于用户 Pictures 下 `ReelNest 截图/`；Linux 优先 `XDG_PICTURES_DIR/ReelNest 截图/`，否则 `HOME/Pictures/ReelNest 截图/`。PNG 文件名含影片标题和时间；重名不覆盖，原子发布、失败清理未完成文件并设尺寸限制。macOS/Linux 路径实现和单测已接入，尚无原生实机验收；不宣称移动端支持。

验证：store/session 新增 11 项、UI 两文件相关 31 项通过。全量 `flutter test --no-pub --reporter expanded` 显式设置 `REELNEST_MPV_PATH` 执行 native，**859 passed / 1 skipped**（45 秒，唯一跳过为可选排序性能基准）；`dart analyze lib test integration_test` 无问题；348 个 Dart 文件 format 0 changed；`git diff --check` clean。

Windows Profile 最终 `integration_test/video_screenshot_test.dart` 的 GPU/SW 两项实际功能用例通过（runner 汇总 3 项含 tearDown，13 秒），覆盖三模式、字幕有无、PNG 像素/尺寸、黑边及无 HUD、图像变换、播放/暂停状态不变、每种 renderer 8 次旋转/resize 截图循环，以及 loopback Range HTTP 播放截图不新增请求；最终 native 运行包含 raw 格式 `bgr0`/`bgra` 校验。既有 `video_viewport_test.dart` GPU/SW 两项实际功能用例也通过（runner 汇总 3 项，2 秒）。

Windows Release 构建 **40.5 秒成功**，EXE 为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`；2026-10-22 14:33:44.0518851 +08:00 五秒 smoke 的 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0` 均通过。未使用真实用户 Emby 服务器验收，原版 UI 视觉逐项对照仍待完成。

Windows 调试中观察到既有 `media_kit_video` resize 时 texture callback 注册竞态：mutable `texture_id_` 在重注册期间被 `map.at` 查找，Profile 本机两次崩溃；minidump 与 SDK PDB 将位置定位到 `flutter::ExternalTextureD3d::PopulateTexture`，随后 `std::terminate`。已在项目自有 `windows/media_kit_viewport.cmake` 生成的项目源码修复：callback 捕获各自注册 ID，旧 ID 撤回和新 descriptor/ID 发布由同一 mutex 同步，旧 callback 或缺失记录返回 null；GPU/SW 均覆盖，最终旋转/resize 循环回归通过。此记录只描述已观察到的竞态和对应修复，不确诊所有历史崩溃，也不代表 macOS/Linux 原生验收完成。排查工具和 dump 摘要只保存在 ignored `apps/client/build/screenshot-diagnostics`，不进入发行包；Pub 缓存未修改。

截图实现与 Windows 自动化验证已完成；macOS/Linux 原生实机、真实用户 Emby 服务器与原版 UI 视觉逐项验收仍待完成。不得外推为全平台验收或所有历史崩溃均已定位。

## 2026-10-22 视频播放器音频均衡器状态

视频均衡器已实现并通过 Windows 自动化验证：后端定向 17 项、UI 定向 14 项、显式 native 全量 873 passed / 1 skipped，Windows Profile GPU/SW 与 native PCM 五频/八预设验证通过；`dart analyze` clean，353 个 Dart 文件格式检查 0 改动。Windows Release 41.2 秒成功，2026-10-22 14:57:45.2163649 +08:00 五秒 smoke 窗口响应、正常关闭和退出码 0 均通过。真实设备听感、真实 Emby、macOS/Linux 原生及原版 UI 视觉验收仍待；详细证据见[视频均衡器计划](PLAYER_VIDEO_EQUALIZER_PLAN.zh-CN.md)。

### 2026-10-15 候选审核开发前提交基线

P1-A/B/C 播放辅助及本日 Emby 超大响应分页自适应、来源全部条目计数合并后，重新执行全量验证：`flutter test --no-pub --concurrency=1` 为 **652 passed / 3 skipped**；三个默认跳过项依赖显式启用的真实 mpv。`flutter analyze --no-pub` 无问题；250 个 Dart 文件格式检查无变化，差异空白检查通过。当前正式 Release 的最后构建及五秒启动检查沿用计数修复后的成功结果（2026-10-15 10:40:14 +08:00），详见 `EMBY_LOADING.zh-CN.md`。本记录不代表真实 Emby 播放、实体键鼠或 macOS/Linux 原生验收完成；自动片头片尾候选仍待下一批实现。

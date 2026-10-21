# 当前阶段与历史实施记录
本轮按原版 `VideoColorAdjustments.swift`、`VideoColorAdjustmentPolicy.swift`、`PlayerView.swift` 迁移亮度、对比度、饱和度、伽马、色相；范围 -100…100、默认 0、半值远离 0 取整、每步 ±5、单项重置。全局 JSON 偏好 `global.videoColorAdjustments`，无 schema，本地/Emby 共用；串行最新值合并、原生应用与保存、失败回滚告警及初始化非致命作为验收契约。实现细节及边界见[画面色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md)。
更新：2026-10-21。遵循[项目边界](PROJECT_SCOPE.zh-CN.md)。

## 2026-10-21 前端 P1-G：全局弹层与反馈表面统一

新增 `apps/client/lib/ui/widgets/app_feedback.dart`，提供 `AppFeedbackKind`、`showAppToast`、`AppInlineNotice`，统一普通页面的信息/成功/警告/错误反馈，浮动提示采用单层阴影。新增 `app_confirmation_dialog.dart`，统一普通页面确认弹窗的标题、副标题、正文，以及普通/危险确认语义；`app_theme.dart` 补齐 `DialogTheme`。

来源确认弹窗与设置表面复用公共确认样式；健康页、Emby 视频批量移除接入。普通页面直接使用的 `ScaffoldMessenger` SnackBar 改由 `showAppToast` 呈现。播放器内两处专用深色提示/失败弹窗仍保留独立视觉，不强行套用普通页面主题。全程保持原有业务流程、按钮语义和功能不变。

新增 `test/app_feedback_test.dart` 覆盖确认弹窗返回值和统一浮动反馈。`fvm flutter analyze --no-pub` 无问题；关键回归 **110 项通过**；本批全量 **834 项通过、9 项既有条件测试跳过**。2026-10-21 统一提交前对最终完整工作区再次复验：显式设置 `REELNEST_MPV_PATH` 的全量 **843 passed / 0 skipped（40 秒）**，全部 9 项 native 实际执行；`dart analyze lib test integration_test` 无问题，339 个 Dart 文件 format **0 changed**，`git diff --check` 无错误。这是整合复验，与本批原始 834/9 结果分别记录。该次复验未重建；最新 Windows Release 仍为 **36.6 秒成功**，2026-10-21 16:20:50 +08:00 五秒 Windows smoke 的窗口响应、正常关闭和退出码 0 均通过。

## 2026-10-21 前端 P1-F：仪表盘与任务中心视觉收口

新增 `apps/client/lib/ui/widgets/dashboard_surfaces.dart`，提供共享 `DashboardPageHeader`、`DashboardSectionHeading`、`DashboardPanel`、`DashboardStatusBadge`、`DashboardNotice/Toast`、`DashboardEmptyState`、`DashboardIconAction` 表面组件。`library_health_page.dart` 统一页头/操作、加载/错误/空状态、监测中心与健康详情分区，缓存卡移至概览之后；健康业务、忽略/恢复和安全清理边界保持不变。`health_overview.dart` 概览卡改为 4/2/1 列响应式布局。`emby_task_center.dart` 统一扫描、片头片尾分析、离线缓存任务的状态徽标/进度/操作，并收口自动缓存订阅与缓存用量表面。

不新增检测规则、后台任务或数据库变化。定向 `health_ui_test.dart`、`emby_offline_ui_test.dart`、`marker_analysis_ui_test.dart` 共 **25 passed**；最后一处任务徽标文案完成后再次运行定向测试 **25/25**，targeted analyze clean。全量 `flutter test --no-pub` **832 passed / 9 skipped**（总数 841），全项目 `flutter analyze --no-pub` clean 仍有效。最终 Windows Release **36.6 秒成功**；2026-10-21 15:23:53.2444446 +08:00 五秒 smoke 的 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0` 均通过。健康页 1088×720 明/暗主题截图人工复核通过；该截图复核不等同于原生实机视觉验收。

### 剩余验收

真实 Emby、实体鼠标/键盘、高 DPI、macOS/Linux 原生目视验收仍待完成。组件测试、截图复核和 Windows smoke 均不替代这些现场验收。

## 2026-10-21 播放后台性能优化（四项落地，自动化验证及 Windows Release/smoke 完成）

用户授权的四项后台优化已落地：

1. `PlaybackSession` 队列读取改用 `SourceRepository.playbackQueueCandidates`，避免读取整库 inventory。剧集队列只查父系列及同源、同父项的可播放集；电影仍跨全部来源读取根视频。保持既有排序、前后切换、不循环和自动播放规则；source lookup 跳过不需要的总数统计。
2. 每次打开时通过一次 SQL 读取 25 个相关偏好 key，复用原有解析、默认值和按组非致命告警；偏好快照只在读回调期间有效，回调结束清空，后续影片或控制操作仍读取最新值。
3. 合并同一事件批次的轨道/设备刷新；读取过程中若状态变化则追加尾读。显式控制操作等待最终读结果；关闭流程丢弃待补读并等待正在执行的读取结束。
4. 软件色彩表达式仅做等价代数简化：消除 0 项、简化单位乘法和 `pow(x, 1)`；无 hue/saturation 时使用精确单位矩阵。保持画质、分辨率及默认值不变。

### 验证结果

- 启用显式 `REELNEST_MPV_PATH` 的 Flutter 全量 **841 passed / 0 skipped（40 秒）**，全部 9 项 native 测试实际运行；`dart analyze lib test integration_test` 无问题；335 个 Dart 文件 format **0 changed**，`git diff --check` 无错误。
- 90,006 条媒体（其中 90,000 条为无关剧集）的 SQLite 内存 fixture 验证：原整库读取改为目标剧集只读 3 条（父系列 1 + 同父集 2）；根电影跨来源只读 2 条。该测试只记录受控 fixture 的读取数量，不据此承诺真实 Emby 性能收益或比例。
- 播放偏好完整 getter 原为 25 次 SQL，现为单次快照 1 次；覆盖同源系列共享、异源隔离、下一次读取可见新值，以及异常退出/异步子任务结束后不残留旧快照。
- 轨道刷新覆盖同批 100 个请求合并为 1 次读取；在途期间 100 次变化追加 1 次尾读；关闭时丢弃补读并等待在途操作，异常后可恢复。Windows Profile `video_performance_test` GPU/SW 各 1 个功能用例通过（摘要 3 项含 tearDown，8 秒），并覆盖新增 50 个刷新请求与音轨切换交错后的最终轨道。
- Windows Profile `video_color_test` GPU/SW 各 1 个功能用例通过（摘要 3 项含 tearDown，22 秒）。9 组颜色（含 BT.709/宽色域组合）旧/优化表达式平均纹理像素差 <0.5；GPU/SW、ASS 字幕、锐化、暂停尺寸等既有断言仍通过。
- 日志位于 `apps/client/build/playback-optimization-*.log`。Windows Release 首轮构建 39.1 秒成功；因构建期间前端工程师修正了 3 处过时选择器（不是本轮前端功能变更），随后最终增量构建 **26.4 秒成功**，以此作为最新构建结果。最终产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`；2026-10-21 14:55:53.5063042 +08:00 五秒 hidden smoke 的 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0` 均通过，报告为 `apps/client/build/smoke/release-startup.json`。

### 尚未验证

没有真实 Emby 性能对比、提升比例、macOS/Linux 原生验证或长时性能验收；不能由受控 fixture 推断真实服务器收益。Windows Release 构建与启动 smoke 通过不代表以上平台/场景也已验收。本轮优化仅涉及播放后台，不涉及前端布局或用户可见功能变更。

## 2026-10-21 前端 P1-E：首页视觉收口

对照原 MediaLib `HomeView.swift` / `HomeVividComponents.swift` 完成首页视觉收口，保留推荐、搜索、排序、播放、横向滚动、模块顺序/隐藏持久化及业务默认值。`home_page.dart` 统一启动加载、读取失败、部分同步和来源错误状态面板/行内通知，空状态补齐边框和品牌渐变图标；统计卡恢复原版渐变图标/数字与单层柔影，减少动态时不位移。`home_header.dart` 搜索框增加焦点边框/阴影及 search 输入动作；`home_video_row.dart` 的“查看全部”和翻页按钮改用首页色板，`home_video_card.dart` 增加键盘焦点轮廓并让 hover/focus 共用反馈。

Hero 支持键盘聚焦，聚焦时暂停自动轮播并显示边框/翻页控件，按钮动作不变。搜索结果统一摘要、部分结果、失败/重试与结果行表面并补键盘焦点；布局编辑入口/添加菜单统一明暗主题和边框。运行状态修正默认紫色并为三张卡增加焦点；内容宽度小于 720 时改为横向滚动卡组，宽窗口仍保持原版三列。`home_ui_test.dart` 增加视觉状态和 680×382 紧凑视口覆盖，并加固编辑入口可见性。

本轮未新增照片、音乐或首页模块，未改变推荐算法、数据或持久化。7 个首页相关测试文件共 **97 项全部通过**；全项目 `flutter analyze --no-pub` 无问题；Windows Release 构建 **37.3 秒成功**，产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`；`git diff --check` 无空白错误，仅有既有 CRLF 提示。

### 剩余验收

真实本地/Emby 混合数据、真实海报/长标题/大量内容、可见窗口实体鼠标键盘、高 DPI，以及 macOS/Linux 原生构建与实机视觉验收仍待完成。Flutter 自动化与 Windows Release 不代替这些验收。

## 2026-10-21 前端 P1-D：设置与服务器页面视觉统一

新增 `apps/client/lib/ui/widgets/settings_surfaces.dart`，提供统一设置页标题、54px 分区图标/标题/说明、内缩静态卡、34px 设置行，以及说明、路径、提示和确认对话框表面。`settings_page.dart`、`watched_settings.dart`、`video_cache_settings.dart`、`ignored_health_settings.dart`、`servers_page.dart` 迁移到该结构，统一明暗主题、层级、间距和控件配色。

观看阈值、缓存目录/容量/清理与任务中心、诊断忽略/恢复、外观切换及服务器登录/刷新/进入媒体库/退出行为均保留；退出后仍显示“还没有服务器”空状态。未新增 WebDAV、音乐、照片或未实现设置项。`sources_page.dart` 加载骨架在加载期间轻微呼吸，完成或错误后退出动画，并尊重 reduced motion，用于稳定异步错误态切换。

全项目 `flutter analyze --no-pub` 无问题；`library_smoke`、`health_ui`、`emby_offline_ui`、`emby_navigation` 相关测试共 **52 项全部通过**。Windows Release 构建成功，产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。`git diff --check` 无空白错误，仅有既有 CRLF 提示。

### 剩余验收

实机可见 UI、高 DPI、真实服务器登录/刷新/退出、缓存路径选择/清理、macOS/Linux 原生构建及实机验收仍待完成。组件测试和 Windows Release 构建不替代这些真实环境验收。

## 2026-10-21 前端 P1-C：媒体源管理与添加流程视觉收口

媒体源主页来源卡改为常态平铺，移除默认 Card 常驻阴影；悬浮/键盘焦点使用单层柔影和平滑上移，reduced motion 下不位移。卡片展示 52px 来源图标、名称、可达性/来源类型徽标、路径、条目数及上次扫描/同步时间，保留原有别名、浏览、设置、扫描/取消、重新定位、Emby 重新认证和移除入口；操作改为横向可滚动紧凑工具条。扫描进度/消息、忙碌、目录选择不可用、加载、错误和空状态统一为静态卡片材质；添加/扫描页头按钮统一。新增 `SourceConfirmationDialog` 替代重新定位与移除来源的默认 AlertDialog，移除继续以破坏性操作强调；别名弹窗改用统一 sheet 材质，保存失败时保持窗口。

本地添加、来源设置及 Emby 弹窗补齐 12px 安全边距和边框；Emby 登录/选库的忙碌、错误、空结果状态统一提示，痕迹同步下拉改为表单样式。所有扫描、登录、选库、保存、删除及重认证业务逻辑和默认值不变；未新增连接器，也未宣称完整三步向导已完成。

实现涉及 `sources_page.dart`、`source_alias_dialog.dart`、新增 `source_confirmation_dialog.dart`、`add_source_dialog.dart`、`source_settings_sheet.dart`、`emby_sheets.dart`。来源/Emby/导航/扫描协调相关 6 个测试文件 **58 项全部通过**；`sources_grouping_test.dart` 单文件复验通过，包含鼠标悬浮、默认 Card 移除及 680×382 下来源选择→本地配置弹窗。`flutter analyze --no-pub` 全项目无问题；Windows Release 构建 **41.8 秒成功**，产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`；`git diff --check` 无错误。未执行启动 smoke。

### 剩余验收

真实目录选择器、真实 Emby 登录/选库、可见窗口鼠标/键盘、长路径与大量来源、Windows 高 DPI，以及 macOS/Linux 原生实机视觉验收仍待完成。组件/平台变体测试和 Windows Release 构建不代替这些验收。

## 2026-10-20 前端 P1-A：Emby 媒体库浏览页收口

已按原 MediaLib 的 `AppAdaptiveControlBar` / `AppControlSegmentedShell` / `GlassCapsuleControl` / `GlassMenuButton` 参数收口筛选控制栏：观看筛选采用 44px 分段壳与 28px 胶囊；类型、排序为 38px 下拉。补齐筛选项及下拉控件的悬浮、选中、按压、键盘焦点和减少动画适配。窄窗口布局切换为观看筛选横向滚动、尾部控件换行，并已覆盖 680×382 尺寸。初始读取和筛选计算加载态改为原版风格四行骨架占位，搜索加载使用搜索语义。

本批只改展示与交互反馈，未改变媒体分类、筛选/排序规则、服务器行为或持久化口径。实现位于 `apps/client/lib/features/sources/presentation/emby_video_library_page.dart`；`apps/client/test/emby_navigation_test.dart` 新增控制栏结构和 680×382 断言。全量 `flutter analyze` 无问题；`flutter test test/emby_navigation_test.dart test/emby_browse_test.dart` 共 **45 项通过**，覆盖 Windows/macOS/Linux 平台变体及明暗主题。最终源码重新执行 `flutter build windows --release --no-pub`，**39.8 秒成功**；产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。本轮没有执行启动 smoke。

### 剩余验收

以上平台覆盖是 Flutter 测试变体，不等于 macOS/Linux 原生运行验收。Emby 真实媒体库上的可见窗口人工视觉对照、实体鼠标/键盘交互，以及三桌面原生运行仍待完成；本批测试结果不代表这些验收已通过。

## 2026-10-20 前端 P1-B：媒体详情页视觉收口

详情页顶部统一为静态页头卡并保留返回行为；Hero 去除灰色背景氛围层，改为对齐原版 `DetailView.swift` 的静态卡片材质，同时保留海报、元数据和原交互。主/次操作整理为横向可滚动操作条，避免任意换行；播放、评分、想看、Emby 已看写回和缓存逻辑不变。加载、错误、来源移除状态统一为状态卡，动效遵循 reduced motion。季标题与右侧操作拆分，消除嵌套按钮；本地/远程文件状态卡统一；剧集行依据既有播放记录弱化已看项并展示对勾、进度、继续观看标签和当前选中左侧锚点，不新增持久化或业务规则。extras 折叠箭头与区块间距统一。

涉及 `apps/client/lib/features/sources/presentation/local_media_detail_page.dart` 与 `emby_detail_extras.dart`；`apps/client/test/emby_detail_test.dart` 等相关回归共 **47 项全部通过**，`flutter analyze --no-pub` 全项目无问题。Windows Release `flutter build windows --release --no-pub` 成功，产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。

### 剩余验收

真实 Emby 数据下的可见 UI、鼠标/键盘交互、长剧集列表、Windows 高 DPI/缩放，以及 macOS/Linux 原生实机视觉验收仍待完成。现有自动化测试和 Windows 构建不替代以上人工及跨平台验收。

## 2026-10-19 播放器“更多设置”弹层 P0 前端收口

本批仅整理播放器更多设置弹窗及相关弹层的布局、主题和错误提示可见性，不改变播放业务、设置默认值或持久化行为。

- 弹窗在窗口安全边距内布局；680×382 窗口四边各留 12px，紧凑侧栏宽 132px，设置内容区可滚动。
- “播放 / 音画同步 / 画面 / 字幕”选项卡复用 `PlayerMenuRowSurface`，统一选中、悬停和焦点状态表面。
- 新增深色 `PlayerInlineNotice`。`controlError` 固定展示在当前可见视口的标题下方，避免长设置列表把错误提示推到不可见位置；字幕、音轨选择弹层复用该通知表面。
- 提取 `playerTooltipTheme`，播放器主页面和嵌套弹层统一深色 tooltip。
- 组件回归新增 680×382 小窗口布局、深色 tooltip、可见失败提示覆盖。

### 验证与验收边界

- 定向播放器测试 **54/54** 通过；普通全量 Flutter 测试 **820 passed / 9 skipped**；`flutter analyze --no-pub` 通过。9 项 skipped 是已有 native mpv 条件测试；本次未设置 `REELNEST_MPV_PATH`，因此不代表 native mpv 全套已验证。
- Windows Release 构建 37.9 秒成功，产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`；2026-10-19 17:34:28 +08:00 五秒隐藏窗口 smoke 的 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0` 均通过。该 smoke 只验证启动响应及正常关闭，不代表可见 UI、实体键鼠或真实播放验收。
- 真实媒体上的可见窗口人工视觉检查、实体鼠标/键盘交互、真实 Emby 播放全流程、macOS/Linux 原生验证均未完成；不能据自动化测试或启动 smoke 宣称视觉对照或跨平台验收完成。
- 本批已修改前端组件并完成上述测试、Windows Release 构建及启动 smoke；未改变数据库结构或清理用户数据。

2026-10-19 Linux 视口补充：已在项目生成源码中加入软件 renderer 共用等比例 fit helper，使用上游实际 1920×1080 caps，覆盖 `SetSize` 与自动尺寸 getter（含旋转），保留零尺寸 reset、缓冲上限、暂停重绘和 GPU 路径。Windows 主机运行 `python tool/check_linux_viewport_patch.py --cmake` 并指定 MSVC 自带 CMake，exit 0；实际生成 C++ 代码在有/无 SW 宏下编译，并由 test doubles 覆盖尺寸、自动/旋转/guard 场景和上游漂移故障注入。该检查不是 Linux GTK/EGL 编译或实机画面验收；Linux 大窗口、高 DPI、暂停窗口实测仍待。本轮没有 Dart/Windows 行为变化，不重跑 Flutter 套件或 Windows 构建，不声称新 Windows EXE。详见[画面显示计划](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md#linux-软件-renderer-视口比例适配源码级验证通过平台验收待完成2026-10-19)。

<a id="video-performance-settings"></a>

## 播放器性能控制：硬件解码选择与弱网内存缓冲（实现及 Windows 自动化验证完成；平台/来源验收待）

已按原版实现两个独立的播放性能用户控制。MPV 内部支持硬件解码/缓存或存在默认行为，不等同于 ReelNest 用户设置；硬解选择也独立于 Flutter/MPV 使用 GL 或 SW 的渲染方式，切换解码模式不隐式切换 renderer。

### 原版选项与行为

| ReelNest 用户选项 | 原版值 / MPV `hwdec` 映射 | 默认 |
|---|---|---|
| 硬件解码：兼容 | `VideoHardwareDecodingMode.safe` → `auto-safe` | `safe` |
| 硬件解码：自动 | `VideoHardwareDecodingMode.automatic` → `auto` | — |
| 硬件解码：关闭 | `VideoHardwareDecodingMode.off` → `no` | — |
| 弱网内存缓冲 | `videoMemoryBufferingEnabled` | `true`（开启） |

弱网内存缓冲开启时原版设置：`cache=yes`、`cache-secs=90`、`demuxer-readahead-secs=90`、`demuxer-max-bytes=256MiB`、`demuxer-max-back-bytes=96MiB`、`cache-pause=yes`。关闭时为：`cache=auto`、`cache-secs=20`、`demuxer-readahead-secs=20`、`demuxer-max-bytes=96MiB`、`demuxer-max-back-bytes=24MiB`、`cache-pause=no`。该功能是客户端内存/解复用器缓冲策略，不是网络测速、磁盘缓存、离线下载或服务端转码。

### 移植契约与 UI 范围

- 本地与 Emby 视频共用两项全局设置；不更改服务器转码行为、预览图使用的独立解码器或 GL/SW 渲染选择。
- Domain 为 `VideoPerformanceSettings` 与 enum `VideoHardwareDecodingMode`；`session.updatePerformanceSettings` 串行更新，按执行时最新状态合并。等待 controller 初始化后再应用设置，以免 controller 初始 `hwdec` 覆盖用户选择；在 session 打开媒体前应用，并保留换片、播放重试及画质切换流程。
- 使用原生 MPV 七个 owned properties。所有变更先读回校验；numeric byte 属性接受原单位别名。部分写入失败时按逆序恢复并读回，`VideoPerformanceRollbackFailure` 单独分流告警。DB 保存失败回滚；partial rollback 有警告并可重试。偏好读取/初始化异常非致命，不阻断播放器。
- 使用既有 `player_preferences` 单 JSON 键 `global.videoPerformanceSettings`，字段为 `hardwareDecodingMode`（enum raw name：`safe` / `automatic` / `off`）及 `memoryBufferingEnabled`（bool）；无 schema 变化。各非法字段独立回落默认，JSON 格式损坏使用整体默认值。键结构已由实现确认，详见[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)。
- 前端已按原版 `PlayerView.swift` 在现有“画面”页追加“播放性能”组，仅包含硬件解码模式和弱网内存缓冲两个控件；遵循原版顺序、默认值和交互，不新增其它可见设置。

### 明确排除与验收边界

本硬件解码/缓冲批次不包含去色带、HDR/色调映射、降噪、截图、均衡器或在线字幕；去色带和 HDR 色调映射现已由用户另行批准为后续独立阶段，范围见下节。不得扩展硬件选择到预览解码器、GL/SW 渲染模式或服务器转码。已阅读原 Swift/SwiftUI 依据并按原版接入设置，但尚未完成三桌面逐项视觉验收。MPV 默认能力、属性可写或配置读回均不能单独证明实际硬件解码或弱网播放收益。

### 验证状态（Windows）

- 新增 backend 13 项与显式 DLL native 1 项定向通过；启用 `REELNEST_MPV_PATH` 的全量测试 **817 passed / 0 skipped（38 秒）**，全部 9 项 native 实际执行（其中本批新增 1 项）；两项 UI 测试也包含在全量内。SDK `dart analyze lib test integration_test` 无问题；323 个 Dart 文件格式检查 0 changed；`git diff --check` 无错误。
- Windows Profile `video_performance_test` 构建 28.9 秒，2 个功能用例运行 8 秒通过（摘要 3 passed 含 tearDown）。覆盖 GPU/SW 真实 texture、六种参数组合读回、验证设置先于媒体 open 且不被 controller 初值覆盖、暂停时位置偏差 ≤0.02 秒/画面平均差 <2、音轨/字幕/owned filters/实际 render-api 保持。循环 Range loopback HTTP 资源播放中与暂停状态下切换缓冲均通过；这是受控 loopback 样本，不代表真实 Emby 或真实弱网收益。
- Profile fixture 不含可硬件解码的视频，`hwdec-current=no`。本轮未证明压缩媒体上实际启用 GPU 硬件解码；设置值/property 被接受不等于硬解实际生效。
- Windows production `lib/main.dart` Release 构建 40.2 秒成功；2026-10-19 14:54:16.9228157 +08:00 五秒 smoke：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。EXE：`apps/client/build/windows/x64/runner/Release/reelnest.exe`；报告：`apps/client/build/smoke/release-startup.json`。
- 真实压缩媒体硬解启用、真实 Emby、真实弱网播放收益、macOS/Linux 原生构建/实机与原版 UI 人工逐项验收仍待。本轮未更改 renderer、preview decoder、Emby 资源或转码；未替换 runtime、清理用户数据、commit 或 push。既有 `fc7dadc` 已推送不属于本轮操作。

<a id="video-deband-tone-mapping"></a>

## 已批准：去色带与 HDR 色调映射（Windows 自动化验证完成；真实设备/跨平台验收待）

用户已批准按原版新增去色带与 HDR 色调映射两项视频渲染设置，并明确决定本轮只交付 GPU 路径；实际使用纯软件 renderer 时，对用户发出的任何渲染设置编辑都明确拒绝（包括 `off`/`auto`），不保存修改。该 SW 行为是用户认可的范围边界，不属于静默降级；不得切换 renderer 规避限制，也不得把 GPU 行为描述成跨 renderer 等效。限制依据实际渲染路径 `user-data/reelnest/render-api=sw`，与硬件解码开关无关；软件解码 + GPU renderer 仍可用。MPV 属性写入/读回不等于最终图像效果验收。

### 原版选项与映射

| 用户设置 | 原版值 | MPV 映射 | 默认 |
|---|---|---|---|
| 去色带 | `VideoDebandMode.off` / `light` / `strong`（显示“关闭”/“轻微”/“明显”） | 按顺序写入 `deband`、`deband-threshold`、`deband-range`、`deband-grain` | `off`；关闭仍写原版默认参数 |
| HDR 色调映射 | `auto` / `bt.2390` / `hable` / `mobius` / `reinhard` / `clip` | `tone-mapping` 属性对应同名 MPV 值 | `auto` |

去色带参数严格沿用原版：

| 模式 | `deband` | `deband-threshold` | `deband-range` | `deband-grain` |
|---|---:|---:|---:|---:|
| `off` | `no` | 64 | 16 | 48 |
| `light` | `yes` | 32 | 12 | 24 |
| `strong` | `yes` | 48 | 18 | 36 |

原版依据为 `MediaLibCore/Models/AppSettings.swift` 中的 `VideoDebandMode`、`VideoToneMappingMode` 和默认值，`MediaLib/App/VideoDebandPolicy.swift`、`VideoToneMappingPolicy.swift` 的属性和值映射，以及 `MediaLib/Views/PlayerView.swift` 的画面设置。固定参考源码为 mpv `a2cd83c56d` 与 FFmpeg `5cb9fcd`；实际 GL/SW 能力按固定代码分别判断，不用其它滤镜或 FFmpeg 版本的支持情况替代本项目证据。

### 实施契约与边界

- 本地与 Emby 视频共用设置；通过播放 session 串行更新并按执行时最新状态合并，原生应用后读回并保存；应用/保存失败恢复旧值并告警，初始化读取/应用失败非致命。换片和重新打开媒体须保持所选值。
- 使用既有 `player_preferences` 的全局单 JSON 键 `global.videoRenderSettings`，字段 `{debandMode, toneMappingMode}`，enum raw name 分别为 `off/light/strong` 与 `auto/bt2390/hable/mobius/reinhard/clip`，无 schema 变化。字段、默认和回退见[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)。
- 原版在现有“画面”页“播放性能”组中，把“去色带”和“HDR 映射”两行追加在“硬件解码”之后。前端按原版标签、选项顺序、布局和交互对照；前端实现和 UI 验证仍由对应负责人完成，本次授权只包含这两项。
- 去色带 GPU 属性顺序为 `deband` → `deband-threshold` → `deband-range` → `deband-grain`。HDR 映射使用固定 mpv 的 `tone-mapping`；固定 FFmpeg `vf_tonemap.c` 不含 BT.2390，不能以 FFmpeg 滤镜替代原生 mpv 曲线策略。
- 已验证行为：GL/GPU 路径是本轮唯一支持交付路径；如果实际 `reelnest/render-api=sw`，所有用户发起的渲染设置编辑明确失败并返回 `VideoRenderUnavailable`，包括重复写入默认 `off`/`auto`，且失败不保存。初始化遇到已存默认值 `off`/`auto` 时静默，不记 warning/failure 日志；非默认值保持数据库原偏好、提示用户并允许播放；后续新 GPU 会话恢复原选择。硬件解码关闭与 SW renderer 无直接关系，软件解码 + GPU renderer 可用；不切 renderer。不能把 SW 属性直接探测的可写误称为图像效果有效。
- 不引入降噪、截图、均衡器、在线字幕、服务器转码或其他新画面效果；不以色调映射设置替换服务端 HDR 转码策略。GPU 和 SW 的有效图像结果必须分别辨认；按用户决定，SW 已明确不支持而非追求等效实现。

### Windows 自动化验证结果与边界

- Windows Profile 最新两功能场景运行 15 秒通过（摘要 3 passed 含 tearDown；Profile 构建 23.5 秒）。除最初 PQ/去色带像素对比外，补充覆盖：同一 PQ 样本 auto 与 BT.2390 差异 <0.5；HLG Hable 与 clip 有实际像素效果，平均差 `34.6839`；HDR 设置和亮度/伽马 + 锐化 + 镜像组合不改变 `vf`、hwdec 和 gamma 状态；暂停位置偏差 ≤0.02 秒，暂停 resize 400×240 → 320×180 画面差 <1；HLG Hable/BT.2390 下 ASS 白字幕保持白色且字幕选择不变；移除 HDR 元数据后 SDR 选择 Hable/clip 的画面差 <0.5；播放中 reset 后继续播放。
- 最初 PQ 10-bit 标签样本数据保留为指定 fixture 证据：去色带 `light`/`strong` 相对 `off` 平均差分别 `0.3143`/`0.4557`；曲线相对 clip 的差异为 auto/BT.2390 `1.8839`、Hable `21.7032`、Mobius `4.5161`、Reinhard `7.9226`。这些是自动化样本像素差，不代表真实 HDR 显示器/片源的主观画质验收。
- SW 直接属性探测的图像像素差仍全为 0。固定 mpv `video/out/libmpv_sw.c` 用 `mp_sws_scale`，GPU 路径在 `video_shaders.c` 执行 shader；生产入口因此按实际 renderer 对 SW 全部用户编辑明确拒绝。该限制来自 renderer，不是解码器；软件解码配 GPU renderer 仍可用。
- 新后端 12 项、UI 2 项真实滚动/点击用例通过。启用 `REELNEST_MPV_PATH` 的完整 `flutter test` **829 passed / 0 skipped（38 秒）**；全部 9 项既有 native 测试执行，本批新增 12 项 Dart 后端测试、没有新增 headless native。SDK `dart analyze lib test integration_test` clean；328 个 Dart 文件 format 0 changed，diff-check 无错误。
- Windows production `lib/main.dart` Release 构建 40.4 秒成功；2026-10-19 17:01:51.3221687 +08:00 五秒 smoke `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。EXE：`apps/client/build/windows/x64/runner/Release/reelnest.exe`；报告：`apps/client/build/smoke/release-startup.json`。AOT `app.so` 已包含两项 JSON 偏好键；测试包中没有集成测试 case 字符串是预期，配置由正式入口加载。
- 最终仍待真实 HDR 片源/显示器、真实 Emby、macOS/Linux 原生构建与实际 renderer、人工 UI/视觉验收。此批未增加非 HDR 媒体效果、服务器转码或 SW 等效处理；未升级 runtime、清用户数据、提交或推送。

当前状态为“Windows GPU 路径、SW 明确拒绝边界与自动化验证完成；真实 HDR 设备/Emby、macOS/Linux 原生与人工 UI 验收待完成”，不代表三个桌面平台和真实内容已验收。

当前播放器故障诊断与加载健壮性批次已完成本轮代码及 Windows 验证：最终定向 native 1 项、analyze、265 文件格式检查和 diff-check 通过；Windows Release 40.8 秒成功，01:12:55 +08:00 五秒 smoke 通过。全量 **701 passed / 4 skipped** 是最后三行 `finally` 修正前的基线，未重复全量。真实 Emby 间歇故障尚无历史日志，根因未确定，需用新版实际复现；macOS/Linux 原生未验收。详见[高级播放与当前批次记录](PLAYER_PRECISION_BACKEND.zh-CN.md)。

2026-10-16 后续修复主窗口关闭卡顿：已确认 `SourceRepository.close` 等待 paused change-stream listener，而 listener 需在 provider container dispose 时取消，构成等待循环。调整 stream 关闭与 app 清理顺序；子窗口关闭不再依赖可能丢失的 IPC 回复，而轮询原生窗口清单，false 回复或超时保留播放器窗口、不强制销毁。后台 marker/offline/cache 并行取消并等待完成，数据库最后关闭，单步清理异常记录后继续释放其他 owner；关闭日志写入现有 `logs/playback-*.jsonl`，不含 URL/账号。代码已冻结：全量 **723 passed / 6 skipped**、analyze 零问题、281 Dart 文件 format 0 改动、diff-check 通过；新增关闭回归和 source paused-listener 定向共 **24 项通过**。首次全量的一项 fixture teardown `HttpException` 已在测试夹具中限定处理为关闭期间预期断连，其他异常仍抛出；修后全量为上述 723/6。Windows 正式 `lib/main.dart` Release 构建 **40.2 秒成功**；2026-10-16 11:15:30.6878930 +08:00 单次 `PostMessage WM_CLOSE` smoke 通过（窗口响应、正常关闭、退出码 0）。关闭日志记录总耗时 **234 ms**：后台任务收尾 225 ms、数据库关闭 8 ms。该结果仅覆盖本机此次启动/退出，不推导所有库、活跃下载、多页面、有播放器或 macOS/Linux 场景均已通过。

2026-10-16 用户新增授权播放器右上角输入速率提示，并确认随底部播放进度 Dock 同步显隐。代码已冻结：backend 54、UI 27、隔离 native 2 项通过；全项目 analyze、269 个 Dart 文件格式 0 改动及 diff 检查通过。本轮未重跑上一轮 701 项全量。Windows 正式 Release 39.6 秒成功，五秒 smoke 正常响应并退出；真实 Emby、实体键鼠、macOS/Linux 原生和三端视觉验收仍待。不得将本地/离线缓存磁盘读取冒充网络速率。详见[专项记录](PLAYER_PRECISION_BACKEND.zh-CN.md#用户授权播放器输入速率提示代码冻结windows-验证完成三端验收待定2026-10-16)。

当前两项 P2 修复的定向、全量及 Windows Release/smoke 验证均完成。三文件共 **28 项定向测试通过**；全量 `flutter test --no-pub --reporter expanded` **753 passed / 6 skipped**（49 秒，exit 0）；analyze 无问题，296 个文件格式检查 0 改动，diff-check 通过。Windows production Release **45.7 秒成功**；2026-10-16 16:57:14.4629377 +08:00 五秒 smoke 的窗口响应、正常关闭及退出码 0 均通过。字幕更新在串行执行时按 engine 最新状态合并；便携 SQLite 对 library、数据库及 sidecar 的路径逃逸做启动与 open 双重防护。无 schema 变更、无用户数据删除、未提交推送。详情见[字幕记录](PLAYER_TRACKS.zh-CN.md#p2-修正快速连续样式更新合并windows-验证完成)和[项目边界](PROJECT_SCOPE.zh-CN.md#p2-修正数据库目录边界校验windows-验证完成)。

用户已确认的原画面显示五项迁移：比例（7 项含跟随片源）、黑边裁切（none/gentle/balanced/fill）、去隔行（off/auto/on）、旋转（source/90/180/-90）、镜像（none/horizontal/vertical/both）。前端设置页、模型/偏好/session/engine 已接通，后端 13 + UI 2 项定向通过。高级设置顺序为播放/音画同步/画面/字幕；播放状态只摘要非默认比例、裁切、去隔行和旋转，不显示镜像摘要；设置及嵌套二级菜单为深色播放器主题。Windows Profile texture 阶段验证通过：像素确认比例黑边、fill 裁切、square 比例和镜像；旋转 getter 与原生属性组合已验证，但未单独做旋转像素图像对比。全量 Flutter **768 passed / 7 skipped**、七项 native DLL 专项、analyze、严格暂停 resize（mpv `osd-dimensions=480x270`）通过。此前 Release 44.4 秒及 2026-10-16 23:30:33.7136344 +08:00 smoke 已通过；CMake pinned archive 下载重试逻辑更新后，增量 Release 45.1 秒成功，2026-10-16 23:39:17.7412689 +08:00 五秒 smoke（`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`）通过。手工预置固定 archive 的新缓存独立验证通过（archive/DLL hash、提取及保留其他 DLL）；冷缓存网络下载因连接中断未验证，不代表 hash 校验失败。暂停 resize 修正由项目内 CMake 生成的 `video_output.cc` 补丁在现有 render queue 执行 `CheckAndResize()` / `Render()`，不 seek、不解除暂停、不改 PubCache。真实 Emby、macOS/Linux 及人工视觉验收仍待；正式发行前需长期保存固定 archive/对应源码/许可证材料并完成依赖通知清点。亮度、对比度、饱和度、伽马、色相已获另行授权，见下文独立计划，不计入本原画面显示五项批次的验收；锐化/降噪、硬解选择和服务器转码扩展仍不在这两个批次范围。无 schema 迁移，Windows 绿色存储不变。验收范围见[画面显示计划](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md)。

2026-10-17 P2 补充：macOS/Linux `media_kit_video` 暂停 resize 只保存尺寸、未主动重绘的问题已有等效项目内补丁。macOS Pod post-install 将 Pods 引用切到 ephemeral 生成的 Swift 文件；hook 另为 `media_kit_video` Pods target 添加编译前脚本 phase，声明 helper/原 Swift 输入与生成 Swift 输出并调用 `ruby --generate-source`，防止 Podfile 未改而 helper 更新后沿用旧副本；Shell 参数由 `Shellwords` 转义、phase 安装幂等、不改 PubCache。新增 setSize 渲染 job 使用 `[weak self]`，检查实例仍存活、未 dispose、texture 存在且 id 有效后，在原 worker 内调用 `_updateCallback` 完成 resize/render 与主线程通知，避免新增排队 job 单独保活已关闭的 `VideoOutput`；不声称解决依赖其他既有任务的全部关闭竞态。Python 静态比对确认 Ruby `ORIGINAL` 片段与 media_kit_video 2.0.1 Swift 源码唯一匹配，但不替代 Ruby 执行、Pods post-install 或 Swift 编译。Ruby 测试覆盖 build phase 输入/输出和重复安装幂等，但本机无 Ruby 未执行；macOS hook/Pods 接线、Pods/Swift 编译未验证。Linux CMake 生成 C++ 补丁，GL 用标记帧请求既有 raster 绘制，SW 复用上游帧渲染体并以新尺寸立即 render，保留生命周期/context guard 和尺寸上限，不新增延迟 raw self 队列。Windows Profile integration 的 GPU/SW 两场景（400×400→480×270→300×450→400×400）通过，mpv `osd-dimensions`、pause、time-pos 符合预期，排队 resize 后 dispose 无崩溃；Linux 补丁检查脚本的两种宏配置生成真实 C++ helper/set_size，以 MSVC 编译并运行 test doubles（Release 显式启用 assert），GL 通知、SW 新尺寸/clamp、无 context/已销毁时不 render、保留其他编译文件及上游 callback 漂移 fail-fast 均通过。Dart backend 13 + UI 2 共 15/15、analyze 0、305 文件 format 0 改动、diff-check 通过；本轮未重跑全量，768/7 仅为上一轮结果。Windows 正式 Release 41.0 秒成功；2026-10-17 00:17:46.2654301 +08:00 五秒 smoke 窗口响应、正常关闭、ExitCode 0 通过。上述 Windows 与 test doubles 结果不等于 macOS/Linux 原生验收。Mac 本机无 Ruby/Swift/CocoaPods，因此 Ruby 用例、post-install/build phase 接线、Pods/Swift 编译未验证；Linux GTK/EGL 原生构建和真实窗口 resize 未验证；CI 已加检查但尚未触发。详情见[画面显示 P2 记录](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md#p2-macoslinux-暂停时视口-resize-不主动重绘实现落地平台验收待完成2026-10-17)。

当前用户已批准的播放器字幕样式与音画同步批次代码已冻结。`flutter test` 718 passed / 6 skipped，analyze 无问题；279 个 Dart 文件格式检查 0 改动、`git diff --check` 通过。真实 libmpv 文本字幕 native 用例 1 项通过，覆盖 5 个样式与 4 个 timing 属性读回、libass 像素变化、暂停及播放位置不变；Windows Profile 字体主/子 engine 集成用例 1 项通过，Profile 构建 21.9 秒，子窗口销毁后主 engine 仍可枚举字体。正式 Windows Release 37.8 秒构建成功，`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 2026-10-16 09:34:00 +08:00 通过（隐藏窗口响应、正常关闭、退出码 0），产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。ASS/位图字幕不在 native 样本内；driver 尾部的通用 plugin 提示未阻断通过，但不等同人工 UI 验收。macOS/Linux、真实 Emby 和视觉验收待完成。细节见[模块记录](PLAYER_TRACKS.zh-CN.md#当前批次字幕样式与音画同步代码已冻结windows-验证完成2026-10-16)。

## 播放器画面色彩调整（用户已授权，实现及 Windows Profile 验证完成；验收中）

最新验证（2026-10-18）：后端色彩定向 15 项 + UI 2 项共 17 项通过；偏好读取失败不阻断播放回归通过，静态分析 `lib`、`test`、`integration_test` 无问题。Windows Profile GPU/SW 当前两条 texture 用例通过：YUV420 五项、宽色度 YUV 四组、ASS 矢量白字幕黑画面、无字幕全黑，以及平滑 RGB 梯度的 hue/saturation 原版语义和 brightness 有效均有证据。全量 Flutter **783 passed / 7 skipped**（57 秒；7 项为需显式设置 `REELNEST_MPV_PATH` 的既有原生测试）通过。暂停尺寸往返 400×240→320×180 已通过：恢复后画面/色彩与白色 ASS 平均像素差 <2，暂停状态为 `yes`，`time-pos` 偏差 <0.02 秒。Windows Release 构建 55.0 秒成功；五秒 smoke 于 **2026-10-18 18:51:54.8987774 +08:00** 通过（`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`），产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，报告 `apps/client/build/smoke/release-startup.json`。Mac Ruby/Swift、Linux 原生构建、真实 Emby、高分辨率 CPU 长测及非 seekable 流仍未验。本轮未清除用户数据、未提交推送。

本轮按原版源码实现亮度、对比度、饱和度、伽马、色相，偏好键格式见[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)，实现细节与验收边界见[画面色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md)。当前后端 15 项 + UI 2 项、Windows Profile GPU/SW 色彩与暂停视口往返、全量 Flutter 783 passed / 7 skipped 均通过；Windows Release/smoke 均通过。真实 Emby、高分辨率 CPU 长测、非 seekable 流以及 macOS/Linux 原生验证待完成。暂停时 mpv 更新 `vf` 会触发内部精确刷新 seek；应用本身不主动 seek/unpause/loadfile。本轮不新增锐化/降噪滤镜或其他面向用户的画面效果；SW 内部 owned `lavfi/geq` 仅为色彩等效处理，不作为新增滤镜功能。`hqdn3d` GPL 依赖仅作后续调研，不扩展硬解、HDR 或转码。

## 播放器画面锐化与滤镜组合（用户已批准下一阶段，开发中）

本阶段迁移原版锐化四档和统一 `vf` 链组合：`global.videoSharpenMode` 保存 enum raw name，默认 `off`；全局、本地/Emby 共用、无 schema。原版完整链为 base quality → flip → sharpen → denoise；当前四-label owned helper 不含 denoise label。锐化 Dart 12 项和显式 DLL native 1 项均包含于启用 `REELNEST_MPV_PATH` 的全量 **803 passed / 0 skipped（39 秒）**，全部 8 项 native 实际执行并通过。Windows Profile GPU/SW 锐化用例 17 秒及附加 `video_color_test.dart` 两 renderer 用例 19 秒通过，medium 锐化时字幕白、移除字幕后全黑、暂停 resize 正常，且同次验证关闭锐化后 RGB 语义恢复。headless native 用例 Temp namespace 通过 `IOOverrides` 隔离至自身 sandbox；PID 复用只是候选解释，未由崩溃栈独立确诊，未改生产 runtime。318 个 Dart 文件格式 0 改动、analyze clean、diff-check 无错误。代码/UI 已冻结；Windows production Release 42.5 秒和五秒 smoke 均通过，2026-10-18 20:01:52.2262702 +08:00 smoke 的窗口响应、正常关闭、退出码 0 均为 true；产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，报告 `apps/client/build/smoke/release-startup.json`。macOS/Linux 原生验收待。详见[锐化计划](PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md)及[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)。

降噪调查结果：固定 FFmpeg commit `5cb9fcd21167cf2f5a2852ea582997bbd0055521` 中 `hqdn3d_filter_deps="gpl"`，filter 文件头标 GPL-2.0-or-later；`unsharp` 文件头标 LGPL-2.1-or-later。Windows 当前固定 LGPL DLL 实测不支持 `hqdn3d`，报 `Option vf-add: 'hqdn3d' isn't supported`，不能直接启用。后续只评估（1）固定源码自建含 `hqdn3d` 的运行时并提供完整源码/构建/许可/分发材料，或（2）先取得适用许可/依据后评估独立等效实现；不得直接换 GPL DLL，也不承诺整体 Apache 许可不受影响。当前仅调研、不实现降噪；见[锐化计划](PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md)。


六项实时统计实现及本轮 Windows 验证完成。`flutter test --no-pub --reporter expanded` 全量 743 passed / 6 skipped（39 秒，exit 0）；`flutter analyze --no-pub` 无问题；`lib`、`test`、`integration_test` 的 296 个文件格式检查 0 改动，diff-check 通过。Windows Profile 真 `MediaKitVideoEngine` texture 专项 1 case 通过（构建 22.1 秒）；暂停只读、seek、重开及 dispose 安全均有覆盖。正式 production `lib/main.dart` Windows Release 构建成功（46.1 秒）；2026-10-16 16:41:35.4687675 +08:00 五秒 smoke 的隐藏窗口响应、正常关闭及退出码 0 均通过。禁用音轨（`aid=no`）时 AV sync 不可用，普通静音/音量 0 不会令其失效。能力报告中的硬解读取可用不代表实际硬件解码已启用；当前 texture VO 不提供 `vo-passes`，UI 显示 `--`，不切换 VO 或播放选项强行采集。真实 Emby、实际硬解启用状态、转码/切画质、macOS/Linux、可见 UI/视觉及长时间性能验收仍未覆盖。本轮无存储行为、配置导入或 schema 变更，未提交推送。细节见[实时统计计划](PLAYER_REALTIME_STATS_PLAN.zh-CN.md)。

后续整合回归：全量 **768 passed / 7 skipped**（52 秒），既有 `playback_stats_test` Windows Profile texture 回归通过；指标与旧库报告一致，`renderPasses=false`、HTTP cache 可用，不强切 VO。七项原生 DLL 专项、analyze 与严格暂停 resize（`osd-dimensions=480x270`）通过。调整 pinned archive 下载重试逻辑后，Windows Release 45.1 秒成功，2026-10-16 23:39:17.7412689 +08:00 五秒 smoke 正常响应、关闭且退出码 0。新缓存的手工预置 archive 独立验证通过；冷缓存网络下载因连接中断仍未验证。真实 Emby、macOS/Linux 与视觉验收仍待。

最新播放器 UI 批次完成 Dock/菜单固定深色 Chrome 色板统一：Dock、右键精度菜单、字幕/音轨/剧集/音量/设置/画质/标记面板及音频设备/字幕字体等嵌套菜单不再随海报明暗切换为浅色；该局部主题不影响媒体库等普通页面。右键精度菜单中的重复迷你悬浮窗/还原窗口入口已删除，迷你悬浮窗仅保留 Dock 按钮，`P` 快捷键保留。Dock 高 72 px，主播放按钮 34×34 px、辅助按钮 32×32 px，图标分别为 18/17 px。`playback_test.dart` 20/20、7 个播放器弹层相关测试 47/47、targeted analyze clean；Windows Release 34.5 秒成功，2026-10-16 11:03:30 +08:00 五秒 smoke 窗口响应、正常关闭、退出码 0 均通过。真实 Windows 可见窗口、实体键鼠及 macOS/Linux 原生目视继续待验收。详见[Dock 批次记录](PLAYER_PRECISION_BACKEND.zh-CN.md#当前-ui-批次播放器控制栏-dock-重构2026-10-15)。

本批已接入原版片头片尾检测的首页/媒体库/详情条目入口、系列批量分析、任务中心进度/取消/失败重试及历史。最终全量 **685 passed / 3 skipped**、分析、260 文件格式检查通过，Windows Release **41.0 秒**构建、**19:51:30 +08:00** 五秒启动检查通过；基线 `fab5dda` 的 668+3 是上批结果。移除上批播放器标记面板临时检测入口，保留审核。字幕样式与音画同步后续批次已完成代码及 Windows 验证，详见上方最新结果；在线字幕仍保留在原版既有迁移清单；真实来源、三端原生及视觉验收仍待。详见[当前批次](PLAYER_PRECISION_BACKEND.zh-CN.md#当前批次检测入口系列批量分析与任务中心2026-10-15)。下方历史批次的“入口/批量待迁移”只描述当时状态。

前一批完成：单视频内嵌章节片头片尾候选生成及采用/忽略，68 项定向回归、全量 668 passed / 3 skipped、静态分析、Windows Release（40.8 秒）与 14:53:36 +08:00 五秒 smoke 均通过。识别规则沿用原版，pending 不参与跳过，rejected 保留以避免相同候选反复生成，不覆盖手动范围；当前初始数据库结构不变。原版媒体条目检测入口、系列批量分析和任务中心后续迁移，字幕样式/音频延迟未在本批实施，真实来源和三端实机/视觉验收仍待。本批之前的 P1 播放辅助和 Emby 分页/计数修复已提交为 `e3cbb8a`（当时全量 652 passed / 3 skipped）。详见[本批接口、边界与验证](PLAYER_PRECISION_BACKEND.zh-CN.md#前一批内嵌章节片头片尾候选2026-10-15)。下方按历史批次保留当时的完成和待办状态。

2026-10-12 用户调整范围：暂不实现照片模块，照片/相册、照片搜索、系统照片库与首页照片墙移出当前计划和验收清单，不自动排入后续阶段。入口及首页标识已移除，91 项相关回归和静态分析通过；正式构建与启动结果见[照片范围记录](PHOTO_SCOPE_DECISION.zh-CN.md)。下方历史批次涉及照片的记录仅保留追溯用途；影视海报、背景和演员图片继续保留。详见[项目边界](PROJECT_SCOPE.zh-CN.md)。

用户随后要求优先实现高级播放。章节/书签、单片循环、A–B 与逐帧的底层及首批 UI 已接入，接口、原版依据与验证见[高级播放记录](PLAYER_PRECISION_BACKEND.zh-CN.md)。当前协作分工为：前端工程师维护播放器 presentation、主题、交互与组件验证；后端/集成工作维护会话、引擎、持久化、来源集成和分层验证；文档工作维护状态、索引、证据和措辞一致性。分工不改变本地与 Emby 共用同一播放器的架构边界。

用户已正式授权实施手动片头/片尾标记与跳过策略。代码与 Windows 自动化验证已完成：全量 609 项测试通过、2 项 native 默认跳过后单独启用通过；分析、格式检查、Release 构建和启动检查通过。首轮全量测试因 UI 测试夹具清理失败而中止，修复后复跑通过。真实 Emby、实体键鼠、macOS/Linux 原生及 UI 视觉验收仍待完成。原版默认“显示按钮”，仅完整且已确认的范围参与提示或跳过；本地与 Emby 共用播放器接口、按影片绝对时间处理。自动识别和候选审核属于后续子批次。接口与当前证据见[高级播放当前批次](PLAYER_PRECISION_BACKEND.zh-CN.md#当前批次片头片尾手动标记与跳过代码与-windows-自动化验证完成)。

随后播放器外观继续调整，补齐背景渐隐、玻璃状态卡、控制条与按钮、6px 时间轴和桌面 hover。该轮在外观修改后通过 26 项定向回归、Windows Release 构建和五秒启动/正常关窗检查，未重跑全量测试；上方 609 项与两项 native 结果是外观调整前的功能基线。最新产物与验证范围见[播放器外观调整记录](PLAYER_PRECISION_BACKEND.zh-CN.md#后续播放器外观调整2026-10-13)。

2026-10-14 完成 P0 播放器前端视觉收口：统一面板表面与颜色、控制按钮状态、弹层和右键菜单外观、入场动效及顶部状态提示，不改播放业务规则。5 个 presentation 文件 `flutter analyze` 通过，6 组播放器相关测试 **62 项通过**；Windows Release 构建和五秒启动烟测通过。本批未运行全量测试，上一批 616 项通过/2 项跳过不代表本批全量验证。macOS/Linux 原生窗口人工目视、真实 Emby 视觉和像素级对照仍待完成。详见[播放器视觉收口记录](PLAYER_PRECISION_BACKEND.zh-CN.md)。

随后完成播放器第二轮 P0 交互收口：窄窗口控制栏、自隐藏与光标反馈、独立音量 HUD。该批当时仅运行 62 项定向测试，未跑全量；此前的“未跑全量”历史表述继续保留。提交前又对两轮 P0 UI、侧栏/Emby 与 Logo 改动完成当前整合复验：616 项通过、2 项默认关闭的原生用例跳过，分析无问题，235 个 Dart 文件格式检查 0 修改，Windows Release 当前代码构建及五秒烟测通过。macOS/Linux 原生构建与实机、真实 Emby 完整流程和人工可视化验收仍待。细节见[提交前整合复验](PLAYER_PRECISION_BACKEND.zh-CN.md#提交前整合复验2026-10-14)。

播放器 P1-A 前端批次已完成：时间轴尾部剩余时间切换与持久化、控制栏锁定、播放信息面板。6 个播放器相关测试文件 62 项通过，分析及 Windows Release 构建通过，14:45 +08:00 五秒 smoke 正常；该批当时未跑全量，前一轮 616+2 是其修改前基线。详情见[P1-A 验证记录](PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-a剩余时间控制栏锁定与播放信息2026-10-14)。

随后完成播放器 P1-B 迷你悬浮窗/置顶：7 个相关测试文件 66 项通过，全量 620 项通过、2 项跳过；分析、Windows Release（36.2 秒）及 15:01:30 +08:00 五秒 smoke 通过。Windows 自动化不等同于迷你窗真实可见窗口验收，macOS/Linux 原生实机、真实媒体人工交互/视觉仍待。该 P1-B 验证早于 P1-C。详见[P1-B 验证记录](PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-b迷你悬浮窗与窗口置顶2026-10-14)。

2026-10-15 完成播放器 P1-C 时间轴预览实现及自动化验证：三档偏好、148×83 预览气泡、悬停/拖动帧预览与释放后 seek；独立静音 headless mpv、单路并发、160 项/32MiB 缓存、同桶合并、取消/换片隔离、受限远程 Range 代理与离线缓存租约均已接入。`flutter analyze --fatal-infos` 零问题，全量 `flutter test --no-pub` 为 643 passed / 3 skipped；时间轴/语义树专项回归及 native 抽帧 1 项通过。Windows Release 42.3 秒构建成功，10:01:54 +08:00 五秒 smoke 正常。真实 Emby、人工可见窗口交互/视觉及 macOS/Linux 原生实机验收仍待。详细实现与验证边界见[P1-C 记录](PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-c时间轴预览图2026-10-15)。

以下既有验收安排继续保留，尚未完成：

1. 首页桌面交互与真实 Emby 验收：详情往返、滚动、搜索、编排和播放后刷新。
2. macOS/Linux 原生构建与原版视觉对照，记录具体差异后修正。

搜索范围、原版交互、数据边界和完成条件见[首页实施计划](HOME_IMPLEMENTATION_PLAN.zh-CN.md)。H1 已接入跨来源视频首页、统计、续播/历史、想看/收藏、最近剧集、分页和播放通知刷新；H2 已接入每日推荐、剧集推荐、高分精选、题材、离线投影、跨来源视频搜索及运行状态摘要。当前视频健康评分已接通原版公式、本地/Emby 核心检查、本地重复与详情缺口；音乐、网址连接器、详情补全不因此标为完成，见[评分范围](HEALTH_SCORE.zh-CN.md)。

前一批完整整合基线提交 `4d4a0ee`：全量 **587 项 Dart 测试通过**，当时 1 项真实 mpv 专项默认跳过并在单独启用后通过。片头/片尾批次曾有全量 **609 项通过、2 项默认跳过**，两项 native 专项单独启用后通过；该结果是历史批次证据。此后各 P0/侧栏等独立改动批次保留其当时未跑全量的事实；最新提交前整合复验已覆盖两轮 P0 UI、侧栏/Emby 与 Logo 改动，结果见上方及[播放器验证记录](PLAYER_PRECISION_BACKEND.zh-CN.md#提交前整合复验2026-10-14)。真实 Emby 完整操作、播放器可见窗口 UI、实体键鼠、macOS/Linux 原生及原版视觉对照仍须分别验收。

## 历史记录说明

下文按实施发生顺序保留 2026-10-05 至 2026-10-10 的本地来源、播放器和 Emby 批次记录，用于追溯规则与验证范围。文中的“当前”“下一步”“首页占位页”、测试数量和未完成项只描述当时状态；与上方当前阶段冲突时以上方及对应最新专项文档为准。

## 历史：原版基线与本地来源第一批

已建立[原版一致性核对清单](design/ORIGINAL_PARITY_AUDIT.zh-CN.md)，深读本批涉及的导航/窗口、来源向导和扫描过滤调用链；其他模块只定位入口，尚未完成全部审计。

本批完成分类/格式/大小过滤规则、SQLite 来源配置存储、成功扫描清理旧索引，以及三桌面端最小内容尺寸 1088×720。桌面导航不再由窗口宽度切到手机底栏；CI 构建矩阵限于 Windows/macOS/Linux。

三步添加向导、完整公共视觉/侧栏来源树、剩余扫描/元数据规则、macOS 持久目录授权仍待实现。N1–N5 均不标为全部完成，尤其没有宣称 UI 已一比一还原。

此前已验证三个桌面目标的 Shell 组件、真实目录过滤/阈值、成功清理和失败保护；分析、格式检查及 Windows Release 构建通过。没有在该轮启动 GUI 或完成原版视觉对照，macOS/Linux 原生构建与运行仍未验收。当前测试范围不包含开发中间版本的数据库兼容。

## 后续批次：来源分组与本地扫描队列

- 媒体源页面接入“添加媒体源…”、“扫描全部”及已连接/已断开分组。分组来自异步目录存在性检查，应用恢复前台、来源变化和扫描结束时刷新；扫描开始前再次检查可达性。
- 参照 `AppState.startScanQueue/runScanQueue`，本地来源顺序扫描，重复请求去重，离线来源跳过，失败后继续后续来源。运行中和排队中均可取消；页面禁止重复扫描全部。
- 按 `VividIconLibrary.swift` 移植来源标题、连接/断开插画和所需线性图标路径；页头/分组间距引用原参数。
- 当前来源卡片、空态材质、按钮表面、全局进度样式、三步向导、自动重新挂载及远程来源同步仍未完整迁移。完整 UI 一致性未验收。

新增队列与分组交互回归后共 26 项测试通过，涵盖排队中断盘、单源失败、取消、重复调用、关闭期间的可达性检查，以及恢复前台后的状态更新。

本批静态分析及 Windows Release 构建通过，实际启动确认主窗口正常。后续媒体源页面检查被用户按 Escape 停止，未完成该页实机检查或原版视觉对照；macOS/Linux 原生构建与运行仍待验证。

## 后续批次：来源配置、逐文件扫描和公共弹窗基础

2026-10-05，按 `MediaSource.swift`、`MediaScanner.scan` 和 `AppState.updateSource` 继续迁移：

- 增加来源策略的数据模型与持久化：自动扫描、NFO、本地海报、网络刮削、截图回退、元数据/健康检查参与、写回偏好、远程痕迹同步和 Emby 选库。默认值沿用原版，库 ID 去空白、去空项并稳定去重，未知同步枚举回退双向同步。
- 当前初始表结构包含来源 ID、路径、分类/阈值、策略、扫描时间及媒体索引，创建/更新时间为必填。设置存储支持原版音乐来源大于 5 MiB 时调整到 512 KiB 的规则。
- 文件清单枚举后提供总数，逐文件导入、跳过或记录错误；单文件读取/数据库写入失败继续处理其余文件。取消或失败保留已导入的新条目及原有索引，只有无错误的完整扫描才清理未发现条目。隐私来源的进度隐藏路径，单文件错误使用原版通用文案。
- 公共 `AppSheetHeader`、`AppSheetSection`、`AppSheetActionFooter` 和 sheet 尺寸参数已翻译。它们仍是待向导接入的基础组件；完整主题解析、材质、按钮样式和原版视觉验收尚未完成。当前简化添加表单未替换，不能称为三步向导完成。

本批当时只迁移配置持久化，未接入自动扫描/监控、元数据、健康和服务器同步服务。2026-10-08 已补设置控制器的保存与扫描重启，见下文；健康缓存失效、原任务通知和策略执行服务仍待迁移，相关策略没有作为有效开关显示。

此前验证了真实文件在枚举后消失、单文件 SQLite 写入失败、取消后保留新旧条目、失败后再次成功清理、隐私进度及策略重开；分析、格式检查及 Windows Release 构建通过。按用户要求移除开发中间版本的升级代码和兼容测试，统一维护当前初始结构；不自动删除已有开发数据库。移除兼容逻辑后，28 项测试全部通过，静态分析无问题，修改文件格式检查及 `git diff --check` 通过；保留当前数据库新建、持久化与重开验证。本次没有重新构建或启动 GUI，macOS/Linux 原生构建与运行及原版视觉对照仍待验证。

## 后续批次：本地多目录配置与公共控件

- `DirectoryAccess.chooseMany` 接入系统目录多选；取消重新选择保留原草稿，读取失败显示错误并允许重试。单目录选择继续供现有重新定位操作使用。
- 添加表单接入独立的 `LocalSourceConfiguration`：按原 `SourcesView.localConfiguration` 分为选择文件夹和分类，显示前四个目录名及剩余数量。移除旧表单的三类文件来源下拉框、手填名称和添加阶段的递归/隐藏开关，改用原默认值；移动盘及挂载 NAS 同样从本地目录入口选择。
- 按目录名保存来源，忽略已存在目录和本次重复选择；全部重复时沿用原提示。新增目录保持选择顺序进入扫描队列，已有来源不重扫。音乐默认 512 KiB；照片和其他视频默认不参与元数据拉取。
- 接入原经典主题的弹窗配色子集、主次按钮及三列分类胶囊，使用原分区和页脚组件；按钮响应鼠标、焦点、禁用与按压状态。目录/分类分区图标从原矢量路径翻译。

**本批不是完整三步向导或最终 UI 验收**：当前仍以本地配置弹窗承载“添加并扫描”；来源选择、步骤指示器和策略页尚未接入。分类胶囊的 SF Symbols 资源、名称居中截断、完整主题预设/系统材质/弹簧动画仍需迁移，不能据此声明像素级一致。保险库解锁和内容隐藏未迁移，因此分类入口暂禁用并说明原因，不把普通来源误当受保护来源。元数据解析和分类浏览也仍是既有缺口。

验证：全量 32 项测试通过，涵盖批量目录去重/顺序、离线已有目录跳过、分类默认值，以及浅深色多选/取消/错误草稿、添加到扫描再到浏览。修正按钮状态更新时序和主题字体继承、补齐正文高度上限后，3 项 UI 回归再次通过；静态分析无问题，16 个相关 Dart 文件格式检查及 `git diff --check` 通过，Windows Release 最终构建成功（39.1 秒）。用 Flutter 测试渲染并检查了 1088×720 浅色/深色预览，临时截图脚本已移除；该检查没有启动正式应用或调用真实目录选择器，也不替代 macOS 原版 UI 对照及三平台实机验收。

下一批接着补三步向导的其余依赖与设置行为；元数据解析/执行服务、隐私规则及 macOS 持久目录授权仍是完整本地来源验收的前置工作。

## 后续批次：文件名识别与分类索引（2026-10-06）

分类选择接入后，继续补扫描器依赖的识别规则。这是本地来源底层迁移的一部分，不代表三步向导已完成。

- 参考原 `FilenameParser.swift`、`ParsedMediaFile.swift`、`MediaScanner.importFile/musicTitle/resolvedMovieType`，以及原文件名、多语言与扫描边界测试。上述解析器、扫描器和测试在基线 `64f8ee2` 与旧仓库当前 HEAD 之间无差异。
- 迁移标题清理、发行年份、SxxExx/中文季集/EP/E/季目录编号识别、系列目录优先命名、来源根目录排除和强制电影规则。保留原版数字标题、短标题回退及发布标签规则，不另行扩展识别语法。
- 自动来源不再把所有视频记为其他视频；影片类别使用原扫描器映射，剧集记为 `episode`。相册绕过电影解析，保留原名并区分照片/其他视频；音乐采用原版曲目前缀清理，尚未读取音频标签。
- 年份、季号、集号及系列目录已写入当前初始表结构。系列目录存来源内相对路径，重新定位后不变；扫描更新会清除不再适用的字段。没有添加数据库升级、旧结构兼容或自动删除本机数据。
- 新增 `characters` 的直接依赖以对齐 Swift 的字素数量规则，版本仍是锁文件已有的 1.4.1。Dart 3.13.5 静态正则检查对 `Emoji_Presentation` 报误告；分别验证 Dart VM 和 Flutter VM 可正确过滤 Emoji、保留数字/标点后，仅在该表达式局部注明并抑制提示。

验证：全量 **46 项测试通过**（新增 11 项解析测试、3 项扫描/持久化测试），覆盖 POSIX/Windows/UNC 路径、原版多语言样例、真实临时目录、SQLite 重开、重新定位、重扫及分类切换后的字段清理。原隐藏文件测试改为断言文件身份，避免把未经清理的显示标题当成文件路径。静态分析无问题，7 个相关 Dart 文件格式检查及 `git diff --check` 通过；Windows Release 构建成功（32.5 秒）。本批没有启动正式应用、操作真实媒体库或进行 macOS/Linux 实机验收。

仍待完成：系列父条目、系列分类与季集分组，NFO/本地海报、音频标签、照片 EXIF 和元数据覆盖顺序；以及此前记录的完整向导、设置执行服务、隐私规则和 macOS 持久目录访问。本批不修改 UI 布局，也不把解析结果持久化等同于完整媒体库迁移。

## 后续批次：本地系列、NFO 与浏览（2026-10-06，待运行验收）

本轮依据用户“先把功能做出来，验收稍后测试”推进以下代码：

1. **系列与单集**：扫描一个剧集文件时生成系列父条目和单集条目，父类按原 `resolvedSeriesType` 映射，单集通过来源内父 ID 关联。系列目录/根目录散集命名沿原逻辑；系列键由相对目录或剧名编码，与有扩展名的文件键隔离，Windows 按路径大小写规则归一化。
2. **本地元数据**：迁移 `LocalMetadataService` 的文件/目录候选优先级、标题/原名/年份/简介规则与海报/背景图查找顺序。读取失败不跨候选合并，空字段回退文件名；`readNFO`、`preferLocalArtwork` 分别生效，暂未提供完整设置 UI。大于 64 KiB 的文本解析放到 isolate，不新增原版不支持的标签语法。
3. **保存与清理**：系列和单集在同一文件事务中写入，本轮保留集合同时记录父子键，成功重扫统一清理缺失条目，失败/取消沿用保留规则。数据库增加同来源父子外键与查询索引，来源删除一并清理。对照原 `MediaRepository.upsert`，相同身份类别重扫保留未读到的已有描述字段；身份类别变化时清除旧描述，区别于每轮都更新的父关系/季集编号。仅调整当前初始结构，无升级分支。
4. **浏览接入**：本地来源顶层显示电影/系列等入口，点击进入本地详情；多季默认折叠、单季平铺、特别篇/未分季命名与原版一致。海报网格和单集行随滚动分批查询，用户界面没有增加分页操作。新增本地详情路由与 Escape 返回，查询由来源 ID 加媒体键限定，不经旧服务端试验代码。
5. **图片与重定位**：索引保存来源内相对图片路径，当前来源根目录用于解析真实路径；本地图片缓存随成功扫描时间变化，读取/解码失败显示源码迁移的海报占位。背景图已发现和保存，完整艺术照展示链路仍待迁移。

源码依据包括 `MediaScanner.swift`、`MediaRepository.upsert/fetchChildren/deleteItems`、`LocalMetadataService.swift` 及其原测试；UI 对照 `DetailView.swift`、`EpisodeListView.swift`、`PosterGridView.swift`、`GeneratedPlaceholderPalette.swift` 和设计 tokens。所读本地元数据服务、详情、单集行及海报网格在原基线 `64f8ee2` 与旧仓库 HEAD 间无差异。

**本批检查**：Dart 格式化及静态分析通过，未运行单元/组件/冒烟测试、未执行构建、未打开正式应用。已有本机开发数据库未删除或迁移。验收延后不等于确认功能正确或界面一致，UI 缺口详见一致性核对清单。

**后续验收清单（本轮未执行）**：

- 两季剧集、特别篇、未分季、同名不同目录/来源、根目录散集的父子关联与排序。
- NFO 候选优先级、空字段、破损/非 UTF-8 文件、plot/overview、无效年份及策略开关；原仓储描述字段保留语义。
- 同一文件父子写入失败的回滚、重扫去重、单集/整剧删除、来源删除、取消/离线时保留、分类变化和重新定位。
- 新建 SQLite 重开后的父子和图片信息；用新的临时数据库验收当前结构，不自动改写或删除开发数据。
- 更新既有来源 UI 测试的旧列表/信息弹窗断言，覆盖网格 → 详情 → 分季展开 → 返回、分页加载、来源删除和图片不可读。
- 原版 UI 对照、Windows/macOS/Linux 构建与实机；HEIC 等本地图片解码及实际海报比例。

播放/观看状态、收藏、手工订正、定位文件、在线刮削、完整艺术照、音频标签和照片元数据仍待后续模块迁移。完整来源三步向导、macOS 持久目录授权和桌面框架也继续保留为阶段任务。

## 后续批次：本地来源设置与保存协调（2026-10-08，待运行验收）

本批实现来源设置入口和保存调用链，三步向导与自动扫描留在后续。依据 `SourcesView.SourceSettingsSheet/SourceBehaviorSettingsPanel`、`AppState.updateSource/restartScanIfNeeded/runScanQueue`、`AppColors.AppSwitchToggleStyle/AppInfoNote`、`VividIconLibrary` 及原来源仓储测试。

**纠正原计划**：原本地设置弹窗只有分类与参与策略，没有名称、递归、大小阈值或 NFO 编辑控件；保存也不是一律重新扫描。以原源码为准，不把模型字段全部扩展为新设置。

- 来源行增加设置入口，扫描期间仍能打开。弹窗使用独立草稿，取消不写入，保存先关闭弹窗再提交。分类可编辑；相册/其他视频隐藏元数据和写回选项。保险库因解锁/隐藏规则尚未迁移继续禁用。
- `SourceSettingsDraft` 只覆盖本地设置面板字段，其他配置从仓储最新快照保留。保存相册/其他视频时关闭元数据参与，不参与元数据时关闭写回；音乐阈值严格大于 5 MiB 才调整为 512 KiB。配置更新触发来源、详情和图片查询刷新，不移动、删除或重命名媒体文件。
- 空闲保存只更新配置，不扫描、不立即改写既有媒体分类索引；分类识别由下一次扫描更新。保存成功后若全局仍在扫描，取消当前任务并等待其退出，再把本次编辑来源排在首位重扫。原运行批次剩余来源取消，运行中另行追加的等待请求保留并去重；保存失败保留原扫描和队列。
- 页面暂复用现有成功提示/错误区域。原任务中心、系统通知与健康缓存失效依赖未迁移，不能称为全部 `updateSource` 副作用已完成。
- 元数据拉取、健康检查和写回显示原配置值，但暂禁用并说明原因。它们的执行服务尚未接入；这不是最终功能删减。已有 NFO/本地图片读取能力不等同于在线元数据拉取服务。
- 对照原弹窗 620 宽、700 高上限、正文 520 高上限、24 内边距、16 分区间距；迁移 44×26 开关与 20 圆点、齿轮标题插画、设置线性图标及信息卡片结构。完整主题、SF Symbols、按钮/通知外观和动效仍待原版对照，尚未宣称 UI 一比一完成。

检查结果：相关 Dart 文件格式化、`flutter analyze --no-pub` 通过。没有运行测试、构建、启动应用，也未修改数据库结构或自动处理旧开发数据库；未提交或推送。

后续验收需覆盖取消/保存/失败后重试、配置重开、音乐阈值边界和相册规则、空闲不扫描、扫描当前或其他来源时保存、初始批次与追加队列的区别、取消等待期间重复请求、关闭控制器，以及三桌面端弹窗/键盘/视觉对照。当前功能仅完成代码接入，以上场景尚未执行。

下一批先接原版参与策略对应执行依赖，再把已有本地配置与策略组件组合进三步向导；自动扫描与 macOS 持久目录授权继续按原调用链迁移。

## 后续批次：本地健康检测与参与策略（2026-10-08，待运行验收）

源码依据：`FileHealthEvaluator.swift` 及其原测试、`SourcePathPolicy.swift`、`MediaMetadataCompletenessPolicy.swift`、`AppState.scheduleFileHealthRefresh/rebuildDerivedItemCaches/ignoreHealthIssue`、`LibraryHealthCenterView.swift` 和 `SettingsView.advancedSettings`。文件健康、元数据完整性和仪表盘源码在原基线 `64f8ee2` 与旧仓库 HEAD 间无差异。

- 通过同一数据库读取事务取得来源/条目快照，再在事务外异步探测文件。按目录边界判断归属，Windows 使用对应路径规则；嵌套来源选择最具体的路径，不把相邻同前缀目录混为一谈。相同绝对路径在一轮检测中只探测一次。
- 将缺失条目、来源离线、可安全清理候选分别保存；忽略离线告警不会改变原始安全候选。照片仍参与文件缺失检查，音乐不参与；相册、其他视频、隐私和非顶层条目排除于影视元数据缺口，这是原版两套判断的区别。元数据缺口只看已存封面、年份和非空简介，不把图片文件探测当作完整性判断，也不由“参与元数据拉取”开关控制健康统计。
- `参与健康检查` 开关可编辑并持久化，排除路径及其下条目。来源修改/删除/重定位、扫描完成或取消触发新检测；旧任务协作取消，过期结果不能重新进入界面。页面支持重新检测、恢复前台刷新。全库结果列表在快照生成时派生，界面构建不逐条探测文件，也不重新过滤全库条目。
- 增加“仪表盘”路由，接入挂载源状态、影视元数据缺口和缺失文件列表；可扫描来源、前往源配置、打开缺失条目详情、忽略告警。设置中的“已忽略健康项”提供数量与恢复显示。忽略/恢复只重新过滤缓存，不重复执行全库文件探测。
- 初始表结构增加 `ignored_health_issues`，按类别、来源 ID 和媒体身份保存；没有数据库版本升级、开发数据兼容或自动重建。忽略配置与媒体索引分离，不修改媒体文件。

**本批边界（2026-10-12 历史状态）**：当时完整仪表盘尚未完成，概览环、离线缓存统计、后台任务、重复项等仍有依赖；失效索引清理尚未接入。仪表盘与任务中心 UI 后续已由 [2026-10-21 P1-F](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-f仪表盘与任务中心视觉收口) 收口；上述功能依赖（包括在线补充、音乐元数据、重复项/链接健康、详情资料缺口及重新挂载）仍需按各模块计划推进，不因本次视觉收口而视为已实现或已检测通过。照片和音乐数据边界按项目范围处理，不以空值假报缺口。

**UI 状态（2026-10-12 历史快照）**：当时仅完成本地区域基础布局，未完成完整仪表盘视觉；该快照已被 2026-10-21 P1-F 的组件实现和验证更新。P1-F 完成统一页头/操作、状态面板、监测与详情分区、缓存卡位置、响应式概览卡及任务中心表面；仍需按项目要求进行真实 Emby、实体键鼠、高 DPI 和 macOS/Linux 原生目视验收。元数据缺口排序/筛选等功能口径仍按对应业务记录，不因 UI 更新而改变。

**检查**：Dart 格式化、静态分析通过；未运行测试、构建或应用。后续验收覆盖在线缺文件/离线根目录、恢复挂载、路径前缀与嵌套排除、同名跨来源身份、私密/相册/音乐规则、连续刷新和过期结果、修改来源期间的探测、忽略持久化和恢复、详情返回，以及三桌面端 UI。保留前批次的未验收项，不沿用历史测试通过数。

下一步继续本地媒体依赖：完成安全索引清理与健康规则剩余部分，接入在线元数据与写回、向导、平台授权、本地播放与续播。本地媒体闭环后优先 Emby，顺序不变。

## 阶段目标与范围

后续新增需求（2026-10-08 用户确认）：[设置云备份与恢复](CLOUD_SETTINGS_PLAN.zh-CN.md)，首版计划支持 WebDAV。仅列入待办，尚未实现；当前继续本地媒体闭环，之后优先 Emby，不插入本批任务。

先建立完整的原版功能/UI 清单，再将桌面主框架、公共视觉组件和本地来源操作路径迁移到与原版一致。以 Windows、macOS、Linux 为目标；本阶段完成不代表整个 MediaLib、整个媒体源模块或全部服务器连接器已经迁移完成。

旧参考基线为 `64f8ee2`。本次核对的 `ContentView.swift`、`SourcesView.swift` 和 `MediaSource.swift` 在该基线与当前旧仓库 HEAD 之间没有差异；代理后来增加的系列摘要服务端接口不纳入原版需求。

## 任务顺序

| 顺序 | 任务 | 交付与完成条件 |
|---|---|---|
| N1 | 原版功能/UI 盘点与现状审核 | 页面、导航、来源类型、默认值、行为、依赖与测试逐项对应源码；现有 Flutter 文件标记复用、需修正、缺失，不能用现有实现反推需求 |
| N2 | 公共视觉和桌面主框架 | 按原 tokens、颜色、主题、材质、图标和组件实现；迁移侧栏分组、来源树、选中/展开、窗口宽度行为及已确认的交互；不把移动底部导航作为桌面窄窗口默认方案 |
| N3 | 来源页面与本地添加路径 | 按原来源页面、来源行、连接/断开分组、空态、扫描进度，以及三步添加向导迁移；本地路径支持原版已有的目录选择、分类和设置行为，替换当前自设计表单 |
| N4 | 来源模型、默认规则和桌面访问 | 核对来源配置与实际生效语义，修正扫描默认值差异；维护当前初始数据库结构；接通 macOS 持久目录访问，验证 Windows/Linux 文件访问 |
| N5 | 三桌面端对照验收 | 使用固定数据和窗口尺寸对照原版 UI/交互，运行原行为样例；记录 Windows/macOS/Linux 实际结果；CI 调整到三桌面端，无法在对应设备验证的项保留为未验收 |

N2、N3 的视觉和 N4 的行为共同完成后，才可以把本地来源路径标为完成。依赖尚未迁移的原功能明确记作缺口，不能用空按钮、无效设置或假成功充数。

## 已核对的原版入口

`ContentView.swift` 包含首页、视频分类、照片/录像、音乐分类、远程来源/媒体库、集合、智能歌单、健康、任务、媒体源和设置等导航。当前 Flutter 三项侧栏不能作为最终结构。盘点时继续追踪对应可见条件、顺序和事件，不机械地把所有枚举直接显示出来。

`SourcesView.swift` 的添加向导为“来源 → 连接 → 设置”，原版来源选项如下：

| 原入口 | 原语义与本阶段处理 |
|---|---|
| 本地目录 | 包含本机硬盘、移动硬盘和已挂载目录；本阶段迁移这条实际可用路径，核对多选、分类与设置 |
| 网络视频地址 | HTTP/RTSP 等视频地址；列入完整清单，后续按原实现迁移 |
| 网络设备 | SMB/FTP/FTPS 连接/挂载后选目录；列入清单与平台差异审计，不因先前计划只写“已挂载 NAS”而删除 |
| Emby、Jellyfin | 参考 `EmbyService.swift` 及其调用链；本阶段盘点认证、选库、同步和状态，完整连接器随后按模块迁移 |
| Plex | 参考 `PlexService.swift`，保留原服务器地址与 Token 连接行为，不套用 Emby 登录表单 |
| ReelNest Server | 对应原版 MediaLIB Server / Mlink 能力，按用户要求以新项目品牌迁移；作为可选来源，不是整个应用的运行前提 |

这批工作的验收对象是主框架和本地来源路径。其他来源暂未完成属于迁移状态，不是最终功能删减；不能宣称全部来源向导已完整可用。

## 规则纠偏要点

按 `MediaSource.swift` 和扫描调用链核对：分类、递归、自动扫描、最小文件大小、隐藏文件、NFO、本地海报偏好、网络刮削、缩略图回退、元数据/健康检查参与策略、写回偏好、远程痕迹同步和选库配置。

例如旧模型有 50 MiB 默认阈值，但扫描器的 `minimumFileSize(for:source:)` 对不同媒体有处理分支；迁移必须保留实际语义，不能统一给所有文件套 50 MiB，也不能保持当前“无阈值”的简化实现。字段存在不等于该功能完成，依赖未接入时不能显示为有效开关。

移动盘/NAS 的移除、离线、缺失项处理也按原行为与测试核对；已有新实现的“待找回”“重新定位”等设计需要验证其原版依据，不能直接作为新增需求保留。

## UI 验收

读取 `ContentView.swift`、`SourcesView.swift`、`DesignSystemTokens.swift`、`AppColors.swift`、`AppTheme.swift` 及相关组件、资源和事件处理，再实现 Flutter。验证选中、悬停、焦点、展开、右键、键盘操作、空态、加载、错误和扫描状态。

固定媒体样本、主题、窗口尺寸和缩放进行原版/新版本截图与操作对照。代码参数一致与 Flutter 组件测试不能替代 macOS 原版视觉验收；需要原版运行环境才能确认的部分保留待验收状态。系统材质、字体和窗口行为无法等效时记录具体差异，由用户决定，不擅自改成另一种设计。

## 之后的阶段

用户于 2026-10-08 确认：本地媒体完成后，下一项优先开发 **Emby 媒体源**。先完成本地来源、浏览/详情、播放/续播及对应原版行为的闭环，再进入 Emby；不要求先完成所有跨模块功能才开始 Emby。Jellyfin、Plex 与其他原有来源继续保留在范围内，但不与 Emby 同批展开。基础本地视频播放与续播已于 2026-10-09 接通；完整播放器、三步向导与平台授权仍待迁移/验收，不能把来源设置或基础播放完成等同于本地媒体全部完成。

Emby 阶段先对照原 `EmbyService.swift`、`SourcesView.swift` 和 AppState 调用链，依次迁移认证与会话、选库与同步、分页浏览/详情/图片、播放准备及观看状态同步。复用本地阶段建立的媒体模型、浏览组件和播放会话，客户端直接连接 Emby。模块归属见 [项目结构](PROJECT_STRUCTURE.zh-CN.md)，不在本轮提前创建连接器空目录。

在基线清单与上述框架稳定后，按原版模块逐项完成来源连接器、媒体浏览/详情、播放器与其他功能，每项同时验收功能和 UI。实际细分顺序以 N1 查明的依赖为依据，不承诺未经核对的固定工期。

## 后续批次：失效索引清理与挂载保护（2026-10-08）

- 沿原版确认流程接通单项“移出索引”与批量“清理失效索引”，只移除内部索引。
- 新增/重新定位记录挂载信息；扫描开始、成功清理前和手工清理时重新检查。挂载变化或未知时保留索引，避免卸载后可读空目录导致误清理。
- 清理重新验证文件不存在、来源/设置和条目未变；离线、权限异常、恢复文件及排除来源不删除。清理与扫描/来源修改互斥，同批事务失败回滚；保留其他来源与剧集兄弟项，最后一集移除后清理空父项。
- 本轮新增 17 项回归，结果见同日测试记录末尾。没有开发数据库升级、自动清库或修改旧 MediaLib 工程。
- 下一步继续原版本地来源闭环：三步添加向导和剩余平台授权/元数据依赖。播放器和 Emby 等远程来源按既有阶段推进，本批不视为整个本地媒体库或原版 UI 已验收。

## 本机空库启动修复（2026-10-09）

用户报告未添加媒体源仍持续加载/提示失败。本机早期空开发数据库结构不匹配当前初始表；空库不应该触发扫描，也不能把数据库初始化错误归为目录权限。已明确区分空库与初始化失败，仪表盘空状态不再显示“全部在线”；新增真实后台磁盘连接和两页组件回归，全量 93 项通过。开发数据库备份、Release 构建和启动记录见 [本轮记录](TEST_REPORT_2026-10-09.zh-CN.md)。没有引入历史兼容升级或自动清空数据库。

## 后续批次：本地视频播放与续播（2026-10-09）

对照原 `AppState.play`、`MpvPlayerController`、`MediaRepository.updatePlayback`、`PlayerView` 和 `DetailView`，接入独立视频窗口、电影/系列/单集入口、基本控制条、快捷键、默认续播回退和已看规则。引擎适配与业务会话分层，SQLite 记录按来源和媒体隔离；切换/关闭保存，离线与解码失败保留旧进度。详见 [本地视频播放](LOCAL_PLAYBACK.zh-CN.md)。

全量 107 项测试、静态分析、Windows 原生独立窗口解码测试通过。Release 构建与启动结果以当日记录为准；macOS/Linux 原生与原版 UI 未验收。本批不是完整播放器：字幕/音轨、队列、播放设置、剩余原版控制面板、材质和图标继续迁移。本地媒体闭环完成后仍优先 Emby，不提前扩展其他来源或云备份。

## 播放关闭与 Linux 卷身份修复（2026-10-09）

复查确认：关闭保存失败前过早销毁会话、Linux 挂载身份缺少稳定卷标识，两项问题均存在。新增回归在修复前失败，修复后通过。关闭现在先暂停/保存，保存失败后保留可用解码器与命令队列；重试恢复或明确放弃后再释放。Linux 本地卷身份改用 UUID，未知身份保护扫描与清理，不采用设备名回退。全量 119 项通过；详细验证、构建和平台边界见当日测试记录。原版字幕/音轨迁移及之后 Emby 的顺序不变。

## 字幕、音轨与音量面板（2026-10-09）

已迁移本地字幕/音轨选择、目录与手动字幕、双字幕、语言/关闭记忆、快慢、输出设备及增强，对应原版三个弹层的本地部分。纠正控制条的字幕/音轨入口与音量弹层，保留原尺寸和明暗调色规则。全量 138 项及 Windows 两项原生业务测试通过。边界见 [字幕/音轨说明](PLAYER_TRACKS.zh-CN.md)，构建/启动见当日记录。

下一批优先迁移原版播放队列、上一集/下一集及播完行为；在线字幕、完整播放设置、标记/迷你窗口和原版 UI/平台验收继续待办。本地媒体闭环之后仍优先 Emby，不提前展开其他连接器或云备份。

## 播放队列与播放结束行为（2026-10-09）

已按原版接入当前集及后续剧集列表、完整系列的手动上一集/下一集、顶层视频手动相邻项，以及自动下一集/停在结尾/关闭窗口。新视频实际打开成功后才释放旧解码器；失败/离线/保存异常保留当前会话，重复及过期 EOF 不重复切集。全局结束设置持久化，扫描和播放记录维护更新时间；详细结构、原版入口与边界见 [队列说明](PLAYER_QUEUE.zh-CN.md)。

全量 156 项回归、Windows 三项原生业务测试通过。本批迁移队列和播放结束设置行，不代表完整播放器设置或原版 UI 已完成。下一批继续倍速、完整播放设置与已有续播/已看规则的设置接入；标记/迷你窗口、在线字幕及三桌面端原生/UI 验收继续待办。本地媒体闭环后仍优先 Emby，安装包精简留在发布阶段。

## 本地视频播放器范围盘点（2026-10-09）

用户要求明确完整实现情况和剩余范围。当前状态、原版固定剩余清单和接 Emby 前的基础批次建议统一在 [播放器实现盘点](PLAYER_STATUS.zh-CN.md)。基础播放/字幕音轨/队列已接通，完整设置与 UI/三平台验收仍未完成；历史批次中的待办按当时进度阅读，不再把已完成队列计入剩余工作。音乐/照片/扫描/连接器单独跟踪，不混入本地视频播放器完成率。此次仅盘点与修正文档，没有继续实现功能。

## 基础播放设置与防休眠（2026-10-09，静态实现）

按用户要求写入倍速/默认与记忆、变调保护、快进快退步长、续播开关/回退、自动已看/阈值、启动音量，以及三桌面端原生防休眠。设置入口和持久化已接入；详细行为见 [基础播放设置](PLAYER_BASIC_SETTINGS.zh-CN.md)。没有运行测试、静态分析或构建，EXE 没有更新。本轮前的测试结果不代表这一批已通过。基础验收后仍优先 Emby，不继续扩大高级播放器前置范围。

## 基础设置测试完成（2026-10-09）

用户后续授权验证。新增 11 项专项回归，全量 167 项通过；Windows 3 项原生业务场景通过，含真实 mpv 倍速/变调与原生防休眠接口。修复数值类型及 Windows 插件链接问题，静态分析与 122 文件格式检查通过。Release 重新构建成功，EXE 更新时间 18:36:04，启动后主窗口保持响应，详见 [当日测试报告](TEST_REPORT_2026-10-09.zh-CN.md)。下一阶段优先 Emby；macOS/Linux、防休眠实际空闲超时与完整 UI 验收仍待进行，不扩展本地高级播放器前置范围。

## Emby E1：连接与选库（2026-10-09）

已接入来源类型选择、Emby 登录/策略、库范围设置、安全凭据与会话恢复、一次性自动重新认证、手动重新认证和删除清理；新增 18 项回归，全量 185 项与静态分析通过。协议直接连接 Emby，不依赖 ReelNest Server；当前不提供远程内容同步/浏览/播放。原版映射、凭据/失败保护、UI 阶段差异和验证边界见 [E1 说明](EMBY_CONNECTION.zh-CN.md)。

## Emby E2：同步与浏览（2026-10-09）

新增 21 项专项回归，全量 206 项通过；静态分析及 Windows 4 项原生业务场景通过。已接通自动/手动分页同步、库范围、完整快照事务、取消/失败保护、海报和电影/季集基本浏览。远程播放仍待 E3，完整 UI/详情扩展与平台验收仍在清单中，见 [E2 说明](EMBY_SYNC.zh-CN.md)。用户授权的 Release/数据库删除被自动审批阻止，未清理；构建采用覆盖现有运行目录。

## Emby 视频库操作与图片内存缓存（2026-10-10）

已接入海报/单集右键、可见范围全选与原版批量栏，想看/评级本机事务、系列观看、带确认的索引移除、清除记录后的旧播放器保护；图片加入稳定键、512 MiB/1800 张内存 LRU、3 路解码及两行/4 路预热。原版依据与范围见 [实施说明](EMBY_LIBRARY_ACTIONS.zh-CN.md)。

全量 369 项回归通过，原生和正式 Release 结果见当日测试记录。下一项按用户既定顺序推进首页；公共分类/搜索、手动集合/封面管理及章节图/标记依赖继续保留，音乐单独推进。真实 Emby、macOS/Linux 原生和完整视觉对照仍待验收。

## Emby 初始评级与显示分类（2026-10-10）

按用户确认的两项收尾，统一 10 分社区评分到 1–5 星的初始换算，保留人工评级与清空；按原版库名 → 题材 → 库类型 → 原始类型计算顶层远程展示分类，补建系列也继承题材。原始播放类型、父子关系及音乐同步保持既有语义。没有数据库升级或自动清库。

规则、实现入口及边界见 [评级与分类](EMBY_CLASSIFICATION_RATING.zh-CN.md)，验证与最新产物见 [测试记录](TEST_REPORT_2026-10-10.zh-CN.md)。下一项仍为首页，不在本轮新增公共分类页面、音乐或其他模块。

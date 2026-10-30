# 当前阶段与历史实施记录
当前摘要：截至 2026-10-27，Plex 基础视频来源已实现并完成 Windows 验证：Plex 专属后端24/24、共享后端255/255、同步/UI 63项通过；前端2/2、Windows Native单业务及最终Windows Release/smoke通过。本批未运行全量 Flutter 测试、不使用真实Token。真实 Plex、macOS/Linux 原生、人工视觉与辅助功能验收待。Jellyfin 基础视频来源闭环已实现并完成 Windows Release/smoke：共享协议 255/255、同步/界面 61/61、Emby 基线 37/37、Jellyfin UI 2/2、Windows Native 真实 mpv 业务链路通过；本批未跑全量 Flutter 测试。真实 Jellyfin、macOS/Linux 原生与人工视觉验收待。TMDB 本地电影定向复跑 39/39 通过；TMDB 本地剧集手动匹配最终后端定向 102/102、前端 12/12、Windows Profile 原生业务用例、Release 与五秒 smoke 均通过，本批未运行全量 Flutter 测试。剧集手动批量及定时自动匹配已完成各自 Windows 定向交付验证；自动匹配 179/179、analyze、Release 与五秒 smoke 通过。真实 TMDB 公服、macOS/Linux 原生、native Flutter drive、全量测试及人工精确视觉仍待。历史电影全量 1034 passed / 2 conditional skip / 1 原生用例及其 tearDown 未完成（exit 1）仍属电影批次，不改写、不与其他专项相加。缓存关闭取消专项独立验证通过；详见[Plex 计划](PLEX_PLAN.zh-CN.md)、[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)、[TMDB 电影计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)、[TMDB 剧集计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)及[缓存关闭取消记录](CACHE_SHUTDOWN_2026-10-26.zh-CN.md)。
更新：2026-10-30。遵循[项目边界](PROJECT_SCOPE.zh-CN.md)。

## 2026-10-30 前端 P0 全局顶部浮窗通知对齐原版（Windows 定向交付验证通过）

- 生产环境 `showAppToast` 不再使用底部 SnackBar。`ReelNestApp` 根部安装 `AppFeedbackScope`，`DesktopShell` 内容区安装 `AppFloatingNoticeHost`，通知在内容区顶部居中显示，不遮挡侧边栏。
- 卡片按原 `ContentView.swift` 的 `FloatingNoticeCapsule` 收口：单层表面、最大宽560px并保留左右20px窄窗安全边距、28px语义色圆形图标、居中文字、22px关闭入口、hover轻微缩放/阴影；Reduce Motion下取消位移及时长，220ms进入、160ms退出。
- `AppFeedbackController` 同时只显示一条并按FIFO排队，最多保留12条等待；默认显示4.2秒、最短1.2秒，支持手动关闭。宿主移除时清空计时器及队列。页面内联 `AppInlineNotice` 保持原样；缺少完整应用作用域的隔离组件测试安全回退至SnackBar，不影响生产路径。调用方文案与业务不变。
- 首轮组合因旧测试直接挂载 `DesktopShell`、缺少应用根作用域而有6项失败；增加无Scope安全降级后最终组合79/79通过，并补充队列上限用例，最终有效验证共80项通过（`app_feedback` 最终7/7）。覆盖应用壳、健康、Emby/Jellyfin/Plex、URL、来源生命周期、深浅色及Windows/macOS/Linux组件变体。`flutter analyze` No issues（12.8秒；前序完整分析74.9秒）；`dart format` 4 files、0 changed；diff-check通过。Windows Release 59.3秒成功；五秒 smoke 于2026-10-30 18:52:06 +08通过（HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0），无残留进程；Flutter临时工具链修改已还原。
- 未做可见窗口逐像素/实体鼠标、长时间通知队列、高DPI或macOS/Linux原生实机验收；未推进移动端布局，未改变业务/持久化/后端。详见[前端 P1-G 全局弹层与反馈表面记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-g-全局弹层与反馈表面统一)。

## 2026-10-30 前端 P0 全局危险操作确认弹窗收口（Windows 定向交付验证通过）

- `AppConfirmationDialog` 从双层厚重矩形改为紧凑单层表面：最大宽430px、圆形语义图标、16px标题、12.5px正文、36px操作按钮，并移除正文内嵌矩形卡。`SourceSheetButton` 增加可选 autofocus；确认弹窗默认聚焦安全“取消”，Enter 执行取消，危险确认继续使用红色。340×300窄窗在16px安全边距内布局。
- 既有共享确认入口覆盖媒体源删除、URL移除、媒体库批量移除、健康索引清理、缓存清理等。所有调用方的业务、文案及返回值保持不变。
- 7个测试文件共60项通过，覆盖Windows/macOS/Linux组件变体、深浅主题及取消不删除；`flutter analyze` No issues（110.1秒）；`dart format` 3 files、0 changed；diff-check通过。Windows Release 104.6秒成功；五秒 smoke 于2026-10-30 12:27:12 +08通过（HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0），无残留进程；Flutter临时工具链修改已还原。
- 未做可见窗口逐像素/实体键鼠、高DPI及macOS/Linux原生实机验收；未改变删除/清理业务、持久化或后端。详见既有[全局弹层与反馈表面记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-g-全局弹层与反馈表面统一)。

## 2026-10-29 播放器错误反馈与决策弹窗 P0（Windows 定向验证通过）

- 播放进度保存失败时改用播放器专用 `PlayerDecisionDialog`：深色/玻璃表面、最大宽430px、160ms fade+scale；Esc和遮罩可关闭，默认聚焦安全的“重试”，危险的“仍然关闭”使用红色。行为保持不变：重试再次保存，仍然关闭则放弃保存并退出，取消则留在播放器。
- 全屏切换、迷你模式和外部播放器失败改为播放器内通知，按 information/error 展示对应图标与颜色，不再错误显示成功勾；外部字幕文件选择失败改为字幕面板内联错误，不再用 SnackBar。
- 网络串流专用输入弹层维持现状：虽然使用 `showDialog`，其内容已采用项目统一 `AppSheet`，不属于默认白色 Material 弹层断层。
- 相关6个测试文件共87项通过；`flutter analyze` 无问题；Windows Release 37.9秒成功；五秒 smoke 于2026-10-29 15:33:38 +08通过（HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0），无残留进程。
- 未完成真实文件选择器失败注入的可见验收、macOS/Linux实机及真实媒体逐项视觉验收；本轮未改变播放业务、持久化或后端。详情见[播放器状态盘点](PLAYER_STATUS.zh-CN.md#2026-10-29-播放器错误反馈与决策弹窗-p0)。

## 2026-10-29 播放器窗口尺寸与自适应 P0（Windows 定向验证通过）

- 对照原 `PlayerView.swift` 的 `VideoPlayerWindowPresenter` / `VideoWindowSizing`：移除 `player_window_app` 固定960×540，改为可用屏幕区域内居中；横屏默认优选宽1120、最多98.5%可用宽/94%可用高，竖屏按可用高度约90%定尺寸。记忆宽度、横竖屏切换、真实解码比例修正及独立全屏/最大化/迷你窗恢复按原版规则处理。
- 引擎真实 aspect/远程 resolution 到达后串行更新最小尺寸、窗口比例和位置；横屏最小控制安全区680×382并按比例扩展，竖屏最小宽360/最小高560。仅横屏普通窗口手动调整结束后经420ms debounce保存 `global.videoPlayerPreferredWidth`；全屏、最大化及迷你窗不写该偏好。原生 full-screen/maximize 事件同步图标状态；迷你窗进入、比例变化和退出恢复普通窗口当前最小尺寸与 aspect。
- 360px窄窗下 Dock 保持324×72，leading/trailing区宽69/106且不溢出；窄态保留字幕/音轨、播放三键、设置、迷你窗和全屏，低优先操作仍可从二级菜单或扩大窗口访问。
- 播放器窗口/播放/基础设置/画面设置/快捷键5文件54/54通过；`flutter analyze` 0 issue；Windows Release 38.5秒成功；hidden smoke 于2026-10-29 15:20:25 +08通过（HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0），无残留进程；SDK临时修改已还原，diff-check无错误（仅既有CRLF提示）。
- 尚未验证可见播放器真实窗口、实体拖拽缩放、竖屏真实视频、macOS/Linux原生及全量Flutter测试。此批是Windows实现与自动化/Release验证，不代表上述实机验收完成。详见[播放器状态盘点](PLAYER_STATUS.zh-CN.md#2026-10-29-播放器窗口尺寸与自适应-p0)。

## 2026-10-29 URL 媒体源管理弹窗 P0（Windows 定向交付验证通过）

- 对照原 MediaLib `SourcesView.URLSourceManagementSheet` 收口管理弹窗，保留单条/批量添加、名称、健康检查、封面、编辑、删除及空来源容器清理规则。删除确认改用 `SourceConfirmationDialog`，标题“删除 URL 地址？”，显示条目名，并明确本机下载文件不会删除；删除使用破坏性色按钮。
- 添加区域、普通行和编辑行统一弹窗表面/前景描边；普通行增加140ms轻量悬浮反馈且不改变布局。普通/编辑态使用180ms过渡并尊重 `disableAnimations`。封面/编辑/删除按钮统一36×36命中区，覆盖悬浮、键盘焦点和删除破坏性色。加载状态保持静态进度视觉，避免持续旋转影响测试等待。
- URL/UI/数据/来源联动21项通过，另有2个native mpv用例按条件跳过；`flutter analyze` 0 issue；Windows Release 38.5秒成功。后台 smoke 于2026-10-29 15:05:46 +08通过（HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0），无 ReelNest 残留进程。Flutter SDK临时兼容改动已还原。
- 状态：Windows 定向交付验证通过；macOS/Linux及可见像素人工验收仍待。未扩大到URL下载、来源其他功能或跨平台实机验收。详见[URL 视频来源计划](URL_VIDEO_SOURCE_PLAN.zh-CN.md#2026-10-29-url-管理弹窗-p0windows-定向交付验证通过)。

## 2026-10-29 媒体源设置 P0（Windows 定向交付验证通过）

- 远程媒体库设置页按原 Swift `SourceSettingsSheet.remoteLibrarySection/libraryRow` 收口。“同步全部媒体库”和单库行改为单层选中卡片，14/12px圆角、前景描边不占布局、140ms hover/focus/selected过渡；单一 InkWell焦点并提供Semantics button/selected/enabled，保持同步范围与保存逻辑不变。
- 媒体库类型图标区分 movies、tvshows、music、boxsets、playlists、homevideos、livetv及其他；照片仍按既定范围过滤。加载态130px、空态150px、错误重试独立状态，用180ms AnimatedSwitcher切换并尊重Reduce Motion。加载环使用固定进度视觉，避免无限动画令 `pumpAndSettle` 推进虚拟时钟并触发 loopback 连接超时。
- 测试覆盖900×820窗口下同步全部/单库卡的几何关系与 hover 无布局跳变，并改为等待明确的 library-list key。7文件57/57通过；全项目 `flutter analyze` 0 issue（60.9秒）；Windows Release 46.2秒成功；项目 hidden smoke 于2026-10-29 14:54:06 +08通过（响应、正常关闭、ExitCode 0）；diff-check通过且无 ReelNest 进程残留。
- 状态：Windows 定向交付验证通过；可见像素人工验收及 macOS/Linux 原生验收仍待。详见[项目状态总览](IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md#状态基线)。

## 2026-10-29 媒体源系统 P1 第二批（Windows 定向交付验证通过）

- 新增共享 `source_wizard_steps.dart`，本地来源向导、来源类型选择及 Emby/Jellyfin/Plex 连接流程统一使用原 Swift `AddMediaSourceWizardSheet.stepIndicator` 三步结构。内容宽572时严格572×40；14px圆角、水平14/垂直12内距、92px步骤槽及两段等宽2px连接线；边框以前景绘制，避免布局尺寸变化。
- 每一步补齐 Semantics：整体暴露“第N步/共3步”，子步骤分别表达已完成/当前状态；覆盖明暗主题。远程服务器连接页切换到参与策略页使用180ms AnimatedSwitcher（easeOut/easeIn），Reduce Motion时为0ms，并用 key 区分 connect/settings 状态。
- 来源类型卡移除 `FocusableActionDetector` 与 `InkWell` 双焦点，改由单一 `InkWell` 处理 hover/focus；保留160ms视觉过渡和键盘激活路径。连接、凭据、扫描及设置持久化业务未改。
- sources/local/url/Emby/Jellyfin/Plex相关7文件41/41通过；全项目 `flutter analyze` 0 issue；Windows Release 38.0秒成功。项目脚本 hidden smoke 于2026-10-29 10:38:42 +08通过：窗口响应、正常关闭、ExitCode 0，且无 ReelNest 进程残留。`git diff --check`通过（仅有既有CRLF提示）。
- 状态：本批 Windows 定向交付验证通过；可见窗口逐像素人工验收及 macOS/Linux 原生验收仍待。第一批的14文件测试和34.7秒Release分别记录；其隐藏启动探针未能正常关闭，不与本批 smoke 结果混用。详见[媒体源系统 P1 首批](NEXT_STAGE.zh-CN.md#2026-10-29-媒体源系统-p1-首批windows-前端与-release-验证通过smoke-未完成正常关闭)。

## 2026-10-29 媒体源系统 P1 首批（Windows 前端与 Release 验证通过；smoke 未完成正常关闭）

- SourcesPage 空态按原 Swift `EmptyStateView` 对齐：移除矩形外卡，恢复104px径向光晕、76px圆角图标块、112×104图标槽、最小高度320px、240ms淡入/轻上浮与 Reduce Motion；保留 ReelNest/URL 授权后的品牌和范围文案。
- 加载态按原 `AppLoadingView` 对齐：22px单层表面、标题“正在加载媒体源/正在准备当前页面”、38px标题图标、72px骨架行、52px图块、10px行距；描边改为前景绘制，避免布局尺寸缩小。
- 来源类型卡统一为264×88、14px圆角；补160ms悬浮/焦点过渡、2px上浮、单层阴影、焦点描边及Semantics selected/button。不改来源业务流程。新增空态/加载态几何与来源卡悬浮无布局跳变测试。
- 14个 sources/local/url/jellyfin/plex 前端用例通过；全项目 `flutter analyze` 0 issue；Windows Release构建34.7秒成功。隐藏启动探针观测5秒 `Responding=true`，但隐藏窗口没有 `CloseMainWindow` handle，随后仅终止本次测试进程；因此**不记录为正常关闭或 smoke 验收通过**。
- 状态：前端专项与Windows Release通过；可见窗口像素级人工验收仍待完成。此批不代表媒体源系统整体或跨平台验收完成。

## 2026-10-29 侧边栏状态卡 P0 第三批收口（Windows 定向交付验证通过）

- 以原 Swift `ContentView.swift` 的 `sidebarRotatingStatusTiers` 与 `SidebarStatusCenterCard` 为基线。失效文件和疑似重复加入 attention 轮换，点击统一进入健康中心；只接受 revision 匹配、`evaluationComplete`、来源数量/identity/`lastScan` 均匹配的健康快照，不发起额外 I/O。
- 视觉按原版收口：卡体严格 224×58（252px 侧栏内左右各14px）；32px leading、25px trailing；14px 线性 glyph；失效文件/重复项分别使用 missing-folder/overlapping glyph 与原版橙红渐变。状态切换为180ms淡入并向上7px（Flutter等价偏移0.12）；进度条宽度至少10px、3px高、0.72透明度，并按14px圆角裁切。
- 首轮交叉组22通过、2失败，暴露0.8px边框参与布局后卡体高59.6px。已将边框移到 `Material` shape side，保持严格58px断言并通过最终复核；未放宽尺寸断言。
- 最终5文件交叉组59/59（`apps/client/build/sidebar-status-p0-delivery-tests.log`），专项复核7/7（`apps/client/build/sidebar-status-p0-recheck-tests.log`）；analyze无问题、61.4秒（`apps/client/build/sidebar-status-p0-analyze.log`）；3个文件format 0 changed、diff-check通过。Windows Release 44.7秒（`apps/client/build/sidebar-status-p0-release.log`）；5秒 hidden smoke 于2026-10-29 09:45:01 +08通过，窗口响应、正常关闭、ExitCode 0（`apps/client/build/sidebar-status-p0-smoke.json`）。
- 状态：**Windows 定向交付验证通过**。可见窗口逐像素对照、真实健康数据下的长时轮换、macOS/Linux原生验收仍待。侧栏整体仍未完成；音乐迷你控制、更新、保险库锁定、赞赏、失败任务重试/活动任务取消尚未迁移。详见[项目状态总览](IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md#状态基线)。

## 2026-10-28 侧边栏状态卡 P0 第三批（实现，未验证）

- 侧栏状态卡新增失效文件数与疑似重复组数两类独立状态，入口指向健康中心；与离线来源和低健康度问题共同轮换，不固定遮挡其他问题。
- 仅采用当前来源修订对应、扫描完整且来源配置/扫描时间仍匹配的健康快照；扫描缺失、未完成、已过期或当前视频来源集合不一致时不展示这两项，且不触发额外扫描或 I/O。
- 本批尚未运行测试、analyze、构建或可见 UI 对照。音乐迷你控制、应用更新/检查、保险库快捷锁定、赞赏提示、失败任务重试/活动任务取消仍未迁移；这些依赖当前尚未接入侧栏的对应应用能力，不添加占位操作。

## 2026-10-27 本地剧集/动漫 TMDB 手动批量匹配（Windows 定向交付验证通过）

- 本阶段扩展 2026-10-26 已完成的单项手动匹配，单独实现人工启动的本地剧集/动漫批量匹配。候选仅取参与元数据拉取的文件来源顶层 `tvShow`/`anime` series；同语言已匹配项跳过，语言变化后可重匹配。远程服务器资料不修改。
- 使用原版三档影视匹配宽容度：默认宽松，阈值 0.42/0.58/0.74，查询预算 16/10/6；标题/原名及集文件父/祖父目录生成清洗查询，评分含年份修正、保留相关性同分顺序，并迁移具体查询唯一命中规则（0.52置信下限只可直接满足宽松档）。评分在 isolate 运行并支持取消等待。
- 批次支持共享进行中任务、HTTP 取消、进度分类和逐项失败隔离。复用现有 `TmdbVideoService` 和 artwork cache；任务前后对来源/索引/配置/元数据快照校验，避免扫描、来源移除/变化、手工编辑或语言变化期间提交过期结果。宽容度变更只影响后续批次。`SourceSettingsSheet` 可编辑并保存 `includeInMetadataFetch`；`preferMetadataWriteToSource` 和 NFO 写回仍禁用。
- 范围不含自动周期、NFO/媒体文件写回或远程资料修改；仅本地文件来源系列参与，动漫分类与远程系列排除有专项覆盖。评分 isolate 对超过1024字符的标题拒绝单项处理；HTTP/单项 diagnostics 只保留脱敏 code/type/stack，不记录关键词、路径或凭据。最终13文件160/160通过（41秒，`apps/client/build/tmdb-batch-tests.log`），analyze clean（4.8秒），44个工作区变更 Dart 文件 format 0 changed、diff-check通过。首轮74项与159项为中间批次，不累计。Windows Release 52.7秒，`data/app.so` 为2026-10-27 21:48:27 +08、13,222,792 bytes；五秒 hidden smoke 于 `2026-10-27T21:49:11.0304196+08:00` 通过（响应、正常关闭、ExitCode 0）。
- 本轮仅完成批量匹配相关 UI 和 `SourceSettingsSheet` 的元数据参与开关；来源列表 `SourceRow` 未修改。未跑全量测试、native Flutter drive、真实 TMDB 凭据/公服、macOS/Linux 原生、实体目录或可见 UI 验收；不宣称来源列表像素对齐。来源设置、专项验证与先前单项匹配结果分开记录，详见[TMDB 剧集计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。

## 2026-10-27 本地剧集/动漫 TMDB 定时自动匹配（Windows 定向交付验证通过）

- 复用 `AutomaticScanInterval` 五档，使用独立 `global.automaticTMDBMatchInterval` 偏好，默认关闭且不改 SQLite schema。开启后等待完整周期才首次匹配；忙于扫描/匹配时跳过 tick、不追补；无凭据/无候选静默跳过并保留既有结果。
- 自动请求使用独立取消 token。按用户确认的“关闭即取消”规则，关闭周期会取消当前自动任务但不影响手动批次；这是当前明确批准的行为，不据此推断原版关闭周期时一定会中断已运行任务。普通切换周期只重设 timer、不打断运行中的任务；同值、语言、宽容度变更不重设周期。退出时停止 timer、取消自动请求后再排空 batch/数据库。启动恢复偏好时不预建 HTTP/batch 服务或遍历媒体目录。
- 自动匹配只覆盖本地、参与元数据的、未按当前语言匹配的 TV/anime 顶层项；沿用手动批次保护、宽容度与失败隔离，不修改远程资料。无 NFO 写回、无 SourceRow 和新连接器工作。15 文件整合回归 179/179 通过（48 秒），最终 `flutter analyze` clean（4.4 秒）；覆盖五档虚拟时间周期、忙碌跳过、重复 tick、改周期、取消 token、退出取消、loopback batch 取消提交保护、已存周期恢复及默认不触发 batch/HTTP 等。上一阶段手动批量 160 项与本轮有覆盖重叠，分批记录、不累计。Windows Release 构建 45.9 秒（`apps/client/build/tmdb-automatic-release.log`），`data/app.so` 时间为 2026-10-27 22:07:19 +08、13,239,176 bytes；五秒 hidden smoke 于 `2026-10-27T22:08:29.8982322+08:00` 通过（响应、正常关闭、ExitCode 0），报告为 `apps/client/build/tmdb-automatic-smoke.json`。48 个工作区变更 Dart 文件 format 0 changed，diff-check 通过。本阶段 Windows 定向交付验证通过。未运行 native Flutter drive、真实 TMDB 公服、macOS/Linux 原生、可见 UI、全量测试或真实 15 分钟墙钟等待；虚拟时间不能替代长期运行验收。详见[TMDB 剧集计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。

## 2026-10-28 本地视频健康补充与 NFO 写回（Windows 定向交付验证通过）

- 只读核对原版 `VideoMetadataSidecarPolicy`、`VideoMetadataSidecarWriter`、`AppState+MetadataSupplement.swift` 和健康中心入口。原版 NFO 写回仅从健康中心一键补充流程触发；普通 TMDB 单项、批量和定时匹配不写 NFO。原版侧车策略与安全限制、Dart 迁移范围和验收清单见[本地视频元数据写回计划](LOCAL_VIDEO_METADATA_WRITEBACK_PLAN.zh-CN.md)。
- 本批计划覆盖本地电影、电视剧与动漫缺失字段补充；来源写回默认关闭并要求来源参与元数据。电影写同 basename `.nfo`；剧集/动漫需确认所有 episode 属于共同系列目录后才写 `tvshow.nfo`。不扩展到原版其他视频类型，不修改媒体文件本体。
- 实现：`MetadataSupplementService` 限定参与元数据的本地电影及 TV/anime series，复用现有 TMDB matcher；`TmdbVideoService.apply(..., supplementOnly: true)` 只补缺失字段并保留既有描述信息。先提交 ReelNest 索引，再独立执行 NFO 写回；写回失败保留索引并在健康结果中提示 warning，不宣称数据库与文件系统之间具备原子事务。普通单项/批量/定时匹配仍不调用 NFO writer。
- `VideoNfoPolicy`/`VideoNfoWriter` 已接入路径归属、XML 安全合并、同目录临时文件与平台原子发布、并发检测和失败恢复。电影写同 basename `.nfo`；剧集/动漫仅在所有现有 episode 确认属于共同系列目录时写 `tvshow.nfo`。来源 `preferMetadataWriteToSource` 默认关闭，并受 `includeInMetadataFetch` 控制。健康中心已有一键入口、运行进度和 NFO 警告结果。
- 原版顺序：`performMetadataSupplement` 先尝试调用 sidecar writer，写回失败只记 warning，随后更新 MediaLib 索引。当前 ReelNest 的安全实现顺序为先提交索引事务，再独立写 NFO；二者不是跨数据库/文件系统的原子事务。补充合并保留已有年份、简介、封面等资料；localized TMDB identity 相同时保留用户编辑标题，首次或更换匹配可更新标题。
- 验证：15 个定向文件 164/164 通过（约 9 秒，`apps/client/build/nfo-final-tests.log`）；`flutter analyze` no issues（3.9 秒，`apps/client/build/nfo-final-analyze.log`）；61 个变更/新增 Dart 文件格式检查 0 更改，`git diff --check` 通过。覆盖 writer/policy/supplement、健康中心 UI、来源配置、TMDB movie/series/batch/automatic/UI、health evaluator 与 app 回归，并验证 NFO 写入后由 `LocalMetadataService` 读取及真实来源重扫恢复字段。此前失败/重复运行不累计。Windows 原生 writer 安全回归首轮通过；Release 构建 44.3 秒成功（`apps/client/build/nfo-release.log`）；五秒 hidden smoke 于 `2026-10-28T09:52:30.7252957+08:00` 通过，`apps/client/build/nfo-smoke.json` 确认窗口响应、正常关闭、ExitCode 0。
- 状态：**Windows 定向交付验证通过。** 本批未运行全量测试；macOS/Linux 原生、真实 NAS/挂载、可见 UI 对照仍未验收，不宣称跨平台写回完成。详细边界见[本地视频元数据写回计划](LOCAL_VIDEO_METADATA_WRITEBACK_PLAN.zh-CN.md)。

## 2026-10-28 来源主页 P0（Windows 定向交付验证通过）

- 本轮以原版 Swift `SourcesView.SourceRowView` 为基线，属于迁移而非重新设计。来源列表为紧凑单行：52×52 avatar、水平18/垂直16 padding，严格常态/hover 84px；状态/来源类型 badge 同层；34×34轻量操作同行呈现，移除旧底部文字工具栏。hover -4px/180ms/22 blur；边框用 `foregroundDecoration` 模拟 Swift `strokeBorder`，避免布局多2px。Emby/Jellyfin/Plex行采用原版通用server glyph，品牌mark保留在连接流程；别名、重新定位、重新认证入口在更多菜单中保留。
- 首轮58/3因边框占布局导致行高86px及等待条件不正确而失败，均已修正；严格84px断言未放宽。Jellyfin/Plex用例等待策略sheet关闭、来源头像出现后再断言；本地「更多→重新定位」可用且点击不会被整行导航抢占。
- 最终8文件交付组82/82（18秒，`apps/client/build/source-row-delivery-tests.log`）通过，覆盖来源6文件及URL UI/app；analyze no issues（`apps/client/build/source-row-analyze.log`），33个工作区Dart文件format 0 changed，diff-check通过。Windows Release52.7秒（`apps/client/build/source-row-release.log`）；五秒hidden smoke于`2026-10-28T21:32:15.4742902+08:00`通过，窗口响应、正常关闭、ExitCode 0（`apps/client/build/source-row-smoke.json`）。首轮58/3及三文件5/5是中间结果，不累计。
- 状态：**Windows 本批定向交付验证通过。** 真实可见 UI 逐像素复核、macOS/Linux原生、系统目录选择器和真实远程服务仍待；不宣称全局UI一致。详情见[本地来源文档](LOCAL_SOURCES.zh-CN.md#2026-10-28来源主页-p0windows定向交付验证通过)。本轮不改写 URL 来源历史证据。

## 2026-10-28 持久 URL 视频媒体源（封面修订后 Windows 定向交付验证通过）

- 持久 URL 来源已接入唯一 `urlsource://local` 容器、单条/多行去重、增删改、空容器清理、当前来源浏览、详情、内置播放/HTTP(S) 外部播放、播放进度、添加后自动封面、复制链接与 HTTP(S) 健康探测。非 HTTP(S) 协议不做健康探测；持久来源和临时打开串流是不同流程。全局其他视频分类入口未迁移；URL 离线下载和手动/自定义封面入口也未迁移，作为原版已有能力及公共缓存/封面模块依赖保留在后续范围。
- 健康失效 URL 列表、管理/复制/删除/忽略与设置恢复已补齐；CRUD 不等待健康请求，手动刷新不锁定管理 sheet 且可关闭。原版 `ThumbnailGenerator` 只读核对后发现封面和普通预览解码策略不同，因此补齐源比例/采样语义，作为质量修正记录。
- 封面保持源比例、最大900×1350且不放大小图；普通预览仍312×176。取样比例依次为 `[0.2,0.15,0.2,0.3]`；每次位置为时长×比例，至少取第1秒，ratio限0.01–0.95。黑帧采用800点/37×53采样、亮度低于16且黑点比例超过0.88。封面/预览共用worker，以mode隔离。修订后8文件定向52/52（7秒，`apps/client/build/url-cover-final-tests.log`）、最终 analyze no issues（`apps/client/build/url-cover-final-analyze.log`）；覆盖native3、URL/health UI、backend12、普通preview/proxy/session。native PNG尺寸160×90断言保持小图原比例、不强制312×176黑边；普通预览native仍312×176。
- 189/189整合及修订后52/52有覆盖重叠，分批记录、不累计；修订前20/20交付组仅作中间证据。修订后 Windows Release 39.0秒成功（`apps/client/build/url-cover-release.log`）；五秒 hidden smoke 于 `2026-10-28T21:09:12.4990275+08:00` 通过（响应正常、正常关闭、ExitCode 0；`apps/client/build/url-cover-smoke.json`）。26个变更/新增 Dart 文件格式检查0变化，`git diff --check`通过。此前53.1秒Release及14:59 smoke属于封面修订前中间批次。
- macOS/Linux原生、真实服务/公网 URL、逐像素 UI 与全量测试仍待；native网络用例仅loopback HTTP。外部播放器仅支持HTTP/HTTPS；其他协议只由内置播放器尝试。`homeVideo` 接入仅覆盖 URL 来源当前浏览，不代表全局公共分类入口完成。URL下载、手动/自定义封面、全局分类入口保留为原版待迁移范围。范围不含SMB/FTP挂载、音乐、照片。详见[持久 URL 视频来源计划](URL_VIDEO_SOURCE_PLAN.zh-CN.md)。
- 建议的后续候选为 HTTP(S) URL 离线缓存；这只是下一阶段建议，未实现也未纳入本批交付，需另行确定范围和验收条件。

## 2026-10-27 来源向导与来源设置 P0（Windows 验证通过）

- 本地添加流程迁移为原版三步结构：来源选择 → 连接/目录与媒体分类 → 设置/参与策略；配置页上一步返回来源类型选择，设置页上一步返回配置页。当时该批仅开放已接入的本地目录、Emby、Jellyfin、Plex。持久 URL 视频来源已由 2026-10-28 后续批次启动实现，尚未完成验收；网络位置和 ReelNest Server 仍待迁移，原版可选连接器也未作为永久删除处理。
- 第三步可确认并持久化 `autoScan`、`includeInMetadataFetch`、`includeInHealthCheck`、`preferMetadataWriteToSource`。照片/家庭视频继续依现有约束规范化元数据选项；重复来源不覆盖原设置，部分失败和重试行为不变。SourceOptions schema 未变。补齐来源图标 `chevronRight`、本地来源说明文案和向导步骤视觉。
- 验证：定向/核心测试90/90通过（后端策略测试包含在内）；`flutter analyze` 0 issues；Windows Release 41.9秒成功。`windows-smoke` 于 `2026-10-27T21:21:32.9178198+08:00` 通过，HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0。
- 后续边界：截至 2026-10-27 批次，来源主页 `SourceRow` 仍是过渡实现；下一日的独立 P0 实现接入与待验边界见本节。真实系统目录选择器及 macOS/Linux 原生验收仍待。此批不等于所有原版来源连接器完成，也不把设置策略持久化等同于策略执行服务全部验收。见[本地来源文档](LOCAL_SOURCES.zh-CN.md#2026-10-27来源向导与来源设置-p0windows-验证通过)。

## 2026-10-27 本地媒体自动监控与增量更新（Windows 自动化/Release 验证通过）

- 自动扫描间隔沿用原版默认关闭与五档选项；开启后并行运行本地文件事件监控和周期扫描，来源设置可单独关闭 `autoScan`。本地文件来源（含移动盘、已挂载 NAS）参与，Emby/Jellyfin/Plex 不自动同步。事件按 1.2 秒合并，按最长根路径归属；目录结构变化及原生事件中断/溢出触发完整扫描，其余路径交 `scanChanges`。增量扫描复用文件解析、NFO/海报和隐藏过滤；同一现有扫描队列合并待执行路径，全扫覆盖局部请求，执行时重检来源参与状态。
- Windows/macOS 递归监控；Linux 建立逐目录 inotify 树并在目录变化时重建。关闭自动扫描、移除来源、关闭来源参与时释放监听；退出先停监控再关数据库。监控错误日志脱敏，单源监控失败不阻塞其他来源；周期扫描用于兜底并恢复监听。
- 验证：8 文件 78/78 通过（16 秒，`apps/client/build/automatic-scan-tests.log`）：`automatic_source_scanner_test` 8、`local_incremental_scan_test` 8、`local_file_monitor_test` 2、`source_scan_queue_test` 8、`source_repository_test` 20、`automatic_scan_frontend_test` 2、`health_ui_test` 12、`home_runtime_test` 18。增量链路覆盖真实文件通知经 `SourceScans` 到数据库新增/重命名/删除；另覆盖 watcher 原生错误回调将 error/stack 传至 scanner 错误处理、脱敏 diagnostics 并触发保护性全扫。`flutter analyze` clean（4.6 秒）；Windows Release 43.4 秒；hidden smoke 于 `2026-10-27T20:54:10.8061317+08:00` 观测5秒，窗口响应、正常关闭、ExitCode 0。来源 schema 未变。以上为最终一轮日志；前一轮77项/50.6秒/20:50 smoke 已被覆盖，不累计。
- 边界：未跑全量测试、native Flutter drive、可见截图验收或真实 NAS/移动盘拔插。Windows 原生递归监控通过；另一个在 Windows 强制 `perDirectory` 的用例只验证该策略，不代表 Linux 原生验收。macOS/Linux 仍待设备实机；macOS 持久目录授权缺口未变。NAS 原生通知可靠性取决于挂载/系统，周期扫描提供兜底。详细边界见[本地来源文档](LOCAL_SOURCES.zh-CN.md#自动监控与增量更新2026-10-27windows-自动化release-验证通过)。

## 2026-10-27 原版侧边栏左下状态卡部分迁移（Windows 验证通过）

- 此前 Flutter `DesktopShell` 将侧栏实现为单个 `ListView`，因此没有迁移原 MediaLib `ContentView.swift` 的 `SidebarStatusCenterCard`；这不是条件隐藏。本轮新增固定在侧栏底部的 `SidebarStatusCard`，菜单改为独立 `Expanded ListView`，状态卡不会随菜单滚动。
- 按原版迁移 14 radius、58 minHeight、32 圆形渐变状态图标、标题/副标题、25px 右侧箭头、单层阴影和底部进度条。卡片只读取现有 `sidebarSourcesProvider`、`observedReachabilityProvider`、`homeRuntimeTasksProvider`、`homeRuntimeHealthProvider`，不因显示卡片额外探测磁盘或服务器。
- 当前行为为：活动任务优先；否则展示离线来源/健康异常；30 分钟内最近任务与媒体源摘要按 60 秒轮换。媒体源/离线状态点击进入 `/sources`，任务/健康状态进入 `/health`。截图中的“6 个媒体源 / 全部在线 · 刚刚”由测试覆盖。
- 验证分组：`app_test` 17/17；来源/侧栏/健康/首页交叉回归 70/70；`flutter analyze` clean。Windows Release 47.4 秒；隐藏 smoke 于 `2026-10-27T15:00:33+08:00` 窗口响应正常、正常关闭、ExitCode 0。
- 这是第一批的部分迁移状态，不代表完整 `SidebarStatusCenterCard` 已迁完。第二批已接入继续观看和真实缓存摘要，见下节；仍未迁移音乐迷你播放控制、应用更新/检查更新、保险库快捷锁定和赞赏提示。

## 2026-10-27 侧边栏状态卡 P0 第二批（部分迁移；Windows 验证通过）

- 继续观看接入 `homeCollectionProvider(HomeCollection.continueWatching)` 的首项，并调用 `homeVideoAction(..., 'play')`，沿用真实续播、远程系列以及内置/外部播放器选择语义。
- 新增被动 `observedVideoCacheStorageProvider`。Emby `embyCacheStorageProvider` 与 `VideoCacheSettings` 读取真实统计后才写入观察快照；侧栏只消费快照，不因展示卡片额外扫描磁盘或探测服务器。缓存摘要显示条目数及格式化 ByteCount，点击进入 `/settings`。
- 活动任务转为“已完成”时，状态卡打断当前显示并提示“刚刚完成”6 秒；一般状态的主轮换仍为60秒。补齐自绘 server、playRectangle、downloadCircle、checkCircle 图标，避免以 Material/SF 近似图标替代原版符号。
- 验证：sidebar/app 专项20/20；首页+缓存+侧栏+健康联合117/117；`flutter analyze` clean、`git diff --check` clean。Windows Release 38.9秒；hidden smoke 于 `2026-10-27T15:43:33+08:00` 窗口响应正常、正常关闭、ExitCode 0。
- 状态卡仍属部分迁移。音乐迷你控制、应用更新/检查更新、保险库快捷锁定、赞赏提示、缺失文件/重复项专属卡，以及失败任务重试/活动任务取消等原版专属动作仍未迁移；未发现当前 update/vault provider、model 或 action 时不伪造入口。

## 2026-10-27 P0 本地媒体卡视觉一致性修正（Windows 验证通过）

- 对照原 MediaLib `PosterGridView.swift` / `HomeVividTokens`，将 ReelNest `LocalMediaCard` 悬浮阴影从 alpha .24、y=10 修正为 alpha .18、blur=22、y=8；评分胶囊恢复黑色 alpha .42，并移除多余白色描边。
- 新增 `apps/client/test/media_card_visual_parity_test.dart`，通过 mouse pointer 验证静止无阴影、悬浮态使用原版 token、评分胶囊没有描边。该专项 1/1 通过（`apps/client/build/p0-media-card-visual.log`）；核心 UI 回归 35/35（`p0-core-ui-regression.log`）；Jellyfin/Plex 前端回归 4/4（`p0-remote-frontend-regression.log`）。分组单独记录，不累计成全量测试结果。
- 全项目 `flutter analyze` clean（`p0-analyze.log`）；Windows Release 40.9 秒成功（`p0-release.log`）。五秒 smoke `apps/client/build/smoke/release-startup.json` 于 `2026-10-27T10:38:12.4366226+08:00` 通过：`ObservationSeconds=5`、`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。人工复核 Release 中首页、侧边栏、媒体库、缺图占位、评分与筛选正常；确认缺图占位内标题及卡片底部标题均为原版设计，保留双处标题。测试窗口已退出。
- 本轮未运行全量 Flutter 测试；此处记录 Windows Release 人工核对，不推定 macOS/Linux 或其他数据规模下验收完成。

## 2026-10-27 原版视觉纠偏第一批（Windows 验证通过）

- 新增可复用 `PointerInspectTilt`，按原 Swift `PointerInspectTiltModifier` 迁移指针坐标归一化、最大约 ±2.6° 的透视倾斜、方向高光与指针阴影；reduce motion 启用时关闭倾斜效果。
- 媒体海报接入指针倾斜，同时保留既有 hover scale 和 shadow。详情 hero 移除 Flutter 额外增加的整块卡片背景、边框、阴影和 padding，恢复原版直接 `HStack` 与窄屏布局结构；详情海报恢复 radius 12、白色 alpha .34/.85 边框和原版方向渐变，并接入 tilt。
- 收藏/书签标题动作从组合胶囊恢复为间距 8 的独立按钮，贴合原版分隔方式。
- 定向测试 16/16；跨来源 Emby/source/Jellyfin/Plex/TMDB 回归 47/47；`flutter analyze --no-pub` clean。Windows Release 41.0 秒成功；隐藏 smoke 于 `2026-10-27T11:04:50+08:00` 通过，窗口响应、正常关闭、exit 0。
- 这只是第一批纠偏，不代表全局像素一致。该批之后发现的媒体卡主悬浮阴影绘制层级已在下方 P0 修正；SF Symbols 与自定义图标逐项映射、来源/设置/首页等页面逐页尺寸/颜色/动效，以及 macOS/Linux 实机视觉仍待。

## 2026-10-27 P0 媒体网格悬浮阴影绘制层级修正

- Flutter `SliverGrid` 按索引绘制；普通 `Transform` 配合 `clip: Clip.none` 仍会让先绘制的海报阴影被后绘制的兄弟项覆盖。本轮新增 `HoverLiftShadow`：通过 `CompositedTransformTarget` / `Follower` 与 `OverlayPortal`，在最近 Overlay 绘制 alpha .18、blur 22、y=8 的主悬浮阴影，对应原 Swift `PosterGridView` 的 active zIndex 效果。
- 真实 `LocalMediaCard` 继续负责点击、焦点、`PointerInspectTilt` 和 scale 1.018；Overlay 只绘制阴影，并使用 `IgnorePointer` / `ExcludeSemantics`，不复制或截获交互。退出时淡出 180ms 后移除；reduce motion 下时长为零且不放大。
- 媒体卡视觉专项最终2/2，覆盖进入、阴影 token、移出清除与 reduce motion。Emby 导航/详情、source lifecycle、Jellyfin/Plex/TMDB 跨来源回归最终63/63。第一次63项组合因新退出断言少 pump 一帧而失败；修正测试时序后，专项2/2与相同组合63/63最终通过。首次失败保留为过程记录，不计作通过。
- 最终 `flutter analyze` clean、`git diff --check` clean；Windows Release 39.7秒，hidden smoke 于 `2026-10-27T16:04:24+08:00` 窗口响应正常、正常关闭、ExitCode 0。
- 此修正只解决媒体卡主悬浮阴影的绘制层级，不等于工具栏/图标映射或全页面像素审计完成；来源、设置、首页的逐页核对与 macOS/Linux 实机视觉仍待。

## 2026-10-27 媒体库主界面 P0 页头对齐原版（Windows 验证通过）

- 原版只读对照 `E:/workspace/829304/MediaLib/Sources/MediaLib/Views/LibraryView.swift`、`AppColors.swift`、`VividIconLibrary.swift`、`DesignSystemTokens.swift`。新增共享 `apps/client/lib/ui/widgets/video_library_page_header.dart`：`PageHeader` 调整为无大卡片的 68pt 标题簇、62pt 图标槽、8pt 间距、30px 黑体标题；右侧动作底对齐。彩色 TV 标题图标按原版 `tvObj` 的 48 网格几何与官方配色翻译。
- `emby_video_library_page.dart` 删除非原版“管理媒体源”页头按钮与外层大卡片；搜索宽度由 280 收至 226；搜索/扫描/选择恢复现有原版线性图标。窄宽度时动作保持单一横向轨道，不任意 Wrap。副标题恢复为“浏览、筛选和管理当前内容 · N 项”，删除正文重复的“共 N 项”。
- 筛选条双层结构保留：原版 `AppAdaptiveControlBar` 本身就是外层静态表面与内层 segmented shell，本轮未误删。搜索、筛选、排序、同步、选择、服务器行为及持久化语义均未改变；适用于共享 Emby/Jellyfin/Plex 视频库页面。
- 验证分组：Emby 导航/详情、source lifecycle、Jellyfin/Plex/TMDB 跨来源四文件63 passed；`media_card_visual_parity` + `sidebar_status_card` + `app_test` 22 passed。相关 Dart 文件最终 format 0 changed，`flutter analyze` 无问题。Windows Release 41.0 秒成功；隐藏 smoke 于 `2026-10-27T20:12:08.4686688+08:00` 的 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。
- 未运行全量 Flutter 测试；未验真实 Emby/Jellyfin/Plex 可见 UI、实体鼠标/键盘、高 DPI 或 macOS/Linux 实机精确视觉。本次只是媒体库主界面页头 P0 对齐，不代表全局 UI 已与原版一致。

## 2026-10-27 Plex 重新认证账号归属修正

- 已复现并修复同服务器换账号 Token 会继承旧来源的问题。用户允许官方账号校验：服务器 ID 与 Plex 官方账号 ID 分开保存；同账号可更新 Token，换账号拒绝沿用原来源。仅服务器可用的 Token 按凭据指纹隔离，更换后须另建来源；账号接口异常保留原凭据与数据。
- 定向 67/67 通过（Plex 后端30、Emby连接18、Jellyfin后端17、Plex UI 2）。Windows Profile Native 39.1秒、业务及 tearDown 通过；Release 40.6秒、五秒 smoke 于 10:12:50 +08 正常响应并关闭、exit 0；analyze clean、427 Dart文件 format 0 changed、diff-check clean。本批未跑全量 Flutter 测试。此前 Plex 24 项里的 Token 隔离只覆盖内存缓存，不作为该问题的修复证据；未做真实 Plex 官方账号/服务器、macOS/Linux 原生、人工视觉或辅助功能验收。详细规则与证据见[Plex 修正](PLEX_PLAN.zh-CN.md#2026-10-27-重新认证的账号归属修正)。

## 2026-10-27 Plex 基础视频来源闭环（已实现；Windows 验证通过）

- 本阶段已接入 Plex 基础视频来源：server + Token 认证/会话恢复、媒体库选择、独立来源与侧栏、分页/搜索/详情、基础 direct 播放/音轨字幕/续播切集，以及进度/已看回写。
- Plex 必须走独立 XML 与 `X-Plex-*` client/protocol；保持 `kind=plex`、`plex://host/sourceId`、Plex credential kind。共用数据层、播放器或历史 `Emby*` 类名不表示 Plex 走 Emby API。
- 原版 Plex 无服务端收藏接口，收藏仅保存在 ReelNest 本地且同步不得覆盖；高转码/质量切换与 Plex 音乐留在后续范围。照片继续排除。数据库保持当前 `schemaVersion=1`，无新表或迁移。
- 原版个人 `userRating` 按 `userRating/2` 映射为可选的 0–5 初始评分，不能覆盖已有本地评分；Plex 专属能力为 `supportsQualitySelection=false`。新增评分字段仅进入 token-free JSON，不变更 SQL schema。
- 使用 strict loopback fixture，不使用真实 Token。最终分项为 Plex 专属后端24/24、共享后端255/255、同步/UI 63项（既有61+Plex UI 2）；前端2/2、Windows Native最终业务用例、analyze、427 Dart文件format、Windows Release与五秒smoke均通过。组合日志276/276与UI85/85含重叠，不重复累计；此前 `plex-shared-regression.log` 的254+1 stale test失败不是最终证据。本批未跑全量Flutter测试。真实 Plex、macOS/Linux、人工精确视觉及辅助功能验收待后续。详细分组见[Plex 基础连接器计划](PLEX_PLAN.zh-CN.md)。

## 2026-10-26 Jellyfin 基础视频来源闭环（已实现；Windows Release/smoke 通过）

- Jellyfin 基础视频来源闭环已实现：登录、凭据/会话恢复、选库、独立侧栏、分页浏览/搜索/详情、视频播放、音轨字幕、续播、切集与播放状态上报；共享定向回归和 Windows Release/smoke 已通过。真实服务器与平台/视觉验收边界见下文及专项计划。
- 原版 `connectJellyfinServer` 委托共用 `connectRemoteMediaServer(provider: .jellyfin)` 和 `EmbyService`，但保留独立 provider、`kind=jellyfin`、`jellyfin://source`、凭据身份与稳定 ID 前缀。ReelNest 扩展 `kind.isEmbyCompatible` 公共协议链路，不复制整套 Emby 实现；错误文案对 provider 中性，UI 显示 Jellyfin。
- 协议差异经官方认证源码和稳定版 OpenAPI 12.3.0 核对；数据库沿用当前初始 schema，`schemaVersion=1`，无开发中间版本迁移。共享实现保留独立 kind/provider/credential/`jellyfin://source`；完整边界见[Jellyfin 基础连接器计划](JELLYFIN_PLAN.zh-CN.md)。
- 2026-10-26 最终交付：共享协议回归 255/255（含 Jellyfin 17 项）、同步/界面四文件组 61/61、Emby 基线 37/37、独立 UI 2/2 均通过，各组不累加；此前中断的 43 项与失败日志不作为最终通过证据。全项目 analyze clean、421 个 Dart 文件 format 0 changed、diff-check 通过；本批未运行全量 Flutter 测试。Windows Native Profile 39.0 秒构建及真实 mpv Range 流、seek、服务器字幕、stop report 业务用例通过（1 case，harness 含 teardown 共2项，exit 0）。Windows Release 44.1 秒成功；标准 EXE 为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，AOT `data/app.so` 为 2026-10-26 21:25:55 +08、12,977,032 bytes，已核验含 Jellyfin brand mark、UserViews 与 UserFavoriteItems。五秒 smoke `apps/client/build/smoke/release-startup.json` 于 21:27:44 +08 响应正常、正常关闭、ExitCode 0。真实 Jellyfin 服务、macOS/Linux 原生与人工精确视觉验收仍待；测试输入模拟不代表人类键盘/IME，AXTree 告警不代表辅助功能通过。基础共享 cache、user flag、quality 路径已有接线，内部 Emby 类名不表示未实现；本轮不宣称全部高级能力完成，详见[验收表](JELLYFIN_PLAN.zh-CN.md#当前分工与验证记录)。

## 2026-10-26 TMDB 本地剧集手动匹配（实现与 Windows 验证完成；跨平台验收待）

- 本地剧集 TMDB 手动匹配的后端定向 102/102、前端 12/12、Windows Profile 原生、Release/smoke 均通过；analyze clean，417 个 Dart 文件 format 0 changed。本批没有运行全量测试，最终证据与分组计数见[本地剧集 TMDB 计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。
- `TmdbVideoService` 与共享 movie/tv provider 使用 `TmdbCandidate.kind` 区分类型；`local_series_metadata` 和 `local_episode_metadata` 纳入 schemaVersion 1。按既有有效季集号获取季详情（最多并发2、不逐集请求），只更新已有集 title/overview/year，保留本地身份、季集号、路径、图片与播放记录；无有效编号提示未匹配。匹配期间集合/编号变化拒绝整事务；重扫资料保护/失效关联清理和部分季失败保留按专项计划执行。
- 本轮不含批量/NFO/在线字幕/Emby 刮削。真实 TMDB 公服、macOS/Linux 原生和人工精确视觉验收仍待；原版 Swift 没有 season endpoint，本轮季详情请求属于获批的新行为。完整范围、原版基线和验收边界见[本地剧集 TMDB 计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。

## 2026-10-26 TMDB 本地电影元数据第一批（实现与 Windows 交付验证完成）

- 用户已批准本地电影的手动元数据闭环：搜索 TMDB、用户确认候选、本地保存，并在详情展示海报/简介/演员等。本轮不含电视剧/动漫、批量或自动匹配、NFO 写回、音乐与照片。
- 配置按原版支持 TMDB API Key 或 Read Access Token，语言默认为 `zh-CN`；Emby 继续使用服务器资料，TMDB 不作为 Emby 视频交付的前置条件。
- 最终 TMDB 定向合并复跑 `tmdb-final-targeted.log`：client16 + service14 + UI9，共39/39通过（18秒，exit 0），含新增 series 拒绝用例。全量 `tmdb-full-final.log` 为 1034 passed / 2 conditional skip / 1 native business test unfinished，exit 1，不能记为通过；Windows Profile 原生用例与 marker skip native 独立复跑分别通过，分组计数不相加。Windows Delivery Release 构建 56.0 秒成功；app.so 为 2026-10-26 09:13:45 +08、12,911,496 bytes；五秒 smoke 正常关闭，ExitCode 0。之后缓存关闭取消专项46项通过，另一个 Windows Release 构建46.5秒、smoke于13:51:47 +08:00正常关闭；该次后台收尾199ms、数据库关闭1ms，未复现之前约4.9秒任务状态，不视为所有负载的时延保证。`dart analyze lib/test/integration_test` 无问题，413 个 Dart 文件 format 0 changed、diff-check 通过。真实 TMDB 公服凭据未使用；macOS/Linux 原生与人工精确视觉验收待。详见[专项计划](TMDB_MOVIE_METADATA_PLAN.zh-CN.md)和[缓存关闭取消记录](CACHE_SHUTDOWN_2026-10-26.zh-CN.md)。

## 2026-10-24 本地文件/URL 临时视频播放与拖入（已实现，Windows 自动化/Release/smoke 通过）

- 本批入口为本地视频文件选择器、网络串流输入及主桌面内容区/播放器窗口两个本地视频拖放目标；已入库视频复用身份/续播，未知本地视频与九种白名单 scheme URL 采用临时单项播放。首页文本模块重排行为保持原状。
- 当前代码使用稳定 SHA-256 64 字符临时身份：文件基于 `file` + 规范化路径，网络流基于 `stream` + trim 后 URL；跨窗口 JSON 校验重算 ID。原始路径/URL/令牌不持久化。音轨/字幕/倍速使用原版稳定 `item.id` 偏好仓库持久化；未知媒体因无 marker 外键目标，其临时 marker 只驻留内存并在关闭时清理。还包括 `relative_id` 精确匹配、临时会话隔离、macOS scope/lease 与 entitlement 接线，以及锁定 `desktop_drop 0.8.0`；适配 SDK 3.47.6，未升级 SDK。
- 修正后定向回归 backend 10 + UI 7 + shortcut 2，共 **19 项/2 秒通过**，日志 `apps/client/build/transient-stable-preferences-tests.log`；format 385 个 Dart 文件 0 changed、diff-check 通过。
- Windows 原生 Profile 已通过，4 秒 exit 0，验证稳定 64 字符身份跨 engine 传递；日志 `apps/client/build/transient-native.log`。稳定偏好版本完整 Flutter 回归 968 passed / 1 optional benchmark skipped（5 分 14 秒，exit 0）。随后补入 NetworkStreamPromptSheet 闲置状态 Escape 取消、opening 状态不可取消及 Enter 提交，4 个 UI 文件 21 项/4 秒通过，日志 `apps/client/build/transient-final-ui-tests.log`；19 项及 21 项专项均包含 `transient_playback_shortcut_test.dart`，Windows `Ctrl+Shift+O` 与 macOS `Meta+Shift+O` 合成键盘自动化通过，不把补充用例并入全量数字。最终 `dart analyze lib test integration_test` clean、386 个 Dart 文件 format 0 changed、diff-check 通过。Windows Release 67.2 秒成功，日志 `apps/client/build/transient-release-final.log`；`app.so` 为 2026-10-24T21:29:03.7480828+08:00、12,665,736 bytes。五秒 smoke `2026-10-24T21:30:40.8223378+08:00` 通过，隐藏窗口响应、正常关闭、退出码 0。macOS/Linux 原生、实体拖放/文件选择器、真实服务器非 HTTP 协议、实体键盘及精确 UI 视觉仍待实机验收。
- 本批不含音乐、媒体库导入、批量播放列表、系统文件关联或外部播放器。OS 冷启动 open-files/CLI 文件事件是原版既有能力，但本批没有实现/验收，作为后续缺口单列；详见[本地文件与网络 URL 临时播放计划](PLAYER_TEMPORARY_PLAYBACK_PLAN.zh-CN.md)。

## 2026-10-24 系统外部播放器（验证收尾中）

- 用户已批准迁移视频系统外部播放器；本阶段仅视频，不包括音乐。最终文件专项 23 项通过（后端 15、前端 7、Windows 原生 helper 1）；Dart 全量 991 passed / 2 条件跳过，`dart analyze` 无问题，397 个 Dart 文件 format 0 changes。全量包含后端 15 项，但前端损坏恢复补丁在全量文件载入后加入，因此两组数字分别记录，不累计相加。两个跳过项为未指定 native helper 路径的条件用例和可选 benchmark。Windows Profile `integration_test/external_playback_test.dart` 已通过：33.4 秒构建、约 4 秒运行，1 个业务用例通过；真实 secondary engine 经 IPC 调用主 service/helper，验证中文及 `&` 本地路径、HTTP(S) 启动和立即失败回传，相关数据库表均为 0。helper 不联网、不播放视频，不代表真实 Emby/VLC/系统默认关联验收。Windows Release 49.1 秒成功，`Release/data/app.so` 时间为 2026-10-25 14:30:05 +08；五秒 smoke 于 2026-10-25T14:30:30.3321959+08:00 通过，窗口响应正常、正常关闭、ExitCode 0。macOS/Linux 未实机验证，真实 Emby/VLC/系统默认关联与崩溃后 lease 回收仍待验。
- 按原版恢复视频默认播放方式 `builtIn` / `external`、系统默认或自选应用路径，以及播放器右键/显式入口和 `VideoPlayerShortcutAction.openExternal`。后端实现由用户负责，前端按原版设置和入口实现。
- 资源范围为本地文件、挂载/网络卷文件、ReelNest 缓存文件及 Emby HTTP(S) 媒体 URL。外部服务只接受 HTTP(S)，不沿用内置播放器九种 scheme。
- 不注册 Windows 文件关联/协议、不写注册表、不做播放进度回读；不探测外部播放器退出或播放完成。主进程服务持有媒体缓存租约及文件访问 scope、定时续租；启动失败释放资源。启动 ACK 超时按结果未知处理并保留资源至 ReelNest 退出，避免外部播放器已启动时提前释放。真实 Windows helper 仅验证 argv 传递和立即失败反馈，不代表真实播放器或系统默认关联验收。
- macOS/Linux 目前仅有源码接入，尚未实机验证。各项证据与限制见[系统外部播放器专项计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。

## 2026-10-24 时间轴预览图无图问题（已修复，Windows 自动化与 Release/smoke 通过）

- 用户反馈正式版时间轴预览图无图。根因已确认并修复代码；scrubber、完整播放器 Windows Profile 原生 UI 和真实资源联合 probe 均通过。7 个定向测试文件共 **31 项全部通过（8 秒）**；变更的 2 个文件 `dart analyze` clean、format 0 changed、diff-check 通过。Windows Release 与 smoke 通过。真实 Emby 的完整连接全链路、Release 人工操作、人工精确视觉和 macOS/Linux 尚未验收。
- 根因：scrubber 原先只在预览请求完成后记录当前 bucket；远程取帧约需 2.2 秒，同一 bucket 内约 110 ms 的鼠标微动会不断取消并重启请求，导致预览无法及时完成。
- 修复：新增 `_pendingBucket`，同 bucket 内复用计时器/在途请求，只有切换 bucket 才取消；离开 scrubber 与拖出时统一清理 pending 状态，允许后续重试。该批针对预览请求生命周期，不改变取帧位置或原版黑场过滤语义。
- 专项验证：7 个定向测试文件合计 **31 项全部通过（8 秒）**，覆盖 scrubber（5 项）、完整页面 UI、native decoder、proxy/queue/cache/session、脱敏诊断及生命周期取消日志限量。之前真实已登录 Emby 资源单独取帧 probe 中，MP4 HTTP Range 返回 206；300 秒位置成功生成 101,801 字节 PNG（2,183 ms）；20 秒位置返回 `frame_dark` 并按原版语义过滤（原版也会过滤黑场）。本轮另对该视频的 809 秒、806 秒位置分别直接取帧成功，生成 101,339 字节/99,161 字节 PNG，用时 2,651 ms/1,928 ms。凭据仅供内存 probe 使用，不回写。本轮变更的 2 个文件 `dart analyze` clean、format 0 changed、diff-check 通过。本批未重复运行 941 项全量测试；此前全量结果不作为本批改动后的全量验收证据。
- 诊断：`preview_unavailable` 使用脱敏固定字段 `code`、`durationMs`、`remote`、`cached`；首张成功预览记录 `preview_generated`。同媒体同 code 最多记录一次、code 种类不超过 16；不记录 URL、token、路径或异常原文。新增有限生命周期日志 `preview_started` / `preview_cancelled` / `preview_finished`，每媒体最多记录前 8 次，用于观测正常取消路径；诊断仅增强可观测性，不作为功能验收证据。
- 完整页面本地媒体原生 UI：`flutter drive --profile -d windows --target=integration_test/timeline_preview_test.dart` exit 0。以本地生成视频、真实 `VideoPlayerPage` 和 `MediaKitVideoEngine` 验证实际 hover/鼠标微动后取得 312×176 native PNG，`RenderImage` 可解码；预览浮层位于 slider 上方、未被裁切且绘制像素 >100，主视频保持暂停且播放进度不变。integration_test plugin 未检测到的提示为 Windows 既有环境提示；AXTree 有 engine warning，但断言通过。
- 真实资源联合 probe：`build/preview_live_ui_test.dart --profile` exit 0。完整 `VideoPlayerPage` 与 native `MediaKitVideoEngine` 播放已保存 Emby URL，同时由预览路径读取同一真实 URL；1.5 秒鼠标微动后成功取得 312×176 PNG 并通过实际绘制像素断言，主播放保持 playing，6 秒内完成。为避免改写用户状态，session/repository 使用内存 fixture，engine.open 重定向至真实 URL，preview generator 显式读取该 URL；Release 便携 DB 只读，凭据仅在内存中，不登录、不刷新、不写用户 DB/播放记录，也不上报 Emby。因此这证明真实资源的 native 播放/预览联合路径可工作，但不是 Release 人工操作或正式 Emby 连接全链路验收。integration_test plugin 提示和 AXTree engine warning 均未影响断言。
- Windows 发布验证：Release 构建 **40.9 秒成功**，`data/app.so` 时间为 **2026-10-24 10:46:51.1594550 +08:00**，日志 `apps/client/build/preview-followup-release.log`。`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 **2026-10-24 10:53:16.6617996 +08:00** 通过，窗口响应正常、正常关闭、退出码 0。
- 验收边界：Windows 定向自动化、完整本地媒体 Profile UI 与受控真实资源联合 probe 通过；真实 Emby 完整连接全链路、Release 人工操作、人工精确视觉、macOS/Linux 原生验收仍待。用户尚未验证指针停留 10 秒的场景，因此没有确认新的 10 秒预览挂起问题；当前证据显示约 2 秒首次加载符合实测。不做推测性 UI 改动或扩展为加载提示功能。原版 `VideoFramePreviewGenerator.swift` 黑场过滤及 FFmpeg 前后 ±1.5 秒重试规则继续作为行为参考。

## 2026-10-22 播放器截图阶段（已实现，Windows 自动化验证通过）

- 范围：沿用原版截图模式 `subtitles`（带字幕，默认）、`video`（纯视频）、`window`（窗口所见）；保存 PNG，文件名包含影片标题与时间，并提示保存成功或失败。本地与 Emby 视频共用；截图不得暂停/跳转播放或修改播放设置。
- 来源依据：只读参考 `MediaLib/Sources/MediaLib/Views/PlayerView.swift` 的截图入口/模式选择与反馈、`MediaLib/Sources/MediaLib/App/MpvPlayerController.swift` 的捕获/文件保存，以及 `MediaLib/Sources/MediaLibCore/Models/AppSettings.swift` 的模式枚举及默认值。原版目录为系统 Pictures 下的 `MediaLIB 截图`，不直接沿用该路径或旧品牌。
- 交互与偏好：播放画面右键“保存当前画面”或按无修饰 `S`（沿用原版默认快捷键）；播放器设置“截图内容”可选带字幕（默认）、纯视频、窗口所见。领域枚举 `VideoScreenshotMode` 以 `subtitles` / `video` / `window` 表示，全局偏好 `global.videoScreenshotMode` 存储 enum `name`，默认 `subtitles`。`Session` 提供 `screenshotMode`、`canCaptureFrame`、`capturingFrame`、`setScreenshotMode`、`captureCurrentFrame`；成功返回 PNG 绝对路径，失败提供 `VideoScreenshotFailure` 安全展示消息。成功反馈只显示文件名；未知错误使用固定安全提示。
- 图像语义：`subtitles` 与 `video` 分别采用当前 mpv `subtitles`/`video` 截图模式；`window` 仅捕获视频渲染区域（含字幕与黑边，不含 Flutter 控制栏/HUD），对应原版 `renderView` 兜底语义。不得改变字幕选择/可见性、播放状态或 seek，不另开解码器。GPU、软件渲染均须验证三种模式；不可静默退化。
- 保存路径：Windows 为 `resolvedExecutable.parent/userdata/screenshots/`，逐层校验真实路径且不得回退到外部目录；macOS 为用户 Pictures 下 `ReelNest 截图/`；Linux 优先 `XDG_PICTURES_DIR/ReelNest 截图/`，未设置时回落到 `HOME/Pictures/ReelNest 截图/`。PNG 文件名包含影片标题与时间；重名不覆盖、原子发布、失败清理未完成文件并限制 PNG 尺寸。macOS/Linux 路径实现和单测已接入，但未做原生实机验收；不宣称移动端支持。
- 自动化验证：store/session 新增 11 项、UI 两文件 31 项回归通过。全量 `flutter test --no-pub --reporter expanded` 显式启用 `REELNEST_MPV_PATH` 执行 native：**859 passed / 1 skipped**，45 秒；唯一跳过为可选排序性能基准。`dart analyze lib test integration_test` 无问题；348 个 Dart 文件格式检查 0 改动；`git diff --check` clean。
- Windows Profile：最终 `integration_test/video_screenshot_test.dart` 中 GPU/SW 两种 renderer 的两项实际功能用例通过（runner 汇总 3 项含 tearDown，13 秒），覆盖三模式、字幕有/无、PNG 像素/尺寸、黑边且不含 HUD、图像变换、播放/暂停状态不变、每种渲染路径 8 次旋转/resize 截图循环，以及 loopback Range HTTP 播放截图不增加请求。最终 native 运行已包含 raw 格式 `bgr0`/`bgra` 校验。既有 `video_viewport_test.dart` 的 GPU/SW 两项实际功能用例通过（汇总 3 项，2 秒）。
- Windows texture callback 修复：截图调试发现既有 `media_kit_video` resize 期间 texture callback 注册竞态；可变 `texture_id_` 重注册时被 `map.at` 访问，Profile 本机曾两次崩溃。minidump 与 SDK PDB 定位至 `flutter::ExternalTextureD3d::PopulateTexture` / `std::terminate`。项目自有 `windows/media_kit_viewport.cmake` 生成源码已修复：callback 持有独立注册 ID，旧 ID 撤回与新 descriptor/ID 发布共用 mutex，旧 callback/缺失记录返回 null；GPU/SW 均覆盖，最终旋转/resize 循环验证通过。该证据不代表所有历史崩溃均已定位；排查工具与 dump 摘要只在 ignored `apps/client/build/screenshot-diagnostics`，不进入发行内容，Pub 缓存未改。
- Windows 发布验证：Release 构建 **40.5 秒成功**，EXE 为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。2026-10-22 14:33:44.0518851 +08:00 五秒 smoke：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。
- 验收边界：本地和 Emby 代码路径共用，但未使用真实用户 Emby 服务器验收；macOS/Linux 尚无原生实机验收；原版 UI 视觉逐项对照仍待完成。以上不改变既有 IME/chrome 历史记录。

## 2026-10-22 视频播放器音频均衡器（已实现，Windows 自动化验证通过；跨平台/真实设备验收待）

用户已授权将视频播放器 5 段均衡器作为下一阶段迁移，非音乐模块功能。已先阅读原版 `VideoAudioFilterPolicy.swift`、`AppSettings.swift` 中 `MusicEqualizerPreset`、`PlayerView.swift` 均衡器设置和 `VideoAudioFilterPolicyTests.swift`。保持原版 8 个预设、5 个频点及增益值，算法使用 FFmpeg `lavfi` `firequalizer`，不得换成 biquad；默认 disabled + flat，disabled/flat 不挂载本功能拥有的音频滤镜，关闭时保留预设。详细状态/引擎契约与验收清单见[视频均衡器计划](PLAYER_VIDEO_EQUALIZER_PLAN.zh-CN.md)。

持久化使用单一 `global.videoEqualizerSettings` JSON key，落在现有 `player_preferences`，无 schema 变化；当前播放器批量偏好 key 数从 26 增至 27，历史快照不回溯修改。状态更新须串行合并最新值，应用/保存失败回滚并提示；初始化应用失败非致命并提示。引擎只管理 `@reelnest-equalizer` owned lavfi，保留其他 `af`/`vf`、变调保护、音量/增强、音轨、输出设备和同步，不主动 seek、unpause 或 reopen。

后端 `video_equalizer_test.dart` 13 项 + `playback_read_performance_test.dart` 4 项，共 17 项通过；设置偏好完整 getter 的 27 次 SQL 已合并为 1 次快照读取。UI `player_basic_settings_test.dart` 与 `player_marker_skip_ui_test.dart` 共 14 项通过。新增均衡器行后的首次 UI 全量出现 18 px 溢出，原因是测试夹具缺少实际设置页滚动容器；前端工程师按产品结构补入 `Scrollbar` + `SingleChildScrollView`，原断言保留。产品实际父容器已有滚动，无产品降级。

全量 `flutter test --no-pub --reporter expanded` 显式设置 `REELNEST_MPV_PATH`：**873 passed / 1 skipped**（45 秒；唯一跳过为可选 sort benchmark），包含 native PCM 1 项实测所有五频与 8 个预设。`dart analyze lib test integration_test` clean，353 个 Dart 文件 format 0 changed，`git diff --check` clean。native 用当前 pinned DLL `ao=pcm` 输出 48 kHz / 16-bit / mono 五频 WAV，以 flat 为基准测试 7 个非 flat 预设，实测误差均在原版增益 ±0.8 dB 内；不是属性读回，未更换运行时。

Windows Profile `integration_test/video_equalizer_test.dart` GPU/SW 各 1 项实际功能用例通过（runner 汇总 3 项含 tearDown；用例 4 秒，Profile 构建 24.2 秒）。覆盖本地与 loopback Range HTTP 视频、8 预设轮换、暂停时 `time-pos` ±0.02 秒、保留 aid/sid/secondary/subvisibility、speed、pitch correction、volume/boost、audio delay/device、hwdec、vf 和 foreign af；播放时调整均衡器/倍速/变调仍无 error 且保持播放；已完全缓存 HTTP 片段切换设置不增加请求。Profile harness 首次因 mount 前设置 `ao` 等 controller 初始化值而挂起；将设置移至 mount 后解决，属于测试顺序调整，不是生产故障修复。

Windows Release 构建 **41.2 秒成功**；`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 **2026-10-22 14:57:45.2163649 +08:00** 通过，`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。

阶段状态：已实现，Windows 自动化验证通过；真实设备听感、真实用户 Emby、macOS/Linux 原生和原版 UI 视觉逐项验收仍待。完整证据及边界见[视频均衡器计划](PLAYER_VIDEO_EQUALIZER_PLAN.zh-CN.md)。

## 2026-10-22 首页搜索复用与 Emby 过期任务取消

首页搜索仓库新增有界 LRU，复用已解码搜索文档；通过 SQLite `total_changes()` / `data_version` 检测写入并失效，范围变化也会使对应缓存失效。Emby 过期搜索现在实际终止 worker isolate，而非仅丢弃 Future 结果。没有实现持久搜索 isolate；180 ms 输入防抖及过滤/排序规则不变。

91 项搜索相关测试通过；最后调整后台匹配阈值后，两个搜索测试文件 16 项复验通过，analyze clean，Windows Release 构建成功。2026-10-22 23:40（UTC+8）五秒 smoke 正常响应、正常关闭、退出码 0。未宣称真实大库可见 UI 或 macOS/Linux 性能已验收；详细范围、缓存上限及测试证据见[搜索性能优化记录](SEARCH_PERFORMANCE_2026-10-22.zh-CN.md)。

## 2026-10-22 首页按来源刷新与偏好快照复用

首页和侧栏更新按来源刷新；偏好更新通过复用不可变内容快照、索引和偏好覆盖避免遍历全部媒体/分集以重建覆盖层，并保留未知范围通知的全局刷新和原推荐行为。当前仍读取该来源全部偏好行；不能表述为只查询发生变化的单条偏好。

96 项相关回归与 130 项变更路径回归通过，两组有重叠，不相加为独立测试数。10,003 条媒体夹具使用列表访问计数，验证构建偏好覆盖层时未遍历基底媒体列表；该结果不代表后续筛选/渲染不访问列表，也不是整页耗时倍率。analyze clean，Windows Release 构建成功；2026-10-22 23:52（UTC+8）五秒 smoke 正常响应、正常关闭、退出码 0。真实大库交互、长期 CPU/内存及 macOS/Linux 原生性能仍待实机验收，详见[按来源刷新与偏好快照优化](SCOPED_REFRESH_PERFORMANCE_2026-10-22.zh-CN.md)。

## 2026-10-22 Windows 播放器窗口 chrome 拖拽与 IME 焦点修复

非迷你播放器窗口顶部 chrome 从距顶 17px、38px 高调整为从窗口 y=0 开始、高 54px；整个标题区和右侧额外 14px 区域可拖动，窗口按钮保持独立点击区域，修复顶部拖拽范围及命中不便。实现位于 `apps/client/lib/features/playback/presentation/video_player_page.dart`。

Flutter 3.47.6 / Windows 11 10.0.26200 下观察到的 CJK IME 失焦恢复问题与 [Flutter issue #190042](https://github.com/flutter/flutter/issues/190042) 所述情形相符。`ReelNestApp` 在 Windows 窗口 inactive、hidden 或 paused 时主动取消当前 `TextField` 焦点，断开旧 text client；窗口恢复后用户再次点击搜索框时，以当前输入法重新连接。该处理仅针对 Windows，不改变 macOS/Linux 行为，代码位于 `apps/client/lib/app/reelnest_app.dart`。此处记录症状与环境相符，不据此断言已证明 Flutter 上游问题的底层根因。

回归覆盖 `app_test` 的 inactive 时释放 TextField 焦点，以及 `playback_test` 的 chrome y=0/高 54px。`flutter analyze` clean；`app_test.dart`、`playback_test.dart`、`home_ui_test.dart` 合计 **61 passed**。Windows Release **43.7 秒成功**；2026-10-22 09:28:12 +08:00 五秒 hidden smoke 窗口响应、正常关闭、`ExitCode=0` 均通过。该批变更不涉及播放业务行为。

## 2026-10-21 Emby 媒体库排序性能优化

`filterVideoLibrary` 现在在单次排序中惰性缓存标题分段和数字解析结果，同一标题只解析一次；主排序值相同的条目按原规则以标题及 ID 决胜，标题主排序不重复比较。保留自然数字、大小写、前导零、超长数字、反序及 ID 决胜规则。缓存仅在本次查询内存活，不改变数据库或产品行为。

相关功能回归分两组 **64 + 19 = 83 项通过**；初次批量命令因写错离线订阅测试文件名而失败，正确的 `emby_offline_test.dart` 随后单独通过 19 项，不能把首次批量命令表述为全绿。排序基准前后版本各另运行 2 项通过。最终 analyze、Windows Release **47.5 秒**及五秒窗口响应/正常关闭 smoke 通过；产物为 Windows Release EXE，未制作发行包。受控基准不代表整页或真实服务器性能，详见[2026-10-21 性能检查](PERFORMANCE_REVIEW_2026-10-21.zh-CN.md)。

后续已完成首轮审查中的演员作品 N+1 与想看/评分触发整来源 Emby 快照重读两项优化：缓存未命中时批量读取作品/父项；成功的偏好事务按来源更新版本，Emby 使用内容基础快照加偏好覆盖。相关 80 项回归通过，全量 838 passed / 10 按配置跳过，analyze、Windows Release 和五秒 smoke 通过；边界见[增量读取记录](LIBRARY_INCREMENTAL_READS_2026-10-21.zh-CN.md)。短生命周期 isolate 的拼音缓存仍不能跨 isolate 复用，未实现持久搜索 isolate。真实大库可见 UI 和 macOS/Linux 原生性能仍待验收；首页轮播已有活动条件，本轮未改。

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

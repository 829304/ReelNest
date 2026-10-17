# 共用视频播放器实现盘点

最后更新：2026-10-17。播放诊断批次最终定向 native **1 项通过**、analyze、265 文件格式检查及差异检查通过；Windows Release 40.8 秒成功，01:12:55 +08:00 五秒 smoke 通过。全量 **701 passed / 4 skipped** 是最后三行兜底修正前的结果。真实 Emby 根因尚未确定，macOS/Linux 原生未验收。另：输入速率提示代码已冻结，backend 54 项、UI 27 项及隔离 native 2 项通过，全项目 analyze、269 文件格式和 diff 检查通过；本轮未重跑 701 项全量。Windows Release 39.6 秒和五秒 smoke 通过；真实 Emby、实体键鼠、macOS/Linux 原生和三端视觉验收仍待。见[专项记录](PLAYER_PRECISION_BACKEND.zh-CN.md#用户授权播放器输入速率提示代码冻结windows-验证完成三端验收待定2026-10-16)。

最新画面显示批次：后端 13 + UI 2 项定向通过；Windows Profile texture 的比例/裁切/镜像像素比较及旋转 getter/属性组合测试通过，但未单独做旋转像素图像对比。全量 Flutter **768 passed / 7 skipped**（52 秒）、stats texture 回归、七项显式 native DLL 专项、严格暂停 resize（`osd-dimensions=480x270`）是上一轮已通过的证据，本轮未重跑全量。CMake 下载重试逻辑变更后的增量 Windows Release 45.1 秒成功，2026-10-16 23:39:17 +08:00 五秒 smoke 正常响应并关闭。手工预置固定 archive 的新缓存独立验证通过（archive/DLL hash、提取和保留其他 DLL）；冷缓存网络下载因连接中断未获验证。2026-10-17 macOS/Linux 暂停 resize P2 最新 Dart backend 13 + UI 2 共 15/15、analyze 0、305 文件 format 0 改动、diff-check 通过；Windows Profile GPU/SW 两场景、Linux 补丁两种宏配置下 MSVC 编译生成源码及 test doubles 通过。Windows Release 41.0 秒成功，00:17:46 +08:00 五秒 smoke 正常响应、关闭且退出码 0。Mac Ruby/Pods/Swift、Linux GTK/EGL 原生构建、CI 和两端实机 resize 尚未验证，不能视为 macOS/Linux 原生验收完成。真实 Emby、macOS/Linux 其他原生验收和人工视觉验收仍待；发行前还需长期保存精确依赖 archive/源码/许可证材料并完成依赖通知清点。详见[画面显示 P2 记录](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md#p2-macoslinux-暂停时视口-resize-不主动重绘实现落地平台验收待完成2026-10-17)。

本文为当前状态总表；2026-10-09 的基础播放器记录和后续日期型批次只证明当时范围，不能覆盖本表。盘点依据原版 `PlayerView.swift`、`MpvPlayerController.swift`、`AppSettings.swift` 与 ReelNest 的 `features/playback`、`player` 实际代码；上述原文件在参考基线 `64f8ee2` 与原仓库当前 HEAD 之间没有变化。

## 结论与范围

本地与 Emby 视频共用的播放会话、播放器页面、续播、音轨/字幕、剧集连播和精确播放第一批已接通，并有 Windows 自动化及分层原生证据；完整原版播放器尚未迁移完毕，UI 也没有完成一比一验收。

2026-10-16 发现主窗口关闭卡顿的依赖死锁：`SourceRepository.close` 等待 change stream 关闭，而 paused listener 只有 provider container dispose 后才能取消；bootstrap 原先又在 `source.close` 返回后才 dispose container。已调整 stream 关闭和 app 清理顺序；主/子窗口关闭请求改为观察原生窗口实际消失，避免等待可能丢失的 IPC 回复，明确拒绝或超时仍保留播放器窗口、不强制销毁。关闭时并行取消后台 marker/offline/cache owner 并等待收尾，数据库最后关闭；单步异常记录并继续释放其他 owner。最终全量 **723 passed / 6 skipped**、analyze 零问题、281 个 Dart 文件格式 0 改动及 diff-check 通过；关闭回归定向 **24 项通过**。Windows 正式 `lib/main.dart` Release 构建 **40.2 秒成功**；2026-10-16 11:15:30.6878930 +08:00 单次 `PostMessage WM_CLOSE` smoke 正常退出，`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。日志 `playback-4368-1792120525622583.jsonl` 记录 main close 至 native close 请求 **234 ms**（后台任务收尾 225 ms、数据库关闭 8 ms）。这只证明本机此次启动/退出，不推导所有媒体库、活跃下载、多页面、有播放器或 macOS/Linux 场景均通过。

此前按基础播放、字幕/音轨、队列三个小批次推进，没有先提供完整剩余清单；部分旧文档仍把已完成的队列列为待办，造成进度不透明。下表统一状态。剩余项来自原版，不是新产品功能；今后拆分批次不应增加范围，确需调整时单独说明。

这里盘点的是共用**视频**播放器。本地路径解析与 Emby 鉴权、播放地址、转码、远程上报和离线缓存仍由对应来源模块负责，但进入播放会话后复用同一播放器状态、控制与 presentation，不能为 Emby 另建一套用户可见播放器。音乐播放器、媒体库扫描/元数据和 NAS 连接/挂载是其他模块；照片查看器已按用户 2026-10-12 的决定移出当前产品、计划与验收范围。

## 已接通的功能

“已接通”指当前功能代码存在且有对应自动化或专项证据；具体等级以验证章节为准，不表示真实 Emby、视觉或三桌面端均验收完成。

| 功能 | 当前状态 |
|---|---|
| 库内播放入口 | 电影详情、系列首集、单集双击；独立窗口及窗口复用 |
| mpv 播放 | 本地文件、移动硬盘及已挂载 NAS 的文件路径播放；有真实解码验证 |
| 本地/Emby 共用播放器 | 来源模块分别准备本地路径或远程播放资源；播放会话、控制页、字幕音轨、队列和精确控制复用同一实现 |
| 基本控制 | 播放/暂停、拖进度、左右键跳转、音量/静音、全屏、双击全屏、关闭 |
| 控制栏 Dock | 固定深色 Chrome 色板覆盖播放器 Dock、右键精度菜单、设置/选择面板及嵌套菜单，不随海报明暗变浅，且不影响普通页面；Dock 高 72 px，主播放键 34×34 px、辅助按钮 32×32 px。迷你悬浮窗仅保留 Dock 按钮和 `P` 快捷键，右键精度菜单重复入口已移除。最新 `playback_test.dart` 20/20、弹层相关 47/47、targeted analyze、Windows Release 34.5 秒及 11:03:30 smoke 通过；真实窗口及三桌面端可见 UI 验收待补 |
| 输入速率提示（用户授权新增） | HUD/UI 已冻结；backend 54、UI 27、隔离 native 2 项通过，analyze/269 文件格式/diff 检查通过。Windows Release 39.6 秒及五秒 smoke 通过；真实 Emby、实体键鼠、macOS/Linux 原生与三端视觉仍待。远程未知值 `-- KB/s`，本地/离线不显示；不得冒充网络速率 |
| 观看记录 | 周期/暂停/切换/播完/关闭保存；默认续播回退 5 秒，90% 已看且不因回退清除 |
| 安全切换/关闭 | 保存失败保留会话；重试或明确放弃；缺文件/离线/坏视频不提前释放旧解码器 |
| 本地字幕 | 内嵌/同目录/手动外挂、开关、第二字幕、字幕快慢、语言/关闭偏好、原生 libass 渲染 |
| 音轨与音量面板 | 音轨/语言记忆、输出设备、音量记忆、最高 200% 增强 |
| 剧集队列 | 当前集及后续列表、完整系列手动上一集/下一集、不循环、观看说明 |
| 播放结束 | 默认自动下一集；停在结尾/关闭窗口；记住选择；重复/过期 EOF 保护 |
| 精确播放与播放辅助 | 内嵌章节与手动章节/书签、标记跳转/删除、时间轴刻度、总时长/剩余时间切换、单片循环、A–B 循环、前后逐帧；右键精确播放菜单含播放信息入口 |
| 控制与信息辅助 | 控制栏锁定/解锁（播放、暂停均生效）及居中播放信息面板；缺失元数据明确显示未知 |
| 迷你悬浮窗与置顶 | `P` 与精确播放右键入口、保持比例和右下角定位、迷你播放控制、退出时恢复窗口状态及置顶偏好；播放设置可持久化“窗口置顶” |
| 时间轴预览图（P1-C） | 关闭/流畅优先/画面优先三档、悬停和拖动预览、松手后 seek、148×83 浮层及边缘钳制；独立 headless mpv、受限缓存/并发和远程 Range 安全边界已实现，自动化验证完成，最终验收待进行 |
| 基本快捷键 | 空格、左右/上下、M、F、Esc；B/Shift+B、逗号/句号、Home；弹层优先接收 Esc |
| 片头片尾检测与审核 | 已存内嵌章节生成候选、采用/忽略；首页/媒体库/详情右键发起单项或系列分析；任务中心进度、取消、重试及历史。只覆盖已载入且时长有效的视频，真实来源与三端原生验收待完成 |

## 历史：基础设置验证（Windows，2026-10-09）

2026-10-09 用户授权测试后，当前/默认倍速、本片或系列倍速记忆、变调保护、步长、续播记忆与回退、自动已看与主设置阈值、启动音量通过专项回归。Windows 防休眠通道可创建/释放系统与显示器请求；聚合释放规则通过测试，实际空闲超时仍待人工检查。macOS/Linux 原生防休眠已写代码，尚未在对应平台编译或运行。

当时全量 167 项单元/组件测试（新增 11 项）、Windows 3 项原生业务场景、静态分析及 122 文件格式检查通过。详见[基础播放设置](PLAYER_BASIC_SETTINGS.zh-CN.md)和[当日记录](TEST_REPORT_2026-10-09.zh-CN.md)。这是历史批次数字，不是当前全量测试数，也不代表完整播放器或一比一 UI 已完成。

## 已有基础，但没有完整迁移的部分

| 部分 | 已有 | 还缺 |
|---|---|---|
| 续播/已看 | 原默认规则、记录保存和基础设置已验证 | 三平台实机与 UI 对照 |
| 控制条/弹层 | 基本条、轨道/音量/队列/章节标记弹层、时间轴标记/剩余时间切换、控制栏锁定、播放信息面板与右键入口 | 原完整入口与右键菜单其余操作、截图/外部播放器等；矢量轮廓、字体/材质、箭头、悬停/提示/动效对照 |
| 播放器设置 | 设置弹层、更多设置、剩余时间和预览图开关、播放结束；基础行为行已验证 | 画面、音频/字幕等高级设置；当前不是完整设置页 |
| 字幕 | 本地选择/渲染、双字幕和快慢 | 在线搜索/下载，字体、粗体、颜色、描边/背景、大小/位置 |
| 窗口与平台 | 独立窗口、窗口关闭协调、全屏、控制栏锁定、迷你悬浮窗/置顶代码及 Windows 自动化 | 截图及截图内容选择；Windows 防休眠请求已验证；迷你窗 macOS/Linux 原生及三端可见窗口实机验收 |

## 原版剩余功能清单

以下按固定功能组列出，属于尚未完成的原版迁移范围。

| 功能组 | 剩余项目 |
|---|---|
| 时间轴与精确控制 | 手动边界与跳过、P1-C 预览、章节候选与审核、原版条目检测入口及系列批量任务已接入；最新批次最终验证见专项记录。已有控制仍需真实来源、三桌面端实机与视觉验收 |
| 窗口与辅助工具 | 启动宽度/比例及视频尺寸适配、截图及截图内容选择、右键菜单剩余操作；P1-C 自动化已通过，真实 Emby、人工可见窗口及 macOS/Linux 原生验收待完成；防休眠实机空闲超时仍待 |
| 字幕与音频高级项 | 字幕样式快速连续更新 P2 已修复；3 个定向测试文件 28 项、全量 753 passed / 6 skipped、analyze、296 文件格式检查均通过。Windows production Release 45.7 秒成功，五秒 smoke 正常响应并退出（16:57:14 +08:00）。ASS/位图、macOS/Linux、真实 Emby 和人工 UI/视觉验收待完成。在线字幕、均衡器/预设仍未迁移。详情见[字幕与音轨批次](PLAYER_TRACKS.zh-CN.md#当前批次字幕样式与音画同步p2-修复及-windows-验证完成2026-10-16) |
| 实时播放统计（实现及 Windows 验证完成） | 六项只读统计已接入播放信息面板。原实现全量 743 passed / 6 skipped、Windows Profile texture 专项通过、production Release/smoke 通过；后续播放器整合全量为 **768 passed / 7 skipped**（52 秒）。既有 `playback_stats_test` Windows Profile texture 回归报告与旧库一致：FPS、decoder/output drops、hardwareDecoder、forward bytes/seconds、AV sync 可用；`renderPasses=false`，HTTP cache 读数可用。当前 texture VO 不提供 `vo-passes`，UI 显示 `--`，不得切换 VO 强采；硬解读取可用不代表实际硬解已启用。真实 Emby、转码/切画质、macOS/Linux、可见 UI/视觉及长时间性能验收未覆盖。详见[实时统计计划](PLAYER_REALTIME_STATS_PLAN.zh-CN.md) |

字幕样式快速连续更新 P2 已修复并完成 Windows 验证；3 个定向测试文件合计 28 项、全量 753 passed / 6 skipped 通过，analyze、296 文件格式检查、Windows Release 与 smoke 均通过。其他平台和 UI 视觉验收仍待。详见[字幕与音轨说明](PLAYER_TRACKS.zh-CN.md#p2-修正快速连续样式更新合并windows-验证完成)。
| 画面显示五项（接线完成，Windows Profile texture 阶段验证通过） | 高级设置页签顺序为播放/音画同步/画面/字幕；画面仅含比例、黑边裁切、去隔行、旋转、镜像。播放状态仅显示非默认比例/裁切/去隔行/旋转，不摘要镜像；设置和嵌套二级菜单为深色主题。后端 13 + UI 2 项定向通过；Windows Profile texture 比例/裁切/镜像像素比较及旋转 getter/属性组合通过，未单独做旋转像素图像对比；去隔行 `auto` 属性切换通过，单独切换到 `on` 后 `deinterlace-active=yes`。全量 768 passed / 7 skipped、七项显式 native DLL 专项、严格暂停 resize (`osd-dimensions=480x270`) 与 analyze 通过；下载重试逻辑变更后的增量 Release 45.1 秒及五秒 smoke 已通过。手工预置固定 archive 的新缓存验证通过，但冷缓存网络下载因连接中断未验证。真实 Emby、macOS/Linux 与人工视觉验收待完成，正式发行前依赖长期归档/源码/许可证材料与通知清点待完成。亮度/对比度/Gamma、锐化/降噪、硬解选择及服务器转码扩展不在本轮范围。详见[画面显示计划](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md) |
| 其他画面与性能设置 | 饱和度、锐化/降噪、硬解选择、去色带/HDR 映射、弱网内存缓冲控制等仍按原迁移清单跟踪，不因本轮范围调整而删减 |
| 输入与快捷键 | 原完整默认映射、自定义/冲突处理、滚轮音量、中键/侧键动作、触控板进度/音量/缩放与灵敏度 |
| 文件入口与外部播放 | 从系统打开未入库文件的临时播放、默认/自定义外部播放器及系统文件关联接入；关联注册属于平台依赖 |
| UI 与平台验收 | 原版完整页面/布局/图标/字体/材质/状态/动效对照，Windows/macOS/Linux 原生与实机播放验收 |

画面/性能一栏指原版的可控选项与配置链路没有迁移，不表示 mpv 不能解码对应视频。库内部默认能力不能当作 ReelNest 已实现了原版设置。

## 验证现状与局限

- 前一批完整整合基线为提交 `4d4a0ee`：全量 **587 项 Dart 测试通过**，当时 1 项需要本机 libmpv 的专项测试按默认条件跳过；静态分析无问题，232 个 `lib` / `test` 文件格式检查通过。当前批次另行完成以下验证。
- 默认跳过的 `player_precision_native_test.dart` 单独传入 Windows Release 的 `libmpv-2.dll` 后 **1 项通过**，使用生成媒体验证章节读取、前后逐帧、A–B 和整片循环。它不使用真实 Emby 或用户媒体。
- Windows Release 构建通过；五秒启动检查确认隐藏窗口创建、保持响应、正常关窗且退出码 0，本次没有数据库关闭异常。启动检查不等于播放器可见画面、实体键鼠或真实播放闭环验收。
- 同批播放、精确播放和 Emby 画质弹层 **38 项定向回归**通过；2026-10-09 的 Windows **3 项原生业务场景**仍作为基础播放历史证据保留。
- 当前片头/片尾批次：`player_marker_skip_test.dart` 新增 17 项通过，`player_precision_test.dart` 13 项通过，`emby_quality_cache_test.dart` 34 项通过；其中 Emby 定向回归包含 2 项转码绝对位置与暂停保持检查。启用 `REELNEST_MPV_PATH` 后，marker skip native 新增 1 项及精确播放 native 原 1 项通过，默认运行时这 2 项 native 测试跳过。完整 `fvm flutter test --no-pub --concurrency=1` 最终 **609 项通过、2 项默认跳过**（02:05，退出码 0）；加上单独启用的两项 native 专项，共 611 项通过。
- marker skip native 覆盖真实 mpv session、解码时钟及 open/seek/play/pause 桥接；轨道控制为 stub，未创建 Flutter 原生窗口。它不证明可见播放器 UI、实体鼠标/键盘或真实 Emby 通过。
- 2026-10-13 播放器外观调整改动 `video_player_page.dart` 与 `player_visuals.dart` 的背景渐隐、加载/错误玻璃状态、控制条、按钮、时间轴与桌面 hover；播放流程、弹窗和快捷键未改。调整后 `playback_test.dart`、`player_marker_skip_ui_test.dart`、`slider_overlay_scope_test.dart` 共 26 项通过，Windows Release 用时 37.0 秒构建成功，五秒启动冒烟退出码 0。此前的 609+2 全量结果不是对这次外观改动后的全量验证；原版外观对照仍未完成。
- 2026-10-14 后续窗口 chrome 与控制栏优化：隐藏桌面播放器标题栏，macOS 保留原生窗口按钮、Windows/Linux 使用应用内按钮；新增桌面拖动区及 Windows/Linux 窗口控制，控制栏斜向渐变边框、hover 缩放 1.018；阴影透明度按原 Swift `VideoControlPalette` 恢复为 lightContent 0.08、darkContent 0.10。播放功能与流程不变。播放器相关 69 项通过；全量 616 项通过、2 项既有跳过；静态检查、Windows Release 及五秒启动烟测通过。macOS/Linux 未做原生窗口人工目视验收。
- 2026-10-14 P0 播放器视觉收口：新增复用的面板/控制/菜单表面组件及 choice/control 颜色，统一面板状态、描边、阴影和入场动效；无实时模糊，Esc 关闭即时，减少动态效果时无入场动画。播放业务及流程不变。5 个 presentation 文件分析通过；6 组测试共 62 项通过，Windows Release 与五秒启动烟测通过。本批未运行全量测试；上一批 616+2 不是本批全量结果，macOS/Linux 原生目视及真实 Emby 验收待完成。
- 2026-10-14 播放器第二轮 P0：窗口宽度 <760 时控制栏左右区收缩为 176/112，画质入口改为图标+tooltip；播放中控制层/弹层隐藏时隐藏光标，指针移动唤回控制层，过滤微抖，自动隐藏 3200ms；方向键音量和 M 静音用独立 HUD 显示图标/进度/百分比 950ms，快捷键不唤醒整条控制栏。6 个播放器测试文件共 62 项通过，`fvm flutter analyze --no-pub`、Windows Release 与五秒启动烟测通过；未跑全量测试，真实 Emby 和 macOS/Linux 原生/人工视觉验收待完成。
- 2026-10-14 P1-A：时间轴尾部点击切换总时长/剩余时间，默认关闭剩余时间并经 `PlaybackOptions` 持久化，更多设置提供开关；控制栏锁定后播放/暂停均收起且不被鼠标唤回，保留可见解锁入口与光标，解锁恢复控制/自动隐藏；居中播放信息列出现有元数据、未知值不推断，支持 `I`、优先由 `Esc` 关闭及右键菜单入口。6 个相关测试文件 62 项通过，分析、Windows Release 构建及 14:45 +08:00 五秒 smoke 通过。本批当时未跑全量，616+2 是修改前基线；真实 Emby、可见窗口及 macOS/Linux 原生验收未完成。P1-B 当时尚未完成；P1-C 亦未实现。
- 2026-10-14 P1-B：原版迷你悬浮窗经 `P`/右键入口切换，优先解码宽高比、再用远程分辨率、缺省 16:9；约 380px 优选宽度，最小 280×168，当前屏幕右下角 16px，强制置顶。包含播放/暂停、还原、关闭，双击与 `Esc` 还原；全屏拒绝进入并提示。退出时恢复原窗口位置/尺寸/最大化和用户置顶偏好；“窗口置顶”写入 `PlaybackOptions`。`window_manager` 统一三桌面端，`screen_retriever` 为直接依赖，macOS 迷你窗跨空间显示；协调逻辑抽至 `player_window_coordinator.dart`，引擎暴露实际视频宽高比。7 个相关测试文件 66 项通过，全量 620 通过/2 跳过，分析及 Windows Release 构建通过，15:01:30 +08:00 smoke 通过。macOS/Linux 原生实机、真实视频可见窗口人工交互/视觉仍待，smoke 不是迷你窗目视验收；P1-C 当时尚未实现。
- 2026-10-15 P1-C：时间轴预览图三档、148×83 悬停/拖动浮层、释放后 seek、单路独立静音 headless mpv、160 项/32MiB 同桶合并缓存、请求取消/换片隔离、远程有界 Range 安全代理和离线缓存租约已实现。全量 643 passed / 3 skipped；`flutter analyze --fatal-infos` 零问题；时间轴/语义树专项回归通过，native 抽帧 1 项输出 312×176 PNG 且主播放器状态不变；Windows Release 42.3 秒成功，10:01:54 +08:00 五秒 smoke 通过。真实 Emby、人工可见窗口及 macOS/Linux 原生/视觉最终验收待完成。P1-B 的 620+2 结果不覆盖本批。
- 测试媒体为自己生成的 AVI/Matroska/SRT，尚未全面覆盖真实音频听感、设备插拔、多编码/HDR/长视频、真实 NAS/磁盘拔插。macOS/Linux 原生未验收。
- 原版与当前图标/字体/材质等没有完成逐项视觉验收，不能称一比一完成。未产生更新时间事件的开发索引条目，其顶层相邻排序仍有已记录的对照缺口。
- 当前 `Video` 仍设置 `wakelock: false`，本轮另写原生显示器/系统防休眠服务；Windows 通道创建/释放成功，实际空闲超时和 macOS/Linux 仍未验证。

## P1-A 批次验证（2026-10-14）

播放器 P1-A 本批有 6 个播放器相关测试文件 **62 项通过**；`fvm flutter analyze --no-pub` 通过，Windows Release 构建成功；2026-10-14 14:45（+08:00）`scripts/windows-smoke.ps1 -ObservationSeconds 5` 窗口响应、正常关闭、退出码 0。`git diff --check` 只有 LF/CRLF 提示。P1-A 当时未跑全量，616+2 是 P1-A 的历史前置基线；后续 P1-B 全量结果见下。

P1-B 验证：7 个相关测试文件 **66 项通过**；全量 `flutter test --no-pub --concurrency=1` **620 passed / 2 skipped**，静态分析无问题。Windows Release 构建 36.2 秒成功；2026-10-14 15:01:30（+08:00）`scripts/windows-smoke.ps1 -ObservationSeconds 5` 通过响应、正常关闭、退出码 0。该 smoke 未做迷你窗可见画面/交互人工验收；macOS/Linux 原生实机和真实媒体播放仍待验。

P1-C 自动化验证完成：全量 643 passed / 3 skipped、分析零问题、专项时间轴/语义树回归、native 抽帧、Windows Release 与 smoke 均通过。P1-B 的 620+2 是此前独立批次结果。仍待真实 Emby、人工可见播放器交互/视觉及 macOS/Linux 原生实机验收。

## P1-A 前的整合验证基线

提交前整合复验（2026-10-14）：覆盖播放器两轮 P0 UI、侧栏/Emby 与 Logo 改动；全量 `fvm flutter test --no-pub --concurrency=1` **616 项通过、2 项默认关闭的原生用例跳过**，`fvm flutter analyze --no-pub` 无问题，`dart format lib test` 检查 235 个文件、0 修改。当前 Windows Release 构建后五秒烟测通过（隐藏窗口响应、正常关闭、退出码 0）。各先前批次“未跑全量”的表述仍准确，记录的是该批当时的验证范围；本次整合结果不替代单项原生专项历史证据。macOS/Linux 原生构建与实机、真实 Emby 完整操作、原版 UI 逐项视觉验收仍待完成。详见[提交前整合复验](PLAYER_PRECISION_BACKEND.zh-CN.md#提交前整合复验2026-10-14)。

历史整合基线（P1-A 之前）：两轮 P0、侧栏/Emby 与 Logo 改动经全量 616 项通过、2 项默认原生用例跳过；各独立批次仍保留其当时的验证范围。最新 P1-B 全量结果见上文。详见[播放器专项记录](PLAYER_PRECISION_BACKEND.zh-CN.md#提交前整合复验2026-10-14)。

片头片尾候选、审核及条目/批量任务已接入；本地未知时长与尚未载入的远程单集不会凭猜测参与检测。字幕样式/音画同步初始实现的 Windows 验证已完成；本轮快速连续样式更新 P2 修复后的定向/全量测试、Windows Release 与 smoke 均通过，其他平台与实际效果验收仍待。在线字幕保留原版待迁移地位，不另开新增功能计划。播放器其余高级项、真实 Emby、macOS/Linux 原生和三桌面端 UI 对照仍待完成。分批细节见[基础播放](LOCAL_PLAYBACK.zh-CN.md)、[字幕音轨](PLAYER_TRACKS.zh-CN.md)、[队列](PLAYER_QUEUE.zh-CN.md)和[高级播放接口](PLAYER_PRECISION_BACKEND.zh-CN.md)。

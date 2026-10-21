# ReelNest 文档

更新时间：2026-10-21。

本目录保存 ReelNest 的项目约束、实施计划、模块说明、验证记录和历史试验资料。ReelNest 是 MediaLib 的 Flutter 重构版；第一阶段只开发和验收 Windows、macOS、Linux，功能、UI 与交互不自行增删改。

## 当前快照

- Emby 媒体库性能优化（2026-10-21）：排序内复用标题解析；后续演员作品批量读取和想看/评分偏好增量覆盖也已实现。排序功能回归分批 64+19 项，增量读取相关回归 80 项通过；增量批次全量为 838 passed / 10 按配置跳过。两个批次均有独立 Windows Release/smoke 证据。Flutter test 排序基准仅反映函数耗时，不代表整页或真实 Emby 性能。持久搜索 isolate、真实大库可见 UI 和 macOS/Linux 原生性能仍待。详见[排序性能检查](PERFORMANCE_REVIEW_2026-10-21.zh-CN.md)、[增量读取记录](LIBRARY_INCREMENTAL_READS_2026-10-21.zh-CN.md)和[当前阶段](NEXT_STAGE.zh-CN.md#2026-10-21-emby-媒体库排序性能优化)。
- 前端 P1-G 全局弹层与反馈表面统一：新增公共 toast/inline notice 与确认弹窗，普通页面反馈和确认样式统一并迁移来源、设置、健康及 Emby 批量移除；播放器专用深色 UI 保持独立，业务流程和按钮语义不变。关键回归 110 项、本批全量 834 项通过/9 项既有条件跳过；另有 2026-10-21 统一提交前最终工作区复验，全量 843 passed / 0 skipped（9 项 native 均执行）、analyze clean、339 个 Dart 文件 format 0 changed、diff-check clean。该复验未重建；最新 Windows Release 仍为 36.6 秒，16:20:50 +08:00 五秒 smoke 通过。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-g全局弹层与反馈表面统一)。
- 前端 P1-F 仪表盘与任务中心视觉收口：新增共享 dashboard surfaces，统一健康页状态/分区、4/2/1 列概览卡和扫描/分析/离线缓存任务表面；不新增检测规则、后台任务或 schema 变化。最后定向复验 25/25、targeted analyze clean；全量 832 passed / 9 skipped、全项目 analyze 仍通过。最终 Windows Release 36.6 秒及 2026-10-21 15:23:53 +08:00 五秒 smoke 通过，1088×720 明/暗主题健康页截图人工复核通过。真实 Emby、实体键鼠、高 DPI、macOS/Linux 原生目视仍待。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-f仪表盘与任务中心视觉收口)和[健康评分/仪表盘](HEALTH_SCORE.zh-CN.md#2026-10-21-p1-f仪表盘与任务中心视觉收口)。
- 播放后台性能优化四项已落地并通过自动化验证：显式 mpv 的全量 841/0（9 项 native 实际运行）、analyze、335 文件 format 和 diff-check 通过；90,006 条媒体（其中 90,000 条为无关剧集）的内存 fixture 中目标剧集仅读 3 条，完整偏好 getter 从 25 次 SQL 收敛至 1 次快照。Windows Release 首轮 39.1 秒，最终增量构建 **26.4 秒成功**；2026-10-21 14:55:53 +08:00 五秒 hidden smoke 正常响应、关闭且退出码 0。无真实 Emby 性能对比/提升比例，macOS/Linux 原生和长时性能验收仍待。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-21-播放后台性能优化四项落地自动化验证及-windows-releasesmoke-完成)。
- 前端 P1-E 首页视觉收口：按原版统一加载/错误/部分同步状态、统计卡、搜索、视频行/卡、Hero、搜索结果、布局编辑和运行状态卡；保留首页模块及原业务/持久化，未新增照片、音乐或模块。7 个测试文件 97 项通过，全项目 analyze 无问题，Windows Release 37.3 秒成功。真实本地/Emby 混合数据、海报/长标题/大量内容、实体键鼠、高 DPI 及 macOS/Linux 原生实机视觉仍待。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-e首页视觉收口)、[首页计划](HOME_IMPLEMENTATION_PLAN.zh-CN.md#2026-10-21-p1-e首页视觉收口)和[运行状态](HOME_RUNTIME_STATUS.zh-CN.md#2026-10-21首页运行状态视觉收口)。
- 前端 P1-D 设置/服务器页视觉统一：新增共享 `settings_surfaces.dart` 并迁移设置、观看、缓存、健康忽略和服务器页；保持原业务与默认值，不加入 WebDAV/音乐/照片或未实现设置项。来源加载骨架增加 reduced-motion 兼容的轻微呼吸。相关 Flutter 测试 52 项通过，全项目 analyze 无问题，Windows Release 构建成功。实机 UI、高 DPI、真实服务器操作、缓存路径/清理及 macOS/Linux 原生构建与实机验收仍待。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-d设置与服务器页面视觉统一)。
- 媒体源管理与添加流程 P1-C 视觉收口：来源卡常态平铺与交互反馈、紧凑横向工具条、统一状态卡/弹窗/确认对话框及 12px 弹窗安全边距；不改来源操作业务、默认值或连接器范围。6 个相关测试文件 58 项通过，单文件补充复验、全项目 analyze 及 Windows Release 41.8 秒构建通过；未做启动 smoke。真实目录/Emby 流程、可见鼠标键盘、长路径与来源数、高 DPI、macOS/Linux 原生实机视觉仍待。详见[媒体源说明](LOCAL_SOURCES.zh-CN.md#2026-10-21媒体源管理与添加流程-p1-c-视觉收口)和[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-21-前端-p1-c媒体源管理与添加流程视觉收口)。
- 本地与 Emby 媒体详情页 P1-B 视觉收口：统一静态页头/Hero/状态卡和横向操作条，修正季标题按钮层级、剧集既有观看状态提示及 extras 间距；不改变播放、评分、想看、已看写回或缓存业务。相关回归 47 项通过，全项目 `flutter analyze --no-pub` 通过，Windows Release 构建成功。真实 Emby 可见 UI、鼠标/键盘、长列表、高 DPI 及 macOS/Linux 原生实机视觉验收仍待。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-20-前端-p1-b媒体详情页视觉收口)与[详情页说明](EMBY_DETAILS.zh-CN.md#2026-10-20媒体详情页-p1-b-视觉收口)。
- Emby 媒体库浏览页 P1-A 前端收口：筛选控制栏按原版组件参数重构，补齐状态反馈、减少动画、680×382 窄窗布局及四行加载骨架；不改分类/筛选排序规则、服务器行为或持久化。全量 analyze 通过，导航与浏览定向测试 45 项通过（Windows/macOS/Linux 平台变体、明暗主题）；最终源码 Windows Release 构建 39.8 秒成功。本轮未做启动 smoke；真实媒体库人工视觉、实体键鼠及三桌面原生验收仍待。详见[阶段记录](NEXT_STAGE.zh-CN.md#2026-10-20-前端-p1-a-emby-媒体库浏览页收口)与[Emby 导航](EMBY_NAVIGATION.zh-CN.md#2026-10-20媒体库浏览页-p1-a-前端收口)。
- 当前两项 P2 修复定向、全量和 Windows Release/smoke 验证完成：28 项定向、全量 753 passed / 6 skipped，analyze、296 文件格式检查及 diff-check 通过；Release 45.7 秒，五秒 smoke 正常响应并关闭。无 schema 变更、无用户数据删除、未提交推送。详见[字幕说明](PLAYER_TRACKS.zh-CN.md#p2-修正快速连续样式更新合并windows-验证完成)与[项目边界](PROJECT_SCOPE.zh-CN.md#p2-修正数据库目录边界校验windows-验证完成)。
- 画面显示五项已接通，后端 13 + UI 2 项定向通过。Windows Profile texture 比例/裁切/镜像像素比较及旋转 getter/属性检查通过；768/7 全量、七项 native DLL 专项、Windows 严格暂停 resize 为上一轮结果，本轮未重跑全量。2026-10-17 macOS/Linux 暂停 resize P2 定向 15/15、Windows Profile GPU/SW 及 CMake 下载重试后的 Windows Release/smoke 均通过。2026-10-19 Linux 新增软件 renderer 等比例视口适配：使用上游 `texture_sw.h` 真实 1920×1080 caps，对项目生成 C++ helper/setter/getter 在 Windows 主机编译并以 test doubles 验证（10 组尺寸及自动/旋转/guard 场景、有/无 SW 宏均通过；上游 callback/getter 漂移故障注入均被拒绝）。这不是 Linux GTK/EGL 构建或实机视觉验收；Linux 大窗口/高 DPI/暂停 resize 以及 macOS 原生构建/实机验收仍待。真实 Emby、人工视觉验收、发行前依赖材料归档与通知清点仍待。详见[画面显示 P2 记录](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md#p2-macoslinux-暂停时视口-resize-不主动重绘实现落地平台验收待完成2026-10-17)中的 2026-10-19 Linux 补充。
- 用户已批准播放器画面色彩调整五项：亮度、对比度、饱和度、伽马、色相（-100…100，默认 0，步进 5，单项重置）；全局 JSON 偏好 `global.videoColorAdjustments`，完整对象单条写入既有 `player_preferences`，无 schema 变更，本地/Emby 共用。Windows Profile GPU YUV420 五项及 GPU/SW 宽色度 YUV 四组组合/边界像素对比通过；ASS 矢量白字幕在黑画面上显示正常，无字幕时保持全黑；平滑 RGB 梯度确认 hue/saturation 保持原版无效语义而 brightness 生效。当前两条 GPU/SW texture 用例通过，后端 15 + UI 2 共 17 项通过，偏好读取失败不阻断播放回归通过，静态分析 `lib`/`test`/`integration_test` 无问题。暂停尺寸往返 400×240→320×180 已通过：恢复后画面/色彩与白色 ASS 平均像素差 <2、暂停仍为 `yes`、`time-pos` 偏差 <0.02 秒。全量 783 passed / 7 skipped（57 秒）通过；Windows Release 构建 55.0 秒成功，五秒 smoke 于 2026-10-18 18:51:54 +08:00 通过（隐藏窗口响应、正常关闭、退出码 0）。macOS Ruby/Swift、Linux 原生构建、真实 Emby、高分辨率 CPU 长测、非 seekable 流未验收；历史 768/7 不计本轮。详见[画面色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md)。
- 用户已批准的两项原版播放性能控制已实现：硬件解码模式（兼容/自动/关闭）与弱网内存缓冲。全量 817/0、Profile GPU/SW、Windows Release/smoke 通过；但 Profile fixture 不含可硬解视频且 `hwdec-current=no`，不能据此声称实际硬解启用。loopback Range 测试不证明真实 Emby 或弱网收益；真实压缩媒体硬解、Emby、macOS/Linux 原生和人工 UI 验收仍待。范围/偏好结构见[当前阶段记录](NEXT_STAGE.zh-CN.md#video-performance-settings)与[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)。
- 去色带与 HDR 色调映射本轮 GPU 路径实现及 Windows 自动化验证完成：Profile GPU/SW 两场景、backend 12 + UI 2、全量 **829 passed / 0 skipped**、analyze/328 文件 format、Windows Release 40.4 秒和 smoke 通过。纯 SW renderer 的任何用户渲染设置编辑（包括默认值）明确拒绝、不保存；读取默认偏好静默，非默认保留 DB 并提示。SW 限制来自渲染路径，与硬件解码无关，软件解码+GPU renderer 仍可用。真实 HDR 片源/显示器、真实 Emby、macOS/Linux 原生及人工 UI 验收待，详见[当前阶段记录](NEXT_STAGE.zh-CN.md#video-deband-tone-mapping)和[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)。
- 用户已批准迁移原版锐化四档与滤镜链组合；降噪仅依赖核查并形成实施方案，不在本轮实现。`global.videoSharpenMode` 默认 `off`、持久化原版 enum 名称。共享 owned-filter helper 已接入；锐化 Dart 12 项、显式 DLL native 1 项均包含于启用 `REELNEST_MPV_PATH` 的最终全量 **803 passed / 0 skipped（39 秒）**，全部 8 项 native 实际执行并通过。Windows Profile GPU/SW 锐化用例（17 秒）和 `video_color_test.dart` 两 renderer 用例（19 秒）通过，medium 锐化 ASS/黑画面/暂停 resize 正常，且 19 秒运行已验证关闭锐化后恢复 RGB 原语义。headless native 用例 Temp namespace 通过 `IOOverrides` 隔离至自身 sandbox；PID 复用仅为候选解释，未由崩溃栈独立确诊，未改生产 runtime。318 个 Dart 文件格式 0 改动、analyze clean、diff-check 无错误。代码/UI 已冻结，Windows production Release 42.5 秒和五秒 smoke 均通过；详见[锐化计划](PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md)。
- 画面显示五项已接通，后端 13 + UI 2 项定向通过。Windows Profile texture 比例/裁切/镜像像素比较及旋转 getter/属性检查通过；768/7 全量、七项 native DLL 专项、Windows 严格暂停 resize 为上一轮结果，本轮未重跑全量。下载重试逻辑更新后的 Windows Release 45.1 秒和 2026-10-16 23:39 smoke 通过。2026-10-17 macOS/Linux 暂停 resize P2 最新 Dart 定向 15/15、analyze 0、305 文件 format 0 改动、diff-check 通过；Windows Profile GPU/SW 两场景及 Linux 生成补丁两种宏配置 MSVC/test doubles 检查通过。Windows Release 41.0 秒和 00:17:46 smoke 通过。Mac Ruby/Pods/Swift、Linux GTK/EGL 原生构建、CI 与两端实机 resize 未验收，不代表两平台原生验收完成。固定 archive 新缓存校验通过，冷缓存网络下载仍未验证。真实 Emby 与人工视觉验收待；发行前仍需长期归档依赖源码/许可证材料并清点通知。详见[画面显示 P2 记录](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md#p2-macoslinux-暂停时视口-resize-不主动重绘实现落地平台验收待完成2026-10-17)。
- Windows 绿色便携存储本轮验证完成：全量 731 passed / 6 skipped、analyze clean、289 Dart format 0 改动、Profile 原生 portable_runtime 1 项通过；Release 39.2 秒、不同 cwd 单次 WM_CLOSE smoke 两次、空白 userdata 和 ZIP 白名单均通过。ZIP 含 exe/`data/app.so`，不含用户数据目录或 PDB。Roaming 仍有 518 字节旧凭据 `.dat`，删除受限，需用户手动删除；新版不读取或改写。旧 DB/log、Local 缓存和 Release 副本已清，便携运行需使用空白配置重新添加 Emby；验证范围仅限 Windows，不代表 macOS/Linux 便携。详见[项目边界](PROJECT_SCOPE.zh-CN.md#用户确认的-windows-便携存储约束本轮-windows-验证完成)与[数据字典](DATA_DICTIONARY.zh-CN.md)。
- 播放故障诊断批次最终定向 native、analyze、格式/diff 检查通过，Windows Release 40.8 秒和五秒 smoke 通过；701/4 全量为最后三行兜底修正前结果。真实 Emby 根因仍待新版复现，macOS/Linux 原生未验收；详见[高级播放与当前批次记录](PLAYER_PRECISION_BACKEND.zh-CN.md)。
- 用户于 2026-10-16 明确授权新增播放器输入速率提示：代码已冻结，backend 54、UI 27、隔离 native 2 项通过，analyze、269 文件格式及 diff 检查通过；Windows Release 39.6 秒及五秒 smoke 通过。本轮未跑上一轮 701 项全量；真实 Emby、实体键鼠和 macOS/Linux/三端视觉验收仍待。详见[专项记录](PLAYER_PRECISION_BACKEND.zh-CN.md#用户授权播放器输入速率提示代码冻结windows-验证完成三端验收待定2026-10-16)。
- 播放器六项实时统计实现及 Windows 验证完成：原实现全量 743 passed / 6 skipped、Windows Profile texture 专项及 production Release/smoke 通过；最新整合全量 768 passed / 7 skipped。既有 `playback_stats_test` Windows Profile texture 回归报告与旧库一致，`renderPasses=false`、HTTP cache 读数可用，不切换 VO 强采。真实 Emby、实际硬解启用、转码/切画质、macOS/Linux、可见 UI/视觉及长时间性能验收仍待。详见[实时统计计划](PLAYER_REALTIME_STATS_PLAN.zh-CN.md)。
- 当前播放器主线：片头片尾的首页/媒体库/详情检测入口、系列批量分析与任务中心已接入；最终全量 685 passed / 3 skipped、分析、Windows Release 和启动检查通过。开发前基线为 `fab5dda`；真实来源、三端实机、原版 UI 验收仍待。字幕样式/音画同步初始实现的 718/6、native 和 Windows Profile 字体验证保留为历史结果；本轮字幕连续样式更新 P2 修复后 753/6 全量通过，Windows Release/smoke 复验待补。ASS/位图、macOS/Linux、Emby 和视觉验收未覆盖。详见[字幕音轨记录](PLAYER_TRACKS.zh-CN.md#当前批次字幕样式与音画同步p2-修复全量测试通过release-待验2026-10-16)。
- 最新播放器 UI 固定深色 Chrome 色板覆盖 Dock、右键精度菜单、各设置面板及嵌套菜单，不随海报明暗变浅且不影响普通页面；右键菜单重复迷你悬浮窗入口已移除，迷你悬浮窗仅保留 Dock 按钮和 `P` 快捷键。`playback_test.dart` 20/20、7 个弹层相关测试 47/47、targeted analyze clean；Windows Release 34.5 秒及 2026-10-16 11:03:30 +08:00 五秒 smoke 通过。真实窗口/三端视觉验收未完成，见[Dock 批次记录](PLAYER_PRECISION_BACKEND.zh-CN.md#当前-ui-批次播放器控制栏-dock-重构2026-10-15)。
- 最近完成：高级播放首批章节/书签、单片循环、A–B 与逐帧底层和 UI 接入，以及侧栏/主题整理；此前首页 H1/H2/H3、视频健康评分和来源刷新状态保护已接通。
- 最新侧栏 hover 修复完成 45 项定向回归和 Windows Release/启动冒烟；Windows 结果不代表 macOS/Linux 原生验收，细节见[Emby 导航记录](EMBY_NAVIGATION.zh-CN.md#2026-10-14侧栏菜单悬浮点击残影修复)。
- 来源媒体库 P0 UI 增量已记录：海报卡进度/评分/悬停状态、Emby 视频库响应式工具栏与筛选/状态面板、本地/Emby 共用详情页层级调整。相关范围、原版文件映射和 98 项定向验证见[Emby 导航](EMBY_NAVIGATION.zh-CN.md)、[详情](EMBY_DETAILS.zh-CN.md)及[源码映射](design/SOURCE_MAPPING.md)；原生截图/逐像素验收仍待，全量整合复验见下方记录。
- `4d4a0ee` 的 587 项及后续 609+2 均为历史批次结果。P1-A 之前的提交前整合复验覆盖了两轮 P0 UI、侧栏/Emby 与 Logo 改动：全量 616 项通过、2 项默认关闭的原生用例跳过；这是历史基线，各独立批次“当时未跑全量”的记录仍准确保留。最新 P1-B 全量和 Windows 结果见下方。macOS/Linux 原生验收、真实 Emby 播放仍待，详见[高级播放接口与验证](PLAYER_PRECISION_BACKEND.zh-CN.md#提交前整合复验2026-10-14)。
- P1-A 专项当时为 62 项定向测试且未跑全量；此前 616+2 仅是当时基线。详见[P1-A 验证](PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-a剩余时间控制栏锁定与播放信息2026-10-14)。
- P1-B 的 7 个相关测试文件 66 项、全量 620 项通过/2 项跳过、Windows Release 与 smoke 均为 P1-C 前的验证；迷你窗目视与 macOS/Linux 原生验收仍待。详见[P1-B 验证](PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-b迷你悬浮窗与窗口置顶2026-10-14)。
- 最新播放器 P1-C 自动化验证完成：全量 643 passed / 3 skipped，分析零问题，时间轴/语义树专项及 native 抽帧通过；Windows Release 42.3 秒构建与五秒 smoke 通过。真实 Emby、人工可见窗口交互/视觉和 macOS/Linux 原生验收仍待，P1-C 详细边界见[播放器专项记录](PLAYER_PRECISION_BACKEND.zh-CN.md#播放器-p1-c时间轴预览图2026-10-15)。
- 尚未由该记录证明：真实 Emby 完整操作、实际滚动帧率、macOS/Linux 原生运行、三桌面端原版 UI 对照。
- 音乐后续作为独立大模块统一迁移；Jellyfin、Plex、ReelNest Server 等原有来源仍在完整范围内。
- WebDAV 设置备份是后续明确新增功能，当前不实施。
- 用户于 2026-10-12 明确暂不实现照片模块：照片/相册、照片搜索和首页照片墙移出当前入口、计划与验收范围，恢复需重新确认；影视图片功能保留。后续调整与验证见[照片范围记录](PHOTO_SCOPE_DECISION.zh-CN.md)。

当前任务和完成条件见[当前阶段记录](NEXT_STAGE.zh-CN.md)、[播放器总表](PLAYER_STATUS.zh-CN.md)与[高级播放接口及当前批次](PLAYER_PRECISION_BACKEND.zh-CN.md)。首页未完成验收继续保留在[首页实施计划](HOME_IMPLEMENTATION_PLAN.zh-CN.md)。历史测试数字只代表对应批次，不覆盖后续代码。

## 阅读顺序

1. [项目边界与一致性要求](PROJECT_SCOPE.zh-CN.md)：产品范围、平台、品牌、数据库和验收约束。
2. [当前阶段记录](NEXT_STAGE.zh-CN.md)：当前下一批及从早期本地来源到首页的实施时间线。
3. [首页实施计划](HOME_IMPLEMENTATION_PLAN.zh-CN.md)：当前 H1 → H2 → H3 主线和验收条件。
4. [项目结构与模块设计](PROJECT_STRUCTURE.zh-CN.md)：代码布局、职责和依赖方向。
5. [开发指南](DEVELOPMENT.zh-CN.md)：环境、命令、构建、CI 和原生验证边界。
6. [原版一致性核对清单](design/ORIGINAL_PARITY_AUDIT.zh-CN.md)：源码依据、当前迁移摘要、现有偏差和历史审计。
7. [三桌面端实现与验收矩阵](PLATFORM_VERIFICATION_MATRIX.zh-CN.md)：按平台区分自动化、原生、真实环境和 UI 对照。

文档作者和模块负责人还应阅读[文档维护规范](DOCUMENTATION_GUIDE.zh-CN.md)；涉及持久化时阅读[数据字典](DATA_DICTIONARY.zh-CN.md)。

若文档叙述冲突，按“用户最新明确要求与 `AGENTS.md` → 项目边界 → 原版指定源码基线 → 当前代码/测试与最新专项记录 → 历史计划”的顺序判断。

## 项目约束与设计

| 文档 | 用途 |
|---|---|
| [项目边界与一致性要求](PROJECT_SCOPE.zh-CN.md) | 权威范围、三桌面端、功能/UI 一致性及数据库原则 |
| [文档维护规范](DOCUMENTATION_GUIDE.zh-CN.md) | 文档类型、状态、验证等级、更新与归档规则 |
| [模块规格模板](templates/MODULE_SPEC_TEMPLATE.zh-CN.md) | 新模块或重大补齐使用的统一规格模板 |
| [Flutter 重构实施计划](FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md) | 完整来源范围、阶段目标和验收标准 |
| [项目结构与模块设计](PROJECT_STRUCTURE.zh-CN.md) | 当前与目标目录、模块职责及依赖方向 |
| [数据字典](DATA_DICTIONARY.zh-CN.md) | 当前 SQLite schema、媒体身份、缓存和敏感数据边界 |
| [三桌面端实现与验收矩阵](PLATFORM_VERIFICATION_MATRIX.zh-CN.md) | Windows、macOS、Linux 的实现状态与验证证据 |
| [原版源码映射](design/SOURCE_MAPPING.md) | Swift/SwiftUI 到 Flutter 的来源映射 |
| [原版一致性核对清单](design/ORIGINAL_PARITY_AUDIT.zh-CN.md) | 已读源码、当前偏差及验收缺口 |
| [原版缺陷防引入清单](design/ORIGINAL_DEFECT_GUARDS.zh-CN.md) | 远程读取、缓存提交、重下载和 FFmpeg 回归要求 |
| [初始化决策](decisions/0001-client-bootstrap.md) | 初始化时期的应用标识、依赖和工程选择 |
| [GitHub 仓库与发布规划](GITHUB_REPOSITORY_PLAN.zh-CN.md) | 仓库、分支、CI、版本、签名与发布安排 |
| [设置云备份与恢复计划](CLOUD_SETTINGS_PLAN.zh-CN.md) | 后续 WebDAV 设置备份；尚未实现 |

## 首页

| 文档 | 状态与内容 |
|---|---|
| [首页实施计划](HOME_IMPLEMENTATION_PLAN.zh-CN.md) | 当前计划；H1 基础闭环、H2 推荐/搜索/状态、H3 编排与桌面验收 |
| [首页 H1 实现记录](HOME_H1.zh-CN.md) | 跨来源统计、续播/历史、想看/收藏、最近剧集、分页与刷新 |
| [首页 H2 推荐实现记录](HOME_H2_RECOMMENDATIONS.zh-CN.md) | 每日推荐、剧集推荐、高分精选、封面配色和后台计算 |
| [首页跨来源视频搜索](HOME_SEARCH.zh-CN.md) | 搜索字段、分组、可取消后台匹配、来源隔离及详情返回 |
| [首页运行状态](HOME_RUNTIME_STATUS.zh-CN.md) | 来源、基础健康和任务摘要，读取不触发扫描，检测范围与验证记录 |
| [视频健康评分](HEALTH_SCORE.zh-CN.md) | 原版首页/仪表盘公式、本地/Emby 视频范围、重复/详情缺口、忽略恢复与验证 |
| [首页编排](HOME_LAYOUT_EDITOR.zh-CN.md) | 原版编辑入口、拖动/隐藏/恢复、串行持久化与失败重试、桌面组件验证 |
| [首页进度与清除修复](HOME_PROGRESS_FIXES_2026-10-12.zh-CN.md) | 百分比进度、记录区分及远程失败提示 |

## 本地来源与公共浏览

| 文档 | 内容 |
|---|---|
| [本地媒体源与索引](LOCAL_SOURCES.zh-CN.md) | 目录来源、扫描、SQLite、来源隔离和平台边界 |
| [媒体源别名与 Emby 图标](SOURCE_ALIASES.zh-CN.md) | 侧栏 Logo、来源别名和持久化 |
| [来源刷新与页面生命周期](SOURCE_PAGE_LIFECYCLE_FIX_2026-10-12.zh-CN.md) | 刷新期间保留滚动、多选、分页游标和详情状态 |
| [媒体库进入详情的海报闪烁修复](POSTER_TRANSITION_2026-10-12.zh-CN.md) | 页面切换时的海报占位与过渡修复 |
| [无媒体库与 NAS 的测试方案](MEDIA_TESTING.zh-CN.md) | 合成媒体、可播放样本、SMB 模拟和平台验证 |

## 视频播放

| 文档 | 内容 |
|---|---|
| [共用视频播放器实现盘点](PLAYER_STATUS.zh-CN.md) | 本地/Emby 共用播放器已实现能力、固定剩余范围及验收边界 |
| [本地视频播放与续播](LOCAL_PLAYBACK.zh-CN.md) | 独立窗口、进度、基础控制和失败保护 |
| [播放队列与播完行为](PLAYER_QUEUE.zh-CN.md) | 同系列队列、相邻项和三种结束行为 |
| [字幕、音轨与音量面板](PLAYER_TRACKS.zh-CN.md) | 本地/双字幕、音轨、输出和增强设置；P2 连续样式更新修复后全量测试通过，Windows Release/smoke 复验待补 |
| [基础播放设置与防休眠](PLAYER_BASIC_SETTINGS.zh-CN.md) | 倍速、续播、已看阈值、音量和平台防休眠 |
| [高级播放首批接口与验证](PLAYER_PRECISION_BACKEND.zh-CN.md) | 章节/书签、单片循环、A–B、逐帧、用户授权的输入速率提示及验证边界 |
| [播放器实时统计计划](PLAYER_REALTIME_STATS_PLAN.zh-CN.md) | 六项统计语义、状态与隐私边界；Windows Profile texture 回归通过（`renderPasses` 当前不可用），跨平台及真实场景验收待完成 |
| [播放器画面显示计划](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md) | 五项显示设置的原版偏好、默认值、UI 与引擎映射、平台 native 验收边界；接线及 Windows Profile texture 阶段验证通过，Release/跨平台/真实来源验收待完成 |
| [播放器画面色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md) | 五项色彩调整实现及 Windows 验证完成（含 Release/smoke）；macOS/Linux 原生、真实来源与边界验收待完成 |
| [播放器画面锐化与滤镜组合计划](PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md) | 锐化四档与原版滤镜链迁移；降噪只做 pinned FFmpeg/运行时/分发依赖核查并提出方案，不在本轮实现 |

## Emby 视频

| 文档 | 内容 |
|---|---|
| [Emby 基础闭环计划](EMBY_PLAN.zh-CN.md) | E1–E3 的历史阶段计划和验收范围 |
| [连接与选库（E1）](EMBY_CONNECTION.zh-CN.md) | 登录、凭据、选库、恢复与重新认证 |
| [分页同步与浏览（E2）](EMBY_SYNC.zh-CN.md) | 分页、完整快照、取消/失败保护和基础浏览；超大响应自适应缩页见[首次浏览与人物作品](EMBY_LOADING.zh-CN.md#2026-10-15-超大响应分页自适应修复) |
| [播放与进度同步（E3）](EMBY_PLAYBACK.zh-CN.md) | 鉴权播放、续播、队列、痕迹模式和上报 |
| [收藏、已看与服务器字幕](EMBY_ACTIONS_SUBTITLES.zh-CN.md) | 状态写回/回滚、批量观看和文本字幕 |
| [服务器详情、演职员与艺术照](EMBY_DETAILS.zh-CN.md) | 详情缓存、人员、图片和技术信息 |
| [视频媒体库导航与浏览](EMBY_NAVIGATION.zh-CN.md) | 来源树、分库、筛选、排序、P0 浏览 UI 调整及侧栏切换按压态残留修复 |
| [演员作品批量读取与偏好增量刷新](LIBRARY_INCREMENTAL_READS_2026-10-21.zh-CN.md) | 演员作品批量 SQLite 读取、按来源偏好版本和 Emby 展示快照增量覆盖及验证边界 |
| [首次浏览与人物作品](EMBY_LOADING.zh-CN.md) | 前台分页、后台批量索引和服务器人物作品 |
| [画质与缓存](EMBY_QUALITY_CACHE.zh-CN.md) | 转码画质、图片/视频缓存、手动离线和容量维护 |
| [自动离线订阅与任务入口](EMBY_OFFLINE_SUBSCRIPTIONS.zh-CN.md) | 订阅范围、暂停/到期、网络策略和任务控制 |
| [右键、多选与图片内存缓存](EMBY_LIBRARY_ACTIONS.zh-CN.md) | 菜单、批量栏、索引移除和解码缓存 |
| [初始评级与显示分类](EMBY_CLASSIFICATION_RATING.zh-CN.md) | 评分换算和顶层分类投影 |
| [启动侧栏修复](EMBY_STARTUP_NAVIGATION_2026-10-12.zh-CN.md) | 缓存目录先显示、加载数量和展开响应 |
| [首次剧集播放与分页保护](EMBY_BROWSE_FIXES_2026-10-12.zh-CN.md) | 按需播放准备和延迟分页版本校验 |
| [演员作品与详情加载优化](EMBY_DETAIL_PERFORMANCE_2026-10-11.zh-CN.md) | 详情读取与人物作品性能修正 |

## 验证与性能记录

这些文档记录的是特定提交或批次，数字不能脱离日期当作当前总状态。

| 文档 | 范围 |
|---|---|
| [2026-10-08 本地媒体库回归](TEST_REPORT_2026-10-08.zh-CN.md) | 本地来源、扫描、健康和设置 |
| [2026-10-09 空库启动与错误显示](TEST_REPORT_2026-10-09.zh-CN.md) | 数据库启动、本地播放和 Emby E1/E2 等当日批次 |
| [2026-10-10 Emby 导航、画质与缓存](TEST_REPORT_2026-10-10.zh-CN.md) | Emby 视频批次及 Windows 原生场景 |
| [2026-10-11 媒体库滚动优化](TEST_REPORT_2026-10-11.zh-CN.md) | 卡片索引、显示尺寸解码和图片校验 |
| [数据库读取与关闭优化](DATABASE_PERFORMANCE_2026-10-11.zh-CN.md) | 后台读取、事务关闭和性能边界 |
| [前端性能补充检查](FRONTEND_PERFORMANCE_AUDIT_2026-10-11.zh-CN.md) | 页面和图片管线补充审计 |
| [Emby 媒体库排序性能检查](PERFORMANCE_REVIEW_2026-10-21.zh-CN.md) | 单次排序标题解析复用、受控基准、回归证据与未实施优化候选 |
| [播放器关闭后主界面响应检查](FRONTEND_CLOSE_AUDIT_2026-10-11.zh-CN.md) | Windows 关窗、重开和主界面响应 |
| [Windows 构建与冒烟](WINDOWS_SMOKE.zh-CN.md) | 初始化时期的 Windows 构建与 7 项测试；历史记录 |

## 历史试验资料

以下内容保留用于追溯，不是当前产品架构或下一批开发入口：

- [Mlink 服务器连接试验](MLINK_CONNECTION.zh-CN.md)：历史登录/会话实现。
- [媒体浏览与详情试验](LIBRARY_BROWSING.zh-CN.md)：早期 Mlink 数据路径和可复用界面记录。
- [系列摘要接口试验](SERIES_API.zh-CN.md)：旧 MediaLib 服务端扩展，未部署且不再作为依赖。

`design/` 保存原版源码与一致性资料，`decisions/` 保存技术决策。计划文档中的目录或能力不代表代码已经实现；实现记录中的自动化通过也不替代真实服务器和三桌面端验收。

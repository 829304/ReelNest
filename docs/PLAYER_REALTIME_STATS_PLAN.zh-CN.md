# 播放器实时统计规划

- 状态：实现及 Windows 验证完成；跨平台与真实场景验收待完成
- 负责人：播放器模块
- 最后更新：2026-10-16
- 适用范围：本地与 Emby 共用的视频播放器；第一阶段 Windows、macOS、Linux
- 权威范围：六项播放实时统计的入口、语义、状态、安全边界与计划验收
- 验证状态：实现与本轮 Windows Release/smoke 验证完成；真实 Emby、实际硬解启用、转码/切画质、macOS/Linux、可见 UI 与长时间性能验收待完成

## 目标与批准范围

用户于 2026-10-16 明确授权将下列六项接入 ReelNest 播放信息面板。本轮实现及 Windows Release/smoke 验证已完成。这是对“不自行新增功能”约束的单项范围例外，不授权添加其他性能面板或系统级监控：

1. 视频输出 FPS（估算）
2. 丢帧数（解码器与视频输出分别统计）
3. 实际硬件解码状态
4. 渲染 pass 耗时
5. demuxer 前向缓存字节量与估算缓存时长
6. 实际音画同步偏差

已在现有“播放信息”面板中增加实时统计区。面板默认关闭且不把统计常驻覆盖在视频上；打开时约每秒采样，关闭后停止采样。统计局部使用 notifier/state，使数据刷新不订阅并重建整个播放器页面的高频播放时钟。结构按原版 `PlayerView.swift` 约第 4082 行起的信息面板层级保留；代码迁移完成，但原版与 ReelNest 的可见 UI/视觉对照验收仍待实机完成。

本地与 Emby 视频共用同一统计展示和会话边界。数据只读 mpv 当前引擎状态，不为显示统计而重启播放器、seek、改变画质、硬件解码或缓存配置。面板关闭时不进行周期采样。六项统计默认仅保存在当前进程内存，不保存历史快照，不写入数据库、诊断日志或上传系统性能数据；不得记录媒体路径、URL、凭据等身份信息。

## 官方属性语义与展示规则

mpv 属性参照 [mpv 官方 properties 手册](https://mpv.io/manual/stable/#properties)。属性有缺失、平台/VO 不支持和暂不可用情形；不得把 `null` 转成有效的零，也不得把配置值当作运行时实际状态。

| 展示项 | 计划属性与语义 | 边界与未决项 |
|---|---|---|
| 视频输出 FPS（估算） | `estimated-vf-fps`：视频滤镜链输出 FPS；未使用滤镜时对应解码器输出，按最近 10 帧时长估算 | 不是显示器刷新率、源文件标称 FPS、Flutter UI FPS，也不保证等于实际呈现 FPS。帧丢弃、精确 seek、时间戳不准确会使估算失真；应明确显示“估算”，能力缺失显示 `--` |
| 丢帧数 | `decoder-frame-drop-count` 与 `frame-drop-count` 分开读取，分别表示 decoder 丢帧与 VO 丢帧 | 两者来源与触发条件不同，不合并成不透明总数、不混入 `vo-delayed-frame-count`（延迟帧）。按当前媒体/引擎会话呈现，切片或重建引擎后不沿用旧计数；属性缺失不显示成 0 |
| 硬件解码 | `hwdec-current`：当前实际使用的硬件解码器；值 `no` 表示软件解码，未加载解码器时不可用 | 不读取配置 `hwdec=auto` 来假称已硬解。显示实际值或软件回退状态；不可用显示 `--`，并说明当前无法判断 |
| 渲染耗时 | 对支持的 VO 读取 `vo-passes` 中 pass 的 `last`、`avg`、`peak`（单位 ns，显示时换算 ms） | mpv 明确说明并非所有 VO 都实现 `vo-passes`，返回结构应按 `MPV_FORMAT_NODE` 读取且 pass 数量可变。只呈现确有数据的 pass；不是 Flutter 渲染耗时、整帧端到端时延或所有平台 GPU 时间。具体 pass 选择、统计窗口及 Flutter texture/render API 可用性必须后续探测，未经实机证据不得承诺 |
| 缓存量/时长 | `demuxer-cache-state` 父 node map 中的 `fw-bytes` 为从当前解码位置向前缓冲的数据包字节估算；`demuxer-cache-duration` 为 demuxer 前向缓存时长近似值 | 实现读取方式固定为先读取 `demuxer-cache-state`（`MPV_FORMAT_NODE` map），再从 map 中取得 `fw-bytes`；不可把 `fw-bytes` 当作顶层子属性直接读取。该值是粗略估值，不含当前解码位置之后所有可 seek 范围；duration 估算不可靠且可缺失。因此标为缓存估算/约值，不能承诺为精确可播放时长。不得显示 `file-cache-bytes` 作为此项，它是磁盘文件缓存（如启用），不是内存/网络前向缓存 |
| 音画同步偏差 | `avsync`：mpv 最近一次音画同步差值，单位秒，展示为带符号毫秒 | 音频或视频禁用时不可用。正负分别代表哪一侧领先，必须在实机校验后才可解释或加方向标签；不能拿用户设置的 `audio-delay` / `sub-delay` 代替实际观测值 |

`perf-info` 明确不作为数据源：mpv 手册指出查询会触发内部采集、可能拖慢播放器、会重置内部状态，且不支持属性变更通知，并建议仅由内建 stats 脚本使用。不得以轮询它实现本面板。

## 状态与生命周期

- 打开播放信息面板后按约 1 秒节奏更新局部统计快照；关闭/卸载面板即停止周期读取，不因面板关闭继续后台采样。
- 采样器及 UI 与当前 `PlaybackSession` / engine generation 绑定；换片、播放资源替换、切画质导致的会话替换或引擎重建时，先清空旧快照再读取新会话，不能把旧媒体计数带入新条目。
- 暂停与缓冲状态应使用现有播放状态单独标识。它们不是统计值为零的理由；零值表示有效零，缺失/不支持/当前不可用显示 `--` 并可解释能力限制。
- seek、暂停/恢复、缓冲开始/结束、换片和切换普通/转码资源均不得误归因、触发额外 seek 或让采样器使用旧 session 数据。
- 本地与 Emby 的展示相同；个别来源、VO、renderer、操作系统或 Flutter texture/render API 不支持的属性，逐项标为不可用，不静默替换成推断值。

## 当前进展：实现及 Windows 验证完成（2026-10-16）

- 六项统计的后端与播放信息面板实现已完成。`flutter test --no-pub --reporter expanded` 全量 **743 passed / 6 skipped**，39 秒，exit 0；新加的 12 项测试（后端 8 项、两个 UI 测试文件共 4 项）均包含在全量通过结果中。
- `flutter analyze --no-pub` 无问题；`dart format` 覆盖 `lib`、`test`、`integration_test` 共 296 个文件，0 改动；`git diff --check` 通过。
- Windows Profile 的真实 `MediaKitVideoEngine` texture 专项 **1 个业务 case 通过**，构建 22.1 秒；覆盖暂停只读（`time-pos`、`hwdec`、`audio-delay` 不变）、seek、同引擎重开及 dispose 安全。测试使用循环 HTTP Range 合成资源验证前向缓存，不等同真实 Emby 服务验收；禁用音轨（`aid=no`）时 AV sync 按不可用处理。普通静音或音量为 0 不会令 AV sync 失效。面板生命周期测试初版 FakeAsync I/O 卡住已改用 `tester.runAsync`，最终单项通过。
- 当前能力报告为 `FPS=true`、`decoderDrops=true`、`outputDrops=true`、`hardwareDecoder=true`、`renderPasses=false`、`forwardBytes=true`、`forwardSeconds=true`、`avSync=true`、`httpForwardCacheAvailable=true`。`forwardBytes` 已修正为从 `demuxer-cache-state` 的 `MPV_FORMAT_NODE` 原生 map 读取 `fw-bytes`，并由 Windows Profile 专项复验通过。能力报告中硬解读取接口可用，不等于本轮已验证实际硬件解码正在启用。
- 当前 Windows Profile texture VO 未提供 `vo-passes`，前端对此显示 `--`；这仅说明当前 VO/运行环境未提供该属性，不代表所有 VO/平台均不支持。不得切换 VO 或修改播放选项以强行采集。
- 正式版 `flutter build windows --release --no-pub` 使用 production `lib/main.dart` 构建成功，用时 46.1 秒；新 Flutter 产物 `apps/client/build/windows/x64/runner/Release/data/app.so` 时间为 2026-10-16 16:41:09.4849365 +08:00，大小 11,846,536 bytes。runner 无需重链，因此 `reelnest.exe` 仍保留较早时间戳；这不影响新 `app.so` 已纳入此次 Release 的结论。`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 2026-10-16 16:41:35.4687675 +08:00 通过：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。
- 本轮未改动存储行为、配置导入或 schema；未提交、未推送。上述 Windows 构建与 smoke 不覆盖真实 Emby 服务、实际硬件解码启用状态、Emby 转码与切画质、macOS/Linux 原生、可见 UI/视觉和长时间性能验收；这些边界仍待后续实机验证。

### 后续 Windows texture / 整合回归（2026-10-16）

- 既有 `playback_stats_test` 在 Windows Profile 真实 texture 回归通过；报告中 `estimatedFps`、`decoderDrops`、`outputDrops`、`hardwareDecoder`、`forwardBytes`、`forwardSeconds`、`avSync` 与旧库结果一致；`renderPasses=false`，HTTP cache 读数可用。此结果不改变“当前 texture VO 不提供 `vo-passes`”的能力边界，不得切换 VO 强制采集。
- 随播放器画面显示批次重跑全量 Flutter 测试：**768 passed / 7 skipped，52 秒**。该全量结果覆盖整合批次。
- Windows Release `flutter build windows --release --no-pub --target lib/main.dart` 成功，用时 44.4 秒；2026-10-16 23:30:33.7136344 +08:00 五秒 smoke 为 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。随后 CMake pinned archive 下载重试逻辑更新，增量 Release 再次成功，用时 45.1 秒；2026-10-16 23:39:17.7412689 +08:00 五秒 smoke 同样为 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。手工预置固定 archive 的新缓存独立验证通过（archive/DLL hash、提取和保留其他 DLL）；冷缓存网络下载因连接中断未验证。profile texture stats 回归结果与旧库一致，`renderPasses=false`，HTTP cache 可用；不切换 VO 强采。
- 七项显式 native DLL 专项、严格暂停 resize（`osd-dimensions=480x270`）及 analyze 均通过；304 个 Dart 文件格式检查 0 改动，diff-check 通过。真实 Emby、转码/切画质、macOS/Linux、可见 UI/视觉和长时间性能仍待验证。

## 当前建议顺序（非锁定排期）

当前建议顺序曾为先推进字幕样式与音频延迟/同步，再实施实时统计，之后画面调优；该顺序从未是用户锁定的前置条件。用户最新指令已授权本轮开始六项统计实现，因此当前按本轮授权推进，不等待其他模块完成。

## 验收规划

实现后至少覆盖以下场景；测试结果应分别标记 Dart/组件、原生平台、真实来源及视觉验收，不以单个平台推断三端完成：

- 六项属性全部可用、部分不可用和完全不支持；有效零值与缺失值在模型、格式化和 UI 上可区分。
- 硬解正常启用、`hwdec-current=no` 软件解码、切换硬解配置后的真实回退；UI 依据当前状态而非配置选项。
- decoder/VO 丢帧字段分别呈现，`vo-delayed-frame-count` 不混入；换片及引擎重建后旧会话计数不会残留。
- 标准本地、Emby 原始 HTTP(S)、Emby 转码/缓存资源，以及 seek、暂停/恢复、缓冲/恢复、换片和切画质边界。
- 面板开启时约每秒更新；关闭/卸载后停止采样；长时间开启不造成整页高频重建、播放操作延迟或明显额外性能开销。
- 普通 VO 与 Flutter texture/render API 的属性可用性逐平台探测，尤其 FPS 与 `vo-passes` 渲染耗时；不能支持时显示能力限制，并留下 Windows、macOS、Linux 分平台证据。
- 原版播放信息面板与同数据、窗口尺寸和缩放条件下的 UI 对照；真实播放场景的统计含义及空值/错误状态检查。

## 非目标

- 不提供整机任务管理器式性能仪表、网络测速、带宽探测或历史趋势图。
- 不改变播放画质、硬件解码、缓存策略、音频/字幕延迟，不重启、不 seek、不写入服务器。
- 不把估算输出 FPS称为实际显示 FPS；不把 VO 帧 drop 与 decoder drop、delayed frame 混合；不把 pass 耗时称作 GPU/整帧耗时；不把磁盘文件缓存混作前向播放缓存；不把用户延迟设置伪装成实际 AV sync。
- 不持久化统计数据，不将其纳入自动诊断日志或上传。

实现前须按项目约束阅读原版播放信息面板实现、相关依赖和测试；若原版缺少对应统计能力，保留此用户明确授权的新增范围，但将平台差异与 UI 对照结果分开说明。

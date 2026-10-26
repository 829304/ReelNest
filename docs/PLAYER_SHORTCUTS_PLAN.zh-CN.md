# 播放器自定义快捷键迁移计划（2026-10-23）

状态：**代码、自动化验证及 Windows Release/smoke 通过；平台与产品验收仍未完成。** 本批已接入领域模型、repository、session、router、设置 UI 和失焦取消保护。2026-10-24 最终串行全量测试 **941 passed / 1 optional benchmark skipped（3 分 11 秒）**；五个定向测试文件 **60 passed / 13 秒**（包含新增 model/session/router 14 项及设置 UI 3 项）；Windows Profile GPU/SW 实际 mpv integration 两例通过（模拟按键驱动真实 mpv）。`dart analyze` 无 issues、374 个 Dart 文件 format 检查 0 changed、`git diff --check` 无空白错误。Windows Release 构建 **79.9 秒成功**，smoke 正常响应并关闭、退出码 0。仍待 macOS/Linux、精确视觉、实体键盘及真实 Emby 验收；鼠标和触控板输入设置另列后续批次。计划文件名保留 2026-10-23，最终验证日期为 2026-10-24。

## 原版依据

按项目原版基线核对：

- `Sources/MediaLibCore/Models/AppSettings.swift`：`VideoKeyboardShortcut`、`VideoPlayerShortcutAction`、默认绑定、解析/冲突/设置/重置逻辑（约 498–900、1976–2041 行）。
- `Sources/MediaLib/Views/KeyCaptureView.swift`：播放器窗口内按键监听、录制焦点和修饰键捕获。
- `Sources/MediaLib/Views/PlayerView.swift`：动作执行约 1409–1553 行；设置列表约 4721–4785 行；单行动作编辑/冲突确认约 5385–5549 行。

对应固定源码版本：[`64f8ee2`](https://github.com/829304/MediaLib/tree/64f8ee258d87389414d5e06740a89f59cd857612)。原版行为以这些实现和默认值为准，不以当前 Flutter 行为反推。

## 批次范围

- 本批迁移视频播放器动作快捷键设置与窗口内处理；`openExternal`（系统外部播放器）在本批排除，后续迁移已获批准，范围见[系统外部播放器专项计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。
- 本批覆盖快捷键读取/显示、录制、单动作替换、冲突确认与转移、清除、单项恢复默认、全部恢复默认、偏好持久化以及按键触发已存在动作。
- 不迁移鼠标滚轮、手势、触控板动作或灵敏度。它们是后续独立批次。
- 不新增全局热键服务，不注册系统级快捷键，不更改操作系统键盘或辅助功能设置。快捷键只在当前播放器窗口有效。

### 源码动作数核对说明

指定基线 `64f8ee2` 的 `VideoPlayerShortcutAction` 枚举实有 60 个 case；排除本批的 `openExternal` 后，本批为 59 个动作。当前 domain 已包含这 59 项，无漏动作。`openExternal` 随已批准的[系统外部播放器专项](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)迁移，不在快捷键基础批次提前接入。

## 原版规则（必须保持）

- 同一动作可有多个默认快捷键，界面以分隔形式全部显示。编辑录制新组合键时，目标动作绑定替换为该新键（不是默认集合上追加）。
- 录到已由其他动作使用的组合键时，先显示冲突动作及确认；“替换”将该键从其他动作移除后再分配给目标动作；“取消”不修改绑定。不得静默抢键。
- 查找按键对应动作按动作枚举顺序返回首个匹配项。正常编辑会清理冲突，但加载旧/异常状态时也应保持既定首匹配语义。
- 清除某动作写入空列表 override，使该动作保持未设置；单项“默认”删除该动作 override 并恢复原版默认值；“恢复全部默认”清空 override map，而非持久化展开后的默认表。
- 对记录的组合键做与原版一致的标准化/去重和无效键过滤；只校验当前配置中的损坏值与未知动作键，不提供旧版持久化兼容分支。按键未匹配时放行，不吞系统/菜单键，不发出错误提示音。快进长按行为：首次 `Down` 仍执行普通快进；系统 `Repeat` 开始时切到临时 3×；`KeyUp` 恢复触发前的播放倍速，不写入倍速记忆。窗口失焦、弹窗/独立 modal route 抢占输入或映射被改动时也必须结束长按并恢复原倍速，避免倍速状态卡住。
- 持久化 modifier 精确为四种：Command、Option、Control、Shift。Windows/Linux 默认绑定中的原版 Command 等效映射为 Ctrl、Option 等效映射为 Alt；这是默认键位跨平台适配，不改变实际录制事件。实际录制的 Meta/Command 修饰键按捕获到的 modifier 单独记录，不应被默认适配规则改写。

## 焦点与安全边界

- 仅当前 key 播放器窗口处理快捷键；非播放器窗口、失焦播放器、其他播放器窗口事件均放行。不得创建全局事件监听/系统热键注册来扩大作用范围。
- 输入路由保留文本编辑、快捷键录制和独立 modal route 的优先级：文本输入与当前弹窗/独立路由优先消费按键，不得被播放器快捷键吞掉；录制状态只由录制组件消费新组合键，不同时触发播放动作。录制取消/失焦/窗口切换应退出录制且不产生意外绑定。
- 处理并消费的播放器按键仅执行已迁移的现有动作；未映射键、系统快捷键以及不属于当前窗口的事件原样放行。

## 偏好存储

- 使用现有 `player_preferences` 中 `global.videoKeyboardShortcuts`，值为动作到组合键列表的 override map；不加数据库表、列或 schema 版本迁移。
- 默认快捷键来自代码定义，首次使用/全部恢复默认应呈现原版默认绑定。清除某动作写该动作的空列表 `[]`，保留“明确禁用此动作绑定”的 override；单项重置只删除该动作 override、其余 override 仍保存；全量重置在内存清空 map，并从持久化中 `DELETE global.videoKeyboardShortcuts` 键，缺失键读取时回到代码默认值（不是写 `{}`）。
- 保存失败应按设置系统既有错误处理展示，不得假报保存成功；加载失败不能静默覆盖/清除已有配置。
- 新增设置沿用既有一次 SQL 偏好快照读取；`playback_read_performance_test` 单元 fixture 的 SQLite 计数由 28 次降为 1 次，该计数不是 Profile 原生性能测量。`global.videoKeyboardShortcuts` 的 JSON 读取上限为 128 KiB；损坏值回退默认但不顺手重写/覆盖数据库内容。
- 更新操作按 serial queue 保存；保存失败须保留完整旧映射。每次 runtime delta 在串行操作执行时基于最新值计算，不能用过期快照覆盖较新绑定。
- 长按临时 3× 仅改当前播放 runtime rate，不进入倍速记忆。媒体切换也必须释放 hold 并恢复播放速率。
- 设置行、Tab 切换及应用失焦均应取消未完成的录制，不保留悬挂的录制状态或意外写入。

## 自动化验收要求

- 动作白名单逐项审计：domain 中 59 项与原版 `VideoPlayerShortcutAction`（60 cases）对应，唯一不在本批的是 `openExternal`；不得漏项或提前迁移外部播放动作。
- 默认快捷键 fixture：多绑定显示/解析、非 Mac Command→Ctrl 和 Option→Alt 默认适配、Meta 捕获独立、当前配置的损坏值/未知动作键校验；不提供开发期历史配置兼容迁移。
- 冲突状态：无冲突直接设置；有冲突先提示；确认后目标替换、原动作只移除该键且保留其他键；取消不变；同一键多处冲突时结果符合首匹配顺序。
- 清除、单动作 reset、全量 reset：验证空列表 override；单项只删除该动作 override并保留其他配置；全量删除 `global.videoKeyboardShortcuts` 偏好键，缺失键读取默认；检查数据库持久化/重启恢复。
- 输入事件：仅播放器 key window、其它窗口放行；文本框和独立 modal route 不误触；录制期间不触发播放动作；取消录制/窗口切换正确清理状态；未知键放行。快进覆盖首次 Down 普通 seek、Repeat 临时 3×、KeyUp/失焦/modal route/改映射恢复原倍速且不写记忆。
- 动作映射：白名单每个动作都触发现有业务行为一次且参数符合原版；截图、A–B、轨道、窗口/画面、seek 百分比等边界分别检查；不借此改变动作本身。
- Windows/macOS/Linux 的修饰键显示、捕获和播放窗口焦点需分别验证；Windows/macOS/Linux UI 和原版分组/顺序/状态逐项目视对照。

## 验收记录（实现后补）

| 项目 | 状态 | 证据 |
|---|---|---|
| 59 项 domain 动作白名单与原版 enum | 初步核对通过 | enum 60 cases；排除 `openExternal` 后 domain 包含 59 项，无漏动作 |
| 既有播放器/轨道/偏好定向回归 | 阶段通过 | 5 个专项文件 60 passed / 13 秒，覆盖既有 playback/read-performance/tracks/pref 回归；不等同最终全量 |
| 偏好存储与保存失败保护 | 自动化通过 | 现有一次 SQL 快照；仅 `global.videoKeyboardShortcuts` 的 JSON 读取上限为 128 KiB；坏值回默认不重写；串行保存失败保留完整旧映射、runtime delta 按最新值计算。`playback_read_performance_test` 单元 fixture 中 SQLite 计数为 28→1，不是 Profile 原生性能测量 |
| 本批新增 model/session/router 与设置 UI | 阶段通过 | 14 项 + 3 项，共新增 17 项；录制行/Tab/应用、窗口与 row focus 失焦取消保护已覆盖 |
| Windows Profile GPU/SW 实际 mpv integration | 通过（两例） | `flutter drive --no-pub --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/video_keyboard_shortcuts_test.dart`，`apps/client/build/keyboard-shortcuts-native.log`；验证本地合成 Matroska 双音轨/双字幕、remap N、Right 旧绑定失效、seek/rate、字幕与音轨切换、hold 3×→恢复 1.25 且保留倍速记忆。使用 Flutter 合成按键驱动真实 mpv，不是用户实体键盘/OS 原生输入；非真实 Emby。 |
| 全量测试、格式检查与静态分析 | 通过（2026-10-24） | `flutter test --no-pub --concurrency 1 --reporter expanded --dart-define=REELNEST_MPV_PATH=...`：**941 passed / 1 optional benchmark skipped，3 分 11 秒**；日志 `apps/client/build/keyboard-shortcuts-full-tests-serial.log`。`dart analyze` 无 issues；374 个 Dart 文件 format 0 changed；`git diff --check` 无空白错误。并发 4 的运行曾有一个 `video_display_native` 进程未完成；串行最终全量包含该 native 用例并全部通过，未改测试逻辑。 |
| Windows Release/smoke | 通过（2026-10-24） | `flutter build windows --release --no-pub` 79.9 秒、exit 0；日志 `apps/client/build/keyboard-shortcuts-release.log`。`data/app.so` 为 2026-10-24 09:35:37 +08:00、12,583,816 bytes。五秒 smoke exit 0；`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`，检查时间 09:36:11 +08:00；报告 `apps/client/build/smoke/release-startup.json`。Flutter 的升级提示未触发 SDK 升级。 |
| macOS/Linux 与平台/UI 验收 | 待验收 | macOS/Linux、可见 UI/精确视觉及用户实际键盘输入未验收 |
| 默认绑定、平台修饰键映射 | 自动化阶段通过，实机待验收 | 定向及全量测试通过；各桌面平台实体键盘/修饰键显示与捕获仍需实机验证 |
| 冲突确认、替换/取消与首匹配 | 自动化阶段通过 | 定向及最终全量通过；跨平台可见 UI 与实机交互仍待验收 |
| 空列表清除、单项/全量恢复及持久化 | 待验收 | 待存储与重启恢复证据 |
| 窗口/文本/弹窗/录制焦点规则 | 自动化阶段通过，实机待验收 | 录制行、Tab、应用/窗口与 row focus 失焦取消保护已覆盖；人工桌面交互仍待 |
| Windows/macOS/Linux 原生与原版 UI 对照 | 待验收 | 分平台补实际构建/运行与可见 UI 证据 |
| `openExternal` | 本批明确排除，下一专项待实现 | 随已批准的系统外部播放器专项迁移；本快捷键批次不实现入口 |
| 鼠标/触控板输入 | 后续独立批次 | 本计划不定义或实现 |

## 相关状态索引

- [播放器状态总表](PLAYER_STATUS.zh-CN.md)
- [统一实现状态盘点](IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md)
- [后续外部文件/URL 与播放器范围](IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md#建议分阶段路线)

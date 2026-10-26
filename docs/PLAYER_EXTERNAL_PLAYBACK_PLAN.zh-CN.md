# 系统外部播放器迁移计划（2026-10-24）

状态：**Windows 自动化、Release 与 smoke 验证通过；真实外部播放器及跨平台验收仍待完成。** 最终文件版本专项 23 项通过（后端 15、前端 7、Windows 原生 helper 1）；Dart 全量串行回归 991 passed / 2 conditionally skipped，`dart analyze` 无问题，397 个 Dart 文件 format 检查 0 changed。全量回归包含后端 15 项，但 UI 损坏恢复补丁在全量文件载入后才加入，因此以最终文件专项 23 项记录专项状态，不把不同批次数字累计相加。两个条件跳过项为未指定 native helper 路径的条件用例和可选 benchmark。Windows Profile integration `integration_test/external_playback_test.dart` 已通过：33.4 秒构建、约 4 秒运行，1 个业务用例通过（harness 含 teardown 显示 +2）；退出码 0，driver 显示 All tests passed。日志含既有 integration 插件未检测警告。测试覆盖真实 secondary Flutter engine 经 IPC 调用主 service 与原生 helper、本地中文及含 `&` 路径、HTTP(S) 启动成功、立即失败安全回传，并确认 sources/media/playback_states/media_activity 均未写入。helper 不播放视频、不联网，不代表真实 Emby/VLC/系统默认关联验收。Windows Release 构建 49.1 秒成功，`Release/data/app.so` 时间为 2026-10-25 14:30:05 +08；五秒 smoke 于 2026-10-25T14:30:30.3321959+08:00 通过，窗口响应正常、正常关闭、ExitCode 0。证据日志位于 `apps/client/build/`，不提交。macOS/Linux 目前仅有源码接入，未实机验证。

## 原版行为基线

固定参考 MediaLib `64f8ee2`，只读核对：

- `Sources/MediaLibCore/Services/ExternalPlayerService.swift`：发现已知播放器、显示可用播放器、使用系统默认应用或指定应用打开媒体；远程地址只按 HTTP/HTTPS 处理。
- `Sources/MediaLib/App/AppState.swift`：`openExternally(_:)` 先尝试取得已缓存的可播放媒体项，再按视频/音乐分别读取播放器路径并交给服务打开；本专项只迁移视频分支。
- `Sources/MediaLibCore/Models/AppSettings.swift`：视频默认播放器有 `builtIn` / `external` 两种选择，另存可选外部播放器路径。
- `Sources/MediaLib/Views/SettingsView.swift`：视频播放器设置提供默认模式切换；选择“系统”时显示系统播放器路径/应用选择控件。媒体库使用的“设为默认”动作涉及系统文件关联，明确不迁移。
- `Sources/MediaLib/Views/PlayerView.swift`：播放器右键菜单的“用系统播放器打开”、播放错误提示中的外部打开动作，以及 `VideoPlayerShortcutAction.openExternal` 调用 `openExternally(_:)`。

## 本专项范围

### 必须迁移

- 视频默认播放器偏好：`builtIn` 使用 ReelNest 内置播放器，`external` 交给系统默认视频播放器；偏好应按原有设置保存和恢复。
- 在外部模式下显示系统默认播放器状态，并允许用户选择具体应用路径；选择应用的文件/应用包过滤、取消与路径失效反馈按原版行为迁移。更换默认播放器路径不得破坏已有视频偏好。
- 保留系统默认应用打开能力；明确选择的外部应用优先按该路径启动。系统或自选应用不存在、打不开或拒绝启动时，应给出明确错误。
- 迁移视频播放器右键入口、原版播放错误提示中的外部播放器入口，以及 `VideoPlayerShortcutAction.openExternal`（原版 60 个动作中的该项）。默认播放器偏好影响普通播放启动；显式右键/播放器入口及快捷键也必须可以按其产品语义请求外部播放。
- 资源交接覆盖本地文件、已挂载/网络卷文件、ReelNest 已缓存的媒体文件，以及 Emby HTTP(S) 媒体 URL。交接应优先使用有效的缓存文件，避免外部播放器访问已失效或不必要重拉的远程地址；缓存不存在时，Emby HTTP(S) 交接使用可访问的媒体 URL。
- 启动失败恢复：错误不得让内置播放器或当前媒体会话进入半关闭状态；若是从播放中显式切换，原内置会话按原版允许的失败语义保留可用。启动失败立即释放本次外部交接持有的缓存保护。
- 外部播放器没有通用的播放完成/退出通知。缓存保护采用保守生命周期：当前实现保持缓存 lease/文件 scope 至 ReelNest 退出，定时续期；不得仅凭 `open` 返回、外部窗口关闭猜测播放结束或提前释放。ReelNest 退出后停止续期，由缓存租约本身的到期/清理机制回收。ACK 超时导致启动结果不确定时同样保留资源至 ReelNest 退出。此生命周期已有专项覆盖，完整回归仍在进行。

### 明确不在本专项

- 音乐外部播放器、音乐默认播放器偏好及音乐专属入口；音乐保持独立后续模块，不随视频服务顺手迁移。
- 注册 Windows 文件类型/协议、写注册表、设置系统默认视频应用或宣称支持双击文件启动。设置页原版“设为默认”系统关联能力不属于本专项。
- 播放进度回读、外部播放器状态监控、播放完成检测、自动关闭内置会话或自动跳到下一条。系统没有通用结束通知时，不猜测用户是否播放完毕。
- 将内置播放器的九种网络 scheme 透传给外部播放器。外部服务当前基线只接收 HTTP(S) URL；本专项远程资源范围是 Emby HTTP(S)。其他协议应安全失败并说明不支持，不改写成 HTTP，也不调用内置协议能力冒充外部支持。
- 为外部播放器另建队列、遥控、字幕/音轨控制或额外的产品入口。

## 平台与实现约束

- 原版 `ExternalPlayerService` 使用 macOS `NSWorkspace`。当前代码按平台接入：macOS 通过 `NSWorkspace` 原生通道发现 IINA/VLC/Movist Pro/QuickTime 并支持默认或指定 `.app`；Windows 以 argv 启动自选 `.exe`，未选择应用时读取扩展关联并使用 `ShellExecute`，检测到关联回指 ReelNest 时拒绝循环打开；Linux 以 argv 启动自选程序或 `xdg-open`。自选应用路径校验和媒体/应用文件访问授权已接线。以上是代码状态，尚未等同各平台原生验收通过。
- `global.externalVideoPlayerSettings` 存于现有 `player_preferences`，默认 `builtIn`，本轮没有 schema 变更。`PreferredPlaybackLauncher` 每次按新加载的设置路由普通 library/transient 播放；显式 external 请求直接走外部服务，不被默认 mode 再次覆盖。
- 外部资源由主 engine 的 `ExternalPlaybackService` 持有。播放器子窗口通过 IPC 委托主 engine 打开，避免子窗口关闭时过早释放外部播放所需租约或文件访问权限。缓存路径按 location 去重，重复 lease 释放按实现去重。
- 已缓存的 Emby 项优先取得缓存路径和 lease；未取到可用缓存时再准备 Emby HTTP(S) 地址。本地/挂载文件和 transient file 使用文件访问 scope/bookmark；外部应用路径在 macOS 通过其 bookmark 获得访问权限。音乐与非 HTTP(S) 远程地址在服务层拒绝。
- 启动管理使用平台应用 argv/系统 API，不拼接 shell 命令，不注册系统文件关联或修改默认关联。Windows 对系统默认关联只读检查，避免关联回指 ReelNest 造成循环打开。真实 Windows helper 已验证 `Process.start` 将完整 Unicode 文件路径及含 `&` 等参数的 HTTP(S) URL 作为单个 argv 传递；helper 只捕获参数、不读取网络或播放媒体，不能替代 VLC 或系统默认关联验收。立即非零退出能提示启动失败。
- 当前实现目标优先完成启动交接与缓存安全，不探测外部播放器进程、播放状态或播放位置。
- 当前实现每 30 秒续期缓存 lease；缓存 lease 的存储期限由缓存层控制。已知启动失败立即释放；成功启动后 lease/文件 scope 持有至主 service dispose，并在应用关闭时释放。外部播放器没有通用结束通知，不因打开调用返回或窗口/子窗口关闭推测播放完成。主进程关闭期间排队请求拒绝已有回归覆盖。
- 外部启动请求有确认超时。超时可能代表外部程序已启动但 ACK 丢失；当前实现保守保留相应缓存 lease/文件访问资源至主程序关闭，并向用户提示“无法确认是否启动”，不假装启动成功，也不猜测 EOF。ACK 超时保留、进程关闭释放已有后端专项覆盖；各平台真实 ACK 超时行为、崩溃后的 lease 回收仍待实测。
- 错误反馈不得泄露 Emby URL 中的凭据、令牌或敏感查询参数。日志和错误消息不得持久化完整鉴权 URL。
- 默认外部播放和显式外部打开都不得把未知媒体写成新的媒体库条目；内置临时播放数据库隔离规则继续适用。

## 验收清单

- 设置默认模式在 `builtIn` / `external` 间切换，重启后保留；外部模式的系统默认与自选播放器显示、选择、取消、失效路径和启动失败均有覆盖。
- 显式入口覆盖右键菜单、播放错误反馈入口、`openExternal` 快捷键及普通播放采用外部默认设置的行为。
- 本地文件与挂载路径可交接；Emby 缓存有效时外部播放器读取本地缓存副本且租约阻止清理；缓存无效/缺失时使用 Emby HTTP(S) 地址；鉴权与失败消息不泄露秘密。
- 外部启动成功后缓存租约按计划续期；不因启动 API 返回成功、焦点变化或界面关闭立即释放；启动失败立即释放；停止续期后由租约过期机制清理。测试通过时钟/租约状态验证边界，不依赖猜测外部播放完成。
- 进行中的内置播放器不因外部交接失败而损坏；播放进度不从外部播放器回读、不因本次迁移新增后台同步。
- Windows、macOS、Linux 分别记录自动化和原生启动验证；真实 Emby、非 HTTP 服务器协议、实体选择/键盘操作及原版 UI 逐项视觉验收分别记录，Release/smoke 不替代这些验收。

## 当前验收记录

| 项目 | 状态 | 证据 |
|---|---|---|
| 产品范围与原版入口核对 | 完成（计划阶段） | `ExternalPlayerService.swift`、`AppState.openExternally`、`SettingsView`、`PlayerView`、`VideoPlayerShortcutAction.openExternal` |
| 最终文件专项回归 | 通过（23 项） | 后端 15 + 前端 7 + Windows 原生 helper 1；覆盖最终 UI 损坏恢复补丁 |
| Dart 全量串行回归 | 通过（991 项） | 2 项条件跳过：未指定 native helper 路径的条件用例、可选 benchmark。全量包含后端专项 15 项；不与专项数相加 |
| 静态分析与格式 | 通过 | `dart analyze` No issues found；397 个 Dart 文件 format 0 changes |
| Windows 原生启动 helper | 通过（含在专项 23 项内） | 已验证 Unicode 路径、完整 URL 单 argv 和立即非零退出错误；不代表真实 VLC 或系统默认关联验收 |
| Windows Profile integration | 通过 | `integration_test/external_playback_test.dart`：33.4 秒构建、约 4 秒运行，1 个业务用例通过；secondary engine → IPC → 主 service → 原生 helper。校验中文/`&` 本地路径、HTTP(S) 启动及立即失败回传；相关数据库表均为 0。driver All tests passed/exit 0；既有插件未检测警告不改变通过结果。helper 不播放视频、不联网，不代表真实 Emby/VLC/系统默认关联验收 |
| Windows Release/smoke | 通过 | Release 49.1 秒；`Release/data/app.so` 时间 2026-10-25 14:30:05 +08；五秒 smoke 2026-10-25T14:30:30.3321959+08:00，窗口响应正常、正常关闭、ExitCode 0。日志 `apps/client/build/smoke/release-startup.json` |
| macOS/Linux 原生启动与 UI 视觉验收 | 未验证 | 目前只有源码接入，未在本机实测 |

本轮其余构建/测试证据位于 `apps/client/build/external-full-tests.log`、`external-final-targeted.log`、`external-native-ipc.log`、`external-analyze-final.log`，均为本机运行证据，不随源码提交。最终 7 项前端专项覆盖损坏设置显式重置入口；设置写入失败时保留旧值并允许重试的回归属于后端 15 项专项。

## 相关文档

- [自定义播放器快捷键计划](PLAYER_SHORTCUTS_PLAN.zh-CN.md)
- [本地文件与网络 URL 临时播放计划](PLAYER_TEMPORARY_PLAYBACK_PLAN.zh-CN.md)
- [播放器实现状态](PLAYER_STATUS.zh-CN.md)
- [项目范围与路线](PROJECT_SCOPE.zh-CN.md)

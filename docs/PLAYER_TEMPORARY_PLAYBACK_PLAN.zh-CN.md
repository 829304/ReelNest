# 本地文件与网络 URL 临时播放计划（2026-10-24）

状态：**用户已批准；当前代码及 Windows 自动化验证通过。稳定偏好版本完整回归 968 passed / 1 optional benchmark skipped（5 分 14 秒，exit 0）；之后补齐网络串流提示 Escape 取消行为，最终 UI 专项 4 文件 21 项/4 秒通过，不将两次结果相加。最终 `dart analyze lib test integration_test` clean、386 个 Dart 文件 format 0 changed、diff-check 通过。Windows Release 67.2 秒成功；五秒 smoke 通过（隐藏窗口响应、正常关闭、退出码 0）。** macOS/Linux 原生、实体拖放/文件选择器、真实服务器非 HTTP 协议及精确 UI 视觉仍待实机验收。当前批次范围仅覆盖视频：已入库文件复用原条目；未入库本地视频及允许协议的网络视频 URL 作为临时单项交给内置播放器；另实现用户当前明确批准的拖入本地视频临时播放。音乐独立模块以后续计划为准，不纳入本批。系统外部播放器和 `openExternal` 已另获批准，边界与下一阶段状态见[外部播放器专项计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。

## 原版源码依据

固定参考 MediaLib `64f8ee2`，只读核对：

- `Sources/MediaLib/App/AppState+ExternalPlayback.swift`：`presentBuiltInPlayer`、`playExternalFiles`、`playNetworkStream`、`videoQueueItems`。
- `Sources/MediaLib/App/MediaLibApp.swift`：`MediaLibAppDelegate.application(_:open:)` 暂存系统传入的文件 URL；SwiftUI 场景就绪后注册回调并消费启动前暂存的文件。
- `Sources/MediaLib/App/MediaLibApp.swift` 的“播放”菜单：`打开网络串流…`，快捷键 Command+Shift+O。
- `Sources/MediaLib/Views/ContentView.swift`：`NetworkStreamPromptSheet` 的输入、提交、取消和错误反馈。
- `Sources/MediaLib/App/SystemDefaultPlayerRegistrar.swift`：原版视频打开扩展名列表；本批只沿用其视频文件类型边界，不迁移系统默认应用注册能力。
- `Sources/MediaLib/App/AppState.swift`：`openExternally(_:)` 属于外部播放器后续能力，本批不迁移。

## 批次范围

### 本批实现

- 未入库本地**视频文件**临时播放，以及已入库本地文件身份匹配与既有播放流程复用。
- 原版列出的 16 个视频扩展名：`mp4`、`mkv`、`avi`、`mov`、`m4v`、`wmv`、`flv`、`ts`、`m2ts`、`webm`、`mpg`、`mpeg`、`rmvb`、`rm`、`3gp`、`vob`。不把原版音乐扩展名合并到本批。
- 通过本地视频文件选择器选择单个视频并以内置播放器播放。
- 通过原版“播放 → 打开网络串流…”入口，粘贴 URL 并以内置播放器播放；只接受 `http`、`https`、`rtsp`、`rtmp`、`rtp`、`mms`、`srt`、`udp`、`ftp` 九种 scheme。
- 用户明确批准的本地视频拖放：主桌面内容区和播放器窗口两个投放区域均可启动临时播放。首页原有文本模块排序拖放语义保持不变；除这两个区域外不增加其他投放目标/功能。
- 未入库文件/网络 URL 的临时身份、单项队列、播放进度 no-op 与数据库隔离。

### 明确不在本批

- 音乐临时播放。原版 `playExternalFiles` 可按音乐扩展名转到音乐播放，但本阶段按用户范围只迁移视频；不得将非视频文件误送入视频播放器。
- 系统外部播放器、外部播放器配置 UI 和 `VideoPlayerShortcutAction.openExternal` 不属于本批；后续专项见[系统外部播放器迁移计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。
- 注册 Windows 文件类型/协议、写注册表、修改系统级文件关联，或宣称 Windows 便携包支持双击关联启动。macOS/Linux 同样不在本批注册系统文件关联。
- 文件夹导入、媒体库扫描、目录遍历、多个文件生成播放列表、将文件加入媒体库、拖入网络 URL、在主桌面内容区/播放器窗口之外增加投放目标，以及额外的加载提示/播放入口。
- 修改照片、音乐、服务器同步、已有数据库结构或便携存储约束。

## 原版行为与迁移约束

### 本地文件

- 原版收到系统文件打开事件时只保留 file URL；`playExternalFiles(_:)` 选取收到顺序中的首个本地 URL。本批沿用单个视频临时播放语义，不把多个路径解释为播放队列。
- 已索引文件按来源与 `relative_id` 精确查询并复用库内身份，保留原媒体 ID、续播/已看状态、系列身份与原剧集后续队列；不得构造重复条目或只凭 basename 误匹配。
- 未匹配时，播放会话构造临时项并使用单项队列。临时项不插入媒体表、不触发媒体扫描、不创建本地或远程媒体记录；未知 ID 的播放进度写入必须为 no-op。离开临时项后不留下虚假媒体库状态。
- 临时身份不得直接使用或暴露 URL/本机路径；对文件使用规范化路径、对串流使用 trim 后的原始 URL，分别加 `file`/`stream` 类型前缀后计算稳定 SHA-256 标识（64 个十六进制字符）。标识用于临时目标区分及按原版偏好键恢复；JSON 跨窗口传递时重新计算并校验标识与目标匹配。不得持久化原始 URL、路径或令牌。
- 本批文件输入通过本地文件选择器与用户批准的窗口拖放接入；不要求接入 OS 冷启动 open-files / CLI 文件事件。
- 原版 `MediaLibAppDelegate.application(_:open:)` 可处理 OS open-files 调用；ReelNest 尚未接入 OS 冷启动 open-files/CLI 直接启动事件，单列为后续迁移项，不纳入本批验收。系统文件关联/注册表均不注册，也不以此作为测试前提。
- 拖放只处理获批的主桌面内容区与播放器窗口两个目标。首页编辑模式用于重排模块的文本拖放保持原状；不得把它替换为媒体导入，也不增加其他 drop 目标/行为。

### 网络 URL

- 保留原版独立网络串流 sheet：输入框支持提交、播放与取消；空白输入不提交。URL 首尾空白先去除，再解析并小写化 scheme。
- 仅放行白名单：`http`、`https`、`rtsp`、`rtmp`、`rtp`、`mms`、`srt`、`udp`、`ftp`。缺失/非法 URL 或未允许的 scheme 显示安全的“无法播放”反馈，不启动播放；不扩展到 `file`、`javascript`、自定义协议或未知 scheme。
- URL 作为本次播放地址，不写媒体库或持久化来源。为临时项生成非库身份；未知 ID 的播放进度写入必须 no-op，不向 Emby 上报，不污染库索引。
- 默认使用内置播放器。不要悄悄把网络串流切至系统外部播放器；失败提示及播放准备/取消应遵循原版会话规则。

## 存储、安全与桌面约束

- 临时媒体身份仅用于活跃会话，不新增 SQLite 表/列/schema，不写入 `remote_media_metadata`、媒体详情、播放历史或凭据存储。
- URL/路径须按敏感播放输入处理：不得写诊断日志、错误原文或持久化设置；UI 显示标题按原版从最后路径分量取名，必要时以 host/受控显示值回退，避免展示鉴权参数。
- 便携存储规则继续优先：不得写注册表、用户/系统环境变量或系统文件关联。Windows 临时媒体路径需在打开文件权限有效期间使用；路径/访问权限失败必须安全失败，不得回退到 AppData 或外部副本。macOS/Linux 遵守项目既有授权目录与平台存储约定。
- 不改变本机已有数据，不自动清库；临时文件播放不得复制/移动/删除用户源文件。

## 当前实现与验证状态

- `TransientPlaybackTarget` 携带播放所需的 `location`，并以稳定 SHA-256（64 个十六进制字符）作为不透明临时身份，不以 URL 或文件路径作为媒体 ID。文件键由 `file` 前缀和规范化路径计算；串流键由 `stream` 前缀和 trim 后的原始 URL 计算。跨窗口 JSON 传递时校验重算后的 ID 与目标一致；原始路径/URL/令牌不持久化。临时目标使用单项队列。
- 已索引路径通过来源 `relative_id` 精确查询并复用库条目身份与续播信息。内置播放器继续共用现有 `PlaybackSession`、引擎、设置、字幕及预览链路，不另建播放器。
- 临时媒体不写播放进度或活动记录，未知媒体 ID 也不插入媒体索引。音轨、字幕及倍速偏好按原版 `TrackPreferenceStore` / `PlayerPreferencesRepository` 使用稳定临时 ID 持久化，恢复后继续生效；不得将它们降级为仅内存状态。未知媒体没有满足外键的媒体行，因此临时章节/书签 marker 仅保存在内存，换片/关闭时清理，不尝试写入 marker 表。跨窗口只传递本次会话需要的目标/bookmark；标识必须重算校验，敏感原始地址不得持久化。
- macOS 文件访问接入自有临时 scope 通道：持有 URL 与 lease；bookmark 仅内存交接；预览另持 lease，避免异步取帧期间访问权限提前释放。已补 `user-selected.read-write` 与 app-scope bookmark entitlement，并在主/子 engine 注册。以上为源码接线说明，不能代替 macOS 原生构建、权限生命周期及实际播放验收；当前验证主机为 Windows。
- 拖放使用锁定版本 `desktop_drop 0.8.0`，适配项目 Flutter/Dart SDK 3.47.6；未升级 SDK。未改系统默认应用关联、Windows 注册表或协议注册。
- 稳定 SHA-256 临时身份使用 `crypto 3.0.7`；该版本从已锁定的传递依赖提升为直接依赖，没有升级依赖版本。
- 前端还补入未知时长直播流的播放/暂停控制及临时播放信息中的来源显示；新旧接口保持兼容。
- 稳定偏好键修正后 backend 10 项 + UI 7 项 + shortcut 2 项，共 **19 项全部通过（2 秒）**，日志 `apps/client/build/transient-stable-preferences-tests.log`。覆盖稳定身份、重开后的偏好恢复与敏感数据脱敏。
- 原 `Command+Shift+O` 网络串流菜单保留；`transient_playback_shortcut_test.dart` 合成键盘自动化验证 Windows `Ctrl+Shift+O` 与 macOS `Meta+Shift+O` 通过；实体键盘操作仍待验收。
- 原版网络串流提示可通过 Escape 取消；ReelNest 在 opening 状态保持不可取消，闲置输入时 Escape 关闭提示。Enter 提交行为保持原样。
- 稳定偏好版本定向回归 backend 10 + UI 7 + shortcut 2 共 19 项通过（2 秒）；之后 Escape/Enter 最终 UI 专项 4 个文件 21 项通过（4 秒），日志 `apps/client/build/transient-final-ui-tests.log`。新增 UI 用例不并入此前完整回归数字。
- 稳定偏好版本完整 Flutter 回归 **968 passed / 1 optional benchmark skipped（5 分 14 秒，exit 0）**，日志 `apps/client/build/transient-full-tests-stable.log`。Windows native 多窗口 Profile 4 秒 exit 0，通过本地/HTTP 播放、失败回滚、媒体进度零写入及正常关闭；日志 `apps/client/build/transient-native.log`。最终检查 `dart analyze lib test integration_test` clean、386 个 Dart 文件 format 0 changed、`git diff --check` 通过。Windows Release 67.2 秒成功，日志 `apps/client/build/transient-release-final.log`，产物 `app.so` 时间 `2026-10-24T21:29:03.7480828+08:00`、大小 12,665,736 bytes。五秒 smoke 于 `2026-10-24T21:30:40.8223378+08:00` 通过：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。macOS/Linux 原生、实体拖放/文件选择器、真实服务器非 HTTP 协议及精确 UI 视觉验收仍待实机。

## 自动化验收要求

- 库内路径匹配：同 ID 条目复用，保留播放进度、已看与剧集队列；相同路径不生成重复库项。
- 未入库视频：临时单项正确播放，不进入 SQLite/inventory/同步队列；未知 ID 的播放进度写入 no-op；退出后不残留活动条目或伪造记录。
- 文件输入：本地视频选择器；主桌面内容区与播放器窗口拖放；非本地 file URL、非视频、空/失效路径安全拒绝；单项处理，不误建多文件队列。不能通过系统文件关联注册来让测试通过。
- URL sheet：菜单入口与 Command+Shift+O；合成键盘专项已覆盖 Windows Ctrl+Shift+O 与 macOS Meta+Shift+O；验证提交/取消/空输入，九个允许 scheme 分别解析并准备内置播放；拒绝无效 URL、无 scheme、未许可 scheme 和 `file`。验证 URL 不进入数据库、凭据、日志或 Emby 上报；实体键盘仍待验收。
- URL sheet 键盘：Enter 提交；Escape 仅在闲置输入状态取消，opening 状态不可取消；最终补充 UI 专项覆盖键盘交互。
- 会话切换：每次临时播放取消陈旧的远程播放准备；切换已入库/临时项目时旧资源正确释放；关闭、停止及播放失败后状态一致，不改既有播放器控制行为。
- 拖放边界：分别验证主桌面内容区与播放器窗口对获批本地视频的拖放临时播放；首页文本模块排序保持原状；OS 冷启动 open-files/CLI、音乐/文件夹/多文件/URL 不属于本批，不得变成隐式新增功能。
- Windows/macOS/Linux 分别验证路径授权与可见 UI；自动化/Profile/Release、真实媒体来源和原版视觉对照分级记录，不相互替代。

## 验收记录

| 项目 | 状态 | 证据 |
|---|---|---|
| 当前代码定向回归 | 通过 | backend 10 + UI 7 + shortcut 2，共 19 项/2 秒，含 Windows `Ctrl+Shift+O` 与 macOS `Meta+Shift+O` 合成键盘测试；日志 `apps/client/build/transient-stable-preferences-tests.log` |
| 最终 Escape/Enter UI 专项 | 通过 | 4 个文件 21 项/4 秒，含 `transient_playback_shortcut_test.dart`；日志 `apps/client/build/transient-final-ui-tests.log`。该补充回归不并入 968 项完整测试数字 |
| Windows 原生 Profile 多引擎/窗口 | 通过 | 64 字符稳定身份跨 engine 传递验证通过；4 秒，exit 0，日志 `apps/client/build/transient-native.log` |
| 稳定偏好版本全量 Flutter 测试 | 通过 | 968 passed / 1 optional benchmark skipped（5 分 14 秒，exit 0）；最后 Escape/Enter 两项 UI 补丁之后另跑专项回归，不相加推算全量 |
| 最终 Dart 分析与格式检查 | 通过 | `dart analyze lib test integration_test` clean；386 个 Dart 文件 format 0 changed；`git diff --check` 通过 |
| Windows Release 构建 | 通过 | 67.2 秒，日志 `apps/client/build/transient-release-final.log`；`app.so` 时间 `2026-10-24T21:29:03.7480828+08:00`、12,665,736 bytes |
| Windows 五秒 smoke | 通过 | `2026-10-24T21:30:40.8223378+08:00`：隐藏窗口响应、正常关闭、退出码 0 |
| 平台及人工验收 | 待验证 | macOS/Linux 原生、实体拖放/文件选择器、真实服务器非 HTTP 协议、实体键盘操作、精确 UI 视觉仍待实机验收 |

## 相关文档

- [统一实现状态盘点](IMPLEMENTATION_STATUS_2026-10-23.zh-CN.md)
- [共用视频播放器状态总表](PLAYER_STATUS.zh-CN.md)
- [当前阶段记录](NEXT_STAGE.zh-CN.md)

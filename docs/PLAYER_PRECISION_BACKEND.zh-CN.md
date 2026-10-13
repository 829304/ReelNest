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

## 验证与边界

- 130 项相关 Dart 回归通过，覆盖播放、设置、字幕音轨、队列、Emby 播放与画质缓存，以及新增标记/循环规则。
- 2026-10-13 前端接入后，播放器 presentation 静态分析无问题；`playback_test.dart`、`player_precision_test.dart`、`emby_quality_panel_test.dart` 共 38 项定向回归通过，其中组件测试覆盖标记弹层、进度条刻度、A–B 状态、右键菜单、单片循环、前后逐帧及快捷键。
- Windows 使用已有 `libmpv-2.dll` 与本地生成的 Matroska，真实验证章节读取、前后逐帧、A–B 区间回跳与整片循环；未依赖用户 Emby 或媒体文件。
- 原生测试：`test/player_precision_native_test.dart`，通过 `--dart-define=REELNEST_MPV_PATH=<libmpv绝对路径>` 启用；默认跳过，避免普通单元测试隐式依赖本机构建。
- Windows 原生检查与 Flutter 组件测试是两条独立证据；当前仍不代表真实窗口渲染或原版像素级视觉验收完成。
- 真实 Emby 转码服务器、macOS/Linux 原生、三桌面端实体键盘及鼠标右键交互仍需后续验收。
- 本批不实现预览缩略图、片头片尾识别/跳过、在线字幕或其他高级设置；模型保留原版标记类型不等于对应执行功能已迁移。
- 原版标记面板中的片头/片尾边界编辑、自动候选采用/忽略与跳过策略未包含在本批后端接口中，因此前端没有伪造入口；待对应执行链路迁移后再按原版接入。

### 2026-10-13 提交前复查

环境为本机 Windows，范围为本次提交的高级播放后端、首批播放器入口、侧栏/主题与文档改动。

- 修复视频未成功打开时按 `B` 或执行 A–B 菜单动作仍可能读取空 A 点的问题，并加入打开失败后的快捷键组件回归；提示入口同时防止组件销毁后更新状态。
- `flutter analyze --no-pub` 无问题；`dart format --output=none --set-exit-if-changed lib test` 检查 232 个文件，无格式改动；`git diff --check` 通过。
- `flutter test --no-pub --concurrency=1`：587 项通过，1 项真实 mpv 测试按默认条件跳过。
- `flutter test --no-pub --concurrency=1 --dart-define=REELNEST_MPV_PATH=<Release/libmpv-2.dll 的绝对路径> test/player_precision_native_test.dart`：单独启用的 1 项通过，使用生成媒体验证章节读取、前后逐帧、A–B 与整片循环。
- `flutter build windows --release --no-pub --target lib/main.dart` 成功，产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。
- `scripts/windows-smoke.ps1 -ObservationSeconds 5`：Release 隐藏窗口创建、五秒响应、正常关窗通过，退出码 0；本次输出无数据库关闭异常。
- 原生播放测试不使用用户服务器或媒体；启动检查使用本机现有应用数据，不执行媒体扫描或播放写回。未完成真实 Emby 全流程、播放器可见画面/实体键鼠、滚动性能、macOS/Linux 原生及原版 UI 对照验收。

# Emby 播放与进度同步（E3）

日期：2026-10-09。完成 E1 连接、E2 同步/浏览之后，本批接通电影/剧集的鉴权播放、续播、队列和进度上报。仍是一个 Flutter 应用，不依赖 MediaLib 或 ReelNest Server。本批没有连接用户的真实 Emby，也没有删除开发数据库、提交或推送。

## 原版依据与实际行为

对照 `Sources/MediaLib/App/EmbyService.swift` 的 `streamURL`、`reportPlayback`、`validateSession`，`AppState.swift` 的 `prepareEmbyItemForPlayback`、`syncEmbyPlayback`、`importEmbyItems`、`preservingLocalTraceForDisabledEmbySync`，以及 `MpvPlayerController.reportPlayback`、`RemoteTraceSyncMode` 和 `EmbyServiceResourceURLTests`。

- 视频使用 `Videos/{itemID}/stream[.container]`，保留代理路径，携带 `Static=true`、稳定 `DeviceId`、当前 `api_key` 和可用的 `MediaSourceId`。每次打开前验证会话，401 最多重新认证并重试一次；403/限制接入不会循环登录。容器只允许安全的扩展名，其他值回退无扩展名 stream。
- 主窗口只向独立播放器传来源/条目身份。播放器从自己的系统安全存储读取来源会话，在内存中准备资源，复用现有 media_kit/libmpv。带令牌的 URL 不写入 SQLite、普通配置或窗口参数。
- 电影详情播放按钮、系列首集入口、剧集双击播放已启用；已有队列、上一集/下一集、EOF 行为和轨道控制继续复用。音乐播放不在本批电影/剧集验收范围内。
- 续播读取当前公共播放记录，沿原记忆开关及默认回退 5 秒规则。远程条目不进行文件存在性/挂载或同名字幕探测；播放器内嵌轨道仍由 mpv 提供。
- 每个成功解码的条目分配独立 PlaySessionId，发送 `Sessions/Playing`、`Progress`、`Stopped`，携带 ItemId、MediaSourceId、PositionTicks、RunTimeTicks、IsPaused 和 `PlayMethod=DirectStream`。Ticks 为 100 ns；204 视为成功，不强制解码 JSON。
- 常规观察按原版 15 秒节流；暂停/继续、跳转触发强制状态更新。最多保留一个进行中的进度请求及最新强制状态，避免高频时钟造成无限队列。慢请求期间的连续跳转合并为最新一次；关闭/切集的停止状态包含最终位置，EOF 使用完整时长。
- 每次上报总预算 5 秒，覆盖同来源排队、凭据读取、401 重新登录/重试及 HTTP；外层 Future 到时立即失败，同时取消令牌以中止实际 HTTP，过期排队任务稍后到达队首时不会发送。上报失败提示非致命信息，本机记录继续保存。停止会等待已有顺序上报收尾；多次请求的合计时间可能超过单次预算。
- `VideoEngine.open` 只准备暂停资源，不自行播放。切集期间候选引擎在旧视频停止上报结束前保持暂停；提交新引擎、应用音轨/字幕等偏好、播放器页面完成一帧后才调用 play。复用隐藏播放器时先显示/聚焦，避免等待不可见窗口的帧。
- 切集失败继续保留原解码器、队列与控制，不上报失败目标已经开始。关闭时先保存本机进度；保存失败仍可重试，直到保存成功或用户明确放弃进度后才释放解码器并结束远程会话。

## 三种痕迹同步模式

| 模式 | 完整同步时的服务器记录 | 本机播放记录 | 向服务器上报 |
|---|---|---|---|
| 双向（默认） | 导入并替换 | 保存 | 开启 |
| 仅从服务器同步 | 导入并替换 | 保存，下次完整同步按服务器状态覆盖 | 关闭 |
| 不同步 | 已有本机记录保留；首次导入仍使用服务器初始状态，与原版相同 | 保存 | 关闭 |

E2 完整快照事务现在同时提交播放位置、时长、已看状态及服务器最近观看时间。失败/取消仍回滚整批；来源间严格隔离。服务器没有最近观看日期时，用当前非空列中的 0 表示未知，仓储读取为 null，不伪造本机观看时间。播放记录 provider 订阅来源变更，完整同步后刷新当前详情里的记录。没有新增历史 schema 或升级分支。

## 实现位置

- `api/emby/emby_playback.dart`：播放阶段与短生命周期资源模型。
- `api/emby/emby_client.dart`：鉴权 stream 地址和有界、可取消的播放上报。
- `features/sources/data/emby_connection_repository.dart`：会话验证、按来源刷新、播放资源准备及上报策略。
- `features/sources/data/source_repository.dart`：完整同步事务内导入公共播放记录。
- `features/playback/application/playback_session.dart`：文件/远程资源分派，串行切换/记录、有限上报队列及关闭收尾。
- `features/playback/presentation/player_window_app.dart`：播放器窗口独立装配连接服务；不从主窗口传凭据。
- `player/media_kit_video_engine.dart`：已有网络资源解码；远程解码错误使用通用文案，不向 UI 回显鉴权 URL。

## 验证与边界

本批新增 15 项回归（最终结果见当日测试记录），覆盖协议路径/参数/204/Ticks、来源凭据刷新、续播、时钟节流、快速跳转合并、三种痕迹模式、非致命 403、401 单次重试、保存失败关闭重试、失败切换、剧集 EOF、来源同步后 provider 刷新和无响应上报取消。

Windows 原生连接场景增加自生成 24 秒 AVI，由本机 HTTP 模拟服务器按 Range 提供，验证真实 mpv 鉴权网络解码、服务端 12 秒记录回退续播、跳转至 14 秒、停止上报及真实 SQLite 保存。原有字幕/音轨、多窗口和 EOF 场景继续回归。没有使用用户影片或真实服务器；Windows 结果不代表 macOS/Linux 实机通过。

收尾冒烟发现原主窗口通过 `windowManager.destroy` 直接发送 WM_QUIT，正式版退出发生 flutter_windows.dll 原生异常。改为完成持久化后撤销关闭拦截、移除监听并请求正常窗口关闭；修复后主窗口启动/响应/正常退出检查通过，退出码 0。

E1–E3 基础电影/剧集闭环已接通，不能据此宣称原版所有 Emby 功能完成。服务器外置字幕、收藏/手动已看操作、完整详情、图片预热/磁盘缓存、音乐及其他原版远程功能仍在迁移清单；没有添加转码协商或新码率策略。完整侧栏库树、材质/字体/图标/动效及 macOS UI 一比一对照尚未验收。

用户确认顺序为“先实现 Emby，再实现首页”。本轮首页仍为占位页，不会展示已经同步的媒体。先收尾原版 Emby 基础操作与字幕，再开始按原 `HomeView` 源码迁移首页、最近添加和继续观看；不能把占位页当作已完成首页，也不能要求用户额外连接 ReelNest Server。


## 后续静态复核修复：播放启动顺序与排队预算

用户指出两个真实缺口：旧引擎停止上报前候选 `open` 已自动播放；以及计时器虽然取消令牌，却不能让等待 `_serial` 前序任务的 Future 及时返回。这两个问题已修复，上面的资源准备/预算描述对应修复后的实现；此前 221 项测试未覆盖这两个边界。

新增 4 项回归：慢停止上报与画面挂接双重阻塞下候选保持暂停；同来源前序任务成功/失败两种情况下，上报都先超时且后来不会补发；前序任务仍阻塞时播放器仍可按上报预算完成释放并保存本机记录。Windows 原生另补暂停准备阶段时钟不自行前进，以及隐藏窗口恢复后切集。

组件测试同步调整为在播放准备完成后再渲染最终控制状态，然后发送鼠标事件；没有取消原有音轨/队列交互断言。

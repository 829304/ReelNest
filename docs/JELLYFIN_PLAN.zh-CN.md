# Jellyfin 基础连接器闭环计划（2026-10-26）

状态：**Jellyfin 基础闭环已实现并完成 Windows Release/smoke；定向回归与 Windows Native 验证通过。真实 Jellyfin、macOS/Linux 与人工视觉验收仍待。** 本文定义第一批 Jellyfin 基础连接器闭环，不表示这些后续验收已完成。先用受控 HTTP fixture 验证；目前不要求用户提供真实 Jellyfin 地址。

本轮交付目标限于 Jellyfin 基础视频来源闭环，不宣称所有高级能力、真实 Jellyfin 服务兼容或 Windows/macOS/Linux 三桌面端均已验收。共享实现沿用 Emby 命名的类/目录，不代表 Jellyfin 对应路径未接线；目前基础共享 cache、user flag、quality 路径已有接线，仍以本计划范围和验收记录为准。

## 目标与范围

完成独立 Jellyfin 来源的基础使用闭环：添加来源、登录、凭据/会话恢复、选择媒体库、侧栏导航、分页浏览、搜索、详情、媒体播放、音轨/字幕选择、续播、切换下一集及进度上报。

Jellyfin 必须保留独立的 `MediaSourceKind.jellyfin`、连接器 provider、凭据类型、显示名称与 `jellyfin://source` 身份前缀。共享协议代码可复用 Emby 兼容链路，但不能把 Jellyfin 来源改存为 Emby，也不能因内部类名为 Emby 就在 UI、通知、任务、日志或错误中把 Jellyfin 显示成 Emby。

## 原版行为基线

只读核对原版 MediaLib 固定参考版本 `64f8ee2`：

- `Sources/MediaLib/App/AppState.swift` 的 `connectJellyfinServer` 将 `provider: .jellyfin` 交给 `connectRemoteMediaServer`；同一连接流程调用共享 `EmbyService.authenticate`，随后保存来源、连接器凭据/账户并导入所选库。
- `RemoteConnectorProvider` 为 Jellyfin 独立生成 `jellyfin` scheme、credential kind、显示名及来源路径 `jellyfin://<host>/<sourceID>`。`EmbySession.provider` 保留 provider 值，session 稳定 ID 前缀也对 Jellyfin 使用 `jellyfin`。
- `Sources/MediaLib/App/EmbyService.swift` 的远程请求、条目分页及流地址有 Emby/Jellyfin 共享实现。通用错误信息必须中性，不得在 Jellyfin 操作失败时泄漏“Emby”文案；具体平台名由上层 Jellyfin UI 提供。
- `Sources/MediaLib/Views/SourcesView.swift` 为 Jellyfin 提供独立来源项、连接状态、服务器配置与登录并同步动作；`ContentView.swift` 侧栏分组按来源身份显示。原版 UI 结构、导航与状态需直接对照 Swift 源码，不以当前 Emby 页截图代替。
- `AppState.swift` 的 Emby-compatible 分支说明部分流媒体播放、进度上报、转码取流共享协议；这不意味着来源身份、认证会话、API 差异或全部 UI 可以抹平。

## ReelNest 接入原则

- 采用已批准的公共协议扩展路径：现有 Emby 公共协议分支接受 `kind.isEmbyCompatible`，由 `emby` / `jellyfin` 两种来源共用适用的 API、分页、播放和上报逻辑。
- 来源 `kind`、来源 URI/scheme、服务端 provider、credential kind、稳定 ID 前缀、服务器和用户会话始终按 Jellyfin 独立保存与恢复；不得伪装为 Emby 来源。
- 不复制整套 Emby 实现形成平行连接器。共享层只收敛真实一致的协议行为；有差异时通过 provider-specific 配置/映射处理，不写“Emby 专用”文案或硬编码 Emby 假设。
- 登录失败、认证过期、连接限制、超时和协议错误文本保持服务端中性；用户可见标题与操作名显示 Jellyfin。内部旧类名或目录名不作为产品品牌文案。
- 凭据和 token 继续使用既有安全凭据存储，按来源身份隔离；不进入 SQLite 普通偏好、URL、错误原文或诊断日志。数据库保持当前 `schemaVersion=1`；不加开发中间版本迁移、历史 schema 分支或兼容测试，不自动清理本机数据。

## 协议差异盘点与验证

不能只凭 Emby-compatible 判断所有行为相同。后端须对照原版连接器并用 fixture 核查以下协议面，确认证据后再决定是否需要 Jellyfin 专属分支：

| 协议面 | 核对内容 |
|---|---|
| 身份认证与会话 | 用户认证请求/响应、访问 token、用户 ID、客户端身份头、401/403、认证恢复、credential kind 隔离；Jellyfin HTTP API 使用 `Authorization: MediaBrowser ...`，Emby 行为保持原样 |
| 地址与来源身份 | HTTP/HTTPS、反向代理前缀、规范化服务器地址；`jellyfin://` 稳定来源路径及独立 source ID |
| 媒体库与分页 | 获取用户可见 Views、媒体库选择/重选、collection type、过滤字段、分页参数、总数/空库/缺字段/重复项 |
| 搜索与详情 | 用户作用域、媒体类型、详情字段和 TV 季集父子关系映射；搜索只限已选来源，不跨来源串数据 |
| 图片 | 图片 URL、token/鉴权头、尺寸参数、缺图/失败和同源缓存；不把 token 写进持久化远程元数据 |
| 播放与轨道 | 资源 URL、direct/transcode 参数、音轨/字幕选择、续播 seek、切集和服务端可播放资源错误 |
| 播放状态上报 | start/progress/stop 的字段、session/device ID、服务端接受范围和重复/停止行为 |

### Jellyfin 官方认证与端点约束

已核对 Jellyfin 上游当前 `master` 的认证实现：标准 `Authorization` 请求头会被解析，`MediaBrowser` scheme 可用；`ApiKey` 查询参数始终受支持。旧 `X-Emby-Token` 和小写 `api_key` 查询参数仅在服务端启用 legacy authorization 时读取；`X-Emby-Authorization` 与 `Emby` authorization scheme 同样受 legacy 开关控制。因此本连接器对 Jellyfin 普通 HTTP API 请求使用 `Authorization: MediaBrowser ...`，对无法附加普通请求头的 mpv/外部播放器及下载资源 URL 使用 `ApiKey` 查询参数。Emby 继续保持当前 `X-Emby-*` 请求头与 `api_key` 查询参数行为，不随 Jellyfin 调整。

稳定版 OpenAPI 文件已从 Jellyfin 官方 fra1 mirror 下载并核对，`info.version` 为 `12.3.0`。本连接器使用 Jellyfin 现代路由：`UserViews`、`Items`、`Items/{id}`、`UserFavoriteItems/{id}`、`UserPlayedItems/{id}`，按接口要求传 `UserId` query；不依赖 `/Users/{userId}/Items/...` 旧路由。当前上游 `UserLibraryController` 也将该旧路由标记为 obsolete 并从 API explorer 隐藏。Emby 继续使用现有路由，不随 Jellyfin 调整。

当前连接配置身份键为 `connector.jellyfin.uuid`。共享 session 必须同时保存/校验来源 `kind`；凭据工厂内部沿用 `emby.source.<uuid>` 命名只是共享实现细节，凭据仍按 UUID 隔离且读取时校验 provider kind，不代表 Jellyfin 与 Emby 共用身份。该功能不新增表、不改 schema，也不做数据迁移。

认证规则以官方源码及稳定版 OpenAPI 为依据。实施方最终回报：15 个共享协议受影响文件定向回归 255/255 通过（28 秒，exit 0），其中含 Jellyfin 17 项；覆盖 Emby 连接、浏览、详情、字幕、播放、分页、取消、cache、offline、library、home、search、source 等领域。该组不含 EmbySync 文件。另一个 4 文件同步/界面回归组 61/61 通过（17 秒，exit 0），覆盖 EmbySync、EmbyNavigation（6 种平台/主题变体）、EmbySidebarStartup、JellyfinFrontend 2 项。独立的 Jellyfin UI 2/2 通过；不同测试组有重叠或不同范围，分别记录、不相加。之前中断的 43 项运行无最终结果，不纳入计数。Windows Native 真实 mpv 业务用例 1 项通过（Profile 构建 39.0 秒；harness 总计 2 项，含 tearDown 1 项，exit 0）：生产库页、空搜索/重新匹配、详情演员、实际 mpv Range 流、seek、服务器字幕加载及 stop report 均已走通。测试显式注册/注销 `TextInput` harness；这不是产品行为变更，也不构成人工硬件键盘/IME 验收。Native 日志有未影响业务用例的 Flutter accessibility AXTree 告警，辅助功能尚未验收。Windows Release 44.1 秒构建成功；标准 EXE 位于 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。AOT `data/app.so` 为 2026-10-26 21:25:55 +08、12,977,032 bytes，已核验包含 Jellyfin brand mark、`UserViews` 与 `UserFavoriteItems`。五秒 smoke `apps/client/build/smoke/release-startup.json` 于 21:27:44 +08 正常响应、正常关闭、ExitCode 0。最终 analyze clean、421 个 Dart 文件 format 0 changed、diff-check 通过；本批未运行全量 Flutter 测试。真实 Jellyfin 服务、macOS/Linux 与人工视觉验收仍待。

实施中发现反向代理 base URL 带路径且不以 `/` 结尾时，相对 `DeliveryUrl` 会错误地按文件名语义解析并丢失 base path；生产代码已修正为以 base path 目录语义解析，严格字幕 fixture 已通过。此项说明只记录实施方测试回报，不代表全部反向代理形式均已覆盖。

真实 Jellyfin 服务地址尚未提供，本阶段先以本机 loopback/mock fixture、临时 SQLite 和安全凭据替身建立证据。fixture 验证不等于真实服务器兼容验收；后续收到真实测试环境后另记实测结果。

## UI 与功能验收范围

- 来源添加页按原版展示 Jellyfin 独立入口、服务器地址/用户名/密码、连接中与登录并同步状态；校验禁用、空地址和失败状态逐项对照 `SourcesView.swift`。
- 重启后恢复 Jellyfin 来源、凭据与会话；来源选择、移除、改选库及重新认证不影响同地址 Emby 来源或其他账号。
- Jellyfin 侧栏与选库列表独立命名，支持分页浏览、搜索、详情、海报与加载/空/错误状态；条目身份始终携带 Jellyfin `sourceId`。
- 播放可取得真实 fixture 媒体地址，进行续播、音轨/字幕选择、切换下一集，并按原版会话模式上报开始/进度/停止；异常或认证失效应保留合理的重试/重新登录路径。
- 逐项对照原版布局、控件顺序、尺寸、间距、颜色、图标、加载反馈和交互状态。真实可见 UI / 人工精确视觉验收单独记录。

## 明确不在本批

- Emby 既有行为重设计、移除或改名；Jellyfin 不得覆盖或合并现有 Emby 来源。
- Plex、ReelNest Server、网络设备挂载、WebDAV、TMDB 刮削、云备份及未授权元数据服务。
- 音乐资料库浏览/队列/音乐播放（音乐作为独立后续大模块）；此处的音轨选择仅指视频播放中的音轨。
- 照片/相册模块；影视海报、背景图、演员图等媒体 artwork 仍适用既有范围。
- 仅凭协议兼容性宣称完整 Jellyfin 全功能或跨平台验收完成。

## 当前分工与验证记录

- 后端负责人：扩展共享 Emby-compatible 公共协议链路，维持独立 Jellyfin kind/provider/URI/凭据/ID，核对协议差异，完成认证、同步、分页、详情、播放/轨道和播放状态上报。
- 前端工程师：对照原版 Sources / Sidebar / Library / Detail / Player 页面迁移 Jellyfin 独立入口、会话恢复、选库、浏览搜索详情和播放反馈。
- 当前已收到定向回归、基础 UI、analyze、format、Windows Native 真实播放链路、四文件同步/界面回归及 Windows Release/smoke 结果。本批未运行全量 Flutter 测试。真实 Jellyfin、macOS/Linux 与人工视觉验收仍待；各测试组分开记录，不将范围不同或重叠的计数相加。

| 验收项 | 状态 | 证据与边界 |
|---|---|---|
| 原版 Swift 与协议差异盘点 | 进行中 | 已核对连接委托、共享 `EmbyService`、独立 provider/source scheme 与中性错误要求；UI 对照及剩余协议面仍待回报 |
| 官方认证/端点证据 | 已完成 | 上游认证源码与稳定版 OpenAPI 12.3.0 已核对；现代 Jellyfin 路由与 `UserId` query 已明确，Emby 路由保持不变 |
| Jellyfin/共享协议定向回归 | 通过 | `apps/client/build/jellyfin-regression-final.log`：15 个文件/领域共 255/255（28 秒，exit 0），含 Jellyfin 17 项；覆盖连接、浏览、详情、字幕、播放、分页、取消、cache、offline、library、home、search、source，不含 EmbySync。先前中断的 43 项不纳入 |
| 同步与界面四文件回归 | 通过 | `apps/client/build/jellyfin-ui-regression-final.log`：61/61（17 秒，exit 0），覆盖 EmbySync、EmbyNavigation（6 种平台/主题变体）、EmbySidebarStartup、JellyfinFrontend 2 项；和 255 项组分开统计，不求和 |
| Emby 行为回归基线 | 通过 | 独立基线 `build/jellyfin-emby-baseline.log`：37/37；与 255 项分组独立记录，不求和 |
| Jellyfin UI 定向测试 | 通过 | `apps/client/build/jellyfin-frontend-final.log`：2/2；仅证明该组自动化通过，不代表人工视觉验收 |
| 静态分析与格式 | 通过 | `apps/client/build/jellyfin-analyze-final.log` 全项目 analyze clean；`apps/client/build/jellyfin-format-final.log` 421 个 Dart 文件 format 0 改动 |
| 反向代理相对 DeliveryUrl | 定向通过 | 修正带路径且无尾斜线 base URL 的相对解析；严格字幕 fixture 通过，未证明所有代理配置 |
| Jellyfin UI 与原版对照 | 自动化部分通过，人工验收待完成 | 2/2 UI 定向测试通过；自动化不能替代原版逐项视觉对照与人工验收 |
| Windows Native 真实播放链路 | 通过 | `apps/client/build/jellyfin-native-final-pass.log`：业务 1 项通过，harness 共 2 项（含 tearDown 1 项），exit 0；生产库页→搜索/重新匹配→详情演员→真实 mpv Range 流→seek→服务器字幕→stop report。显式注册/注销测试输入 harness；不代表人工硬件键盘/IME、辅助功能或完整 UI 验收。日志有不影响用例的 Flutter accessibility AXTree 告警 |
| Windows Release 与启动关闭 smoke | 通过 | Release 44.1 秒成功，`apps/client/build/jellyfin-release.log`；标准产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。AOT `data/app.so`：2026-10-26 21:25:55 +08，12,977,032 bytes；已核验包含 Jellyfin brand mark、`UserViews` 与 `UserFavoriteItems`。五秒 smoke `apps/client/build/smoke/release-startup.json`：2026-10-26 21:27:44 +08，响应正常、正常关闭、ExitCode 0。最终 `git diff --check` 通过；本批未跑全量 Flutter 测试 |
| macOS/Linux、真实 Jellyfin 与人工视觉验收 | 待后续验收 | 不由当前 fixture、Windows Native 或自动 UI 测试推定通过 |
| 真实 Jellyfin 服务 | 待后续验收 | 服务器地址暂未知；当前无需用户提供 |

## 参考源码

- 原版：`Sources/MediaLib/App/AppState.swift`（`connectJellyfinServer`、`connectRemoteMediaServer`、会话恢复、Emby-compatible 分派）。
- 原版：`Sources/MediaLib/App/EmbyService.swift`（provider-aware 认证、session、媒体请求和错误）。
- 原版：`Sources/MediaLib/Views/SourcesView.swift`、`ContentView.swift`（添加来源表单、连接反馈与侧栏）。
- Jellyfin 官方上游当前认证实现：[AuthorizationContext.cs](https://raw.githubusercontent.com/jellyfin/jellyfin/master/Jellyfin.Server.Implementations/Security/AuthorizationContext.cs)（`Authorization`/`MediaBrowser` 与 legacy authorization 解析规则）。
- Jellyfin 官方上游用户媒体路由：[UserLibraryController.cs](https://raw.githubusercontent.com/jellyfin/jellyfin/master/Jellyfin.Api/Controllers/UserLibraryController.cs)（旧 `Users/{userId}/Items` 路由标记 obsolete）。
- Jellyfin 官方稳定版 API 契约：[jellyfin-openapi-stable.json](https://fra1.mirror.jellyfin.org/main/files/releases/openapi/jellyfin-openapi-stable.json)。当前文件 `info.version=12.3.0`；上游 `master` 源码可能先于稳定发行版变化，端点实现应以目标稳定版 OpenAPI 和 fixture 响应复核。
- 本批实施回报的稳定 OpenAPI 副本：`build/jellyfin-openapi-stable.json`（`info.version=12.3.0`）；最终回归、同步/界面组、独立 UI、分析、格式、Windows Native、Release 与 smoke 证据：`apps/client/build/jellyfin-regression-final.log`、`apps/client/build/jellyfin-ui-regression-final.log`、`apps/client/build/jellyfin-frontend-final.log`、`apps/client/build/jellyfin-analyze-delivery.log`、`apps/client/build/jellyfin-format-delivery.log`、`apps/client/build/jellyfin-native-final-pass.log`、`apps/client/build/jellyfin-release.log`、`apps/client/build/smoke/release-startup.json`。Emby 37 项基线日志：`build/jellyfin-emby-baseline.log`。按测试组分开记录，不把范围不同或重叠的计数相加；此前中断/失败日志不作为最终通过证据。
- ReelNest 项目范围：[项目边界](PROJECT_SCOPE.zh-CN.md)、[数据字典](DATA_DICTIONARY.zh-CN.md)、[来源映射](design/SOURCE_MAPPING.md)。

# Plex 基础视频来源闭环计划（2026-10-27）

状态：**Plex 基础视频来源与 Windows Release/smoke 自动验证通过；真实服务、macOS/Linux 原生和人工验收仍待完成。** 本文限定本阶段 Plex 基础视频来源闭环。使用严格 loopback fixture 和 Windows Native mpv 验证；不使用真实 Plex Token。真实 Plex、macOS/Linux 原生及人工精确视觉验收待后续。

## 目标与范围

迁移 Plex 视频来源最小可用闭环：服务器地址与 Token 认证、凭据/会话恢复、媒体库选择、独立 Plex 来源与侧栏、分页同步/浏览、来源内搜索、详情、直连视频播放、音轨与字幕、续播/切集、播放进度上报以及已看/未看回写。

保留独立 `MediaSourceKind.plex`、Plex provider、credential kind、稳定媒体 ID 与 `plex://<host>/<sourceId>` 来源身份。复用数据库、播放器和适用的 UI/数据模型不表示 Plex 使用 Emby API 或登录协议；协议请求必须走独立 Plex client/service。

## 原版行为基线

以原版 MediaLib 当前参考源码和测试为权威：

- `Sources/MediaLib/App/PlexService.swift`：Plex 独立 XML client/service；认证以 server URL + Token 调用 `/identity`，使用 `X-Plex-Token` 和 `X-Plex-*` 客户端头；库列表来自 `/library/sections`，条目按 `X-Plex-Container-Start` / `X-Plex-Container-Size` 分页获取。
- 原版 URL helper 仅给同源 Plex 资源地址补/换 `X-Plex-Token`，不向外部绝对 URL 注入本站凭据。Plex 媒体身份以来源内 rating key 映射到 `plex` 稳定 ID。
- Plex 播放进度使用 `/:/progress`，已看状态使用 `/:/scrobble` / `/:/unscrobble`。会话恢复按 `RemoteConnectorProvider.plex` 凭据类型读取 Token 并验证 Plex session。
- `Sources/MediaLib/App/AppState.swift` 的 `connectPlexServer` 接受 server 与 token，保存独立 `plex://<host>/<sourceId>` 来源和来源凭据，然后导入所选媒体库。`Sources/MediaLib/Views/SourcesView.swift` 提供 Plex 独立入口与地址/Token 配置。
- `Tests/MediaLibTests/App/PlexServiceMetadataIDTests.swift` 覆盖媒体服务商 ID 解析、同源 Token 替换和不向不同 host/scheme/port 泄漏 Token 等行为；逐项核对测试的适用边界，不把元数据 ID 单测当作连接器集成验收。

## ReelNest 接入约束

- Plex 认证、XML 响应、分页头、播放进度与 scrobble/unscrobble 必须由 Plex 独立连接器处理。不得把 Plex 请求路由到 Emby `Authorization`、`X-Emby-*`、`api_key` 或 Jellyfin endpoint。
- 来源身份、用户凭据、会话与稳定条目 ID 按 Plex `sourceId` 隔离；所有同源 Token 注入须遵守 host/scheme/port 边界，绝不把 Token 加入 SQLite、日志或其他主机 URL。
- 共享远程表、数据库仓储、播放器、通用条目 UI 或内部 `Emby*` 类型可以复用，但内部名称不表示 Plex 协议、身份或产品文案属于 Emby。
- 原版 Plex 导入条目将 `favorite` 设为 `false`，且 Plex 原版无服务端收藏接口。本阶段收藏/取消收藏在 ReelNest 本地保存；Plex 同步合并必须保留该本地值，不能把导入的 false 覆盖用户收藏。已看状态不同：经 Plex `scrobble` / `unscrobble` 写回。
- 原版个人 `userRating` 按五分制换算为 ReelNest 0–5 评分（含 `userRating/2` 初始偏好播种）；映射值可选，已有本地评分不得被 Plex 同步覆盖。Plex 不支持本项目的质量选择能力，专属能力标记为 `supportsQualitySelection=false`。
- 本阶段只做基础 direct playback 与用户选择的已有音轨/字幕能力；不扩展高转码策略或完整质量切换流程。音乐作为独立后续模块推进，Plex 音乐不在本阶段；照片模块继续排除。
- 凭据放在既有安全凭据存储，按 Plex source 身份隔离。数据库仅沿用当前 schemaVersion 1 和现有 source/media/remote tables；不增加表、schema 变更、迁移或历史兼容分支，不清理本机数据。

## 2026-10-27 重新认证的账号归属修正

用户复核的 P2 已复现：原先把 `machineIdentifier` 同时当作 `userId`，导致同服务器的另一账号 Token 可以替换原凭据。此前 24 项回归中的不同 Token 隔离仅验证内存查询缓存，不能证明持久索引和离线缓存的账号归属安全。

按用户本轮选择，连接/重新认证读取固定的 Plex 官方 `https://plex.tv/api/v2/user`，以账号 `id` 保存 `plex-account:<id>`；服务器身份独立保存在 `serverIdentity`。重新认证必须同时满足 kind、服务器身份和账号身份一致，再保存新凭据。同账号更新 Token 可沿用原来源；另一账号（包括权限更低的账号）必须另建来源，不能继承旧索引或离线缓存。用户名和服务器友好名称不作为身份依据。

官方返回 401/403 的服务器专用 Token 仍可通过 PMS 受保护接口连接，但来源仅绑定 `plex-token:<SHA-256 指纹>`，不能据此推断账号归属；更换该 Token 必须另建来源。官方请求超时/失败、响应无有效 ID、超大响应或重定向均不得覆盖原凭据。账号请求使用 HTTPS 固定域名、Token 请求头、256 KiB 流式上限并拒绝重定向；测试地址只能显式注入 loopback。只保存账号标识，不保存完整 profile、邮箱或响应中的 authenticationToken；原始 Token 仍仅进入安全凭据存储。普通浏览、会话恢复和离线播放不调用账号接口。

没有新增 SQL 表或迁移，不自动删除本机数据。开发中旧来源若以服务器身份冒充账号身份，重新认证不能直接认领旧数据，须由用户重新添加来源；不设计历史数据库兼容分支。

本轮定向测试 `build/plex-account-final-tests.log` **67/67**：Plex 后端 30、Emby 连接 18、Jellyfin 后端 17、Plex UI 2（四文件，不与此前 24/255/63 组累计）。覆盖同账号 Token 轮换、跨账号拒绝且凭据/索引/离线记录不变、另建来源隔离、服务器身份变化、仅服务器 Token、无效/超大账号响应、拒绝账号重定向、取消在途账号请求，以及 Emby/Jellyfin 认证回归。使用本地模拟账号接口，未验证真实 Plex 官方账号或真实服务器；此前 24 项的 Token 隔离只覆盖内存缓存，不作为此 P2 问题的安全证据。

本轮 Windows 验证完成：`build/plex-account-native.log` Profile 构建 39.1 秒，`integration_test/plex_test.dart` 业务 1 项与 tearDown 通过；`build/plex-account-release.log` Release 构建 40.6 秒成功；`build/plex-account-smoke.json` 对应 2026-10-27 10:12:50.4795150 +08:00 的五秒 smoke，窗口响应、正常关闭、ExitCode 0。`build/plex-account-analyze.log` clean，`build/plex-account-format.log` 对 427 个 Dart 文件检查为 0 changed，diff-check clean。本批未运行全量 Flutter 测试；真实 Plex 官方账号/服务器、macOS/Linux 原生、人工视觉和辅助功能验收仍待。

## 协议与验收矩阵

| 领域 | 本阶段核对与验收点 | 当前状态 |
|---|---|---|
| 认证与恢复 | server URL + Token；`/identity`；Plex 专属 `X-Plex-*` 头和 `X-Plex-Token`；过期后重新认证/恢复；Token source 隔离 | Plex 专属后端最终 24/24 通过；前端连接和重新认证用例通过 |
| 来源身份与库选择 | `kind=plex`、`plex://host/sourceId`、Plex credential kind；`/library/sections` 返回与选择的库按 sourceId 保存 | 前端身份/导航用例及后端最终定向测试通过 |
| XML 与分页 | Plex XML 解析；container start/size 分页；电影/剧集/季集父子身份；异常 XML、空结果、末页与重复 ID | Plex 专属后端最终 24/24；覆盖分页边界及原版 mixedcase/Guidchild 优先、pathcase 保留 |
| 搜索与详情 | 限定当前 Plex 来源的搜索；详情演员/主创/外部 ID/图片 URL；同源 Token 替换规则 | 前端定向 2/2、Native 搜索/演员详情链路及后端 Token 边界测试通过；更广 UI/人工视觉待 |
| 播放 | 直连 media/part URL、实际 mpv Range 请求、seek、音轨/字幕选择、续播和切集；不把通用播放器测试当 Plex stream 验收 | Windows Native 真实 Range/seek/外部字幕链路通过；其他播放边界仍待 |
| 写回与本地状态 | `/:/progress`、`/:/scrobble`、`/:/unscrobble`；本地 favorite 在重同步后保留，不伪造 Plex 收藏 endpoint | Native 验证 stopped progress；其余进度/已看及收藏重同步语义仍需独立覆盖 |
| 安全性 | 错误 host/scheme/port 不注入 Plex Token；真实 token 不进入 fixture、日志、数据库或构建包 | 最终24项定向回归覆盖换服务器索引隔离、不同受限Token缓存隔离与外部公开图不带凭据；不使用真实凭据 |
| UI 与平台 | 来源入口、登录状态、媒体库、浏览/搜索/详情/播放器按原版对照；Windows Native mpv 先验 | 前端 2/2、Windows Native 单业务用例通过；人工精确视觉、macOS/Linux 待后续 |

后端最终定向组为 24/24（`build/plex-backend-final.log`）；此前 21/21、23/23 均为中间态。此结果基于严格本地 XML fixture，不代表真实 Plex 或全项目测试通过。

共享与 UI 回归也已完成：最终口径分列为 Plex 专属后端 24/24（`build/plex-backend-final.log`）、共享后端 255/255，以及同步/UI 63 项（既有 61 项 + Plex UI 2 项）。`apps/client/build/plex-shared-final.log` 的 276/276、27 秒、exit 0 是当时 255 项共享 + Plex 后端 21 项的组合报告；21 项已被最终专属 24/24 覆盖，不能再和 24/24 累加。`apps/client/build/plex-ui-final.log` 的 85/85、21 秒、exit 0 包含 PlexBackend、EmbySync、EmbyNavigation、EmbySidebarStartup、JellyfinFrontend、PlexFrontend，其中 PlexFrontend 2 项已纳入同步/UI 63 项，组合日志也不另行加总。此前 `plex-shared-regression.log` 的 254 项 + 1 项 stale test 失败不是最终交付证据。

## 不在本阶段

- Plex 高转码、完整画质切换策略、服务器管理或高级服务端功能。
- Plex 音乐浏览/队列/播放；音乐整体按独立模块迁移。
- 照片/相册、照片查看器、照片搜索与首页照片墙；既有范围决定继续生效。
- 对真实 Plex 服务器、macOS/Linux 或人工精确视觉的通过声明，除非后续实际证据补齐。

## 当前实现与验收记录

Plex 基础视频闭环已实现并通过本地自动化、Windows Native、Release 与 smoke 验证；真实服务和跨平台/人工验收待完成。以下为分项证据，不可将含重叠用例的组合日志重复累计。验收基于严格 loopback server 和无效占位 Token，不使用真实 token。首轮失败/中间日志不作为最终通过证据。

| 验收项 | 状态 | 证据 |
|---|---|---|
| 原版 Swift 与 `PlexServiceMetadataIDTests` 盘点 | 已核对基线 | `PlexService.swift`、`AppState.connectPlexServer`、`SourcesView.swift` 与 `PlexServiceMetadataIDTests.swift`；适用行为已纳入本阶段回归 |
| Plex 专属后端最终定向测试 | 通过 | `build/plex-backend-final.log`：24/24；严格 loopback XML fixture、非真实服务。覆盖分页无 totalSize/自适应缩页、Token 重定向与外部图片隔离、换服务器身份不得覆盖索引、同服务器不同受限 Token 缓存隔离，以及原版 mixedcase/Guidchild 优先和 pathcase 保留；21/23 均为中间态 |
| 前端定向测试 | 通过 | `build/plex-frontend-final.log`：2/2；包含 Token-only 来源向导/空 Token 校验、连接同步、官方 Plex 资产、来源身份/名称/位置、Token-only 重新认证、侧栏/媒体库/详情/演员身份 |
| 共享与同步/UI 回归 | 通过 | 最终口径：共享后端 255/255；同步/UI 63 项（既有 61 + Plex UI 2）。组合日志 276/276 和 UI 85/85 均有重叠，不另行累计 |
| Windows Native + mpv 最终复跑 | 通过（单业务用例） | `build/plex-native-final.log`：Profile 构建 37.0 秒，业务 1 case + tearDown（共 2 项）通过；真实 Range/seek/外部字幕/`/:/progress` stopped 通过。仍有 AXTree 告警与 integration_test plugin 提示，不代表辅助功能验收 |
| 静态检查 | 通过 | `build/plex-analyze-final.log` clean；`build/plex-format-final.log` 对 427 个 Dart 文件检查，0 changed |
| Windows Release | 通过 | `build/plex-release.log`：42.9 秒成功；`build/windows/x64/runner/Release/data/app.so` 为 13,042,568 bytes（2026-10-27T01:47:22.3311810+08:00）。Dart 应用代码位于 AOT `app.so`，EXE wrapper 时间可旧 |
| Windows smoke | 通过 | `scripts/windows-smoke.ps1 -ObservationSeconds 5`；`build/smoke/release-startup.json` 的 `CheckedAt=2026-10-27T01:47:49.4943380+08:00`，5 秒内窗口响应、正常关闭、exit 0 |
| macOS/Linux、真实 Plex、人工视觉 | 待后续验收 | 不从 Windows Native/UI 自动化结果推定通过 |
| 辅助功能 | 待后续验收 | Native 日志有 Flutter accessibility AXTree 告警；未宣称辅助功能已验收 |
| 真实 Plex 服务 | 待后续验收 | 不使用真实 Token；后续另行安排真实服务验证 |

## 参考源码

- 原版：`Sources/MediaLib/App/PlexService.swift`。
- 原版：`Sources/MediaLib/App/AppState.swift`（`connectPlexServer`、来源身份、凭据保存、刷新/恢复与播放状态分派）。
- 原版：`Sources/MediaLib/Views/SourcesView.swift`（Plex 来源表单和连接入口）。
- 原版测试：`Tests/MediaLibTests/App/PlexServiceMetadataIDTests.swift`。
- 项目约束：[项目边界](PROJECT_SCOPE.zh-CN.md)、[数据字典](DATA_DICTIONARY.zh-CN.md)、[来源映射](design/SOURCE_MAPPING.md)。

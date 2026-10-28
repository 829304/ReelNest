# TMDB 本地剧集元数据手动匹配计划（2026-10-26）

状态：**2026-10-26 单项手动匹配完成；2026-10-27 手动批量匹配和定时自动匹配均已完成 Windows 定向交付验证。** 自动匹配 15 文件整合回归 179/179、最终 analyze、Windows Release 与五秒 smoke 通过。以下既有 102/102 后端、12/12 UI、Windows 原生及 Release/smoke 记录属于单项匹配批次；批量匹配 160/160 及其 Windows Release/smoke 属于上一阶段，均不替代当前自动匹配验收。真实 TMDB 公服、macOS/Linux 原生、native Flutter drive、全量测试与可见 UI 验收仍待。

## 2026-10-27：本地剧集/动漫 TMDB 手动批量匹配（Windows 定向交付验证通过）

本节是对 2026-10-26 单项手动匹配之后的独立扩展；原先“本批不实现批量/自动匹配”的表述仍描述 10-26 单项匹配批次，不改写其历史范围与结果。本阶段实现已接入，但首轮后端测试及 UI 文案修正不是最终整合验收。

### 范围与行为

- 只由用户手动启动；目标限于 `localFolder`、`removableDrive`、`mountedNas` 文件来源中的顶层 series，且 `isSeries=true`、类型为 `tvShow` 或 `anime`。动漫分类专项明确覆盖；Emby/Jellyfin/Plex 等远程来源的 series 不进入批量目标，也不改写远程资料。只处理来源 `includeInMetadataFetch=true` 的条目。
- 同语言且已有关联的 `TMDB[language]` 资料跳过；语言改变后可重新匹配。候选标题、原名及已有集文件的父/祖父目录生成去噪查询，按宽容度限制查询预算；重复查询和 TMDB ID 去重。
- 沿用原版影视匹配宽容度，默认宽松：宽松/标准/严格阈值为 0.42/0.58/0.74，查询预算为 16/10/6。评分结合清洗后的标题/查询命中及年份，相关性同分保留原顺序；具体查询的单项唯一命中将置信度至少抬至 0.52，只有宽松阈值可由该下限直接放行，标准/严格仍需满足各自阈值。Levenshtein 评分在 isolate 执行，并可取消等待。
- 批量任务同一时刻仅运行一次；重复启动共享进行中的 Future。用户可取消，HTTP 搜索随取消中断。逐项隔离失败，进度分别累计已处理、已匹配、低置信跳过与失败；已完成的条目保留。过长标题（超过 1024 字符）按单项失败处理，避免 edit-distance 评分的过量计算；评分 isolate 支持协作取消等待。HTTP 与单项异常写入 diagnostics 前脱敏，只保留脱敏 code/type/stack，不记录关键词、路径或凭据。
- 复用 `TmdbVideoService.apply`、现有 series 数据与 artwork cache，不写媒体文件或 NFO，不建立周期任务。来源扫描/移除/配置变化、语言变化，或条目/现有元数据被手动编辑时，通过快照校验阻止过期结果提交；提交阶段再校验一次。批次候选仅保存 metadata JSON 的 SHA256 摘要用于变化检测，不复制整份元数据快照。
- 宽容度偏好使用既有 `PreferenceStore` 键 `global.metadataMatchTolerance`；运行时变化不改变当前批次已读取的设置快照，后续新批次才使用新值，不改 SQLite schema。`SourceSettingsSheet` 可编辑并保存来源 `includeInMetadataFetch`，该选项参与后台候选过滤；`preferMetadataWriteToSource` 仍禁用，NFO 写回不在本批范围，界面说明此处来源参与开关用于本地剧集/动漫一键匹配。

### 阶段性验证状态

最终 13 文件定向回归 160/160 通过（41 秒，`apps/client/build/tmdb-batch-tests.log`；按日志计数，含 scorer、batch、既有 TMDB 服务/客户端、前端、健康、来源扫描/增量、仓储与 app 回归）。`flutter analyze` clean（4.8 秒，`apps/client/build/tmdb-batch-analyze.log`）；44 个工作区变更 Dart 文件 format 0 changed，`git diff --check` 通过。首轮 74 项及 159 项是中间验证，已由最终 160 项替代，不累加。Windows Release 成功（52.7 秒，`apps/client/build/tmdb-batch-release.log`）；`data/app.so` 于 2026-10-27 21:48:27 +08，13,222,792 bytes。五秒 hidden smoke 于 `2026-10-27T21:49:11.0304196+08:00` 通过（`apps/client/build/tmdb-batch-smoke.json`）：HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0。

边界：没有运行全量测试、native Flutter drive；没有使用真实 TMDB 凭据/公服；没有 macOS/Linux 原生、实体目录选择器或可见 UI 验收。本轮仅改批量匹配相关 UI 与 `SourceSettingsSheet` 元数据参与开关；来源列表 `SourceRow` 未改，来源列表像素/交互一致性仍未验收。

## 2026-10-27：本地剧集/动漫 TMDB 定时自动匹配（Windows 定向交付验证通过）

本阶段在手动批量匹配之上增加独立的自动周期调度；不会把自动运行结果与上一阶段 13 文件 160/160 的手动批量验证合并。

### 调度规则与范围

- `TmdbSettings.automaticMatchInterval` 默认 `disabled`，复用 `AutomaticScanInterval` 的五档，但以独立 `PreferenceStore` 键 `global.automaticTMDBMatchInterval` 保存；不与文件自动扫描间隔共用偏好，不改 SQLite schema。
- 开启周期后等待完整周期才第一次 tick，不立即执行；忙于媒体扫描、手动/自动匹配时跳过 tick，不追补。无 TMDB 凭据或无合格候选时静默跳过，并保留上次任务状态/结果。
- 自动任务复用手动批次的本地来源/`includeInMetadataFetch`、当前语言未匹配筛选，宽容度、取消、逐项隔离失败与过期结果校验；Emby/Jellyfin/Plex 远程资料不参与、不改写。
- 自动调度有独立取消 token。按用户确认的“关闭即取消”规则，关闭周期会取消当前自动任务但不影响手动批次；这条是当前明确批准的行为，不据此推断原版关闭周期时一定会中断已运行任务。切换非关闭周期只重设 timer，不打断正在运行的自动批次；同值、语言或宽容度变化不重设 timer。应用退出先停止 timer、取消自动请求，再排空批次并关闭数据库。原版基线是完整周期后触发、忙碌时跳过，不补跑。
- 设置菜单允许无 TMDB 凭据时保存周期偏好；默认关闭且启动恢复偏好时不创建批次/HTTP 服务、不查询媒体目录。NFO/媒体文件写回、来源列表 `SourceRow`、新连接器均不在本阶段范围。

### 阶段状态

15 文件整合回归 179/179 通过（48 秒，`apps/client/build/tmdb-automatic-tests.log`）；最终 `flutter analyze` clean（4.4 秒，`apps/client/build/tmdb-automatic-analyze.log`）。覆盖五档虚拟时间周期、忙碌跳过、重复 tick、修改周期、禁用自动 token、退出取消；真实 loopback 自动 batch 验证取消时第一条已提交结果保留、后续条目不写入；provider 验证恢复已存周期、默认不创建 batch/HTTP 服务、语言变化不重置 timer，以及偏好写入失败保护。Windows Release 构建 45.9 秒（`apps/client/build/tmdb-automatic-release.log`）；`data/app.so` 时间为 2026-10-27 22:07:19 +08、13,239,176 bytes。五秒 hidden smoke 于 `2026-10-27T22:08:29.8982322+08:00` 通过：窗口响应、正常关闭、ExitCode 0；原始报告已复制并核对为 `apps/client/build/tmdb-automatic-smoke.json`。48 个工作区变更 Dart 文件 format 0 changed，`git diff --check` 通过。上一阶段 160 项与本轮 179 项存在覆盖重叠，分别记录、不累计。本阶段 Windows 定向交付验证通过。

边界：未运行 native Flutter drive、真实 TMDB 公服、macOS/Linux 原生、可见 UI 验收、全量测试或真实 15 分钟墙钟等待。周期测试使用虚拟时间，不能据此宣称真实长期运行验收完成。

## 上一阶段目标与范围（2026-10-26 单项手动匹配）

用户可从本地剧集进入 TMDB 搜索，查看候选并明确选择匹配。选定剧集的 TMDB 资料本地保存，并依据 ReelNest 本地媒体已有的季号、集号关联已有剧集记录与对应元数据。

匹配对象限于本地来源中已索引的剧集。关联只能使用已有本地剧集及其季号/集号；不得创建虚拟媒体或本地集记录，不修改媒体路径、文件身份、播放进度、播放记录、书签/章节或其他播放状态。

Emby 继续使用 Emby 服务端资料。**2026-10-26 单项手动匹配批次**不实现剧集批量/自动匹配、NFO 写回、媒体文件写入、在线字幕、Emby 刮削或未获批的其他元数据源；这条仅为上一批范围记录，不限制本页新批准的 2026-10-27 手动批量匹配扩展，也不改变 TMDB 电影第一批的范围与验收结论。

## 原版 Swift 行为基线

只读对照原版 MediaLib 固定参考版本 `64f8ee2`：

- `Sources/MediaLib/App/MetadataSearchService.swift` 的 `searchTMDB(query:itemType:apiKey:language:)`：`MediaType.tvShow` 等 TV 类型走 `/3/search/tv`；使用 `query`、`include_adult=false`、语言（空值回退 `zh-CN`），最多取 12 个结果。TV 候选 ID 采用 `tmdb:tv:<id>`，标题取 `name`，原名取 `original_name`，日期取 `first_air_date`，并带简介、海报/背景图与评分。
- `fetchTMDBDetailResult` 调用 `TMDBMetadataClient.metadataResult` 补全候选摘要。`TMDBEnrichmentService.fetch` 按 `tmdb:tv:<id>` 请求 `/3/tv/<id>`，扩展 `aggregate_credits`、`recommendations`、`similar`、`videos`、`images`、`external_ids`、`content_ratings`；该详情提供剧集级摘要、演职员、季数/集数、播出日期、网络和内容分级等信息。**原版没有 TMDB season endpoint 请求**；本轮对已有本地季集做关联并调用季详情 endpoint，是用户批准的新实现行为，不应描述成原版已有流程。
- `AppState.applyMetadataSearchResult(_:to:)` 在候选确认后获取详情，构造元数据更新并调用 `updateMetadata(..., source: "manual")`；详情获取失败时保留搜索候选摘要作为回退输入。
- `MediaRepository.updateMetadata(id:metadata:)` 更新既有媒体记录的标题、原名、年份、简介、艺术图、评分、时长、外部 ID、来源与题材等通用元数据字段。新实现须结合本地 series/episode 身份模型设计独立持久化，不把 Emby 远程媒体路径套用于本地资料。

TMDB 凭据沿用电影批次既有 API Key / Read Access Token 行为，语言默认与空值回退 `zh-CN`。本地剧集 root 使用原版共用的 620×460 搜索弹窗、22pt 标题与相同副标题结构，movie/tv 走不同搜索路由；候选副标题显示 `releaseDate`，年份/评分/应用操作在底行。匹配进行中禁止关闭、Escape 关闭和重复提交，成功提示“TMDB 剧集资料已应用。”。详情 Hero 显示 TMDB 标题、海报、简介、评分、状态、分级、类型、制作公司及正数季数/集数；剧集不显示 runtime。演员/主创复用折叠详情。已有本地季集列表直接显示后端更新的 episode `cardTitle`，不新建 TMDB 季卡，也不逐集请求 provider/N+1；单集详情和 Emby 页面没有匹配入口。

## 数据模型与持久化边界

- 公共实现命名为 `TmdbVideoService`，位于 `application/tmdb_video_service.dart`；movie 与 tv provider 共享服务实现。公共候选为 `TmdbCandidate`，由 `kind` 区分 movie/tv。
- 剧集级资料保存在 `local_series_metadata(source_id, local_id, value)`；单集资料保存在 `local_episode_metadata(source_id, local_id, series_local_id, value)`。episode 表通过 `(source_id, local_id)` 关联已有 `media` 行，并通过 `(source_id, series_local_id)` 关联 series metadata；两条外键均级联删除。
- 单集拉取仅依据本地已有 `seasonNumber >= 0` 且 `episodeNumber > 0` 请求 TMDB 季详情，最多同时 2 个季请求；不逐集调用 TMDB episode endpoint。无有效季/集编号时不猜测匹配，显示未匹配提示。
- TMDB 可更新已有 episode 的 `title`、`overview`、`year`；保留本地媒体身份、季号、集号、文件路径、图片和所有播放记录。剧集海报/背景图通过既有安全本地图片存储；不下载季或单集图片。本轮不创建 TMDB 季卡，界面保留本地季集结构。
- 部分季详情失败时保留已有单集资料；重匹配同一个 TMDB 系列时保留先前成功取得的季资料。若匹配期间媒体集合或季/集编号发生变化，整个事务拒绝提交，避免把结果写入已变化的目标。
- 重扫保护已确认的 `title` / `overview`；若季号、集号、父级或媒体类型变化，则移除不再适用的单集元数据关联。
- `schemaVersion` 保持 1，不增加开发中间版本迁移、旧 schema 分支或历史兼容测试。实际 SQL 见[数据字典](DATA_DICTIONARY.zh-CN.md#本地-tmdb-元数据剧集手动匹配已实现)。
- TMDB 凭据留在既有安全凭据存储中，不写入 SQLite、一般偏好、错误文本或日志。图片仍走既有 TMDB artwork 缓存与校验约束，不写入媒体源目录。
- 不修改任何媒体路径或文件，不创建虚拟媒体，不触碰播放记录、播放进度、章节/书签、观看状态与离线缓存状态。

本轮新增的季详情请求只用于关联并丰富本地已有季号/集号；这是获批的本地剧集实现行为，不是原版 Swift season endpoint 行为。

## 上一阶段实现与验证（2026-10-26 单项手动匹配）

- 后端：负责 TV 搜索/详情映射、剧集与集资料持久化、已有季号/集号关联及数据边界。公共模型已全局重命名为 `TmdbCandidate` / `TmdbMetadata`，增加 `kind`（movie/tv）及 TV、season、episode DTO；这些接线不等于本功能验收完成。
- 前端：负责本地剧集详情入口、搜索/候选选择/确认流程、剧集/季/集资料展示与状态反馈，并逐项对照原版 Swift。
- 上一批单项手动匹配及其定向验证完成：后端102/102、UI12/12、Windows Profile 原生、Release/smoke 与 analyze/format 通过。该批未运行全量测试；真实 TMDB 公服、macOS/Linux 原生和人工精确视觉验收仍待。此结果不作为当前批量匹配的验收证据；各专项与全量结果按批次分别记录，不累计重叠计数。

## 上一阶段单项匹配验收清单

- 本地剧集可手动搜索 TMDB TV 候选；搜索取消、空结果、缺凭据及 API 错误均有清楚状态。
- 用户明确确认后，保存所选 TV 身份与剧集级资料；关闭并重开详情后仍可读回。
- 按已有有效季号并发获取最多两个 TMDB 季详情，不调用逐集 endpoint；未编号的集有未匹配提示，不创建缺失 season/episode 的虚拟媒体。
- TMDB 更新单集 title/overview/year 时保留路径、身份、季集号、图片和播放记录；剧集 artwork 复用安全本地存储，季/集图片不下载，页面不创建 TMDB 季卡。
- 部分季失败保留已有单集资料，同系列重匹配保留先前成功季；集合或编号快照变化时整事务拒绝。重扫保留已确认 title/overview，并在编号/父级/类型变化时清理失效单集关联。
- Emby 元数据链路不受改写；电影匹配原行为保持；不引入批量/自动匹配、NFO、在线字幕或其他未批准范围。
- 对照原版完成剧集详情、搜索 UI、候选与加载/错误/已匹配各状态的逐项布局和交互验收。
- Windows、macOS、Linux 分别记录实际验证；真实公服认证和可见人工 UI 验收单独记录，构建通过不替代这些验收。

## 上一阶段验证记录（2026-10-26）

| 验证项 | 状态 | 证据与边界 |
|---|---|---|
| 最终后端定向回归 | 通过（102/102，20秒） | `apps/client/build/tmdb-series-final-targeted.log`：6文件，backend4 + `source_repository` + `Emby_library_actions`，exit 0。该最终组是本批后端汇总证据，之前49、86、66、14项是中间重叠批次，不累计。包含季请求并发上限、未编号/错误类型/季/重复集/系列拒绝、离线重开、图片保护与清理、重扫、事务竞态拒绝及 Emby 隔离 |
| 前端 movie + series UI | 通过（12/12，7秒） | `apps/client/build/tmdb-series-frontend-passed.log`，exit 0；movie9 + series3。覆盖共用620×460弹窗、22pt标题、候选与确认，详情 Hero/演职员，以及既有 episode `cardTitle`；不创建季卡或逐集/N+1请求 |
| 全项目静态分析与格式 | 通过 | `apps/client/build/tmdb-series-analyze-final.log` clean；`apps/client/build/tmdb-series-format.log` 417 Dart files，0 changed；`git diff --check` 通过 |
| Windows Profile 原生与离线重开 | 通过（1个业务用例） | `apps/client/build/tmdb-series-native.log`：Profile 构建37.6秒，series 业务1 case 通过（harness 计数另含业务1和 tearDown1），exit 0。生产 `LocalMediaDetailPage` 完成 TV 搜索/详情/季/图片、既有单集标题刷新、poster `RawImage` 解码，fixture 关闭后 SQLite 离线重开成功；不代表公服或人工视觉验收 |
| Windows Release | 通过（42.3秒） | `apps/client/build/tmdb-series-release.log`；标准 Release EXE 路径 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。`data/app.so` 时间 2026-10-26 14:38:50 +08，12,977,032 bytes |
| Windows smoke | 通过（5秒） | `scripts/windows-smoke.ps1 -ObservationSeconds 5`；报告 `apps/client/build/smoke/release-startup.json`，CheckedAt `2026-10-26T14:40:49.9127080+08:00`，`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0` |
| 本批全量测试 | 未运行 | 本批不以其他历史全量测试替代，也不把以上专项相加成全量结果 |
| 真实 TMDB 公服、macOS/Linux 原生与人工精确视觉 | 待验 | 尚无对应实测证据 |

## 参考

- [TMDB：Application Authentication](https://developer.themoviedb.org/docs/authentication-application)
- [TMDB：Search & Query For Details](https://developer.themoviedb.org/docs/search-and-query-for-details)
- [TMDB：Search TV](https://developer.themoviedb.org/reference/search-tv)
- [TMDB：TV Series Details](https://developer.themoviedb.org/reference/tv-series-details)
- [TMDB：TV Season Details](https://developer.themoviedb.org/reference/tv-season-details)
- 原版 Swift 搜索：`Sources/MediaLib/App/MetadataSearchService.swift`
- 原版 Swift 详情：`Sources/MediaLib/App/TMDBEnrichmentService.swift`
- 原版元数据应用/持久化：`Sources/MediaLib/App/AppState.swift`、`Sources/MediaLibCore/Database/MediaRepository.swift`

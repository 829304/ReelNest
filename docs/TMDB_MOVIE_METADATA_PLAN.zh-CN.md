# TMDB 本地电影元数据第一批计划（2026-10-26）

状态：**实现与 Windows Release/smoke 交付验证完成；全量测试有一项未收尾，跨平台及真实公服验收待完成。产品代码冻结。** 最终 TMDB 定向合并复跑 `apps/client/build/tmdb-final-targeted.log`：client 16 + service 14 + UI 9，共 39/39，18 秒，exit 0，含新增 series 拒绝用例。该专项计数不与全量或独立原生用例相加。Windows Delivery Release 构建成功（56.0 秒）；产物 `apps/client/build/windows/x64/runner/Release/data/app.so` 时间为 2026-10-26 09:13:45 +08，大小 12,911,496 bytes。五秒启动 smoke 于 2026-10-26T09:14:23.4674062+08:00 正常关闭，ExitCode 0。全量 `apps/client/build/tmdb-full-final.log` 为 1034 passed / 2 conditional skip / 1 native business test unfinished，exit 1，不能记作全量通过。Windows Profile 原生业务用例 1 项通过，marker skip native business 用例另在 `tmdb-marker-native-recheck.log` 单独复跑通过，两者不合并宣称 2 项同批次。`dart analyze lib/test/integration_test` 无问题；413 个 Dart 文件 format 0 changed，`git diff --check` 通过。后续缓存关闭取消专项46项通过，Windows Release/smoke 通过；该次未重现此前约4.9秒的具体任务状态，不作为所有负载下的耗时保证。真实 TMDB 公服、macOS/Linux 原生与人工精确视觉待验。

## 本批目标

为本地电影提供用户可控的 TMDB 元数据匹配闭环：从电影详情进入搜索，用户选择候选并明确确认后，将匹配结果和详情信息保存到本地媒体记录，在本地电影详情页展示海报、简介、演员等信息。

本批只覆盖本地电影。Emby 继续使用 Emby 服务端提供的资料；TMDB 是独立的公共元数据来源，不是 Emby 视频接口完成的前置条件。

## 原版行为基线

只读核对原版 MediaLib，固定参考版本 `64f8ee2`：

- `Sources/MediaLib/App/MetadataSearchService.swift` 的 `searchTMDB(query:itemType:apiKey:language:)`：按媒体类型调用 `/3/search/movie` 或 `/3/search/tv`；搜索词使用 query 参数，`include_adult=false`，语言空值回退 `zh-CN`，最多返回前 12 条。TMDB token 形态按原版处理：短 API Key 作为 `api_key` 查询参数；Read Access Token 作为 `Authorization: Bearer` 请求头。结果包含 TMDB 外部 ID、标题/原名、年份、简介、海报/背景图 URL、评分和可识别类型。
- 同文件的 `fetchTMDBDetailResult` 联合 `TMDBEnrichmentService.metadataResult`：用户选中候选后先拉取详情并补足候选摘要，再交给本地元数据更新流程。
- `Sources/MediaLib/App/AppState.swift` 的 `applyMetadataSearchResult(_:to:)`：对 TMDB 结果获取详情、构造本地元数据更新，调用 `updateMetadata(..., source: "manual")` 持久化并刷新详情快照；失败时保留搜索候选结果作为回退输入。
- `Sources/MediaLib/App/TMDBEnrichmentService.swift`：按 `tmdb:movie:<id>` 读取电影详情和扩展资料，包括主创/演员、相似作品、视频、图片、外部 ID、发行信息等。电影详情使用 `credits`、`recommendations`、`similar`、`videos`、`images`、`external_ids`、`release_dates` 扩展字段；演职员和艺术图由详情快照按需展示。
- `Sources/MediaLib/Views/SettingsView.swift` 的元数据设置：TMDB 凭据输入支持 API Key 或 Read Access Token；语言设置字段默认 `zh-CN`，清空后回退 `zh-CN`。原版还包含剧集批量匹配、自动拉取周期和匹配宽容度，本批不迁移这些控制。
- `Sources/MediaLib/Views/DetailView.swift`：本地条目详情操作区提供“搜索 TMDB”；搜索面板输入关键词、提交搜索并显示候选，点击候选执行应用。电影详情展示已保存的简介、类型、评分和详情快照中的演职员/组织等资料。UI 应逐项对照原版，不用通用页面代替。

## 本批范围

### 必须实现

- 仅本地电影的手动 TMDB 搜索入口、关键词搜索、候选展示和显式确认。
- 设置 TMDB API Key 或 Read Access Token；语言设置默认 `zh-CN`，空值按原版回退默认语言。
- 对确认的电影候选获取需要的 TMDB 电影详情，保存匹配身份和允许持久化的元数据到本地记录；详情页读取已保存资料并展示海报、简介、演员等内容。
- 搜索、详情获取、图片获取或本地保存失败时给出可理解的反馈，保留现有本地资料，不把失败静默表现为已匹配。
- 按原版媒体详情、搜索面板、设置控件、加载/空结果/错误/已匹配状态逐项迁移 UI 与交互。

### 明确不在本批

- 电视剧/动漫、剧集自动匹配、批量匹配、自动拉取周期及自动高置信匹配。
- NFO 写回、向媒体文件写入或覆盖元数据、文件重命名，以及未获批的额外刮削器。
- Emby 元数据替换或写回；Emby 仍以服务器资料为准。
- 音乐、照片/相册及相关资料匹配。
- 将 TMDB 接口完成设为 Emby 视频交付前置条件。

## 数据与失败边界

- 当前实现新增 `local_movie_metadata` 表，按本地 `source` 与 `local` 外键关联并级联删除，以 `value` 列保存 JSON 字符串；表以 `IF NOT EXISTS` 建立，当前 `schemaVersion` 保持 1，不新增历史版本迁移。条目基础字段与本地详情/演员数据在最终事务中写入；事务内再次确认来源和文件状态，来源变化事件触发刷新。扫描更新需保留人工匹配结果。
- TMDB 凭据经 `SecureCredentialStore` 存取；Windows 便携版本使用当前用户 DPAPI，不写入 SQLite。语言偏好使用 `global.tmdbLanguage`。不得把凭据或完整鉴权请求写入普通偏好、错误或日志。
- 海报/背景图以 `metadata-artwork:<SHA256>.<ext>` 标识，保存到 `userdata/library/metadata-artwork/`，不写入媒体源目录。下载采用流式处理，限制 8 MiB，并验证图片尺寸/解码；成功后写入原子、不可变文件。演员头像仍使用公开 TMDB URL 在线加载；图片失败时保留已有本地图片。
- TMDB API 响应限制 4 MiB，单次请求总预算 12 秒；拒绝 HTTP 重定向，避免鉴权信息意外转发。详情请求遇 429/503 最多重试两次，遵守原版 Retry-After 0.5–4 秒等待，且不突破总预算。API Key/Read Access Token 的传递方式按原版兼容：凭据含点或长度大于 80 使用 Bearer，其余作为 `api_key`。搜索使用 `/search/movie`、`include_adult=false`，按服务相关性排序后取前 12 项，不额外按年份硬过滤。
- 只有用户明确选择并确认的候选才可更改本地电影资料；普通搜索不得自动覆盖资料。
- 远端详情获取失败时按原版回退到搜索候选资料并通过 warnings 提示；图片失败保留原图。保存失败需保留既有元数据。错误提示不得暴露凭据或敏感请求信息。
- 本地 TMDB 评分参与现有首页 HomeVideo 评分规则，个人评分继续保留，不被 TMDB 评分覆盖。
- 电影详情字段映射保留既有产品语义：Producer 职位显示为“制片”；TmdbClient 从 `release_dates.results` 优先选择 `iso_3166_1 == "US"` 的分组（若无则取首组），使用其中首个非空 `certification`，映射到模型 `contentRating`。响应没有单独的 `contentRatingUS` 字段。
- 不可变图片若在本地事务失败后尚未被元数据引用，可能留下未引用文件；共享图片不会因单条匹配删除而被删除。本批不包含完整 metadata-artwork 存储整理。
- 当前已执行的验证结果和未覆盖范围见下表；未列入的真实来源/平台验收不因自动化通过而视为完成。

## 验收清单

- 设置可填写 API Key 或 Read Access Token；两种认证方式均有请求级覆盖，语言默认/空值回退 `zh-CN`。
- 本地电影可以搜索、查看候选、取消或确认；确认只更新目标本地电影。
- 选定的 TMDB ID 与电影详情保存并在详情页重开后恢复；海报、简介、演员等有数据时展示，无数据时不制造占位信息。
- 空结果、无凭据、网络/API 错误、详情失败和本地写入失败均有明确处理；失败不覆盖旧资料，不产生错误成功状态。
- Emby 资料路径未被 TMDB 改写；电视剧/动漫、音乐、照片、自动匹配、批量匹配和 NFO 写回均不进入本批。
- Windows、macOS、Linux 分别记录自动化/原生结果；真实 TMDB 请求与可见 UI、手动操作验收分开记录。构建通过不代替真实 UI 和数据持久化验收。

## 当前验证记录

| 项目 | 状态 | 证据与边界 |
|---|---|---|
| 后端 client/service 专项 | 通过（30 项：client 16 + service 14） | 覆盖 loopback HTTP 搜索/详情/PNG 下载、API Key/Bearer、相关性排序与前 12 项、字段回退、图片请求不附鉴权、拒绝重定向、Content-Length/chunk 限制、取消/超时、429/503 最多两次重试及 Retry-After 等、事务回滚与重试、重扫保留人工匹配、真实 SQLite 关闭重开、来源删除/文件索引变化拒绝、重复 apply、退出取消及凭据不入 SQLite。此项通过不改变全量测试退出 1 的结论 |
| 后端与测试静态分析 | 通过 | `dart analyze lib/test/integration_test`：No issues found |
| 来源/首页相关回归 | 通过（97 项） | 8 个文件回归；该批包含前一轮 27 个 TMDB 用例，计数属于同一验证批次，不与 29 项后端专项相加 |
| 前端设置/搜索/确认/详情 UI | 通过（9/9） | 日志 `apps/client/build/tmdb-ui-engineer.log`。原版布局对照为 22pt 纯标题/副标题/X、padding 22、620×460；结果卡副标题为 releaseDate，应用按钮在底行。覆盖凭据脱敏/明确清除、语言回显、自动搜索字段、关闭/取消、apply 中关闭及重复提交阻止、失败留窗、详情演员与刷新折叠保持、非 movie 不显示入口、头像失败静默。设置 2 个用例使用 fake notifier 验证 UI；真实 repository/controller 持久化由后端测试覆盖，不宣称 UI 用例执行了真实 I/O |
| 最终 TMDB 定向合并复跑 | 通过（39/39，18 秒） | `apps/client/build/tmdb-final-targeted.log`：client16 + service14 + UI9，exit 0；包含新增 series 拒绝用例。作为本批最终专项证据，不与全量和原生用例计数相加 |
| Windows 原生 UI 与离线重开 integration | 通过（1 个业务用例） | `apps/client/build/tmdb-native-final.log`：Profile 构建 52.2 秒，业务用例约 1 秒，harness +2 为 teardown 计数，exit 0。真实 `LocalMediaDetailPage`→搜索/选择→loopback HTTP 详情/图片→保存→关闭 fixture/DB→离线 SQLite 重开后读取成功；`RawImage(RenderImage.image != null)` 绘制通过。媒体目录仅保留原 mkv，playback/history/markers 均为 0。fixture-key 与 loopback 不代表公服认证、跨平台或人工视觉验收 |
| 全量测试 | 未完全通过 | `apps/client/build/tmdb-full-final.log`：1034 passed / 2 conditional skip / 1 native business test unfinished，exit 1；该原生业务用例及其 tearDown 未完成，不把全量记作通过。TMDB 30 后端项、9 UI 项均通过。`player_marker_skip_native_test` 在 `tmdb-marker-native-recheck.log` 独立复跑，1 个业务用例通过，不能与全量数字相加 |
| Windows Release/smoke | 通过 | Delivery Release 构建 56.0 秒；`app.so` 时间 2026-10-26 09:13:45 +08，12,911,496 bytes。`apps/client/build/smoke/release-startup.json` 于 2026-10-26T09:14:23.4674062+08:00 记录五秒观察、正常关闭、ExitCode 0。该次关闭耗时约 4.9 秒，其中 `close_cache` 约 4897 ms（见 `playback-34576-1792977253620073.jsonl`）；后续缓存关闭取消专项 smoke 未复现相同任务状态，不能据单次结果断言普遍耗时已消除，详见[缓存关闭取消记录](CACHE_SHUTDOWN_2026-10-26.zh-CN.md) |
| 真实 TMDB 公共服务、macOS/Linux 原生与可见 UI | 待验 | 尚无本批实测证据 |

## 当前实施状态
最终定向合并复跑 `tmdb-final-targeted.log` 为 client16 + service14 + UI9，共 39/39、18 秒、exit 0，含新增 series 拒绝用例。全量 `tmdb-full-final.log` 结果为 1034 passed / 2 conditional skip / 1 native business test unfinished，exit 1；不是全量通过。Windows Profile 原生 1 个业务用例及 marker skip native 的独立复跑分别通过，均不与定向/全量计数相加。`dart analyze lib/test/integration_test` 无问题，413 个 Dart 文件 format 0 changed，`git diff --check` 通过。Windows Delivery Release 与五秒 smoke 已通过；后续缓存关闭取消专项46项通过，Smoke 未重现先前约4.9秒的具体任务状态（详情见[缓存关闭取消记录](CACHE_SHUTDOWN_2026-10-26.zh-CN.md)），不据此作所有负载的关闭耗时保证。真实 TMDB 公服、macOS/Linux 原生及人工精确视觉验收仍待。未使用真实公服凭据。
## 参考

- [TMDB：Application Authentication](https://developer.themoviedb.org/docs/authentication-application)：V3 API 可用 `api_key` 参数或 Bearer access token 认证。
- [TMDB：Search & Query For Details](https://developer.themoviedb.org/docs/search-and-query-for-details)：先搜索取得候选 ID，再查询对应详情。
- [TMDB：Image Basics](https://developer.themoviedb.org/docs/image-basics)：图片 URL 由基础 URL、尺寸和文件路径构成。

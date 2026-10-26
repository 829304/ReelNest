# ReelNest 数据字典

- 状态：Active
- 负责人：数据与文档维护者
- 最后更新：2026-10-26
- 适用范围：`apps/client` 当前本地数据库与敏感数据边界
- 权威范围：数据身份、表用途、生命周期和隐私说明
- 代码依据：`apps/client/lib/storage/library_database.dart`
- 当前 schema：`1`

## 使用说明

本文件解释当前数据结构，实际建表 SQL 仍以 `library_database.dart` 为准。项目尚未发布，不维护开发中间版本升级链；`schemaVersion` 当前为 1，结构不匹配时抛出 `LibrarySchemaMismatch`，不会自动清空或迁移本机开发数据库。

数据库由 Drift/SQLite 管理。macOS/Linux 仍由各平台 `path_provider` 决定应用支持目录，数据库相对路径为：

```text
library/reelnest.sqlite
```

不要在跨平台文档中把某台机器的绝对路径写成固定产品路径。Windows 便携版数据库位置为 exe 同级的 `userdata/library/reelnest.sqlite`，详见下一节；本轮 Windows 路径、Release、启动关闭与打包已验证。

### Windows 便携存储（本轮 Windows 验证完成；旧凭据残留需手动清理）

用户于 2026-10-16 明确要求 Windows 改为绿色便携布局，相关路径代码现已接入；以解析后的 exe 父目录 `resolvedExecutable.parent` 为唯一根，不依赖启动时 cwd：

```text
<exe-parent>/
├── log/                         # 应用日志
├── userdata/
│   ├── library/reelnest.sqlite  # 当前 SQLite 数据库
│   └── credentials/             # DPAPI 加密凭据文件
├── cache/                       # 应用缓存
└── temp/                        # 临时文件
```

目标行为是不向 Windows 用户 C 盘配置目录或注册表写应用配置。native `main.cpp` 只为当前进程设置 `TMP`/`TEMP`，不改用户/系统环境变量。启动 prepare 若发现目标不可写或路径链接逃逸，由 bootstrap 既有错误处理显示 `PortableStorageFailureApp`；数据库实际 open 阶段的复检失败会拒绝打开，不回退 AppData。凭据由 Windows `PortableCredentialStore` 按逻辑 key 保存独立 DPAPI 密文 `.bin`，写入先验证临时密文，再经 `MoveFileEx(REPLACE_EXISTING | WRITE_THROUGH)` 原子替换，不使用 `flutter_secure_storage`/Windows 凭据库；密文绑定当前 Windows 账户，换电脑需重新登录。

普通 Windows runtime 使用便携目录，不调用 `path_provider` 获取 AppData 路径或调用 `flutter_secure_storage` 读写凭据。当前使用空白便携配置，Emby 需重新添加；不导入旧凭据或媒体库状态，也不保留旧数据导入或 schema 迁移兼容。旧数据库/日志、Local 缓存及 Release 便携副本已清理；旧 Roaming 仍残留一个 518 字节 `flutter_secure_storage.dat`，因删除受阻需用户手动清除，新版不读取或改写该文件。

一次性清理仅针对旧应用数据，不允许普通运行时自动清库；代码、Flutter data 资源、SDK 和媒体不在清理范围。全量 `flutter test` **731 passed / 6 skipped**，`flutter analyze --no-pub` 零问题，289 个 Dart 文件格式检查 0 改动，`git diff --check` 通过。Windows Profile `portable_runtime_test` 构建 20.4 秒后 1 项通过，验证进程 TMP 与 `Directory.systemTemp` 同址、切换 cwd 后 log 仍落 exe/log，且真实 mpv 可打开合成媒体。生产 `lib/main.dart` Windows Release **39.2 秒成功**。从 `apps/client/build/portable-launch-cwd` 启动的五秒 smoke 两次通过，最新为 **2026-10-16 15:15:41.0485208 +08:00**；均通过单次 `WM_CLOSE` 正常退出，退出码 0。只读检查新 `userdata` 数据库 sources=0、media=0、credentialFiles=0；exe 同级 `log/` 已生成日志，启动 cwd 保持空，旧 Local 缓存未重建。清理后 Roaming 旧 `flutter_secure_storage.dat` 前后 hash/大小一致（518 字节），新版未改写且不读取；需用户手动删除。ZIP 包 **37,917,144 字节、37 entries**，包含 `reelnest.exe` 和 `data/app.so`，排除 `userdata/`、`cache/`、`log/`、`temp/` 与 PDB。以上只证明本轮 Windows 便携验证，不代表 macOS/Linux 便携。

当前 P2 已修正 `userdata/library` 路径边界：启动 prepare 与 `LibraryDatabase.open` 均验证解析后的 library 目录、数据库和 sidecar 路径位于便携根内，数据库 open 再检查并返回 canonical path；prepare 对嵌套 library 做写权限 probe。启动 prepare 发现越界/不可写时由 bootstrap 既有 catch 显示 `PortableStorageFailureApp`；数据库实际 open 复检失败则拒绝打开、不回退 AppData；未修改全局异常路由。8 项新增路径专项覆盖 Windows junction 与数据库/sidecar symlink，包含内部 junction 正常建库和外部目标未被修改；三文件共 28 项定向测试及全量 753 passed / 6 skipped 通过，analyze 无问题，296 文件格式检查 0 改动，Windows Release 45.7 秒及五秒 smoke 通过。无 schema 变更、无用户数据删除，详见[项目边界 P2 修正](PROJECT_SCOPE.zh-CN.md#p2-修正数据库目录边界校验windows-验证完成)。

发行约束：`scripts/package-windows.ps1` 采用 `reelnest.exe`、`*.dll`、`data/` 白名单创建 ZIP，拒绝覆盖已存在 ZIP，排除运行时 `log/`、`userdata/`、`cache/`、`temp/` 和 PDB；`build.yml` Windows job 上传打包 ZIP。此次 ZIP 白名单核验通过，不含数据库或便携登录态。

以上记录 Windows 本轮已验证的便携路径、启动/关闭、空白数据库与发行包行为。macOS/Linux 的目录和凭据存储约定保持不变，本节不表示其他平台已实现便携化。

## 核心身份

### 来源身份

`sources.id` 是稳定的 `sourceId`。路径、服务器地址和显示名称都不能单独替代来源身份；修改别名或重新定位不得创建新的媒体身份。

当前 `MediaSourceKind` 包含：

- `localFolder`
- `removableDrive`
- `mountedNas`
- `emby`
- `jellyfin`
- `plex`

枚举存在不等于对应连接器已经实现。ReelNest Server 仍属于后续原版能力迁移范围，当前尚未进入该枚举。

Jellyfin 基础视频来源闭环已实现，Windows Release/smoke 已通过。实现使用独立 `sources.kind = jellyfin`、Jellyfin provider/凭据类型及 `jellyfin://` 来源路径；普通 HTTP API 采用 `Authorization: MediaBrowser`，播放/下载 URL 采用 `ApiKey` 查询参数，Emby 既有认证行为保持不变。来源配置使用 `connector.jellyfin.uuid`；共享凭据工厂内部的 `emby.source.<uuid>` 命名按来源 UUID 隔离，并通过 provider kind 校验，不表示二者身份相同。凭据存入既有安全凭据存储，不写普通 SQLite 字段。远程媒体数据沿用现有 `remote_media_metadata`、`remote_media_details`、`remote_library_views` 结构并按 `source_id` 隔离；不新增表、不改变 schema 或执行迁移，`schemaVersion` 维持 1。官方稳定版 OpenAPI 12.3.0 已核对；实施方回报共享协议定向 255/255、同步/界面组 61/61、Emby 基线 37/37、UI 2/2 与 Windows Native 真实 mpv 业务用例通过；analyze 与 421 个 Dart 文件格式检查通过。本批未跑全量 Flutter 测试。真实服务器与其他平台验收待完成。实现与验收边界见[Jellyfin 计划](JELLYFIN_PLAN.zh-CN.md)。

### 媒体身份

媒体主身份是：

```text
(sourceId, localId)
```

`localId` 只在所属来源内唯一。本地来源通常使用来源根目录下可定位的媒体标识；远程来源使用连接器映射后的来源内标识。不同来源中的相同远端 ID、路径或标题不得自动合并。

系列父子关系使用同一 `sourceId` 下的 `parent_id`。播放器、偏好、缓存和远程详情均应携带来源身份，避免账号或来源之间串数据。

## 时间与布尔值

- SQLite 时间字段使用 Unix epoch 毫秒整数，读取为本地 `DateTime` 对象。
- 可空时间使用 `NULL` 表示未发生或未配置。
- SQLite 布尔值使用整数：`0` 为 false，`1` 为 true。
- JSON 中的日期可使用 ISO 8601 字符串；具体以对应模型解析器为准。

## 表总览

| 表 | 类型 | 用途 | 主键/身份 |
|---|---|---|---|
| `sources` | 持久 | 媒体源配置与扫描版本 | `id` |
| `media` | 持久 | 来源隔离的媒体索引 | `(source_id, local_id)` |
| `media_activity` | 持久 | 媒体最近发生有效活动的时间 | `(source_id, local_id)` |
| `playback_states` | 持久 | 播放位置、时长、已看和最后播放时间 | `(source_id, local_id)` |
| `playback_markers` | 持久 | 内嵌章节、手动章节和书签等播放标记 | `(source_id, local_id, id)` |
| `media_library_preferences` | 持久 | 本机想看与人工评级 | `(source_id, local_id)` |
| `player_preferences` | 持久 | 播放器、库视图及模块键值偏好 | `key` |
| `local_movie_metadata` | 持久 | 本地电影 TMDB 详情 JSON | `(source_id, local_id)` |
| `local_series_metadata` | 持久 | 本地剧集 TMDB 详情 JSON | `(source_id, local_id)` |
| `local_episode_metadata` | 持久 | TMDB 季详情与已有本地单集的资料/关联 | `(source_id, local_id)` |
| `remote_media_metadata` | 持久 | 无凭据的远程列表元数据 JSON | `(source_id, local_id)` |
| `remote_media_details` | 持久 | 无凭据的远程详情缓存 JSON | `(source_id, local_id)` |
| `remote_library_views` | 持久 | 远程服务器媒体库目录 | `(source_id, library_id)` |
| `ignored_health_issues` | 持久 | 用户忽略的健康问题 | `(category, source_id, local_id)` |
| `artwork_disk_cache` | 持久清单 | 图片磁盘缓存清单 | `cache_key` |
| `video_disk_cache` | 持久清单 | 视频离线缓存清单 | `(source_id, local_id)` |
| `video_cache_leases` | 持久协调 | 正在使用的缓存租约 | `owner` |
| `video_cache_staging` | 持久协调 | 未提交下载的暂存目录 | `token` |
| `video_offline_subscriptions` | 持久 | 系列自动离线订阅 | `(source_id, series_id)`，另有唯一 `id` |
| `scan_stage` | 临时 | 当前进程扫描/同步成功身份集合 | `(run_id, local_id)` |

### 本地 TMDB 元数据（剧集手动匹配已实现）

`local_movie_metadata` 按 `(source_id, local_id)` 保存 `value` JSON，并关联本地 `media` 条目。本地剧集手动匹配已实现并纳入当前初始 schema：

- `local_series_metadata(source_id, local_id, value)`：以 `(source_id, local_id)` 为主键，保存本地剧集的 TMDB 元数据 JSON。
- `local_episode_metadata(source_id, local_id, series_local_id, value)`：以 `(source_id, local_id)` 为主键，保存已有本地 episode 的 TMDB 季详情元数据及其所属本地系列关联。`(source_id, local_id)` 外键引用 `media`；`(source_id, series_local_id)` 外键引用 `local_series_metadata(source_id, local_id)`；两条外键均 `ON DELETE CASCADE`。

单集关联取自本地 `seasonNumber >= 0` 与 `episodeNumber > 0`；最多 2 个季详情并行请求，不逐集请求。无有效编号时不猜测匹配。匹配只更新已有 episode 的 title/overview/year，保留媒体身份、季集号、路径、图片和播放记录；剧集海报/背景图复用安全本地图片存储，不下载季/单集图片，也不创建 TMDB 季卡。部分季失败保留已有单集资料；同一 TMDB 系列重匹配保留此前成功季。提交时若媒体集合或编号变化则拒绝整事务。重扫保护已确认 title/overview；季号、集号、父级或类型变化会删除失效的单集元数据关联。`schemaVersion=1`，不引入开发中间版本迁移或历史兼容分支。后端定向 102/102、UI 12/12、Windows Profile 原生及 Release/smoke 验证通过；真实 TMDB 公服、macOS/Linux 与人工精确视觉仍待。详见[TMDB 本地剧集计划](TMDB_SERIES_METADATA_PLAN.zh-CN.md)。

## `sources`

媒体源配置。删除来源时，对声明了外键级联的媒体、远程目录、详情和缓存清单执行清理；凭据和无外键协调数据仍由来源仓储显式处理。

| 字段 | 类型 | 含义 |
|---|---|---|
| `id` | TEXT | 稳定来源 ID |
| `kind` | TEXT | `MediaSourceKind` 存储值 |
| `name` | TEXT | 用户可见名称或别名 |
| `location` | TEXT | 目录位置或服务器地址；可能包含隐私信息 |
| `location_key` | TEXT UNIQUE | 规范化位置去重键，不作为用户显示值 |
| `recursive` | INTEGER | 是否递归扫描文件来源 |
| `ignore_hidden` | INTEGER | 是否忽略隐藏文件/目录 |
| `last_scan` | INTEGER NULL | 当前范围的成功扫描/完整同步时间，同时用于部分分页版本保护；扩大 Emby 选库范围时清空标记、保留旧索引，完整同步提交成功后恢复 |
| `access_identity` | TEXT NULL | 挂载卷或平台访问身份，不等同于显示路径 |
| `media_type` | TEXT | 来源媒体分类，默认 `auto` |
| `minimum_file_size` | INTEGER | 最小文件大小，默认 50 MiB；实际规则仍由来源策略解释 |
| `options` | TEXT | `SourceOptions` JSON |
| `created_at` | INTEGER | 创建时间 |
| `updated_at` | INTEGER | 配置更新时间 |

`options` 当前字段：

| JSON 键 | 默认值 | 含义 |
|---|---:|---|
| `autoScan` | `true` | 是否参与自动扫描 |
| `readNFO` | `true` | 是否读取 NFO |
| `preferLocalArtwork` | `true` | 是否优先本地图片 |
| `networkScrapingEnabled` | `true` | 是否允许网络刮削；依赖未接入时不能宣称功能有效 |
| `screenshotFallbackEnabled` | `true` | 是否允许截图回退 |
| `includeInMetadataFetch` | `true` | 是否参与元数据拉取 |
| `preferMetadataWriteToSource` | `false` | 是否偏好写回来源 |
| `includeInHealthCheck` | `true` | 是否参与健康检查 |
| `remoteTraceSyncMode` | `bidirectional` | `bidirectional` / `importOnly` / `disabled` |
| `selectedEmbyLibraryIDs` | `[]` | 已选择的 Emby 媒体库 ID |

保存字段不代表相关执行服务已经全部迁移。模块文档必须说明字段是否真正生效。

## `media`

本地与远程来源共用的媒体索引。删除来源会级联删除其媒体；删除父系列时，子项关系由仓储按业务顺序处理。

| 字段 | 类型 | 含义 |
|---|---|---|
| `source_id` | TEXT | 来源 ID |
| `local_id` | TEXT | 来源内媒体 ID |
| `title` | TEXT | 显示标题 |
| `type` | TEXT | 原始媒体类型；显示分类不应覆盖它 |
| `bytes` | INTEGER | 文件或远程媒体大小；未知值按连接器规则处理 |
| `modified` | INTEGER | 来源更新时间/文件修改时间 |
| `missing` | INTEGER | 文件索引是否暂时缺失 |
| `year` | INTEGER NULL | 年份 |
| `season_number` | INTEGER NULL | 季号 |
| `episode_number` | INTEGER NULL | 集号 |
| `series_directory` | TEXT NULL | 来源根目录下可迁移的系列相对目录 |
| `is_series` | INTEGER | 是否是系列聚合条目 |
| `identity_kind` | TEXT | 媒体身份的来源/解析类型 |
| `parent_id` | TEXT NULL | 同来源父媒体 `local_id` |
| `original_title` | TEXT NULL | 原名 |
| `overview` | TEXT NULL | 简介 |
| `poster_path` | TEXT NULL | 本地或缓存图片身份；不得保存带凭据 URL |
| `backdrop_path` | TEXT NULL | 背景图身份；不得保存带凭据 URL |

索引：

- `media_title(source_id, title COLLATE NOCASE, local_id)`：来源内标题查询。
- `media_parent(source_id, parent_id, season_number, episode_number)`：系列、季集排序和子项查询。

## 播放与用户状态

### `media_activity`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id` | 媒体身份 |
| `updated_at` | 最近导入、播放或相关有效活动时间 |

该表用于首页最近内容和排序，不等同于首次入库时间或服务器最后播放时间。

### `playback_states`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id` | 媒体身份 |
| `position_ms` | 本机播放位置，毫秒 |
| `duration_ms` | 已知时长，毫秒 |
| `watched` | 本机已看标记 |
| `last_played_at` | 本机最后播放时间 |

播放记录只保存仍存在的非系列媒体。远程服务器痕迹另存在远程元数据中，并按来源的同步模式协调。

### `playback_markers`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id`, `id` | 来源隔离的标记身份，删除媒体时级联清理 |
| `kind`, `title` | 标记类型和名称；章节、手动章节/书签及手动片头/片尾范围均已接入 |
| `start_us`, `end_us` | 起止时间，微秒；结束时间可空 |
| `origin` | `embedded`、`manual` 或 `automatic` |
| `review_status` | `accepted`、`pending` 或 `rejected`；当前手动/内嵌标记归一为 accepted |
| `detector_identifier`, `confidence` | 当前内嵌章节候选标识为 `embedded-chapter-keyword`，置信度沿原版为 0.88/0.76；单项和系列任务共用生成链路 |
| `created_at`, `updated_at` | UTC 毫秒时间 |

非空内嵌章节快照在事务内替换该媒体的内嵌章节，保留手动标记；空快照及转码部分时间轴不会清除已保存的完整章节。删除接口只删除指定媒体的手动标记。单片循环开关保存于 `player_preferences` 的 `global.videoLoopCurrentItem`；跳过策略保存于 `global.videoMarkerSkipBehavior`，默认 `prompt`；A/B 点仅在会话内保存，不写数据库。手动片头/片尾及基于内嵌章节生成的自动候选复用本表，无新增表或 schema。自动候选为 pending，采用变 accepted、忽略变 rejected；普通读取隐藏 rejected，生成时包含它以防重复。审核只修改对应身份的 pending automatic 行。当前验证范围和边界见[高级播放接口与规则](PLAYER_PRECISION_BACKEND.zh-CN.md)。

### `media_library_preferences`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id` | 媒体身份 |
| `watchlist` | 本机想看状态 |
| `user_rating` | 本机人工评分；`NULL` 表示没有人工值 |
| `created_at` | 偏好首次建立时间，可参与首页排序 |

### `player_preferences`

通用键值表，`value` 由拥有该键的模块解释。当前用于播放器全局/媒体偏好、清理代次、来源连接非敏感配置、库视图状态、侧栏折叠、缓存目录和容量设置等。

`global.markerAnalysisTasks` 保存片头片尾检测的有界 JSON 任务快照：任务/root 身份、状态、计数、时间和安全错误。最多持久化/恢复 60 条，新插入保留 40 条且保护运行中请求；退出中断的 queued/running 恢复为 failed，不自动重跑。清除记录只删除非活跃快照，不删除 `playback_markers`。私密标题统一为“片头片尾检测”；不存凭据、播放 URL、章节正文或原始异常。此键与持久候选分开提交，记录保存失败会提示但不抹去已提交候选。

播放器截图计划使用现有 `player_preferences`，不新增表、列或 schema：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoScreenshotMode` | enum `name` 字符串 | `subtitles`（带字幕）；另有 `video`（纯视频）、`window`（窗口所见） |

截图输出为 PNG，含影片标题与时间；重名不可覆盖，目标文件原子发布，失败清理未完成文件并限制 PNG 尺寸。Windows 目标为 `resolvedExecutable.parent/userdata/screenshots/`，逐层真实路径校验且不向外部目录回退；macOS 为用户 Pictures 下 `ReelNest 截图/`；Linux 为 `XDG_PICTURES_DIR/ReelNest 截图/`，无该变量时为 `HOME/Pictures/ReelNest 截图/`。macOS/Linux 路径实现和单测已接入，原生实机仍待；移动端不在本阶段范围。

截图实现及 Windows 自动化验证已完成：store/session 11 项、UI 两文件 31 项通过；显式启用 native 的全量测试 859 passed / 1 skipped（可选排序性能基准）；analyze clean、348 个 Dart 文件 format 0 changed、diff-check clean。Windows Profile GPU/SW 截图两项实际功能用例和 viewport 两项实际功能用例通过；Windows Release 40.5 秒成功，五秒 smoke 于 2026-10-22 14:33:44 +08:00 通过。真实用户 Emby、macOS/Linux 原生实机及原版 UI 视觉验收未完成。Windows Profile resize callback 修复范围仅限观测到的竞态，不代表所有历史崩溃均已定位。播放器偏好批量 key 当前为 26；此前记录的 25 是历史截面，保持原样不追溯修改。详见[播放器截图实现与验证](NEXT_STAGE.zh-CN.md#2026-10-22-播放器截图阶段已实现windows-自动化验证通过)。

视频播放器均衡器阶段新增全局偏好键（实现及 Windows 自动化验证完成）：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoEqualizerSettings` | JSON 字符串 | `{"enabled":false,"preset":"flat"}`；8 个预设的 raw name 及原始频点/增益见[视频均衡器计划](PLAYER_VIDEO_EQUALIZER_PLAN.zh-CN.md) |

该 key 使用既有 `player_preferences`，不新增 schema；播放器偏好批量 key 当前为 27，文档中既有 26/25 是历史截面，不回改。后端/UI、native PCM、Windows Profile/全量以及 Release/smoke 证据见[视频均衡器计划](PLAYER_VIDEO_EQUALIZER_PLAN.zh-CN.md)。真实设备听感、Emby 或跨平台验收仍未完成。

播放器画面色彩调整使用下列全局偏好键（本轮实现已完成；Windows Profile、Release 构建及 5 秒 smoke 通过；平台/来源验收边界见[色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md)）：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoColorAdjustments` | JSON 字符串 | `{brightness, contrast, saturation, gamma, hue}`；五项默认均为 `0`，各项归一化为整数 `[-100, 100]` |

每次调整以一个完整对象写入该单一偏好键，不拆分成五个键；此偏好使用既有 `player_preferences` 键值结构，不增加数据库表、列或 schema 版本。读写、归一化与应用契约见[播放器画面色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md)。

播放器性能设置已接入下列全局偏好键；Windows 自动化验证完成，其他平台/来源验收见[当前阶段记录](NEXT_STAGE.zh-CN.md#video-performance-settings)：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoPerformanceSettings` | JSON 字符串 | `{hardwareDecodingMode, memoryBufferingEnabled}`；分别默认 `safe` 与 `true` |

`hardwareDecodingMode` 使用 enum raw name：`safe` → MPV `hwdec=auto-safe`，`automatic` → `auto`，`off` → `no`；`memoryBufferingEnabled` 为布尔值。非法字段独立回落到对应默认，整个 JSON 格式损坏时回落完整默认对象。此键存于既有 `player_preferences`，不新增表、列、schema 版本或迁移。

去色带与 HDR 色调映射设置已接入既有 `player_preferences` 的全局 JSON 键；Windows GPU 自动化验证通过。限制取决于实际 renderer：纯 SW 的任何用户渲染编辑（包括写默认值）都明确拒绝且不保存；读取持久化默认值时无多余告警，读取非默认值时保留 DB 并提示。软件解码 + GPU renderer 仍受支持。跨平台/真实内容边界见[当前阶段记录](NEXT_STAGE.zh-CN.md#video-deband-tone-mapping)：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoRenderSettings` | JSON 字符串 | `{debandMode, toneMappingMode}`；默认分别为 `off`、`auto` |

`debandMode` 为 enum raw name `off`、`light`、`strong`；`toneMappingMode` 为 enum raw name `auto`、`bt2390`、`hable`、`mobius`、`reinhard`、`clip`（其中 `bt2390` 对应 MPV 值 `bt.2390`）。该键使用既有 `player_preferences`，无 schema 变化。Windows GPU Profile、全量与 Release/smoke 验证通过，但数据键存在不代表真实 HDR 设备、Emby 或 macOS/Linux 平台已验收。SW 不支持系 renderer 边界，与硬件解码模式无关。

锐化批次使用下列全局偏好键；该键只保存锐化档位，不含降噪状态。代码已接入该键和 shared owned-filter helper；锐化 Dart 定向 12 项、显式 DLL native 1 项均包含于启用 `REELNEST_MPV_PATH` 的全量 **803 passed / 0 skipped（39 秒）**，全部 8 项 native 实际执行并通过。Windows Profile GPU/SW 用例通过，medium 锐化时字幕/黑画面/暂停 resize 正常，且同一 19 秒运行验证了关闭锐化后的 RGB 语义恢复。headless native 的 Temp namespace 通过 `IOOverrides` 隔离至自身 sandbox；PID 复用解释未由崩溃栈独立确诊。318 个 Dart 文件格式检查 0 改动、analyze clean、diff-check 无错误。Windows production Release 构建 42.5 秒成功；2026-10-18 20:01:52.2262702 +08:00 五秒 smoke 通过（窗口响应、正常关闭、退出码 0）。产物 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，报告 `apps/client/build/smoke/release-startup.json`；macOS/Linux 原生验收待，详见[锐化计划](PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md)：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoSharpenMode` | enum raw name 字符串 | `off`、`light`、`medium`、`strong`；默认 `off` |

此值作为单个字符串写入既有 `player_preferences` 键值结构，不新增 schema。当前实现和验收状态见[播放器画面锐化与滤镜组合计划](PLAYER_VIDEO_SHARPEN_PLAN.zh-CN.md)；降噪目前仅核查依赖和方案，不持久化、不实现。

键空间必须带模块或范围前缀；新代码不能使用含义不明的通用键。JSON、数值和布尔值均以 TEXT 保存，读取端负责校验与默认值。敏感凭据禁止写入该表。

播放器自定义快捷键使用现有 `player_preferences` 全局键：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoKeyboardShortcuts` | JSON 字符串 | 动作 ID → 快捷键列表的 override map；未保存的动作使用代码定义的默认绑定，动作值 `[]` 表示明确清除该动作绑定 |

该键仅保存用户覆盖，不展开写入整套默认表；单动作恢复默认只删除该动作 override，全部恢复默认删除整个 `global.videoKeyboardShortcuts` 键。快捷键配置沿用既有 `player_preferences`，不新增表、列或 schema 版本。该快捷键 JSON 的读取上限为 128 KiB；损坏值回退默认且不自动重写。偏好读取使用单次 SQL 快照；`playback_read_performance_test` 单元 fixture 中该读取路径的 SQLite 计数由 28 次降为 1 次，不是 Profile 原生性能测量。动作范围、录制/冲突及焦点规则见[播放器快捷键迁移计划](PLAYER_SHORTCUTS_PLAN.zh-CN.md)；自动化及 Windows Release/smoke 于 2026-10-24 通过，平台实机与 UI 验收边界仍见计划。

当前字幕样式/音画同步批次已将下列全局默认值接入现有 `player_preferences` 键值表（代码已冻结；Windows 构建及 smoke 通过，平台与 UI 验收范围见[模块记录](PLAYER_TRACKS.zh-CN.md#当前批次字幕样式与音画同步代码已冻结windows-验证完成2026-10-16)）：

| 键 | 值格式 | 默认/内容 |
|---|---|---|
| `global.videoSubtitleStyle` | JSON 字符串 | `{fontName, bold, colorPreset, borderSize, backgroundOpacity}`；默认分别为 `null`、`false`、`white`、`3`、`0` |
| `global.videoDefaultAudioDelay` | 数值字符串 | 秒；默认 `0` |
| `global.videoDefaultSubtitleDelay` | 数值字符串 | 秒；默认 `0` |
| `global.videoDefaultSubtitleScale` | 数值字符串 | 比例；默认 `1` |
| `global.videoDefaultSubtitlePosition` | 数值字符串 | 百分位置；默认 `100` |

这些均为不按来源/媒体区分的全局默认，不代表当前播放媒体身份状态。`VideoSubtitleStyle` JSON 还会把边框/背景范围归一化；`colorPreset` 写 enum 名称。具体读写/恢复代码见 `features/playback/data/player_preferences_repository.dart` 与 `playback_session.dart`；自动化已覆盖全局偏好恢复及存储失败回滚。当前 Windows Profile 字体集成测试验证主/子 engine 字体通道生命周期，不等同于完整偏好持久化或人工 UI 验收。业务目标和失败策略见[播放器字幕与音轨说明](PLAYER_TRACKS.zh-CN.md#当前批次字幕样式与音画同步代码已冻结windows-验证完成2026-10-16)。本批不新增表、不改变 schema，也不清理本机数据。

## 远程来源数据

### `remote_media_metadata`

`value` 是 `RemoteMediaMetadata` JSON，只保存无凭据展示和播放状态字段，例如：

- 服务器媒体 ID、媒体库 ID/名称和集合类型。
- 时长、位置、播放百分比、已看、收藏和评分。
- 艺术家、专辑和题材。
- 媒体源 ID、封装、视频/音频编码、分辨率和码率。
- 最后播放时间。

不得保存访问令牌、密码或已拼接鉴权参数的资源 URL。播放地址由活动会话按需准备。

### `remote_media_details`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id` | 媒体身份 |
| `value` | 白名单详情 JSON |
| `fetched_at` | 获取时间，用于缓存过期 |

详情缓存可包含简介、演职员、角色/部门、图片身份、技术信息、状态、分级、国家、公司、题材、电视网、日期、语言及 TMDB/IMDb 标识。不得保存原始服务器 DTO；原 DTO 的媒体源和人员字段可能携带鉴权资源信息。

### `remote_library_views`

| 字段 | 含义 |
|---|---|
| `source_id` | 远程来源 ID |
| `library_id` | 服务器媒体库 ID |
| `name` | 媒体库名称 |
| `collection_type` | 服务器集合类型，可空 |

选库范围由 `sources.options.selectedEmbyLibraryIDs` 保存；目录表本身不代表用户已经选择该库。

## 健康数据

### `ignored_health_issues`

| 字段 | 含义 |
|---|---|
| `category` | 健康问题类别 |
| `source_id`, `local_id` | 被忽略对象的来源和媒体身份 |

该表当前没有数据库外键，由健康/来源仓储显式清理。忽略问题只改变告警展示，不得修改媒体文件或把离线条目当作安全删除候选。

## 图片与视频缓存

### `artwork_disk_cache`

| 字段 | 含义 |
|---|---|
| `cache_key` | 来源、图片身份和版本组成的稳定缓存键 |
| `source_id` | 来源 ID |
| `filename` | 缓存根目录内文件名 |
| `bytes` | 文件大小 |
| `accessed_at` | 最近访问时间，用于 LRU |

### `video_disk_cache`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id` | 缓存媒体身份 |
| `bundle` | 一组视频、字幕和相关文件的缓存包身份 |
| `root` | 缓存根目录身份 |
| `filename` | 主视频文件名 |
| `bytes` | 缓存大小 |
| `quality_id`, `quality_label` | 画质身份和用户可见名称 |
| `created_at`, `accessed_at` | 创建与最近访问时间 |

### `video_cache_leases`

记录播放器或任务对缓存包的临时占用。`owner` 唯一，`bundle` 指向缓存包，`expires_at` 用于回收过期租约。该表不依赖媒体外键，异常退出后的过期清理由缓存仓储负责。

### `video_cache_staging`

记录尚未安全提交的下载暂存目录。`token` 唯一，`root` 是受控暂存根，`touched_at` 用于清理超时残留。最终缓存必须采用安全提交流程；不能先删除旧缓存再下载新副本。

### `video_offline_subscriptions`

| 字段 | 含义 |
|---|---|
| `id` | 订阅 ID，额外唯一 |
| `source_id`, `series_id` | 所属来源和系列身份 |
| `title` | 用户可见系列标题快照 |
| `mode` | 未看窗口、整季或全系列等订阅模式 |
| `episode_limit` | 未看窗口集数 |
| `season` | 指定季，可空 |
| `quality_id` | 指定画质，可空 |
| `enabled` | 是否启用 |
| `paused_until` | 暂停截止时间，可空 |
| `expires_at` | 到期时间，可空 |
| `network` | 网络策略 |
| `created_at`, `updated_at` | 创建和更新时间 |

删除系列索引会级联删除订阅。订阅删除不等同于自动删除已经存在的离线副本，具体行为由离线模块规则决定。

## 临时扫描数据

`scan_stage` 是每个数据库连接内的 TEMP 表，只记录当前运行的 `run_id + local_id`。成功扫描/同步后用它判断本轮完整覆盖范围内的旧索引；失败、取消、离线、权限异常或挂载身份变化时不能据此把整库条目标记为删除。

TEMP 表不随数据库文件持久化，也不属于备份范围。

## 照片数据范围

2026-10-12 用户明确暂不实现照片模块。照片/相册来源入口、照片查看器、系统照片库、照片搜索和首页照片墙不属于当前产品与验收范围；恢复这些能力需用户重新确认。

该决定不授权删除已有数据或磁盘文件。当前数据层继续遵守以下边界：

- 已存在的照片来源、索引和媒体文件不得自动删除；本项目未发布，不为此次范围调整增加历史 schema 或升级分支。
- 必要的照片文件类型识别、既有数据读取和与影视聚合的隔离可以保留，但不能据此重新暴露照片产品入口。
- 影视海报、背景图、演员头像、剧照和 `artwork_disk_cache` 属于视频元数据与图片缓存，不属于被移除的照片媒体模块。
- 搜索、首页、健康评分和远程选库默认排除照片媒体；若只为保护既有数据执行缺失检测或清理保护，文档与界面不得把它描述为照片功能恢复。

详细产品决定和回归证据见[照片范围记录](PHOTO_SCOPE_DECISION.zh-CN.md)。

## 凭据与敏感数据

以下数据不能写入 SQLite 普通表或提交到日志：

- Emby、Jellyfin、Plex 或 ReelNest Server 密码、Token 和会话密钥。
- 带鉴权查询参数或请求头的资源 URL。
- 用户真实服务器响应中的敏感字段。

Emby 凭据的逻辑 key 按来源隔离，形如：

```text
io.github.user829304.reelnest.emby.source.<sourceId>
```

Windows 当前代码将上述逻辑 key 交由 `PortableCredentialStore` 以 DPAPI 密文文件保存；非 Windows 继续使用原平台 `SecureCredentialStore`。服务器地址和本地目录路径仍可能属于隐私数据，即使它们不是认证凭据。测试报告和截图应脱敏。

## 删除与保留规则

- 删除来源不得删除用户原始媒体文件或服务器媒体。
- `media` 及其大多数用户状态、远程详情和缓存清单通过外键随索引删除。
- 删除索引前必须按来源在线、挂载身份、文件存在性和并发版本重新验证。
- 缓存文件的物理删除由缓存仓储协调租约、暂存和清单，不能只删除数据库行。
- 远程同步失败或取消应保留旧快照；只有成功覆盖的范围可以清理旧索引。
- 清除播放记录和移出索引是不同操作；两者都不应删除原文件。

## 云备份边界

后续 WebDAV 设置备份不能直接上传整个数据库。首版备份范围需按[设置云备份计划](CLOUD_SETTINGS_PLAN.zh-CN.md)筛选：

- 可以考虑：与设备无关、可跨设备恢复的用户设置。
- 需要转换或重新绑定：媒体源配置、库选择和模块布局。
- 默认排除：本机绝对路径、挂载身份、安全凭据、缓存清单、暂存/租约、设备相关目录和临时任务状态。

恢复设计必须在写入前校验版本和内容，不能覆盖仍在运行的扫描、下载或播放事务。

## 结构变更规则

项目正式发布前：

1. 只维护当前初始结构。
2. 修改 schema 时同步更新建表代码、数据字典和当前测试夹具。
3. 不为开发中间版本增加升级分支或兼容测试。
4. 不自动删除开发者本机数据库；结构不匹配时给出明确错误，由用户决定如何处理。

正式发布后的升级和数据迁移必须另行设计，并通过 ADR 确认后再改变本规则。

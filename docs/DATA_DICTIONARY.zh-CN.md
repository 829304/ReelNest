# ReelNest 数据字典

- 状态：Active
- 负责人：数据与文档维护者
- 最后更新：2026-10-12
- 适用范围：`apps/client` 当前本地数据库与敏感数据边界
- 权威范围：数据身份、表用途、生命周期和隐私说明
- 代码依据：`apps/client/lib/storage/library_database.dart`
- 当前 schema：`1`

## 使用说明

本文件解释当前数据结构，实际建表 SQL 仍以 `library_database.dart` 为准。项目尚未发布，不维护开发中间版本升级链；`schemaVersion` 当前为 1，结构不匹配时抛出 `LibrarySchemaMismatch`，不会自动清空或迁移本机开发数据库。

数据库由 Drift/SQLite 管理，默认位置为应用支持目录下的：

```text
library/reelnest.sqlite
```

具体应用支持目录由各平台 `path_provider` 决定。不要在跨平台文档中把某台机器的绝对路径写成固定产品路径。

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
| `media_library_preferences` | 持久 | 本机想看与人工评级 | `(source_id, local_id)` |
| `player_preferences` | 持久 | 播放器、库视图及模块键值偏好 | `key` |
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

### `media_library_preferences`

| 字段 | 含义 |
|---|---|
| `source_id`, `local_id` | 媒体身份 |
| `watchlist` | 本机想看状态 |
| `user_rating` | 本机人工评分；`NULL` 表示没有人工值 |
| `created_at` | 偏好首次建立时间，可参与首页排序 |

### `player_preferences`

通用键值表，`value` 由拥有该键的模块解释。当前用于播放器全局/媒体偏好、清理代次、来源连接非敏感配置、库视图状态、侧栏折叠、缓存目录和容量设置等。

键空间必须带模块或范围前缀；新代码不能使用含义不明的通用键。JSON、数值和布尔值均以 TEXT 保存，读取端负责校验与默认值。敏感凭据禁止写入该表。

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

## 凭据与敏感数据

以下数据不能写入 SQLite 普通表或提交到日志：

- Emby、Jellyfin、Plex 或 ReelNest Server 密码、Token 和会话密钥。
- 带鉴权查询参数或请求头的资源 URL。
- 用户真实服务器响应中的敏感字段。

Emby 当前使用按来源隔离的 `SecureCredentialStore`，键形如：

```text
io.github.user829304.reelnest.emby.source.<sourceId>
```

服务器地址和本地目录路径仍可能属于隐私数据，即使它们不是认证凭据。测试报告和截图应脱敏。

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

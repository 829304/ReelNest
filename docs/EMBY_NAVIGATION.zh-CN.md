# Emby 视频媒体库导航与浏览

实现日期：2026-10-10。此批接入来源树、分库浏览、搜索、观看筛选、类型筛选、排序和本机想看状态；不代表完整 Emby 或原版 UI 已验收。音乐按用户决定留给独立模块，已有 Audio 同步保留。

## 原版依据

- `Sources/MediaLib/Views/ContentView.swift`：`EmbyLibrarySection`、`embySourceGroup`、`SidebarMetrics`。按来源分组，显示非空的全部视频/想看/收藏，以及服务端命名库；来源可折叠和右键重命名。音乐和音乐最近播放留给后续模块。
- `Sources/MediaLib/Views/LibraryView.swift`：`LibrarySnapshotBuilder`、`availableSortModes`、`selectSortMode`、浏览状态恢复。搜索延迟 180 ms，按当前目的地筛选、排序；分库使用来源 ID 和库 ID 双重定位。
- `Sources/MediaLib/App/AppState.swift`：`items(for:)`、`searchFields(for:)`、`toggleWatchlist`。想看是本机状态，不调用 Emby 写回接口；收藏/观看沿用已实现的远程痕迹模式。
- `Sources/MediaLib/App/PinyinSearchMatcher.swift`：原子串、拼音和首字母匹配语义。具体搜索平台差异见下文。

## 本批行为

侧栏加入已保存的 Emby 来源。全部视频、想看和收藏只在有对应顶层内容时显示；非音乐的命名库即使为空也保留入口。来源折叠状态写入 SQLite，右键重命名复用原来源设置保存，不触发额外扫描。不同账号/服务器的同名库和同 ID 条目始终隔离。

同步成功时，服务端 Views 目录与媒体快照在同一事务提交。分页、数据库写入或取消失败均保留上次目录和媒体索引。仅浏览、搜索、筛选及修改想看不请求服务器；封面加载仍使用已有鉴权图片入口。离线图片持久缓存尚未实现，不能把可浏览索引等同于离线图片已就绪。

浏览只展示顶层视频，按当前库/全部视频/想看/收藏限定范围，再取搜索与类型、观看筛选的交集。搜索覆盖标题、原名、简介、年份、ID、类型、编解码器、清晰度、已缓存详情人物/公司/国家以及子集标题和季集编号。系列可由已同步单集的搜索字段命中，不把单集混入顶层海报墙。超过 180 项的过滤和排序在独立 isolate 执行，海报网格按需构建，不受旧的单页数量限制。

观看筛选沿用全部、正在观看、未观看、已观看、想看和喜欢；使用全局已看阈值，默认 90%，阈值保存会使结果刷新。排序包括最近更新、最近添加、标题、年份、时长、观看进度、评分、评级；时长/评分/评级仅在当前范围有数据时显示。标题默认自然升序，其余默认较新/较大优先；重复选择同项反向，主值相同时标题仍升序。最近添加保留首次入库时间，重同步不覆盖本机想看与初始评级。

排序、方向和观看筛选按来源及目的地分别持久化。搜索和类型不跨应用重启恢复；打开详情后返回保留当前页面的搜索、筛选和位置。详情操作条加入想看/移出想看，读状态尚未完成时禁止错误地以默认值切换。设置写入失败显示错误，不调用无关服务端。

## 代码边界

| 文件/目录（相对 `apps/client/lib`） | 职责 |
|---|---|
| `features/sources/domain/emby_library.dart` | 目的地、筛选/排序模型、纯搜索与结果排序 |
| `features/sources/data/emby_library_repository.dart` | 本机目录快照、观看状态联合读取、想看及浏览偏好 |
| `features/sources/application/emby_library_providers.dart` | 索引变更刷新、目的地结果和大库 isolate |
| `features/sources/presentation/emby_sidebar.dart` | 来源分组、命名库导航、折叠/重命名 |
| `features/sources/presentation/emby_video_library_page.dart` | 搜索、筛选、排序、扫描入口及海报墙 |
| `features/sources/data/emby_sync_repository.dart` | 组合 Views 和媒体的原子提交 |

当前独立表 `remote_library_views` 使用来源/库 ID 复合主键；`media_library_preferences` 使用来源/媒体 ID 复合外键，随媒体删除。只维护当前初始结构，未添加历史升级、自动清库或旧数据库导入。

## 仍待迁移与验收

本批不是完整 `LibraryView`：批量选择/右键操作、手动集合、离线缓存筛选、公共海报设置/其他布局与原版其他功能仍保留在迁移清单中。库名/类型/题材推断的显示分类尚未迁移为完整公共分类策略；当前媒体身份和播放类型沿用同步器，后续首页分类须接入原 `RemoteLibraryClassificationPolicy`。

中文拼音使用锁定的 [lpinyin 2.0.3](https://pub.dev/packages/lpinyin)，已覆盖常见汉字全拼/首字母与英文词首字母。尚未等效原 `CFStringTransform(.toLatin)` 对全部文字体系、重音和地区排序的处理；当前数字分段自然排序也不能替代完整 `localizedStandardCompare`。这些属于未迁移的一致性项，不视为用户同意降级，后续公共搜索/排序适配需继续补齐。

侧栏使用原 252 宽、22 缩进、11 图文间距、10/9 内边距、12 圆角与 13.5 字号；网格沿用最小 150、列距 20、行距 30。系统字体/SF Symbols、菜单材质、完整主题和动画仍未通过原版逐项视觉验收，不能称一比一完成。

接下来仍按已确认顺序做原版画质切换/Emby 转码取流、图片持久缓存/预热、视频离线下载与字幕缓存，再进入首页。TMDB 和完整人物推荐属于公共元数据模块；真实 Emby 连接验收继续延后，不将本机模拟服务通过当作真实兼容性通过。

本轮验证见 [2026-10-10 测试记录](TEST_REPORT_2026-10-10.zh-CN.md)。

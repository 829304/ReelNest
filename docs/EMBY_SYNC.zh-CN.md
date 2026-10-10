# Emby 分页同步与浏览（E2）

更新：2026-10-09。接续 [E1 连接与选库](EMBY_CONNECTION.zh-CN.md)，属于 [Emby 基础闭环计划](EMBY_PLAN.zh-CN.md) 的第二批。远程播放和观看进度上报属于 E3，尚未接入；不能将本批理解为完整 Emby 支持。

## 原版依据与行为

只读对照 `Sources/MediaLib/App/EmbyService.swift` 的 `fetchItems`、`fetchItemPage`、`mediaItem`、`syntheticSeriesParents`、图片接口及评分规则；对照 `AppState.importEmbyItems` 的完整抓取后替换，以及 `SourcesView` 连接/改选库后的同步行为。分页边界参考原 `EmbyServicePaginationTests`，详情和网格沿用此前从 `DetailView`、`EpisodeListView`、`PosterGridView` 迁移的组件。

- `Users/{userID}/Items`，递归查询 `Movie,Series,Episode,Audio`，默认每页 300 条，最大 10000 页。字段沿原请求清单，不额外请求服务端路径或昂贵的顶层 MediaStreams。
- 按已选 Views 分别分页；全部模式接入所有库。合法空 Views 在全部模式回退根查询；指定库已不存在时形成空范围，与原版一致。不同页/库按来源内服务器 ID 去重。
- 电影、系列、剧集和音频分别映射到公共索引；保留原名、简介、年份、评分、时长、分类及基础音乐字段，剧集关联 SeriesId 并保存季/集号。缺少系列条目时，用 SeriesId+SeriesName 补系列；真实系列数据优先。
- 评分只接受有限且大于 0、不超过 10 的值。图片采用原 Primary 和 Backdrop 接口及尺寸参数；没有令牌的普通图片标识进入 SQL，访问时才用当前来源会话请求。
- 首次登录保存后自动同步；改变库范围显示“保存并同步”，策略单独调整只保存。媒体源支持手动同步/取消、扫描全部队列，以及缓存索引浏览；离线不清空既有媒体。

## 完整性与取消

先获取、校验并映射完整快照，再在单个 SQLite 事务中写入父子索引、附属元数据、删除缺失项并更新上次成功时间。网络失败、异常响应、SQL 写入失败或取消，不会留下半个新快照，也不删除旧条目或旧播放记录。成功清理严格限定当前 sourceId，关联元数据随条目删除。

重复非空页、页数超限、已声明总数下提前空页、分页重叠造成遗漏、分页期间总数改变及无法补全的系列关系，均中止并保留旧索引。这里比“停止翻页后把已读部分当成功结果”更严格，避免损失索引。服务端同时发生增删改而总数不变，客户端无法仅靠分页接口保证服务端快照一致性；真实服务器验收仍须检查。

取消会中止正在读取的 HTTP 请求，排队取消不执行；应用关闭会等待任务退出后关闭数据库。同步期间禁止修改范围或移除来源。来源协调器使用既有顺序队列，Emby 同步通过独立同步仓储，不经文件适配器，也不探测远程 ID 对应的本地文件。

## 实现位置

- `lib/api/emby/emby_item.dart`、`emby_client.dart`：分页 DTO、查询与二进制图片请求；JSON 默认 4 MiB、图片 16 MiB、错误正文 8 KiB，流式读取达到上限即停止。401 请求最多重新认证一次，403/限制接入不循环登录。
- `lib/sources/emby/emby_library_synchronizer.dart`、`emby_item_mapper.dart`：纯抓取与映射，独立于 Widget/SQL。
- `features/sources/data/emby_sync_repository.dart`：组合连接与索引；`SourceRepository.syncRemote` 负责互斥、取消、事务和完成通知。
- `domain/remote_media_metadata.dart` 与当前模块表 `remote_media_metadata`：保存无凭据的来源内条目标识、所属库、基础媒体及服务器观看字段。观看字段目前只是元数据，不代表 E3 播放器痕迹协调已完成。
- 媒体源页面接入同步状态；来源浏览与详情复用现有网格/季集布局，图片通过按来源/条目/扫描版本隔离的 provider 读取并限制解码尺寸。资源刷新不依赖旧 Mlink 路由。

本批只维护当前模块表，沿用现有模块的幂等建表方式；没有历史升级分支、ALTER 兼容链或自动清空开发数据。仍只有 `apps/client` 一个 Flutter 包，没有新建空 packages。

## 验证

新增 21 项 E2 单元/组件回归，全量 206 项通过。覆盖真实本机 HTTP 分页/代理路径/字段、库范围/空 Views、缺总数/短页、去重/音乐/系列补全、评分规则、异常关系、重复/重叠页/总数变化、网络与 SQL 回滚、取消与设置互斥、跨来源清理、图片认证/大小限制，以及完整添加向导自动同步和浏览到季集详情。

Windows 4 项原生业务场景通过（工具 `+5` 含 tearDownAll，驱动退出码 0）。原 Emby 安全存储场景增加真实 SQLite 快照同步、内容读取与本机 HTTP 图片获取；原有三项 mpv/字幕/独立窗口/EOF 回归保持通过。静态分析无问题，134 个 Dart 文件格式检查无变化。没有连接用户真实 Emby 做本批验收。

## 仍待完成

下一批 E3 接入鉴权播放资源、mpv 网络播放/续播/队列和开始/进度/停止上报，按原同步模式协调观看状态。完整详情扩展、收藏操作、服务器字幕、海报预热/磁盘缓存和其他原功能继续保留在迁移清单中。

当前复用的网格、详情与来源卡片仍有此前记录的视觉缺口；类名中的 Local 是旧阶段命名，文件/Emby 共用布局并按来源分支取资源，不代表把 Emby 当成本地目录。完整侧栏库树、材质、字体、图标、动效及原 macOS 逐项对照尚未验收；播放入口在 E3 接通前禁用。macOS/Linux 原生与真实 Emby 最终验收仍待后续环境。

用户本轮明确要求清理旧 Release 和开发数据库。删除命令两次被自动审批以“blocked by policy”拒绝，未执行删除；开发数据库及旧运行目录保留。本批采用覆盖构建，不声称清理完成。相关路径为 `apps/client/build/windows/x64/runner/Release` 和 `C:/Users/hzx/AppData/Roaming/io.github.user829304/reelnest/library/reelnest.sqlite`。数据库目录中的历史手动备份也未删除。没有修改原 MediaLib 或提交/推送代码。

## 最终 Windows 构建与启动

最终 Windows Release 正常入口构建成功，30.9 秒。原生启动器本批未变，EXE 时间仍为 18:36:04；Dart 业务产物 `data/app.so` 更新于 **2026-10-09 19:41:00**，大小 **8,930,184 字节**。进程 **28004** 启动 5 秒后创建 ReelNest 主窗口且仍响应，stderr 仅 Impeller 提示。

随后发送正常关闭请求，首次等待 15 秒仍未退出；后续复核进程已退出，没有强制终止。该退出延迟记录为待复核的 Windows 行为，不据此声称关闭时延已验收。本轮没有打开真实 Emby 来源页面或执行真实服务器同步，应用现已关闭，方便处理开发数据库。

运行包：`C:/Users/hzx/workspace/829304/ReelNest/apps/client/build/windows/x64/runner/Release/reelnest.exe`。依旧需要完整 Release 目录运行。没有成功清空旧目录，不能把此次覆盖构建描述为 clean build。

日志均为本机忽略文件，位于 `apps/client/`：`emby-e2-full-tests.log`、`emby-e2-analyze.log`、`emby-e2-native.log`、`emby-e2-release-build.log`、`emby-e2-final-startup.stdout.log` / `.stderr.log`。原生测试中既有 AXTree/CUDA/结果插件提示仍出现，未将它们记作已修复。

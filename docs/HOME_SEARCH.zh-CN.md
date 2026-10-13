# 首页跨来源视频搜索

实现日期：2026-10-12。属于首页 H2；运行状态与 H3 首页编排另行推进。

## 原版依据

- `Sources/MediaLib/Views/HomeVividComponents.swift`：`HomeVividHeader`、`HomeVividSearchControl`。
- `Sources/MediaLib/Views/HomeView.swift`：180 毫秒延迟提交、回车立即提交、清空回总览及详情返回上下文。
- `Sources/MediaLib/Views/GlobalSearchView.swift`：分组顺序、标题排序、40×60 海报结果行与搜索/空结果状态。
- `Sources/MediaLib/App/AppState.swift`：`mediaSearchFields(for:)`。
- `Sources/MediaLib/App/PinyinSearchMatcher.swift` 与 `Sources/MediaLibCore/Database/MediaDetailRepository.swift`：匹配规则及缓存资料字段。

## 已接通

首页页头增加 230×41、圆角 13 的搜索控件；横向放不下时移到标题下方。输入暂停 180 毫秒后搜索，回车立即提交，清空后恢复总览。搜索在同一页面滚动区域显示，视频结果进入既有首页详情路由，返回保留查询和位置。

统一搜索本地目录、移动盘、已挂载 NAS 与 Emby 的已有索引。按电影、电视剧、动漫、纪录片、综艺、其他排列分组；复用自然标题排序与拼音/首字母匹配。每行使用 40×60 海报、标题、类型/年份/题材/评分及详情箭头，惰性创建，不一次创建全库组件。

字段包含标题、原名、年份、简介、已有题材及编码资料；缓存 Emby 详情额外提供演员、角色、演职部门、制作方、电视网、国家、状态、分级、日期、语言和已有外部编号。单集名称、简介与季集标记匹配其所属系列，不独立铺开单集结果。没有逐条访问服务器获取资料，也不新增 TMDB 搜索请求。

来源资格和 SQL 范围复用首页现有规则：排除保险库、照片和本批延期的音乐，过滤 Emby 未选择的媒体库；来源 ID 与条目 ID 共同构成身份。未完整同步的 Emby 明确显示“已载入范围”，搜索不触发完整同步。

各来源独立返回结果，失败来源显示错误并允许重试，其他来源的结果仍可用。失败不能假称没有结果。大于 180 条的匹配与汇总排序放在工作 isolate；查询替换、清空或依赖失效时取消并终止旧工作 isolate。关键词及来源配置分别进入 provider 身份，读取结束再次核对来源范围，防止旧查询/选库/路径的结果混入新范围。

详情返回采用保留旧值的依赖刷新。进入详情前解除当前输入焦点，避免返回时 Flutter 为显示搜索框光标而自动滚回页头。

## 文件职责

- `home_repository.dart`：共享公开范围，读取索引和缓存详情快照，匹配字段构建。
- `home_search_worker.dart`：可取消工作 isolate，收尾、退出与错误转发。
- `home_search.dart`：来源范围身份、分类及结果汇总。
- `home_search_providers.dart`：独立来源查询与增量汇总、过期任务处理。
- `home_header.dart`、`home_search_results.dart`：原页头控件、分组和惰性结果行。

上述客户端文件均位于 `apps/client/lib/features/home/` 的对应层。缓存详情新增的可选展示字段沿用现有 JSON 存储，不增加数据库升级链。

## 范围与验收边界

搜索只匹配已经入库/缓存的资料。尚未加载的 Emby 条目和详情不会因输入关键词自动下载；本地尚未迁移的演员/制作方等元数据也不会凭空生成。外部磁盘离线时仍可搜索已有索引，实际播放继续使用既有目录安全检查。

音乐、公共人物搜索与其他连接器仍在相应模块的后续范围。照片搜索已按用户 2026-10-12 的决定移出当前产品、计划与验收范围；保留照片数据隔离不代表保留搜索入口。复用的 `libraryTitleCompare` 提供数字段自然排序；本批没有引入新的系统区域排序实现，其与 macOS 原生区域排序的完整一致性仍待桌面专项验收。

本批回归覆盖字段/拼音、单集归系列、跨来源同 ID、选库与隐私、慢来源/局部失败、清空/过期查询、后台取消/异常、大结果后台汇总，以及三个桌面目标的组件交互、来源刷新和详情返回位置。组件平台变体不等于 macOS/Linux 原生验收；正式 Windows EXE 启动检查也不等于真实 Emby 全库实测。

## 本批验证结果

- 全量 **499 项 Dart 测试通过**（1 分 40 秒）；新增 17 个测试实例覆盖本批行为。输入/清空及详情返回检查分别运行 Windows、macOS、Linux 组件平台变体。
- Dart 静态分析无问题；变更代码格式和差异空白检查通过。
- Windows Release 构建通过（42.4 秒），业务产物 `apps/client/build/windows/x64/runner/Release/data/app.so` 已更新。
- 2026-10-12 14:45:30 +08:00 完成正式 EXE 五秒启动冒烟检查：窗口消息循环有响应、正常关闭、退出码 0。日志位于被忽略的 `apps/client/build/smoke/release-startup.json`。
- 已检查 1088×720 Windows 组件渲染预览，位于被忽略的 `apps/client/build/home-search/search-preview.png`。

本批未做真实 Emby 大库搜索实机验收、滚动帧率测量或 macOS/Linux 原生构建运行；不将以上检查扩大解释为这些验收已经完成。

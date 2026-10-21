# 性能检查：2026-10-21

检查范围：Emby 媒体库查询与排序、演员缓存查询、首页轮播的后台活动条件。此次不修改产品规则、数据库结构或本机数据。

状态：媒体库排序、演员作品批量读取和观看/评分偏好增量刷新均已实现并通过相应自动化验证及 Windows Release/smoke；持久搜索 isolate 优化未实施。真实大库可见 UI、macOS/Linux 原生性能仍待验收。本文为审查与后续实现记录；摘要见[当前阶段](NEXT_STAGE.zh-CN.md#2026-10-21-emby-媒体库排序性能优化)。

## 已优化：媒体库排序的重复标题解析

`filterVideoLibrary` 原来每次比较都会对两个标题重新分段、转小写并解析数字；标题排序以及其他排序的同值条目都会重复做这些工作。现在按一次排序维护惰性的标题解析表，同一标题只解析一次，排序完成即可回收，不增加跨页面持久缓存。标题相等时不再重复执行第二次比较。

参考原版 `Sources/MediaLib/Views/LibraryView.swift` 的主排序、反序和标题次级排序规则。保留现有自然数字排序、大小写处理、前导零、超长数字和 ID 决胜顺序；没有改变原有地区排序能力边界。

### 本机基准

固定随机种子 42，10,000 条中英混合带数字的模拟标题。每种模式先预热一次，再测五次取中位数；两版运行相同测试。以下为 Flutter test 环境内排序函数耗时，含过滤与本次排序解析表创建，不含页面渲染、数据库、isolate 启动或网络时间。

| 场景 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 标题排序 | 798.938 ms | 50.678 ms |
| 年份相同，按标题决胜 | 815.694 ms | 51.528 ms |

该数据不能解释为整页快约 16 倍。实际收益取决于条目数量、标题结构以及主排序值的重复程度。解析表带来单次排序内的临时内存开销，规模受参与排序的标题数量和长度约束。

重测命令（在 apps/client 中）：

```powershell
fvm flutter test --no-pub --dart-define=RUN_SORT_BENCHMARK=true test/library_sort_performance_test.dart
```

基准默认跳过，不设机器耗时阈值。基准显式启用后，修改前 `sort-before.log` 和修改后 `sort-after.log` 均为 **2 项通过**（自然标题正确性与基准）。功能回归分批通过：媒体库导航及首页搜索/推荐/仓库相关测试 **64 项通过**；首次组合命令把离线订阅测试误写为不存在的 `emby_offline_subscription_test.dart`，因此该命令最终失败，不能记为全绿。随后以正确文件 `emby_offline_test.dart` 单独复验 **19 项通过**；两组功能回归合计 **83 项**。测试覆盖排序正反序、其他排序主值相同后的标题顺序、超长数字、前导零及输入列表不被改写。

`performance-analyze.log` 显示最终静态分析无问题；`git diff --check` 通过。Windows Release `performance-release-build.log` 记录 **47.5 秒**构建成功，产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，未制作发行包。随后五秒隐藏窗口 smoke 检查窗口响应及正常关闭，`ExitCode=0`；`build/smoke/release.stderr.log` 只有 Impeller 渲染后端信息。这些不等同于真实大库可见 UI 或 macOS/Linux 原生性能验收。

可复核日志位于 `apps/client/`：`sort-before.log`、`sort-after.log`、`performance-regression.log`、`performance-offline.log`、`performance-analyze.log`、`performance-release-build.log`。日志与自动化测试结果用于本批证据，不作为发布包或真实服务器性能的证明。

## 后续实现：演员作品批量读取与偏好增量刷新（2026-10-21）

首轮审查识别的前两个热点已完成优化，详细实现与回归见[增量读取记录](LIBRARY_INCREMENTAL_READS_2026-10-21.zh-CN.md)：

- `cachedPersonWorks` 保持同来源有效会话缓存优先；缓存未命中后，通过 `indexedSelection` 分别批量读取作品与父剧集，保留父项去重、库范围、来源隔离、关联顺序/排序和音乐排除。1000 条剧集关联测试的本地回退固定为 4 次 SELECT（来源、关联 ID、作品、父项），不再逐作品或父项查询。
- 想看/评分事务成功后发布分来源偏好版本，并保留原全局通知。Emby 快照拆为内容基础快照与轻量偏好覆盖：只重查当前来源的偏好表，复用内容元数据与值未变的条目对象；必要时重建筛选索引。播放器通知及显式错误重试会失效内容基础快照。其他来源不会因本次偏好变化重新加载，但首页等既有全局通知订阅者仍可刷新自己的查询。
- 该方案不是所有操作 O(1)，偏好覆盖仍读取当前来源偏好并遍历快照；没有实现常驻拼音搜索 isolate。新增相关回归 80 项通过，全量 **838 passed / 10 按配置跳过**，analyze 与 diff 检查通过；Windows Release 和五秒隐藏窗口响应/正常退出 smoke 通过，退出码 0。未宣称真实大库可见 UI、macOS/Linux 原生性能验收完成，也未制作发行包。

日志：`apps/client/incremental-final-tests.log`、`incremental-all-tests.log`、`incremental-analyze.log`、`incremental-release-build.log`。

## 首轮审查发现与当前状态

- 首轮发现的 `cachedPersonWorks` N+1 查询已由上述批量读取实现解决；保留发现时的原始描述作为审查历史，当前实现见[增量读取记录](LIBRARY_INCREMENTAL_READS_2026-10-21.zh-CN.md)。
- 首轮发现的想看/评分触发 Emby 整来源快照重读已由分来源偏好版本和覆盖快照解决；原全局通知继续保留，且首页等其他订阅者仍会收到通知。当前边界见[增量读取记录](LIBRARY_INCREMENTAL_READS_2026-10-21.zh-CN.md)。
- 大列表搜索使用短生命周期 `Isolate.run`；拼音静态缓存不能跨这些 isolate 保留。持久搜索工作 isolate 尚未实现；如后续评估，需先测量真实输入延迟及内存，不能把审查建议写作已完成。

首页轮播代码已有窗口生命周期、TickerMode、当前路由等活动条件判断，此次没有仅因存在 Timer 就更改轮播行为。

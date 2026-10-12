# 来源刷新与页面生命周期修复

## 原因与修改

`sourcesProvider` 依赖 `sourceChangesProvider`，分页入库、收藏及播放痕迹更新等事件会重新查询来源。Riverpod 的依赖重载状态为携带旧值的 `AsyncLoading`；`asData` 只匹配当前 `AsyncData`，重载时返回 NULL。此前 `SourceLibraryPage` 因此错误地将 Emby 分支换成普通列表，销毁页面、滚动控制器、选择集合及前台分页游标。详情页也会将“有旧数据但暂时取不到来源”误判成来源已移除。

修复只调整展示层的异步状态处理：

- 媒体库入口和详情页通过 `AsyncValue.value` 读取刷新期间保留的已有来源；不把重载等同于没有来源。
- 已有来源可以在来源列表刷新失败时继续展示；没有可用来源时仍显示错误。只有来源查询结束且结果确认不含当前来源，才显示“此媒体源已移除”。首次没有缓存数据时继续显示加载状态。
- 普通列表首屏与详情数据的 `when` 显式保留依赖重载期间已有内容，避免由同一来源事件再次替换内容子树。
- 不增加导航缓存，不另存一份来源状态，不改来源查询、同步或删除协议。改变目标来源/分类仍按原页面的 `didUpdateWidget` 重置；真实来源删除仍卸载 Emby 页面。

## 回归范围

`source_page_lifecycle_test.dart` 新增 3 项组件回归：

1. 使用真实 Riverpod 来源事件、SQLite 分页入库及 `EmbyBrowseCursor`，只替换 HTTP 边界；收藏触发的慢来源刷新期间，断言确实处于 `AsyncLoading` 且 `asData == null`，页面 Element/State、滚动位置和多选数保持；分页顺序仍为 0 → 60 → 120，不重复请求第一页。
2. 详情页在来源刷新中保留内容，不误报移除；真实删除且来源查询结束后正确显示移除提示。
3. 首次加载、带旧数据的刷新失败与真实移除分别处理，刷新失败不会重建已有 Emby 页面。

专项 3 项组件回归通过；全量 **482 项 Dart 测试通过**（1 分 28 秒），静态分析通过，3 个修改的 Dart 文件格式与差异空白检查通过。

Windows Release（`lib/main.dart`）构建成功，耗时 34.1 秒；2026-10-12 10:59:12 +08:00 完成 5 秒启动检查，窗口有响应、正常关闭、退出码 0。新版产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`。

测试与构建日志为 `apps/client/source-lifecycle-tests.log`、`source-lifecycle-full-tests.log`、`source-lifecycle-analyze.log`、`source-lifecycle-build.log`，启动记录为 `apps/client/build/smoke/release-startup.json`，不提交日志与构建产物。组件测试与启动冒烟不等同于真实 Emby 服务器交互或三端原生验收。

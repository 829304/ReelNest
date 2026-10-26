# 缓存关闭取消与计时（2026-10-26）

此前 `close_cache` 约 4.9 秒只定位到缓存服务，不能证明其中每一步都是必要等待。本轮对照原 `AppColors.swift` 的 `ArtworkDecodeCoordinator.cancelAll/runWithPermit`，补齐取消检查，不改变缓存预算、图片内容和正常浏览流程。

- 关闭后拒绝新的 artwork 请求；磁盘读取和网络返回后检查关闭状态，不继续排队校验或更新访问时间。
- 解码许可队列支持调用方取消：撤销尚未取得许可的任务，不关闭其他调用方共享的队列。已经运行的原生操作仍完成资源释放。
- 图片文件写入后、取得发布锁后检查关闭状态；尚未发布则清理本任务临时文件。已经进入重命名/清单提交的操作完成提交或原有回滚流程。
- 关闭时跳过未开始的图片清理和视频维护；清理循环在安全边界停止，不中断正在执行的单项删除。
- 没有为整个 dispose 添加超时放弃，也不提前关闭数据库。

## 诊断

主窗口现有关闭 trace 增加 `close_cache_pending_*`，记录关闭开始时图片任务所处阶段（不包含来源 ID、URL、路径）。阶段完成时记录 `close_cache_artwork_*` 耗时：目录准备、磁盘读取、磁盘/下载后校验、网络、文件写入、发布、图片清理；另记 video_tasks 和 image_tasks 两段等待。

阶段耗时包含关闭前已运行的时间；publish 包含其内部 prune，不能相加作为总关闭耗时。pending 事件的 0 只是状态标记。全局实际关闭耗时仍以 close_cache begin/completed 为准。

## 验证

`emby_quality_cache_test.dart` 与 `artwork_image_pipeline_test.dart` 共 46 项通过。新增磁盘命中和下载后两类排队校验测试：共享队列的占用任务不释放，cache.dispose 仍在一秒测试上限内完成；已有缓存保留、未发布图片不落清单、关闭后请求被拒绝、共享队列随后仍可正常使用。既有缓存替换/取消、租约和清理保护测试继续通过。记录：`apps/client/cache-close-tests.log`。

这些测试验证取消行为，不等于真实用户媒体库的 4.9 秒已消除；需结合新的关闭阶段日志复验。

最终 flutter analyze 无问题，Windows Release 构建通过（46.5 秒）。2026-10-26 13:51:47 +08:00 五秒 smoke 响应正常、正常关闭、退出码 0。`playback-38564-1792993901909168.jsonl` 记录 image_tasks 和后台任务收尾 199 ms、数据库关闭 1 ms，elapsedMs 201 时请求原生关闭。该次启动/退出没有复现此前 4.9 秒的具体任务状态，不作为所有活跃下载或真实大库的耗时保证。验证记录：`cache-close-analyze-final.log`、`cache-close-build.log`。

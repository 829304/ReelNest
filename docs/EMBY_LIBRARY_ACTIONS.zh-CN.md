# Emby 视频库右键、多选与图片内存缓存

实现日期：2026-10-10。限 Emby 视频，音乐后续统一迁移；原 MediaLib 只读参考。

## 原版依据

- `Views/VideoItemContextMenuItems.swift`：播放、观看、想看、喜欢、评级和历史记录，远程内容不提供本地重新分类；单集无独立记录时可删除所属系列的记录。
- `Views/LibraryView.swift`、`App/SelectionStore.swift`、`App/AppState+BatchSelection.swift`：选择/完成、海报选中标记、可见范围全选、浮动批量栏和移出索引确认。
- `Views/VideoCacheMenuItems.swift`：手动缓存/清晰度、删除副本、自动缓存系列；复用已实现的缓存服务。
- `App/AppState.swift`、`MediaLibCore/Database/MediaRepository.swift`：清除记录递归包含子项，阻止旧播放器稍后恢复已清除的记录。
- `Views/AppColors.swift`、`Views/PosterGridView.swift`：512 MiB/1800 张解码缓存，3 路解码、4 路预热；海报解码目标 512×768 像素，预热接下来两行。

## 已接入

海报和单集共用右键菜单。电影/系列提供播放；系列从现有季集顺序选择可播放单集。菜单接入手动缓存、画质、删除副本和自动订阅；观看操作展开系列及已索引子集，重叠目标去重。想看和 1–5 星评级只保存在本机，喜欢和观看按已有三种痕迹模式写回 Emby。远程写回部分失败保留本机更新并报告失败数，继续处理后续目标。

视频库提供“选择/完成”、22 像素圆形标记及 2.5 像素选中边框。浮动栏按原版提供全选/取消全选、已看、未看、想看、评级、清除记录和移出库；圆角 16、控件高 30、间隔 8。搜索或筛选不会丢弃隐藏选中项；全选只增减当前可见范围，批量操作作用于全部选中项。退出清空选择；索引变动移除已不存在的选中项。

想看/评级先校验全部身份，再以单个 SQLite 事务更新。清除评级的显式空值不会重新回落到服务器评分，同步后仍保留。移出库先确认，再按子项到父项顺序原子删除本机索引；与扫描/维护互斥，不删除原文件或服务端媒体，下一次同步可以重新入库。

清除播放记录只处理真正有播放痕迹的条目，重置位置、观看标记和播放时间，保留时长。使用既有偏好表保存来源/媒体隔离的清理代次，播放器打开时记录代次，保存时在事务中核对。已打开的旧会话不能恢复旧进度；远程进度上报停止，最终停止上报使用零进度。新打开的会话可以正常保存。不增加数据库版本或历史迁移，不清理用户数据库。

图片使用独立 Flutter ImageCache，解码像素按 LRU 受 512 MiB/1800 张限制；当前仍显示的图像由活跃控件持有。稳定键包含来源、图片身份、类型、序号、解码尺寸和版本，不依赖临时 Uint8List 对象身份；页面重建可复用已解码图像。磁盘图片校验与显示解码共享最多 3 个许可，网络仍最多 4 路。

按原比例缩小到目标框，不拉伸，也不放大小图。海报列表只预解码接下来两行，预热最多 4 个工作任务；新窗口替换后旧预热不再追加离屏请求。收到内存压力清理解码 LRU，关闭释放缓存和观察者；晚到响应不会重新填充已关闭的缓存。磁盘版本键、限流、退避和安全提交规则保持有效。

## 文件职责

| 位置（相对 apps/client/lib） | 职责 |
|---|---|
| features/sources/presentation/emby_video_context_menu.dart | 海报/单集右键菜单 |
| features/sources/presentation/emby_library_selection_bar.dart | 批量浮动栏 |
| features/sources/presentation/emby_video_library_page.dart | 选择状态、可见范围和预热窗口 |
| features/sources/data/emby_library_repository.dart | 校验、展开、想看/评级事务 |
| features/sources/data/source_repository.dart | 与扫描互斥的索引移除 |
| features/playback/data/playback_repository.dart | 清理代次和旧保存保护 |
| features/sources/data/artwork_decode_queue.dart | 公平解码许可 |
| features/sources/data/artwork_image_pipeline.dart | 稳定图片提供器、内存 LRU、预解码 |

## 验证及剩余边界

新增 28 项回归：10 项数据库/HTTP/播放器业务检查，1 项单集删除系列记录交互，9 项三桌面目标的选择/右键/确认交互，8 项图片缓存与解码检查。完整结果、原生构建和产物见 [当日测试报告](TEST_REPORT_2026-10-10.zh-CN.md)。

本批不等于所有公共右键功能完成。手动集合、公共封面管理、章节图/片头片尾分析、完整分类和搜索排序的平台等效性继续随对应公共模块迁移。菜单系统材质、字体/SF Symbols、动画及完整原版像素对照尚待 macOS 原版环境验收。三种桌面目标的组件测试不能代替 macOS/Linux 原生构建或真机验证；真实 Emby、长片/HDR和大库压力验收仍待执行。下一项按既定顺序推进首页，不把公共模块或音乐扩展为 Emby 视频接口前置条件。

后续增量：初始评级换算和 Emby 顶层显示分类已接入，见 [评级与分类](EMBY_CLASSIFICATION_RATING.zh-CN.md)。这里的剩余“完整分类”指首页/公共分类页面及原版整体对照，不再表示上述推断规则未实现。

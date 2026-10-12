# 首页编排

2026-10-12。接通 H3 的首页布局编辑；三桌面端原生和完整首页视觉验收仍单独进行。

## 原版依据

- `Sources/MediaLib/Views/HomeView.swift`：`HomeModuleKind`、`orderedHomeModules`、编辑模块包装、拖动预览、`HomeLayoutFooter`、`HomeLayoutEditorDock` 和添加面板。
- `Sources/MediaLibCore/Models/HomeModuleLayoutPolicy.swift`：顺序归一化、隐藏、恢复、移动和默认布局规则。原仓库未发现该策略的独立测试，本批根据实现建立 Dart 回归。

沿用原底部“编辑首页”入口，编辑时显示底部居中工具条；拖入另一模块即时排序，右键“移除…”隐藏，添加面板恢复模块并追加到当前末尾。恢复默认同时清除自定义顺序和隐藏设置。至少保留一个当前可用模块，空内容模块在编辑模式保留原版的布局位置，不另加占位卡片。

编辑工具条距底部 14、内边距 5、按钮高 36、间距 8；添加面板宽 280，位于添加按钮上方。拖动预览为 280×176、圆角 16，原模块透明度 .42；减少动态效果时停用缩放。进入编辑后屏蔽模块内容点击，拖到窗口上下边缘可滚动，释放后停止。

目前可编排每日推荐、媒体总览、剧集推荐、继续观看、最近播放、想看、收藏、最近添加、高分精选、运行状态。音乐推荐和继续听保留原版标识和默认顺序，随音乐模块迁移后开放；当前不显示尚未实现的添加操作。照片墙已按用户 2026-10-12 的决定移除，不再保留在首页默认布局或后续待办中。

## 存储与状态

- `features/home/domain/home_layout.dart`：纯布局规则；已知标识保留首个、忽略未知项、补齐缺失默认项。延期模块的已知标识保留，不改写为新产品结构。
- `features/home/data/home_layout_repository.dart`：复用 SQLite `player_preferences` 的 `home.moduleOrder`、`home.hiddenModules` 两个键，逗号分隔标识；两项在一个事务内提交。恢复默认只删除这两个键，不改播放器偏好、来源或媒体索引。没有数据库升级分支或自动清库。
- `features/home/application/home_layout_provider.dart`：加载完成后允许编辑；读取失败可重试，禁止默认值覆盖未读出的偏好。编辑即时更新，后台串行保存并合并连续调整；完成等待最新草稿保存成功。保存失败保留编辑状态和草稿，显示重试入口。
- 首页按模块标识保留组件身份，编排不发来源变更事件、不失效推荐或媒体查询；已有横向滚动位置保留。编辑模式及拖动预览保持同一媒体快照。

## 验证

布局规则、事务回滚、串行保存与失败重试由 `home_layout_test.dart` 覆盖；`home_ui_test.dart` 覆盖鼠标拖动、右键隐藏、添加恢复、默认布局、重新读取偏好、不重复查询、不重建条带、横向滚动保留、边缘滚动停止及搜索与编辑切换。

Windows/macOS/Linux Flutter 平台变体检查 1088×720 最小内容窗口和深浅主题。组件渲染图位于被忽略的 `apps/client/build/home-layout/editor-light.png`、`editor-dark.png`；已检查工具条和添加面板可见性。这些测试不能替代对应系统原生构建、真实鼠标体验或 SwiftUI 像素对照。

本轮完整 **541 项 Dart 测试通过**（编排新增 24 项），静态分析无问题，修改的 7 个 Dart 文件格式检查通过。正式入口 `lib/main.dart` 的 Windows Release 构建成功（35.6 秒）；2026-10-12 16:22:00（UTC+8）启动观察 5 秒，窗口消息循环响应，正常关闭，退出码 0。记录位于应用目录下被忽略的 `home-layout-full-tests.log`、`home-layout-analyze.log`、`home-layout-build.log` 和 `build/smoke/release-startup.json`。

后续已接通当前视频范围的[健康评分](HEALTH_SCORE.zh-CN.md)；首页桌面交互及真实数据验收、延期的音乐/手动集合能力保持原计划。照片模块不在当前验收范围。

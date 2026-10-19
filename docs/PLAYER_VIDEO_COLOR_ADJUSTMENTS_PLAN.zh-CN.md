# 播放器画面色彩调整计划

- 状态：本轮实现及 Windows 验证完成；后端 15 + UI 2 共 17 项通过，GPU/SW texture、ASS/RGB/YUV 样本与暂停视口往返通过，全量 783 passed / 7 skipped；Windows Release 构建 55.0 秒成功，5 秒 smoke 通过；macOS/Linux 原生、真实来源及其他边界验收待完成
- 最后更新：2026-10-18
- 适用范围：本地与 Emby 共用视频播放器；第一阶段 Windows、macOS、Linux
- 原版基线：`VideoColorAdjustments.swift`、`VideoColorAdjustmentPolicy.swift`、`PlayerView.swift` 的画面调整行

## 本轮授权范围

本轮仅迁移五项画面色彩调整：亮度、对比度、饱和度、伽马、色相。所有分量范围为 **-100…100**，默认 **0** 表示原始画面；数值取整遵循半值远离 0。每项通过 `−` / `+` 按 **5** 递减/递增，单项恢复按钮将该项单独重置为 0。数值显示沿用原版：0 显示为 `0`，非零显示正负号。

原版 `PlayerView.swift` 在“画面调整”组按亮度、对比度、饱和度、伽马、色相顺序提供控制；每行含减小、数值、恢复默认、增加操作。本轮 UI 必须按原版源码迁移并逐项对照，不以通用 Material 控件或近似截图替代。

原版模型 `VideoColorAdjustments` 将五个值作为一个可编码值对象，默认 `.neutral`，每个值限制到合法范围并取整；策略映射为 libmpv 的 `brightness`、`contrast`、`saturation`、`gamma`、`hue` 属性。本轮不是产品重新设计，不扩大为其他视频效果。

## 持久化与应用契约

- ReelNest 使用全局 JSON 偏好键 `global.videoColorAdjustments` 保存五个值的整体对象；默认五项均为 0。不新增数据库 schema、迁移或数据库列。
- 本地视频与 Emby 视频共用同一设置状态、应用链路和 UI 行为；不做逐片、逐来源或 per-server 配置。
- 连续操作进入串行队列后，必须以操作实际执行时的最新状态为基础合并分量，避免快速连点丢失其他项更新。
- 更新时应用五项原生播放器属性并保存偏好；保存/应用失败时回滚到前一状态并告警。初始化读取或应用失败为非致命，不阻断播放器启动或播放。
- 换片、重建会话和本地/Emby来源切换后仍使用当前全局偏好；未知/缺省 JSON 字段按 0 处理，非法/非有限值归一到安全范围，不允许超出 -100…100。

以上串行、回滚、告警和初始化容错是本轮移植与验收契约；实现前需对照 ReelNest 当前偏好仓库和播放会话实际接口，不能把本文当成已经实现或验证的声明。

## 明确不在本轮

- 锐化和降噪不在本轮实现/验收范围，保留原版功能迁移清单，不得删除或静默降级。
- `hqdn3d` 涉及 GPL 依赖的影响仅作为后续依赖/许可证调研事项；不是本轮实现前置条件，不在本轮新增滤镜或替换运行时依赖。
- 本轮不新增锐化/降噪滤镜、硬解选择、HDR/色调映射、服务器转码、视频均衡器预设或其他面向用户的画面效果。SW 内部 owned `lavfi/geq` 仅用于实现本轮五项色彩调整的等效处理，不构成新增可选滤镜功能。
- 不新增数据库 schema、不改变 Windows 便携存储约束，也不改变本地/Emby原有服务器连接行为。

## 当前验证与调查证据（Windows Profile texture；完整跨平台验收未完成）

- Windows Profile texture 的 RGB fixture 下 GPU 路径中，亮度/对比度有像素变化，饱和度设为 -100 未观察到像素变化。已查明固定 mpv `a2cd83c56d` 的 `video/csputils.c` 仅对 YUV 601/709/240M/2020NC 矩阵应用 hue/saturation；所以 RGB fixture 的 hue/saturation 不变化符合 mpv 行为，并与原版直接设置这五个 mpv 属性的映射一致，不为追求 RGB 像素变化而擅自改写。
- 已生成 YUV420 测试片，Windows Profile GPU texture 对五项均完成像素验证。该项是当前 GPU texture/该测试源的证据，不代表其他格式或平台均通过。
- software 路径中亮度属性读回成功但输出像素未变化；已查明 `video/out/libmpv_sw.c` 没有 equalizer 实现。用户要求本轮实现软件等效处理，不接受仅 GPU 交付；软件前置处理已接入。
- 实现细节：`native/media_kit_color.cmake` 与 Windows/Linux CMake、macOS `media_kit_viewport.rb` 在实际 GL/SW renderer 创建处分支设置 mpv user-data `reelnest/render-api`；Dart 读取实际 render API，不从 hwdec 或配置意图推断。SW 使用独立 owned filter `@reelnest-color:lavfi=[format=gbrpf32le,geq...]` 处理五项：按 mpv `csputils` 的 YUV 矩阵处理 hue/saturation，应用 contrast/brightness 与 `pow(8,-gamma/100)` gamma；前置处理位于字幕/OSD 合成前，默认全零时移除自身 filter，不覆盖或删除其他 `vf`。与锐化组合时，若 RGB 输入经自有 `unsharp` 转成 YUV 且 matrix tag 为 `auto`，SW 按 mpv 尺寸规则（宽度 ≥1280 或高度 >576 选 709，否则 601）在 float 转换前显式指定 `in_color_matrix`；切换锐化时同步重建 SW color stage。Windows Profile 两个 GPU/SW 像素用例中 RGB/unsharp 差 `<3`、关闭后 RGB hue/saturation 原语义恢复、两种调整顺序输出一致均已通过。`video_color_test.dart` GPU/SW 各一功能 case（19 秒）也通过：medium 锐化时 ASS 白字幕、移除字幕后全黑、暂停 resize、关闭锐化后 RGB 原语义恢复均在该运行中符合预期。本轮锐化专用的启用 native 全量 **803 passed / 0 skipped（39 秒）**，不替代本色彩批次的历史 `783 passed / 7 skipped` 记录。本轮未升级 DLL 或许可证依赖，也未新增硬解开关。代码接线不等于全部场景验收通过。
- 最终 Windows Profile `flutter drive integration_test/video_color_test.dart` 中 GPU 与纯 SW 两条 texture 功能用例通过（摘要含 tearDown 共 3 passed，功能用例为 2 条，耗时 19 秒）。当前 fixture 使用 YUV420 与静态平滑 RGB 梯度，避免把 GPU/SW 原有 scaler 对硬边的差异误作色彩差异：YUV420 五项各自调整均有 >2 的像素变化；同一暂停帧 reset 平均差 <2；纯 SW 与 GPU 同值 RGB 平均差 <3；RGB 源 hue/saturation 保持原版无效语义而 brightness 生效。ASS 矢量白色字幕在黑画面上的渲染符合预期，无字幕时输出保持全黑。暂停状态保持 `yes`、`time-pos` 偏差 <0.02 秒；比例/裁切/旋转/镜像组合前后其他 `vf` 与 hwdec 不变，播放中 reset 仍保持 playing。此为 Windows Profile 所列样本/场景证据，不等于其他格式或所有生命周期边界通过。
- 扩展到宽色度 YUV 样本后，GPU 与 SW 四组组合/边界像素对比均 <3：亮度 -40、饱和度 -100、色相 60 + 饱和度 100、亮度 20 + 对比度 -40 + gamma 40。此证据覆盖列明的样本组合，不替代其他格式和原生平台验收。
- 后端定向测试现为 **15 项**、UI **2 项**，合计 **17 项通过**；包含色彩偏好读取失败不阻断播放回归。静态分析 `lib`、`test`、`integration_test` 无问题；311 个 Dart 文件格式检查 0 改动，`git diff --check` 通过。当前 `flutter test` 全量 **783 passed / 7 skipped**，耗时 57 秒；7 项为需显式设置 `REELNEST_MPV_PATH` 的既有原生测试跳过。本轮全量是当前证据，不把历史单独运行的 7 项结果计入本轮。
- Linux 生成代码 test doubles 对 GL/SW 能力标记、viewport 渲染及关闭 guards 通过；这是生成代码替身检查，不是 Linux 原生构建或实机验收。macOS/Linux 原生验收仍待。
- 暂停视口往返 **400×240 → 320×180** 已通过 Windows Profile GPU/SW 集成验证：恢复后画面/色彩与白色 ASS 字幕平均像素差小于 2，暂停状态仍为 `yes`，`time-pos` 偏差小于 0.02 秒。暂停更新 `vf` 会触发 mpv 内部精确刷新 seek（原 flip 路径也有此行为）：应用没有主动发送 seek/unpause/loadfile；对非 seekable 流不能仅凭当前 fixture 保证同帧，因此非 seekable 输入不在已验范围。
- 当前 Windows Profile GPU/SW 验证包含 ASS 矢量白字幕在黑画面上的显示、无字幕时输出全黑、静态平滑 RGB 梯度下 hue/saturation 原版无效语义与 brightness 有效；此前列明的 YUV420 五项与宽色度 YUV 四组合、像素差值、暂停位置及组合保持均通过。真实 Emby、高分辨率 CPU 长时间测试、非 seekable 流、macOS Ruby/Swift 与 Linux 原生构建/实机均未验收。Linux 生成代码 test doubles 不是 Linux 原生证据。
- Windows Release 构建 **55.0 秒成功**；五秒 smoke 于 **2026-10-18 18:51:54.8987774 +08:00** 通过：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，报告为 `apps/client/build/smoke/release-startup.json`。本轮全量 **783 passed / 7 skipped** 已通过。不得把历史 768/7 或旧显示/resize 结果计入本轮色彩测试，也不得概括为 Windows、macOS、Linux 三端已验收。

## 完成与验收状态

本轮实现与限定场景验证已完成：backend/UI、Profile GPU/SW、暂停视口往返、全量测试及 Windows Release/smoke 均通过。macOS/Linux 原生、真实来源/边界场景及逐项 UI 对照仍需验收。此次未清除任何用户数据、未提交推送。不得将历史 768/7 或旧批次验收计入本轮，也不得写成三端已验收。

完成前至少需验证：

1. 五项范围、缺省值、边界、非有限值与正负半值舍入（半值远离 0）；`±5` 步进及单项重置，不影响其余四项。
2. 全局 JSON 偏好写入、读取、重启/新会话恢复、缺字段默认值；确认无 schema 变化。
3. 串行快速连续调整按实际执行时的最新状态合并；原生属性应用、持久化失败回滚与告警、初始化失败不阻断启动/播放。
4. 本地与 Emby 共用相同行为；执行适用的 Windows、macOS、Linux 构建/原生路径及 UI 对照。某个平台未实测时须明确列出，不得由另一平台结果推断。
5. 与原版 `PlayerView.swift` 控件顺序、标签、图标、尺寸、间距、数值显示、交互和状态逐项比较；锐化/降噪及 GPL 依赖研究另列后续范围。

后续继续记录真实来源、边界场景及 macOS/Linux 原生验收证据。当前状态为“本轮实现及 Windows 验证完成，跨平台和真实来源验收待完成”。

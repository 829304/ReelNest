# 播放器画面锐化与滤镜组合计划

- 状态：锐化代码/UI 已冻结；共享 owned-filter helper 已接入。锐化 Dart 定向 12 项、显式 DLL native 1 项通过；Windows Profile GPU/SW 锐化两功能用例 17 秒及 medium 锐化下色彩/ASS 组合两功能用例 19 秒通过。启用 `REELNEST_MPV_PATH` 的全量 **803 passed / 0 skipped（39 秒）**，包含全部 8 项 native。相关 headless native 用例通过 `IOOverrides` 将 Temp 命名空间隔离至自身 sandbox，隔离缘由及候选解释见下方；未修改生产 runtime。318 个 Dart 文件格式检查 0 改动、analyze clean、diff-check 无错误。Windows production Release 构建 **42.5 秒成功**；2026-10-18 20:01:52.2262702 +08:00 五秒 smoke 通过（`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`）。产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，报告为 `apps/client/build/smoke/release-startup.json`。macOS/Linux 原生证据仍待。降噪仅依赖核查和实施方案，不实现
- 最后更新：2026-10-18
- 适用范围：本地与 Emby 共用视频播放器；第一阶段 Windows、macOS、Linux
- 原版依据：`VideoSharpenMode`、`VideoFilterChainPolicy`、`MpvPlayerController.setSharpenMode`、`PlayerView.swift` 锐化设置行
- 关联批次：[画面色彩调整计划](PLAYER_VIDEO_COLOR_ADJUSTMENTS_PLAN.zh-CN.md)、[画面显示计划](PLAYER_VIDEO_DISPLAY_PLAN.zh-CN.md)

## 本轮目标与边界

迁移原版锐化模式及统一视频滤镜链行为：关闭、轻微、适中、明显四档；并确保本功能与原有质量缩放、翻转及降噪 filter chain 正确组合，不覆盖其它功能拥有的 `vf` 内容。色彩调整继续沿其独立计划实现，最终应位于 GPU VO 或 SW 等效色彩处理末端。

本轮实施锐化。降噪仅核查原版算法依赖、固定源码与运行时/发行方案，并形成单独实施方案；本轮不得实现降噪 UI、偏好、引擎行为或 `hqdn3d` filter。

不得以其他锐化/降噪算法替换原版，不升级或替换项目运行时 DLL，不改项目许可证/授权策略。固定 FFmpeg 源码锚点及当前 Windows 运行时 `hqdn3d` 不支持的初步证据已提供；可选构建/分发方案材料仍待后续提供和审阅。降噪保持未实现，不把它列为锐化交付的阻塞前置条件。

## 原版行为基线

原版 `VideoSharpenMode` 的 raw value 为 `off`、`light`、`medium`、`strong`，界面标签依次为“关闭”“轻微”“适中”“明显”，默认 `.off`。`VideoFilterChainPolicy` 对应滤镜为：

| 模式 | 原版 `vf` 片段 |
|---|---|
| 关闭 (`off`) | 无 |
| 轻微 (`light`) | `unsharp=la=0.4` |
| 适中 (`medium`) | `unsharp=la=0.8` |
| 明显 (`strong`) | `unsharp=la=1.2` |

原版 `VideoFilterChainPolicy` 统一重建单一 `vf` 字符串，顺序是：

`base quality filter → flip filter(s) → sharpen → denoise`

其中 quality filter 为空时不加入；flip 为 none/水平/垂直/双向映射为空、`hflip`、`vflip`、`hflip,vflip`。锐化关闭时不加入 `unsharp`。本轮需忠实迁移锐化部分和组合契约；降噪原有 `off/light/medium/strong` 与 `hqdn3d` 参数只用于核查/方案记录，不在本轮执行。

原版播放器设置行位于“画面”设置区域，图标为 `triangle`，标题“锐化”，选项按上述四档显示。新 UI 逐项对照原版源码，不用近似 Material 控件或截图推测替代。

源码基线只读参考：

- `E:/workspace/829304/MediaLib/Sources/MediaLibCore/Models/AppSettings.swift`
- `E:/workspace/829304/MediaLib/Sources/MediaLib/App/VideoFilterChainPolicy.swift`
- `E:/workspace/829304/MediaLib/Sources/MediaLib/App/MpvPlayerController.swift`
- `E:/workspace/829304/MediaLib/Sources/MediaLib/Views/PlayerView.swift`
- `E:/workspace/829304/MediaLib/Tests/MediaLibTests/App/VideoFilterChainPolicyTests.swift`

## ReelNest 持久化与会话契约

- 全局偏好键为 `global.videoSharpenMode`，值为 enum raw name：`off`、`light`、`medium`、`strong`；默认 `off`。不分媒体、来源或服务器，本地与 Emby 视频共享。
- 使用现有 `player_preferences` 键值表；不新增数据库表、列、schema 版本或迁移。键格式与数据边界见[数据字典](DATA_DICTIONARY.zh-CN.md#player_preferences)。
- 会话 API 为 `session.setSharpenMode(mode)`；从设置操作、会话状态、持久化到 native `vf` 更新必须沿用统一状态所有权，禁止 UI 或其它调用点直接覆盖整个 `vf`。遵循既有 `_controls` 规则：engine 未初始化或处于 loading 时控件不接受设置，不新增“engine 未就绪时先写会话偏好、稍后补应用”的行为。
- 快速连续变更应串行合并，以执行时最新状态重建完整 filter chain，避免锐化变更丢失质量、flip 或其他已有 filter。
- 保存/应用失败时恢复前一模式、重建旧链并向用户告警；启动读取偏好或应用默认值失败为非致命，不阻断初始化/播放。
- 改动只操作 ReelNest 自己拥有的锐化片段/状态；重建 filter chain 时保留仍有效的其它模块片段。应用层不得删除未知的既有 filter。

## 当前实现与初步原生证据（2026-10-18）

- Windows 固定 LGPL 运行时 DLL 的原生初步实测：`unsharp` 四档 option 设置及结构读回成功。这只证明 filter option 可设置/结构可读，不等于实际画面锐化强度、关闭还原、GPU/SW 均有效或 UI/平台验收通过。
- 同一运行时对 `hqdn3d` 的 `vf-add` 实测返回 `Option vf-add: 'hqdn3d' isn't supported`。因此当前发行包不得直接接通/调用原版降噪档位；这不推断其他 FFmpeg 构建或另行固定的运行时也不支持。
- ReelNest 已接入共享 ordered-filter helper：仅更新四个本应用拥有的 labels（当前没有 denoise label），以 mpv 字节长度规则为参数加引号，原样保留非自有 filter，并在本轮处理 `flip → sharpen → SW color`。失败恢复只回滚整个 owned snapshot，不覆盖其他 filter。代码接入已落地；Windows Profile 画面集成和完整验收仍在进行。
- 四档标签保持原版“关闭、轻微、适中、明显”，不得改成“关闭、轻、中、强”。

## 当前自动化与集成进度（2026-10-18）

- 上一次整体定向合计 **42 项通过**：`video_sharpen_test` 当时新增 11 项、`video_sharpen_native_test` 显式 DLL native 1 项，以及既有 display 13 项、color 15 项和 UI 2 项。随后新增一项矩阵单测，锐化 Dart 定向现为 12 项；新增测试后的整体定向总数待复跑，42 不是本次新锐化专测数。
- Headless native 验证了四档 `unsharp` 属性和停止状态；同一测试确认当前固定 DLL 对 `hqdn3d` 返回 unsupported，未执行任何实际降噪。
- Windows Profile GPU/SW 两个真实像素功能用例 **17 秒通过**：逐档锐化强度像素差递增、off 恢复原画面、组合操作顺序结果一致、暂停尺寸往返期间的位置/hwdec 保持，以及播放中切档/关闭与 dispose 均有覆盖。此证据限当前 Profile 样本，不等于完整验收。
- RGB 输入经 `unsharp` 自动转为 YUV、输出 matrix tag 变为 `auto` 时，GPU/SW 实际像素对比差 `<3` 已通过。SW 当前在 RGB 输入 + 自有 unsharp 情况下按 mpv 尺寸规则选择矩阵（`width >= 1280` 或 `height > 576` 用 709，否则用 601），并在 float 转换前显式设置 `in_color_matrix`；开启/关闭锐化时同步重建 SW color stage，失败恢复整个 owned snapshot。Windows Profile 最终两功能用例同时确认关闭时恢复 RGB hue/saturation 原版语义，以及先调色后锐化/先锐化后调色的结果一致。
- `video_color_test.dart` GPU/SW renderer 功能用例（19 秒）通过：medium 锐化下 ASS 字幕仍为白色、移除字幕后画面全黑、暂停尺寸往返正常，并在同一运行中关闭锐化、恢复 RGB 原语义。Windows Profile 锐化像素用例（17 秒）也覆盖 RGB hue/saturation 语义恢复及调整顺序。启用 `REELNEST_MPV_PATH` 的全量 **803 passed / 0 skipped（39 秒）**，全部 8 项 native 均实际执行并通过；锐化 Dart 12 项和显式 DLL native 1 项包含在此全量内。为保证 headless native 用例使用隔离的临时文件命名空间，测试以 `IOOverrides` 将其 Temp 路径限定在自身 sandbox。media_kit debug `NativeReferenceHolder` 源码显示其 PID 命名临时文件保存 native 指针；PID 复用是候选解释，未由崩溃栈独立确诊，生产 runtime 未改。318 个 Dart 文件格式检查 0 改动、analyze clean、diff-check 无错误。Windows production Release 构建 42.5 秒成功；2026-10-18 20:01:52.2262702 +08:00 五秒 smoke 通过（窗口响应、正常关闭、退出码 0）。产物与报告路径见本节状态行；色彩批次的 `783 passed / 7 skipped` 不属于本轮锐化全量证据。

## 与画面色彩调整的顺序

原版完整 `VideoFilterChainPolicy` 顺序是 `base quality → flip → sharpen → denoise`，其中 denoise 是未来范围；本轮已迁移/当前 helper 实际管理的链是 `base quality (保留) → flip → sharpen → SW color`。当前四个 owned labels 不包含 denoise label。

`flip → sharpen → SW color`

原版 `vf` 属性内的 chain 到锐化/降噪；本项目的色彩调整可能走 GPU VO 属性或 SW owned lavfi/geq。色彩效果应位于渲染链末端，不能因本次 `vf` 重建被覆盖或重复施加。GPU 与 SW 路径都必须实测锐化生效、关闭恢复和已有 filter 保持；若 pipeline 顺序无法在某一路径等效，记录具体证据并提出用户可评估的方案，不得悄悄降级或重排原版行为。

## 降噪依赖核查与实施方案（仅调查，不实现）

原版降噪保留 `off/light/medium/strong` 四档，非关闭档使用 `hqdn3d`：`light = hqdn3d=2:1.5:3:2.25`、`medium = hqdn3d=4:3:6:4.5`、`strong = hqdn3d=7:5:10:7.5`。不得替换算法。

固定 FFmpeg commit `5cb9fcd21167cf2f5a2852ea582997bbd0055521` 的源码证据：`configure` 将 `hqdn3d_filter_deps` 标为 `gpl`；`vf_hqdn3d.c` 文件头声明 GPL version 2 or later；`vf_unsharp.c` 文件头声明 LGPL version 2.1 or later，并标明经许可 relicensed to LGPL。上述是固定版本的源码标记，不能单独替代对最终二进制组成、分发义务或整体项目许可证影响的法律审查。现包运行时初步实测也显示 `hqdn3d` 不支持，故不得直接启用。

两条后续评估路线（仅提案，不在本轮选择或实现）：

- 评估是否可基于固定源码版本自建并纳入 `hqdn3d` 的运行时：必须连同构建配置、完整对应源码、许可证文本、copyright/NOTICE、修补集、可重现材料、产物 hash、分发告知与发行流程影响一起交付并接受许可审查。不得直接拿 GPL DLL 替换当前运行时，也不得承诺应用整体 Apache 许可不受影响。
- 或先取得适用许可/有充分依据后，再评估独立等效实现及其授权、来源和分发材料；不得以“替代算法”名义绕开原功能契约，必须另行审阅方案。

固定 FFmpeg 源码和当前运行时实测证据已提供；可选构建/分发材料仍待。审阅时需对应固定 commit、构建配置与实际 DLL，区分源码存在、构建启用、运行时可调用、媒体输出有效四级证据。当前已知源码锚点：[configure（5cb9fcd21）](https://github.com/FFmpeg/FFmpeg/blob/5cb9fcd21167cf2f5a2852ea582997bbd0055521/configure)、[vf_hqdn3d.c](https://github.com/FFmpeg/FFmpeg/blob/5cb9fcd21167cf2f5a2852ea582997bbd0055521/libavfilter/vf_hqdn3d.c)、[vf_unsharp.c](https://github.com/FFmpeg/FFmpeg/blob/5cb9fcd21167cf2f5a2852ea582997bbd0055521/libavfilter/vf_unsharp.c)。

完成以上调查后另行给出实施方案；实施仍需用户明确确认，不能把本轮的“核查授权”解释成代码实施授权。

## 验收矩阵

| 范围 | 最低证据 |
|---|---|
| 模型/偏好 | 四 enum raw value、非法/缺失值回落、`off` 默认；单键持久化、重启/新会话恢复、本地/Emby 共用、无 schema 变化 |
| 链路组合 | base quality + 各 flip + 四档 sharpen；确保 `vf` 顺序准确、关闭时无 unsharp、变更不覆盖其他拥有的 filter |
| 失败处理 | 串行快速切换、保存/应用失败回滚并告警、初始化读取/应用失败不阻断播放 |
| Windows GPU VO | Profile 锐化像素用例（17 秒）及 `video_color_test.dart` GPU case（19 秒）通过；medium sharpen 下 ASS、黑画面、暂停 resize 通过；锐化 Profile 已验证关闭恢复 RGB 语义 |
| Windows SW | Profile 锐化像素用例（17 秒）及 `video_color_test.dart` SW case（19 秒）通过；medium sharpen 下 ASS、黑画面、暂停 resize 通过；锐化 Profile 已验证关闭恢复 RGB 语义 |
| macOS/Linux | 分别记录构建和实际 GL/SW renderer 的锐化效果；不得由 Windows 证据推断 |
| UI parity | 原版设置区域、标签/顺序、图标、布局尺寸/间距、选择态及关闭/打开行为逐项核对 |
| 桌面平台 | Windows、macOS、Linux 分别记录构建、实际 renderer、Profile/实机及未完成项；一个平台通过不代表其它平台通过 |
| 降噪调查 | pinned 源码、运行时实测及可选构建/分发证据与方案完成；本轮不要求也不允许实现降噪 |

## 当前结论

本轮范围仅为锐化实施与降噪依赖调查/方案；shared owned-filter helper 已接入。锐化 Dart 定向 12 项与显式 DLL native 1 项均包含于全量 **803 passed / 0 skipped（39 秒）**，全部 8 项 native 实际执行并通过。Windows Profile GPU/SW、RGB/unsharp、两种调整顺序、medium sharpen 下 ASS/黑画面、关闭恢复 RGB 语义和暂停 resize 均有通过证据。headless native 用例的 Temp namespace 通过 `IOOverrides` 隔离至自身 sandbox；`NativeReferenceHolder` 的 PID 文件行为来自 media_kit debug 源码，但 PID 复用仅为候选解释、未由崩溃栈独立确诊，生产 runtime 未改。318 个 Dart 文件格式 0 改动、analyze clean、diff-check 无错误。Windows production Release 构建及五秒 smoke 均通过，smoke 时间、状态、产物和报告路径见状态行；真实 Emby、高分辨率 CPU 长时间运行、macOS/Linux 原生及 UI 视觉验收仍待。未清理用户数据、未替换 runtime DLL、未提交推送。不得引用色彩调整批次的 `783 passed / 7 skipped` 作为本轮锐化全量证据。

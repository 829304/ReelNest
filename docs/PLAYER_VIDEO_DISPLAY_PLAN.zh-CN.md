# 播放器画面显示调整计划

- 状态：模型/偏好/session/engine/前端已接通；Windows Profile texture 五项阶段测试及上一轮全量测试通过；macOS/Linux 暂停 resize 等效修复已实现，最新定向验证与 Windows Release/smoke 通过，但两端原生平台验收未完成；真实 Emby 及人工视觉验收未完成
- 最后更新：2026-10-17
- 适用范围：本地与 Emby 共用视频播放器；第一阶段 Windows、macOS、Linux
- 权威范围：画面显示五项的原版默认值、持久化键、mpv/filter 映射及有界验收

## 本轮范围

本轮按用户确认接入原版画面显示五项：画面比例、黑边裁切、去隔行、旋转、镜像。模型、偏好、session、engine 和前端设置页已接通；Windows Flutter texture 阶段已核验实际渲染与属性读回，并继续补齐三桌面端暂停 resize 行为。本文记录原版基线与验收边界，不把尚未实测或读回异常的能力当成已支持。

明确不在本轮范围：亮度、对比度、Gamma、锐化、降噪、硬解选择以及服务器端转码扩展。不得因本轮未实现而删除或改变原版已有行为。无数据库 schema/迁移变更；Windows 绿色便携存储约束不变。

## 前端接入边界（已完成；统一验收待完成）

- 高级设置页签顺序为“播放 / 音画同步 / 画面 / 字幕”；新增“画面”页签只含画面比例、黑边裁切、去隔行、画面旋转、镜像翻转五项。
- 播放器信息面板的“播放状态”按原版只追加非默认的画面比例、裁切、去隔行、旋转摘要；不显示镜像摘要。
- 高级设置及其嵌套二级菜单统一使用深色播放器主题。
- 前端独立测试覆盖快速连续修改、错误显示和 **680×382** 最小窗口；目前后端定向 **13 项**、UI 定向 **2 项**，共 **15 项通过**（全量 768/7 已包含后端第 13 项）。
- 初始接线批次的全量 Flutter 测试、Windows Release 已通过；最新 macOS/Linux resize 集成的最终 target 测试、analyze、Release 仍待。定向通过不证明所有参数读回、engine/session、几何、Flutter texture 或本机解码路径已完整等效。

## 当前接线与 Windows texture 阶段证据（2026-10-16）

- Domain 类型为 `video_display_settings.dart`。五个全局偏好键为 `videoAspectOverride`、`videoCropMode`、`videoDeinterlaceMode`、`videoRotationMode`、`videoFlipMode`，取值沿用原版 enum `.name`；五项在一个事务中保存，不新增数据库 schema。
- `session.displaySettings` / `updateDisplaySettings` 在串行操作实际执行时合并最新状态；应用后保存，保存失败回滚，回滚失败告警。换片/新会话读回偏好；初始化应用失败为非致命，不阻断播放。
- Engine 已接入四个原版 mpv 属性；镜像使用专属 `vf` 名称 `reelnest-hflip` / `reelnest-vflip`、通过 `MPV_FORMAT_NODE` 读取 filter chain，保留原有其他 filter，不覆盖整条过滤链。Windows 运行时以固定版本 LGPL libmpv DLL 同时供 Dart API 与 C++ texture 使用；旧 media-kit DLL 不支持 hflip/vflip，固定候选的 headless `hflip` / `vflip` / `both` 均成功，Profile texture 镜像像素检查也通过。Windows 来源、构建和发行许可证材料见 [`third_party/mpv/README.md`](../third_party/mpv/README.md)。
- Flutter texture 默认按片源尺寸创建，导致 `panscan` 不起作用。本轮将 FBO 绑定到视口物理像素，每边上限 8192 并按比例缩小；窗口 resize 合并 80 ms，参数变化后通过公开 `VideoController.setSize` 请求重设视口。发现 `media_kit_video` 的 `VideoOutput::SetSize` 只保存尺寸，暂停时可能没有后续 mpv 回调触发 `CheckAndResize` / `Render`，因此 Flutter 容器 resize 不足以证明原生尺寸更新。Windows 现由 [`media_kit_viewport.cmake`](../apps/client/windows/media_kit_viewport.cmake) 生成项目内 `video_output.cc` 补丁：复用现有 render queue，在检查 `destroyed_` 后调用 `CheckAndResize()` 与 `Render()`；不 seek、不解除暂停、不改 PubCache。mini 窗比例来自 `videoParams` 旋转后的实际 aspect。
- Windows Profile texture 阶段测试（5 秒）通过：像素确认 16:9 黑边、crop-fill 去黑边、square 比例、水平/垂直/双向镜像；组合 `aspect=4:3 + crop=balanced + deinterlace=auto + rotate=270 + flip=both` 通过，其中组合项验证属性状态，不断言 `deinterlace-active`。单独将去隔行从 `auto` 切换为 `on` 后，`deinterlace-active=yes` 读回通过。90°旋转 getter 按预期读回 `9/16`，原生属性组合已验证；未单独做旋转像素图像对比。恢复默认、暂停位置/播放状态/hwdec 配置保持通过。严格暂停 resize（原生补丁构建 11.7 秒、实测 5 秒）通过：暂停时视口设为 480×270 后 mpv `osd-dimensions` 更新到 `w=480 h=270`，还原 400×400 视口后黑边保持，暂停位置/playing/hwdec 不变。此结果验证原生 FBO/output resize，不 seek、不解除暂停。
- 镜像比较出现过的 1 px 差异来自把整视口翻转与 mpv 仅翻转视频区域作比较；使用 square fixture 隔离后通过，不记录为产品功能 bug。
- 全量 Flutter 测试 **768 passed / 7 skipped**（52 秒）；既有 `playback_stats_test` Windows Profile 真实 texture 回归通过，比较的 FPS/drop/hwdec/cache/AV-sync 报告与旧库一致。`renderPasses=false`、HTTP cache 读数可用；不切换 VO 强制提供 `vo-passes`。七项显式 native DLL 专项、严格暂停 resize 均通过，analyze 零问题，304 Dart 文件格式检查 0 改动，diff-check 通过。此前 Windows production Release 成功（44.4 秒）；CMake 下载重试逻辑更新后的增量 Release 也成功（45.1 秒），2026-10-16 23:39:17.7412689 +08:00 五秒 smoke 为 `HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。手动置入已核验归档到新缓存后，独立 CMake 检查确认 archive hash、解压、DLL hash 和保留其他 DLL 均通过；这不代表冷缓存联网下载成功。真实 Emby、macOS/Linux、可见 UI/人工视觉验收仍待完成。
- 本次 Release `data/app.so` 为 11,895,688 bytes（2026-10-16 23:28:55 +08:00）；`libmpv-2.dll` SHA-256=`22a7cb13ded0a6e80137661f5321de9a43c586780e798e46c39d3395488ece5f`、101,261,312 bytes。第三方许可证/版权文件随包位于 `data/third_party/mpv`。未改 schema、未删除用户数据、未提交/推送；正式发行前仍须把固定 archive、对应源码/build/许可证材料长期保存并完成依赖通知清点（上游仅保留近 30 日构建）。

## P2：macOS/Linux 暂停时视口 resize 不主动重绘（实现落地，平台验收待完成；2026-10-17）

- 根因与边界：当前 `media_kit_video` 上游 `setSize` 只保存尺寸；暂停时无后续 mpv callback，可能令原生 FBO/output 仍保留旧尺寸。修复不得 seek、解除暂停、修改 PubCache，也不能把 Flutter 容器尺寸变化当成原生输出已更新。
- macOS：`macos/Podfile` 采用 Flutter 3.47.6 标准 macOS 12 模板并集成 `media_kit_viewport.rb` post-install，只将 Pods 编译引用指向项目 ephemeral 目录生成的 `VideoOutput.swift`。hook 除 post-install 生成外，还为 `media_kit_video` Pods target 添加编译前脚本 phase，显式声明 helper 与原 Swift 为输入、生成 Swift 为输出并调用 `ruby --generate-source`，避免 Podfile 未变而 helper 更新时继续编译旧生成副本；Shell 参数使用 `Shellwords` 转义，重复安装不会重复添加 phase，且不改 PubCache。新增 setSize 渲染 job 捕获 `[weak self]`，执行时检查 `self` 仍存在、未 dispose、texture 存在且 id 有效，保存宽高后在原 worker 内调用 `_updateCallback`，完成 resize/render 与主线程通知；避免该新增排队 job 单独延长已关闭 `VideoOutput` 的生命周期。没有声称解决依赖其他既有任务的全部关闭竞态。Python 静态比对确认 Ruby `ORIGINAL` 片段与实际 media_kit_video 2.0.1 Swift 源码唯一匹配，但这不替代 Ruby 执行、Pods post-install 或 Swift 编译。Ruby 测试 `macos/test/media_kit_viewport_test.rb` 已覆盖 phase 输入/输出与幂等性，但本机无 Ruby，尚未执行；Mac hook/Pods 接线、Pods/Swift 编译与 macOS 实机验收仍待完成。
- Linux：新增 `linux/media_kit_viewport.cmake` 生成项目内 `video_output.cc`。软件渲染路径复用上游软件帧渲染体为 helper；GTK `set_size` 路径对 GL 标记帧供 raster 绘制，对 SW 使用新尺寸立即 render 并标记帧；不新增延迟 raw self 队列，保留 destroyed/context guards 与上游 SW 尺寸上限。Dart `viewportApplied` 改名 `Submitted`，准确表示请求提交标记，而非确认已呈现。`tool/check_linux_viewport_patch.py` 在 Windows 编译真实生成的 helper/set_size 并用 test doubles 校验 GL 通知、SW 新尺寸/clamp、关闭 guard 与上游漂移拒绝；这不是 Linux 原生实测。
- Windows Profile `integration_test/video_viewport_test.dart` 新增 GPU/SW 两种渲染配置回归，暂停时 400×400 → 480×270 → 300×450 → 400×400；mpv `osd-dimensions`、`pause`、`time-pos` 均保持预期，排队 resize 后立即 dispose 无崩溃。该测试构建 25.3 秒、测试 3 秒，共 2 场景通过。它验证 Dart 调用/跨平台接口及 Windows 原生路径，不代替 Linux 或 macOS 原生验证；`VideoControllerConfiguration` 注入仅用于 GPU/SW 回归，不是新增硬解设置。
- 最新定向回归：Dart backend 13 + UI 2 共 **15/15** 通过，analyze 0 问题，305 个 Dart 文件格式检查 0 改动，diff-check 通过；本轮未重跑全量 Flutter，**768 passed / 7 skipped** 仅为上一轮历史结果。Windows Profile viewport GPU/SW 两个真实 texture 场景通过（构建 25.3 秒、测试 3 秒）。Linux 生成补丁在两种宏配置下，将实际生成的 C++ helper/set_size 用 MSVC 编译并运行 test doubles（Release 显式启用 assert）；GL 通知、SW 新尺寸/clamp、无 context 或已销毁时不 render、保留其他编译文件及上游 callback 漂移 fail-fast 均通过，源文件未改。Windows 正式 `lib/main.dart` Release 41.0 秒成功；2026-10-17 00:17:46.2654301 +08:00 五秒 smoke 的窗口响应、正常关闭、ExitCode 0 均通过。
- `.github/workflows/build.yml` 已为 macOS/Linux 平台构建加入补丁检查，但尚未触发 CI。macOS 本机无 Ruby/Swift/CocoaPods，Ruby 用例、Pod post-install、Pods/Swift 编译未验证；Linux GTK/EGL 原生构建和真实窗口 resize 未验证。Windows Profile 与 Linux 生成补丁 test doubles 结果均不能替代 macOS/Linux 平台验收。

## Windows LGPL libmpv / FFmpeg filters 候选核验（2026-10-16）

### 当前问题与证据

- 当前正式随包的旧 libmpv 原生探测中，`hflip` / `vflip` 被报告为不可用；因此镜像不能仅凭 UI、属性设置成功或 Dart 定向测试判定可用。固定 LGPL 候选已通过隔离 headless `hflip`、`vflip`、`both` 探测，但还需要 ReelNest texture 实际画面证据。
- mpv 官方安装页说明 Windows 上 shinchiro、zhongfly 均为非官方第三方构建；mpv 第一方 CI 主要用于测试，可能缺少功能。该页面不把 shinchiro 或 zhongfly 的普通包标注为 LGPL，不能由“官方安装页列出”推导其许可证适合发行。
- Zhongfly 构建仓库 README 明确把 `mpv-dev-lgpl-xxxx.7z` 声明为 LGPL-2.1-or-later libmpv，并称静态链接 LGPLv3 FFmpeg、禁用 LGPLv2.1+ 不兼容包；维护者同时明确不能保证所有不兼容包均已禁用。该声明是候选筛选依据，不是法律意见或独立合规结论。仓库自身的 MIT LICENSE 仅说明构建仓库内容，不能替代二进制及其依赖的许可证核查。
- 本轮固定的候选为 [`mpv-dev-lgpl-x86_64-20261016-git-a2cd83c56d.7z`](https://github.com/zhongfly/mpv-winbuild/releases/download/2026-10-16-a2cd83c56d/mpv-dev-lgpl-x86_64-20261016-git-a2cd83c56d.7z)，SHA-256=`63baee08e7a242952aa9a78a6bd172aaf3a2654cdb64361687c9d139e46fefcf`。本机隔离副本 `apps/client/build/mpv-runtime-candidate/runtime.7z` 重算哈希与发布值完全一致；GitHub Actions 记录亦列出同名资产和相同 digest。Release 标记 mpv upstream commit `a2cd83c`、构建工作流仓库 revision `8a39c51`。
- 隔离归档清单只有 `libmpv-2.dll`、`libmpv.dll.a` 和四个 mpv client/render 头文件，没有许可证文本、第三方告知或源码。单独打包此 DLL 时，ReelNest 发行材料仍须另外提供适用许可证与源码/再链接说明。`configuration.json` 实读为 mpv `v0.41.0-1186-ga2cd83c56`、FFmpeg `N-127579-g5cb9fcd21`；mpv flags 含 `-Dgpl=false -Ddvdnav=disabled -Drubberband=disabled -Dlibmpv=true`，但 `ffmpeg-configuration` 字段为 `null`，不能把完整 FFmpeg configure flags 当作已证明。
- 隔离 headless 探测结果显示 hflip、vflip、both 均成功；Windows Profile texture 中比例/裁切/镜像像素比较及旋转 getter/属性组合检查通过，但未单独做旋转像素对比。Dart API 与 C++ texture 统一加载同级单一新版 DLL；曾出现的跨模块 context 崩溃来自混载候选与旧 DLL，不表示候选本身不兼容。stats texture 回归、768/7 全量、七项显式 native DLL 专项和 analyze 均已通过；Windows 原生暂停 resize 已验证。Linux 补丁已有 Windows 编译替身验证，Mac 仅完成静态匹配，Windows Dart GPU/SW 集成通过；这些结果不代表 macOS/Linux 两平台原生验收。Mac Ruby/Pods/Swift、Linux 原生构建与两平台实机验收仍未完成；Emby 实播和人工视觉验收仍待。
- 构建仓库 `compile-lgpl-libmpv.patch` 对应的可读配置改动包括：mpv Meson `-Dgpl=false -Dcplayer=false -Dlibmpv=true`；FFmpeg 移除 `--enable-gpl` 及 x264/x265/davs2、Avisynth、DVDNav/DVDRead、Rubber Band、libzvbi 等依赖/启用项；libarchive 设置 `-DENABLE_LZO=OFF`。它保留 `--enable-version3`、静态偏好和若干 LGPL/宽松许可证库。补丁没有看到 `--disable-filters`，因此与 media-kit 配方不同，理论上不会整体关闭 FFmpeg filters；但实际 configure summary/日志和运行时滤镜列表仍须对这一个产物核实。
- 值得追踪的 GPL 风险：FFmpeg 官方 LICENSE 将 x264、x265、davs2、rubberband、avisynth 列为会令 FFmpeg 转为 GPL 构建的外部库；这份 LGPL patch 移除了相应 FFmpeg 依赖/启用项。它还删去 DVDNav/Read 和 libzvbi，并关闭 LZO 支持。通用 README 仍列有 `libdvdcss`（VideoLAN 明确说明该组件使用 GPL）及若干 GPL 编码器，但这只是通用构建组件索引：候选 `mpv-dev` 归档实际未包含独立 `libdvdcss` 文件，mpv 配置又禁用 dvdnav；仍需用确切链接/构建资料确认其未静态并入 DLL。其余 GPL-only 组件也须以本次 workflow 的真实 configure/build 记录确认未启用，不能仅据补丁删除行或 `-Dgpl=false` 推定。
- 当前看见的强证据支持“候选按 LGPL 方式构建”，尚不等于法律审计完成：FFmpeg 被静态合入 libmpv（维护者 README 声明），但此候选 `configuration.json` 没有记录 FFmpeg configure 结果，归档也没有许可证/源码/NOTICE。发行前应保存实际采用的第三方许可证文本与告知、mpv/FFmpeg 对应源码和该 revision 的补丁/构建脚本，以及履行 LGPL 再链接/替换库要求所需的材料；可将其作为发行材料完整性门槛，不要求为隔离测试先完成整套发行包。ReelNest 仍按 Apache-2.0 发布，Apache LICENSE/NOTICE 与第三方 LGPL 通知分开保留；该集成判断不构成法律意见。
- media-kit 的 Windows FFmpeg 配方当前使用 `--disable-gpl`、`--disable-nonfree`、`--enable-version3`，但也先设 `--disable-filters`，随后仅启用 `overlay` 与 `equalizer`。这能解释为什么基于此配置的包可能缺少滤镜；也表明仅替换到另一版同配方 DLL 不会自动补回功能。该仓库当前配方不等同于本机随包 2023-09-24 二进制的完整可追溯构建清单。
- media-kit issue #1460 记录了其 `mpv-dev-x86_64-20230924-git-652a1dd.7z` 包的版本/哈希和构建信息，并请求对应源码或完整 build manifest；这不是对该包 GPL 或 nonfree 的指控，但提示当前公开材料不足以仅凭版本字符串完成复现与许可证审计。
- mpv 手册说明 `--deinterlace=yes/auto` 通常插入 `bwdif`，也可能由 video output 执行去隔行。因此，FFmpeg 的 bwdif 是否存在是软件滤镜路径的重要检查项，但不能据此断言所有硬件/VO 去隔行路径都只依赖 bwdif。FFmpeg 官方滤镜文档列有 `hflip`、`vflip`、`yadif`、`bwdif`。

### 候选评估与建议

| 候选 | 已见许可证/构建证据 | 结论 |
|---|---|---|
| Zhongfly 固定 `mpv-dev-lgpl` | 维护者声明 LGPL-2.1-or-later libmpv + LGPLv3 静态 FFmpeg；精确 release/workflow/hash 已锁定；隔离 headless `hflip`、`vflip`、`both` 均成功；完整 FFmpeg configuration 和附随许可材料仍缺 | 保留为当前优先候选。继续完成 bwdif、ABI、texture/播放回归及实际发行材料核验；不得据 headless 滤镜成功或包名直接等同于发行许可已完成。 |
| shinchiro 普通 Windows build | mpv 官方安装页只作为第三方构建链接列出；本轮未找到该构建系列对具体资产作 LGPL 构建声明及对应完整材料 | 不因其被官方安装页列出而采用；除非后续找到精确资产、可复现构建配置与完整许可证证据。 |
| media-kit 当前 Windows CMake 构建 | 可读到 LGPL 取向的 FFmpeg flags，但过滤器配置禁用全部 filters，只启用 overlay/equalizer；当前配方不是旧发行二进制的完整清单 | 可作为“如何显式收窄 GPL/nonfree 并选择 FFmpeg 组件”的参考，不可原样满足本项目镜像/去隔行需求。若后续重建，应只在获批构建流程中明确启用所需 filters 并审核所有依赖；本轮不改 CMake。 |

推荐顺序：使用已锁定 hash 的 Zhongfly 产物继续隔离验证：确认 `bwdif`、mpv API/ABI、texture 图像结果及 Emby/本地播放回归；同步从该次 build logs/configuration 获取 FFmpeg 实际 flags 和确切静态/动态依赖，整理实际随包组件所需许可证告知与对应源码/再链接材料。完成后再由实现流程决定是否将其作为 Windows 发布依赖，并确保 Apache-2.0 与第三方许可证材料并存。若 `bwdif` 不齐或必要的来源/许可材料拿不到，再评估可复现的自有构建方案。不能把普通 `mpv-dev` 包当作替代品，也不能把 `-Dgpl=false` 或名称中的 `lgpl` 当成充分合规证明。

### 尚未执行 / 验收门槛

- 来源/许可证核验见 [`third_party/mpv/README.md`](../third_party/mpv/README.md)。初始画面显示批次全量 Flutter 768/7、七项显式 native DLL、Windows 严格暂停 resize、analyze、下载重试逻辑修改后的增量 Release/smoke 均通过；独立验证覆盖手动预置已核验 archive 的新缓存路径，不代表冷缓存联网下载成功。2026-10-17 P2 最新定向验证、analyze、format、Windows Release/smoke 已通过；该轮没有重跑全量。Mac Ruby/Pods/Swift、Linux GTK/EGL 原生构建、两端平台实机 resize、CI、真实 Emby、其他设置组合与人工 UI/视觉对照仍待完成。
- 后续来源记录至少应固化精确资产 URL/hash、release/workflow/build-script revision、mpv/FFmpeg 版本、真实 FFmpeg configure 与链接依赖证据、实际发行的第三方许可证文本/告知、对应源码/补丁获取方式及再链接方案。对通用 manifest 中仍出现的 `libdvdcss`、x264/x265 等，要基于该产物的实际链接/归档证据判定是否适用；不能只假设 patch 已排除。
- 已完成固定候选的 headless `hflip` / `vflip` / `both` 探测，以及 Windows Profile texture 阶段画面/组合验收：`deinterlace=auto` 属性切换通过；单独切换为 `on` 后 `deinterlace-active=yes`。未验证 mpv 选择了 bwdif 软件滤镜，也未判定具体去隔行路径。全量测试 768/7、stats texture 回归、七项显式 native DLL 专项、严格暂停 resize、analyze、重试逻辑变更后的增量 Release 与 smoke 已通过；这不证明冷缓存联网下载成功。另待真实 Emby、macOS/Linux、人工视觉验收和发行前许可证依赖清点及长期材料保存。
- 2026-10-16 的 Windows 依赖来源核验不修改官方发行 DLL、CMake/打包规则或产品代码；2026-10-17 的暂停 resize P2 为另一个获授权的项目内实现批次。两者均不额外限制后续获授权工作。画面显示模块继续开发中，Windows texture 显示已完成当前阶段验收，macOS/Linux 平台验收未完成。

### 外部证据链接

- [mpv 官方 Windows 安装页](https://mpv.io/installation/)
- [Zhongfly mpv-winbuild README 与 LGPL 包声明](https://github.com/zhongfly/mpv-winbuild)
- [固定候选 release（mpv commit `a2cd83c`）](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-16-a2cd83c56d)
- [固定候选构建工作流（revision `8a39c51`，含 LGPL 资产及 SHA-256）](https://github.com/zhongfly/mpv-winbuild/actions/runs/38897527900)
- [Zhongfly LGPL build patch at workflow revision `8a39c51`](https://github.com/zhongfly/mpv-winbuild/blob/8a39c51/compile-lgpl-libmpv.patch)
- [FFmpeg license matrix / GPL external libraries](https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md)
- [VideoLAN libdvdcss license statement](https://images.videolan.org/developers/libdvdcss.html)
- [media-kit FFmpeg CMake 配置](https://github.com/media-kit/libmpv-win32-video-cmake/blob/master/packages/ffmpeg.cmake)
- [media-kit 2023-09-24 Windows libmpv build manifest issue](https://github.com/media-kit/media-kit/issues/1460)
- [mpv 官方手册](https://mpv.io/manual/stable/)
- [FFmpeg 官方 filters 文档](https://ffmpeg.org/ffmpeg-filters.html)

## 原版偏好键与默认值

以下键来自只读参考仓库 `AppSettings` 的 Codable 属性/键和默认参数。ReelNest 应通过现有设置持久化机制保存等价值，不新增数据库表或 schema 迁移。

| 设置项 | 原版设置键 | 默认值 | 选项 |
|---|---|---|---|
| 画面比例 | `videoAspectOverride` | `source` | `source`、`square`、`fourByThree`、`sixteenByNine`、`sixteenByTen`、`twentyOneByNine`、`cinemaScope` |
| 黑边裁切 | `videoCropMode` | `none` | `none`、`gentle`、`balanced`、`fill` |
| 去隔行 | `videoDeinterlaceMode` | `off` | `off`、`auto`、`on` |
| 旋转 | `videoRotationMode` | `source` | `source`、`clockwise90`、`rotate180`、`counterclockwise90` |
| 镜像 | `videoFlipMode` | `none` | `none`、`horizontal`、`vertical`、`both` |

原版 JSON 解码对这些键使用 `decodeIfPresent(... ) ?? defaults`；枚举以稳定字符串值编码。ReelNest 偏好保存需保持默认行为、已存值恢复和无效/缺失值处理的一致性。

## 原版引擎映射

核对来源：

- `E:/workspace/829304/MediaLib/Sources/MediaLib/App/VideoPlaybackPropertyPolicy.swift`
- `E:/workspace/829304/MediaLib/Sources/MediaLib/App/VideoFilterChainPolicy.swift`
- `E:/workspace/829304/MediaLib/Tests/MediaLibTests/App/VideoPlaybackPropertyPolicyTests.swift`
- `E:/workspace/829304/MediaLib/Tests/MediaLibTests/App/VideoFilterChainPolicyTests.swift`
- 设置键与默认值：只读参考仓库 `MediaLibCore/Models/AppSettings.swift`

| 设置项 | mpv/filter 映射 | 注意事项 |
|---|---|---|
| 画面比例 | `video-aspect-override`：跟随源 `no`；`1:1`、`4:3`、`16:9`、`16:10`、`21:9`、电影宽屏 `2.39:1` | 用户交互采用原版七项，包括“跟随片源”；几何适配必须按渲染后的实际方向/比例验证 |
| 黑边裁切 | `panscan`：`none=0`、`gentle=0.18`、`balanced=0.42`、`fill=1` | mpv 数值不能直接证明 Flutter texture 渲染器应用了等效裁切 |
| 去隔行 | `deinterlace`：`off=no`、`auto=auto`、`on=yes` | 验证不同视频源/解码路径的实际效果；不扩展成转码设置 |
| 旋转 | `video-rotate`：`source=0`、顺时针 90=`90`、180=`180`、逆时针 90=`270` | 原版明确 `0` 保留文件旋转元数据并不追加角度；`no` 会忽略源旋转元数据，不能互换 |
| 镜像 | `vf` 中追加：`none=[]`、水平=`hflip`、垂直=`vflip`、双向=`hflip,vflip` | 在既有 filter chain 中按原顺序组合；原版策略先保留非空 base quality filter，再加 flip，再加 sharpen/denoise。此轮只负责 mirror，不能覆盖或破坏既有 filter；不借此引入锐化/降噪 UI |

原版 `playbackProperties` 还会在同一数组包含 `hwdec`，顺序为比例、panscan、去隔行、旋转、硬解；硬解选择明确不属于本轮，不能由该组合接口的存在推导为已授权实现。

## 有界验收

1. 设置页：确认高级设置页签顺序为“播放 / 音画同步 / 画面 / 字幕”；“画面”仅有五项设置。逐项对照 `PlayerView.swift` 原版结构、顺序、选项、默认态、交互反馈及可见样式；高级设置及嵌套二级菜单维持深色播放器主题，不以通用 Material 风格或近似截图替代。
2. 播放状态摘要：仅在值非默认时显示比例、裁切、去隔行、旋转；镜像不显示摘要，保持原版行为。
3. 偏好与策略：默认值、各选项映射、保存/重启恢复及缺省值回退；旋转“跟随源”必须保留源元数据；裁切、去隔行和旋转不可互相覆盖；mirror 与既有 base `vf` 保序组合，禁用态清理自身效果但保留其他 filter。
4. Engine/session：本地与 Emby 共用设置状态；首次创建 engine 和播放期间改值都按用户选择应用，重新打开媒体后从偏好恢复；失败状态不得谎报生效或静默更改其他选项。
5. 原生画面几何：在实际 Windows、macOS、Linux Flutter texture/renderer 上逐项验证 aspect、panscan、deinterlace、rotation、mirror 的画面结果，包含源旋转元数据、非 16:9 画面、黑边、横/竖镜像及组合操作；验证布局尺寸、裁切框和控制层命中区域与视频实际几何一致。
6. 支持性声明：特别验证 Flutter texture 对 `panscan`、`video-rotate` 与 `vf` 变换的实际支持。未完成具体平台 native 证据前，不宣称三端等效；若不能等效，记录平台、渲染路径、重现条件和证据后向用户说明，不私自降级。

亮度/对比度/Gamma、锐化/降噪、硬解选择、服务器转码扩展不作为本轮验收项。无 schema 迁移；Windows 便携存储路径/凭据规则不变。

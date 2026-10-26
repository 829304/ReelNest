# 项目边界与一致性要求

首次确认：2026-10-05。最后更新：2026-10-16。来源：用户明确要求。本文件替代此前由实现者自行作出的产品范围、界面与平台排期假设。

## 项目性质

ReelNest 是 MediaLib 的 Flutter 多平台重构版本。更换实现技术，保留原项目的功能、UI 和交互，不重新设计产品，不自行添加、删除或修改功能。内部模块、状态管理、存储实现与平台桥接可以调整，但不能因此改变用户可见行为。

用户明确的品牌调整：客户端使用 **ReelNest**，原项目自有服务端能力的重构目标及对应来源入口使用 **ReelNest Server**。界面、当前规划与后续产品说明统一采用新名称；MediaLib / MediaLIB Server 仅保留在源码出处、历史记录及必要的协议兼容说明中。品牌替换是用户确认的调整，不违反功能与 UI 一致性要求。

2026-10-13，用户指定 `apps/client/assets/branding/reelnest_logo.png` 为 ReelNest 客户端 Logo。当前桌面阶段将其用于应用内品牌位以及 Windows、macOS、Linux 应用图标；仅允许为不同图标尺寸进行等比裁切和缩放，不重新绘制或改变配色。iOS/Android 图标不属于当前阶段。

## 第一阶段平台

仅 Windows、macOS、Linux 三个桌面端。iOS 和 Android 留待后续阶段，现有工程目录可保留，但移动端开发、移动布局设计和移动端发行不属于本阶段任务。Linux 的开发验证环境可使用 Ubuntu，不把发行版名称误当另一套产品。

已生成五端工程及编写五端工作流是历史事实，不代表当前阶段仍需交付五端；对应 CI 范围在配置调整时按三桌面端收敛。

## 用户确认的 Windows 便携存储约束（本轮 Windows 验证完成）

2026-10-16，用户明确要求 Windows 客户端作为绿色纯净软件运行：程序日志、用户数据、缓存和临时文件放在 exe 同级目录树中，不向用户 C 盘配置目录或注册表写应用配置。便携根目录固定由已解析的 executable 路径父目录（`resolvedExecutable.parent`）确定，不依赖当前工作目录；路径代码已接入。目标目录为 `log/`、`userdata/library/reelnest.sqlite`、`userdata/credentials/`、`cache/`、`temp/`。native `main.cpp` 只设置当前进程的 `TMP`/`TEMP` 以覆盖 media_kit 临时播放列表，不改用户/系统环境变量。启动 prepare 若发现目标不可写或路径链接逃逸，由 bootstrap 既有错误处理显示 `PortableStorageFailureApp`；数据库实际 open 阶段再次发现越界则拒绝打开数据库、不回退 AppData。

Windows 凭据不使用 Credential Manager 或 `flutter_secure_storage` 凭据库，改由 `PortableCredentialStore` 为每个逻辑 key 保存独立 DPAPI 密文 `.bin`；写入先验证临时密文，再用 `MoveFileEx` 的 `REPLACE_EXISTING | WRITE_THROUGH` 原子替换。DPAPI 绑定当前 Windows 账户，换电脑需重新登录。

Windows runtime 使用空白便携配置，不读取旧 AppData，也不提供旧配置导入；用户需重新添加 Emby，不导入旧凭据或媒体库状态。用户授权的一次性清理已删除旧数据库/日志、Local 缓存及 Release 便携副本；旧 Roaming 仍残留一个 518 字节 `flutter_secure_storage.dat`，因删除受阻需用户手动清除，新版不读取或改写。该一次性清理不授权应用普通运行时自动清库，且不包括代码、Flutter data 资源、SDK 或媒体。本轮已完成 Windows Release、不同 cwd 启动/单次关闭、空库与 ZIP 白名单验证；macOS/Linux 仍只使用各自原有存储约定，不代表便携化完成。

不保留旧配置导入、历史迁移支持或版本兼容分支；数据库只维护当前初始 schema。Windows Release 包由 `scripts/package-windows.ps1` 白名单打包 `reelnest.exe`、`*.dll`、`data/`，排除运行时数据目录与 PDB；`build.yml` Windows job 生成 ZIP 后上传。此调整仅针对 Windows；macOS/Linux 继续遵循各自原有平台约定，不据此宣称其便携化。

### P2 修正：数据库目录边界校验（Windows 验证完成）

本轮复核确认路径防逃逸存在缺口：`RuntimeStoragePaths.prepare` 原先只校验 `userdata` 顶层，而 `LibraryDatabase.open` 会直接创建 `userdata/library` 并打开 SQLite；若 `library` 子目录由 junction/symlink 指向程序根目录外，数据库及 SQLite sidecar 文件可能逃出便携根。现已在启动 prepare 与数据库实际 open 两处统一验证解析后的 library 目录、数据库文件及 sidecar 目标；逐级先校验现存父目录再创建子目录，数据库打开延迟回调再次检查并返回 canonical 路径。prepare 会执行嵌套 library 写权限 probe：启动 prepare 发现越界/不可写时由 bootstrap 既有 catch 显示 `PortableStorageFailureApp`；数据库实际 open 复检失败则拒绝打开，不回退 AppData。没有修改全局异常路由。

`portable_storage_test.dart` 包含 8 项新增路径用例：真实 Windows junction 4 项和文件/SQLite `-wal`、`-shm`、`-journal` symlink 4 项。覆盖启动 prepare 与 direct DB open 拒绝外部 library junction、prepare 后 junction 被替换仍拒绝、外部 userdata junction 下不得创建 library 子目录、数据库及 sidecar 外部链接拒绝且外部文件不被修改，以及程序根内 junction 仍可正常建库。与字幕修复相关的三个定向测试文件合计 **28 项通过**，其中新增 10 项后端/路径回归；全量 `flutter test --no-pub --reporter expanded` **753 passed / 6 skipped**（49 秒，exit 0），`flutter analyze --no-pub` 无问题，296 个 `lib`、`test`、`integration_test` 文件格式检查 0 改动，`git diff --check` 通过。production `lib/main.dart` 的 `flutter build windows --release --no-pub` **45.7 秒成功**；五秒 smoke 于 **2026-10-16 16:57:14.4629377 +08:00** 通过（窗口响应、正常关闭、退出码 0）。`data/app.so` 为 **11,846,536 bytes**，最后写入时间 **2026-10-16 16:56:42.629222 +08:00**。无 schema 变更、无用户数据删除、未提交推送。

## 功能与来源

以原版代码、页面入口、配置项及行为测试建立完整功能清单。媒体源包括本地文件夹、移动硬盘、已挂载 NAS，以及 Emby、Jellyfin、Plex。参考原项目对各类服务器的连接、认证、同步、播放和错误处理实现，迁移其行为。

MediaLib 不能被当作所有媒体来源必须经过的后台。原版若有可选的 Mlink/MediaLib Server 连接方式，或其他已有功能，应列入原版功能核对，而不是因为之前做错架构就自行永久删除。此前“只保留六类来源”“Mlink 不是必交付”等排除性假设不再作为删减依据。

这项可选来源在新项目中称为 ReelNest Server，其服务端与连接能力按原实现核对迁移。客户端直接管理本地目录并连接 Emby/Jellyfin/Plex，不强制依赖 ReelNest Server。命名确定不等于服务端已实现；已有 Mlink 协议路径、请求头和存储标识的迁移/兼容规则单独核对，不随界面文案直接替换。

分阶段开发允许功能暂未实现，但必须明确记录为迁移缺口；不能把缺口改写成最终产品限制。任何新增需求、默认规则变更、功能删减都需要用户明确决定。

## 用户确认的范围调整：暂不实现照片

2026-10-12，用户明确“照片我们暂时就不实现了，这个模块可以去掉”。当前产品入口、开发计划和验收范围移除照片/相册、照片查看器、系统照片库、照片搜索及首页照片墙，不再列为首页完成的缺口，也不自动安排到后续阶段。恢复该模块需用户重新确认；这是用户授权的例外，其余原版功能与 UI 一致性要求不变。

移除本地来源分类中的照片入口及首页照片墙标识，Emby 的照片库不出现在导航和选库入口中。不删除已有来源、索引或磁盘文件；必要的照片类型识别与影视聚合隔离保留，不添加历史数据库兼容分支。影视海报、背景图、演员头像、剧照及对应图片缓存属于视频功能，继续保留。

## 用户确认的后续新增功能

2026-10-08，用户确认将“设置云备份与恢复”纳入后续计划。这是明确授权的新增需求，不是原版已有功能；其余重构一致性约束继续适用。首版计划使用用户自己的 WebDAV 存储，不要求建立 ReelNest 统一账号系统，具体范围见 [设置云备份计划](CLOUD_SETTINGS_PLAN.zh-CN.md)。

当前只记录规划，不启动实现，不改变本地媒体闭环 → Emby 的优先顺序。自动双向同步、凭据同步和 WebDAV 媒体库直连不随此需求自动纳入实现范围。

## 用户确认的新增需求：播放器输入速率提示（2026-10-16）

用户明确授权在视频播放器右上角显示播放输入速率。提示在底部播放进度 Dock 显示期间可见，并随 Dock 的自动隐藏一起隐藏；它不是仅在缓冲或卡顿时才出现的状态提示。这是对“不自行新增功能”规则的单项明确例外，不授权其他未确认的产品增项。

计划数据源为 mpv `cache-speed`（后端接口 `VideoClock.networkBytesPerSecond`，单位 bytes/sec）。按 [mpv 官方属性说明](https://mpv.io/manual/stable/#properties)，`cache-speed` 是缓存到较低层输入源方向上的当前 I/O 读取速率，按约一秒窗口统计；底层 `raw-input-rate` 是对网络层或其他字节输入层的估算，可能不准确或不可用。因此 UI 应将它理解为播放器输入速率估计，而不是整机总网速或精确网络吞吐量。

范围边界：本地文件、已挂载目录及离线缓存的磁盘读取速率不得冒充网络速度；不得为此额外发起测速/流量探测或重下载，也不得使用媒体码率伪装输入速率。后端已实现 `cache-speed` 观察：仅 HTTP(S) 视频资源赋值，未知、本地及离线来源为空值，换资源时清空；0 是有效速率值。UI HUD 采用局部 timeline 订阅，避免播放器整页高频重建；仅已知远程资源显示，并与公共 `shouldShowPlayerControlLayer` 可见掩码同步。已知远程媒体在 loading/error 或暂无采样时以 `-- KB/s` 占位；mini/锁定状态及本地/离线来源不显示；初次尚未识别来源时无 HUD 项。速率单位以 1024 为换算基数显示 KB/s 或 MB/s，小于 1 KB/s 显示小数，0 显示 `0 KB/s`。

当前冻结代码验证：backend 54 项、UI 27 项（含 4 项速率 HUD 测试及自动隐藏/鼠标唤醒/采样不续时/loading 未知值检查）、隔离 native 2 项通过；全项目 analyze 无问题、269 个 Dart 文件格式检查 0 改动、diff whitespace 检查通过。本轮未重复上一轮 701 项全量测试，不能把该旧基线当作本轮结果。Windows 正式 `lib/main.dart` Release 构建 39.6 秒成功；AOT `apps/client/build/windows/x64/runner/Release/data/app.so` 于 2026-10-16 01:27:35 +08 生成，11,797,384 bytes。五秒 smoke 于 2026-10-16 01:28:42.7234575 +08 完成，`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`，stderr 仅正常 Impeller 提示。以上不代表真实 Emby、实体键鼠、macOS/Linux 原生或三桌面端视觉验收已完成。

## 用户确认的新增功能：播放器实时统计（实现及本轮 Windows 验证完成，2026-10-16）

用户已明确授权并完成视频输出 FPS 估算、分列 decoder/VO 丢帧、实际硬解状态、VO render pass 耗时、demuxer 前向缓存量/时长估算、实际 AV sync 偏差六项实现；本轮 Windows 全量测试、Release 与启动/关闭 smoke 验证完成。入口位于现有播放信息面板；只读当前引擎属性，面板开启时约每秒采样，关闭即停，换引擎/媒体清除旧快照。未知值显示 `--`，有效 0 保留；不得重启、seek、改变播放配置、网络探测、保存统计快照或写数据库/诊断日志。Windows Profile texture VO 实测不提供 `vo-passes`，UI 显示 `--`；其他 VO/平台须分别验证，不得由此推断全部 VO 均不支持。真实 Emby、实际硬解启用状态、转码/切画质、macOS/Linux 与 UI 视觉对照仍未验收。属性定义、局限及验收计划见[播放器实时统计规划](PLAYER_REALTIME_STATS_PLAN.zh-CN.md)。

之前的排期建议为字幕样式/音画同步后再做实时统计，但该顺序并非锁定前置；用户已授权且本轮实现完成。实际呈现 FPS、VO render pass 与缓存估算均有 mpv/平台局限；当前 Windows texture VO 的 `vo-passes` 不可用，其他平台/VO 的 Flutter texture/render API 可用性仍待验证。不得将估算或缺失属性包装成精确指标，也不得静默降级或扩大统计范围。

## UI 与交互

目标是与原版一致，尤其是 UI。逐项迁移页面结构、侧栏与来源树、布局、尺寸、间距、字体、颜色、图标、材质、动效、悬停、选中、右键、快捷键，以及加载/空态/错误态等。

实施依据顺序：原 SwiftUI View 与子组件 → 设计参数/资源 → 状态与事件处理 → Flutter 实现 → 同数据、同窗口尺寸/缩放下的截图和交互对照。截图用于验收与补充观察，不能替代阅读源码。

不把基础 Material 卡片、简化导航或另行设计的表单作为最终 UI。功能和界面的迁移可以分步完成，但每个模块只有同时完成行为与界面对照才算完成。最终阶段做统一一致性验收，而不是届时重新设计或补做全部 UI。

对于字体、系统标题栏、窗口材质、文件授权等平台差异，先用平台适配实现等效体验；无法等效的具体差异需要单列证据并由用户明确决定，不能以“跨平台”为由自行降低目标。

## 开发阶段数据库约束

项目尚未发布，没有旧版 ReelNest 数据库兼容要求。只维护当前初始表结构，不为开发中间版本保留升级分支、历史 schema 或兼容测试；验证当前数据库的新建、读写、重开及事务行为。实际发布后有需要再设计数据升级。不要自动删除或重建本机开发数据。

## 现有代码的地位与偏差

已写的 Flutter 工程、来源索引、播放器、Emby 视频链路、首页、Mlink 试验和页面仅是可复用的实现素材，不是新的产品规范。测试通过和构建成功只证明对应批次的自动化或产物结果，不证明真实服务器、三桌面端原生行为或原版 UI 已验收。

截至 2026-10-13，原版功能/UI 对照清单已经建立并持续维护；当前主要缺口包括：

- 首页 H1/H2/H3、运行状态和视频健康评分已接入，但桌面交互、真实数据、滚动性能和原版视觉对照仍需验收。
- 本地来源、扫描、NFO、海报、浏览、健康与播放闭环已具备主体实现；完整三步向导、部分元数据执行依赖、macOS 持久目录授权及移动盘/NAS 三端实测仍待完成。
- Emby 视频已覆盖登录、选库、同步、浏览、详情、播放、写回、图片/视频缓存和离线下载；真实服务器完整操作、长片/大库和三端原生验收仍是明确缺口。
- Jellyfin 基础视频来源闭环已实现；真实服务器、macOS/Linux 和人工视觉验收仍待。其余 Jellyfin 高级能力以及 Plex、ReelNest Server、公共集合、保险库和独立音乐模块仍待按原版迁移；照片模块按上文用户决定排除，不列入这些迁移缺口。
- 播放器已有本地/Emby 核心链路、字幕音轨、队列与基础设置；其余原版控制、窗口行为及三端完整视觉对照仍待补齐。视频系统外部播放器主要代码链路已接入工作树，尚未专项测试及平台验收，范围见[专项计划](PLAYER_EXTERNAL_PLAYBACK_PLAN.zh-CN.md)。
- Mlink 入口目前仅保留在历史隔离与回归路径中；ReelNest Server 是否及如何复用协议需按原连接器继续核对，不能把旧试验变成应用运行前置条件。
- 移动端工程与既有适配代码不作为第一阶段桌面 UI 的设计依据。

每项对照记录原代码路径/提交、原行为、原 UI、Flutter 对应文件、已知差异及三个桌面端验收结果。此前引用的 `64f8ee2` 继续作为历史参考，不擅自把代理后来添加的服务端扩展算作原版需求。

## 后续工作顺序

1. 按[当前阶段记录](NEXT_STAGE.zh-CN.md)优先迁移原版高级播放功能，后端提供共用接口，前端按原版接入；保留首页桌面交互与真实 Emby 验收任务。
2. 补齐本地来源和播放器的其余明确缺口，同时保持源码可追溯的功能/UI 对照。
3. 按原版依次迁移其余来源、公共能力、保险库和独立音乐模块；TMDB 与音乐不作为当前 Emby 视频交付前置条件。
4. 在 Windows、macOS、Linux 分别验收行为、界面、性能与发行；不能由一个平台或自动化结果推导另外两个平台通过。

本文件只定义产品边界和顺序，不以当前实现状态降低原版一致性要求；详细进展与证据分别以当前阶段、模块文档和平台验收矩阵为准。

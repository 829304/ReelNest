# ReelNest 开发指南

更新：2026-10-05。

范围纠正：ReelNest 是独立的 MediaLib 多平台重构，直接管理本地文件夹、移动硬盘、已挂载 NAS 和 Emby/Jellyfin/Plex。下文 Mlink 相关内容描述历史试验代码，不是新的开发主线；不再要求运行、修改或部署 MediaLib 服务端。下一步按 [实施计划](FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md) 建立多来源架构与本地库闭环。

## 当前实现

2026-10-05 代码更新：正常导航已改为媒体源，首页不再恢复 Mlink 会话。已接入目录选择、多来源、SQLite、可取消扫描、索引分页与文件信息；Mlink 路由仅供隔离回归测试使用。目录入口目前对 Windows/Linux 开放，其他平台等待文件授权适配。详情及未完成范围见 [本地媒体源与索引](LOCAL_SOURCES.zh-CN.md)。下列 Mlink 项目描述保留的历史代码，不是正常产品入口。

- 一个 `apps/client` Flutter 应用，包含 Windows、macOS、Linux、iOS、Android 平台工程。
- 启动入口、Riverpod 依赖与状态、go_router 路由、宽屏侧栏与窄屏底部导航。
- 从旧 SwiftUI 源码提取的部分设计参数和侧栏样式，详见[源码映射](design/SOURCE_MAPPING.md)。
- 本地已编写 Mlink 发现、登录、令牌刷新、会话恢复、安全存储和分类列表；已完成 Windows 构建与部分自动化冒烟，真实服务器及凭据生命周期仍待验证，详见[服务器连接实现](MLINK_CONNECTION.zh-CN.md)。
- 设置页支持跟随系统、浅色和深色；外观选择暂不持久化。
- 已静态编写媒体条目分页、排序、海报/列表视图、详情与单集上下文中的季集分页，详见[媒体浏览与详情](LIBRARY_BROWSING.zh-CN.md)。
- 已实现本地来源与文件索引数据库；播放器、下载、Emby/Jellyfin/Plex 尚未接入。历史 Mlink 试验仍是单连接模型，但正常媒体库已不依赖它。

工程版本为 `0.1.0+1`，不是已经发布的产品版本。开发用应用标识为 `io.github.user829304.reelnest`，平台启动图标暂时保留 Flutter 模板。

## 环境与命令

用户已于 2026-10-04 授权恢复编译与冒烟验证。安全存储依赖已解析，lock 和工具生成的插件注册文件已更新，`--enforce-lockfile` 检查通过。格式、分析、7 项自动化测试、Windows Release 构建及进程启动检查均通过，详见[本轮验证记录](WINDOWS_SMOKE.zh-CN.md)。不要手工编造 lock 或生成注册文件，也不要移除 CI 锁校验。

安装 FVM 后，在仓库根目录执行：

```sh
fvm install
```

FVM 读取根 `.fvmrc` 中的 Flutter **3.47.6**（Dart **3.13.5**）。首次初始化 IDE 链接时可在支持符号链接的文件系统上执行 `fvm use 3.47.6 --force --skip-pub-get`。根目录不是 Dart 包，因此这里不执行 `pub get`。

进入客户端目录后执行：

```sh
cd apps/client
fvm flutter pub get --enforce-lockfile
fvm flutter run -d windows
```

Mac 上运行使用 `-d macos`，Linux 使用 `-d linux`；手机或模拟器先通过 `fvm flutter devices` 获取设备 ID。各平台仍需安装对应原生工具链。

检查与编译命令（均在 `apps/client` 执行）：

```sh
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze --fatal-infos
fvm flutter test
fvm flutter build windows --release
```

Windows 产物是 `build/windows/x64/runner/Release/` 的整个目录，不能只复制 EXE；必须带上 DLL 和 `data/`。SDK 缓存、`.fvm/`、`.dart_tool/` 和构建目录不提交；`.fvmrc` 与 `pubspec.lock` 需要提交。

## 本机目录与历史文件系统限制

日常工程现位于 `C:\Users\hzx\workspace\829304\ReelNest`，FVM 缓存位于 `C:\Users\hzx\development\fvm`，均为 NTFS。Windows 开发者模式已开启，项目和插件的符号链接已成功创建；当前 C 盘工程已直接完成 Windows Release 构建。E 盘旧工程及缓存保留作备份，后续开发不再使用它们。

此次初始化发现 E 盘为 **exFAT**，有两个实际问题：

1. FVM 无法在工程中创建 SDK 符号链接；直接使用 `.fvmrc` 和 `fvm flutter` 可以运行当前纯 Dart/Flutter 检查，但不能视为完整 IDE/原生插件环境已就绪。
2. SDK 位于 exFAT 时，Flutter 的 `Unblock-File` 操作产生 `Zone.Identifier` 错误；在本机中文环境中又触发 Windows 构建子进程的 UTF-8 解码异常，最终报 MSB8066。

验证时使用 C 盘的临时工程和同版本 SDK 副本，Windows release 构建成功。原 E 盘工程与 SDK 没有迁移或删除，也没有修改系统语言或 Flutter SDK 源码。

日常原生开发应将**工程和 SDK 缓存都放在 NTFS**，并具备 Windows 符号链接权限。只开启开发者模式不会让 exFAT 支持符号链接。此前临时验证目录不是当前日常工程目录。

FVM 为 NTFS 工程创建链接后，编辑器可选根目录下的 `.fvm/flutter_sdk`；如果临时直接指定缓存 SDK 路径，应保存在本机设置中，不提交含个人磁盘路径的配置。

## CI 配置

- `Client checks`：PR、main/codex 分支提交或手动触发，执行依赖锁校验、格式检查、分析和组件测试。
- `Platform builds`：main 提交或手动触发 Windows/macOS/Linux 编译，使用 `.fvmrc` 的同一版本；初始化阶段不发布 Release。iOS/Android 仅保留工程模板。
- Windows 编译 release 并上传完整目录；Linux 和 macOS 将应用打成 tar.gz 保留文件权限。
- Android 使用 debug APK 进行安装测试，不使用该包作为正式发布签名包。
- iOS 执行无签名 release 编译，上传未签名 app 压缩包，不是可以直接安装的 IPA。
- 构建产物保留 7 天。正式签名、公证、商店上传和发布流程后续配置。

## 初始化阶段验证记录（不覆盖本轮新增代码）

日期：2026-10-04；仅针对初始化提交 `e091445`。

| 检查 | 结果 |
|---|---|
| 静态分析 | 通过 |
| 依赖锁与格式检查 | 通过 |
| 组件测试 | 3 项通过：导航与缩放、主题选择、窄屏大字号 |
| Windows release 构建 | C 盘临时验证副本通过；E 盘原地构建受上述环境问题影响 |
| Windows 启动检查 | 生成的完整产物复制回 E 盘后可以启动，未出现立即退出；这不等于人工视觉验收 |
| macOS / iOS / Android / Linux | 已生成平台工程和 CI 配置，尚未在相应环境执行验证 |

这些记录不等于原版界面迁移、五端播放或真实服务器流程已经验收。后续页面迁移继续以 SwiftUI 源码和状态逻辑为主要依据。

## 历史：服务器连接静态迭代

本轮仅阅读源码、修改代码及文档；没有执行 pub get、格式化工具、静态分析、组件测试、编译、应用启动、真实服务登录或 GitHub Actions。已有外壳测试只调整依赖注入，使用内存存储以免读取开发者的真实凭据，未执行。新增业务的验证场景记录在[服务器连接实现](MLINK_CONNECTION.zh-CN.md)，均为待办。

Linux 构建工作流已声明 `libsecret-1-dev`，但没有触发工作流或安装环境。Windows ATL、Apple Keychain 配置和设备权限均待后续核实。连接迭代按用户要求以 `c7300d7` 提交并推送，使用 `[skip ci]`；依赖解析与运行验证仍待后续完成。

## 历史：媒体浏览静态迭代

本轮新增分页浏览、媒体详情及鉴权图片代码，并调整会话仓库以支持并发只读请求。只读取旧工程、本地依赖源码和编辑文件；未运行格式化、静态分析、测试、编译、依赖解析或真实网络联调。没有新增依赖，上一轮安全存储依赖的 lock 待办仍然有效。本轮代码按用户要求提交，提交信息使用 `[skip ci]`；不能沿用初始化阶段的通过记录为新增功能背书。

后续补充系列入口：旧 MediaLib 在独立分支 `codex/series-summary-api` 增加系列摘要只读路由及 `series-detail` 能力声明，共修改三个服务端文件。ReelNest 在原 `codex/flutter-bootstrap` 分支实现能力协商、摘要解析、季选择和当前单集标记。两边分别提交，均未编译或测试，服务端没有部署；现有未跟踪的旧工程 docs 目录未改动、未纳入提交。协议和待验证项见[系列摘要接口](SERIES_API.zh-CN.md)。

以上两节保留当时的静态迭代记录。迁移后的客户端验证结果以 [WINDOWS_SMOKE.zh-CN.md](WINDOWS_SMOKE.zh-CN.md) 为准；MediaLib 服务端仍未编译或部署。

## 每轮可运行功能的本地产物

2026-10-08 用户明确要求功能完成后同步更新 Windows EXE。早期“只静态写代码、不编译”的限制已解除。后续默认在适当测试和静态检查通过后执行 Windows Release 构建，并报告产物位置；构建失败需说明原因，不能以旧 EXE 作为新功能产物。构建通过不等于启动冒烟、真实媒体源或三平台 UI 验收通过。

产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`；分享或移动时需携带整个 Release 目录中的 DLL 和 data 等文件。

2026-10-09 的实际启动检查发现增量 Release 曾产生旧表结构，而单元测试与新业务快照包含当前代码；本轮清理项目构建缓存后完整重建，启动器也更新。以后若运行行为与已验证源码不符，应核查实际运行路径与产物，并进行完整重建；不能只依据构建命令返回成功声明实际应用正确。

## 本地视频原生验证（2026-10-09）

播放器依赖已锁定；Linux 构建需 libmpv-dev 和 mpv（构建工作流已补齐）。Windows 独立窗口测试使用 `fvm flutter drive --driver test_driver/integration_test.dart --target integration_test/local_playback_test.dart -d windows`。不能以 `flutter test -d windows` 替代：它生成的 listener 会让子引擎等待测试调度而无法启动播放入口。普通 `fvm flutter test` 继续执行全部单元/组件回归。

样本和数据库由测试自行生成，不访问或改写用户媒体库。基础播放范围、原生测试警告和未完成事项见 [本地视频播放](LOCAL_PLAYBACK.zh-CN.md)与[当日测试记录](TEST_REPORT_2026-10-09.zh-CN.md)。

# ReelNest 开发指南

更新：2026-10-04。

## 当前实现

- 一个 `apps/client` Flutter 应用，包含 Windows、macOS、Linux、iOS、Android 平台工程。
- 启动入口、Riverpod 依赖与状态、go_router 路由、宽屏侧栏与窄屏底部导航。
- 从旧 SwiftUI 源码提取的部分设计参数和侧栏样式，详见[源码映射](design/SOURCE_MAPPING.md)。
- 首页和服务器页为空数据入口，设置页支持跟随系统、浅色和深色；外观选择暂不持久化。
- 尚未接入真实账号、Mlink API、数据库、播放器或下载。

工程版本为 `0.1.0+1`，不是已经发布的产品版本。开发用应用标识为 `io.github.user829304.reelnest`，平台启动图标暂时保留 Flutter 模板。

## 环境与命令

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

## 本机文件系统限制

此次初始化发现 E 盘为 **exFAT**，有两个实际问题：

1. FVM 无法在工程中创建 SDK 符号链接；直接使用 `.fvmrc` 和 `fvm flutter` 可以运行当前纯 Dart/Flutter 检查，但不能视为完整 IDE/原生插件环境已就绪。
2. SDK 位于 exFAT 时，Flutter 的 `Unblock-File` 操作产生 `Zone.Identifier` 错误；在本机中文环境中又触发 Windows 构建子进程的 UTF-8 解码异常，最终报 MSB8066。

验证时使用 C 盘的临时工程和同版本 SDK 副本，Windows release 构建成功。原 E 盘工程与 SDK 没有迁移或删除，也没有修改系统语言或 Flutter SDK 源码。

日常原生开发建议将**工程和 SDK 缓存都放在 NTFS**，并具备 Windows 符号链接权限。只开启开发者模式不会让 exFAT 支持符号链接。正式迁移目录由用户确定；不要将此次临时验证目录作为长期开发位置。

FVM 为 NTFS 工程创建链接后，编辑器可选根目录下的 `.fvm/flutter_sdk`；如果临时直接指定缓存 SDK 路径，应保存在本机设置中，不提交含个人磁盘路径的配置。

## CI 配置

- `Client checks`：PR、main/codex 分支提交或手动触发，执行依赖锁校验、格式检查、分析和组件测试。
- `Platform builds`：main 提交或手动触发五端编译，使用 `.fvmrc` 的同一版本；初始化阶段不发布 Release。
- Windows 编译 release 并上传完整目录；Linux 和 macOS 将应用打成 tar.gz 保留文件权限。
- Android 使用 debug APK 进行安装测试，不使用该包作为正式发布签名包。
- iOS 执行无签名 release 编译，上传未签名 app 压缩包，不是可以直接安装的 IPA。
- 构建产物保留 7 天。正式签名、公证、商店上传和发布流程后续配置。

## 本轮验证记录

日期：2026-10-04。

| 检查 | 结果 |
|---|---|
| 静态分析 | 通过 |
| 依赖锁与格式检查 | 通过 |
| 组件测试 | 3 项通过：导航与缩放、主题选择、窄屏大字号 |
| Windows release 构建 | C 盘临时验证副本通过；E 盘原地构建受上述环境问题影响 |
| Windows 启动检查 | 生成的完整产物复制回 E 盘后可以启动，未出现立即退出；这不等于人工视觉验收 |
| macOS / iOS / Android / Linux | 已生成平台工程和 CI 配置，尚未在相应环境执行验证 |

本轮不等于原版界面迁移、五端播放或真实服务器流程已经验收。后续页面迁移继续以 SwiftUI 源码和状态逻辑为主要依据。

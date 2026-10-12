# ReelNest 开发指南

更新：2026-10-12。

ReelNest 是独立的 MediaLib Flutter 重构项目。正常应用直接管理本地来源并连接 Emby 等服务器，不要求运行或修改旧 MediaLib 服务端。第一阶段只开发和验收 Windows、macOS、Linux；iOS/Android 工程暂时保留。

## 当前工程

- 客户端位于 `apps/client`，目前是仓库内唯一的 Flutter 包。
- Flutter 固定为 **3.47.6**，Dart 版本随该 SDK；应用版本为 `0.1.0+1`。
- 应用标识为 `io.github.user829304.reelnest`。
- 已接入本地视频来源与播放、Emby 视频闭环，以及首页 H1、H2 推荐与跨来源视频搜索。当前详细状态见[文档索引](README.md)。
- Mlink 相关模块是隔离保留的历史试验，不是正常导航或运行前提。
- 数据库只维护当前初始表结构；不要为开发中间版本增加升级分支，也不要自动删除本机开发数据。

代码职责和依赖方向见[项目结构](PROJECT_STRUCTURE.zh-CN.md)，产品范围以[项目边界](PROJECT_SCOPE.zh-CN.md)为准。

## 环境准备

安装 FVM 后，在仓库根目录执行：

```sh
fvm install
```

FVM 读取根目录 `.fvmrc`。根目录不是 Dart 包，不在根目录执行 `pub get`。首次建立 IDE SDK 链接时，可在支持符号链接的文件系统上执行：

```sh
fvm use 3.47.6 --force --skip-pub-get
```

进入客户端目录并解析锁定依赖：

```sh
cd apps/client
fvm flutter pub get --enforce-lockfile
```

不要手工修改 `pubspec.lock` 或 Flutter 生成的插件注册文件，也不要移除 CI 中的锁文件校验。

## 运行

在 `apps/client` 目录执行：

```sh
fvm flutter run -d windows
fvm flutter run -d macos
fvm flutter run -d linux
```

只在当前操作系统执行对应命令，并预先安装 Flutter 要求的原生工具链。第一阶段不推进手机或模拟器运行。

## 常规检查

```sh
fvm dart format --output=none --set-exit-if-changed lib test integration_test
fvm flutter analyze --fatal-infos
fvm flutter test
```

单元和组件测试使用隔离数据库、测试资源或协议替身。测试通过不等于真实服务器、原生播放、滚动性能或视觉对照已经验收。

## Release 构建

按当前平台执行：

```sh
fvm flutter build windows --release
fvm flutter build macos --release
fvm flutter build linux --release
```

Windows 产物位于 `apps/client/build/windows/x64/runner/Release/`。分发或移动时必须保留整个目录，不能只复制 `reelnest.exe`；DLL 与 `data/` 都是运行所需内容。

Windows 构建后可从仓库根目录执行启动冒烟：

```powershell
.\scripts\windows-smoke.ps1
```

该脚本只确认本次启动的 Release 窗口能够创建、保持响应并正常退出，不覆盖具体业务操作。

若运行行为与已验证源码不一致，应核对实际启动路径与 `data/app.so`，必要时完整重建。不能仅根据 EXE 文件时间或构建命令成功判断业务代码已经更新。

## 原生集成测试

Windows 本地播放器场景：

```sh
fvm flutter drive --driver test_driver/integration_test.dart --target integration_test/local_playback_test.dart -d windows
```

该场景使用测试生成的媒体和数据库，不访问用户媒体库。不要用 `flutter test -d windows` 替代；独立播放器窗口需要 `flutter drive` 的原生进程环境。

真实 Emby 只读浏览场景默认跳过，只有在正式应用已经保存可用 Emby 来源与凭据时才显式开启：

```sh
fvm flutter drive --no-pub -d windows --driver=test_driver/integration_test.dart --target=integration_test/emby_live_browse_test.dart --dart-define=REELNEST_EMBY_LIVE=true
```

该测试为来源建立隔离索引，不应创建、清除或覆盖正式登录；运行前仍应确认目标服务器和本机凭据适合测试。详细边界见[Emby 首次浏览与人物作品](EMBY_LOADING.zh-CN.md)。

macOS/Linux 的原生播放、目录授权和完整业务流程必须在对应系统单独验证，不能用 Flutter 平台变体组件测试代替。

## Windows 本机文件系统

当前工程位于 `C:\Users\hzx\workspace\829304\ReelNest`，FVM 缓存位于 NTFS。Windows 开发者模式与符号链接能力已经用于本机 Flutter 插件构建。

历史上把工程或 SDK 放在 exFAT 会造成两个问题：

1. FVM 不能建立 SDK 符号链接。
2. Flutter 的 Windows 解锁与构建步骤可能因 `Zone.Identifier` 和子进程编码失败。

Windows 原生开发应把工程和 Flutter SDK 缓存放在 NTFS，并启用所需的符号链接权限。编辑器可以指向根目录 `.fvm/flutter_sdk`；个人 SDK 绝对路径只能保存在本机设置中，不提交到仓库。

## Linux 依赖

Linux 的 Flutter 桌面工具链之外，播放器构建还需要 `libmpv-dev` 和 `mpv`。CI 当前安装：

```sh
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libsecret-1-dev libmpv-dev mpv
```

发行环境仍需单独验证运行时依赖和打包策略。

## CI

- `.github/workflows/check.yml`：在 PR、`main`、`codex/**` 提交或手动触发时执行锁文件解析、格式检查、静态分析和测试。
- `.github/workflows/build.yml`：在 `main` 提交或手动触发时构建 Windows、macOS、Linux Release。
- Windows 上传完整 Release 目录；macOS/Linux 上传 tar.gz；产物保留 7 天。
- 当前工作流不构建 iOS/Android，也不执行签名、公证、商店上传或正式发布。

CI 配置存在不代表远程任务已经成功运行；具体结果以对应工作流记录为准。

## 验证记录的写法

每轮文档至少区分以下层级：

1. 代码已接入。
2. 格式、静态分析和 Dart 测试通过。
3. Release 构建与启动冒烟通过。
4. 对应平台原生业务场景通过。
5. 真实媒体源或服务器流程通过。
6. 与原 MediaLib 的功能、交互和视觉对照通过。

低层级结果不能替代高层级验收。测试数量必须带日期或批次，不能把历史数字写成当前总状态。

初始化、早期 Mlink 和服务端扩展的历史记录分别见 [Windows 构建与冒烟](WINDOWS_SMOKE.zh-CN.md)、[Mlink 连接试验](MLINK_CONNECTION.zh-CN.md)、[媒体浏览试验](LIBRARY_BROWSING.zh-CN.md)和[系列摘要接口试验](SERIES_API.zh-CN.md)。

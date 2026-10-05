# Windows 构建与冒烟验证

日期：2026-10-04。基于 `codex/flutter-bootstrap` 的 `2c8efc2`，包含本次本地格式整理、lint 修正、依赖锁更新及新增测试；尚未提交或推送。

## 环境

- 项目：`C:\Users\hzx\workspace\829304\ReelNest`。
- FVM：4.3.1；SDK 缓存：`C:\Users\hzx\development\fvm`。
- Flutter 3.47.6、Dart 3.13.5；Windows 11 25H2；Visual Studio Community 2026 18.10.3。
- 工程和 SDK 都位于 NTFS。用户开启 Windows 开发者模式后，`fvm use` 和原生插件符号链接均成功，不再依赖手工目录联接。

## 已执行结果

| 项目 | 结果 |
|---|---|
| `flutter pub get` | 成功；更新已有安全存储依赖的 lock 与 Flutter 生成的插件注册文件 |
| `flutter pub get --enforce-lockfile` | 通过 |
| `dart format --output=none --set-exit-if-changed lib test` | 通过，41 个文件无需修改 |
| `flutter analyze --no-pub --fatal-infos` | 通过，No issues found |
| `flutter test --no-pub` | 7 项通过 |
| `flutter build windows --release --no-pub` | 成功，约 59 秒 |
| Release EXE 启动检查 | 创建隐藏窗口并持续响应 12 秒；通过正常关闭消息退出，退出码 0 |

运行日志只有 Impeller 渲染后端说明，未发现异常堆栈。首轮启动探测使用 `Process.MainWindowHandle`，无法识别隐藏窗口；后改为枚举本次子进程拥有的窗口并检查消息响应，同时通过保留的进程句柄读取退出码。这是测试脚本的修正，没有修改应用窗口实现。

本次整理了此前静态编写代码的格式，并修正分析器报告的 9 项规范问题；没有新增运行时依赖或改变 SDK 版本。

## 自动化覆盖范围

- `test/app_test.dart`：3 项，桌面/移动导航与缩放、主题切换、窄屏大字号布局。
- `test/library_smoke_test.dart`：2 项，模拟传输与内存凭据存储，使用真实页面、路由、仓库、状态管理及 JSON 解码。覆盖登录、分页失败后重试同一 offset、系列季选择、特别篇和未分季、当前单集、返回导航、详情窄屏布局、退出清除凭据；另覆盖旧服务器基本详情以及升级后刷新能力。
- `test/mlink_http_smoke_test.dart`：2 项，通过临时 IPv4 回环 HTTP 服务验证真实客户端的发现、登录、分页、系列摘要、季集及图片请求，检查 Bearer 请求头、路径特殊字符、查询参数、拒绝重定向和系列 404 映射。数据和令牌均为测试专用值。

测试没有登录真实媒体服务器、修改真实服务端数据或写入用户的实际登录凭据。Release 应用启动仍使用正式入口和系统安全存储适配器，但这不等于完成了真实凭据写入、重启恢复或删除的验证。

## 产物与复现

应用入口：`apps/client/build/windows/x64/runner/Release/reelnest.exe`。分发时需要整个 `Release` 目录，包含 DLL 与 `data`，不能只取 EXE。

仓库根目录执行：

```powershell
.\scripts\windows-smoke.ps1
```

该脚本只启动生成的应用并检查进程窗口响应，然后关闭它，不点击业务界面。结果和输出位于已忽略的 `apps/client/build/smoke/`：`release-startup.json`、`release.stdout.log`、`release.stderr.log`。

## 尚未覆盖

### 2026-10-05：本地媒体源第一轮实现

新增目录来源、SQLite 索引、可取消扫描、分页浏览与文件信息。正式首页和导航不再依赖 Mlink 会话，旧路由只在隔离回归测试中启用。详见 [本地媒体源与索引](LOCAL_SOURCES.zh-CN.md)。

- `flutter analyze --no-pub --fatal-infos`：通过。
- `flutter test --no-pub`：14 项通过，包括 6 项文件系统/SQLite 测试和 1 项新来源 UI 测试。
- `flutter build windows --release --no-pub`：通过，约 39 秒，包含目录选择插件与 SQLite 原生运行库。
- 桌面 Release 实际启动、首页“管理媒体源”导航、SQLite 初始化和空来源列表显示正常。未完成原生目录弹窗选择、真实移动盘/NAS 的整条流程；目录添加到详情由注入选择器的 UI 测试覆盖。

播放器、实际视频解码、元数据、其他平台目录权限及三个第三方服务器连接器不在本轮完成范围内。

### 2026-10-05：标题栏拖动延迟排查

用户反馈整个窗口在拖动标题栏时落后于鼠标。检查发现，ReelNest 的顶层窗口由 runner 的 `Win32Window` 创建，没有使用 Flutter 引擎的 `HostWindow`，因此没有覆盖上游已有的标题栏起步停顿处理（[Flutter PR #177597](https://github.com/flutter/flutter/pull/177597)）。

在 `apps/client/windows/runner/win32_window.cpp` 中为 `WM_NCLBUTTONDOWN` 的 `HTCAPTION` 情况补发当前鼠标位置的 `WM_MOUSEMOVE`，再继续交给默认窗口过程。坐标读取或转换失败时保持原有行为；没有改变渲染后端、线程策略、SDK 或系统设置。

Windows Release 重新构建成功（约 31 秒），并通过桌面自动化检查启动、标题栏拖动和双击最大化。自动化的前后截图无法测量连续拖动时的鼠标与窗口位置差，因此本补丁只处理已知的拖动起步等待，尚不能认定用户报告的持续滞后已经消除。需要在此 Release 上人工确认快速来回拖动、按住后再拖动，以及最大化还原后的拖动体验；若持续滞后仍在，再对消息循环和渲染耗时进行测量。

本轮仅修改原生窗口代码，未重跑 Dart 测试；上文的 7 项测试结果属于 2026-10-04 的验证。

### 其他验证边界

没有进行原版视觉对照、真实 Mlink/MediaLib 联调、MediaLib 服务端编译、原生安全存储完整生命周期或播放器验证；并发令牌刷新、取消竞态、图片解码与内存边界等仍需专项测试。macOS、iOS、Android 和 Ubuntu 没有在对应环境构建。Android SDK 当前未配置；`flutter doctor` 的 Google 存储网络检查出现握手失败，但本次依赖解析与 Windows 构建均成功。没有触发 GitHub Actions。

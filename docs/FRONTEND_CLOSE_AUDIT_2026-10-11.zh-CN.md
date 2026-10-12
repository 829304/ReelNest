# Windows 播放器关闭后主界面失去响应检查

用户反馈：关闭播放窗口后，主窗口所有标签均无法操作。本轮围绕该故障检查原生消息分发、播放器控件和关窗后的实际导航；不代表整个前端、所有平台已完成验收。

## 已确认的消息分发缺陷

锁定依赖 `media_kit_video 2.0.1` 的 Windows 插件为每个顶层窗口安装 `WindowProcDelegate`，但使用进程级 `MediaKitVideoPlugin::instance_` 保存最后注册的插件实例。播放器注册时覆盖主窗口实例；播放器销毁时清空指针，主窗口仍保留插件安装的窗口过程，之后只能进入 `DefWindowProc`，无法继续转发到原来的 Flutter 窗口处理器。播放器存在期间，主窗口消息也会使用播放器的原窗口过程。

这能解释为何 Windows 仍判定窗口“响应”，但 Flutter 界面不随原生窗口消息正常更新。上游同类多引擎问题见 [media-kit #1383](https://github.com/media-kit/media-kit/issues/1383)。本轮结论同时依据本机锁定源码和修复前后对照测试，不仅依赖该 issue。

`windows/media_kit_window_dispatch.cmake` 将回调改为按 HWND 查找所属插件，各窗口保存和恢复各自的原窗口过程。只修改项目生成目录中的编译输入，不修改共享 Pub 缓存。依赖源码变化导致补丁锚点不匹配时构建失败，要求重新核对，避免静默失效。

## 控件无障碍节点

额外检查到 Flutter 3.47 的 Material Slider 在路由、弹窗中可能输出游离的无障碍节点。上游记录见 [Flutter #190357](https://github.com/flutter/flutter/issues/190357)。新增 `SliderOverlayScope`，用局部 Overlay 和明确的语义容器承载原滑块，应用于进度、音量、启动音量与倍速滑块；保留原尺寸、样式、值、回调和键盘操作，不关闭无障碍支持。

录制真实 `SemanticsUpdateBuilder` 输出的测试覆盖初始加载后的播放器控件、逐个悬停工具提示、路由和弹窗，验证节点可从根抵达、引用子节点存在、拖动与方向键有效。对照实验撤掉滑块包装时，路由及弹窗两项测试均失败；恢复后通过。播放器 Tooltip 在悬停时另产生 8 个游离节点，添加独立 Semantics 容器后通过，不改变工具提示的布局和定位。全量测试还发现并校正了局部 Overlay 与弹出面板的语义边界问题。

## 原生回归的补强

原测试通过 `tester.tap` 直接注入 Flutter 事件，无法证明原生窗口消息仍正常；使用前台 HWND 定位播放器也会受 Windows 焦点限制或用户切换窗口干扰。

现在按窗口类和当前测试进程定位播放器，以 `WM_CLOSE` 走标题栏关闭路径。主窗口检查真实尺寸变化、向 Flutter 子窗口发送 Windows 鼠标按下/抬起消息、依次点击设置／媒体源／仪表盘／首页并验证真实路由。覆盖播放、切换单集、关闭保存、连续三次重开关窗及最后一次导航。

修复前，同一原生尺寸回归失败：窗口尺寸请求已发出，Flutter 仍停留在原来的 1280×720；修复后该检查通过。可选大库负载只读取本机 92,130 条现有索引，播放器使用临时数据库与生成样本，不修改用户观看记录，也不连接真实 Emby。

## 验证边界

2026-10-11 最终代码验证：

- `flutter test`：415 项通过（`player-close-audit-all-tests-final.log`）。
- `flutter analyze`：无问题（`player-close-audit-analyze-final.log`）。
- Windows Profile 原生播放集成：4 项业务场景及清理全部通过，运行 57 秒（`player-close-audit-native-profile-final.log`）；包含 Emby 测试服务连接、轨道/字幕、EOF/队列、连续关窗后的原生输入与尺寸回归。
- 另一次关闭专项负载回归已通过：读取本机 92,130 条索引，10 次索引刷新期间重复播放与关闭（`player-close-audit-stress-verified.log`）。该负载验证发生于最后的 Tooltip 语义边界修正之前。
- 正式 `lib/main.dart` Windows Release 构建成功；2026-10-11 12:06（UTC+8）启动烟测的窗口响应与退出检查通过，观察 5 秒窗口消息有响应，正常关闭、退出码 0。但退出日志存在 Drift `This database has already been closed` 异常，堆栈位于事务回滚/远端执行器清理，不能据退出码将其视为无异常。该关闭时序问题仍待单独定位。产物为 `apps/client/build/windows/x64/runner/Release/reelnest.exe`，分发时需要保留整个 Release 目录。记录为 `apps/client/build/smoke/release-startup.json` 和 `release.stderr.log`。

Windows 原生日志仍可能包含 Flutter AXTree 诊断。上述滑块回归通过不代表 Flutter 引擎全部无障碍缺陷均已解决，也不能将此前所有崩溃归结为同一个原因。macOS/Linux 原生、真实 Emby 播放和完整原版视觉对照未在本轮验收。原 Swift `PlayerView.swift` 的关闭、清除活动选择与播放行为作为基线，只读检查，不修改原仓库。

本轮未删除或迁移用户数据库，未提交或推送代码。检查开始前已有较多未提交改动，本报告仅归属本轮窗口分发、滑块及工具提示语义边界和对应回归，不将其他改动计为本轮完成。

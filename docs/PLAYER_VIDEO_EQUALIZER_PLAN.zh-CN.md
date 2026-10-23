# 视频播放器音频均衡器计划

- 状态：已实现，Windows 自动化验证通过；跨平台与真实设备验收待。
- 范围：仅视频播放器音频均衡器；本地与 Emby 共用同一播放会话。不扩展音乐模块，不实现降噪或在线字幕。
- 原版依据：只读参考 `MediaLib/Sources/MediaLib/App/VideoAudioFilterPolicy.swift`、`MediaLib/Sources/MediaLibCore/Models/AppSettings.swift`（`MusicEqualizerPreset`）、`MediaLib/Sources/MediaLib/Views/PlayerView.swift`（约 4686 行）及 `MediaLib/Tests/MediaLibTests/App/VideoAudioFilterPolicyTests.swift`。

## 用户可见选项与原版数据

五段中心频率固定为 **60 / 230 / 910 / 3600 / 14000 Hz**，增益数组顺序与频率顺序一致，单位 dB；预设名、显示名和原版值如下：

| raw name | 原版显示名 | 60 / 230 / 910 / 3600 / 14000 Hz (dB) |
|---|---|---|
| `flat` | 纯平 | `0, 0, 0, 0, 0` |
| `pop` | 流行 | `-1, 2, 4, 2, -1` |
| `rock` | 摇滚 | `4, 2, -1, 2, 4` |
| `jazz` | 爵士 | `3, 1, 1, 2, 3` |
| `classical` | 古典 | `4, 2, -1, 2, 3` |
| `bassBoost` | 低音增强 | `6, 4, 1, 0, 0` |
| `vocal` | 人声 | `-2, 0, 4, 3, 0` |
| `trebleBoost` | 高音增强 | `0, 0, 1, 4, 6` |

默认 `enabled=false`、`preset=flat`。关闭均衡器必须保留所选预设；关闭状态与 `flat` 预设均不安装本功能拥有的音频滤镜。

## 状态、持久化与引擎边界

- 领域类型：`VideoEqualizerSettings(enabled, preset)`，共用原版 `MusicEqualizerPreset` 的语义/预设集合，不把均衡器功能扩展到音乐播放器。
- 单一全局偏好：`global.videoEqualizerSettings`，JSON 存于既有 `player_preferences`；默认 `{"enabled":false,"preset":"flat"}`。不增加表、列或 schema；播放器偏好批量 key 数从当前 26 增至 27。历史文档中的 26/25 保持各自历史截面，不回改。
- 会话：本地与 Emby 使用同一会话能力。偏好连续变化按串行“最新值合并”应用与保存；应用/保存失败回滚设置并提示。初始化应用失败为非致命错误，并向用户提示，不阻断播放。
- 引擎抽象为可选 `VideoEqualizerEngine`；mpv 侧由 `MpvEqualizerCommands` 只管理本功能拥有的 `@reelnest-equalizer` lavfi 标记。保持现有 `af`、`vf` 与其他滤镜，不清除/覆盖非本功能 owned filter。
- 采用原版 `lavfi=[firequalizer=gain_entry='entry(frequency,gain);...']` 算法，不能用 biquad 均衡器或其他近似算法替代。验证 pinned DLL 时不得更换运行时。
- 必须保护变调链，并保留音量/增强、音轨、输出设备及音画同步行为。不得为了应用设置主动 seek、unpause 或重新打开媒体。

## 实现与自动化证据

原版 `VideoAudioFilterPolicyTests` 覆盖 disabled 输出空滤镜、enabled+flat 输出空滤镜、rock 五段滤镜字符串及 `af` 属性映射、disabled 属性为空，以及其余非 flat 预设均输出五个有限数值频点。Flutter 侧已建立后端与 UI 回归；下列证据仍不代替实际设备听感、真实 Emby 或原生多平台验收。

- 后端 `video_equalizer_test.dart` 13 项与 `playback_read_performance_test.dart` 4 项，共 **17 项通过**；完整偏好读取 27 次 getter 查询已收敛为 1 次快照。
- UI `player_basic_settings_test.dart` 与 `player_marker_skip_ui_test.dart` 共 **14 项通过**。初始夹具未包含实际设置页滚动容器，新增设置行后产生 18 px 溢出；前端工程师按实际页面 `Scrollbar` + `SingleChildScrollView` 修正测试夹具并保留原断言。产品设置页已有滚动父容器，无产品布局降级。
- 全量 `flutter test --no-pub --reporter expanded` 显式启用 `REELNEST_MPV_PATH`：**873 passed / 1 skipped**（45 秒），唯一跳过项为可选排序性能基准；其中包含下述 native PCM 用例。
- `dart analyze lib test integration_test` clean；353 个 Dart 文件 format 0 changed；`git diff --check` clean。
- 当前 pinned Windows DLL 的 `test/video_equalizer_native_test.dart` 显式启用 native 后 **1 项通过**：使用 `ao=pcm` 生成 48 kHz / 16-bit / mono 五频 WAV，比较 flat 基准与七个非 flat 预设；实际五频输出增益相对原版值误差均在 **0.8 dB** 容差内。该证据验证真实 PCM 样本滤波而非属性读回，不更换运行时。
- Windows Profile `integration_test/video_equalizer_test.dart`：GPU/SW 各 **1 项实际功能用例通过**（runner 汇总 3 项含 tearDown；测试 4 秒，Profile 构建 24.2 秒）。两种 renderer 都覆盖本地与 loopback Range HTTP 视频、8 预设轮换、暂停时 `time-pos` ±0.02 秒、保留 `aid`/`sid`/secondary/subvisibility、speed、pitch correction、volume/boost、audio delay/device、hwdec、vf 和 foreign af；播放时改均衡器/倍速/变调后无 error 且仍播放；已完整缓存的 HTTP 片段上切换设置不会增加请求。
- Profile harness 首次因在 mount 前设置 `ao` 等 controller 初始化属性而挂起；将测试设置移至 mount 后后续通过。这是测试 harness 初始化顺序调整，不是生产故障修复。

## Windows Release 与剩余验收

Windows Release 构建 **41.2 秒成功**。`scripts/windows-smoke.ps1 -ObservationSeconds 5` 于 **2026-10-22 14:57:45.2163649 +08:00** 通过，`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`；EXE：`apps/client/build/windows/x64/runner/Release/reelnest.exe`。

阶段状态为“已实现，Windows 自动化验证通过；跨平台/真实设备验收待”。真实设备听感、真实用户 Emby、macOS/Linux 原生与原版 UI 视觉逐项验收仍待；Windows 自动化、native PCM 与 Release/smoke 证据不等同于这些验收。

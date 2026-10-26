# 在线字幕搜索与下载计划（2026-10-23）

状态：**实现已冻结；自动化回归及 Windows Release/smoke 通过。** 设置页、在线搜索/下载、凭据存储、payload 校验/解压、本地/Emby 会话资源管理与播放器弹层已接线。最终行为包括：编辑后保存；在设置页导航离开时尝试保存当前草稿；处理已保存值与进行中写入交错，避免值恢复成旧值后漏存；设置初次读取失败时不在 dispose 阶段把空默认值写回覆盖既有值。若离页后的 dispose 保存失败，页面已销毁，不能承诺在当前页 toast 或阻止导航；下次进入显示实际成功持久化的值。

最终全量 `flutter test --no-pub --concurrency=4 --reporter expanded --dart-define=REELNEST_MPV_PATH=...` **924 passed / 1 optional benchmark skipped**（58 秒），包含在线字幕 39 项（data 26、session 7、UI 6）；日志 `apps/client/build/online-subtitle-full-tests-final.log`。定向 UI + marker native **7 passed**；全项目 `dart analyze` 无问题，367 个 Dart 文件 format 0 changed，diff-check 无空白错误（仅既有 CRLF 警告）。Windows Profile GPU/SW 两例真实 mpv fixture 集成通过。最终 Windows Release 构建 38.5 秒、exit 0，日志 `apps/client/build/online-subtitle-release.log`；产物 `data/app.so` 时间为 2026-10-23 17:33:55 +08:00。最终五秒 `windows-smoke` 于 `2026-10-23T17:34:27.4953710+08:00` 通过，`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`，记录 `apps/client/build/smoke/release-startup.json`。该 smoke 只验证启动/响应/正常关闭，不是可见 UI 验收。macOS/Linux 实机、公开字幕服务 live、真实 Emby 在线/离线字幕及可见 UI/原版视觉仍未验收。

## 实现摘要

- SettingsPage 新增“字幕下载”设置区：首选语言和 API Key；失焦/完成编辑时保存，保存安全失败需明确处理。OpenSubtitles 匿名调用只要求 API Key，不要求账户登录；当前没有测试 API Key，尚未做 live 请求。
- 播放器字幕 popover 在双字幕区域后接入在线字幕区，维持宽 360 px、最大高 540 px；首次打开自动搜索一次，支持手动刷新。
- 按已配置来源显示 Podnapisi 及（存在 API Key 时）OpenSubtitles；支持搜索中、无结果、错误、部分来源警告状态，最多展示前 20 条；下载中/已下载状态及再次点击重新加载。
- 同一 playback session 切片时重新搜索并清除旧媒体结果；关闭弹层、切离面板或切换 session 会取消搜索任务，避免迟到结果污染当前 UI。
- 离页时尝试保存草稿；saved/saving 竞态不会漏存；初次读取失败时不把空默认值写回覆盖已有设置。dispose 保存若失败，页面已销毁，不能承诺当前页 toast 或阻止导航；下次进入显示实际成功持久化值。

## 目标与范围

将原版视频播放器的在线字幕搜索/下载迁移到 ReelNest 桌面端，优先级先于自定义快捷键、鼠标与触控板设置。来源为 Podnapisi，以及用户配置可选 API Key 后的 OpenSubtitles。只实现在线字幕闭环，不借此扩展播放器偏好、公共元数据或其他在线服务功能。

原版核对依据（MediaLib 只读参考）：

- `Sources/MediaLib/App/SubtitleSearchService.swift`
- `Sources/MediaLib/Views/PlayerView.swift`，字幕弹层和搜索实现约 6619–6790 行，重点 `searchOnlineSubtitles`、`downloadOnlineSubtitle`、`onlineSubtitleRow`
- `Sources/MediaLib/Views/SettingsView.swift`，`subtitleSettings` 约 852 行起
- `Tests/MediaLibTests/App/SubtitleSearchServiceTests.swift`

原版行为基线包括：弹层首次打开自动搜索一次；用户可手动刷新；结果去重后最多显示前 20 条；Podnapisi 在前，配置了密钥时再合并 OpenSubtitles；设置首选字幕语言，默认 `zh-CN`；本地视频下载同名字幕到影片目录并立即加载。原版测试覆盖同名输出扩展名、缺省 SRT、结果去重和原子写入入口等。源码中 `.zip` 被当成不支持扩展名回退为 `.srt` 的行为是缺陷，本迁移不得复制：压缩包必须先安全解包、识别并验证有界字幕文本后才能保存/加载。

原版远程资源弹层有搜索入口，但下载分支只接受 `item.filePath`；该 guard 对 Emby 等远程项不成立时不会给出可用结果。本次已向用户说明并获准修正：远程/Emby（包括离线副本）要有可用的下载即加载流程，不保留无响应行为，也不得把字幕写入或上传到 Emby 服务器。

## 用户可见行为与持久化

- 设置首选字幕语言，默认 `zh-CN`；复用既有全局偏好键 `global.subtitleLanguage`，不新增数据库 schema/历史迁移。空白值按 `zh-CN` 处理。
- OpenSubtitles API Key 是可选设置；空值时仍搜索 Podnapisi。凭据通过现有 `SecureCredentialStore` 保存，不以明文写入数据库；Windows 遵守当前账户 DPAPI 便携凭据约束。
- 播放器字幕面板打开时自动搜索一次，提供明确的手动刷新入口；展示去重后的前 20 项及来源/语言等必要信息。结果按 Podnapisi 后 OpenSubtitles 顺序合并；一方失败不能清掉另一方成功结果。必须区分“无结果”与单源/网络错误，Podnapisi DNS/服务不可达时不得伪造为空结果。
- 搜索只发送完成检索所需的影片标题、年份、IMDb 等必要识别信息及目标语言。不得把 Emby URL、服务器地址、用户名、token、凭据、播放 URL 或本地完整路径发送给字幕服务。
- 对结果执行下载后校验媒体种类与大小边界。普通字幕文本可支持明确允许的格式。ZIP/gzip 在内存中有界解压，不将成员路径写到磁盘：最多 64 个条目，压缩体上限 8 MiB，单份解压字幕文本上限 4 MiB，归档声明总量上限 16 MiB；按中央目录顺序选择第一份受支持字幕。拒绝重复成员名、越界内容、加密条目、CRC 错误和路径穿越条目；多条目归档不一概拒绝。校验字幕文本/扩展名后才原子保存或交给播放器。
- 本地文件：以原影片文件名 stem 生成同目录字幕名（如 `videoStem.srt` 或经白名单校验的真实字幕扩展名），原子替换/写入并立即加载；文件权限或只读目录失败时明确报错，不回退到 AppData、缓存目录或其他不透明位置。
- Emby 在线条目及其离线副本：不能修改媒体源目录或上传服务器。下载到属于当前 playback session 的隔离临时目录，校验后立即加载；切换媒体或关闭播放 session 时清理该 session 的在线字幕临时文件。临时资源生命周期与普通离线媒体缓存分开。

## 网络、安全与并发要求

- 所有请求有明确超时、取消能力、响应体上限、重定向策略以及下载/解压后大小上限；服务端错误、日志、toast 和诊断信息不泄露 API Key、token、签名下载 URL、用户路径或 Emby 地址。
- 带凭据的 OpenSubtitles 请求如发生重定向，不允许把凭据转发到非预期 origin；下载短链按不可信输入处理。不得依赖任意 redirect 默认行为。
- 请求响应需与触发它的 playback session、媒体身份及查询代次绑定。快速连续切片/关闭/刷新时取消旧任务或丢弃过期响应，不把上一个媒体的结果显示在当前影片上。
- Podnapisi 与 OpenSubtitles 独立失败隔离；密钥未配置、错误密钥、HTTP 错误、限流、取消、超时、下载失败、归档校验失败、文件不可写均产生可理解且不泄密的反馈。
- OpenSubtitles 官方帮助说明 API Key 与下载端点行为，可能受服务端限额约束；限额会变，不在 UI/文档中固化未经当前官方资料确认的免费配额或“每日 5 条”等承诺：[OpenSubtitles Getting Started](https://opensubtitles.tawk.help/article/getting-started)。

## 当前外部服务验证限制

- 官方 OpenSubtitles 文档已查阅；匿名 API 调用需要 API Key，但不要求账户登录。当前没有可用测试 API Key，尚未执行 live 请求；`ignored build/opensubtitles-openapi.json` 已在本机保存作开发参考（ignored，不作为项目文档或提交内容）。任何 live 验证都须使用安全凭据并遵循 API 服务条款与动态限额。
- 本机查询 `www.podnapisi.net` DNS 失败，当前不能做 Podnapisi live 搜索/下载证明。不得据此删除 Podnapisi 来源，也不得把网络不可达伪装为“搜索成功但无字幕”。开发阶段以可复现 service fixture 验证解析、排序、合并、下载和错误路径；具备网络条件时另行记录 live 验收结果。

## 最终完成定义

### 自动化与安全测试

- 服务层 fixture：Podnapisi XML 和 OpenSubtitles JSON 成功/坏响应/空结果/单源失败、合并顺序、规范化去重、前 20、可选密钥及错误处理。
- 本地保存：basename/stem、扩展名白名单、原子写入、既有文件替换策略、不可写失败且不回退。
- 文件验证：plain text 和支持格式；ZIP/gzip 有效字幕及多成员按中央目录顺序选择、损坏归档、重复成员名、路径穿越、伪造扩展名、二进制内容、加密/CRC 错误、超限压缩体/条目数/单文件解压体/声明总量。解压应在有界内存中完成，不写出成员路径。
- 安全边界：检索请求字段只含允许元数据；凭据不进入 URL/日志/错误文本；重定向不泄露凭据；取消/超时/体积限制生效。
- 生命周期：媒体切换、关闭、快速刷新时旧结果不污染新会话；远程/离线副本临时文件隔离、可加载并在 session 结束后清除。
- 一方服务失败时另一方结果仍能展示；文件权限、服务器错误、限流和无结果有不同可理解状态。

### 平台及人工验收

Windows、macOS、Linux 分别验收设置存取和实际文件语义；Windows 另外确认 API Key 通过 DPAPI 凭据路径保存，数据库无明文。人工确认弹层自动搜索/刷新/前 20/去重/下载中状态、错误、样式及原版布局/间距/交互对照。至少验收真实本地可写/不可写影片目录、真实 Emby 在线播放和 Emby 离线副本；确认远程字幕不写回服务器、媒体切换/退出清理正确。记录 OpenSubtitles live 结果（若未做应明确写未做）；Podnapisi 在 DNS/服务不可用期间明确记为未 live 验证，而非通过或空结果。

## 最终验收记录（冻结代码）

| 项目 | 结果 | 证据/限制 |
|---|---|---|
| 实现与代码冻结版本 | 已冻结 | 冻结代码的版本/提交标识待记录；本文件日期不代表提交日期 |
| 服务/解析/失败隔离测试 | 通过 | 在线字幕 data 26 + session 7 + UI 6，共 39 项；包含于最终全量 |
| ZIP/gzip 与安全边界测试 | 通过（自动化） | 有界内存解压；64 条目、8 MiB 压缩体、4 MiB 单字幕、16 MiB 声明总量；不将归档成员路径写入磁盘 |
| Windows Profile 本机集成 | 通过（两例） | `integration_test/online_subtitle_test.dart` GPU=true/false，实际 mpv 验证 HTTP fixture 下载→原子写入→`sub-add`→同路径覆盖后 `sub-reload`；字幕文本变化，path/time-pos/pause/speed 不变。非 live 公共源 |
| 全量测试、静态分析 | 通过 | `flutter test --no-pub --concurrency=4 --reporter expanded --dart-define=REELNEST_MPV_PATH=...`：924 passed / 1 optional benchmark skipped（58 秒），日志 `apps/client/build/online-subtitle-full-tests-final.log`；`dart analyze` 无 issues；367 个 Dart 文件 format 0 changed；diff-check 无空白错误（仅既有 CRLF 警告） |
| 定向 UI + marker native | 通过 | 7 passed |
| Windows Release 与 smoke | 通过 | Release 38.5 秒、exit 0；最终五秒 smoke 正常响应/关闭、exit 0；证据见上方。Smoke 不是可见 UI 验收 |
| Windows 可见 UI 与 DPAPI | 待补 | 人工界面和原版视觉未验收；DPAPI 验收另列凭据/平台证据 |
| macOS 原生/人工验收 | 未验收 | 原生运行和人工验收未做 |
| Linux 原生/人工验收 | 未验收 | 原生运行和人工验收未做 |
| 真实本地/Emby 在线及离线场景 | 未验收 | 已通过的 Profile 用本机 HTTP fixture；不替代真实本地目录权限、真实 Emby 在线/离线副本和无服务器写回验收 |
| OpenSubtitles / Podnapisi live | 未验证 | OpenSubtitles 无测试 API Key；Podnapisi DNS 不通，应明确未验证，不能记作空结果 |
| 原版 UI 对照 | 未验收 | 三桌面端可见布局/交互对照未做 |

## 当前阶段顺序调整

本项已作为优先功能批次实现并冻结；后续自定义快捷键排在本项之后获批，鼠标/触控板继续拆为后续批次。在线字幕在 macOS/Linux、真实来源和 UI 的独立验收边界仍见上表；平台基础工作（macOS 目录持久授权与稳定卷身份、macOS/Linux 原生构建及基础运行验收）并行推进。

### 原版链接

- [SubtitleSearchService.swift](https://github.com/829304/MediaLib/blob/64f8ee258d87389414d5e06740a89f59cd857612/Sources/MediaLib/App/SubtitleSearchService.swift)
- [PlayerView.swift](https://github.com/829304/MediaLib/blob/64f8ee258d87389414d5e06740a89f59cd857612/Sources/MediaLib/Views/PlayerView.swift)
- [SettingsView.swift](https://github.com/829304/MediaLib/blob/64f8ee258d87389414d5e06740a89f59cd857612/Sources/MediaLib/Views/SettingsView.swift)
- [SubtitleSearchServiceTests.swift](https://github.com/829304/MediaLib/blob/64f8ee258d87389414d5e06740a89f59cd857612/Tests/MediaLibTests/App/SubtitleSearchServiceTests.swift)

# 公共逻辑提取（2026-10-27）

本轮只合并语义一致的实现，不调整目录架构、产品界面、数据库结构或凭据存储方式。对照原 `AppSettingsStore.swift` 的普通设置与秘密存储分离原则；原版历史配置导入不属于本轮范围。

## 提取内容

- `lib/storage/preference_store.dart`：数据库原始字符串读写，null 删除、空字符串保留；调用方负责 trim、默认值和业务校验。沿用调用方当前事务，不增加缓存、串行锁或来源通知。覆盖播放器设置、外部播放器、TMDB 语言、首页布局写入、媒体库视图、播放历史版本、收藏及缓存目录。
- `lib/application/async_tasks.dart`：串行任务队列，失败不阻断后续任务；可取消等待，统一取消监听清理。TMDB 和字幕设置保留各自的校验与凭据回滚。连接器、详情和缓存字幕保留原超时与错误策略。
- 可取消等待不等于强制终止任意 Future；底层请求仍需接收取消信号。字幕子任务通过取消回调中止，超时置于受管理任务内，以确保超时后释放父任务监听。
- 首页布局和播放器设置原有批量读取保留，没有改成逐键查询。Emby 账号识别/凭据更新中的插入语义、想看初始评级等存在业务差异的代码没有强行合并。

## 代码量与验证

第一批按开始时保存的 11 个调用方文件统计，调用方减少 103 行；新增两个公共实现共 55 行，生产代码净减少 48 行（3635 → 3587）。含注释和空行，不含新增测试和本文；不是相对 Git HEAD 的整个共享工作区统计。基线记录：`apps/client/build/common-extraction-before.txt`。

12 个相关测试文件 176 项通过，记录 `apps/client/common-extraction-tests.log`。新增测试覆盖原始空值/空白语义、事务回滚、串行任务失败后继续、取消前不启动、活动任务取消、迟到错误以及监听释放。已有测试覆盖设置保存、详情缓存、请求取消、离线缓存、首页布局、播放读取和导航。

flutter analyze 无问题；Windows Release 构建成功（47.4 秒）。记录：`apps/client/common-extraction-analyze.log`、`apps/client/common-extraction-build.log`。未宣称真实服务器、macOS/Linux 原生场景完成验收。

## 第二批：播放设置事务与 JSON 读取

第二批只改播放设置 repository 内部的重复流程，不改变业务行为或界面：

- `playback_session.dart` 新增私有 `_changeSetting<T>`，统一 8 处“应用→保存→失败回滚→状态刷新”流程。各模块原有的类型检查、归一化、队列执行时合并、专属提示、回滚异常类型和 trace 名称均保留。`subtitleStyle` 与 `timing` 在 apply 失败时原本不刷新的边界，通过 `refreshAfterApplyFailure=false` 显式维持。
- `player_preferences_repository.dart` 新增私有 `_readJsonSetting<T>`，复用 5 种 JSON 设置读取。默认值不变；仅原本字幕/色彩恢复会处理的两个 `TypeError` 使用 `recoverTypeErrors=true`，其余读取错误策略保持原样。设置键名、表、批量快照、缓存及通知均未改变。

### 第二批代码量

第二批开始前两个目标文件共 3,105 行（`playback_session.dart` 2,756 行 + `player_preferences_repository.dart` 349 行）；完成后共 3,043 行（2,710 + 333），净减少 62 行，helper 已计入。基线为 `apps/client/build/common-settings-before.json` 与 `apps/client/build/common-settings-before/*.dart`；数量记录 `build/common-settings-line-count.json`。两文件 format 检查 0 changed（`build/common-settings-format.log`）。该数字是共享工作区中的本批前后对照，不是相对 Git HEAD 的变更总量；第一批净减 48 行单独保留，不与本批验证混算。

### 第二批验证状态

第二批 9 个相关测试文件 **97/97 通过（8 秒）**，记录于 `build/common-settings-tests.log`：video_render_settings/performance/equalizer/sharpen/color/display、player_subtitle_settings、playback_read_performance、player_video_display_settings。覆盖偏好恢复、实际命令失败、数据库保存失败、回滚再次失败、连续排队修改、字幕前序操作回滚后合并、误值默认及播放偏好保持单次 SQLite 读取；复用已有失败场景，没有增加机械重复测试。`build/common-settings-analyze.log` 全 `lib` analyze clean。仅涉及两个目标文件；未改底层 mpv 命令、UI、认证或数据库结构。

第二批 Windows Release `build/common-settings-release.log` 构建成功（46.3 秒；这是本批 Release 构建，不是前端 41 秒构建）。最终五秒 smoke 通过，记录于 `build/common-settings-smoke.json`：`CheckedAt=2026-10-27T20:21:52.0558631+08:00`、`ObservationSeconds=5`、`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。未跑全量 Flutter 测试、真实媒体验收、其他平台验收，也未重跑与本次改动无关的裸 mpv engine native 专项；不据此宣称本批原生场景或三平台验收通过。第一批的 176 项相关测试、47.4 秒 Release 和 20:10 +08 smoke 仅属于第一批，不能作为第二批通过证据。

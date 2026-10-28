# 本地视频健康补充与 NFO 写回计划（2026-10-28）

状态：**实现与健康中心 UI 已接入；Windows 定向交付验证通过。** 15 个定向文件 164/164 通过（约 9 秒，`apps/client/build/nfo-final-tests.log`）；`flutter analyze` no issues（3.9 秒，`apps/client/build/nfo-final-analyze.log`）。61 个变更/新增 Dart 文件格式检查 0 更改，`git diff --check` 通过。Windows Release 44.3 秒成功（`apps/client/build/nfo-release.log`）；五秒 hidden smoke 于 `2026-10-28T09:52:30.7252957+08:00` 通过，报告 `apps/client/build/nfo-smoke.json`：`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`。Windows 原生 writer 安全回归首轮通过；macOS/Linux 原生、真实 NAS 仍待验。本阶段将 NFO 写回限制在健康中心的一键补充流程中。普通 TMDB 单项匹配、手动批量匹配和定时自动匹配仍只更新 ReelNest 索引，不触碰媒体目录。

## 本阶段目标

- 在健康中心从参与元数据拉取的本地电影、电视剧和动漫中，筛出缺失元数据的条目，用户明确启动“一键补充”后才查询并补齐缺失字段。
- 复用现有 TMDB 查询、匹配评分、详情获取、图片缓存和元数据更新流程；匹配不到、低置信度、网络或解析失败时跳过/报告，不以首个搜索结果盲目覆盖。
- 保留来源级 `includeInMetadataFetch` 开关，并迁移原版 `preferMetadataWriteToSource`（默认关闭）。仅该偏好打开且该来源参与元数据拉取时，才尝试把本次成功补得的字段写入本地 NFO。
- 先提交 ReelNest 索引，再独立尝试源 NFO 写回。写回失败时保留已提交的索引，并通过健康任务警告数和结果提示说明失败；数据库提交与文件系统写入不是跨资源原子事务。

## 原版行为基线

只读对照 `E:\workspace\829304\MediaLib`：

- `Sources/MediaLibCore/Services/VideoMetadataSidecarPolicy.swift` 根据来源类型、写回偏好、媒体路径、系列子项和私有库状态确定目标。远程来源、未启用写回、越出授权根目录、所有权不明或不支持类型均跳过。
- `VideoMetadataSidecarWriter.swift` 为单个视频文件写同 basename 的 `.nfo`；有文件 backing 的电影/视频类型用 `<movie>` 根。剧集/动漫只允许将所有现有 episode 文件解析到同一系列目录后，写该系列目录下 `tvshow.nfo`；源目录本身、不同系列混合及无法确认的路径均拒绝。不得按媒体源根创建/覆盖系列 NFO。
- 现有 NFO 仅合并受支持字段，保留未知节点、未知字段及非 TMDB `uniqueid`。安全限制包括拒绝符号链接目标、外部实体/DTD、坏 XML、根元素不兼容和大于 4 MiB 的文档。先写临时文件并校验，再进行原子替换；提交前复核外部修改，并在替换失败时恢复/保留安全副本。不得修改媒体本体。
- 原版写回调用链：`AppState.supplementMissingMetadataFromHealth()` 从健康中心入口启动补充任务；`performMetadataSupplement` 对视频候选调用 `bestSupplementalVideoUpdate`，若来源 `preferMetadataWriteToSource` 开启则先尝试 `writeVideoMetadataSidecarIfPossible`，失败只记 warning，随后调用 `updateMetadata` 保存 ReelNest 索引。普通搜索/单项匹配/批量流程没有该写回调用。
- 原版来源设置 `preferMetadataWriteToSource` 默认 `false`，并受 `includeInMetadataFetch` 控制；关闭参与元数据拉取时同时关闭写回选择。健康中心入口位于 `LibraryHealthCenterView.swift`，触发 `supplementMissingMetadataFromHealth()`。

## 本阶段范围与明确边界

- 本阶段只处理本地电影、电视剧和动漫。原版 writer 兼容的纪录片、综艺、私有集合及其他文件 backing 视频分类暂不因此自动扩展；完成基线盘点后另行排期。
- 仅一键健康补充缺失元数据的流程可以请求写回。普通 TMDB 搜索/确认、批量匹配、定时自动匹配、媒体扫描、Emby/Jellyfin/Plex 远程资料、音乐、照片都不写入 NFO。
- NFO 不是数据库事实来源；源目录不可写、NFO 不安全/不兼容、所有权不确定或外部并发变化时，不降低路径/文件安全限制。索引更新与 sidecar 写入分别处理。
- 不新增数据库 schema，不改写视频文件，不自动整理/搬移已有 NFO。已有电影旧式目录 NFO 与按 basename 定位的专属 NFO 冲突时，先按原版“专属文件优先、保留旧 NFO”行为处理；禁止迁移或删除旧文件。
- 来源列表 `SourceRow`、其他未迁移的视频类型、macOS/Linux 原生行为及其他连接器不因本阶段完成而宣称通过。

## 实施分工

- 后端：Dart 路径归属策略、XML 安全解析与合并、临时文件/原子替换/恢复、并发与取消保护；健康补充只对本地电影/剧集/动漫启用；源写失败不阻止索引更新，并返回可展示的诊断结果。
- 前端：复用已迁移并持久化的来源级“元数据优先写入源目录”开关，复核其默认关闭、受元数据参与开关约束的行为；接通健康中心一键补充入口、运行进度和失败/跳过结果，文案明确这是 NFO 写回且仅在来源开关开启时尝试。
- 验证：分别覆盖 policy、writer、健康补充调用链、来源偏好持久化和 UI。最终记录定向测试、`flutter analyze`、format/diff-check、Windows Release/smoke；不可把这些结果表述为全量测试或跨平台验收。

## 验收清单

- [ ] 健康补充仅选本地、启用元数据拉取的电影/剧集/动漫缺失项；其它类型和远程来源不写回。
- [x] TMDB 普通单项匹配在来源写回偏好开启时仍不写 NFO；手动批量与定时自动匹配维持各自匹配路径，不调用 NFO writer。
- [x] 默认不写回；来源参与元数据关闭时不能保留写回开启状态。关闭/不可用设置行为与原版一致。
- [x] 电影写入独立 basename `.nfo`；系列必须确认共同系列目录并写 `tvshow.nfo`，拒绝 source root、跨系列、越界、缺路径和符号链接逃逸。
- [x] XML 合并只改本次补充字段，保留原有标题等有用字段、未知 XML 内容及非 TMDB ID；拒绝 DTD/entity、无效 XML、错误 root 和超 4 MiB 输入。编辑标题仅在已有 localized TMDB identity 相同的补充时保留；首次或更换匹配允许更新标题。
- [x] 写临时文件、原子提交、并发外部编辑保护与失败恢复有效；回归确认媒体文件内容不变。
- [x] NFO 写回失败后索引仍能成功更新并显示警告；NFO 写入后由 `LocalMetadataService` 读取，真实来源重扫后可读回补充字段。
- [x] 定向回归、静态分析、format/diff-check 和 Windows Release/smoke 完成。真实公服、长时间、macOS/Linux 原生、可见 UI 与全量套件仍待验。

## 实现与当前验证

- 已接入 `VideoNfoPolicy`、`VideoNfoWriter`、`supplementOnly` 的缺失字段合并，以及健康中心一键补充/进度/结果提示。现有来源写回偏好默认关闭，且要求来源参与元数据拉取。
- 当前 Dart 实现：`MetadataSupplementService` 仅筛选本地电影及 TV/anime series 缺失项，并复用 TMDB matcher。`TmdbVideoService.apply(..., supplementOnly: true)` 先提交 ReelNest 索引事务，再单独按来源偏好尝试 NFO 写入；这不是跨数据库与文件系统的原子事务。既有年份、简介和封面等有用字段保留；localized TMDB identity 相同时保留用户编辑过的标题，首次或更换匹配则允许纠正标题。NFO 写回失败保留已提交的索引并增加 warning。
- 最终 15 个定向文件 164/164 通过（约 9 秒，`apps/client/build/nfo-final-tests.log`）；最终 `flutter analyze` 无问题（3.9 秒，`apps/client/build/nfo-final-analyze.log`）；61 个变更/新增 Dart 文件格式检查 0 更改，`git diff --check` 通过。覆盖 NFO writer/policy/supplement、健康中心 UI、来源配置、TMDB movie/series/batch/automatic/UI、health evaluator 与 app 回归；另验证写入 NFO 后由 `LocalMetadataService` 读取，并在真实来源重扫后恢复字段。此前失败或重复运行结果不累计。
- writer/policy 回归覆盖 XML 合并与未知字段保留、危险/不兼容 XML、4 MiB 上限、外部并发修改、目标符号链接、替换失败恢复、路径所有权及电影/系列目标；Windows 原生 writer 安全回归首轮通过。Windows Release 44.3 秒成功（`apps/client/build/nfo-release.log`）；五秒 hidden smoke 于 `2026-10-28T09:52:30.7252957+08:00` 通过，`apps/client/build/nfo-smoke.json` 确认窗口响应、正常关闭、ExitCode 0。
- 本批未运行全量测试；macOS/Linux 原生、真实 NAS/挂载行为和可见 UI 逐项对照仍待分别验收。不要将 Windows writer 验证表述成跨平台验收。

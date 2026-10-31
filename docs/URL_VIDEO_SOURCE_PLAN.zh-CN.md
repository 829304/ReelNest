# 持久 URL 视频媒体源计划（2026-10-28）

状态：**封面修订后的 Windows 本批定向交付验证通过。** 8 文件 52/52、最终 analyze、格式检查、Windows Release 39.0 秒及最终 smoke 均通过。封面修正是只读核对原版 `ThumbnailGenerator` 后补齐解码语义的质量修正。189/189 与修订后 52/52 有覆盖重叠、不累计；修订前 20/20 与 53.1 秒 Release/14:59 smoke 仅作中间证据。macOS/Linux 原生、真实服务、逐像素 UI 和全量测试仍待。

## 范围

- 把用户添加的网络视频地址保存为持久媒体条目，归入唯一的虚拟 URL 来源容器，并在该来源的当前浏览页显示为 `homeVideo` 条目。本批不迁移全局「其他视频」分类入口。
- 支持单条及多行批量添加、地址去重、名称自动生成、管理 sheet 中编辑、删除及复制链接；删除容器内最后一个地址后清理空容器。
- 已交付范围为现有媒体详情、内置播放器、HTTP/HTTPS 外部播放、播放进度持久化，以及添加后自动提取封面；封面提取失败不阻断添加。
- URL 离线下载、手动截帧设为海报及自定义封面入口未包含在本计划此前的 URL 来源交付中；URL 缓存现按 2026-10-31 用户授权进入本计划，见下方专项边界。手动截帧和自定义封面仍属于待迁移能力，不得从产品范围删除。
- 自动封面与普通预览采用不同解码模式：封面保持源画面比例，最大 900×1350、不放大小图；普通预览仍为 312×176。取样比例依次为 `[0.2, 0.15, 0.2, 0.3]`；每次取样位置为时长乘以比例，至少取第 1 秒，ratio 限于 0.01–0.95。黑帧判定沿用原版 800 点、37×53 坐标采样，亮度低于 16 且黑点比例超过 0.88；封面/预览共用 worker，但以 mode 隔离解码行为。
- 来源健康设置开启时检查 HTTP(S) 地址可达性和响应类型；其他可播放协议不发起健康网络请求。
- 外部播放器能力遵循原版：仅 HTTP/HTTPS 地址可交给外部播放器；其他受支持协议仅由内置播放器尝试，外部打开时明确提示不支持。

不包括 SMB/FTP 网络挂载、音乐、照片或新播放器能力。URL 视频本身可接受原版支持的 FTP 视频地址；这不等同于 FTP 文件系统挂载。

此项是可持久保存到媒体库的 URL 来源；已完成的临时 URL 播放/拖入能力属于独立入口，不代表持久媒体源已迁移。

## 原版行为基线

只读对照 `E:\workspace\829304\MediaLib`：

- `URLSourcePolicy.mediaSourcePath` 固定为 `urlsource://local`，只创建至多一个 `.url` 类型虚拟来源，默认 `homeVideo`、不递归、不自动扫描、不参与元数据拉取、参与健康检查。视频条目类型为 `homeVideo`，URL 保存于 `filePath`，所以仍走现有其他视频浏览和播放链路。
- 支持协议：`http`、`https`、`rtsp`、`rtmp`、`rtp`、`mms`、`srt`、`udp`、`ftp`。添加时去除首尾空白，要求 URL 有 host；默认名称优先取路径末段去扩展名，路径无末段时回退 host。
- 稳定 ID 由规范化 URL 生成；重复地址拒绝单项添加，多行批量按行读取、跳过空白/无效/已有/重复地址，保留输入顺序并报告新增数量。管理支持改名、换地址和删除；换地址时重算 ID 并防止重复，清空后删除虚拟来源。
- 单条添加可自定义名称；批量添加使用自动名称。添加成功即尝试静默截帧，失败不影响地址保存；管理项可重新截帧或选择自定义封面。
- URL 媒体作为普通 `homeVideo` 条目接入当前来源浏览，因此复用详情、内置播放、HTTP(S) 外部播放、播放记录/进度等现有调用链，不另建播放状态模型；全局其他视频分类入口与完整公共分类/集合导航尚未迁移。
- 健康监控只把 HTTP(S) 地址放入探测队列；并发 HEAD 请求失败后以 `Range: bytes=0-1023` 的 GET 兜底，超时 12 秒。HTTP 状态码 ≥400 判为无法访问，`text/html`/`application/xhtml` 判为不可解析，其余 HTTP 响应为正常；健康关闭时取消并清空结果，刷新会剔除已删除条目的过期状态，过期 refresh 回调不得覆盖新结果。
- `SourcesView.swift` 的来源向导选择 URL 后不进入通用策略页，配置提交后直达；来源行提供管理入口，管理 sheet 提供批量添加、编辑、删除、封面和重新健康检查。
- 本项目实现涉及 `SourceKind`、`SourcesPage`、URL 管理 sheet、`SourceLibrary` 与 `LocalMediaDetail`；持久 URL 来源和已完成的临时打开串流仍为不同用户流程。
- 原版策略与健康回归见 `Tests/MediaLibTests/App/URLSourcePolicyTests.swift`、`URLSourceHealthMonitorTests.swift`；ReelNest 当前阶段的定向验证证据与未完成项见下方“当前验证”。

## 迁移与验收要求

- 复用当前 `MediaSource`、`MediaItem`、其他视频浏览、播放和播放进度持久化；虚拟容器与条目增删改必须在应用重启后恢复，禁止新增独立 URL 播放历史。
- URL 健康探测仅在来源 `includeInHealthCheck` 开启时运行，且只探测 HTTP(S)；RTSP/RTMP/FTP 等其他受支持协议显示未知/不参与健康结论，不能因未探测标失效。
- 单条/批量输入的协议校验、规范化、去重、稳定身份、标题回退、更新冲突、空容器清理和部分失败行为均需逐项回归。
- 添加成功自动截帧；封面获取失败时保留可播放条目。原版自定义封面与手动截帧设海报能力尚未迁移，后续依赖公共 artwork 流程实现。
- Windows、macOS、Linux 分别进行原生播放/封面/健康探测验收；未实际完成的端不得标为通过。真实服务器、用户可见 UI 与全量套件按实际证据记录。

## 验收边界

- [x] 单条及多行持久添加、去重、编辑、删除和空容器清理已接入并有定向回归覆盖；最终持久化/重启及整体回归结论仍随最终证据收口。
- [x] 地址可在 URL 来源当前浏览页显示为 `homeVideo`，并沿用详情、内置播放、HTTP(S) 外部播放及播放进度记录；URL UI 定向用例已纳入最终 189 项整合回归。全局其他视频分类入口尚未迁移。
- [x] 添加时自动提取封面；封面失败保留地址。未实现 URL 离线下载、手动截帧设海报或自定义封面入口，这些原版能力作为公共缓存/封面模块依赖保留在迁移范围。
- [x] 健康监控只探测 HTTP(S)，定向回归覆盖非 HTTP 跳过、关闭来源时不探测、删除条目后的迟到结果保护、响应头分类及不读取超大响应体；headers-only HEAD 仅在传输失败时以 Range GET 兜底，保留原版 HTTP 405 不回退规则。健康 UI 列表、忽略/恢复与管理流程已包含于前一版 20 项 UI/native 验证；新封面逻辑复验中。
- [ ] Windows/macOS/Linux 原生验收及精确 UI 对照按平台分别记录；真实 URL 服务和全量测试如未执行则注明待验。

## 当前验证

- 健康坏链接具体列表、管理/复制/删除/忽略与设置恢复已补齐；CRUD 不等待健康网络请求，手动刷新不锁定管理 sheet 且可关闭。最终整合 15 文件 189/189 通过（39 秒，`apps/client/build/url-final-tests.log`），取代此前 186/186，不累计；该批不代表全量套件。
- 前序后端 URL 专项 12/12（`apps/client/build/url-backend-final-tests.log`）、analyze（`url-third-analyze.log`）和 native 专项（`url-native-final-tests.log`）保留作历史证据；与整合/交付组覆盖重叠，不累计。URL 网络 native 用例仅使用 loopback，不代表真实公网服务。
- 封面修订后 8 文件定向 52/52（7 秒，`apps/client/build/url-cover-final-tests.log`）及最终 analyze no issues（`apps/client/build/url-cover-final-analyze.log`）通过。定向组覆盖 native 3 项、URL/health UI、backend 12 项、普通 preview/proxy/session；与 189/189 及旧20/20有覆盖重叠，不累计。native PNG 断言验证 160×90 小图保持源比例，不强制变为 312×176 黑边帧；普通预览 native 仍为 312×176。
- 此前整合 15 文件 189/189（`apps/client/build/url-final-tests.log`）及修订前 UI + native 4 文件 20/20（`apps/client/build/url-delivery-tests.log`）保留为前序中间证据，不代表当前修订组通过。
- 封面修订后 Windows Release 39.0 秒成功（`apps/client/build/url-cover-release.log`）；五秒 hidden smoke 于 `2026-10-28T21:09:12.4990275+08:00` 通过，窗口响应正常、正常关闭、ExitCode 0，报告 `apps/client/build/url-cover-smoke.json` 存在。
- 修订前 Windows Release 53.1 秒与 14:59 smoke（`url-release.log` / `url-smoke.json`）仅保留为中间批次，不作为最终交付证据。
- 26 个变更/新增 Dart 文件格式检查 0 变化，`git diff --check` 通过。
### 2026-10-29 URL 管理弹窗 P0（Windows 定向交付验证通过）

- 按原 `URLSourceManagementSheet` 收口添加/编辑/删除与确认文案、弹窗表面、行交互、按钮命中区及静态加载进度。URL/UI/数据/来源联动21项通过，2项native mpv conditional skipped；analyze 0 issue，Windows Release38.5秒；后台 smoke 于15:05:46 +08通过（HiddenWindowResponding=true、ClosedNormally=true、ExitCode=0），无 ReelNest 残留进程。Flutter SDK临时兼容改动已还原。此批没有验证macOS/Linux可见 UI。
- macOS/Linux 原生、真实服务/公网 URL、完整可见及逐像素 UI 验收、全量测试仍待；native 网络用例仅使用 loopback HTTP，不宣称真实公网或三桌面端验收完成。

## 2026-10-31 HTTP(S) URL 单视频离线缓存（本轮 Windows 定向交付通过）

用户已授权迁移原版 URL 视频缓存能力。本阶段只覆盖持久 URL 来源中可直接下载的 HTTP(S) 单视频地址，使用原始媒体质量；实现复用 ReelNest 已有视频缓存队列、当前清单、暂存发布、播放租约及容量/孤儿清理机制，不另建 URL 专用下载状态或缓存格式。

原版依据：`Views/VideoCacheMenuItems.swift` 对 URL 视频使用通用“缓存到本地/重新缓存到本地”与删除入口；`MediaLibCore/Models/VideoOfflinePolicy.swift` 的 `isCacheableVideoCandidate` 只接受带 HTTP/HTTPS scheme 的非音乐视频；`AppState.videoCacheQualityChoices` 对没有远程降档选项的地址回退提供“原画 · 直连缓存”。

### 目标行为

- 对 HTTP/HTTPS URL 视频提供与原版一致的“缓存到本地/重新缓存到本地”及删除缓存入口，并接入现有缓存任务、进度和容量信息。
- 单视频按 URL 原始字节下载，不转码、不选择 Emby 画质档。已完成且可用的本地副本优先播放；本地副本缺失、损坏、路径不可用或租约/清单读取失败时，保留清单并回退该 URL 的在线播放，给出独立缓存提示。在线播放自身失败仍显示播放错误。
- 新缓存先写入受管理的暂存位置，校验后原子发布并替换清单。重新缓存期间旧副本仍可播放；下载失败、取消、校验失败或提交失败只清理本次未提交文件，不得删除/覆盖旧缓存。播放会话租约保护正在播放的副本，容量维护与删除不得回收有效租约指向的文件。
- 下载只能处理可作为单文件下载的普通 HTTP(S) 视频响应；下载过程按流写盘，不将整段视频读入内存。遵循现有缓存目录可写性、路径约束和清理规则。

### 验收范围

- [ ] 来源筛选：仅 URL 来源的 HTTP/HTTPS 项可缓存；RTSP、RTMP、RTP、MMS、SRT、UDP、FTP 等其他协议不发起缓存下载，也不因此被判为失效。
- [ ] 文件语义：普通单视频响应成功落盘并按原画播放；拒绝/明确处理 HTML 错误页、无效响应、零字节或写入失败，不登记为已缓存。
- [ ] 队列与任务：重复任务去重，进度/排队/取消/失败状态可见；如复用现有队列不支持的暂停/续传行为，不新增 URL 专属产品流程，按既有缓存任务能力验收。
- [ ] 失败保护：缓存替换时注入下载失败、取消、清单提交失败和进程关闭情形，确认旧文件及旧清单继续有效，新暂存文件最终可安全回收。
- [ ] 播放优先级：可用副本离线优先且不请求原 URL；manifest 有记录但文件缺失或长度损坏时提示并回退在线播放，不抹除旧 manifest 记录；缓存存储故障时在线回退；离线时有副本仍可开始播放。`hasRecord` 只读 manifest 状态，不以文件当前存在性改写旧记录。
- [ ] 并发保护：播放租约期间删除、容量清理及成功重缓存均不移除当前播放文件；释放/过期租约后按公共清理机制回收旧副本。
- [ ] UI 与容量：不可缓存的非 HTTP(S) 地址及清单类地址显示禁用状态和原因；若该条目已有缓存，删除缓存操作仍可用。缓存存在、下载中、失败和删除状态与现有 URL 管理及缓存任务界面一致，容量统计包含 URL 缓存。
- [ ] Windows、macOS、Linux 原生下载/离线播放分别验收；真实可访问 HTTP(S) 文件、可见 UI 和精确原版对照单独记录，未测平台不得标通过。

### 明确不在本轮范围

- 不做 HLS/DASH 等多段流离线打包、播放列表、直播或分段清单解析。
- 不做转码、画质选择、字幕抓取、跨重启断点续传新流程或其他协议（包括 FTP）下载。
- 不做手动截帧设海报或自定义封面；它们仍是独立待迁移能力。

### 本轮交付与验证

- 本轮实现复用共享 manifest/staging/lease/queue，支持 HTTP(S) 原画下载、取消/暂停/续传；HTTP 错误、断流、SQL 发布失败、实际落盘失败均保护旧缓存。缓存目录失败时回退在线播放。
- URL 下载使用独立 `HttpClient`，不携带 Emby 认证；CDN 重定向保留目标 query，不复制旧凭据；服务器认证下载跨站时拒绝。HLS/DASH 依 URL、MIME 和最多 512 字节前缀检查拒绝，不下载分段。
- manifest 有记录但文件缺失或长度损坏时提示并在线回退，保留旧记录；`hasRecord` 只读 manifest。非 HTTP(S)/清单地址保留禁用原因，已有缓存仍可删除。
- 最终定向自动化：11文件175/175，23秒，exit 0（`apps/client/build/url-cache-final-tests.log`），覆盖 URL 缓存/来源 UI、共享 Emby 缓存/离线、外部播放、播放和健康回归。显式设置 `REELNEST_MPV_PATH`，原生 mpv 缓存解码用例实际执行、未跳过。先前68/68与20/20为阶段组，与最终组覆盖重叠、不累计；首轮UI等待超时为中间结果，修正后最终组通过。
- `dart analyze lib test integration_test` 无问题（`apps/client/build/url-cache-final-analyze.log`）；12个变更新增 Dart 文件格式检查0 changed。Windows Release 67.7秒成功（`apps/client/build/url-cache-release.log`）；五秒 `windows-smoke` 于 `2026-10-31T19:31:42.0886533+08:00` 通过（`HiddenWindowResponding=true`、`ClosedNormally=true`、`ExitCode=0`），报告 `apps/client/build/url-cache-smoke.json` 已实际复制并核验。本轮未修改 Flutter SDK。
- 本轮未运行全量 Flutter 测试；此前 Emby browse/scroll 两项已在媒体库浏览 P0 中修复并通过目标回归。URL 缓存专项不改变其全量测试口径。macOS/Linux、真实公网及人工可见 UI 验收仍待。

阶段状态：**本轮 HTTP(S) URL 单视频缓存实现完成，Windows 定向交付验证通过。** 这不代表整个 URL 模块完成：全量测试、真实公网、人工可见 UI、macOS/Linux 验收未完成；手动截帧/自定义封面及全局其他视频分类入口仍未迁移。

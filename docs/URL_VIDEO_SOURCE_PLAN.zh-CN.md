# 持久 URL 视频媒体源计划（2026-10-28）

状态：**封面修订后的 Windows 本批定向交付验证通过。** 8 文件 52/52、最终 analyze、格式检查、Windows Release 39.0 秒及最终 smoke 均通过。封面修正是只读核对原版 `ThumbnailGenerator` 后补齐解码语义的质量修正。189/189 与修订后 52/52 有覆盖重叠、不累计；修订前 20/20 与 53.1 秒 Release/14:59 smoke 仅作中间证据。macOS/Linux 原生、真实服务、逐像素 UI 和全量测试仍待。

## 范围

- 把用户添加的网络视频地址保存为持久媒体条目，归入唯一的虚拟 URL 来源容器，并在该来源的当前浏览页显示为 `homeVideo` 条目。本批不迁移全局「其他视频」分类入口。
- 支持单条及多行批量添加、地址去重、名称自动生成、管理 sheet 中编辑、删除及复制链接；删除容器内最后一个地址后清理空容器。
- 已交付范围为现有媒体详情、内置播放器、HTTP/HTTPS 外部播放、播放进度持久化，以及添加后自动提取封面；封面提取失败不阻断添加。
- URL 离线下载、手动截帧设为海报及自定义封面入口尚未迁移。它们属于原版已有能力，依赖公共缓存/封面模块，应保留在后续迁移范围，不能据此宣称本批交付或从产品范围删除。
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

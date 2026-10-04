# 系列摘要接口与客户端兼容

更新：2026-10-04。状态：本地静态实现，未编译、测试或部署。

## 实现位置

ReelNest 客户端使用 `codex/flutter-bootstrap` 分支。配套服务端位于原 MediaLib 仓库的 `codex/series-summary-api` 分支。客户端和服务端分别提交，提交信息使用 `[skip ci]`；提交代码不代表接口已经验证或部署。

服务端仅修改三个文件：

- `Sources/MediaLibServer/ServerDiscoveryHTTPHandler.swift`：接收现有系列数据提供器，增加摘要 JSON 路由。
- `Sources/MediaLibServer/LocalLoopbackHTTPServer.swift`：向处理器传入现有 `seriesDetailProvider`。
- `Sources/MediaLibServer/MediaLibServerEntry.swift`：共用能力列表增加 `series-detail`，供发现接口和命令输出使用。

复用原有 `ServerSeriesDetail`、`ServerSeriesSeason` 和 `ServerLibraryCatalog.seriesDetail`，不新增数据库结构、媒体扫描或鉴权机制。

## 路由契约

`GET /api/v1/series/{id}`，支持 HEAD。需要有效登录凭据及 `viewMedia` 权限，沿用 `apiRead` 限流。数据提供器按当前用户的来源权限、内容分级和用户 ID 读取摘要及观看统计。

ID 是单个百分号编码的路径组件，解码后最多 512 UTF-8 字节，不可为空、`.`、`..`，不能包含斜杠、反斜杠或 ASCII 控制字符。摘要路由不接受查询参数，也不接受空 `?` 或尾斜杠。ID 本身可为 `episodes`；只有增加 `/episodes` 子路径才进入原有按季分页接口。

| 响应 | 含义 |
|---|---|
| 200 | 原有 ServerSeriesDetail 的 JSON；HEAD 不返回正文 |
| 400 | 非法路径、ID 或查询 |
| 401 | 未认证或凭据失效（外层认证处理） |
| 403 | 缺少 viewMedia 权限 |
| 404 | 系列不存在，或当前用户不可见 |
| 405 | 已认证请求使用 GET/HEAD 以外的方法 |
| 429 | 命中原有 API 读取限流 |
| 503 | 数据读取或 JSON 编码失败 |

主要字段：`id`、`type`、`title`、`originalTitle`、`year`、`overview`、`genres`、`communityRating`、`artworkAvailable`、`backdropAvailable`、`totalEpisodeCount`、`seasons`、`userPreference`。可选字段沿用 Swift Codable 的省略规则；不返回本机文件路径、来源路径或其他用户数据。

每个季包含 `id`、可选 `seasonNumber`、`title`、`episodeCount`、`watchedCount`、`inProgressCount`。季号 0 表示特别篇，缺失/空值对应 `unspecified`。客户端校验季 ID 和 selector 唯一，计数非负且单项观看统计不超过该季集数；观看中与已看不擅自视为互斥。季顺序沿用服务端顺序。

按季分页继续使用 `/api/v1/series/{id}/episodes?season=...&offset=...&limit=48`；不由总集数或季数猜测季号。系列详情的用户评分不会充当社区评分。

## 客户端能力协商

打开或刷新系列详情时，重新读取 `/.well-known/mlink`，核对服务器 ID 与登录时一致，再检查 `capabilities` 中的 `series-detail`。

- 有该能力：调用系列摘要路由，展示总集数、季列表和观看统计，继续按季分页。
- 无该能力：调用既有 `/api/v1/items/{id}` 查看基本资料，提示升级；普通媒体与单集详情不受影响。
- 新接口返回错误：保留实际错误和重试入口，不静默切换到旧接口。401 沿用仓库的一次令牌轮换重试；跨会话响应仍被丢弃。

实时能力只保存在当前仓库实例中，不修改凭据存储格式。服务器升级后刷新详情即可重新读取能力；若服务器 ID 改变，要求重新连接。

## 后续验证与部署顺序

以下均为待办，没有执行：

1. 在允许恢复验证且环境就绪后，解析客户端已有依赖并更新 lock，执行格式检查、分析和必要测试；服务端在可用 Swift 环境编译和验证。
2. 服务端覆盖 GET/HEAD、未登录、无权限、来源/分级过滤、用户统计隔离、缺失系列、限流、读取异常，以及非法 ID/查询/尾斜杠。回归原有 episodes 路由，特别包含 ID 为 episodes 的情况。
3. 客户端覆盖旧版无能力、新版有能力、升级后刷新、身份改变、错误响应、特别篇、未分季、空系列、重复季、分页重试和退出竞态。
4. 先验证并部署含路由和能力声明的 MediaLib 服务端，再用 ReelNest 联调系列 → 季 → 单集。能力声明必须与实际路由一起发布，不能只单独添加字符串。
5. 客户端可以先部署到旧服务端环境，但届时只能查看系列基本资料。服务端扩展不会自动随 Flutter 五端产物一起部署。

本轮没有触发 CI、连接真实服务器或执行上述命令；保留静态实现状态，不将其表述为已验证可用。

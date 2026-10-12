# Emby 初始评级与显示分类

2026-10-10。按用户确认的两项收尾实施；第一阶段仅 Windows/macOS/Linux。

## 原版依据

- Sources/MediaLib/App/EmbyService.swift 的 normalizedProviderRating、seedUserRating、mediaItem、syntheticSeriesParents：有效社区评分为大于 0、至多 10 的有限数；初始星级为评分除以 2、四舍五入并约束到 1–5。补建系列继承单集评分及题材。
- Sources/MediaLibCore/Models/RemoteLibraryClassificationPolicy.swift 及其测试：库名优先于题材，题材优先于库类型，最后回退原始媒体类型；无提示的 episode 回退 tvShow。中文和英文子串按原顺序匹配，动漫优先电影，家庭视频优先普通电影。
- Sources/MediaLib/App/AppState.swift 的 classifiedEmbyTopLevelItem：只对顶层、非音乐的远程内容生成展示分类，子集关系和原始媒体身份不变。

## 实现

domain/remote_media_policy.dart 集中保存评级换算和有序分类规则。社区评分保持 10 分制：8.2、8.4 对应初始 4 星，9、10 对应 5 星；无效值不生成评级。导入、新建想看记录及确实不存在偏好记录时的读取回退使用同一换算。已有偏好记录、手动评级及显式清空在重新同步后保留，不拿社区评分覆盖；没有数据库升级、历史结构分支、自动修正已有开发偏好或清除用户数据。

同步将库名、库类型和题材写入无凭据远程元数据 JSON；补建系列也保留题材。IndexedMedia.displayType 为所有索引读取入口提供同一展示分类，当前海报占位与视频范围使用它。原始 type、identity_kind、isSeries、父子和季集编号仍用于播放、队列及同步，不因分类改变。名称/题材/库类型随成功同步刷新，失败沿用完整旧快照；离线读取不请求服务器。

分类保留原版关键词及优先级，不增添新分类或页面入口。文本处理包含百分号解码、大小写、全角 ASCII/空格和拉丁重音折叠；非法转义或 UTF-8 沿用原文本。纯 Dart [unorm_dart 0.3.3](https://pub.dev/packages/unorm_dart/versions/0.3.3) 提供 NFD 分解，避免用平台进程处理文本；相关行为有针对性回归，完整地区语言行为仍需原版环境对照。

## 验证

新增 22 项回归，覆盖评级边界、四舍五入、缺少偏好/显式清空、社区分变化后保留人工操作、分类优先级及原版样例、异常转义、仅顶层分类、三桌面目标的海报占位、同步失败原子性、离线索引读取、系列补建和音乐数据保留。

全量检查、正式 Release 及启动结果记录在 [当日测试报告](TEST_REPORT_2026-10-10.zh-CN.md)。测试使用临时 SQLite 和本机 HTTP Emby 替身；三桌面组件目标不能替代 macOS/Linux 原生验证。

## 后续边界

这两项规则已接入 Emby 视频，不代表首页、公共分类页、公共集合/封面管理或完整 UI 已完成。按既定顺序继续首页；音乐独立推进，真实 Emby 联调、macOS/Linux 原生、长片/HDR/大库压力和原版视觉仍待验收。

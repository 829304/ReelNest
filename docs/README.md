# ReelNest 文档

本目录统一保存映栖 ReelNest 的规划与设计文档。更新时间：2026-10-05。

**当前约束：MediaLib 的 Flutter 重构，第一阶段仅 Windows/macOS/Linux；功能、UI 与交互一致，不自行新增、删除或修改功能。** [项目边界](PROJECT_SCOPE.zh-CN.md)替代此前“五端同时推进”“简化 UI 后期再重做”等假设。

品牌约定：客户端 **ReelNest**，自有服务端及对应可选来源 **ReelNest Server**。原 MediaLib 名称只用于源码出处、历史记录及必要的兼容说明。

当前目标是 MediaLib 的 Flutter 多平台重构：直接管理本地文件夹、移动硬盘、已挂载 NAS，以及 Emby/Jellyfin/Plex。此前“依赖 MediaLib 服务端、先做 Mlink 客户端”的规划已撤销。第一轮已实现独立目录来源、扫描、索引和浏览，Mlink 试验路由只用于回归测试；完整目标仍按实施计划推进。

| 文档 | 内容 |
|---|---|
| [项目边界与一致性要求](PROJECT_SCOPE.zh-CN.md) | 用户确认的范围、原版 UI/行为验收与已有偏差 |
| [下一阶段实施安排](NEXT_STAGE.zh-CN.md) | 原版基线、桌面主框架、本地来源还原与三桌面端验收 |
| [原版一致性核对清单](design/ORIGINAL_PARITY_AUDIT.zh-CN.md) | 原源码入口、已读规则、当前偏差、第一批落地范围及验收缺口 |
| [开发指南](DEVELOPMENT.zh-CN.md) | SDK、运行命令、验证结果和本地环境限制 |
| [本地媒体源与索引](LOCAL_SOURCES.zh-CN.md) | 第一轮纠偏实现、目录扫描、SQLite、来源隔离与验证边界 |
| [Windows 构建与冒烟](WINDOWS_SMOKE.zh-CN.md) | C 盘构建、7 项自动化测试、EXE 启动结果及未覆盖范围 |
| [原版源码映射](design/SOURCE_MAPPING.md) | SwiftUI 到 Flutter 的迁移来源与范围 |
| [Mlink 连接试验记录](MLINK_CONNECTION.zh-CN.md) | 历史登录/会话实现，停止作为产品主线扩展 |
| [媒体浏览与详情](LIBRARY_BROWSING.zh-CN.md) | 现有 Mlink 试验路径与可复用界面；待解除来源耦合 |
| [系列摘要接口试验记录](SERIES_API.zh-CN.md) | 历史服务端扩展，不再是新应用依赖，不执行部署 |
| [初始化决策](decisions/0001-client-bootstrap.md) | 应用标识、依赖、布局和 CI 选择 |
| [项目结构与模块设计](PROJECT_STRUCTURE.zh-CN.md) | 目录布局、模块职责、依赖方向、播放器和平台适配边界 |
| [Flutter 重构实施计划](FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md) | 旧项目复用边界、功能范围、开发阶段与验收标准 |
| [GitHub 仓库与发布规划](GITHUB_REPOSITORY_PLAN.zh-CN.md) | 仓库组织、分支、五端构建、版本与发布 |

`design/` 保存源码映射与界面参考，`decisions/` 保存重要技术决策。目录树中的计划项不代表代码已经实现。

当前自动化测试共 26 项通过；已修正来源过滤、旧库迁移、成功扫描清理与桌面窗口规则，并接入来源分组和本地扫描队列，详见下一阶段进度。原版完整 UI、播放器、macOS 持久目录授权和服务器直连仍待实现。旧 MediaLib 的系列摘要分支是此前错误方向产生的历史变更，未部署，不再作为后续任务前置条件。

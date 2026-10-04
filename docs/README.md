# ReelNest 文档

本目录统一保存映栖 ReelNest 的规划与设计文档。更新时间：2026-10-04。

| 文档 | 内容 |
|---|---|
| [开发指南](DEVELOPMENT.zh-CN.md) | SDK、运行命令、验证结果和本地环境限制 |
| [原版源码映射](design/SOURCE_MAPPING.md) | SwiftUI 到 Flutter 的迁移来源与范围 |
| [服务器连接实现](MLINK_CONNECTION.zh-CN.md) | Mlink 登录、会话存储、分类读取、平台配置和待验证事项 |
| [媒体浏览与详情](LIBRARY_BROWSING.zh-CN.md) | 分页列表、海报、详情与季集导航的实现及验证边界 |
| [系列摘要接口](SERIES_API.zh-CN.md) | 服务端补充路由、能力协商、新旧版本兼容及部署顺序 |
| [初始化决策](decisions/0001-client-bootstrap.md) | 应用标识、依赖、布局和 CI 选择 |
| [项目结构与模块设计](PROJECT_STRUCTURE.zh-CN.md) | 目录布局、模块职责、依赖方向、播放器和平台适配边界 |
| [Flutter 重构实施计划](FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md) | 旧项目复用边界、功能范围、开发阶段与验收标准 |
| [GitHub 仓库与发布规划](GITHUB_REPOSITORY_PLAN.zh-CN.md) | 仓库组织、分支、五端构建、版本与发布 |

`design/` 保存源码映射与界面参考，`decisions/` 保存重要技术决策。目录树中的计划项不代表代码已经实现。

当前已初始化 Flutter 工程并连接远程仓库；连接迭代已提交，随后新增媒体浏览、详情与系列入口代码。连接与浏览均尚未运行验证。旧 MediaLib 在独立分支补充系列摘要接口，作为配套服务端单独提交，尚未验证或部署，详见系列摘要接口文档。

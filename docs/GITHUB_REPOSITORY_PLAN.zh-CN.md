# 映栖 ReelNest：GitHub 仓库与发布规划

日期：2026-10-02
更新：2026-10-03，统一使用 `docs/`，补充应用外壳、播放器模块与结构设计链接。
分析基线：旧项目 MediaLib `64f8ee2`，旧产品版本 `1.8.0` / build `98`。
状态：规划稿。已确定品牌为“映栖 ReelNest”，先建立本地 `reelnest` 仓库；远程仓库、Flutter 工程、工作流和 GitHub 设置尚未创建或启用。

## 1. 推荐结论

新项目采用独立的 `reelnest` 主仓库，未来远程目标为 `829304/reelnest`，当前仅在本地创建。采用单仓库多模块的组织方式：一个 Flutter 客户端共享界面与业务代码，通过 Windows、macOS、Linux 构建环境分别生成 Windows、macOS、iOS、Android、Ubuntu 产物。

旧 `829304/MediaLib` 保留为参考项目与兼容服务端来源，不把旧源码整体复制进新仓库。这里保留新旧两个项目，并不表示按平台拆仓库；ReelNest 五端仍在同一个新仓库中维护。

不按操作系统拆仓库，不为五个平台建立长期分支。平台差异放进 Flutter 平台目录与能力适配层。服务端和客户端可以在同一仓库独立构建、独立发布；仓库数量不决定部署方式。

这样可以让一次功能修改、接口调整和测试更新在同一个 PR 中完成，也便于参考旧 Swift 实现。未来只有服务端形成独立团队、独立访问权限或明显不同的维护周期时，再评估拆仓库。

“一份代码”指共享主要实现，不是把同一个二进制复制给五个平台。仍然需要平台工程、部分原生代码、对应编译环境和发行签名。

## 2. 仓库目录

新仓库采用以下目标布局。旧 Swift 工程、测试和打包脚本保留在原 MediaLib 仓库；本仓库当前只有 README 与 `docs/` 中的规划文档。模块职责和依赖规则以[项目结构与模块设计](PROJECT_STRUCTURE.zh-CN.md)为准。

```text
reelnest/
├── README.md                     # 项目入口与当前状态
├── apps/
│   └── client/                   # 新 Flutter 客户端，一个应用工程
│       ├── lib/
│       │   ├── app/              # 启动、路由、依赖装配
│       │   ├── shell/            # 桌面与移动应用外壳
│       │   ├── features/         # 首页、资料库、播放、下载、设置等
│       │   └── platform/         # 系统能力接口与适配
│       ├── assets/               # 已提取的跨端资源
│       ├── test/
│       ├── integration_test/
│       ├── android/
│       ├── ios/
│       ├── windows/
│       ├── macos/
│       ├── linux/
│       └── pubspec.yaml          # Flutter 客户端版本来源
├── packages/                     # 随实际边界建立，不预先创建空包
│   ├── reelnest_domain/          # Dart 领域模型和纯业务规则
│   ├── reelnest_api/             # Mlink DTO、协议客户端、契约测试
│   ├── reelnest_storage/         # SQLite/Drift、迁移、缓存
│   ├── reelnest_player/          # 播放引擎接口与实现，不含业务页面
│   └── reelnest_ui/              # 设计参数和共享组件
├── contracts/
│   └── mlink-v1/                 # 从现有实现整理的契约与脱敏样例
├── tooling/                      # 新客户端的构建、版本校验、测试工具
├── docs/
│   ├── README.md                # 文档索引
│   ├── PROJECT_STRUCTURE.zh-CN.md
│   ├── GITHUB_REPOSITORY_PLAN.zh-CN.md
│   ├── FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md
│   ├── design/                  # 原版界面参考与交互说明，按需建立
│   └── decisions/               # 重要技术决策及原因
├── pubspec.yaml                 # 建立多个 Dart 包时启用 Pub workspace
├── pubspec.lock                 # workspace 的统一依赖锁
└── .github/
    ├── workflows/
    ├── ISSUE_TEMPLATE/
    ├── pull_request_template.md
    ├── CODEOWNERS
    └── dependabot.yml
```

目录树是目标布局，不表示本次已经创建 Flutter 工程。初期只有一个应用时，可先把模块放在应用内；确实需要独立依赖、独立测试时再提取为包。

多包阶段优先用 Dart 官方 Pub workspaces，统一解析依赖、提交根目录锁文件，不同时维护互相冲突的子包锁文件。暂不引入额外的仓库编排工具。[Pub workspaces 文档](https://dart.dev/tools/pub/workspaces)

新仓库独立维护 `.gitignore`，不直接照搬旧 MediaLib 的规则。建立 Flutter 工程时保留平台工程、资源、锁文件和数据库迁移文件；排除构建缓存、证书、真实媒体库和用户数据。`docs/` 与 `apps/client/assets/` 应正常纳入版本控制。

## 3. 分支、PR 与版本

| 项目 | 建议 |
|---|---|
| 默认分支 | 使用 `main`；应用工程建立后保持可以构建 |
| 日常开发 | 短期 `codex/<功能名>` 分支，通过 PR 合并 |
| 平台分支 | 不建立长期 `windows`、`ios`、`android` 分支 |
| 重构分支 | 不把整个重构积压到一个长期大分支，按模块合并 |
| 合并方式 | 优先 squash，合并后删除功能分支 |
| 维护分支 | 仅在确实需要同时维护旧版本时建立 `release/<版本线>` |
| Flutter 标签 | `client-v0.1.0-alpha.1`、`client-v0.1.0-beta.1` 等，与旧标签区分 |
| 旧版本发布 | 在旧 MediaLib 仓库保留现有版本与发布机制 |

Flutter 试验版从独立的 `0.x` 版本线开始，不直接覆盖旧 macOS `1.8.x` 的更新来源。五端同一客户端版本使用相同源提交；如果某端尚未达到验收标准，在发布说明中标为不提供或实验性，不能因为其他端通过就宣称五端正式支持。

新客户端以 `apps/client/pubspec.yaml` 的 `version` 为唯一客户端版本来源。标签与其语义版本必须一致。商店版本字符串、整数 build number 和预发布渠道由构建脚本显式映射并校验；构建号必须满足各商店的递增要求，不能把带 `alpha` 的字符串原样用于所有原生版本字段。

产品版本、Mlink API 版本、数据库 schema 版本分别管理。保持 API `v1` 兼容不意味着应用版本也必须相同。

## 4. GitHub 设置清单

以下为待落地配置，不代表已读取或修改远程设置。实施时先确认当前仓库可见性、账号套餐、已有规则和维护者名单。

| 设置 | 建议值或行为 |
|---|---|
| 仓库可见性 | 远程尚未创建；未来创建时默认建议私有 |
| Issues | 开启，按功能与平台记录问题 |
| Projects | 可选，一个重构看板即可 |
| 合并方式 | 开启 squash；按团队习惯关闭其他方式 |
| 默认 Actions 权限 | `contents: read`；发布 job 单独申请需要的写权限 |
| `main` 规则 | 禁止 force push 和删除，PR 合并、必需检查通过、讨论已解决 |
| 必需审查人数 | 单人维护不强制设置自己无法完成的审批；多人协作后建议 1 人 |
| 必需检查 | 在检查实际运行并稳定后添加，避免绑定尚不存在的检查名 |
| 标签规则 | 保护客户端发行标签，禁止随意重写已发布标签 |
| CODEOWNERS | 使用已确认的维护者账号，尤其覆盖工作流和发布脚本 |
| 自动更新依赖 | 按 Dart、GitHub Actions 等范围分组，发布 PR，验证后合并 |

建议标签：`area:ui`、`area:playback`、`area:library`、`area:api`、`area:storage`、`area:ci`，以及 `platform:windows/macos/ios/android/linux`、`type:bug/feature/refactor`。

PR 模板要求说明：用户可见变化、涉及平台、验证记录、界面截图、API/数据库兼容影响。UI PR 附原版与新版对照；播放 PR 附样本与设备信息。

## 5. CI 工作流规划

### 5.1 现有流水线

旧 MediaLib 仓库已有 `swift.yml` 和 `acceptance.yml`，覆盖 Swift 构建与测试、集成自检、真实网络传输、浏览器播放和 DMG 验证。它们继续保留在旧仓库；ReelNest 新仓库当前没有工作流。

旧流水线继续在旧仓库按现状执行。新仓库的真实接口验收可检出固定提交的旧服务端到临时目录独立构建，明确访问权限与网络条件；不要把旧仓库工作流名称当作新仓库已经存在的检查。

### 5.2 新增工作流及触发

| 拟议文件 | 触发 | 主要职责 |
|---|---|---|
| `client-checks.yml` | 每个 PR、`main` push、手动 | 格式、静态检查、单测、组件测试、契约测试、受影响平台构建、统一检查结果 |
| `client-acceptance.yml` | 定期、手动、候选版本 | 五端完整构建与可自动化验收，汇总真机待验项 |
| `client-release.yml` | `client-v*` 标签、受控手动触发 | 校验版本，测试指定提交，构建签名包，生成发行草稿 |

建立稳定的 `client-ci-gate` 检查作为 Flutter 合并门槛。所在 workflow 对 PR 总是触发，在 job 内判断受影响模块；汇总 job 使用总是执行的条件，逐项检查结果。只有明确不受影响的 job 可以跳过，预期任务失败、取消或意外跳过必须使门槛失败。

不能直接给必需 workflow 加文件路径过滤后就不管：GitHub 文档说明，被路径过滤跳过的 workflow 可能让必需检查一直 Pending。旧 Swift 检查继续由旧仓库管理；新仓库验收应显式执行所需服务端测试，不能把 `needs` 指向另一个仓库或普通 workflow 的 job。[GitHub workflow 语法](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)

变化影响规则：

- 纯文档变化：文档与引用检查，可跳过客户端编译。
- 共享 Dart 代码、资源、依赖锁、播放插件变化：五端编译检查。
- 单个平台工程变化：公共检查加对应平台编译。
- `contracts/` 或服务端基线版本变化：Dart 契约测试和真实连接验收；若需要修改旧 Swift API 或认证策略，在旧仓库配套提交并执行其测试。
- 播放、存储、原生插件变化：追加相应设备验收；编译成功不代表功能成功。

只有工程与检查实际就绪后才启用对应门槛。原型期允许阶段性支持表，但已声明支持的平台不能长期处于跳过状态。

### 5.3 构建环境与产物

| 目标端 | 构建主机 | PR 验证 | 候选/发行产物 |
|---|---|---|---|
| Windows | Windows runner | 编译、测试、启动冒烟 | 完整应用目录 ZIP；后续选择一种安装器 |
| macOS | macOS runner | 编译、测试、启动冒烟 | `.app` 的 ZIP / DMG；正式发行完成签名与公证 |
| iOS | macOS + Xcode | 模拟器构建或不签名设备构建 | 正确签名的 IPA，通过 TestFlight/商店等有效渠道分发 |
| Android | Linux runner + Android SDK/JDK | Debug APK 编译、模拟器测试 | 签名 APK、商店 AAB |
| Ubuntu | Linux runner + 桌面依赖 | 编译、可用显示环境下的冒烟 | 完整 bundle 的 tar.gz；再增加 `.deb` 或 AppImage |

Windows 不能只上传一个 exe，Linux 不能只上传单个可执行文件；随包附带实际需要的动态库、Flutter 资源和媒体运行库。安装包制作是 Flutter 编译之后的独立步骤。

GitHub Actions matrix 可以在不同操作系统上执行任务；Flutter 各端构建有宿主要求，iOS/macOS 仍需 macOS。[GitHub matrix](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/run-job-variations) · [Flutter 构建环境](https://docs.flutter.dev/install/custom)

初始架构建议：Windows x64、Ubuntu x64、macOS Apple Silicon、iOS arm64、Android arm64；Windows/Linux arm64、Intel Mac 和 Android 其他 ABI 单独列为待评估支持项。锁定 Flutter/播放器版本时核对架构兼容，不根据 runner 名称推断实际架构。macOS Intel 的支持需特别核对 Flutter 当前政策。[Flutter 平台矩阵](https://docs.flutter.dev/reference/supported-platforms)

### 5.4 工具链和成本

- 明确锁定 Flutter SDK、依赖锁文件、JDK、Xcode、Android SDK/NDK 和 runner 系统版本，记录可重复的安装方式。
- Actions 引用在落地时核验并固定到受信任提交；自动化工具定期提出升级 PR。
- 缓存键包含操作系统、CPU 架构、SDK 和锁文件摘要；不跨系统复用原生构建输出。
- PR 新提交取消旧运行；发布任务不被普通 PR 的并发分组取消。
- PR 产物建议保留 7 天，候选版验收记录建议保留 30 天，正式包使用 Releases。
- GPU、HDR、系统相册、后台音频和真实触控不能仅靠云 runner 验收；保留真机验证记录。
- 自托管设备仅用于受信任提交的专项验收，不让外部 PR 自动在带签名凭据的设备上执行。

## 6. 发布和凭据

发布步骤：

1. 从 `main` 的指定提交准备客户端版本与变更说明，验证平台支持清单。
2. 创建版本标签，流水线检验标签、应用版本、源提交和工具链一致。
3. 构建同一提交的各端产物，运行自动化检查，汇总真机验收结果。
4. 签名、macOS 公证、生成 SHA-256 校验清单与构建信息。
5. 先形成 GitHub Release 草稿或预发布版；按渠道发布，首期商店上传采用明确的手动触发。
6. 某平台失败时明确阻止该平台发行；不得悄悄拿旧包冒充同版本新产物。

发行文件使用明确名字，例如 `ReelNest-client-0.1.0-beta.1-windows-x64.zip`。同时记录客户端版本、构建号、Git SHA、平台/架构、工具链、API 兼容范围、包校验值和签名状态。重跑任务不能静默替换已正式发布的包。

GitHub Release 中的 IPA 并不等于任意 iPhone 都能直接安装；iOS 分发方式按签名和渠道确定。测试包与正式包应明确区分。

凭据按平台隔离，建议使用 `android-release`、`apple-release`、`windows-release` 等 GitHub Environments，限制发行分支/标签。具体可用的环境保护功能依赖仓库可见性和 GitHub 套餐，落地前确认；不可用时设计等价的受控发布流程。[GitHub Environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)

| 范围 | 所需内容 | 说明 |
|---|---|---|
| Android | 上传密钥、密码、alias；商店上传凭据（若启用） | 调试构建不接触正式密钥 |
| Apple | 签名身份、描述文件、团队标识、公证/商店 API 凭据 | macOS 与 iOS 的签名用途不同，按 job 最小授权 |
| Windows | 代码签名服务或证书配置（正式发行时） | 未签名试验包如实标注 |
| 普通 CI | 通常不需要产品账户或签名凭据 | 使用合成媒体、临时库和测试账号 |

凭据只存适合的 secret 存储，不提交到 Git，不在日志中打印，不加入构建缓存或普通 PR artifact。发行授权是 GitHub 权限配置问题，不应依靠客户端代码中的开关。

## 7. 配置落地顺序

| 步骤 | 交付 | 验收 |
|---|---|---|
| R0 | 本文与实施计划 | 仓库策略、范围、平台角色清楚 |
| R1 | 新客户端骨架、必要模块、忽略规则 | 新客户端可独立构建，旧 Swift 工程仍在原仓库维护 |
| R2 | PR 模板、Issue 模板、基础客户端 CI | 一个真实 PR 跑通检查，检查名稳定 |
| R3 | 五端编译、API 契约、平台适配原型 | 同一提交有明确的五端结果与阻塞记录 |
| R4 | GitHub ruleset / 分支保护 | 必需检查正确阻止失败合并，不造成文档 PR Pending |
| R5 | 预发布流水线和产物命名 | 无正式凭据时也可生成清楚标注的测试产物 |
| R6 | 签名、发布环境、正式渠道 | 可追溯产物在目标设备上安装和运行 |

R0 已由文档交付，其余未执行。不要先启用指向未来工作流的必需检查，也不要先为五个平台复制五份仓库。

## 8. 与重构计划的关系

后续功能阶段、API 复用边界、原版界面还原和测试策略见 [Flutter 实施计划](FLUTTER_IMPLEMENTATION_PLAN.zh-CN.md)。默认先迁移客户端，保留现有 macOS 服务端作为兼容基线；Windows/Ubuntu 独立服务器属于另一项交付，不能用“客户端支持 Linux”代替。

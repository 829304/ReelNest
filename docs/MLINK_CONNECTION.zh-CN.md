# Mlink 服务器连接与分类读取

更新：2026-10-04。状态：**已静态编写，未编译、未测试、未联调**。

## 本轮范围

实现一个 Mlink / MediaLIB Server 连接的“填写地址 → 发现服务 → 登录 → 保存会话 → 读取分类”流程。首页自动恢复已保存连接，服务器页提供重新登录、刷新和退出此设备，`/servers/library` 展示服务端返回的分类与数量。不会预置样例媒体冒充服务端数据。

本轮一次保存一个服务器账号。更换服务器或账号先退出此设备；多服务器列表与快捷切换留到后续。Emby、Jellyfin、Plex 的直接连接需要各自协议适配器，本轮不包含。后续浏览迭代已为分类卡片增加媒体条目入口，见[媒体浏览与详情](LIBRARY_BROWSING.zh-CN.md)；播放器、下载、离线索引和后台同步仍未实现。

## 源码依据与请求契约

参考 MediaLib 基线 `64f8ee258d87389414d5e06740a89f59cd857612`：`MlinkAPIClient.swift`、`ServerProtocolModels.swift`、`ServerAuthenticationHTTPHandler.swift` 和 `HTTPRequestSecurityPolicy.swift`。界面字段顺序及动作来自 `SourcesView.swift` 的远程来源配置，映射见 [SOURCE_MAPPING](design/SOURCE_MAPPING.md)。

| 请求 | 请求数据与鉴权 | 响应 |
|---|---|---|
| GET `/.well-known/mlink` | 无凭据；Accept: application/json | `serverID`、`serverName`、`apiVersion`、`capabilities` |
| POST `/api/v1/auth/login` | JSON：`username`、`password`、`deviceName`、`platform`、`delivery: token` | Bearer access / refresh token 及到期时间、会话和设备 ID |
| POST `/api/v1/auth/refresh` | JSON：`refreshToken`、`delivery: token` | 轮换后的完整 token 集合 |
| GET `/api/v1/library/categories` | Authorization: Bearer accessToken | `categories: [{id, title, itemCount}]`、`videoGroupItemCount` |

登录和刷新携带原项目约定的 `X-MediaLIB-Client: mlink-native/1` 与 JSON Content-Type。这个头是协议标记，产品仍使用 ReelNest 名称；设备名为 `ReelNest (平台)`。请求不依赖 Cookie，不把凭据拼进 URL，不记录请求正文、Authorization 或响应正文。

上述接口要求 HTTP 200。401 在登录阶段显示凭据错误，在分类阶段最多触发一次令牌刷新，在刷新阶段视为会话失效。403 显示权限不足，428 提示服务端初始化，429 提示稍后重试；网络、超时、TLS、响应格式及存储异常各自给出不含敏感数据的提示。不会自动重试登录或无限循环刷新。

每个网络请求总超时 10 秒，读取上限为解码后 1 MiB，拒绝自动跟随重定向。只接受 Mlink v1；响应校验字符串 UTF-8 字节长度、分类数量上限、重复分类 ID、非负整数计数、带时区的令牌时间和 Bearer 类型。`videoGroupItemCount` 单独保留，不将它解释为分类数量之和。能力列表保留为服务描述，当前依靠实际接口响应处理不支持的功能。

## 地址与凭据

只接受 HTTP / HTTPS origin，禁止嵌入账号密码。非回环地址强制 HTTPS，HTTP 仅允许 `localhost`、`127.0.0.1`、`::1`。保留默认 TLS 证书验证，不加入忽略证书的回调。手机上的 localhost 指向手机自身，不能用来代指开发电脑。

相较旧客户端自动剥离路径、查询参数和片段，本轮表单直接拒绝这些内容并提示填写 origin，避免用户误以为支持子路径反向代理。服务器应将 Mlink 端点暴露在 origin 根路径。

用户名去除首尾空白，上限 128 UTF-8 字节；密码保持原值，上限 1024 字节。提交后清空密码输入框，失败时重新输入；密码不进入存储和公开页面状态。会话资料使用版本为 1 的单个安全存储键，包含 origin、服务描述、用户名及令牌，不存媒体路径。

## 会话生命周期

1. 启动时读取安全存储。读取失败或记录损坏时显示恢复错误，允许重试或清除记录，不静默覆盖旧凭据。
2. 登录先发现服务，再发送密码。成功后保存令牌并回读确认，然后读取分类；保存失败时显示待保存状态，可以重试或退出。
3. 每次读取分类前重新发现服务并比较 serverID。地址返回不同服务器时停止发送已保存令牌，要求退出后重连。此比较用于发现服务配置变化，不代替 TLS 身份验证。
4. access token 距离到期不足 30 秒时先刷新。读请求收到 401 后进入串行的凭据处理阶段；若其它请求已轮换令牌则复用新值，否则刷新一次。重试仍收到 401 时要求重新登录。
5. 轮换后的 token 立即替换内存值，再写安全存储。写入失败时保留新值供重试保存，后续请求必须先完成保存，避免继续使用已经失效的 refresh token。若此时关闭应用，下一次可能需要重新登录。
6. 会话恢复、登录、令牌准备/刷新与存储清除在仓库中串行处理；浏览迭代将实际只读网络请求移出串行队列，让图片并发。请求带会话代次，在发送前与返回后检查，退出或换账号后的旧结果不可进入当前页面。页面销毁后不再更新其状态。
7. 分类刷新失败保留本次进程内上次成功结果并标注旧数据；会话失效或退出时移除分类。没有实现磁盘媒体缓存。
8. 退出立即清空内存凭据，然后删除该存储键并回读确认。删除失败时明确提示，阻止添加新连接，提供重新清除；不能声称本机已完全退出。若未成功删除就关闭应用，旧记录仍可能存在。

**退出是本机操作。** 原服务端虽有 `/api/v1/auth/logout`，但原生写操作白名单仅覆盖播放状态和用户媒体偏好，并未覆盖退出。本轮不伪造浏览器 Cookie / CSRF 流程；服务端会话撤销需后续扩展契约，现阶段由服务端会话管理完成。

## 代码边界

| 目录（相对 apps/client/lib） | 职责 |
|---|---|
| `domain/` | 纯 Dart 地址、连接资料、分类和错误模型，无 Flutter / 插件依赖 |
| `api/mlink/` | dart:io 网络请求、Mlink JSON 校验和 token 数据类型 |
| `storage/credential_store.dart` | 会话文档存储接口 |
| `platform/secure_credential_store.dart` | 系统安全存储插件适配，不提供明文降级 |
| `features/servers/data/` | 版本化存储文档、串行会话操作、自动刷新 |
| `features/servers/application/` | 公开连接状态、忙碌与恢复流程，不暴露令牌 |
| `features/servers/presentation/` | 登录表单、连接资料、重试及退出入口 |
| `features/library/presentation/` | 只读分类列表、空状态、旧数据提示 |
| `app/service_providers.dart` | 组装 API、平台存储与仓库，可替换存储适配器 |

没有提前拆成多包；未来 Emby 等实现可以沿协议边界扩展。当前分类状态由连接流程共同管理，分页条目浏览接入时再增加独立的库控制器。

## 依赖与平台配置

安全存储声明为 `flutter_secure_storage: ^11.2.0`，使用 [插件官方说明](https://pub.dev/packages/flutter_secure_storage) 中的原生存储能力。本轮没有运行 pub get，锁文件和插件生成文件仍是初始化版本。恢复验证时需解析依赖、审阅锁文件与生成变更，再运行现有 CI。不要手工编写生成注册代码。

| 平台 | 已写入的配置 | 仍需验证 |
|---|---|---|
| Windows | 使用插件默认适配器 | VS 的 C++ ATL 组件、当前用户凭据读写及重启恢复 |
| macOS | Debug/Profile 与 Release 开启 network.client；本地网络用途说明；使用不共享的传统 Keychain | 签名后钥匙串提示、保存及删除、局域网权限 |
| iOS | Runner.entitlements 的 keychain-access-groups；三个构建配置均引用；本地网络用途说明 | 实机签名、Keychain、系统网络授权 |
| Android | INTERNET；最低 SDK 至少 23 且不降低 Flutter 要求；禁用备份并排除云备份/设备迁移数据 | KeyStore 读写、重启恢复与系统版本差异 |
| Ubuntu | 构建工作流加入 libsecret-1-dev | 打包声明 libsecret-1-0，桌面用户会话中的 Secret Service / 钥匙串可用性 |

macOS 按插件的非共享 Keychain 方案设置 `usesDataProtectionKeychain: false`，未增加跨应用共享组。Android 备份排除同时涵盖旧版与 Android 12+ 格式，依据 [Android 备份文档](https://developer.android.com/identity/data/autobackup)。当前未启用全局明文网络或关闭 TLS 校验，也未安装任何本机工具链组件。

## 后续验收清单（本轮均未执行）

- 解析依赖并更新 lock；格式化、分析及现有组件测试；随后在支持符号链接的文件系统验证原生插件构建。
- 使用可控的 Mlink 服务验证正确登录、错误密码、服务初始化未完成、被限流和账号权限不足。
- 地址覆盖 HTTPS、端口、IPv6 回环、非回环 HTTP 拒绝、嵌入凭据/路径拒绝、重定向拒绝和无效证书。
- 响应覆盖字段缺失、未知 API 版本、畸形 JSON、重复分类 ID、负数量及超大/缓慢响应。
- 验证重启恢复、即将过期的 token、401 后刷新、新令牌再次 401、refresh 过期或撤销。
- 验证 token 已轮换但写存储失败后的重试，退出删除失败，以及网络操作和退出的先后顺序。
- 验证安全存储不可用、记录损坏、服务器 ID 改变，以及失败时不泄露凭据。
- 验证空分类、零条目分类、刷新失败保留旧结果、退出清空结果，以及窄屏/大字号/键盘下的表单布局。
- 分别验收五个平台的真实安全存储与网络权限；无签名构建通过不能代替 iOS 实机 Keychain 验收。

分类下分页和详情已在后续静态迭代接入，详见[媒体浏览与详情](LIBRARY_BROWSING.zh-CN.md)。本文件的连接验收待办仍未执行。

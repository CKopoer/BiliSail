# 参考项目、证据与采用边界

检查日期：2026-10-05。两个参考项目只读查看，未修改它们。设计阶段未调用真实接口；随后实现首版时已进行游客公开 API 和 Windows 媒体烟测，结果见 [实测记录](validation/m0-results.md)。以下路径按三个仓库在同一父目录下给出；在其他机器上可按仓库名、提交和相对路径定位。

## 1. 来源快照

| 项目 | 本地提交 | 观察 |
| --- | --- | --- |
| bili-lite（现名 BiliSail） | 本次交付时尚无提交 | 已从设计阶段初始化为 Flutter 0.1.0 Windows 预览工程；源码版本以本地交付文件为准 |
| biliuwp-lite | `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` | C#/UWP 客户端，Views/ViewModels/Services 与播放器等模块 |
| bili-kernel | `e26f6dbd071e20d4220806fcff7bd675f3c29fc5` | C#/.NET API 包装，抽象、服务、鉴权、解析器、Protobuf |

用户提供的“跨平台框架比较”对话作为需求背景：采用 Flutter，并关注 Android/Windows/macOS、视频/直播/弹幕与 Rust 可扩展性。对话中的星级评价和性能概括不作为基准数据；本方案对关键依赖另外查阅维护方资料，并安排实测。

## 2. UWP → Flutter 的映射

2026-10-07 评论 IP 属地只读参考 [CommentApi.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/CommentApi.cs)、[CommentItem.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Comment/CommentItem.cs) 和 [CommentReplyControlModel.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Comment/CommentReplyControlModel.cs) 的 `reply_control.location` 字段。仅借鉴协议语义，未复制源码、样式或资源；Flutter 展示沿用当前日期行的文字样式，结果与在线验证边界见 [评论验证](validation/video-comments.md#评论-ip-属地2026-10-07)。

| 已查看入口 | 借鉴点 | Flutter 落点/调整 |
| --- | --- | --- |
| [App.xaml.cs](../../biliuwp-lite/src/BiliLite.UWP/App.xaml.cs) | 启动、服务注册、窗口/会话初始化 | `app/bootstrap` + Provider 组合根；避免任意访问静态 ServiceProvider |
| [RegisterServiceExtensions](../../biliuwp-lite/src/BiliLite.UWP/Extensions/RegisterServiceExtensions.cs) | 服务生命周期区分 | 显式 Provider 作用域，注入构造器，取消/释放受所有权约束 |
| [MainPageViewModel](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Common/MainPageViewModel.cs)、[ViewModels](../../biliuwp-lite/src/BiliLite.UWP/ViewModels) | 导航/设置与 Home/Search/Video/Live 等功能分组 | 自适应 AppShell + feature 目录，保留产品能力而非 XAML 布局 |
| [MainPage.xaml](../../biliuwp-lite/src/BiliLite.UWP/MainPage.xaml)、[HomePage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/HomePage.xaml)、[DefaultHomeNavItems](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Home/DefaultHomeNavItems.cs) | 本轮多标签条、顶部频道、搜索及账号工具位置；本机已安装 UWP 的推荐/热门页也已实际查看 | Dart 工作区状态和自有 Flutter 控件；仅参考布局与交互，不复制 XAML、图标字体或图片 |
| [IBiliPlayer](../../biliuwp-lite/src/BiliLite.UWP/Player/IBiliPlayer.cs) | 播放控制、事件、单文件/分离媒体形态 | `PlayerEngine` + `ResolvedMediaSource` + `PlaybackSnapshot` |
| [BasePlayerController](../../biliuwp-lite/src/BiliLite.UWP/Player/Controllers/BasePlayerController.cs)、[States](../../biliuwp-lite/src/BiliLite.UWP/Player/States) | 播放/暂停/屏幕状态分离 | 明确播放状态机和正交字段，统一管理资源 |
| [ISubPlayer](../../biliuwp-lite/src/BiliLite.UWP/Player/SubPlayers/ISubPlayer.cs)、[WebPlayer](../../biliuwp-lite/src/BiliLite.UWP/Player/WebPlayer) | 后端差异隔离、多种直播格式 | `MediaKitEngine`；WebView 不是本项目默认播放路径 |
| [IDanmakuController](../../biliuwp-lite/src/BiliLite.UWP/Services/Interfaces/IDanmakuController.cs) | 弹幕设置、显示模式、独立控制器 | 与播放器无库级耦合的 DanmakuController |
| [弹幕设置](../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/VideoDanmakuSettingsControl.xaml)、[播放器滑条](../../biliuwp-lite/src/BiliLite.UWP/Controls/PlayerControl.xaml) | 顶部距离默认 0、播放器范围 0–200／步长 4、顶部边距语义 | 独立实现设置保存与点播／直播轨道区域计算；未复制源码或资源，见 [顶部距离验证](validation/danmaku-top-margin.md) |
| [FrostMasterDanmakuController](../../biliuwp-lite/src/BiliLite.UWP/Services/FrostMasterDanmakuController.cs) | Canvas 动画与弹幕绘制适配 | Flutter Canvas/TextPainter，不依赖 Win2D/Windows.UI 类型 |
| [IDownloadService](../../biliuwp-lite/src/BiliLite.UWP/Services/Interfaces/IDownloadService.cs)、[DownloadService](../../biliuwp-lite/src/BiliLite.UWP/Services/DownloadService.cs) | 下载、暂停恢复、索引和文件 | 独立任务状态机与存储，下载服务不直接维护页面 ViewModel |
| [WbiKeyService](../../biliuwp-lite/src/BiliLite.UWP/Services/WbiKeyService.cs) | WBI key 获取与缓存 | API 层 WbiKeyProvider，新增单飞与重签预算 |
| [AccountApi](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/AccountApi.cs) | Web/TV 二维码、Cookie 刷新入口 | MVP Web auth profile；其他方式按能力单独接入 |
| [WindowSizeService](../../biliuwp-lite/src/BiliLite.UWP/Services/WindowSizeService.cs)、[IWindowSizeProvider](../../biliuwp-lite/src/BiliLite.UWP/Services/Interfaces/IWindowSizeProvider.cs) | 窗口能力接口化 | PlatformServices + 桌面适配，移动有合理无操作实现 |

本轮播放控件、视频动态与设置另参考 [DynamicPageViewModel](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Home/DynamicPageViewModel.cs)、[播放设置](../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/PlaySettingsControl.xaml)、[弹幕设置](../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/VideoDanmakuSettingsControl.xaml)，并实际查看本机安装的 UWP 视频动态/播放界面和官方桌面端直播列表。只借鉴信息层次与交互，自行实现 Flutter 控件；来源与端点验证见 [本轮记录](validation/ui-controls.md)。

这是针对具体入口的架构映射，不是全仓库代码审计。UWP 的 Windows Runtime、Win2D、WebView 播放桥接、后台下载和注册方式需要重做平台适配；成熟功能范围不等于接口都仍然在线可用。

播放页双标签与评论本轮另外实际查看官方桌面“哔哩哔哩”客户端的示例视频，参考简介内图标操作、嵌套合集和同侧栏楼中楼详情；这一轮的视觉参考不是 UWP。评论协议定位使用 [CommentAPI.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/CommentAPI.cs) 的 Comment／Reply／Like／ReplyComment，合集使用视频详情响应的 `ugc_season`。只采用协议字段和交互职责，未复制 C#、图片、字体或其他资源；没有扩大未明确的许可范围。结果见 [播放页与评论交互](validation/video-comments.md)。

## 3. bili-kernel → Dart 的映射

影视/直播内置播放本轮另外查看本机 UWP 番剧首页与影视选集界面，以及 `SeasonDetailPage.xaml`、`SeasonAPI.cs`、`LiveDetailPage.xaml`、`LiveRoomAPI.cs`。只借鉴交互职责和协议字段，未复制 C#、schema、图片或新增资源；不增加相邻仓库运行时依赖。实际采用与端点验证见 [影视与直播内置播放](validation/content-playback.md)。

后续影视侧栏以用户指定的 **官方桌面“哔哩哔哩”** 为视觉参考，已实际查看其“名侦探柯南（中配）”播放页；这是对前序 UWP 影视布局的调整。直播 SC 仅参考相邻 `LiveRoomAPI.RoomSuperChat`、`LiveRoomViewModel.LoadSuperChat` 和 `LiveRoomSuperChatModel` 的协议字段，自行实现 Web 读取与 Flutter 交互，不复制 App 签名或参考代码。结果见 [影视侧栏与直播 SC](validation/pgc-live-sidebar.md)。

首页悬浮刷新与回顶部本轮参考用户提供的本机客户端截图；图片缓存与状态保留另外只读查看 [PerformanceSettingsControl.xaml](../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/PerformanceSettingsControl.xaml)、[RecommendPage.xaml.cs](../../biliuwp-lite/src/BiliLite.UWP/Pages/Home/RecommendPage.xaml.cs) 和 [DynamicPage.xaml.cs](../../biliuwp-lite/src/BiliLite.UWP/Pages/Home/DynamicPage.xaml.cs)。自行编写 Flutter/Dart 控件、滚动检查和有界图片缓存，不复制参考实现或新增图片资源；本轮未操作已安装客户端实机验收，详见 [首页刷新、自动分页与图片缓存](validation/feed-scroll-image-cache.md)。

2026-10-06 视频封面缩略图另只读参考 [ImageCompressionConvert.cs](../../biliuwp-lite/src/BiliLite.UWP/Converters/ImageCompressionConvert.cs)、[RecommendPage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/Home/RecommendPage.xaml) 的 `200h` 和 [VideoListView.xaml](../../biliuwp-lite/src/BiliLite.UWP/Controls/VideoListView.xaml) 的 `140w`。仅借鉴给原地址追加 CDN 尺寸参数、保留已有处理地址的规则，复用本项目既有 WebP 缩略图生成器，独立实现随显示尺寸/屏幕缩放选择档位；没有采用参考源码或资源，不扩大许可范围。实际传输对比与验证见 [图片缓存记录](validation/feed-scroll-image-cache.md#视频封面-cdn-缩略图)。

用户空间另参考本机 **哔哩哔哩 UWP 4.8.18.0** 的个人中心、关注列表和 UP 主主页，以及 [UserInfoPage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/UserInfoPage.xaml)、[UserDetailAPI.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/UserDetailAPI.cs)、[UserDetailViewModel.cs](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/User/UserDetailViewModel.cs)。本轮仅参考交互和协议字段，自行编写 Flutter/Dart；不新增资源复制或相邻仓库运行时依赖。结果见 [用户主页验证](validation/user-profile.md)。

| 已查看入口 | 借鉴点 | Flutter/Dart 落点 |
| --- | --- | --- |
| [README](../../bili-kernel/README.md)、[BiliService 示例](../../bili-kernel/src/Samples/Bili.Console/BiliService.cs) | 可组合的 API 服务 | `bili_api` 的模块化 clients，按阶段引入 |
| [BiliApis](../../bili-kernel/src/BiliKernel.Abstractions/Bili/BiliApis.cs) | 接口族与路径集中管理 | EndpointSpec，补齐 method/profile/auth/retry/response 格式 |
| [BiliHttpClient](../../bili-kernel/src/BiliKernel.Core/Http/BiliHttpClient.cs) | HTTP/Protobuf 传输边界 | 可注入 transport，系统 TLS，完整 framing 验证 |
| [BiliAuthenticator](../../bili-kernel/src/BiliKernel.Core/Authenticator/BiliAuthenticator.cs)、[执行设置](../../bili-kernel/src/BiliKernel.Core/Authenticator/BiliAuthorizeExecutionSettings.cs) | Cookie/token/CSRF/签名策略分离 | ApiProfile + 会话快照，按端点鉴权 |
| [TV AuthorizeClient](../../bili-kernel/src/Authorizers/Authorizers.Tv/Core/TvAuthorizeClient.cs) | 授权生命周期和取消 | AuthRepository；MVP 改为 Web QR，TV 实现只作参考 |
| [Resolvers](../../bili-kernel/src/Resolvers) | 凭据存储接口可替换 | CredentialStore；实际使用系统安全存储 |
| [PlayerService](../../bili-kernel/src/Services/Services.Media/PlayerService.cs)、[PlayerClient](../../bili-kernel/src/Services/Services.Media/Core/PlayerClient.cs) | 详情/播放/PGC/直播源、操作、消息分离 | 对应各 Client，PlaybackResolver 统一源模型 |
| [DashMediaInformation](../../bili-kernel/src/BiliKernel.Abstractions/Models/Media/DashMediaInformation.cs)、[LiveMediaInformation](../../bili-kernel/src/BiliKernel.Abstractions/Models/Media/LiveMediaInformation.cs) | 点播音视频轨道与直播线路不同模型 | DashPairSource / LiveSource，不都压成一个 URL |
| [DanmakuClient](../../bili-kernel/src/Services/Services.Media/Core/DanmakuClient.cs)、[dm v1.proto](../../bili-kernel/src/BiliKernel.Grpc/bilibili/community/service/dm/v1.proto) | 元信息、分段与 Protobuf 消息 | 有界分页/解码，协议 fixture；采用 schema 前记录来源 |
| [SubtitleClient](../../bili-kernel/src/Services/Services.Media/Core/SubtitleClient.cs) | 字幕索引与内容分开获取 | 字幕 metadata/cue 分离 |
| [VideoDiscoveryClient](../../bili-kernel/src/Services/Services.Media/Core/VideoDiscoveryClient.cs)、[SearchClient](../../bili-kernel/src/Services/Services.Search/Core/SearchClient.cs) | 分类/推荐/排行/搜索及不同分页 | Catalog/Search Repository，保留 cursor 语义 |
| [FavoriteService](../../bili-kernel/src/Services/Services.User/FavoriteService.cs)、[MyClient](../../bili-kernel/src/Services/Services.User/Core/MyClient.cs)、[ViewHistoryClient](../../bili-kernel/src/Services/Services.User/Core/ViewHistoryClient.cs) | 用户资产与历史 API 定位 | LibraryRepository，scope 隔离、云/本地进度合并 |

### 不能照搬的具体实现

- `BiliHttpClient` 构造中存在无条件接受证书的回调：本项目保持系统证书验证。
- `BiliHttpClient.CreateRequest(Uri, IMessage)` 把消息长度写入单个 byte：本项目如接 gRPC 要支持完整 32 位长度及标准状态/压缩处理。
- `PlayerClient.GetLiveSocketMessagesAsync` 单次读取固定 4096 字节缓冲并传给解析器：本项目按 message/packet 实际长度处理，验证合包、分片和解压边界。
- `PlayerService.GetVideoPageDetailAsync` 捕获广义异常后改走 REST：本项目仅对已分类的兼容性故障启用登记过的降级，取消、权限、风控不进入此路径。
- NativeCookies/NativeToken resolver 中的 `cookie.json`、`token.json` 示例存储：本项目凭据进入安全存储，不放工作目录或普通配置文件。

以上来自当前快照的实现细节，用来约束迁移；不据此推断整个参考项目的安全性或当前维护状态。

## 4. 许可与来源记录

2026-10-06 登录扩展另只读查看 K 的 BiliApis/TVAuthorizeClient，以及 U 的 AccountApi、LoginVM、LoginDialog 和 bili_gt.html。K 当前快照只有密码／App 登录常量，没有完整密码／短信客户端；U 有对应 App 协议与交互。最终采用内嵌官网登录页，独立编写 Flutter 适配和安全会话接入；未复制参考源码、22/33 图片或 gt.js，未把 App/TV token 混入 Web 会话。依赖、来源链接和验证边界见 [登录验证](validation/password-sms-login.md)。

用户后续指定的 [dart_simple_live dev](https://github.com/xiaoyaocz/dart_simple_live/tree/dev)，本轮固定提交 `bccd2ba2e77bc34b3e3a0897f1cb5e0b402afd2b`，仅只读参考移动端完整网页登录与 Cookie 获取职责，未复制其 GPL-3.0 源码或资源。其网页登录入口只对 Android/iOS 开放，桌面使用扫码／手动 Cookie；不能由此推导 Windows 密码／短信已提供。源码链接与对比见 [登录验证](validation/password-sms-login.md)。

本地 `bili-kernel` 根 [LICENSE](../../bili-kernel/LICENSE) 是 GPL-3.0 文本，但已查看的多个 C# 文件头写 MIT，存在需要厘清的来源信息。本地 `biliuwp-lite` 用 `rg --files` 搜索未找到 LICENSE 命名文件，这不等于可随意复制其代码或资源。

初始实现参考职责、协议入口和 UWP 实际界面，自行编写 Dart，没有复制 C# 或 Protobuf 文件。本轮按用户明确要求采用 `biliuwp-lite` 的业务图标字体、等级/认证图片和启动图标；具体来源、哈希和生成方法见 [资源清单](../assets/README.md)。2026-10-07 启动图标已替换为按 BiliSail 名称设计的小电视与船帆角标，当前采用第二轮 C 版；官网视觉参考、保留方案和提示词见 [品牌资源说明](../assets/branding/README.md)，业务图标的既有来源不变。本地参考仓库未找到明确覆盖这些资源的 LICENSE，本机预览采用不代表上游已授权开源或再分发。弹幕使用按公开 wire 字段编写的最小有界解析器，来源见 [API 验证记录](validation/api-endpoints.md)。测试媒体由本机 FFmpeg 的合成信号生成。依赖与原生来源见 [第三方说明](../THIRD_PARTY_NOTICES.md)；项目自己的最终开源许可证留待采用范围明确后决定。

### CI/CD 补充参考（2026-10-06）

本轮只读查看 `biliuwp-lite` 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [release.yml](../../biliuwp-lite/.github/workflows/release.yml)、[choco.yml](../../biliuwp-lite/.github/workflows/choco.yml) 和 [release-drafter.yml](../../biliuwp-lite/.github/release-drafter.yml)。仅借鉴手动选平台、打包、Release 草稿与产物上传职责，独立编写 Flutter/Dart 构建配置；未复制上游工作流代码、私有下载地址或凭据，未修改相邻仓库。采用范围沿用本节许可限制；新的 MSIX manifest 按 Microsoft 公开 schema 独立编写，工具与验证见 [CI/CD 与 MSIX](validation/ci-cd.md)。

### 快捷键和富评论补充参考

实际查看已安装的哔哩哔哩 UWP **4.8.18.0** 快捷键设置和评论区。对应源码为 [默认快捷键](../../biliuwp-lite/src/BiliLite.UWP/Models/Functions/BaseShortcutFunction.cs)、[快捷键设置](../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/ShortcutKeySettingsControl.xaml)、[评论成员模型](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Comment/CommentMemberModel.cs)、[表情 API](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/EmoteApi.cs) 和 [表情模型](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/EmoteViewModel.cs)。前文中“未复制图标/图片”的描述属于各历史阶段；当前采用范围以资源清单为准。功能验证见 [快捷键与富评论](validation/shortcuts-rich-comments.md)。

### 评论装扮与共享图片预览补充参考

评论图片与作者装扮本轮另对照用户提供的 UWP 评论截图，并只读查看 `CommentControl.xaml`、`CommentMemberModel.cs`、`CommentMemberUserSailingCardbgModel.cs`、`CommentMemberUserSailingCardbgFanModel.cs` 和 `ColorConvert.cs`。借鉴 `user_sailing.cardbg` 的右侧图片与 `NO.` 粉丝编号职责，独立实现 Flutter／Dart，没有复制新的源码、字体或图片；来源链接、复用边界和验证见 [评论图片与作者装扮](validation/comment-images-decorations.md)。

### 主页卡片与富动态补充参考

本轮对照用户提供的投稿截图，实际查看本机 UWP 的 UP 主投稿和空间动态页，并阅读 [UserInfoPage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/UserInfoPage.xaml)、[DynamicItemV2Control.xaml](../../biliuwp-lite/src/BiliLite.UWP/Controls/Dynamic/DynamicItemV2Control.xaml)、[DynamicV2Template.xaml](../../biliuwp-lite/src/BiliLite.UWP/Controls/Dynamic/DynamicV2Template.xaml)、[DynamicV2ItemViewModel.cs](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/UserDynamic/DynamicV2ItemViewModel.cs) 和 [DynamicParseExtensions.cs](../../biliuwp-lite/src/BiliLite.UWP/Extensions/DynamicParseExtensions.cs)。参考横向封面/元信息布局、作者与发布时间层次、图文与转发的组合方式，使用现有 Web 动态端点返回的富文本与媒体字段独立实现 Flutter 组件。本轮未复制新的上游代码、图片或字体，未修改相邻仓库；远端表情按响应中的图片地址加载，不打包上游表情资源。验证见 [主页卡片与富动态](validation/profile-dynamic-style.md)。

### 用户页顶部与固定倍速补充参考

用户页顶部与倍速本轮继续对照本机 UWP 及 [UserInfoPage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/UserInfoPage.xaml)、[组合工具栏](../../biliuwp-lite/src/BiliLite.UWP/Controls/PlayerControlToolBarWithComboBox.xaml.cs)、[滑块工具栏](../../biliuwp-lite/src/BiliLite.UWP/Controls/PlayerControlToolBarWithSlider.xaml.cs)。借鉴信息排列及按可选倍速索引加减的语义，独立实现 Flutter；没有新增上游资源复制或相邻运行时依赖。普通标签继续播放是本项目本轮行为调整，依据现有单会话契约与回归验证，见 [用户页、倍速与标签播放](validation/profile-playback-rates.md)。

视频编解码设置另只读参考 [UWP 播放设置](../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/PlaySettingsControl.xaml) 的优先视频编码与后端选项，独立实现 Flutter/Dart。当前后端是 media_kit/libmpv，因此未采用 Microsoft Store 编码扩展提示、FFmpegInteropX 参数或 Web 播放器选项；没有复制新的上游代码/资源或修改相邻仓库。固定 SDK 核对、选择规则与本机六组原生样片验证见 [视频编解码设置](validation/video-codec-settings.md)。

### 直播表情与主页入口补充参考

本轮按用户要求只读参考 [LiveDetailPage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml)、[LiveDetailPage.xaml.cs](../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml.cs)、[LiveMessage.cs](../../biliuwp-lite/src/BiliLite.UWP/Modules/Live/LiveMessage.cs)、[LiveRoomHistoryDanmu.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveRoomHistoryDanmu.cs) 和 [LiveMessageHandleActionsMap.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveMessageHandleActionsMap.cs)，借鉴表情元数据、观看人数事件和基于 UID 的主页入口。独立实现 Dart/Flutter，远端表情按协议中的 URL 加载，不打包上游表情或复制源码；结果见 [直播表情与主页入口](validation/live-chat-profiles.md)。

### 视频标签补充参考（2026-10-06）

只读查看 `biliuwp-lite` 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [视频详情 XAML](../../biliuwp-lite/src/BiliLite.UWP/Pages/VideoDetailPage.xaml)、[标签点击处理](../../biliuwp-lite/src/BiliLite.UWP/Pages/VideoDetailPage.xaml.cs)、[详情 ViewModel](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Video/VideoDetailPageViewModel.cs) 和 [VideoAPI](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/VideoAPI.cs)。借鉴标签列表与按名称搜索的交互及 Web 端点，独立编写 Dart／Flutter，没有复制新源码或资源，采用范围沿用第 4 节许可限制。协议与验证见 [视频标签与搜索](validation/video-tags.md)。

## 5. 外部一手资料

### 账号菜单与消息补充参考

本轮对照用户提供的头像菜单截图，读取 [HomePage.xaml](../../biliuwp-lite/src/BiliLite.UWP/Pages/HomePage.xaml)、[MessageApi.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/MessageApi.cs)、[MessagesPage.xaml.cs](../../biliuwp-lite/src/BiliLite.UWP/Pages/MessagesPage.xaml.cs)、[BiliMessageSession.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Msg/BiliMessageSession.cs)、[BiliSessionPrivateMessage.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Msg/BiliSessionPrivateMessage.cs)，以及内核的 [MessageService.cs](../../bili-kernel/src/Services/Services.User/MessageService.cs) 和 [MyClient.cs](../../bili-kernel/src/Services/Services.User/Core/MyClient.cs)。参考菜单信息、导航职责和 Web 会话/私信、未读、回复/@/点赞的协议字段；两仓库仍采用前文登记的提交快照。系统通知的独立 host/path 和字段另参考 [BiliChrome API 源码](https://github.com/EZ118/BiliChrome/blob/main/js/api/index.js)，并用本机已有 Web 会话只读验证。本轮独立编写 Dart/Flutter，没有新增复制上游代码、schema 或资源，也没有修改相邻仓库。许可范围沿用第 4 节限制，实际采用与验证见 [账号菜单与消息](validation/account-messages.md)。

### 自建收藏夹编辑补充参考

自建收藏夹卡片按用户补充截图显示内容数、私密锁和创建日期，编辑交互与 `folder/edit` 参数只读参考 [EditFavFolderDialog.xaml](../../biliuwp-lite/src/BiliLite.UWP/Controls/Dialogs/EditFavFolderDialog.xaml)、[EditFavFolderDialog.xaml.cs](../../biliuwp-lite/src/BiliLite.UWP/Controls/Dialogs/EditFavFolderDialog.xaml.cs) 和 [FavoriteAPI.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FavoriteAPI.cs)。独立实现 Dart/Flutter，只参考职责与协议；没有复制新增源码/schema/资源、修改相邻仓库或增加运行时依赖。采用范围沿用第 4 节，线上只读与模拟写入的区别见 [收藏验证](validation/favorites-tabs.md)。

### 七类搜索补充参考

搜索页面按用户提供的官方 B 站截图调整分类栏、排序工具条、UP 主预览与视频卡片。协议只读参考 [SearchAPI.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/SearchAPI.cs)、[SearchVideoViewModel.cs](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Search/SearchVideoViewModel.cs)、[SearchArticleViewModel.cs](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Search/SearchArticleViewModel.cs)、[SearchUserViewModel.cs](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Search/SearchUserViewModel.cs)、[SearchClient.cs](../../bili-kernel/src/Services/Services.Search/Core/SearchClient.cs) 和 [BiliApis.cs](../../bili-kernel/src/BiliKernel.Abstractions/Bili/BiliApis.cs)。只采用端点、字段和交互职责，独立编写 Dart/Flutter；未新增复制上游源码、schema 或资源，未修改相邻仓库。现有等级/UP 图标沿用已登记资源。接口返回与综合排序差异通过游客只读烟测验证，见 [搜索分类与排序](validation/search-categories.md)。

### 视频卡菜单与稍后再看计数补充参考（2026-10-06）

标题右侧竖三点与入口范围按用户截图实现。只读参考 [RecommendPageViewModel.cs](../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Home/RecommendPageViewModel.cs)、[WatchLaterAPI.cs](../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/WatchLaterAPI.cs) 和 [ViewLaterClient.cs](../../bili-kernel/src/Services/Services.User/Core/ViewLaterClient.cs) 的操作职责、删除 `aid` 参数与响应统计模型。UWP 推荐反馈使用 App 鉴权，因此实际 Web 反馈另核对 [官网首页脚本](https://s1.hdslb.com/bfs/static/shanks/laputa-home/assets/index-12fc55c2.js) 中的 `feedback/dislike` 表单和内容不感兴趣 `reason_id=1`，删除仍使用 `toview/del` 的 `aid`。独立编写 Dart/Flutter，没有复制上游源码、schema 或资源，也未修改相邻仓库；查阅公开脚本不等于真实账号写入成功。协议与验证边界见 [视频卡操作菜单](validation/video-card-menus.md) 和 [共享视频卡片](validation/shared-video-cards.md)。

下列资料在 2026-10-05 查阅，支撑选型与接口可能性；依赖与平台范围可能改变，以 M0 锁定版本及实测为准。

| 来源 | 本次用途 |
| --- | --- |
| [Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations) | UI/数据分离、Repository、ViewModel 与依赖注入的依据 |
| [Flutter 平台支持](https://docs.flutter.dev/reference/supported-platforms) | 初始 OS/ABI 范围；避免只用插件声明推断平台下限 |
| [Flutter video_player 教程](https://docs.flutter.dev/cookbook/plugins/play-video) | 确认单用官方默认插件不足以覆盖 Windows 方案 |
| [media_kit](https://pub.dev/packages/media_kit) | 平台、音轨、headers、字幕和初始化/释放接口 |
| [fvp](https://pub.dev/packages/fvp) | libmdk 后端和替代播放器可行性 |
| [Riverpod 生命周期](https://riverpod.dev/docs/concepts2/auto_dispose) | 自动释放与取消/所有权设计 |
| [Dio](https://pub.dev/packages/dio) | HTTP、拦截器、取消和配置能力 |
| [Drift 平台支持](https://drift.simonbinder.eu/platforms/) | 本地 SQLite 跨平台方案 |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 系统凭据存储选型与平台接入要求 |
| [flutter_rust_bridge 平台说明](https://cjycode.com/flutter_rust_bridge/guides/cross-platform/overview) | Rust 扩展可行性，不作为提前引入的理由 |

## 6. 尚待实测或决定的事项

2026-10-07 下载能力另只读查看 U 的 `Controls/Dialogs/DownloadDialog.xaml.cs`、`ViewModels/Download/DownloadDialogViewModel.cs`、`Services/DownloadService.cs`、`Services/BackgroundDownloadService.cs` 与 `Models/Download/*`，以及 K 的 `Services/Services.Media/Core/PlayerClient.cs`。仅借鉴端点、分轨、选集、队列和附属文件职责，独立编写 Dart/Flutter；不参考下载 XAML 样式、不新增源码/资源复制、不修改相邻仓库。采用范围和验证见 [下载方案](downloads.md)。

1. Web QR 与实际取得的 Cookie/refresh 信息是否满足 MVP 端点，游客可用范围如何。
2. media_kit 分轨路径、外部音轨 headers、原生库版本及三端硬解/生命周期；失败时 fvp 的对照结果。
3. HLS/HTTP-FLV 在目标设备上的稳定性、可用 codec、直播消息压缩版本。
4. 最低 OS、实际设备基线、Flutter/插件组合、包体积与发布方式。
5. 弹幕渲染预算是否达标，是否需要第三方 painter 或 Rust 的纯计算模块。
6. 参考实现/schema 的具体采用许可、项目最终许可证、native binary notices。

这些事项已有 M0/M4 的决策出口。Windows 的已测子项见实测记录；其余仍不应被描述成已验证事实。

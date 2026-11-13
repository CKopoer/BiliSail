# BiliSail（哔帆）设计文档

2026-11-12：已移除 fvp／MDK，当前仅使用 media_kit。历史文档中的双后端实现、SDK、命令及测试记录保留当时事实，不再作为现行入口；清理与设置兼容见[移除记录](validation/fvp-removal-2026-11-12.md)。

设计与实现日期：2026-10-05。状态：已创建 0.1.0 Windows 预览工程；完整设计仍是后续路线，当前能力与验证边界见 [M0 实测记录](validation/m0-results.md) 和 [根 README](../README.md)。

本项目采用 **Flutter + Dart 构建客户端，独立 API 包承接 Bilibili 协议，播放器与弹幕各自封装，Rust 按证据引入**。首批目标为 Android、Windows、macOS；参考 `biliuwp-lite` 的客户端能力和 `bili-kernel` 的 API 分层。

## 阅读顺序

| 文档 | 内容 |
| --- | --- |
| [iOS 播放期间闪退](validation/ios-video-playback-crash-2026-11-13.md) | 输出帧失败退出、Apple 渲染队列与销毁屏障、用户日志/PiliPlus 对照、受控回归及 SDK/实机边界 |
| [移除 fvp 播放后端](validation/fvp-removal-2026-11-12.md) | 统一 media_kit、旧设置回退、原生／依赖／脚本清理及验证边界 |
| [番剧、国创与放映厅追番](validation/pgc-follow.md) | 追番／追剧与取消、登录和状态核对、账号隔离及离线验证 |
| [视频合集定位与播放顺序](validation/video-collection-controls-2026-11-12.md) | 顶部／底部／当前分 P 定位、显示排序与倒序播放、队列边界及回归验证 |
| [fvp 倍速暂停后继续](validation/fvp-pause-resume-synchronization-2026-11-12.md) | 视频停住而音频推进的现场日志、同管线目标确认及单元回归边界 |
| [fvp HTTP 断流与有界续读](validation/fvp-http-read-recovery-2026-11-11.md) | 现场音频提前 EOF、socket 断开／无响应复现、Range 续读及归因边界 |
| [请求风控与设备上下文](validation/api-risk-control-2026-11-11.md) | 热门 WBI、共享 buvid、风控／验证码识别、冷却与未实机边界 |
| [动态投票查看与参与](validation/dynamic-poll-viewing-2026-11-11.md) | 卡片／正文／转发的应用内投票、选项与结果、匿名参与及验证边界 |
| [动态发布能力与自适应编辑器](validation/dynamic-publishing-parity-2026-11-11.md) | B站表情、@用户、18图与裁剪、权限／定时、投票／直播预约及验证边界 |
| [Windows ARM64 EGL 表面修复](validation/windows-arm64-egl-surface-2026-11-12.md) | #100 生产者采样绑定与绘制冲突、resize 生命周期、受控回归及实机边界 |
| [Windows ARM64 黑屏与 MDK 过期提示](validation/windows-arm64-black-video-2026-11-10.md) | #100 前期保留 GPU 默认路径、撤回统一降级、ARM64 SDK 刷新与当时定位边界 |
| [macOS 前台冷启动停滞](validation/macos-foreground-startup-2026-11-10.md) | headless 激活与窗口可见性同步、禁帧生命周期回放及首帧后正常刷新检查 |
| [fvp 缓冲条小幅回缩](validation/fvp-buffer-timeline-2026-11-09.md) | 未解码包队列与呈现时钟差异、双轨端点换算、显示抖动容差和原生回归 |
| [fvp 恢复后反复停帧](validation/fvp-resume-clock-2026-11-09.md) | 本机 Release 中断日志、首次时钟窗口锁死、PiliPlus 职责对照及原生回归 |
| [Windows ARM64 悬停预览闪退](validation/windows-arm64-preview-crash-2026-11-09.md) | #100 的 OpenGL 能力错配、SDK 替换、原生降级与初始化错误传播、离线验证及实机边界 |
| [官方客户端文字排版对齐](validation/official-client-typography-2026-11-09.md) | HarmonyOS 字体核对、文字层级与频道字号、评论各部分样式及昵称色、楼中楼详情返回 |
| [动态页 UP 主筛选](validation/dynamic-author-filter-2026-11-08.md) | 动态／视频动态共享作者目录、宽窄布局、请求与滚动生命周期、离线回归和实机边界 |
| [Android fvp 音频定位阻塞](validation/android-fvp-seek-audio-2026-11-08.md) | 点击进度条久等、音频目标静音确认、SDK 固定参数与 APK 产物校验、手机双后端回归 |
| [PiliPlus 跳转与准备流程对照](validation/piliplus-seek-flow-2026-11-08.md) | 两后端单次目标确认、普通继续、原生缓存复用、真实缓冲提示与原生回归 |
| [播放控制流程简化](validation/player-control-simplification-2026-11-08.md) | PiliPlus 职责参考、原生缓存、统一确认时间线、有界最新跳转及未构建／实机边界 |
| [Windows ARM64 媒体清单校验](validation/windows-arm64-media-manifest-2026-11-08.md) | x64 文件名与 ARM64 哈希错配、应用校验修复及双架构 CMake 回归 |
| [Android fvp 直出跳转准备态](validation/android-fvp-direct-seek-2026-11-08.md) | 暂停 seek 的外部音频主时钟等待、目标图像确认与定向单元回归 |
| [Android fvp 直出起播回归](validation/android-fvp-direct-startup-2026-11-08.md) | 已解码但零呈现的手机日志、Surface 初始化顺序、音频时钟接入与定向单元回归 |
| [iOS 1.2.8 侧载重签兼容性](validation/ios-sideload-2026-11-08.md) | 实际 IPA 的 unsigned FAT 回归、arm64 thinning、临时签名和设备验证边界 |
| [历史分轨缓冲续读](validation/track-buffer-recovery-2026-11-08.md) | 已撤回的 HTTP 代理／字节索引、当时验证与当前原生缓存的区别 |
| [双轨暂停就绪与原生音频时钟](validation/paused-pair-synchronization-2026-11-08.md) | 移除静音预滚，统一起播、seek 与继续播放；真实音频目标确认和原生音频主时钟 |
| [缓冲条与连续跳转修复](validation/buffer-display-rapid-seek-2026-11-08.md) | 缓存淘汰与未知索引、旧 HTTP 读取撤销、原生 seek 完成屏障与 EOF 竞态 |
| [Apple／Linux 纹理交接与 Android 检查](validation/apple-linux-texture-handoff-2026-11-08.md) | Apple 完成帧与 Metal 复制、Linux 双向屏障／软件副本、Android Surface 队列审查与验证边界 |
| [Windows 两后端纹理交接](validation/windows-texture-handoff-2026-11-08.md) | 不可变 GPU 快照、完成查询、旧帧延后消费回归与其他平台边界 |
| [恢复时保留画面与进度](validation/recovery-frame-retention-2026-11-08.md) | 两后端共享停帧、同位置恢复、图像容量与离线验证边界 |
| [fvp 连续跳转与片尾竞态](validation/fvp-rapid-seek-eof-2026-11-08.md) | Android Release 的 MDK busy／unloaded 复现、最新目标隔离与有界重准备 |
| [直播聊天牌子、等级与内容选择](validation/live-chat-medals-selection-2026-11-08.md) | 粉丝牌与等级字段、可选择正文、阅读快照及离线回归边界 |
| [跨后端起播同步](validation/synchronized-playback-startup-2026-11-08.md) | 共享静音起播门槛、fvp 原生暂停与 Flutter 首帧、取消／暂停和延迟双轨验证 |
| [fvp 中途断音检测与恢复](validation/fvp-audio-recovery-2026-11-07.md) | 本机 1.2.8 证据边界、实际外部音频解码活动、停滞恢复与原生回归 |
| [播放后端清理](validation/playback-backends-2026-11-08.md) | 移除 fsplayer 实现、原生依赖与构建入口，旧设置回退和两后端回归 |
| [Windows 硬解边缘绿线](validation/windows-amd-hwdec-edges-2026-11-07.md) | mpv D3D11/EGL 正式修复、AMD／NVIDIA 新旧 mapper 的 392 次抓图及 HEVC 未复现边界 |
| [连续跳转只保留最新目标](validation/rapid-seek-latest-target-2026-11-07.md) | 应用后端包装层的命令分发修复、两后端原生取消、兼容／直出与暂停边界 |
| [解码与输出设置](validation/gpu-device-settings-2026-11-07.md) | Android 直出入口常驻、后端切换、GPU 选择移除、旧设置兼容与验证边界 |
| [fvp 直出启动黑屏修复](validation/android-fvp-direct-black-2026-11-07.md) | 空纹理消费误报、原生暂停屏障、连续打开及截图像素回归 |
| [Android 解码直出与 SurfaceView](validation/android-surface-output-2026-11-07.md) | 两后端纹理直出实验设置、4K60 H.264 约 25 Mbps／3× 实机对照、HC／HCPP 原型与限制 |
| [迷你小窗与置顶](validation/mini-player-2026-11-07.md) | 桌面置顶、尺寸与位置恢复，Android 画中画、移动应用内浮窗，以及 #102 关闭黑屏与 macOS 关闭竞态修复 |
| [可选 fvp 播放后端](validation/fvp-backend-2026-11-07.md) | 默认 media_kit、设置切换、固定 MDK 资产、分轨与生命周期、实机对照边界 |
| [Android fvp 原生进程隔离](validation/android-fvp-process-isolation-2026-11-07.md) | 子进程崩溃保留主界面、脱敏诊断、显式重新打开及受控故障验证 |
| [两后端统一缓冲窗口](validation/unified-buffer-window-2026-11-07.md) | 普通播放最多 2 分钟、预览 5 秒、相同素材的原生对照验证 |
| [个人媒体 fork 统一维护](validation/media-kit-personal-fork-2026-11-07.md) | 官方基线、八个固定 Git 包、libmpv 源码／资产、平台修复和验证边界 |
| [整体架构](architecture.md) | 产品范围、技术栈、模块依赖、目录、状态管理、存储和平台适配 |
| [设置页日志压缩导出](validation/log-export-2026-11-06.md) | 核心与播放日志、脱敏和容量限制、各平台默认保存位置及验证边界 |
| [项目宣传视频脚本](marketing/promotional-video-script.md) | 2026-10-30 第三版，按使用场景介绍发现、导航、播放、听视频、互动与离线，含分镜、素材和导出记录 |
| [推荐流设置](recommendation-settings-design.md) | PiliPlus 11 项对应、查询级过滤与刷新保留、性能约束及验证 |
| [App 推荐接入](app-recommendation-design.md) | Web/App 来源、独立设备标识、扫码授权、安全凭据及服务端反馈 |
| [App 推荐有效性调查](validation/app-recommendation-investigation-2026-11-10.md) | #107 的实际接口与身份、PiliPlus 空参数签名差异、其他客户端对照及游客验证边界 |
| [界面改版候选方案](ui-redesign/proposals.md) | 晴湾／素白／映厅三套视觉与用户最终选择，功能保留清单及双标签设计 |
| [晴湾与双标签实施](ui-redesign/implementation.md) | 共享外观、桌面分组与窄屏四项导航、双标签会话及状态保留、验证边界 |
| [晴湾第二轮调整](ui-redesign/refinement-plan.md) | 桌面独立播放窗口、正式图标、侧栏底部入口、页面工具栏与独立我的页 |
| [晴湾第三轮调整](ui-redesign/third-round-plan.md) | 单标签退役、播放窗原生返回与尺寸保留、首页工具精简、我的页内容标签 |
| [晴湾第四轮调整](ui-redesign/fourth-round-plan.md) | 一级导航同层、双标签返回关闭、直播与消息标签、热门四栏目与旧链接兼容 |
| [晴湾第五轮调整](ui-redesign/fifth-round-plan.md) | 消息/下载/设置同层、统一标签与导航图标、窄屏卡片留白、紧凑账号资料 |
| [晴湾第六轮调整](ui-redesign/sixth-round-plan.md) | 热门内容子标签、动态工具与初始分类、播放窗口会话位置和尺寸记忆 |
| [动态页默认标签](validation/default-dynamic-tab-2026-11-05.md) | #66 动态／视频动态偏好、跨启动保存、会话选择与显式链接优先级 |
| [晴湾第七轮调整](ui-redesign/seventh-round-plan.md) | 设置标题与分类顺序、消息标签精简、播放窗口最大化恢复优先级 |
| [桌面窗口状态持久化](validation/window-geometry-persistence.md) | 主窗口／播放窗口独立保存大小、位置与最大化，跨启动恢复及平台验证边界 |
| [热门四子标签](validation/popular-tabs.md) | 官网协议依据、期数切换与缓存、排行兼容、游客单期风控的验证边界 |
| [PiliPlus 与 media-kit fork 移植](validation/piliplus-media-kit-port.md) | 固定 Git 依赖、Android Surface、macOS SwiftPM stub 修复、解码与弹幕优化及验证边界 |
| [下载与离线播放](downloads.md) | 分 P／剧集、下载队列、断点恢复、校验、本地分轨播放及三端验收边界 |
| [项目更名](validation/project-renaming.md) | BiliSail／哔帆的命名范围、安装／存储标识与平台验证 |
| [应用图标](../assets/branding/README.md) | 小电视与船帆角标、保留候选方案、官网参考和平台资源 |
| [应用图标切换](validation/app-icon-switching.md) | 哔帆／原始小电视、各平台生效范围、持久化与验证边界 |
| [CI/CD 与安装包](validation/ci-cd.md) | GitHub Actions 五端构建、Android 固定签名、Windows 安装包、macOS arm64／Intel x64 DMG、iOS 未签名 IPA、Linux Flatpak／AppImage 与预览 Release 草稿 |
| [iOS 与 Linux 平台接入](validation/ios-linux.md) | iOS 未签名 IPA、Linux Flatpak／AppImage、原生封装、网页登录限制及未验收项 |
| [近期三项界面修复与发布验收](validation/ui-fixes-release-2026-10-09.md) | 顶部标签跟随、点击控件鼠标保护、滑动封面保留的 Windows 构建与测试 |
| [macOS 发布启动与安全存储](validation/macos-release-startup.md) | ad-hoc 权限约束、传统 Keychain、同产物启动／跨进程凭据验证与升级验收 |
| [macOS 双标签播放崩溃](validation/macos-dual-playback-crash.md) | 原生 multiview 断言、窗口能力检查、应用内双标签与验证边界 |
| [macOS 视频全屏与播放窗关闭](validation/macos-fullscreen-playback-close-2026-11-03.md) | 视频退出保留应用全屏、原生关闭与转换屏障、标签组全屏及验证边界 |
| [macOS 灰窗与退出兜底](validation/macos-unresponsive-exit-2026-11-06.md) | #78 退出无限等待修复、原生超时／回复隔离、休眠和引擎日志及灰屏定位边界 |
| [API 与会话](api-design.md) | 协议边界、接口映射、鉴权、错误、缓存和降级 |
| [消息中心与富消息](validation/messages-redesign-2026-11-05.md) | PiliPlus 行为参考、宽窄布局、会话管理、富消息解析及验证边界 |
| [消息表情、发送与管理入口](validation/messages-rich-composition-2026-11-05.md) | 私信表情／图片、直接回复、紧凑通知、聊天设置及外层菜单 |
| [私信聊天设置操作修复](validation/chat-settings-actions-2026-11-05.md) | 弹窗与工作区控制器归属、开关同步、确认操作隔离及回归测试 |
| [空间与消息反馈修复](validation/profile-message-fixes-2026-11-05.md) | 空间头图徽章、隐私提示与操作、私信助手入口及宽窄屏通知布局 |
| [UP 主主页应用内举报](validation/profile-report-2026-11-05.md) | 内容多选、可选理由、空间 Cookie/CSRF 单次提交、账号隔离与验证边界 |
| [搜索历史与热搜](validation/search-discovery-2026-11-01.md) | 居中搜索动效、宽窄屏入口、账号历史存储、热搜协议与自动验证边界 |
| [密码、短信与移动登录窗口](validation/password-sms-login.md) | 三种 Web 登录、交互验证码、安全会话与小屏/键盘布局 |
| [播放、直播与弹幕](playback-and-danmaku.md) | DASH 分轨、播放状态机、直播连接、渲染时钟与性能 |
| [PiliPlus 播放入口与双后端换源复用](validation/player-source-reuse-2026-11-12.md) | EDL、SDK 事件、取消额外音频轮询、兼容实例复用与 fvp 平台边界 |
| [media_kit 与 fvp 播放后端重构方案](player-backend-refactor-design.md) | 共享状态机、原生适配接口、两端行为差异、迁移顺序与验收矩阵；[实施与验证](validation/player-backend-refactor-2026-11-08.md) |
| [播放器实时播放信息](validation/player-information-tab-2026-11-07.md) | 设置内实时参数、当前后端、解码／输出／缓存／同步观测与采样生命周期 |
| [缓冲充足时的播放冻结检测](validation/buffered-playback-stall-2026-11-06.md) | #83 非阻塞时钟采样、静默停滞、抖动保护与恢复验证 |
| [缓冲停帧与误恢复修复](validation/buffering-frame-retention-2026-11-07.md) | 缓存／音频时钟落后的误判、最后一帧保持与连续网络 seek 验证 |
| [跳转后音视频同步恢复](validation/seek-av-synchronization-2026-11-07.md) | 暂停准备目标帧、原生 seek／restart 确认、暂停意图与旧请求隔离 |
| [fvp 跳转后同步恢复](validation/fvp-seek-synchronization-2026-11-07.md) | MDK 精确跳转、两后端直接替换最新目标与暂停意图 |
| [Android 视频灰黑首帧](validation/android-video-first-frame-2026-11-03.md) | Surface 初始尺寸、首帧通知、加载纹理过滤与硬解／软件解码真机回归 |
| [会员彩色弹幕](validation/vip-danmaku-2026-11-03.md) | #35 渐变显示／发送、权限与回显、离线保存及验证边界 |
| [1080P60 播放请求对照](validation/playurl-quality-2026-11-01.md) | PiliPlus 请求上下文、最高档发现／缺档补取、普通账号在线证据与大会员验收边界 |
| [播放地址内容不可用重试](validation/playurl-unavailable-retry-2026-11-05.md) | DASH 缺失／未分类业务错误恢复、网络与 WBI 共享次数预算、取消／账号／超时边界 |
| [无音轨视频播放](validation/silent-video-playback-2026-11-08.md) | BV1fTnZ6LEvr 的明确无音轨响应、完整播放契约和 Windows 两后端在线验证 |
| [DLNA 投屏](validation/dlna-casting.md) | 视频／影视／直播、B站接收端内容身份与弹幕开关、普通 DLNA、生命周期及设备验收边界 |
| [系统媒体通知与控制](validation/system-media-controls.md) | Android 通知、Apple 正在播放、Windows SMTC、Linux MPRIS、会话目标与验证边界 |
| [PiliPlus 播放器与弹幕依赖切换](validation/piliplus-dependencies-2026-11-01.md) | 精确提交、库插件打包、异步 API、headers、首帧与原生回归 |
| [Predidit 弹幕与播放器切换](predidit-media-migration.md) | 固定源码、Canvas 绘制适配、D3D11／Native Assets、打包及逐平台验证 |
| [播放控制、视频输出与平台合成拆分](player-output-composition-design.md) | 三层接口、当前 Flutter 基线、输出所有权与后续平台迁移边界 |
| [播放合成重绘与卡顿分析](validation/playback-composition-performance-2026-10-24.md) | 进度／字幕绘制传播、合成边界、Windows Profile 对照与偶发慢放的证据边界 |
| [弹幕调度与图像缓存合成优化](validation/playback-composition-performance-2026-10-28.md) | 当前播放链路、静止/等待停帧、PiliPlus 设计取舍和 Windows Profile 对照 |
| [滚动与混合弹幕性能复查](validation/scrolling-mixed-danmaku-performance-2026-10-28.md) | 逐帧分配、直接绘制、混合覆盖顺序和图集候选对照 |
| [首页推荐与三类播放性能热点](validation/performance-hotspots-2026-10-11.md) | 当前源码定位、图片／播放器／影视／直播结构探针、优化优先级与验收方案 |
| [Windows 播放器与网页 GPU 对照分析](validation/windows-player-gpu-analysis-2026-10-12.md) | copy-back、ANGLE／纹理复制、空弹幕调度、纯视频 GPU 实测与优化顺序 |
| [Windows 公开 4K60 播放性能](validation/windows-4k60-playback-2026-11-05.md) | Blender 公开素材、实际硬解、弹幕／控件叠加、Profile 稳态采样与瓶颈边界 |
| [Android 4K60 播放热点](validation/android-4k60-playback-2026-11-05.md) | 真机硬解／高刷合成、Perfetto 热点、HTTP 弱网模拟及音画同步边界 |
| [Android 4K60 HEVC／AV1 对照](validation/android-4k60-codecs-2026-11-05.md) | 8-bit／10-bit 实际硬件组件、同片对照、合成帧率复测与解码瓶颈边界 |
| [Android 4K60 H.264 双倍速与长按](validation/android-4k60-h264-2x-hold-2026-11-06.md) | 持续 2x、原生触摸反复切换、输出掉帧、后端时钟峰值与合成等待 |
| [Android 倍速切换掉帧定位与优化候选](validation/android-rate-switch-optimization-2026-11-06.md) | 松手窗口归因、原生速率／音频时钟观测、视口纹理候选与离线回归 |
| [Android 倍速切换优化实机复测](validation/android-rate-switch-device-2026-11-06.md) | H.264 4K60 同包因素对照、160 次长按、时钟平滑／纹理负载收益与残余停顿 |
| [长按倍速与官网／原生时钟对照](validation/hold-rate-web-native-2026-11-06.md) | 官网实际调用链、Chromium／mpv／Media3 差异、回切时钟平滑与验证边界 |
| [Windows GPU 优化结果](validation/windows-gpu-optimization-2026-10-13.md) | 非 copy-back 硬解、GPU 有序提交、空弹幕单次唤醒与同素材前后实测 |
| [Windows 弹幕 GPU 对照](validation/windows-danmaku-gpu-analysis-2026-10-13.md) | 弹幕密度、固定文字、合成帧率与同素材测量边界 |
| [官方弹幕合成检查](validation/official-danmaku-composition-2026-10-13.md) | 官网 DOM、图层和录制行为的参考证据 |
| [真实首页视频 GPU 复测](validation/windows-real-video-gpu-2026-10-13.md) | 正式播放页面、真实弹幕、持久偏好与完整采样 |
| [弹幕高刷合成实验（已撤回）](validation/danmaku-frame-cadence-2026-10-13.md) | 历史候选测量、撤回记录与随屏幕刷新率运行的 Ticker |
| [倍速 seek 供帧缓冲实验](validation/video-frame-queue-experiment-2026-10-13.md) | 构建开关、小容量解码帧队列、Windows 原生兼容性及手动对照方法 |
| [长按与松开倍速回归修复](validation/hold-rate-regression-2026-11-13.md) | 对比 1.2.9+0、音频输出与时钟配置、最新后端跨源复用及验证边界 |
| [性能热点第一批优化结果](validation/performance-hotspots-results-2026-10-11.md) | 九项 P1 的图片任务、局部订阅、弹幕窗口、影视懒创建修复与验证边界 |
| [性能热点 P2 优化结果](validation/performance-p2-results-2026-10-11.md) | 图片连接复用、分页索引、启动并发、字幕与评论、影视缓存／解码、直播对账及待实机测量项 |
| [连续播放与下一集](validation/continuous-playback.md) | 分 P／合集／影视顺序、完播推进、设置持久化与全屏控件 |
| [播放器音量均衡](validation/audio-normalization.md) | 标准／高动态／关闭、UGC／PGC 元数据、原生增益与验证边界 |
| [小窗播放控件与音质选择](validation/player-compact-audio-controls-2026-11-02.md) | 小窗精简控件／更多选项调节、音质选择、换源保留与验证边界 |
| [与 PiliPlus 的播放音量对照](validation/player-volume-piliplus-comparison-2026-11-01.md) | 默认原生音量、移动端系统／播放器控件差异、放大与音轨偏好、同源 A/B 条件及离线验证边界 |
| [播放 GPU 与 PiliPlus 对照](validation/playback-gpu-piliplus-2026-11-01.md) | 固定依赖、透明合成、控件重复绘制修复与 Windows Profile 验证边界 |
| [固定与滚动弹幕分层对照](validation/danmaku-layers-performance-2026-11-01.md) | 单一时钟、固定层保留、覆盖顺序及三类场景的 Profile 前后对照 |
| [Windows 全屏弹幕与 Skia 对照](validation/windows-skia-playback-2026-11-01.md) | 实际硬解、PiliPlus 渲染后端差异、真实视频交叉对照及验证边界 |
| [直通硬解调研与方案](hardware-decoding-plan-2026-11-01.md) | #44 发布追溯、Bili.Libre.Speed／Predidit 路径、各平台硬解设置与自有 fork 分阶段维护 |
| [Windows ANGLE 直通硬解](validation/windows-angle-direct-hwdec-2026-11-01.md) | copy 回退修复、PiliPlus 实际链路差异、三组 Profile 交叉对照及原生验收边界 |
| [Windows 杜比视界 Profile 5 偏色](validation/dolby-vision-profile5-2026-11-02.md) | 解码前色彩转换、公开 Dolby 样片、实际纹理颜色回归与平台边界 |
| [跨平台杜比视界与兼容回退](validation/dolby-vision-cross-platform-2026-11-03.md) | Android RPU／gpu-next 真机对照、原生能力检查、共享兼容流回退及各平台未测项 |
| [听视频与音频控件](validation/listen-video.md) | 独立音轨、常驻响应式控件、切换／检查点及原生验证 |
| [充电专属与付费视频](validation/video-access.md) | 权益分类、播放限制提示、官网入口与共享视频卡角标 |
| [实施与验收](implementation-plan.md) | 技术验证、开发里程碑、测试、构建与发布要求 |
| [架构决策](decisions.md) | 已选方向、备选方案及重新评估条件 |
| [参考项目与资料](references.md) | 本地源码定位、借鉴边界、官方资料和待确认事项 |
| [首版实测记录](validation/m0-results.md) | Windows 原生播放、工程检查、构建结果和未测项 |
| [界面与多标签验证](validation/uwp-workspace.md) | UWP 风格布局、首页频道、多标签状态与本轮验证边界 |
| [单标签导航与顶部滚动](validation/single-page-navigation.md) | 单标签恢复、Android 默认值、播放与空间返回链及历史滚动验证 |
| [顶部连续滚动与子标签吸附](validation/continuous-scroll-headers-2026-10-31.md) | 首页、我的与用户主页的距离联动、淡出、吸附与保留列表生命周期 |
| [首页子频道协议](validation/home-subtabs.md) | 各首页列表的端点、游标与前序接入记录 |
| [窄屏一级导航动效](validation/primary-navigation-motion.md) | 底栏不透明滑入、隐藏根分支构建复用与历史验证边界 |
| [窄屏底栏切换复查](validation/primary-navigation-performance-2026-10-28.md) | Windows/Android 共用分页器活动隔离、设置表单复用和底栏过渡 |
| [窄屏视频卡切页与生命周期分析](validation/narrow-video-card-navigation-analysis-2026-10-30.md) | 页面保留与局部更新、真实账号 Windows Profile、深滚动／快速切换和优化顺序 |
| [视频卡片往返滚动与测量复用](validation/card-scroll-lifecycle-2026-10-31.md) | 页面/行/卡片/图片的生命周期、有限测量缓存、窄屏两列与宽屏六列性能复查 |
| [长列表回到顶部](validation/scroll-to-top-performance-2026-10-31.md) | 自然行高定位、不可见沿途行复用、原动画与布局对照及性能验证 |
| [窄屏视频卡切换优化结果](validation/narrow-video-card-navigation-results-2026-10-30.md) | 空闲内容复用、移除整页平移、1×／3× Windows Profile 对照和验证边界 |
| [Android 窄屏底栏性能复查](validation/android-primary-switch-2026-10-26.md) | 保留列表约束、嵌套查询作用域、图片可见性与真机 Profile 对照 |
| [Android 原生与 PiliPlus 导航对照](validation/android-navigation-reference-comparison-2026-10-26.md) | 状态保留与页面结构、悬停/裁剪优化、图片和骨架候选及后续优先级 |
| [Android 预测式返回](validation/android-predictive-back.md) | 工作区系统手势预览、取消／确认、返回优先级和验证边界 |
| [Android 系统手势条背景](validation/android-system-navigation-2026-10-30.md) | 黑底原因、随主题适配的系统栏、安全区绘制与验证边界 |
| [Android 平板冷启动导航](validation/android-tablet-navigation-cold-start.md) | 缓存引擎屏幕指标初始化、异常尺寸回退、窄屏底栏限制与验证边界 |
| [排行榜分区参数](validation/ranking-regions.md) | 官网配置动态目录、新分区 ID、刷新撤下处理与风控验证边界 |
| [影视与直播内置播放](validation/content-playback.md) | 四频道内置入口、三类播放页、影视选集、直播线路与原生验证 |
| [直播清晰度与线路选择](validation/live-playback-options.md) | 官网与参考协议、统一菜单样式、自动档、主备线路和独立默认清晰度 |
| [直播与点播弱网缓存](validation/network-playback-buffering-2026-11-01.md) | 前后向配额、首次／恢复预缓冲、等待截止时间及 Windows 故障注入 |
| [直播流与点播音质偏好](validation/live-stream-audio-preferences-2026-10-30.md) | 可选协议／格式／编码、偏好保存、WBI 请求、杜比视界与 FLAC／杜比音轨 |
| [影视侧栏与直播 SC](validation/pgc-live-sidebar.md) | 官方桌面式影视简介/选集/系列、直播聊天与 SC 气泡、读取边界 |
| [影视性能分析与选集滚动](validation/pgc-page-performance-scroll.md) | 系列全量构建与简介重建热点、Windows Profile 证据、选集／分 P 边界触摸衔接 |
| [直播 SC 时长与倒计时](validation/live-sc-lifetime.md) | HTTP／实时秒数语义、到期移除、气泡和卡片倒计时、生命周期及验证 |
| [影视与直播弹幕修复](validation/pgc-live-danmaku.md) | 剧集弹幕/发送、直播实时消息与绘制、SC 卡片和分区列表协议 |
| [密集番剧弹幕与选集子标签](validation/pgc-dense-danmaku.md) | 登录首集超量弹幕的有界抽样、横向滚轮与悬停拖动条 |
| [直播表情与主页入口](validation/live-chat-profiles.md) | 精简房间信息、右上在看/看过人数、行内/大表情、弹幕及 SC 用户主页跳转 |
| [直播卡片计数](validation/live-card-count.md) | 人气数字的千／万／亿缩略和卡片回归 |
| [直播连接提示](validation/live-chat-status.md) | 聊天列表内的连接提示、自然滚出与跟随保留 |
| [UP 空间直播入口](validation/profile-live-entry.md) | 独立直播间查询、开播状态和工作区导航 |
| [直播在看人数精度](validation/live-viewer-precision.md) | 7777 接口调查、精确人数快照、实时下界文案和四项集成验证 |
| [隐藏控件进度条与直播发送](validation/collapsed-progress-live-send.md) | 视频／影视底部细进度、直播双发送栏／表情权限和单次写验证 |
| [评论与直播表情选择](validation/emoticon-picker-tabs.md) | 居中弹窗、系列子标签、草稿插入与权限验证 |
| [共享评论发送框扩展](validation/comment-composer-2026-10-31.md) | 图片、@用户、同步动态、播放时间与桌面／移动布局及协议验证 |
| [播放器与标签保留](validation/player-workspace.md) | UWP 播放页、只读子标签和未关闭页面的生命周期修正 |
| [多标签并发播放](validation/multi-tab-playback.md) | 标签独立播放器、互斥播放、模式切换与资源释放 |
| [Windows 播放窗打开性能](validation/dual-playback-open-performance-2026-10-28.md) | 首帧前同步等帧热点、窗口初始尺寸、Profile 前后对照与验收 |
| [云端进度与续播](validation/cloud-playback-progress.md) | 播放进度上报、本地优先/云端补充、账号和源隔离、Windows 验证边界 |
| [点播打开优化](validation/playback-startup.md) | CDN 对照、共享准备预算、可取消外部音轨加载和 Windows 竞态验证 |
| [云端观看历史](validation/cloud-watch-history.md) | 当前账号云列表、游标分页、统计补齐与观看日期、离线验证边界 |
| [界面控件与设置](validation/ui-controls.md) | 播放配置、头像、动态/直播卡、空降助手和账户交互验证 |
| [工作区弹窗一致性](validation/workspace-dialogs.md) | 双/多标签统一窗口内弹层、双 View 路由归属及回归验证 |
| [播放页与评论交互](validation/video-comments.md) | 官方桌面风格双标签、折叠合集、评论与楼中楼触底自动加载及验证 |
| [播放页信息区滑动](validation/playback-info-swipe.md) | 视频／影视简介评论、直播聊天／SC 共用分页、状态保留与手势验证 |
| [评论图片与作者装扮](validation/comment-images-decorations.md) | 共用动态原图预览、右侧装扮图片与粉丝编号、验证边界 |
| [图片查看器保存、复制与长图](validation/image-viewer-export-long-images.md) | 三端默认图片目录、图片剪贴板、长图限制原因与有界解码预览 |
| [播放页简介侧栏](validation/video-sidebar.md) | UP 统计与关注、合集卡片、常驻推荐与分隔线 |
| [合作视频创作团队](validation/video-collaboration.md) | Web staff 成员、正式桌面客户端式头像／角色／展开与共享关注入口 |
| [视频标签与搜索](validation/video-tags.md) | 简介中的真实标签、点击搜索、独立重试与导航保留 |
| [合集订阅按钮](validation/collection-subscription.md) | 合集订阅态、粉色按钮、显式订阅/取消与账号隔离 |
| [合集异常与播放崩溃](validation/collection-playback-crash.md) | 合集状态字段修正、Windows 原生转储与无障碍树更新规避 |
| [Windows 悬停预览销毁崩溃](validation/windows-preview-dispose.md) | mpv 渲染资源释放顺序、可复现原生补丁与针对性检查 |
| [悬停预览与主视频出帧争用](validation/video-preview-contention.md) | 渲染线程尺寸查询、保留 GPU 的修复与 Windows Profile 对照 |
| [Windows 硬解输出性能](validation/windows-video-render-performance-2026-10-11.md) | 中间纹理尺寸、渲染通知合并、GPU 与音画同步对照及验收边界 |
| [硬解播放后端调研](validation/playback-backend-research-2026-10-11.md) | Flutter 纹理交付、fvp/Media3/libmpv 候选与分轨、许可和同步验证门槛 |
| [关注用户分组](validation/follow-groups.md) | 关注列表分组子标签、账号隔离、已关注菜单与单次保存 |
| [快捷键与富评论](validation/shortcuts-rich-comments.md) | UWP 默认键位、悬浮控制栏、评论标识/表情/图片和资源来源 |
| [快捷键体系重构方案](shortcut-system/refactor-design.md) | 设计基线：单一输入入口、完整功能清单、作用域、迁移及实键验收 |
| [快捷键重构实施记录](shortcut-system/implementation-results.md) | 单入口分发、页面能力、全屏／录制／图片作用域、异步媒体目标及验证边界 |
| [音量提示与快捷键焦点](validation/keyboard-feedback-focus.md) | 音量百分比、标点键回退、评论焦点与关闭标签 |
| [设置分类、侧键与字体](validation/settings-tabs-fonts.md) | 设置专属分类、关闭标签快捷键、鼠标侧键录制和默认 HarmonyOS Sans |
| [内置与系统字体选择](validation/font-selection.md) | HarmonyOS Sans、Windows/macOS 已安装字体搜索、独立界面/弹幕偏好与普惠体移除 |
| [关于页与每日更新检查](validation/app-updates.md) | GitHub 地址、手动检查、每日首次启动提醒与 Release 跳转 |
| [视频编解码设置](validation/video-codec-settings.md) | H.264/HEVC/AV1 偏好、自动/软件解码、SDK 差异与验证边界 |
| [视频 CDN 设置与测速](validation/video-cdn.md) | 自动／运营商与具体节点、点击展开测速、旧设置兼容、备用与取消 |
| [悬停预览加载延迟](validation/video-preview-loading.md) | 官网无音轨预览、cid 直传、CDN 顺序、启动预算、静止窗口与首帧切换 |
| [播放控件与小窗布局](validation/responsive-player.md) | 单行工具栏、弹幕输入自适应、窄窗口布局和播放状态保留 |
| [全屏鼠标与滚轮输入](validation/fullscreen-pointer-input-2026-11-02.md) | #60 的视频输出输入隔离、全屏光标空闲隐藏与 Windows 验证边界 |
| [播放器顶部导航与人数](validation/player-top-navigation.md) | 返回／回主页的三种模式、全屏动作、UGC 正在观看人数与取消隔离 |
| [移动端弹幕输入与键盘布局](validation/mobile-danmaku-keyboard-performance.md) | 高度变化局部布局、控件测量复用、直播弹幕缓存保留及结构对比 |
| [视频章节与悬停缩略图](validation/playback-timeline.md) | 自适应分段、雪碧图裁剪、预览生命周期与真实视频验证 |
| [触屏滑动进度与中央预览](validation/touch-swipe-seek.md) | 相对横滑、中央缩略图与时间、松手单次跳转及局部重绘边界 |
| [高能进度条实现方案](high-energy-progress-design.md) | 官网聚合接口、章节互斥、静态曲线、平台默认、时长校验与性能预算；[实现验证](validation/high-energy-progress.md) |
| [字幕与 AI 原声翻译](validation/subtitles-translated-audio.md) | 动态菜单选择修复、空文本字幕、AI 标识与语音双轨切换、登录态 Windows 验证及新版 Protobuf 调查 |
| [用户主页](validation/user-profile.md) | 个人/UP 主空间、头像入口、投稿与动态/收藏/关注列表、会话隔离和实测边界 |
| [UP 主与个人主页重构](ui-redesign/profile-redesign-2026-11-05.md) | PiliPlus 行为参考、宽窄屏头图资料、合集/系列、追番追剧和验证边界 |
| [账号菜单与消息](validation/account-messages.md) | 头像资料/入口、五类收件箱、私信分页/发送/已读、账号隔离与 Windows 只读实测 |
| [主页卡片与富动态](validation/profile-dynamic-style.md) | UWP 横向投稿卡、居中动态列表、行内表情与转发内容、验证边界 |
| [动态分享、评论与点赞](validation/dynamic-interactions.md) | Web 评论身份、共用评论区、复制/转发、单次写与会话隔离 |
| [动态操作菜单与投票](validation/dynamic-operations-and-voting-2026-11-11.md) | 置顶／编辑／删除／举报、共享屏蔽与状态、Web IM 分享、应用内投票及响应式验证 |
| [动态内容与详情重构](validation/dynamic-content-redesign-2026-11-09.md) | PiliPlus 类型对照、话题／商品／附加卡片、宽屏分栏与窄屏滚动、草稿保留及离线验证 |
| [应用内话题与动态展示修复](validation/dynamic-topics-and-text-2026-11-09.md) | 话题简介／排序／分页／折叠、内部导航与名称搜索、右上角详情、真实排版截断及预约状态 |
| [动态话题外跳与顶部栏修复](validation/dynamic-topic-navigation-2026-11-10.md) | 移动端话题链接、ID 优先与名称回退、协议到点击回归、工作区顶部栏去重 |
| [独立话题页与动态发布](validation/dynamic-publishing-and-topic-page-2026-11-10.md) | 页内返回／发起人、菜单收藏与原生举报、响应式发布入口、排序吸顶与账号隔离 |
| [用户页、倍速与标签播放](validation/profile-playback-rates.md) | 紧凑资料/工具条、固定倍速档位和普通标签继续播放 |
| [应用会话内继承倍速与音量](validation/session-playback-rate.md) | 后续播放继承调速／音量、全局音量记忆开关、重启恢复与验证边界 |
| [触摸长按临时倍速](validation/touch-hold-playback-rate.md) | 画面长按使用已有延迟／倍速、松开恢复、全屏与取消边界 |
| [长按倍速的音频输出缓冲](validation/hold-rate-output-buffer-2026-11-01.md) | 剩余停顿原因、PiliPlus 对照、50 ms 输出队列与 Windows Profile ABBA 验证 |
| [播放器滑动亮度与音量](validation/fullscreen-swipe-controls.md) | 普通／全屏左侧亮度与右侧音量、设置开关、窗口亮度恢复和验证边界 |
| [双指缩放与中部全屏手势](validation/player-picture-gestures-2026-11-06.md) | #64 双指缩放／移动／还原、三分区纵滑、设置兼容与手势冲突验证 |
| [首页刷新、自动分页与图片缓存](validation/feed-scroll-image-cache.md) | 悬浮刷新/回顶部、首屏补页、隐藏列表隔离和图片缓存设置 |
| [列表滚动性能修复](validation/feed-scroll-performance.md) | Windows profile 对比、首页及搜索/历史虚拟化、局部重建和悬停生命周期 |
| [页面性能热点复查](validation/page-performance-hotspots-2026-10-28.md) | 下载／离线页、用户空间和消息页的热点证据、局部更新方案及验证边界 |
| [推荐页分页与反馈性能](validation/recommendation-updates-2026-10-27.md) | 单卡订阅、分页组件复用、查询归属与 Android Profile 对照 |
| [多页面深滚动与共享卡片更新](validation/retained-card-pages-2026-10-27.md) | 隐藏列表惯性、共享卡片内容复用、动态高度缓存与真机对照 |
| [全局桌面滚轮平滑过渡](validation/smooth-scrolling.md) | 官方模拟器、阻尼比设置、连续/反向输入、嵌套仲裁及验证边界 |
| [连续滚轮时序优化](validation/wheel-scroll-timing-2026-10-31.md) | 真实输入时间与帧对齐、有界输入缓冲、两列／六列滚轮信号 Profile 对照 |
| [macOS 触控板滑动返回](validation/macos-trackpad-back.md) | 松手返回、阈值取消、左侧箭头、横向列表与播放器进度条隔离 |
| [API 端点验证](validation/api-endpoints.md) | 首版端点、协议与在线只读烟测 |
| [搜索分类与排序](validation/search-categories.md) | 七类搜索、综合页 UP 主、分类排序、筛选与旧响应隔离 |
| [共享视频卡片](validation/shared-video-cards.md) | 推荐理由、搜索/视频动态显示差异、16:9 封面与宽屏网格 |
| [DPI 与文字缩放](validation/dpi-adaptation.md) | 大字体列数、触摸全文与 Windows 工作区约束修复，像素比例／字号矩阵与实机未验项 |
| [视频卡悬停预览](validation/video-card-hover.md) | 官方客户端式封面放大、悬停视频自动播放、稍后再看与网页接口核对 |
| [视频卡操作菜单](validation/video-card-menus.md) | 推荐反馈、添加稍后再看、删除稍后再看及悬停入口范围 |
| [稍后再看队列播放](validation/watch-later-queue.md) | 列表上下文、分 P 与队列推进、侧栏和账号/标签隔离 |
| [收藏子标签与视频卡片](validation/favorites-tabs.md) | 五类收藏入口、公共视频卡、自建收藏夹状态/日期与信息编辑、Windows 验证边界 |
| [收藏夹播放全部](validation/favorite-playback-queue.md) | 收藏夹/合集有序播放、独立分页、播放页列表、账号隔离与容量边界 |
| [收藏与订阅取消操作](validation/favorites-unsubscribe.md) | 卡片三点菜单、取消前确认、CSRF 单次提交与分页/账号竞态 |
| [收藏视频移除与收藏夹删除](validation/favorite-management-2026-11-12.md) | 长按/更多菜单、指定收藏夹取消收藏、自建收藏夹删除与账号/分页隔离 |
| [媒体包验证](validation/media-packages.md) | 包契约、限制、原生资产来源 |
| [播放器预读窗口](validation/player-buffer-ahead.md) | 普通播放最多 5 分钟、悬停预览 5 秒、内存限额和 Windows 原生验证 |
| [弹幕顶部距离](validation/danmaku-top-margin.md) | 默认 0、两处配置入口、点播／直播区域计算和旧设置兼容 |
| [弹幕行距](validation/danmaku-line-spacing.md) | 行间空白从 0 起调节、默认 5、点播／直播布局与持久化 |
| [弹幕样式与过滤配置](validation/danmaku-style-settings.md) | 字体/加粗/效果、时间偏移、重复合并、同屏密度与本地过滤 |
| [弹幕发送色板与面板](validation/danmaku-send-style-picker.md) | 17 色与 RGB 自定义、预览、确认／取消、窗口／键盘及大字号适配 |
| [全屏弹幕保留](validation/danmaku-fullscreen.md) | 点播视口变更保留活动弹幕、调度游标和滚动进度，Windows 全屏回归 |
| [弹幕速度与播放倍速](validation/danmaku-playback-rate.md) | 按播放时间加载／触发，独立动画时间控制滚动和停留，暂停／seek／时间窗回归 |
| [密集弹幕性能优化](validation/danmaku-performance.md) | Windows Profile 热点、分帧准备、阴影图像缓存、参考实现比较与验证边界 |
| [播放错误排查](validation/native-playback-errors.md) | 原生日志误判、错误态控制栏与本地脱敏日志 |
| [双轨同步与自动重试](validation/audio-video-recovery-2026-10-30.md) | 单轨提前耗尽、同步暂停、无日志停滞、共享恢复预算与取消 |
| [双轨两秒同步](validation/paired-stall-synchronization-2026-11-07.md) | media_kit／fvp 共享单轨缺失截止时间、fvp 视频提前结束与整组暂停恢复 |
| [Windows 首帧停滞修复](validation/windows-playback-flag-abi-2026-10-23.md) | libmpv FLAG 类型宽度、seek 位置确认、来源审计与诊断清理 |
| [开发协作约定](../AGENTS.md) | 后续开发与自动化代理必须遵守的仓库规则 |

## 如何理解方案中的结论

- **方案决定**：本项目接下来采用的组织方式，不代表代码已实现。
- **源码事实**：已查看两个本地参考仓库；提交快照见参考文档。
- **外部能力说明**：已查阅框架和包维护方文档；不等于项目中的三端验收结果。
- **实测边界**：Windows 游客点播和部分公开 API 已实测；登录后的完整流程、其他平台运行与性能预算仍待验证，逐项结果以首版实测记录为准。

架构文档中的完整目录树和性能预算仍是目标设计；当前仅创建实际用到的功能。已实现 API/播放器契约以各包公共入口为准，重要差异记录在架构决策和实测记录中。

后续从 [M0 技术验证](implementation-plan.md#m0技术验证) 的未验项目继续，特别是 Android/macOS 原生播放与真实登录；首版已经提供 Windows 观看闭环。


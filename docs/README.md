# BiliSail（哔帆）设计文档

设计与实现日期：2026-10-05。状态：已创建 0.1.0 Windows 预览工程；完整设计仍是后续路线，当前能力与验证边界见 [M0 实测记录](validation/m0-results.md) 和 [根 README](../README.md)。

本项目采用 **Flutter + Dart 构建客户端，独立 API 包承接 Bilibili 协议，播放器与弹幕各自封装，Rust 按证据引入**。首批目标为 Android、Windows、macOS；参考 `biliuwp-lite` 的客户端能力和 `bili-kernel` 的 API 分层。

## 阅读顺序

| 文档 | 内容 |
| --- | --- |
| [整体架构](architecture.md) | 产品范围、技术栈、模块依赖、目录、状态管理、存储和平台适配 |
| [下载与离线播放](downloads.md) | 分 P／剧集、下载队列、断点恢复、校验、本地分轨播放及三端验收边界 |
| [项目更名](validation/project-renaming.md) | BiliSail／哔帆的命名范围、安装／存储标识与平台验证 |
| [应用图标](../assets/branding/README.md) | 小电视与船帆角标、保留候选方案、官网参考和平台资源 |
| [CI/CD 与安装包](validation/ci-cd.md) | GitHub Actions 三端构建、Android 固定签名、预览 Release 草稿、Windows MSIX／MSI／EXE 签名与 macOS DMG 安装 |
| [API 与会话](api-design.md) | 协议边界、接口映射、鉴权、错误、缓存和降级 |
| [密码、短信与移动登录窗口](validation/password-sms-login.md) | 三种 Web 登录、交互验证码、安全会话与小屏/键盘布局 |
| [播放、直播与弹幕](playback-and-danmaku.md) | DASH 分轨、播放状态机、直播连接、渲染时钟与性能 |
| [实施与验收](implementation-plan.md) | 技术验证、开发里程碑、测试、构建与发布要求 |
| [架构决策](decisions.md) | 已选方向、备选方案及重新评估条件 |
| [参考项目与资料](references.md) | 本地源码定位、借鉴边界、官方资料和待确认事项 |
| [首版实测记录](validation/m0-results.md) | Windows 原生播放、工程检查、构建结果和未测项 |
| [界面与多标签验证](validation/uwp-workspace.md) | UWP 风格布局、首页频道、多标签状态与本轮验证边界 |
| [单标签导航与顶部滚动](validation/single-page-navigation.md) | 平台默认／手动导航模式、页面回退、状态保留、横向滚轮与平台验证 |
| [首页子频道协议](validation/home-subtabs.md) | 各首页列表的端点、游标与前序接入记录 |
| [排行榜分区参数](validation/ranking-regions.md) | 官网配置动态目录、新分区 ID、刷新撤下处理与风控验证边界 |
| [影视与直播内置播放](validation/content-playback.md) | 四频道内置入口、三类播放页、影视选集、直播线路与原生验证 |
| [影视侧栏与直播 SC](validation/pgc-live-sidebar.md) | 官方桌面式影视简介/选集/系列、直播聊天与 SC 气泡、读取边界 |
| [直播 SC 时长与倒计时](validation/live-sc-lifetime.md) | HTTP／实时秒数语义、到期移除、气泡和卡片倒计时、生命周期及验证 |
| [影视与直播弹幕修复](validation/pgc-live-danmaku.md) | 剧集弹幕/发送、直播实时消息与绘制、SC 卡片和分区列表协议 |
| [密集番剧弹幕与选集子标签](validation/pgc-dense-danmaku.md) | 登录首集超量弹幕的有界抽样、横向滚轮与悬停拖动条 |
| [直播表情与主页入口](validation/live-chat-profiles.md) | 精简房间信息、右上在看/看过人数、行内/大表情、弹幕及 SC 用户主页跳转 |
| [隐藏控件进度条与直播发送](validation/collapsed-progress-live-send.md) | 视频／影视底部细进度、直播双发送栏／表情权限和单次写验证 |
| [评论与直播表情选择](validation/emoticon-picker-tabs.md) | 居中弹窗、系列子标签、草稿插入与权限验证 |
| [播放器与标签保留](validation/player-workspace.md) | UWP 播放页、只读子标签和未关闭页面的生命周期修正 |
| [多标签并发播放](validation/multi-tab-playback.md) | 标签独立播放器、单标签互斥、模式切换与资源释放 |
| [云端进度与续播](validation/cloud-playback-progress.md) | 播放进度上报、本地优先/云端补充、账号和源隔离、Windows 验证边界 |
| [云端观看历史](validation/cloud-watch-history.md) | 当前账号云列表、游标分页、统计补齐与观看日期、离线验证边界 |
| [界面控件与设置](validation/ui-controls.md) | 播放配置、头像、动态/直播卡、空降助手和账户交互验证 |
| [播放页与评论交互](validation/video-comments.md) | 官方桌面风格双标签、折叠合集、评论与楼中楼验证 |
| [评论图片与作者装扮](validation/comment-images-decorations.md) | 共用动态原图预览、右侧装扮图片与粉丝编号、验证边界 |
| [播放页简介侧栏](validation/video-sidebar.md) | UP 统计与关注、合集卡片、常驻推荐与分隔线 |
| [视频标签与搜索](validation/video-tags.md) | 简介中的真实标签、点击搜索、独立重试与导航保留 |
| [合集订阅按钮](validation/collection-subscription.md) | 合集订阅态、粉色按钮、显式订阅/取消与账号隔离 |
| [合集异常与播放崩溃](validation/collection-playback-crash.md) | 合集状态字段修正、Windows 原生转储与无障碍树更新规避 |
| [关注用户分组](validation/follow-groups.md) | 已关注菜单、现有分组选择、特殊分组保留与单次保存 |
| [快捷键与富评论](validation/shortcuts-rich-comments.md) | UWP 默认键位、悬浮控制栏、评论标识/表情/图片和资源来源 |
| [快捷键体系重构方案](shortcut-system/refactor-design.md) | 设计基线：单一输入入口、完整功能清单、作用域、迁移及实键验收 |
| [快捷键重构实施记录](shortcut-system/implementation-results.md) | 单入口分发、页面能力、全屏／录制／图片作用域、异步媒体目标及验证边界 |
| [音量提示与快捷键焦点](validation/keyboard-feedback-focus.md) | 音量百分比、标点键回退、评论焦点与关闭标签 |
| [设置分类、侧键与字体](validation/settings-tabs-fonts.md) | 设置专属分类、关闭标签快捷键、鼠标侧键录制和默认 HarmonyOS Sans |
| [普惠体与系统字体选择](validation/font-selection.md) | 内置阿里巴巴普惠体、Windows/macOS 已安装字体搜索、独立界面/弹幕偏好 |
| [关于页与每日更新检查](validation/app-updates.md) | GitHub 地址、手动检查、每日首次启动提醒与 Release 跳转 |
| [视频编解码设置](validation/video-codec-settings.md) | H.264/HEVC/AV1 偏好、自动/软件解码、SDK 差异与验证边界 |
| [视频 CDN 与悬停恢复](validation/video-cdn.md) | 自动／运营商优先、旧设置兼容、备用地址／超时和前台恢复 |
| [悬停预览加载延迟](validation/video-preview-loading.md) | 官网无音轨预览、cid 直传、CDN 顺序、启动预算、静止窗口与首帧切换 |
| [播放控件与小窗布局](validation/responsive-player.md) | 单行工具栏、弹幕输入自适应、窄窗口布局和播放状态保留 |
| [视频章节与悬停缩略图](validation/playback-timeline.md) | 自适应分段、雪碧图裁剪、预览生命周期与真实视频验证 |
| [用户主页](validation/user-profile.md) | 个人/UP 主空间、头像入口、投稿与动态/收藏/关注列表、会话隔离和实测边界 |
| [账号菜单与消息](validation/account-messages.md) | 头像资料/入口、五类收件箱、私信分页/发送/已读、账号隔离与 Windows 只读实测 |
| [主页卡片与富动态](validation/profile-dynamic-style.md) | UWP 横向投稿卡、居中动态列表、行内表情与转发内容、验证边界 |
| [动态分享、评论与点赞](validation/dynamic-interactions.md) | Web 评论身份、共用评论区、复制/转发、单次写与会话隔离 |
| [用户页、倍速与标签播放](validation/profile-playback-rates.md) | 紧凑资料/工具条、固定倍速档位和普通标签继续播放 |
| [应用会话内继承倍速](validation/session-playback-rate.md) | 后续视频继承调速、长按隔离、重启默认值与验证边界 |
| [首页刷新、自动分页与图片缓存](validation/feed-scroll-image-cache.md) | 悬浮刷新/回顶部、首屏补页、隐藏列表隔离和图片缓存设置 |
| [列表滚动性能修复](validation/feed-scroll-performance.md) | Windows profile 对比、首页及搜索/历史虚拟化、局部重建和悬停生命周期 |
| [全局桌面滚轮平滑过渡](validation/smooth-scrolling.md) | 统一滚轮动画、连续/反向输入、嵌套仲裁及验证边界 |
| [API 端点验证](validation/api-endpoints.md) | 首版端点、协议与在线只读烟测 |
| [搜索分类与排序](validation/search-categories.md) | 七类搜索、综合页 UP 主、分类排序、筛选与旧响应隔离 |
| [共享视频卡片](validation/shared-video-cards.md) | 推荐理由、搜索/视频动态显示差异、16:9 封面与宽屏网格 |
| [视频卡悬停预览](validation/video-card-hover.md) | 官方客户端式封面放大、悬停视频自动播放、稍后再看与网页接口核对 |
| [视频卡操作菜单](validation/video-card-menus.md) | 推荐反馈、添加稍后再看、删除稍后再看及悬停入口范围 |
| [稍后再看队列播放](validation/watch-later-queue.md) | 列表上下文、分 P 与队列推进、侧栏和账号/标签隔离 |
| [收藏子标签与视频卡片](validation/favorites-tabs.md) | 五类收藏入口、公共视频卡、自建收藏夹状态/日期与信息编辑、Windows 验证边界 |
| [收藏与订阅取消操作](validation/favorites-unsubscribe.md) | 卡片三点菜单、取消前确认、CSRF 单次提交与分页/账号竞态 |
| [媒体包验证](validation/media-packages.md) | 包契约、限制、原生资产来源 |
| [播放器预读窗口](validation/player-buffer-ahead.md) | 普通播放最多 5 分钟、悬停预览 5 秒、内存限额和 Windows 原生验证 |
| [弹幕顶部距离](validation/danmaku-top-margin.md) | 默认 0、两处配置入口、点播／直播区域计算和旧设置兼容 |
| [弹幕行距](validation/danmaku-line-spacing.md) | 行间空白从 0 起调节、默认 5、点播／直播布局与持久化 |
| [弹幕样式与过滤配置](validation/danmaku-style-settings.md) | 字体/加粗/效果、时间偏移、重复合并、同屏密度与本地过滤 |
| [全屏弹幕保留](validation/danmaku-fullscreen.md) | 点播视口变更保留活动弹幕、调度游标和滚动进度，Windows 全屏回归 |
| [弹幕速度与播放倍速](validation/danmaku-playback-rate.md) | 按播放时间加载／触发，独立动画时间控制滚动和停留，暂停／seek／时间窗回归 |
| [播放错误排查](validation/native-playback-errors.md) | 原生日志误判、错误态控制栏与本地脱敏日志 |
| [开发协作约定](../AGENTS.md) | 后续开发与自动化代理必须遵守的仓库规则 |

## 如何理解方案中的结论

- **方案决定**：本项目接下来采用的组织方式，不代表代码已实现。
- **源码事实**：已查看两个本地参考仓库；提交快照见参考文档。
- **外部能力说明**：已查阅框架和包维护方文档；不等于项目中的三端验收结果。
- **实测边界**：Windows 游客点播和部分公开 API 已实测；登录后的完整流程、其他平台运行与性能预算仍待验证，逐项结果以首版实测记录为准。

架构文档中的完整目录树和性能预算仍是目标设计；当前仅创建实际用到的功能。已实现 API/播放器契约以各包公共入口为准，重要差异记录在架构决策和实测记录中。

后续从 [M0 技术验证](implementation-plan.md#m0技术验证) 的未验项目继续，特别是 Android/macOS 原生播放与真实登录；首版已经提供 Windows 观看闭环。


# BiliSail（哔帆）项目宣传视频 · 第三版

制作日期：2026-10-30。基于仓库既有 `promo-video/` Remotion 工程更新，面向首次了解项目的观众。

## 创作方向

- 主线：发现内容 → 自由浏览 → 视频与音频观看 → 番剧直播 → 评论动态 → 个人内容 → 离线下载 → 个性化。
- 成片：72 秒，1920 × 1080，30 fps；短中文字幕、原创器乐，无人声。每节围绕一个使用场景，避免把平台名和设置项堆成清单。
- 保留上一版的晴湾配色、HarmonyOS Sans 字体、品牌图标和《Sail Light》配乐。转场仍为 0.2 秒淡化；原音轨不变速，使用前 72 秒并在最后 1.5 秒淡出。
- 平台信息集中到开场和片尾，不再为 Windows / MacOS 重复演示共享桌面布局。新增听视频、评论动态、历史收藏三节；导航整合为单／双／多标签一节。

## 分镜与字幕

时间为主时间线的章节切入点；各节有 0.2 秒重叠转场。

| 时间 | 章节 / 主标题 | 这节的重点 | 画面与字幕 |
| --- | --- | --- | --- |
| 00:00–00:04 | 品牌开场 / 让观看更自在 | Bilibili 第三方客户端；桌面与移动端界面 | 新采集桌面首页与用户提供的移动端首页；品牌和五平台文字进入 |
| 00:04–00:11 | 发现内容 / 从好奇，到喜欢。 | 每周必看 · 排行榜；番剧 · 国创 · 放映厅；卡片悬停预览 | `home.png` → `popular.png`；“从推荐出发，也可以直达每周必看与排行榜” / “搜索视频、番剧、直播和 UP 主” |
| 00:11–00:18 | 浏览与播放 / 来回切换，接着看。 | 单标签 · 按访问顺序返回；双标签 · 桌面独立播放窗；多标签 · 保留页面状态 | `navigation.png` → `workspace.png`；“单、双、多标签，让浏览方式跟着习惯走” / “列表位置与播放会话，在切换间保留” |
| 00:18–00:26 | 播放与弹幕 / 观看节奏，由你掌握。 | 清晰度 · 编码 · CDN；倍速 · 分 P · 连续播放；弹幕样式 · 密度 · 过滤 | `playback.png` → `danmaku.png`；“清晰度、倍速与连续播放，按自己的节奏观看” / “弹幕样式、密度和过滤，也可以细调” |
| 00:26–00:32 | 听视频 / 换个方式，继续听。 | 同一进度 · 随时返回视频；音频控件 · 倍速与跳转；有字幕时 · 歌词式阅读 | `listening.png` → `listening.png`；“切到听视频，让内容陪你继续” / “保留进度与倍速，有字幕时还能跟着读” |
| 00:32–00:39 | 番剧与直播 / 追下一集，也看此刻。 | 番剧 · 国创 · 影视选集；直播清晰度 · 流与线路；实时聊天 · 弹幕 · SC | `pgc.png` → `live.png`；“番剧、国创与影视，选好下一集” / “进入直播间，看看实时聊天与画面弹幕” |
| 00:39–00:45 | 评论与动态 / 看到精彩，聊得尽兴。 | 热门 / 最新 · 楼中楼；表情 · 图片 · 时间点；动态分类 · UP 主空间 | `comments.png` → `dynamic.png`；“评论、楼中楼与图片，让交流更完整” / “动态与 UP 主空间，继续发现感兴趣的内容” |
| 00:45–00:51 | 历史与收藏 / 喜欢的内容，随时找回。 | 云端历史 · 本地续播；稍后再看 · 收藏夹；追番追剧 · 消息与私信 | `library.png` → `library.png`；“历史、稍后再看与收藏，集中在我的页面” / “本地记住进度，登录后补充云端续播” |
| 00:51–00:58 | 下载与离线 / 提前备好，离线也看。 | 多选下载 · 队列管理；分轨 / MP4 / MKV；离线弹幕 · 字幕 | `download-dialog.png` → `download-formats.png`；“多选分 P 与剧集，选择画质、编码和保存格式” / “暂停、继续与离线播放，按自己的安排就绪” |
| 00:58–01:05 | 按你的习惯 / 看着舒服，用着顺手。 | 明暗主题 · 内置 / 系统字体；键盘快捷键 · 鼠标侧键；播放偏好 · 弹幕与字幕 | `appearance.png` → `appearance-dark.png` → `shortcuts.png`；“主题与字体，调成喜欢的样子” / “快捷键和鼠标侧键，让常用操作更顺手” |
| 01:05–01:12 | 品牌收尾 / BiliSail · 哔帆 | 项目地址和下载入口 | Windows · MacOS · Android · iOS · Linux；iOS 需自行签名；GitHub · CKopoer/BiliSail |

## 内容核对与表达边界

| 内容 | 当前依据 |
| --- | --- |
| 发现与搜索 | [README 功能概览](../../README.md#功能概览)、当前首页和搜索界面 |
| 导航模式与状态保留 | [单标签导航](../validation/single-page-navigation.md)、[多标签播放](../validation/multi-tab-playback.md)、`lib/app/platform_defaults.dart` |
| 播放与弹幕 | [播放设计](../playback-and-danmaku.md)、[连续播放](../validation/continuous-playback.md) |
| 听视频与歌词字幕 | [听视频](../validation/listen-video.md)、[歌词字幕](../validation/listening-subtitle-lyrics-2026-10-30.md) |
| 番剧与直播 | [内容播放](../validation/content-playback.md)、[直播流选择](../validation/live-stream-audio-preferences-2026-10-30.md) |
| 评论与动态 | [视频评论](../validation/video-comments.md)、[动态互动](../validation/dynamic-interactions.md) |
| 历史与续播 | [云端历史](../validation/cloud-watch-history.md)、[云端进度](../validation/cloud-playback-progress.md) |
| 下载离线 | [下载方案](../downloads.md)、[封装验证](../validation/download-muxing-results.md) |
| 字体与快捷键 | [字体选择](../validation/font-selection.md)、[快捷键](../shortcut-system/implementation-results.md) |
| 平台状态 | [整体架构](../architecture.md)、[CI/CD](../validation/ci-cd.md)、[iOS / Linux](../validation/ios-linux.md) |

听视频仅适用于提供独立音轨的内容；歌词式阅读依赖可用字幕。清晰度、音轨、剧集与直播流选项以账号权限和服务端实际返回为准。影片不宣称全平台实机已验收，也不把听视频等同于后台、锁屏或 PiP 验收，不给出未测量的性能提升数字。

## 素材与交付

重新采集的素材放在 `promo-video/public/screens/2026-10-30/`；原版素材保留。每张素材的来源、采集环境和处理见 `promo-video/ASSETS.md`。移动端画面按用户后续要求统一替换为本次提供的 1080 × 2400 首页 JPG，原样复制，用于开场与两种封面；原 Windows 窄屏素材保留。本轮没有连接 Android 设备进行补拍，不使用 Windows 画面伪装 MacOS 实拍。

只浏览内容、播放器与下载选择界面，不发送评论／私信／弹幕，不点赞、投币、关注或创建下载任务。私信正文不进入镜头；个人内容镜头只展示入口，不暴露完整历史列表。临时修改的导航和主题已恢复为采集前的单标签、跟随系统；采集窗口保留在窄屏首页。

已交付：第三版 MP4、字幕 SRT、16:9 与 4:3 封面、可继续编辑的 Remotion 工程，以及本脚本。文件输出在 `promo-video/out/`，不自动上传发布。最终采集、导出与验证结果见工程 README。


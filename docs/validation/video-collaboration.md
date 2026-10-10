# 合作视频创作团队

日期：2026-10-10。

## 行为与数据链路

普通视频保留现有 UP 主资料栏；Web 详情含非空 `staff` 时，简介顶部改为“创作团队 N 人”。成员按接口顺序显示头像、昵称和角色，不重复追加 `owner`；常规桌面侧栏默认显示一行五人，点击标题栏展开全部成员，再次点击收起。列数根据实际宽度与文字缩放计算，窄屏／大字号自然换行，长昵称和角色可悬停查看全文。

头像和昵称使用服务端 UID 打开已有用户主页。缺少／无效 UID 的成员仍显示署名，不生成可点击身份或关注请求。头像右下角的圆形关注入口复用 [UserFollowButton](../../lib/shared/ui/user_follow_button.dart) 和既有作者控制器，已关注菜单继续提供设置分组／取消关注；游客打开登录入口，本人隐藏按钮，忙碌时禁用，结果不确定时先刷新状态。账号 scope、session epoch、取消与未知结果处理继续由共享控制器负责。

协议解析在 `bili_api`，Repository 映射为纯 Dart `VideoStaffMember`，页面只消费领域成员和共享关注组件。合作团队展开不改变播放源、分 P、进度或播放器实例；未增加依赖、原生播放器修改或新的写接口。

## 接口与来源

| 项目 | 约束 |
| --- | --- |
| 端点 | `api.bilibili.com` GET `/x/web-interface/view?bvid=…`，沿用 `video_detail` Web profile |
| 鉴权／签名 | Cookie 可选；无 App token、WBI 或 CSRF；公开署名可用游客读取 |
| 响应 | JSON `data.staff[]`：`mid`、`name`、`title`、`face`、`label_style`、`vip.nickname_color` |
| 身份 | 正整数或十进制字符串保留为字符串；不接受浮点数、零、负数或包含参数的文本 |
| 展示 | `title` 原样展示；`label_style=1` 使用金色角色标签；合法六位十六进制昵称颜色生效，其余使用主题文字颜色 |
| 缺省／容量 | 缺失、null、空列表保持普通作者栏；可选成员属性独立降级；最多 100 人，非列表／非对象结构报告协议错误 |
| 分页／重试 | 无分页；沿用现有详情的总 deadline、取消、session epoch 和有界只读重试 |

只读参考 biliuwp-lite 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [VideoAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/VideoAPI.cs)、[VideoDetailStaffModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Video/Detail/VideoDetailStaffModel.cs)、[VideoDetailViewModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Video/VideoDetailViewModel.cs) 与 [VideoDetailPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/VideoDetailPage.xaml)，用于确认 Web 详情、合作成员字段与独立关系操作。仅采用协议事实和职责，Dart／Flutter 代码独立编写；没有复制 C#、XAML、schema、图片、字体或其他资源，不扩大参考项目许可范围。

**视觉参考为正式“哔哩哔哩”桌面客户端，路径 `C:\Program Files\bilibili\哔哩哔哩.exe`，不是哔哩哔哩 UWP。** 本轮实际打开样本 `BV1C4Hx6KEvf`，核对“创作团队 7 人”、一行五人、角色角标、赞助商金色标签、昵称与头像关注入口；布局由 Flutter 独立实现，未复制客户端资源。

## 验证

- 游客只读 [video_staff_smoke.dart](../../packages/bili_api/tool/video_staff_smoke.dart) 在线通过：上述样本返回 7 位成员、7 个合法 UID、7 个头像、1 个强调角色；角色为 UP主、赞助商和五位参演者。仅此样本当次接口观察，无账号 Cookie，不执行真实关注或其他账户写操作。
- [API 回归](../../packages/bili_api/test/video_staff_test.dart) 5 项通过：成员顺序、长 UID、角色／头像／昵称颜色、缺省字段、无效身份、容量和结构错误。
- [Repository 回归](../../test/features/video/api_video_staff_repository_test.dart) 验证字段进入领域层、无身份猜测和不可变列表。[组件／播放页回归](../../test/features/video/video_staff_panel_test.dart) 覆盖明暗主题、展开／收起、精确 UID 主页跳转、单次关注与取消关注、游客登录、缺失身份、普通作者栏和 220／390／1100 逻辑像素宽度下两倍字号的布局及播放器保留。既有作者控制器和播放页测试一同通过，初轮共 34 项定向回归。
- Flutter 控件渲染已检查明暗主题；布局预览位于忽略目录 `build/video-staff-preview/`，为占位头像和 fake 仓储的组件预览。
- `tool/check.ps1 -SkipPub` 全量通过：根应用 1612、API 350、播放器 32、弹幕 72、封装包 2 项，共 2068 项；根应用和四个包的格式／静态分析均通过。封装包 7 项真实 native 测试因未设置 `BILI_MUX_LIBRARY` 按原规则跳过，本任务未修改封装或原生媒体代码。日志 `build/video-staff-check.log`；最终团队预览回归 7 项再次通过，日志 `build/video-staff-preview.log`。

未构建应用或执行本轮 BiliSail 原生窗口验收；未执行真实账号关注／取消关注；Android／macOS 未实机验证。组件布局检查与游客接口读取不代表三端原生播放验收。

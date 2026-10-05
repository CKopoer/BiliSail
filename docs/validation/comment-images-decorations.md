# 评论图片预览与作者装扮

日期：2026-10-06。本轮按用户提供的 UWP 评论截图调整；装扮指用户名右侧的图片与 `NO.` 粉丝编号，编号不作为账号等级或粉丝勋章等级处理。

## 展示与协议

- 评论图片与首页／空间动态共用 [图片预览组件](../../lib/shared/ui/image_viewer.dart)。点击第几张就从第几张打开，支持整组图片切换、缩放、原始大小、适应窗口和键盘关闭；原图额度、取消、账号变化及迟到响应隔离沿用既有图片控制器与仓储。列表缩略图使用共享公开图片提供器，原图地址保留在领域模型中。
- 共用预览视图从 `features/image_viewer/presentation` 移到 `shared/ui`，避免视频 Feature 导入另一 Feature 的 presentation；原图加载、应用状态与领域契约仍位于 `features/image_viewer`。
- 评论的 `member.user_sailing.cardbg.image` 用于作者右侧装扮，`cardbg.fan.num_desc` 原样保留为字符串并显示为 `NO.` 编号，`fan.color` 控制编号颜色。`cardbg.name` 只用于无障碍说明，不以普通文字替代图片。账号等级继续使用现有等级图片；`fans_detail` 的粉丝勋章展示保持既有行为。
- 根评论与楼中楼详情共用作者头部；宽度足够时装扮位于用户名／日期右侧，窄窗口移至下一行靠右。缺少装扮图片时不占用装扮区域，缺少编号时只显示图片；图片失败时不改为显示装扮名称，已有编号保留。
- 沿用 `/x/v2/reply` 与 `/x/v2/reply/reply`，没有新增端点、依赖或账号写入。可选字段形态异常不影响评论正文；图片使用既有 HTTPS、凭据与端口校验，编号颜色只接受有界 24-bit RGB（整数、十进制字符串、六位十六进制字符串）。

## 来源与验证边界

只读查看 `biliuwp-lite` 的 [CommentControl.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Controls/CommentControl.xaml)、[成员模型](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Comment/CommentMemberModel.cs)、[装扮模型](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Comment/CommentMemberUserSailingCardbgModel.cs)、[粉丝编号模型](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Comment/CommentMemberUserSailingCardbgFanModel.cs) 和 [颜色转换](../../../biliuwp-lite/src/BiliLite.UWP/Converters/ColorConvert.cs)。参考图片、编号及布局职责，自行编写 Dart／Flutter；没有复制新的上游源码、字体或图片，远端装扮按评论响应加载。参考快照与许可限制沿用 [参考文档](../references.md)。

回归覆盖评论可选装扮字段、非法图片与颜色、编号前导零、回复字段解析、点赞／回复复制保留装扮、两倍字号下的窄／宽头部布局，以及点击中间评论图片后切图、缩放、关闭和加载失败。动态图片和原图预览原有回归一并执行。

`tool/check.ps1 -SkipPub` 完整通过：当前工作区根应用 525、`bili_api` 172、`bili_player` 16、`bili_danmaku` 10 项，合计 723 项；四处格式检查与静态分析均通过。日志保存在本机忽略目录 `artifacts/comment-images-decorations-check.log`。检查覆盖工作区已有修改，计数不是本轮新增测试数量。

本次不使用真实账号执行点赞、发送或其他写入。在线装扮样本与 Windows／Android／macOS 实机显示尚未在本轮验证；组件与脱敏协议测试不等于三端实机验收。

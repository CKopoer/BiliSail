# 评论图片预览与作者装扮

2026-10-25 新增共用查看器保存／复制与长图支持，目录、限额、平台实现和验证边界见[图片查看器保存、复制与长图](image-viewer-export-long-images.md)。

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

## 2026-10-25 双标签独立播放窗的图片预览

双标签播放窗口启用固定 Flutter 3.47.6 的实验多窗口机制后，SDK 的 `showDialog` 会经 `showRawDialog` 创建独立原生对话窗口。共享入口现改为直接向当前 Navigator 推入 `DialogRoute`，继续使用同一 `ImageViewer`，在所属窗口内覆盖显示；保留主题、焦点循环、切图、缩放、背景点击和 Esc 关闭行为。评论、首页／空间动态仍共用同一入口。

[双窗口回归](../../test/app/workspace_image_viewer_test.dart) 启用 SDK 多窗口开关，用 fake 次级 view 和原图仓储点击评论第二张图片，核对查看器仍属于播放 view／Navigator、浏览窗不增加路由、不注册原生对话窗口；切图和缩放正常，原生标题栏返回被模态隔离，Esc 仅关闭图片且保留原页面与播放窗口。旧实现已复现原生对话框创建路径及查看器落到主 view 的失败。此测试使用真实 Flutter 组件和模拟窗口，不代表 Windows／macOS 原生窗口实测。

本轮 `tool/check.ps1 -SkipPub` 完整通过：根应用 2,209、`bili_api` 446、`bili_player` 81、`bili_danmaku` 93、`bili_mux` 2 项，共 2,831 项；五处格式、静态分析和打包边界检查通过。mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志为本机忽略目录 `build/validation/image-viewer-window-check.log`。未构建或执行三端实机验收；DTD 未发现运行中的调试应用，热重载因无连接未能执行。

## 2026-10-25 双标签原图加载状态修复

原图已读完仍显示“正在加载原图…”的原因是 `DialogRoute.builder` 每次执行都会创建新的 `ImageViewerRequest`。该对象同时作为 family provider 的身份，而查看器只在 `initState` 中启动首次加载。播放窗口触发路由页面重建时，查看器 State 沿用，订阅却切到另一个初始加载态的控制器，原请求的完成结果无法显示；手动切图会对当前控制器调用 `load`，因此切走再切回能够恢复。

共享入口现于推入路由前创建请求，同一次预览的路由重建始终沿用该身份。加载中的读取、已完成图片、当前图片序号和缩放状态均可保留，关闭与账号变化的取消边界仍由原控制器管理。

[双窗口回归](../../test/app/workspace_image_viewer_test.dart) 使用可手动完成的原图仓储，分别覆盖单图／多图在加载中及完成后触发 `ModalRoute.changedExternalState`，断言原读取不被取消、无需切图即可显示原图、不会额外下载；继续检查所属 view／Navigator、缩放、切图、原生返回隔离与 Esc 关闭。旧代码在路由重建后已复现加载提示重新出现的断言失败；固定请求身份后，这 4 项及原图控制器、普通宽／窄屏查看器和评论富内容的共 25 项定向测试通过。

本次 `tool/check.ps1 -SkipPub` 首次被同期改动的 `test/app/comment_detail_navigation_test.dart` 格式检查阻断；后续全根目录格式复查通过，根应用与四个包的静态分析、四包格式及测试、打包边界脚本通过。根应用全量测试为 2,216 项通过、2 项失败：同期新增的桌面双标签视频／PGC 评论详情模态测试找不到“评论详情”文本，均位于该文件，本任务未修改它。四包分别为 446／81／93／2 项通过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志保存在本机忽略目录 `build/validation/image-viewer-loading-{check,root-format,root-analyze,root-tests,packages}.log`，未将全量检查记为通过。

本次未构建或执行 Windows／Android／macOS 实机验收。DTD 未发现运行中的调试应用，热重载调用因无活动连接未能执行；上述双窗口验证使用真实 Flutter 组件与 fake view，不代表真实原生窗口验收。

## 2026-11-11 与 PiliPlus 对齐装扮显示（issue #113）

基线 `01e2df8b41272130aca8c5ba1efe87f3c461e554`，对应 [issue #113](https://github.com/CKopoer/BiliSail/issues/113)。只读核对 PiliPlus `cab0114a21ce7fad5b90b9a4d788d35d313d25f9` 的 [评论头部](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/pages/video/reply/widgets/reply_item_grpc.dart)、[头像挂件](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/cab0114a21ce7fad5b90b9a4d788d35d313d25f9/lib/common/widgets/pendant_avatar.dart)、`lib/utils/image_utils.dart` 和 `lib/utils/extension/num_ext.dart`。独立修改现有组件；未复制其 GPLv3 源码、图片或数字字体，未新增依赖。编号使用应用现有字体的粗体和等宽数字特性。

旧评论组件将带透明留白的装扮画布转为 336×120 缩略图，再用 `BoxFit.cover` 和 40 像素偏移裁剪，图片与编号位置也与参考相反。现通过 [UserDecorationImage](../../lib/shared/ui/user_decoration_image.dart) 加载原始图片，保留透明画布，以 38 逻辑像素高度、单一物理高度解码，按屏幕 DPI 向上取整；编号以 8 号字叠在画布右侧。原有窄屏换行、编号前导零、颜色、无障碍标签和加载失败处理继续保留。视频、PGC、动态评论和楼中楼使用同一共享评论组件。

头像框统一由 [NetworkAvatar](../../lib/shared/ui/network_avatar.dart) 处理：有挂件时头像直径相对占位缩小 6 像素，挂件画布为头像的 1.75 倍，居中绘制，挂件不截获点击。个人空间原 64 像素头像的挂件画布从 88 调整为 112；评论与首页／空间／转发动态补齐挂件字段。优先使用安全的 `image_enhance`，缺失或非法时回退到 `image`；点赞与楼中楼更新保留装扮信息。纯布局测量不请求动态挂件。

回归验证使用自行生成的 1800×300（6∶1）透明 PNG，检查 1／1.25／3／4 倍 DPI 下实际解码尺寸、画布宽高比、透明左边距、编号左侧的不透明图案和右侧透明区，以及编号位置。另覆盖挂件比例与点击、放大字号的窄／宽评论、缺失字段、增强图片回退、评论复制、直接及转发动态的字段解析和共享映射。

匿名只读请求 `/x/v2/reply?type=1&oid=170001&sort=2&ps=20&pn=1` 返回成功，取得一张 972×162 的真实装扮画布，确认装扮素材存在大幅透明留白；原图仅用于本地核对，未提交用户内容或图片。

使用固定 Flutter 3.47.6／Dart 3.13.5，五份锁文件的 `pub get --enforce-lockfile` 均通过。按 `tool/check.ps1` 的三个阶段执行：`-Stage Lint -SkipPub`、`-Stage RootTests -SkipPub`、`-Stage PackageTests -SkipPub` 全部通过。根应用 **5,082**，`bili_api` **852**、`bili_player` **372**、`bili_danmaku` **161**、`bili_mux` **5**，合计 **6,472 项通过**；格式、静态分析和打包边界检查通过。根应用 6 项按环境条件跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生覆盖。

云环境最初缺少 Flutter、Clang、PowerShell 和 CMake，已在用户目录准备工具，未修改 SDK／Pub 缓存源码。初次完整检查的 macOS 子进程终止用例被云容器 PID 1 遗留的僵尸子进程阻塞；为测试入口增加会话临时 subreaper，真实回收孤儿进程后，同一未修改的检查脚本通过。该辅助入口仅用于本次环境，不属于应用修改。

未进行 Windows／Android／macOS 实机验收或真实账号写入。

## 2026-11-12 窄屏评论装扮与头像对齐

动态详情、视频／影视评论与完整楼中楼回复复用 `CommentsPanel` 和 `CommentAuthorHeader`。原作者栏在扣除头像、间距和面板内边距后，以剩余宽度是否达到 300 逻辑像素决定横排或换行，导致手机上仍有空间时也把装扮放到昵称和 IP 属地下方，再次撑高正文前的留白。

共享作者栏现始终顶部横排：装扮预留不超过间距后可用宽度的 40%，上限 112 逻辑像素，剩余空间由昵称、徽章及时间／IP 信息自然换行。装扮与粉丝编号一起等比缩小，去掉原 152 像素占位中多余的 40 像素；原始透明画布的比例、右侧编号、前导零、颜色和无障碍标签保持。

回归覆盖 180／220／260／299／320 宽度的作者栏和两倍字号，以及 320／360／600 宽度的真实动态详情组件，检查装扮、头像与昵称顶部对齐，作者文字不与装扮占位重叠，正文位于头部下方。修改前的动态详情在 320／360 宽度均复现装扮下移 35 逻辑像素；600 宽度正常。最终 103 项定向测试通过，包含真实字体下的视频／动态评论行、昵称与 VIP 徽章、楼中楼、原图比例和解码 DPI 回归。

固定 Flutter 3.47.6／Dart 3.13.5，五份锁文件严格解析通过。`tool/check.ps1 -Stage Lint -SkipPub` 和 `-Stage PackageTests -SkipPub` 通过；四包分别为 911／398／161／5 项通过。根应用全量运行有 5,252 项通过、6 项按环境跳过，另 2 项既有窄屏测试仍要求装扮保持 52 像素并位于元数据下方，因本次行为调整失败。只将这些旧断言更新为顶部同排、宽度有界且等比缩放后，上述 103 项相关测试全部复测通过，运行代码未再次变更；未重复运行其余已通过的根应用用例。最终格式与静态分析复查通过。

日志位于忽略目录 `build/validation/comment-decoration-*.log`。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过；未构建安装包或执行手机／桌面实机验收。

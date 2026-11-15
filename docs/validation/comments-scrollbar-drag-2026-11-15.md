# 评论区滚动条拖动跳变修复

日期：2026-11-15。覆盖视频、影视和动态共享 `CommentsPanel` 的主评论、楼中楼和通知定位回复。

## 原因与修复

原列表使用 `ListView.builder`，Flutter 根据当前已布局行的平均高度估算总长。评论正文、装扮、图片和回复预览高度差异较大；拖动右侧滚动条进入另一组评论后，总长变化，滑块位置和鼠标位移到内容距离的映射随之改变。

离线 150 条长短混排评论的鼠标拖动回归中，修复前主评论的 `maxScrollExtent` 从 29,556 变为 59,260；楼中楼从约 17,730.86 变为 36,768。测试仅说明几何变化，不是性能测量。

- 新增共享 `MeasuredListView`：按当前宽度与文字环境测量每个已加载行，向列表同时提供逐行高度及总高度，滚动范围不再使用可见行均值。高度取自然布局结果，不统一限制评论行高。
- 测量复用动态列表已有的离屏布局实现，提取为 `WidgetMeasurement`。只缓存当前列表中的数据身份和数字高度；分页复用未变评论的测量，宽度、文字缩放、主题或系统字体改变后重新测量。输入框或键盘仅改变视口高度时，复用原列表和测量。
- 测量态使用同一评论布局，头像、装扮、行内表情和评论图片使用等尺寸空白，不创建图片请求、文本选择和正文点击识别器。表情加载失败也保留 28×28 的位置，避免回退文字改变行高。
- 实际评论仍按视口懒创建，保持分页、主评论位置恢复、详情独立滚动及关闭释放行为；沿用既有 500 条数据容量，不保留全列表交互组件。

实现：[评论面板](../../lib/shared/ui/comments_panel.dart)、[列表测量](../../lib/shared/ui/measured_list_view.dart)、[离屏测量](../../lib/shared/ui/widget_measurement.dart)、[富评论内容](../../lib/shared/ui/comment_rich_content.dart)。

## 验证

- [滚动条回归](../../test/shared/ui/comments_scrollbar_test.dart)：主评论及楼中楼真实鼠标按下滑块后连续上下移动，滚动方向正确，总范围误差小于 0.01 逻辑像素，交互组件按视口释放；宽度及字号变化更新范围，仍可正确到达末尾。
- 媒体回归验证离屏测量不会加载全部评论图片，并在卸载后取消未完成请求。
- 自动分页、视频／影视嵌套滚动与动态列表测量保留回归通过。
- 六个相关测试文件最终合并运行共 113 项通过，包含评论 controller、富内容、500 条列表释放和本轮新增的 4 项回归；最终静态分析无问题。日志：`build/comments-scrollbar-final-targeted.log`、`build/comments-scrollbar-final-analyze.log`。
- 已运行离线 Flutter test device 评论入口，通过 DTD 执行热重载，运行错误查询为空；这不属于 Windows 桌面鼠标实测。

- `tool/check.ps1 -SkipPub`：格式、静态分析及打包边界检查通过；根应用 5,626 项通过、13 项跳过、12 项失败。本次评论回归均通过，另有以下未改动路径的滚轮距离断言失败，因此不将全量检查记为通过：

  | 路径 | 失败数量 | 观察 |
  | --- | ---: | --- |
  | `test/features/live/live_screen_test.dart` | 4 | 滚动 24／120 的断言得到 48／240 |
  | `test/features/pgc/pgc_episode_panel_test.dart` | 1 | 分组横向滚轮期望 130，得到约 212.3 |
  | `test/features/profile/profile_swipe_test.dart` | 7 | 普通／减少动画滚轮距离与现有断言不一致 |

- `tool/check.ps1 -SkipPub -Stage PackageTests` 通过：`bili_api` 997 项、`bili_player` 356 项、`bili_danmaku` 161 项、`bili_mux` 5 项。播放器 3 项原生用例因缺少 `BILI_TEST_NATIVE_MPV`／`BILI_TEST_MEDIA_DIR` 跳过，mux 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，均不算原生验证通过。

日志：`build/comments-scrollbar-full-check-2026-11-15.log`、`build/comments-scrollbar-package-check-2026-11-15.log`。未生成安装包、进行账号写入或真实设备性能测量。

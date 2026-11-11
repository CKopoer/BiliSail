# 评论正文文字样式复核

日期：2026-11-11。

## 对照依据与结论

重新只读核对本机官方 Windows 客户端 **1.13.0.3194** 的 `C:\Program Files\bilibili\resources\app.asar` 内的 `render/assets/index.a27d27c1.css`，使用客户端专用的 `.reply-item-client`、`.reply-content-client`、`.sub-reply-item-client` 和 `.bili-comment.client` 规则，不混用同包内的网页评论样式。对照依据及此前调整见[官方客户端文字排版](official-client-typography-2026-11-09.md)。本次安装包 SHA-256 为 `11564436E8325ADBCAB4FD820EFED99A48CDE897501C7323C4B42678BD95E17B`；未复制或分发官方代码和资源。

[共享正文样式](../../lib/shared/ui/comment_text_styles.dart)及[评论组件](../../lib/shared/ui/comment_rich_content.dart)已经保留此前对齐结果，本次不改动已一致的参数：

| 角色 | 字号 / 字重 / 行高 | 颜色 |
| --- | --- | --- |
| 主评论、详情内完整回复 | 15 / 400 / 25 | 浅色 `#18191C`，深色 `#E7E9EB` |
| 楼中楼预览正文 | 14 / 400 / 20 | 同上 |
| 正文链接、时间点和可点击的 @用户 | 继承所在正文的字号、字重和行高 | 浅色 `#008AC5`，深色 `#2C9CC8` |

保留用户选择的界面字体；默认继续使用应用内置的 HarmonyOS Sans。评论原有零字距保持，其他组件继承的 Material 默认字距及“共 X 条回复”的主题色保持原样。

额外复核了行高留白。Flutter 通用默认值为按字体升部／降部比例分配，但本项目使用的 Material 3 `bodyMedium` 已指定 `TextLeadingDistribution.even`，正文的 `copyWith` 会保留它，因此当前已采用 CSS 的上下均分方式。使用真实字体测量的首行基线和三行正文总高度均符合该配置，无需重复设置或修改字号、加粗正文。

## 验证

新增[正文渲染回归](../../test/shared/ui/comment_body_typography_test.dart)，覆盖主评论／楼中楼预览、浅／深主题和普通／双倍文字缩放八种组合。实际加载应用的 HarmonyOS Sans Regular，检查渲染段落的字体、字号、字重、颜色、字距、多行总高度及相对自然字体度量的基线；同时验证链接不覆盖正文的字号／字重，并实际点击 @用户、时间点和 URL，保留文字选择能力。

八项定向回归通过。固定 Flutter 3.47.6／Dart 3.13.5 下，`tool/check.ps1 -SkipPub` 的 Lint、RootTests、PackageTests 三阶段全部通过：根应用 5,138 项，`bili_api` 861 项、`bili_player` 372 项、`bili_danmaku` 161 项、`bili_mux` 5 项，共 6,537 项通过。格式、静态分析及打包边界检查通过；根应用 13 项按既有环境条件跳过，mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生验证。

日志位于本机 `build/validation/comment-body-typography-2026-11-11/`，包括 `body-tests.log`、`Lint.log`、`RootTests.log` 和 `PackageTests.log`。本节及关联记录的本地链接检查、`git diff --check` 通过。本次仅新增正文渲染回归和文档，未修改应用的视觉参数。

未重新构建、安装或执行官方客户端与 Flutter 的逐像素视觉比较；不同渲染引擎的字形栅格化差异不在本次结论内。未发现运行中的 Dart／DTD 调试进程，已尝试热重载，无法连接。

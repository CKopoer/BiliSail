# 独立话题页与动态发布

日期：2026-11-10。按用户要求，将话题页从工作区通用搜索／频道栏中独立出来，提供页内返回、发起人、收藏、举报与参与入口；动态／视频动态列表和自己的空间动态共用发布组件。保留工作区页面身份和访问历史，不构建应用、不操作真实设备。

## 参考与页面组合

只读核对 PiliPlus `4fce4bb5a35c425aee759ef9263352316a29e355` 的 `lib/pages/dynamics_topic/{view,controller}.dart`、`lib/pages/dynamics_create/view.dart`、`lib/pages/common/publish/common_rich_text_pub_page.dart`、`lib/pages/dynamics_select_topic/` 和 `lib/http/{api,dynamics,fav,search}.dart`。借鉴话题头部职责、发布图片元数据和话题关联字段，独立实现；未复制 GPLv3 应用代码、资源，未修改相邻仓库或依赖。

话题页沿用空间页的工作区组合规则：不显示通用搜索栏、频道条和窄屏底部导航；桌面窗口及标签容器保持工作区所有权。页内返回在单／双标签沿历史返回，多标签关闭当前临时页。发起人头像与名称可进入空间；话题名称、简介、统计、排序和动态列表仍使用已有协议与共享卡片。

收藏初值读取 `topic_item.is_fav/fav`，成功提交后才更新状态和计数。操作串行，结果不明确时锁定收藏写入，成功刷新简介后重新核对。举报使用应用内理由与说明表单，只有点击提交才发送；成功或结果不明时均阻止重复举报。游客入口请求登录。

## 协议登记

PiliPlus 使用官方 H5 举报页。另只读获取[官方话题举报页](https://www.bilibili.com/h5/topic-active/topic-report)及其公开脚本，核对 `/x/topic/report` 的字符串理由参数。脚本版本 `ce1ff5aebaac2ede0b09c510e26c23c9f36f2533`，主脚本 SHA-256 `a70101572f766bba6b586b1829669d7b3aa3ed06a6590f794727fdb5adbd01c6`；只记录协议事实，没有将脚本代码或资源纳入工程。

| Profile | Host / method / path | 鉴权、响应与边界 |
| --- | --- | --- |
| dynamic_compose_topics | app.bilibili.com GET `/x/topic/pub/search` | Cookie JSON；`keywords/content/page_size=20/page_num=1/web_location`，最多20个候选，允许空关键词；显式搜索替换旧请求，共用有界只读重试 |
| dynamic_picture_upload | api.bilibili.com POST `/x/dynamic/feed/draw/upload_bfs` | Web Cookie + multipart CSRF；`category=daily/biz=new_dyn` 与 `file_up`；JSON 图片 URL／宽高；单次尝试 |
| dynamic_publish | api.bilibili.com POST `/x/dynamic/feed/create/dyn` | Web Cookie + query `platform=web/csrf`；JSON `dyn_req`，纯文字 scene=1、图文 scene=2，话题 ID／名称、图片元数据、upload_id 与 Web meta；读取 `dyn_id_str/dyn_id`，不重放 |
| dynamic_topic_favorite | api.bilibili.com POST `/x/topic/fav/sub/add` 或 `/cancel` | Web Cookie + form CSRF；`topic_id`，JSON code 信封；显式单次写 |
| dynamic_topic_report | api.bilibili.com POST `/x/topic/report` | Web Cookie + form CSRF；`topic_id/reason`，理由是字符串；JSON code 信封，显式单次写 |

`app.bilibili.com` 的 Web 白名单只增加上述具体搜索路径。图片上传响应须为无 query／凭据的 HTTPS 图片 CDN 地址，并校验尺寸；提交前再次检查图片身份与元数据。参考接口及公开 H5 可读取不代表这些账号写接口已做真实在线验证。

## 发布状态与容量

- 共用一个按账号／session epoch 隔离的内存草稿；关闭编辑器保留正文、图片和话题，清空或发布成功后释放，账号变化取消请求并清除草稿，不落盘。话题参与入口预选当前话题，发布成功刷新当前列表。
- 支持文字、Unicode 表情、图片预览／移除和话题搜索选择。正文上限1000个 Unicode 码点，图片最多9张、单张10 MB，JPG／PNG／GIF，解码尺寸上限20000边长及4000万像素；选择图片与评论共用核心平台适配器。
- 图片只在用户点击发布后上传，全部成功才创建动态；失败保留草稿，已确认上传的图片在同一草稿中复用。上传失败不创建部分动态，创建请求结果不明时阻止再次提交，必须先由用户核对自己的动态并确认未发布。
- 发布期间禁用重复发送、草稿编辑、图片选择和关闭；请求和迟到的选择结果同时检查账号范围、epoch 与 generation，旧结果不能发布到新账号或清除新草稿。每次网络操作沿用 `ApiRequests` 取消与 deadline。

## 验证

定向覆盖协议负载、单次写、上传返回校验、游客、正文／图片容量、先上传后创建、失败草稿保留与上传缓存、结果不明锁定、账号变化和相同 mid 的 epoch 变化、话题搜索乱序响应，以及窄屏大字号／宽屏的实际编辑与提交。话题页回归覆盖三种导航模式、Android／Windows 两种主题平台、返回入口、收藏与原生举报、当前话题预选和发布后刷新。

动态、评论图片／编辑和滚动的定向回归151项通过（`build/dynamic-publish-targeted-final.log`）；API 定向22项通过（`build/dynamic-publish-api-tests.log`）。独立话题页最终18项回归及定向静态分析通过，额外覆盖已有播放标签时，工作区悬浮按钮不会遮挡窄屏“参与话题”（`build/dynamic-topic-standalone-final.log`）。

`.\tool\check.ps1 -SkipPub` 退出码0，格式、静态分析、打包边界脚本及离线测试通过，日志为 `build/dynamic-publish-check.log`：

| 范围 | 通过 | 跳过 |
| --- | ---: | ---: |
| 根应用 | 4980 | 13（Windows 符号链接权限不足） |
| bili_api | 835 | 0 |
| bili_player | 367 | 0 |
| bili_danmaku | 161 | 0 |
| bili_mux | 5 | 10（未配置 `BILI_MUX_LIBRARY` 的原生用例） |

本轮完整检查覆盖当时的工作区，包含同期已单独提交的评论标记回归；本提交只包含话题页与发布功能相关变更。文档相对链接及 `git diff --check` 通过。跳过的原生用例不代表原生集成通过。

构建、真实账号发布／收藏／举报、系统图片选择器及实机点击由用户后续验收；本次自动测试仅使用脱敏 fixture 与 fake，不执行真实账号写操作。

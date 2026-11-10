# 动态发布能力与自适应编辑器

日期：2026-11-11。对照 PiliPlus 补齐新动态发布，修正原先使用少量 Unicode 表情的面板。继续使用已有的账号草稿、动态列表／空间／话题入口和 Web Cookie 通道。

## 参考与采用范围

只读核对 PiliPlus `4fce4bb5a35c425aee759ef9263352316a29e355` 的 `lib/pages/dynamics_create/view.dart`、`lib/pages/common/publish/common_rich_text_pub_page.dart`、`lib/pages/dynamics_mention/`、`lib/pages/emote/controller.dart`、`lib/pages/dynamics_create_vote/{view,controller}.dart`、`lib/pages/dynamics_create_reserve/{view,controller}.dart`、`lib/models/dynamics/vote_model.dart` 和 `lib/http/{api,dynamics}.dart`，另读取该提交的[公开协议源码](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4fce4bb5a35c425aee759ef9263352316a29e355/lib/http/dynamics.dart)。

核对其实际 overrides／锁文件：核心及平台库解析 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频包解析 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`；这些依赖不用于本次修改。只借鉴职责和协议事实，独立实现，没有复制 GPLv3 应用代码／资源，没有修改相邻仓库、Pub缓存或增加依赖。B站表情图片按协议加载，不打包参考项目资源。本轮聚焦新动态投稿，不扩展既有动态的编辑／删除管理。

## 功能与布局

| 能力 | 本项目行为 |
| --- | --- |
| 标题与正文 | 可选20字标题，正文及投票标记合计最多1000个 Unicode 码点；标题不代替投稿内容 |
| B站表情 | 按需加载用户表情包、包标签、图片／文本标记和错误重试；按选区插入，发送type=9，替换原固定Unicode面板 |
| @用户 | 搜索并选择真实UID，以type=2/biz_id投稿；编辑前方文字移动UTF-16范围，修改标记内部移除旧身份，避免错误提及 |
| 图片 | 18张，单张10 MB、JPG／PNG／GIF；本地预览、移除、顺序调整，静态图矩形裁剪并校验输出大小；GIF保留动画，只预览不裁剪 |
| 发布设置 | 允许／关闭／精选评论，所有人／仅自己可见，6分钟至7天内定时发布；定时与私密互斥，投稿时重验过期时间 |
| 投票 | 文字／图片投票、标题／说明、2至20项、单选／最多选N项、90天内截止；选项图片沿用大小校验 |
| 直播预约 | 标题、公开／大航海直播、90天内开播；当前账号权限由服务端检查 |

投票截止／预约开播须晚于定时发布时间。所有字段保存在本账号的一份有界内存草稿中，不落盘；关闭保留，清空／成功投稿／账号或session epoch变化释放。普通评论和私信图片仍使用原9张默认值。

编辑器最大760×800，受当前窗口、SafeArea和键盘约束；主表单滚动，底部工具和发布按钮随宽度换行，短横屏保留提交／关闭入口。图片网格、话题及附件使用当前主题和可用约束；桌面限宽，窄屏不增加横向页面滚动。表情复用 `EmoticonPickerDialog`，其余子表单共用受约束容器；日期／时间通过 `showAppDialog` 留在所属Navigator。鼠标／触摸均可选择、裁剪图片，工具提供tooltip和键盘焦点。

## 协议与并发

沿用[已有发布登记](dynamic-publishing-and-topic-page-2026-11-10.md#协议登记)。以下为Web profile，无App token／WBI；读取共用有界重试、取消和25秒deadline，写入均为单次尝试，不自动重放。

| Profile | Host / method / path | 参数、鉴权与响应 |
| --- | --- | --- |
| comment_emotes（复用） | api.bilibili.com GET `/x/emote/user/panel/web` | `business=reply`，可选Cookie，最多50包／每包200项，沿用表情URL解析 |
| dynamic_mentions | api.bilibili.com GET `/x/polymer/web-dynamic/v1/mention/search` | 原始keyword/web_location编码一次；Cookie，按组解析uid/name/face，最多100个去重候选，无本地无限分页 |
| dynamic_picture_upload | api.bilibili.com POST `/x/dynamic/feed/draw/upload_bfs` | multipart Cookie／CSRF；动态 `category=daily/biz=new_dyn`，投票选项biz=vote；校验CDN URL、尺寸及大小 |
| dynamic_poll_create | api.bilibili.com POST `/x/vote/create` | Cookie／query CSRF；JSON vote_info：title/desc/type/choice_cnt/duration/options/only_fans_level/vote_publisher；读取vote_id，不经浮点数 |
| dynamic_reserve_create | api.bilibili.com POST `/x/new-reserve/up/reserve/create` | Cookie／form CSRF；type=2、sub_type=0/1、from=1、title、live_plan_start_time（Unix秒）；读取sid |
| dynamic_publish（扩展） | api.bilibili.com POST `/x/dynamic/feed/create/dyn` | 既有Cookie／query CSRF；content.title、contents type=1/2/4/9、option.private_pub/close_comment/up_choose_comment/timer_pub_time，预约attach_card.common_card type=14 |

选择图片、表情、用户及保存投票／预约表单不发账号写请求；点击总表单“发布／定时发布”后才上传图片、创建附件，最后提交动态。已确认的附件ID在本草稿重试时复用，更改附件丢弃相应缓存。服务端附件是独立资源，后续动态被明确拒绝时可能已经存在，清空草稿不会自动删除服务端附件。

附件或动态创建发生网络／超时／HTTP／协议不明确结果时，保持草稿并锁定重复投稿，要求核对自己的动态、投票和预约。只有明确确认未创建后才继续；已确认的附件不会因此重新创建。账号切换取消请求，迟到的选择、查询及创建回复不能污染新账号草稿；投稿期间禁用编辑和关闭。

## 验证

动态专项165项通过（`build/dynamic-parity-all-dynamic.log`），覆盖范围重建、API映射、写入不明、账号／epoch、附件复用、裁剪输出尺寸及像素、定时交互、六种主题平台的320×568双倍字号及键盘、844×390横屏及键盘、768×1024和1440×900。随后补入短窗口日期／时间确认可点击、图片投票和附件创建中换号回归，包含在最终全量检查中；最终编辑器单文件37项通过（`build/dynamic-parity-compose-final.log`）。平台主题测试在Windows运行，不能代替对应操作系统实机。

真实项目主题与HarmonyOS字体的390宽手机、1280宽桌面、320宽双倍字号深色布局，3项截图夹具通过并人工查看（`build/dynamic-parity-visual.log`、`build/dynamic-compose-parity-*.png`）。临时夹具和截图仅保留在忽略的build目录。

Windows模拟投稿器Debug构建通过。首次固定fvp SDK下载遇到TLS失败，复用build目录现有归档并重新校验锁定SHA-256 `e492fd45f3a6828e44f75ce665708c9040abaa60602605437b71c95c714808e3` 后构建成功，没有更改依赖或跳过校验。DTD连接、最终热重载成功；实际Windows窗口完成文字输入、表情插入、模拟提交和新日期时间表单操作，两次读取均无运行错误。此夹具的账号及所有写入都是fake，不是正常入口的Release构建或真实投稿验收，检查结束后已退出。

短窗口复查发现默认TimePickerDialog在大字号和键盘下可能把按钮放到点击区外，最终改为同一可滚动表单中的CalendarDatePicker与小时／分钟下拉项，确认区固定；回归明确验证按钮的hitTestable状态和提交后对话框消失。

最终 `.\tool\check.ps1 -SkipPub` 退出码0（`build/dynamic-parity-check-final.log`），格式、根／包静态分析、打包边界及离线测试通过：根应用5058项通过、13项因Windows符号链接权限不足跳过；bili_api 840项、bili_player 367项、bili_danmaku 161项通过；bili_mux 5项通过、10项因未配置 `BILI_MUX_LIBRARY` 跳过。原生跳过不代表原生集成通过。文档相对链接和 `git diff --check` 通过。同期pubspec版本号修改保留在工作区，不纳入本次提交。

未执行真实账号投稿、投票／预约创建或定时到达验收；表情服务在线响应、系统图片选择器、触摸裁剪及Android／Apple／Linux实机仍需后续验收。

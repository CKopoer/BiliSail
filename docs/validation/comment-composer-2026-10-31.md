# 共享评论发送框扩展

日期：2026-10-31。

视频与动态沿用 `CommentsPanel` 和 `CommentsController`，评论身份仍由 `CommentTarget(oid, type)` 决定。发送框默认单行，聚焦展开至最多四行；失焦保留文字、图片及回复目标。展开后显示表情、图片、@用户、可选播放时间、同步动态开关、字数及发布按钮。同步动态默认关闭，每次成功发布或切换账号后复位。

宽面板工具与发布同排；小于 380 逻辑像素或字号放大超过 1.3 倍时分行。图片以可横向滚动的缩略图展示并可逐张移除。输入区在键盘挤压时独立滚动，保留原评论列表的懒构建和滚动位置。

## 功能与约束

- 主评论支持 JPG、PNG、GIF，最多 9 张，每张最多 10 MiB；选择时检查文件签名、解码头和像素上限（单边 20000、总像素 4000 万）。使用系统文件选择器，不读取整个相册；取消或读取失败不改动现有草稿。
- 选图仅保留在当前页面内存，不上传、不存入数据库。点击发布后串行上传，全部完成后单次提交评论；任一上传失败不发评论，保留草稿供用户重试。支持纯图片主评论，读取评论时允许带有效图片的空文字正文。
- 图片只用于主评论。转入回复后保留附件并解释限制，发布禁用，需回到主评论或移除图片；楼中楼仍保留 root/parent 语义。
- @用户弹窗提供初始推荐、300 毫秒防抖搜索、错误重试和取消；选中后替换编辑选区或插入光标处。仅提交草稿中仍存在的已选择用户映射，长 UID 不经浮点转换。
- 视频评论可插入当前会话的确认播放时间，读取动作发生在点击时；未准备好时提示，不新建会话。动态不显示播放时间工具。
- 同步动态由用户显式开启并在发送前显示提示；开启开关本身不写入账号。
- 评论写入继续单次发送、未知结果锁定和人工核对机制。上传期间账号变更会取消旧请求，迟到上传不能继续提交评论；账号、评论目标变化清空草稿，旧选择器结果不能插入新页面。

## 协议登记

| 能力 | Web 端点与参数 | 鉴权／响应／重试 |
| --- | --- | --- |
| @搜索 | `GET https://api.bilibili.com/x/polymer/web-dynamic/v1/mention/search`，可选 `keyword` | Cookie，无签名；JSON `data.groups[].items[]`，无分页，最多保留 100 用户，沿用有界读重试与取消 |
| 评论图片上传 | `POST https://api.bilibili.com/x/dynamic/feed/draw/upload_bfs`，multipart `file_up/category=daily/biz=new_dyn/csrf` | Cookie+CSRF，无签名；JSON 图片 URL/尺寸，仅接受 HTTPS hdslb CDN；单次尝试、不跟随重定向，复用 deadline/session epoch |
| 发布扩展 | `POST https://api.bilibili.com/x/v2/reply/add`，既有 oid/type/root/parent/message，增加 `pictures`、`at_name_to_mid`、可选 `sync_to_dynamic=1` | Cookie+CSRF，无签名；两项 JSON 各序列化一次再 form 编码一次；所有评论 type 共用，写入不重放 |

协议和交互参考本地 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/pages/video/reply_new/view.dart`、`lib/pages/common/publish/common_rich_text_pub_page.dart`、`lib/http/video.dart`、`lib/http/msg.dart`、`lib/http/dynamics.dart` 及 mention 模型。PiliPlus 应用许可为 GPLv3；仅核对端点字段、职责和交互，自行编写本项目实现，未复制源码、schema 或资源。

文件选择使用 Flutter 官方 BSD-3-Clause 插件 [file_selector 1.1.0](https://pub.dev/packages/file_selector/versions/1.1.0)，支持 Android、Windows、macOS 及其余已配置目标，未增加图像编辑或原生媒体库依赖。macOS 沙盒补充用户选择文件的只读权限，并同步发布权限验证。插件平台声明不代表设备选图已验收。

## 验证

定向评论／动态组件回归 66 项、API 协议与 multipart 回归 6 项通过。覆盖图片预览移除及纯图发布、上传失败不提交、账号切换取消、@选区插入和映射过滤、视频时间插入、同步开关，以及 320 宽／双倍字号／300 高键盘下可发布。协议测试使用脱敏 fake transport 和本机 HTTP server，未执行真实账号上传、发评论或同步动态。

本次改动的格式、定向静态分析和 `git diff --check` 通过；Windows Debug 普通入口构建成功。四个包离线测试通过：`bili_api` 505、`bili_player` 105、`bili_danmaku` 145、`bili_mux` 5，mux 另 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计原生通过。

为隔离同期修改，在基线 `d89be756f1662bb3ccd28c928df5edd6e191c04a` 加本任务补丁的独立临时工作区完成根检查脚本的全部阶段：格式、静态分析、打包边界、根应用 3794 项及四个包合计 760 项测试通过。根应用另 13 项按配置跳过；包测试的 mux 另 10 项原生用例跳过。五份锁文件均经 `-EnforceLockfile` 解析；首次原生归档下载停滞后，复制与固定清单 SHA-256 一致的本机归档，由正常构建钩子再次校验及解包，随后执行 `-SkipPub -Stage RootTests/PackageTests`。未修改 Pub 缓存或绕过校验。

检查日志位于忽略目录 `artifacts/comment-composer-isolated-check.log`、`comment-composer-isolated-root.log`、`comment-composer-isolated-packages.log`；主工作区 Windows 普通入口 Debug 构建成功，局部响应式视觉复查采用本项目字体和主题的 widget 截图，结果为 `artifacts/comment-composer-800.png`、`comment-composer-320.png`。提交只包含本任务补丁，保留原工作区同期修改。

本轮后续检测到 Windows 调试实例，成功执行热重载，工具未报告运行时错误。Windows 实际系统选图及 Android/macOS 设备交互、在线接口可用性和风控限制尚未验收。

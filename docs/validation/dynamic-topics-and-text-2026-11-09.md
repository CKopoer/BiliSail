# 应用内话题与动态展示修复

日期：2026-11-09。按用户的后续反馈修正[上一轮动态重构](dynamic-content-redesign-2026-11-09.md)：话题改为应用内阅读，移除动态的浏览器按钮，正文根据实际排版判断展开，并修复未预约却显示已预约的问题。沿用用户指定的单元／Widget 检查与提交范围，不构建应用或操作真实设备。

2026-11-10 后续定位到移动端 `/topic-detail` 链接未识别、标签未优先使用 ID，导致仍落入浏览器。已改为共享的身份优先／名称回退规则并补充协议到点击回归，见[话题外跳修复](dynamic-topic-navigation-2026-11-10.md)。

## 参考与实现

只读参考 PiliPlus `4fce4bb5a35c425aee759ef9263352316a29e355`：`lib/pages/dynamics_topic/{controller,view}.dart`、`lib/http/{api,dynamics,constants}.dart`、`lib/models_new/dynamic/dyn_topic_{top,feed}/`，以及 `lib/pages/dynamics/widgets/content_panel.dart`、`lib/common/widgets/text_more/{text_more,rich_text_more,paragraph_more}.dart`。参考协议身份、服务端排序与游标、折叠内容入口，以及使用排版溢出结果决定“更多”的职责。

预约状态另外核对同一提交的 `lib/pages/dynamics/widgets/additional_panel.dart` 与 `lib/models/dynamics/result.dart`：预约按钮以 `status == type` 判断选中状态，`jump_style` 的跳转文案优先。

独立实现 API 客户端、领域契约、Repository、Riverpod 控制器和 Flutter 页面／正文组件。未复制其 GPLv3 应用源码、资源、背景图或字体，未修改相邻仓库；沿用上一轮记录的实际 overrides／锁文件核对，没有变更播放器或其他依赖。

### 话题导航与页面

- 新增 `/topic/:id` 工作区页面。首页、空间和动态详情内，合法话题 ID 进入同一应用内路由；话题页中的其他话题也使用此路由。没有 ID 的话题／话题富文本按名称进入既有应用内搜索，不猜测话题身份。
- 页面展示标题、简介、发起人、浏览／讨论计数，以及服务端提供的排序项、动态流、分页和折叠内容。发起人进入用户主页；动态继续复用现有图片、商品、视频／影视／直播、评论和账号动作。
- 分页与折叠内容分别持有取消信号。切换排序取消旧页并清空旧游标；账号 scope／epoch、请求代次和页面释放共同隔离迟到响应。分页合并按动态 ID 去重，检测游标及内容不前进，动态最多 500 条；错误显示并保留正确的重试身份，不自动无限重试。
- 排序切换重建对应滚动控制器并回到顶部；普通工作区切换保留页面与列表。话题属于非播放临时页，沿用 16 页／64 次访问历史边界和现有返回行为。

### 卡片入口与正文

- 移除“在浏览器打开动态”和“在浏览器打开原动态”的头部按钮。列表中的“查看动态详情”成为作者行右上角的唯一详情入口；详情自身不显示重复入口。分享弹窗继续支持用户主动复制链接。
- 将正文和展开状态提取到 `DynamicPostText`。列表默认最多 6 行；使用与实际正文相同的宽度、字体、locale、方向、文字缩放和表情占位进行 `TextPainter` 测量，以 `didExceedMaxLines` 决定是否显示展开按钮。
- 修复短正文只因换行就显示按钮、宽屏长正文其实未被截断仍显示按钮、窄屏／大字体／富文本无法依字符数判断是否截断的问题。点击展开立即取消行数限制，收起恢复 6 行；按动态 ID 保留展开状态，继续参与列表高度测量和虚拟化。
- 取消展开后的额外 12000 字符截断。列表和详情一致保留协议允许的 32768 字符、256 富文本节点上限；详情直接显示完整的有界正文，不出现无意义的“展开／收起”。富文本链接与表情保留，手势识别器仍按组件生命周期释放。

### 预约状态

- 旧实现把 `button.status == 1` 固定映射到 `check.text`，会将 `status=1/type=2` 这类未预约按钮误显示为“已预约”。改为在状态和类型均合法时比较 `status == type`，相等使用 `check.text`，不同使用 `uncheck.text`；服务端缺少文案时分别使用“已预约”和“预约”。
- 状态／类型只接纳非负整数或十进制数字字符串，类型必须大于 0；缺失、浮点数、负值及“1万”等计数格式不作为已预约依据，使用中性的“查看详情”。服务端 `jump_style.text` 继续优先于状态文案，已结束的卡片继续显示结束提示。
- 首页、空间和嵌套转发经过同一个解析器。新增 28 项协议回归覆盖两个读取入口的类型／状态组合、字符串形式、未知状态、默认文案和跳转优先级；显示状态不触发预约或取消预约请求。

## 协议登记

三项均为 Web Cookie profile 的 JSON 只读 GET，Cookie 可选，沿用服务端权限；不要求 App token、WBI 或 CSRF，不新增写接口。每个请求使用既有有界读取重试、25 秒应用 deadline、取消与会话 epoch 检查。

| 能力 | host / path | 参数与分页 |
| --- | --- | --- |
| 话题简介 | `app.bilibili.com` `/x/topic/web/details/top` | `topic_id` 十进制字符串、`source=Web`；读取 `top_details.topic_item/topic_creator`，校验返回身份 |
| 话题动态 | `api.bilibili.com` `/x/polymer/web-dynamic/v1/feed/topic` | `topic_id`、`sort_by`、`page_size=20`、`source=Web`、`features=itemOpusStyle`、可选 opaque `offset`；读取 `topic_card_list` 与服务端排序配置 |
| 折叠内容 | `api.bilibili.com` `/x/topic/web/details/fold` | `topic_id`、`sort_by`、`source=Web`；用户显式点击后读取并合并，不改变主列表游标 |

`requestJson` 只为 `app.bilibili.com` 开放上述话题简介路径，其他 App host 路径继续拒绝。所有 ID 不经浮点数转换，游标最多 2048 字符且只编码一次；单份动态响应最多解析 50 条、排序最多 8 项。明确的 `topic_card_list: null` 表达空结果，缺失必需结构或错误类型按协议失败处理，不返回空成功。目标 URL 识别校验 scheme／host／port／userinfo，禁止伪造子域进入内部路由。

## 验证与边界

新增 API 用例覆盖端点／host、长 ID、游标编码、排序、折叠数据、空结果／畸形响应／鉴权错误和输入边界；控制器用例覆盖排序取消、迟到响应、账号切换、正确重试、去重与容量、折叠读取和页面释放。Widget 用例覆盖真实工作区内连续打开话题、名称搜索、320 像素／两倍文字、排序／重试／折叠交互，以及真实截断、6／7 行边界、长正文、表情占位和右上角入口。

最终 `tool/check.ps1 -SkipPub` 全流程通过：格式、全仓静态分析与打包边界检查通过；根应用 **4910 项通过、13 项按配置跳过**；`bili_api` **805**、`bili_player` **367**、`bili_danmaku` **161**、`bili_mux` **5** 项通过。未配置 `BILI_MUX_LIBRARY`，另有 **10 项 mux 原生用例跳过**，不将其计作原生验证通过。

动态专项最后一次 **107 项全部通过**，本次 27 个 Dart 文件的定向格式／静态分析通过，文档新增相对链接与 `git diff --check` 通过。最终日志位于本机忽略目录 `build/dynamic-topic-reservation-full-check.log`，另有 `dynamic-topic-regression-final.log` 和 `dynamic-topic-api-final.log`。没有执行应用构建、真实账号写入或设备测试。

未做真实接口在线可用性、真实账号话题／预约状态、系统浏览器／购买目标或 Android／Windows／Apple 实机交互验收；离线协议与布局检查不等于这些流程已通过。

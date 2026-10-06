# 合集状态异常与 Windows 播放期间崩溃

日期：2026-10-06。用户反馈合集卡片显示“服务返回了暂不支持的数据”，并补充程序在播放一段时间后崩溃；二者分别排查。

## 已取得证据

- 合集详情 `/x/space/fav/season/list` 的公开只读正常响应没有 `info.fav_state`。此前新客户端假定该字段存在，所以把正常数据判成协议错误；`info.id` 校验不是此次原因。改从当前账号 `/x/v3/fav/folder/collected/list` 分页匹配 `type=21` 和合集 ID，完整读完后才能判断未订阅，详细边界见 [合集订阅按钮](collection-subscription.md)。
- Windows Application 事件记录本次 `bilisail.exe` 进程 40992 于本地 14:14:36 崩溃，模块 `flutter_windows.dll`，异常 `0xc0000005`，偏移 `0x3c1ca`。读取本机 `CrashDumps/bilisail.exe.40992.dmp`，使用当前 SDK 的 `windows-x64-release/flutter_windows.dll.pdb`，异常指令符号为 `flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate+0xba`；异常参数是读取地址 `0x48`，寄存器 `rax=0`。只采用异常位置的匹配符号，后续自动栈展开不可靠，不作为调用链证据。
- 固定 Flutter 3.47.6，framework `5fc346839b5d0eef006ed8404392afb4dfae428d`、engine `692136cb6582dbfc5af3fb33c2515a069f2f66d0`。本地 engine 的 `accessibility_bridge.cc` 在重挂节点时仅用 `assert(child->parent())`，Release 随后仍会访问 `child->parent()->id()`；断言不能保护空指针。
- [Flutter issue 193410](https://github.com/flutter/flutter/issues/193410) 的 Windows `Slider`／`IndexedStack` 复现有相同异常符号和 `+0xba` 偏移。[PR 190903](https://github.com/flutter/flutter/pull/190903) 提供原生空父节点保护，截至本次查看仍未合入。结合本机转储，可确认此次故障点是 Windows 无障碍树重挂的空指针访问；无法从转储确定具体是哪一个 Flutter 控件首先产生错误更新。
- 应用工作区保留隐藏的设置页 `Slider`，播放页有时间轴／音量 `Slider` 与 `OverlayPortal`。SDK 的 Material Slider 会始终挂载其 value-indicator portal；隐藏页面的绘制祖先与无障碍遍历祖先可因此不同。其结构与上游复现接近，不能把“查看评论”或某个 `IndexedStack` 单独定为已证实的触发条件。播放日志未提供媒体解码崩溃证据。

## 应用侧修正

新增 `core/presentation/bili_widgets_binding.dart`，由 `main.dart` 在初始化时安装。仅 Windows 单 Flutter view 的语义更新使用保护路径；不升级或改写全局 SDK、原生 DLL、播放器和依赖，不强制关闭无障碍。

- 从当前 `SemanticsOwner` 根节点及原始 portal identifiers 推导实际遍历连通性，排除 merged 后代；不把 attached 状态或旧序列化缓存等同于当前可见。
- 仅向原生端提交连通节点。遍历子列表剔除根 ID 0、自引用、循环／双父以及旧父引用；命中列表保持其独立次序，只过滤无效或不连通节点，不将两套子列表强行合并。
- 缓存每个仍由当前 owner 持有的节点的最新不可变参数；列表／矩阵拥有副本。重新连通的干净节点补发数据，过滤导致干净父节点子边改变时也补发父节点，保留标签页面状态、语义字段和自定义动作。
- 缓存同时核对 owner 与节点对象身份，避免 ID 复用；节点移除、owner 更换和关闭语义时清理，不写盘或输出语义文字。
- 当前应用是单窗口／单 view；若以后引入多个 view，需要按 owner 分离该更新路径，不能共享根 ID 0。Android／macOS 保持标准语义更新，未将 Windows 规避结论推广至其他平台。

源码依据为本机锁定的 Flutter public API 和语义序列化实现（Flutter BSD-3-Clause）。同时阅读 [OpenHarness 的公开应用侧方案](https://github.com/autonomous-ai/openharness/pull/620) 了解连通过滤与干净节点重连思路；本项目按自身入口独立实现，没有导入该仓库源码、测试、资源或运行时依赖。上游 issue／外部方案均不能替代本项目运行验收；SDK 更新后应重新评估是否移除这层规避。

## 构建与验收边界

按用户要求不运行或新增测试流程，没有自动执行订阅／取消等账号写入。根应用和 `bili_api` 静态分析通过，受影响 Dart 目录格式检查通过。分析与转储符号记录保存在忽略目录 `build/crash-diagnostics/`，未输出凭据或原始内存内容。

用户旧版 Release 仍在运行，因此从独立源码快照 `build/collection-crash-fix-source` 构建，保持锁文件和 SDK。构建与导出结果由本轮交付后补；需使用完整新目录启动，旧进程不会自动加载修正。

此为对应已定位故障的应用侧规避，构建通过不能证明长时间播放已稳定。真实登录订阅态、持续播放、设置标签往返、评论／简介往返、窗口尺寸变化与 Windows 读屏行为交由用户验收；Android／macOS 本轮未构建或运行。

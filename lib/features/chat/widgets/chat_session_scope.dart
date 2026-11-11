import 'package:flutter/widgets.dart';

/// 聊天会话作用域：把「当前会话 id」以 [InheritedWidget] 下发给聊天页内的所有后代。
///
/// 用途：媒体预览（灯箱）这类**跨路由**动作需要知道「这张图来自哪个会话」。
/// 原先靠解析 go_router 的当前路由来猜，但 `context.push('/chat/<id>')`
/// （窄屏从会话列表进聊天页的唯一方式）**不会更新** delegate 的
/// `currentConfiguration`（实测停在基路由 `/`），push 出来的 URI 只出现在
/// `routeInformationProvider` 里 ⇒ 「引用」按钮在手机上永远报
/// 「当前没有打开的聊天会话」。
///
/// 这里改成**由聊天页自己声明身份**：灯箱的调用方（消息气泡 / 实时文本块 /
/// 待发附件条）都在本作用域的后代里，`showAttachmentPreview` 在调用瞬间用
/// 调用方 context 取到会话 id 并随灯箱一起带走 —— 与路由怎么进聊天页无关。
class ChatSessionScope extends InheritedWidget {
  const ChatSessionScope({
    super.key,
    required this.sessionId,
    required super.child,
  });

  /// 当前聊天会话 id（非空；新会话页还没有 id 时不上作用域）。
  final String sessionId;

  /// 取祖先作用域里的会话 id（null = 不在聊天页内 / 新会话尚无 id）。
  ///
  /// 刻意用 [BuildContext.getInheritedWidgetOfExactType]（不登记依赖）：
  /// 调用点是点击回调、不在 build 期，登记依赖会撞框架断言。
  static String? of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ChatSessionScope>();
    final id = scope?.sessionId;
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  bool updateShouldNotify(ChatSessionScope oldWidget) =>
      oldWidget.sessionId != sessionId;
}

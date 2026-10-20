import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';

/// #205 收尾：done 帧裁窗的**窗口计算**守卫。
///
/// 背景（2026-10-20 真机 bug）：裁窗把「可渲染行不足窗口」那一支写成了
///
/// ```dart
/// start = 0;
/// for (var i = 0; i < messages.length; i++) {
///   if (_countsAsRenderableRow(messages[i])) continue;
///   start = i + 1;          // ← 每遇一条工具结果行就把 start 往后推
/// }
/// ```
///
/// ⇒ start 落到「最后一条工具结果行 + 1」⇒ 窗口被裁成尾部几条。
///
/// 现场（本机真实会话 af294c385b5e）：63 条消息、仅 27 条可渲染行 ⇒
/// 窗口被裁成 **1 条** ⇒ 本轮 user 提问行被裁掉 ⇒
/// `_mergingLoadedMessages` 在窗口里找不到 user 边界行 ⇒ 乐观 user 气泡的
/// 插入点退化成「最末尾」⇒ **提问气泡跑到本轮回复下方**（主人真机截图），
/// 刷新后走 REST（服务端窗口正确）才回到上方。
///
/// 正确语义（对齐服务端 `routes.py::_message_window_for_display`）：
/// 可渲染行不满 limit 时 `start_idx` 停在 0 ⇒ 窗口 = 全部行。
void main() {
  group('done 帧裁窗：窗口边界计算', () {
    test('可渲染行不足窗口 ⇒ 全量保留（不得裁掉 user 提问行）', () {
      // 构造现场同款形态：user 提问 + 大量工具结果行 + 末条 assistant。
      // 消息总数 > 窗口（50），但可渲染行远不足 50。
      final messages = <ChatMessage>[
        const ChatMessage(
          role: 'user',
          content: '帮我给 Hermes 配下支持直通视觉和上下文',
          messageId: 'm-user',
          timestamp: 1,
        ),
        const ChatMessage(
          role: 'assistant',
          content: '收到喵~',
          messageId: 'm-a1',
          timestamp: 2,
        ),
        // 60 条工具结果行（role=user + toolCallId ⇒ 不计入可渲染行）
        for (var i = 0; i < 60; i++)
          ChatMessage(
            role: 'user',
            content: '{"output":"tool result $i"}',
            messageId: 'm-t$i',
            toolCallId: 'tid-$i',
            timestamp: (3 + i).toDouble(),
          ),
        const ChatMessage(
          role: 'assistant',
          content: '配好了，主人。',
          messageId: 'm-final',
          timestamp: 100,
        ),
      ];
      expect(messages.length, greaterThan(50), reason: '总数超窗口');

      final window = ChatController.tailWindowForTesting(messages, 50);

      expect(
        window.length,
        messages.length,
        reason: '可渲染行不足窗口时必须**全量保留**（与服务端同语义）；'
            '裁掉任何一行都可能把本轮 user 提问行裁没 ⇒ 乐观气泡插到末尾',
      );
      expect(
        window.first.messageId,
        'm-user',
        reason: '本轮 user 提问行必须在窗口内（丢了它气泡就会跑到回复下方）',
      );
      expect(
        window.any((m) => m.role == 'user' && m.messageId == 'm-user'),
        isTrue,
      );
    });

    test('可渲染行多于窗口 ⇒ 只保留尾部窗口，且保留最新行', () {
      final messages = <ChatMessage>[
        for (var i = 0; i < 80; i++)
          ChatMessage(
            role: i.isEven ? 'user' : 'assistant',
            content: 'row $i',
            messageId: 'm-$i',
            timestamp: i.toDouble(),
          ),
      ];

      final window = ChatController.tailWindowForTesting(messages, 50);

      expect(window.length, 50, reason: '可渲染行够 ⇒ 严格按窗口裁');
      expect(
        window.last.messageId,
        'm-79',
        reason: '必须保留最新行（尾部 = 最新）',
      );
      expect(
        window.first.messageId,
        'm-30',
        reason: '窗口起点 = 第 50 条可渲染行（80 - 50 = 30）',
      );
    });

    test('工具结果行不占可渲染行预算（对齐服务端口径）', () {
      // 1 条 user + 49 条工具结果行 + 1 条 assistant ⇒ 可渲染行仅 2 条。
      final messages = <ChatMessage>[
        const ChatMessage(
          role: 'user',
          content: 'hi',
          messageId: 'm-user',
          timestamp: 1,
        ),
        for (var i = 0; i < 49; i++)
          ChatMessage(
            role: 'user',
            content: 'tool $i',
            messageId: 'm-t$i',
            toolCallId: 'tid-$i',
            timestamp: (2 + i).toDouble(),
          ),
        const ChatMessage(
          role: 'assistant',
          content: 'done',
          messageId: 'm-a',
          timestamp: 100,
        ),
      ];

      final window = ChatController.tailWindowForTesting(messages, 50);

      expect(
        window.length,
        messages.length,
        reason: '工具结果行不占预算 ⇒ 可渲染行只有 2 条 ⇒ 全量保留',
      );
      expect(window.first.messageId, 'm-user');
    });
  });
}

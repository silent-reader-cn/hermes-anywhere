import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_diff_merge.dart';

/// 2026-10-23 真机 bug 守卫：**旧提问气泡跑到本轮回复下方**。
///
/// 现象（主人截图）：回合跑完后，列表最末端多出一条**蓝色用户气泡**，内容却是
/// 会话第一句的原文（带附件卡片）；正常情况最后一条应是 AI 内容。
///
/// 根因（收尾合并 `_mergingLoadedMessages`）：
/// 1. 发送时本地先插一条 `local-*` 乐观 user 行（正文是**用户原文**）；
/// 2. 服务端落库的 user 行正文带 `[Workspace::v1: …]` / `[Attached files: …]`
///    注入标记 ⇒ 旧的「是否已被服务端确认」判定直接比原文，恒定不相等；
/// 3. 于是这条乐观行永远被判成「服务端还没有」，每轮收尾都被重新插回，
///    插入点是「最后一个 user 边界之后」；当服务端窗口（尾窗 50 行）里已经没有
///    它对应的那一行时，插入点退化到本轮末尾 ⇒ 旧气泡冒到最下面。
void main() {
  ChatMessage user(String id, String content, double ts) => ChatMessage(
    role: 'user',
    content: content,
    messageId: id,
    timestamp: ts,
  );

  ChatMessage assistant(String id, String content, double ts) => ChatMessage(
    role: 'assistant',
    content: content,
    messageId: id,
    timestamp: ts,
  );

  test('陈旧乐观提问行不得被插回本轮末尾', () {
    // 会话第一句（本地乐观副本，正文无注入标记）。
    const firstText = '现在没配置服务器是显示这个界面 太丑了 我建议按钮放最下面';
    final localFirst = user('local-first', firstText, 100);

    // 服务端尾窗：已经推进到很后面，第一句早已落在窗口之外。
    final loaded = <ChatMessage>[
      user(
        'm-200',
        '[Workspace::v1: D:\\\\projects\\\\hermes-ui] 而且现在跑完以后你看这个 steer',
        900,
      ),
      assistant('m-201', '收到，本喵排查一下喵。', 901),
      assistant('m-202', '根因在收尾合并里。', 902),
    ];

    // 本地还留着第一句的乐观行（永远没被确认的那条）。
    final current = <ChatMessage>[localFirst];

    final merged = ChatController.mergingLoadedMessagesForTesting(
      loaded,
      current,
    );

    expect(
      merged.last.role,
      'assistant',
      reason: '回合收尾后最后一条必须是 AI 内容，不能是旧用户气泡',
    );
    expect(
      merged.any((m) => m.messageId == 'local-first'),
      isFalse,
      reason: '早于服务端窗口的乐观行属陈旧回声，不得再插入本轮',
    );
    expect(merged.length, loaded.length);
  });

  test('同一条消息的乐观行遇到带注入标记的服务端行要判重复（不比原文）', () {
    // 服务端窗口里**包含**这条提问行，但正文带工作区标记。
    final loaded = <ChatMessage>[
      user(
        'm-300',
        '[Workspace::v1: D:\\\\projects\\\\hermes-ui]\n帮我把按钮放最下面',
        1000,
      ),
      assistant('m-301', '收到喵~', 1001),
    ];
    final current = <ChatMessage>[
      user('local-300', '帮我把按钮放最下面', 1000),
    ];

    final merged = ChatController.mergingLoadedMessagesForTesting(
      loaded,
      current,
    );

    expect(
      merged.where((m) => m.role == 'user').length,
      1,
      reason: '归一化后同一条消息只能有一条气泡，不能被插成两条',
    );
  });

  test('REST 合并：陈旧乐观回声退场，正在发送的新乐观行保留', () {
    final local = <ChatMessage>[
      user('local-old', '会话第一句提问', 100),
      assistant('m-a1', '旧回复', 110),
      user('local-new', '刚打的下一句', 2000),
    ];
    // 服务端窗口与本地有交集（m-a1），首行时刻已晚于那条陈旧乐观行。
    final server = <ChatMessage>[
      assistant('m-a1', '旧回复', 110),
      assistant('m-a2', '更新的回复', 2100),
    ];

    final merged = diffMergeMessages(
      localMessages: local,
      serverMessages: server,
    );
    final ids = merged.map((m) => m.messageId).toList();

    expect(ids, isNot(contains('local-old')), reason: '陈旧回声不得当历史保留');
    expect(ids, contains('local-new'), reason: '刚发出、尚未落库的乐观行必须保留');
    expect(
      merged.any((m) => m.messageId == 'm-a2'),
      isTrue,
      reason: '服务端新行照常入列',
    );
  });
}

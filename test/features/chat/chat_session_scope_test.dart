import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_session_scope.dart';

import '../../helpers/fake_chat_api.dart';

/// 媒体预览「引用」按钮的**会话来源**由聊天页声明（[ChatSessionScope]），
/// 不再靠解析路由猜 —— 窄屏 `context.push` 进聊天页时
/// `routerDelegate.currentConfiguration` 停在基路由 `/`，猜必错
/// （见 `chat_media_quote_push_route_test.dart` 与
/// `resolveCurrentChatSessionId` 的注释）。
///
/// 本文件锁死：真实聊天页确实把会话 id 下发给后代；新会话（空 id）不挂作用域。
void main() {
  Future<void> pumpChatPage(WidgetTester tester, String sessionId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(FakeChatApi()),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
        ],
        child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('聊天页把会话 id 下发给后代（后代可直接 of() 取到）', (tester) async {
    await pumpChatPage(tester, 's-scope');

    final scope = tester.widget<ChatSessionScope>(
      find.byType(ChatSessionScope),
    );
    expect(scope.sessionId, 's-scope');

    // 后代 context 能直接读到（灯箱在调用瞬间就是这么取来源会话的）。
    final descendantContext = tester.element(find.byType(ChatSessionScope));
    expect(
      ChatSessionScope.of(descendantContext),
      's-scope',
    );
  });

  testWidgets('新会话（sessionId 为空）不挂作用域：不给出假会话 id', (tester) async {
    await pumpChatPage(tester, '');

    expect(find.byType(ChatSessionScope), findsNothing);
  });
}

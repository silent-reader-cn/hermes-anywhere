import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 「同一句话重复 N 遍」（2026-10-20 实机）客户端防重回归。
///
/// 定性（实证，三重）：
///  - state.db 里该句话**只有一份** → 重复 100% 在渲染层（非生成/非线程）；
///  - 客户端 SSE 日志里该 interim **只到达 1 次** → 服务端正常时一句一次；
///  - 服务端 `already_streamed` 标记靠「已流出正文的**尾部**匹配」算，而已流出正文
///    只在 **token 路径**累积 → 手机弱网（5G + VPN）下 token 帧丢失 → 尾部不匹配
///    → 标记失效 → interim 整段被当「新段落」再次追加 → 每次重投/重连多一份。
///
/// 修复：客户端在 `_handleInterimAssistant` 入口加「整段指纹」闸门 ——
/// 本回合已投递过的整段，且能证明「确实已展示过」（replay 连接 ∨ 已由 token
/// 流出过）⇒ 直接吞掉，不进任何追加分支。
void main() {
  group('interim 整段指纹去重（防同一句话重复 N 遍）', () {
    test('token 已流出该段 + interim 到达（already_streamed 标记失效）→ 不得追加第二份', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 实机原文（截图 1：2026-10-20 21:12:06 那条）。
        const line = '评测在跑（要编码 8284 条语料 × 3 轮）。本喵等结果喵。';

        // ① 这段正文**已经由 token 流出过**（实机日志：token 帧先到，interim 帧
        //    后到且带 already_streamed 标记）。这里用 token 路径构造「已流出」，
        //    再用 interim 重投模拟「服务端标记在弱网下失效」。
        api.emit(const TokenSseEvent(line));
        // 打字机 reveal 是分批推进的 → 多给几轮时间让它吐完。
        for (var i = 0; i < 30; i++) {
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(_streamingContent(container).trim(), line);

        // ② 弱网下服务端的 already_streamed 标记失效（尾部不匹配）⇒ 同一整段
        //    以 already_streamed=false 重投 ⇒ 旧实现会把它当「新段落」再追加一次。
        api.emit(
          const InterimAssistantSseEvent(text: line, alreadyStreamed: false),
        );
        async.elapse(const Duration(milliseconds: 100));

        // 关键：不能变成「同一段\n\n同一段」。
        final content = _streamingContent(container);
        expect(
          content.allMatches(line).length,
          1,
          reason: '目标整段出现了多份：$content',
        );
      });
    });

    test('replay 连接上重投同一整段 → 只显一份（服务端回放重投，已实证）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        const line = '同一整段';

        // live 期间收到这一段（interim 立即落地，不走打字机队列）。
        api.emit(
          const InterimAssistantSseEvent(text: line, alreadyStreamed: false),
        );
        async.elapse(const Duration(milliseconds: 100));
        expect(_streamingContent(container).trim(), line);

        // 断线重连（**不携带 event id** ⇒ afterSeq=0 ⇒ 走 fullReconnect，
        // 序号闸门条件 replayAfterSeq>0 不成立 ⇒ 整段内容全部放行）。
        api.emit(const TransportErrorSseEvent('cut'));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider(''));
        expect(state.stream.isReplayConnection, isTrue);
        expect(state.stream.replayAfterSeq, 0);

        // 服务端全量重放：同一整段重投 3 次。
        for (var i = 0; i < 3; i++) {
          api.emit(
            const InterimAssistantSseEvent(
              text: line,
              alreadyStreamed: false,
            ),
          );
          async.elapse(const Duration(milliseconds: 100));
        }

        final content = _streamingContent(container);
        expect(
          content.allMatches(line).length,
          1,
          reason: '重投导致目标整段出现了多份：$content',
        );
      });
    });

    test('合法的重复（未被 token 流出且非 replay）→ 行为与旧实现一致（不因指纹闸门被额外吞掉）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        const line = '本喵继续。';
        api.emit(
          const InterimAssistantSseEvent(text: line, alreadyStreamed: false),
        );
        async.elapse(const Duration(milliseconds: 100));
        expect(_streamingContent(container), line);

        // 第二个工具轮次又说同一句（**没有** token 流出过它）⇒ 必须照常展示。
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'terminal'),
          ),
        );
        async.flushMicrotasks();
        api.emit(
          const InterimAssistantSseEvent(text: line, alreadyStreamed: false),
        );
        async.elapse(const Duration(milliseconds: 100));

        // 旧实现的「整段包含」启发式已会吞掉同一回合内的重复 interim（content 包含本文）
        // → 此处只锁定「不因新增指纹闸门而被额外吞掉」，不改变既有行为。
        final content = _streamingContent(container);
        expect(
          content.allMatches(line).length,
          1,
          reason: '重复的表现与旧实现不一致：$content',
        );
      });
    });

    test('不同回合里的同一句话 → 合法展示（指纹不跨回合清空）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        const line = '同一句话';
        api.emit(
          const InterimAssistantSseEvent(text: line, alreadyStreamed: false),
        );
        async.elapse(const Duration(milliseconds: 100));
        expect(_streamingContent(container), line);

        // 第二个回合（真正的新回合：interrupt 行为 → stop 当前流 + 新发一条
        // 消息 → _beginStream 清空指纹集）
        unawaited(
          controller.send(
            'hi again',
            behavior: StreamingSendBehavior.interrupt,
          ),
        );
        async.flushMicrotasks();

        api.emitId('s2:1');
        api.emit(
          const InterimAssistantSseEvent(text: line, alreadyStreamed: false),
        );
        async.elapse(const Duration(milliseconds: 100));

        final state = container.read(chatControllerProvider(''));
        final texts = state.messages
            .where((m) => m.role == 'assistant')
            .map((m) => m.content ?? '')
            .where((c) => c.isNotEmpty)
            .toList();
        expect(texts.where((c) => c == line).length, 2);
      });
    });

    test('指纹归一化：空白差异不影响判定，但不同正文不得归一', () {
      expect(
        ChatController.interimFingerprint('  你好  世界 '),
        '你好 世界',
      );
      expect(
        ChatController.interimFingerprint('你好世界'),
        isNot(ChatController.interimFingerprint('你好 世界')),
      );
      expect(
        ChatController.interimFingerprint('你好世界'),
        isNot(ChatController.interimFingerprint('你好世界!')),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

String _streamingContent(ProviderContainer container) {
  final state = container.read(chatControllerProvider(''));
  final streaming = state.messages
      .where((m) => m.messageId == state.stream.streamingAssistantMessageId)
      .firstOrNull;
  return streaming?.content ?? '';
}

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);
  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async =>
      const [];

  @override
  Future<void> writeSessions(List<SessionSummary> sessions) async {}

  @override
  Future<List<SessionSummary>> readSessions() async => const [];
}

ProviderContainer _buildContainer(FakeChatApi api, _FakeClock clock) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      appDatabaseProvider.overrideWithValue(db),
      cacheServiceProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    container.dispose();
  });
  return container;
}

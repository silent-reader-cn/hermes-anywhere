// #196 / #197 回归：孤儿显示态（「生成中 · 已工作 MM:SS」永久卡死）的收尾对称清理、
// 自动守卫与「强制刷新」出口。
//
// 现象（主人真机）：服务端回合早已收尾（active_stream_id 已清、transcript 完整），
// 某台客户端却永久显示「生成中 ≈N tps · 已工作 300+ 分钟」，且侧边栏无生成中图标。
//
// 机理链（本文件逐条覆盖）：
//   1) `_applyDone`（done 路径）只调 `_completeCurrentResponse`、**不调** `_finishStream`
//      ⇒ `turnStartedMillis` 从未清（状态行「已工作」永久递增）—— 承重修复，RED 实证；
//   2) `_completeCurrentResponse` 原先不取消 merge/reveal 定时器、不丢弃「待落账」缓冲
//      （对称加固：当前调用点下 done 已先 flush，故属防御性）；
//   3) 该状态（无活跃流 + 相位已离场 + 气泡/计时残留）下既有自愈链**全体**被闸门挡在
//      外面 ⇒ F1 守卫补位（RED 实证）；
//   4) 用户级出口 = 会话菜单「强制刷新」。

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
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeClock {
  DateTime now = DateTime(2026, 10, 13, 9, 8, 11);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
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

/// 注入任意初始状态（孤儿显示态 / 真回合进行中）的控制器。
///
/// 只覆写 `build`：`syncMissingMessages` 保持真实实现，好让守卫与「强制刷新」
/// 真的打到 [FakeChatApi]（用 `sessionCalls` 取证）。
class _StaticChatController extends ChatController {
  _StaticChatController(this.initialState);

  final ChatState initialState;

  @override
  ChatState build(String sessionId) {
    // 必须先跑基类 build：它注入 `_api`、启动看门狗、挂通道与监听器；
    // 直接 return 注入态会让 `_api` 为空（强制刷新/探活链会空崩、也不发请求）。
    super.build(sessionId);
    return initialState;
  }

  // 基类 build 会用微任务拉起 loadMessages，会把注入态冲掉；本用例只看
  // 守卫/强制刷新链，故掐掉它（`syncMissingMessages` 保持真实实现以取证请求）。
  @override
  Future<void> loadMessages({int? messageBefore}) async {}

  @override
  Future<void> loadYoloState() async {}
}

ProviderContainer _buildContainer(
  FakeChatApi api,
  _FakeClock clock, {
  ChatWatchdogConfig? watchdogConfig,
  ChatState? staticState,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
      chatWatchdogConfigProvider.overrideWithValue(
        watchdogConfig ??
            const ChatWatchdogConfig(reconnectJitterMax: Duration.zero),
      ),
      if (staticState != null)
        chatControllerProvider.overrideWith(
          () => _StaticChatController(staticState),
        ),
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

/// done 路径用的最小会话快照（含权威 assistant 行）。
const DoneSseEvent _doneWithTranscript = DoneSseEvent(
  DoneStreamEvent(
    session: {
      'session_id': 's1',
      'messages': [
        {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
        {'role': 'assistant', 'content': 'hi', 'message_id': 'a1'},
      ],
    },
  ),
);

/// 服务端已收尾、客户端却留着流式子气泡 + 回合计时的「孤儿显示态」。
const ChatState _orphanDisplayState = ChatState(
  sessionId: 's1',
  phase: ChatPhase.idle,
  messages: [
    ChatMessage(
      role: 'assistant',
      content: '半截正文',
      messageId: 'stream-stale',
    ),
  ],
  turnStartedMillis: 1791861491000,
  stream: ChatStreamState(
    streamingAssistantMessageId: 'stream-stale',
    hasCompletedResponse: true,
  ),
);

/// 真回合进行中（不得被任何守卫误清）。
const ChatState _liveTurnState = ChatState(
  sessionId: 's1',
  phase: ChatPhase.streaming,
  messages: [
    ChatMessage(
      role: 'assistant',
      content: '正在吐字',
      messageId: 'stream-live',
    ),
  ],
  turnStartedMillis: 1791861491000,
  stream: ChatStreamState(
    activeStreamId: 'st1',
    streamingAssistantMessageId: 'stream-live',
  ),
);

void main() {
  group('#196 孤儿显示态：收尾对称清理（F2）', () {
    test('1. done 路径收尾 ⇒ 清回合计时（否则状态行永久显示「已工作 MM:SS」）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('s1')).stream.activeStreamId,
          isNotNull,
        );
        expect(
          container.read(chatControllerProvider('s1')).turnStartedMillis,
          isNotNull,
        );

        // 正文 token 已到（还没走完 merge tick）⇒ 缓冲里留着「待落账」正文。
        api.emit(const TokenSseEvent('半截正文'));
        async.flushMicrotasks();
        expect(
          container
              .read(chatControllerProvider('s1'))
              .stream
              .streamingAssistantMessageId,
          isNotNull,
          reason: '此时应存在流式子气泡',
        );

        // done 路径收尾（`_applyDone` → `_completeCurrentResponse`）。
        api.emit(_doneWithTranscript);
        async.flushMicrotasks();

        final settled = container.read(chatControllerProvider('s1'));
        expect(settled.stream.activeStreamId, isNull);
        expect(
          settled.turnStartedMillis,
          isNull,
          reason: '收尾必须清回合耗时，否则状态行永久显示「已工作 MM:SS」',
        );

        // 给任何残留定时器机会（收尾后不得有任何东西把消息状态再往前推）。
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));

        final after = container.read(chatControllerProvider('s1'));
        expect(after.turnStartedMillis, isNull);
        expect(after.pendingAssistantTokenChunks, isEmpty);
      });
    });

    test('2. 反向：stream_end 路径同样不留残渣（既有 _finishStream 语义不得回归）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('半截正文'));
        async.flushMicrotasks();

        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));

        final after = container.read(chatControllerProvider('s1'));
        expect(after.stream.activeStreamId, isNull);
        expect(after.stream.streamingAssistantMessageId, isNull);
        expect(after.turnStartedMillis, isNull);
        expect(after.pendingAssistantTokenChunks, isEmpty);
      });
    });

    test(
      '3. 反向：收尾后到达的迟到/重放内容帧 ⇒ 不得重建流式子气泡（owner-alive 守卫）',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller = container.read(
            chatControllerProvider('s1').notifier,
          );

          unawaited(controller.send('hi'));
          async.flushMicrotasks();
          api.emit(_doneWithTranscript);
          async.flushMicrotasks();
          expect(
            container.read(chatControllerProvider('s1')).stream.activeStreamId,
            isNull,
          );

          // 迟到 / 重放帧：owner-alive 守卫必须丢弃（不给它重建子气泡的机会）。
          api.emit(const TokenSseEvent('迟到正文'));
          clock.advance(const Duration(seconds: 8));
          async.elapse(const Duration(seconds: 8));
          async.flushMicrotasks();

          final after = container.read(chatControllerProvider('s1'));
          expect(
            after.stream.streamingAssistantMessageId,
            isNull,
            reason: '收尾后不得再重建流式子气泡（状态行据此显示「生成中」）',
          );
          expect(
            after.messages,
            hasLength(2),
            reason: '迟到帧不得新建消息行（权威 transcript 的 u1/a1 两行）',
          );
          expect(after.turnStartedMillis, isNull);
        });
      },
    );
  });

  group('#196 孤儿显示态：F1 守卫', () {
    test('4. 无活跃流 + 相位已离场但气泡/计时残留 ⇒ 看门狗清残渣并兜底拉 transcript', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          staticState: _orphanDisplayState,
        );
        container.read(chatControllerProvider('s1'));
        async.flushMicrotasks();

        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        final after = container.read(chatControllerProvider('s1'));
        expect(
          after.stream.streamingAssistantMessageId,
          isNull,
          reason: '孤儿子气泡必须被清（状态行据此显示「生成中」）',
        );
        expect(after.turnStartedMillis, isNull, reason: '回合计时必须被清');
        expect(
          api.sessionCalls,
          greaterThan(0),
          reason: '守卫应兜底拉一次权威 transcript',
        );
      });
    });

    test('5. 反向：真回合进行中（phase streaming + activeStreamId）⇒ 不得清显示态', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          staticState: _liveTurnState,
        );
        container.read(chatControllerProvider('s1'));
        async.flushMicrotasks();

        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        final after = container.read(chatControllerProvider('s1'));
        expect(after.stream.activeStreamId, 'st1');
        expect(after.stream.streamingAssistantMessageId, 'stream-live');
        expect(after.turnStartedMillis, isNotNull);
      });
    });
  });

  group('#197 强制刷新（forceRefresh）', () {
    test('6. 孤儿态 ⇒ 清残渣 + 拉权威 transcript + 返回 true', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          staticState: _orphanDisplayState,
        );
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );
        async.flushMicrotasks();

        bool? ok;
        unawaited(controller.forceRefresh().then((value) => ok = value));
        async.flushMicrotasks();

        expect(ok, isTrue);
        final after = container.read(chatControllerProvider('s1'));
        expect(after.stream.streamingAssistantMessageId, isNull);
        expect(after.turnStartedMillis, isNull);
        expect(api.sessionCalls, greaterThan(0));
      });
    });

    test('7. 反向：有活跃流 ⇒ 走状态链探活，不硬清显示态（不打断真回合）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final container = _buildContainer(
          api,
          clock,
          staticState: _liveTurnState,
        );
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );
        async.flushMicrotasks();

        bool? ok;
        unawaited(controller.forceRefresh().then((value) => ok = value));
        async.flushMicrotasks();

        expect(ok, isTrue);
        expect(
          api.statusCalls,
          1,
          reason: '有活跃流时必须走 status 探活链，而不是硬清显示态',
        );
        expect(
          container.read(chatControllerProvider('s1')).stream.activeStreamId,
          'st1',
          reason: '不得把进行中的流清掉',
        );
      });
    });
  });
}

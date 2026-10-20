import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 取证探针：done 收尾帧（全量 transcript）落地后，界面上到底是
/// 「一条 assistant 行」还是「两条一模一样的 assistant 行」。
///
/// 背景（实测现象）：live 回复生成完毕后要等很久才弹「已完成」，主人观感像是
/// 「重新拉取了一遍这个生成完毕的回复」。本探针把该现象落到可断言的层面：
///
/// - 场景 A：done 帧带全量 transcript（服务端真实形态，_session_payload_with_full_messages），
///   服务端内容与本地流式内容**完全一致** → 期望本地流式行退场，只剩一条。
/// - 场景 B：done 帧带全量 transcript，但服务端内容**与本地流式内容不同**
///   （服务端 trim/改写了尾部）→ 考察是否两条并存。
/// - 场景 C：done 帧**不带** transcript（hasCompletedTranscript=false）
///   → 走 needsTranscriptRefresh 路径，考察是否补拉。
///
/// 判定口径：assistant 行的**内容指纹**（去空白后取前缀 + 长度），
/// 指纹相同且行数 > 1 ⇒ 「两组完全一样的文本」确实并存。
void main() {
  group('取证：done 收尾帧落地后的消息行（是否两组重复文本）', () {
    test('场景 A：done 带全量 transcript 且内容与服务端一致 → 只应剩一条', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 本地流式正文（分段 token，模拟真实流式）
        api.emit(const TokenSseEvent('这是一段'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('很长的最终回复正文。'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        final beforeRows = _assistantRows(controller.state);
        debugPrint('【场景A】done 落地前 assistant 行数=${beforeRows.length}');
        for (final r in beforeRows) {
          debugPrint('  · ${r.id} · ${r.fingerprint}');
        }

        // done 帧：服务端全量 transcript，正文与本地流式一致（真实形态）
        api.emit(
          DoneSseEvent(
            DoneStreamEvent(
              usage: const {'input_tokens': 10, 'output_tokens': 20},
              session: _rawSession([
                _userRaw('hi'),
                _assistantRaw('这是一段很长的最终回复正文。', 'm-final'),
              ]),
            ),
          ),
        );
        async.flushMicrotasks();

        final afterRows = _assistantRows(controller.state);
        debugPrint('【场景A】done 落地后 assistant 行数=${afterRows.length}');
        for (final r in afterRows) {
          debugPrint('  · ${r.id} · ${r.fingerprint}');
        }

        final dup = _duplicateFingerprints(afterRows);
        debugPrint('【场景A】重复指纹=$dup');

        expect(
          afterRows.length,
          1,
          reason: '内容一致时，本地流式行应退场，不应出现两条 assistant 行',
        );
        expect(dup, isEmpty, reason: '不应存在内容完全相同的两行');
        expect(controller.state.stream.hasCompletedResponse, isTrue);
        expect(controller.state.phase, ChatPhase.idle);
      });
    });

    test('场景 B：done 带全量 transcript 但服务端内容被改写 → 观察是否并存两条', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('本地流式正文'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        // 服务端把正文 trim 并追加了尾部（真实后处理差异的最小复现）
        api.emit(
          DoneSseEvent(
            DoneStreamEvent(
              usage: const {'input_tokens': 10},
              session: _rawSession([
                _userRaw('hi'),
                _assistantRaw('本地流式正文（服务端补充）', 'm-final'),
              ]),
            ),
          ),
        );
        async.flushMicrotasks();

        final afterRows = _assistantRows(controller.state);
        debugPrint('【场景B】done 落地后 assistant 行数=${afterRows.length}');
        for (final r in afterRows) {
          debugPrint('  · ${r.id} · ${r.fingerprint}');
        }
        final dup = _duplicateFingerprints(afterRows);
        debugPrint('【场景B】重复指纹=$dup');

        // 这里不断言「必须一条」——本用例只做取证记录，
        // 真实结论以输出的行数与指纹为准。
        expect(controller.state.stream.hasCompletedResponse, isTrue);
      });
    });

    test('场景 D：done 落地时行身份从 stream- 换成服务端 id（动画重播的成因）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('同一段正文'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        final idBefore = controller.state.messages
            .where((m) => m.role == 'assistant')
            .map((m) => m.messageId)
            .toList();
        final streamingIdBefore = controller.state.stream.streamingAssistantMessageId;

        api.emit(
          DoneSseEvent(
            DoneStreamEvent(
              usage: const {'input_tokens': 10},
              session: _rawSession([
                _userRaw('hi'),
                _assistantRaw('同一段正文', 'm-final'),
              ]),
            ),
          ),
        );
        async.flushMicrotasks();

        final idAfter = controller.state.messages
            .where((m) => m.role == 'assistant')
            .map((m) => m.messageId)
            .toList();
        debugPrint('【场景D】落地前 id=$idBefore (streaming=$streamingIdBefore)');
        debugPrint('【场景D】落地后 id=$idAfter');

        // 行数恒为 1（无重复），但**行的身份变了** ⇒ 渲染层视为新行 ⇒ 气泡重建、
        // 动画重播。这就是主人看到的「重新拉取了一遍这个生成完毕的回复」。
        expect(idAfter.length, 1, reason: '行数不变');
        expect(
          idBefore,
          isNot(idAfter),
          reason: '行身份确实被服务端 id 替换（气泡重建 ⇒ 动画重播）',
        );
        expect(idAfter.single, 'm-final');
      });
    });

    test('场景 E：done 带 200 条全量 transcript → 落地后必须裁到 50 条窗口内', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 服务端全量 transcript：100 轮 user/assistant（真实 done 帧形态）
        final serverRows = <Map<String, Object?>>[];
        for (var i = 0; i < 100; i++) {
          serverRows.add(_userRaw('问题 $i'));
          serverRows.add(_assistantRaw('回答 $i', 'm-$i'));
        }
        debugPrint('【场景E】done 帧携带 ${serverRows.length} 条消息');

        api.emit(
          DoneSseEvent(
            DoneStreamEvent(
              usage: const {'input_tokens': 10},
              session: _rawSession(serverRows),
            ),
          ),
        );
        async.flushMicrotasks();

        final rows = controller.state.messages;
        debugPrint('【场景E】落地后 state.messages 行数=${rows.length}');
        final ids = rows.map((m) => m.messageId).whereType<String>().toList();
        debugPrint('【场景E】首行=${ids.first} 末行=${ids.last}');
        debugPrint('【场景E】全部 id=${ids.join(",")}');

        expect(
          rows.length,
          lessThanOrEqualTo(60),
          reason: 'done 落地后 state.messages 必须被裁到窗口量级，不能是整表 200 条',
        );
        expect(
          ids.last,
          'm-99',
          reason: '必须保留**尾部**（最新一轮），不能裁掉最新内容',
        );
        expect(
          ids.contains('m-75'),
          isTrue,
          reason: '窗口应覆盖最近 50 条**可渲染**行 = 25 轮 user+assistant（起点 m-75）',
        );
        expect(
          ids.contains('m-74'),
          isFalse,
          reason: '第 26 轮已在窗口外，不该被塞进显示态（分页另走 REST）',
        );
      });
    });

    test('场景 C：done 不带 transcript → 走补拉路径，记录补拉次数与最终行数', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResponse = _session(messages: [_user('hi')]);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('sess-1').notifier,
        );
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('本地流式正文'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        // done 帧**不带** session.messages（另一条真实契约形态）
        api.emit(
          const DoneSseEvent(DoneStreamEvent(usage: {'input_tokens': 10})),
        );
        async.flushMicrotasks();

        final rowsBeforeRefresh = _assistantRows(controller.state);
        debugPrint(
          '【场景C】done 落地后（补拉前）assistant 行数=${rowsBeforeRefresh.length}',
        );
        for (final r in rowsBeforeRefresh) {
          debugPrint('  · ${r.id} · ${r.fingerprint}');
        }
        expect(
          controller.state.responseCompletionNeedsTranscriptRefresh,
          isTrue,
          reason: '无 transcript 的 done 必须标记待补拉',
        );

        // 500ms 后补拉触发：status 检查 + loadMessages
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        debugPrint('【场景C】补拉后 sessionCalls=${api.sessionCalls}');

        final afterRows = _assistantRows(controller.state);
        debugPrint('【场景C】补拉后 assistant 行数=${afterRows.length}');
        for (final r in afterRows) {
          debugPrint('  · ${r.id} · ${r.fingerprint}');
        }
        final dup = _duplicateFingerprints(afterRows);
        debugPrint('【场景C】重复指纹=$dup');

        expect(api.sessionCalls, greaterThan(0), reason: '应发生一次 REST 补拉');
        expect(dup, isEmpty, reason: '补拉后不应出现两条完全相同的内容');
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 探针工具
// ---------------------------------------------------------------------------

class _RowProbe {
  const _RowProbe(this.id, this.fingerprint, this.content);

  final String id;
  final String fingerprint;
  final String content;
}

/// 取当前 state 里的 assistant 行（按内容去空白后的指纹 + 长度作为内容指纹）。
List<_RowProbe> _assistantRows(ChatState state) {
  return state.messages
      .where((m) => m.role == 'assistant')
      .map(
        (m) => _RowProbe(
          m.messageId ?? '(no-id)',
          _fingerprint(m.content ?? ''),
          m.content ?? '',
        ),
      )
      .toList();
}

/// 内容指纹：去空白后取前 24 字符 + 总长。足以判别「是否同一段文本」。
String _fingerprint(String content) {
  final squeezed = content.replaceAll(RegExp(r'\s+'), '');
  final head = squeezed.length <= 24
      ? squeezed
      : squeezed.substring(0, 24);
  return '$head…(len=${squeezed.length})';
}

/// 找出内容指纹重复的行（= 「两组完全一样的文本」确实并存）。
List<String> _duplicateFingerprints(List<_RowProbe> rows) {
  final counts = <String, int>{};
  for (final r in rows) {
    counts[r.fingerprint] = (counts[r.fingerprint] ?? 0) + 1;
  }
  return counts.entries
      .where((e) => e.value > 1)
      .map((e) => '${e.key} ×${e.value}')
      .toList();
}

// ---------------------------------------------------------------------------
// 测试基建
// ---------------------------------------------------------------------------

ChatMessage _user(String content) =>
    ChatMessage(role: 'user', content: content, timestamp: 1);

SessionResponse _session({required List<ChatMessage> messages}) =>
    SessionResponse(
      session: SessionDetail(sessionId: 'sess-1', messages: messages),
    );

Map<String, Object?> _userRaw(String content) => {
  'role': 'user',
  'content': content,
  'timestamp': 1,
  'message_id': 'm-user',
};

Map<String, Object?> _assistantRaw(String content, String id) => {
  'role': 'assistant',
  'content': content,
  'timestamp': 2,
  'message_id': id,
};

/// done 帧里的 session 载荷（服务端真实形态：全量 messages 数组）。
Map<String, Object?> _rawSession(List<Map<String, Object?>> messages) => {
  'session_id': 'sess-1',
  'title': '测试会话',
  'message_count': messages.length,
  'messages': messages,
};

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
      chatWatchdogConfigProvider.overrideWithValue(
        const ChatWatchdogConfig(
          fullReconnectCooldown: Duration.zero,
          reconnectJitterMax: Duration.zero,
        ),
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

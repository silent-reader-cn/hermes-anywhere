// 聊天消息列表「key → rawIndex 反查」（`ListView.builder` 的
// `findChildIndexCallback`）守禁用例。
//
// ## 治理对象（危害形状）
// `ChatMessageList` 的消息列表是 `ListView.builder(reverse: true)`，itemBuilder
// 首行做反向映射 `逻辑下标 = itemCount - 1 - rawIndex`。于是「末尾追加一条消息」
// 或「头部插入一页历史」会让**每个 rawIndex 对应的逻辑条目整体错位**；而该
// delegate 未传 `findChildIndexCallback` ⇒ `SliverChildBuilderDelegate
// .findIndexByKey` 恒返回 null（scroll_delegate.dart）⇒ SDK 的
// `SliverMultiBoxAdaptorElement.performRebuild`（sliver.dart）只会按**位置**
// `updateChild`：位置上的 widget key 变了 ⇒ 已挂载元素被整体销毁重建
// （整屏重建；滚动锚点、动画/选区等元素级状态随之丢失）。
//
// ## 判据
// 唯一判据 = **元素对象 `identical`**：同一 `msg-item:<renderId>` key 在前后的
// [Element] 必须还是同一个对象。另加「不串内容」守卫：反查一旦错位（把元素搬到
// 错下标）会出现同一行文本重复挂载 / 条目显示别人的内容，故断言每个已挂载条目的
// 子树里恰有它自己的那一行、且该行全局只出现一次。
//
// 修复前这些用例必须 RED（kept=0 / recreated=屏上挂载数）。
//
// 说明（判据边界）：常规视口下追加/插入会让**视口边缘（cacheExtent 之外）**的
// 少数条目滚出而被正常销毁 —— 那不是本缺陷的表征，故 A1/B1 用 `gone` 显式记账并
// 只允许极少数；A2/B2 用「全部落在视口内」的高视口把这一干扰项清零，断言
// **kept == 追加前挂载数**（一条不重建、一条不消失）。
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

/// 可控 ChatState 的控制器：`push` 直接替换状态（模拟分页插入 / 服务端重载）。
class _PuppetChatController extends ChatController {
  _PuppetChatController(this._initial);

  final ChatState _initial;

  @override
  ChatState build(String sessionId) => _initial;

  @override
  Future<void> loadYoloState() async {}

  @override
  Future<void> syncMissingMessages({int limit = 50}) async {}

  void push(ChatState next) => state = next;
}

/// 第 i 行的内容恒为 `行 $i`，且 renderId = `transcript:${offset + i}`
/// ⇒ `行 <renderId 数字后缀>` 恒为该条目自己的那一行（负数同样成立）。
List<ChatMessage> _rows(int from, int to) => [
  for (var i = from; i < to; i++)
    ChatMessage(
      role: i.isEven ? 'user' : 'assistant',
      content: '行 $i',
      messageId: 'm$i',
    ),
];

const String _itemKeyPrefix = 'msg-item:';

/// 高亮靶点的独立前缀（与 lib 内 `_highlightKeyPrefix` 同值）。
const String _highlightItemKeyPrefix = 'msg-item-hl:';

/// 屏上已挂载条目：`renderId → 锚点元素`（`msg-item:<renderId>` 包装层）。
Map<String, Element> _mounted(WidgetTester tester) => tester
    .state<ChatMessageListState>(find.byType(ChatMessageList))
    .mountedItemElements;

/// 复用报告：同一 key 在前后的元素是否为**同一个对象**。
class _Reuse {
  _Reuse({
    required this.before,
    required this.after,
    required this.kept,
    required this.recreated,
    required this.gone,
    required this.recreatedIds,
  });

  final int before;
  final int after;
  final int kept;
  final int recreated;
  final int gone;
  final List<String> recreatedIds;

  @override
  String toString() =>
      '挂载 $before → $after，kept=$kept recreated=$recreated gone=$gone'
      '${recreatedIds.isEmpty ? '' : '（重建样例：${recreatedIds.take(3).join(', ')}）'}';
}

_Reuse _reuse(Map<String, Element> before, Map<String, Element> after) {
  var kept = 0;
  var recreated = 0;
  var gone = 0;
  final recreatedIds = <String>[];
  for (final entry in before.entries) {
    final now = after[entry.key];
    if (now == null) {
      gone++;
      continue;
    }
    if (identical(entry.value, now)) {
      kept++;
    } else {
      recreated++;
      recreatedIds.add(entry.key);
    }
  }
  return _Reuse(
    before: before.length,
    after: after.length,
    kept: kept,
    recreated: recreated,
    gone: gone,
    recreatedIds: recreatedIds,
  );
}

/// 按 key 前缀收集挂载元素：`<前缀><id> → Element`。
Map<String, Element> _mountedByPrefix(WidgetTester tester, String prefix) {
  final found = <String, Element>{};
  final root = tester.element(find.byType(ChatMessageList));
  void visit(Element element) {
    final key = element.widget.key;
    if (key is ValueKey<String> && key.value.startsWith(prefix)) {
      found[key.value.substring(prefix.length)] = element;
    }
    element.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

Future<_PuppetChatController> _pumpList(
  WidgetTester tester, {
  required String sessionId,
  required List<ChatMessage> messages,
  int messagesOffset = 0,
  Size size = const Size(390, 844),
  String? highlightQuery,
}) => _pumpState(
  tester,
  ChatState(
    sessionId: sessionId,
    messages: messages,
    messagesOffset: messagesOffset,
  ),
  size: size,
  highlightQuery: highlightQuery,
);

Future<_PuppetChatController> _pumpState(
  WidgetTester tester,
  ChatState state, {
  Size size = const Size(390, 844),
  String? highlightQuery,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final controller = _PuppetChatController(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatControllerProvider.overrideWith(() => controller)],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: ChatMessageList(
            sessionId: state.sessionId,
            highlightQuery: highlightQuery,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return controller;
}

/// 直播态：streaming 锚定 `stream-1`（content = [content]），
/// live 段由 [points] 切成若干 `live:text:<seq>` 条目。
ChatState _liveState({
  required String sessionId,
  required String content,
  required List<LiveTimelinePoint> points,
}) => ChatState(
  sessionId: sessionId,
  messages: [
    ChatMessage(role: 'assistant', content: content, messageId: 'stream-1'),
  ],
  stream: const ChatStreamState(streamingAssistantMessageId: 'stream-1'),
  liveTimelinePoints: points,
);

/// 前 [count] 段正文断点（`live:text:0` … `live:text:${count - 1}`）。
List<LiveTimelinePoint> _textPoints(int count) => [
  for (var i = 0; i < count; i++)
    LiveTimelinePoint(kind: LiveSegmentKind.text, start: i, sequence: i),
];

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull, reason: '重建过程不得抛异常');
}

/// 「不串内容」守卫：每个已挂载 `msg-item:<renderId>` 的子树里恰有**它自己的**
/// 那一行，且该行在整棵树上只出现一次。
void _expectOwnTextOnce(WidgetTester tester, String phase) {
  final mounted = _mounted(tester);
  expect(mounted, isNotEmpty, reason: '$phase：应有已挂载条目');
  for (final id in mounted.keys) {
    expect(
      id,
      startsWith('transcript:'),
      reason: '$phase：本用例只涉及 transcript 条目（key=$id）',
    );
    final n = int.parse(id.substring('transcript:'.length));
    final row = '行 $n';
    final finder = find.descendant(
      of: find.byKey(ValueKey<String>('$_itemKeyPrefix$id')),
      matching: find.text(row),
    );
    expect(finder, findsOneWidget, reason: '$phase：$id 的子树里应恰有它自己的一行「$row」');
    expect(
      find.text(row),
      findsOneWidget,
      reason: '$phase：「$row」全局只应出现一次（重复出现 = 反查错位把元素搬到同一下标）',
    );
  }
}

void main() {
  group('A. 末尾追加一条消息：已挂载元素必须复用', () {
    testWidgets('A1 常规视口 390x844 / 40 条：recreated == 0（不得整屏重建）', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-append',
        messages: _rows(0, 40),
      );
      final before = _mounted(tester);
      expect(
        before.length,
        greaterThanOrEqualTo(20),
        reason: '前置条件：屏上应挂载一批条目（实为 ${before.length}）',
      );

      controller.push(ChatState(sessionId: 's-append', messages: _rows(0, 41)));
      await _settle(tester);

      final after = _mounted(tester);
      final reuse = _reuse(before, after);
      debugPrint('[A1 末尾追加] $reuse');
      expect(
        reuse.recreated,
        0,
        reason: '追加一条消息后，此前已挂载的元素必须全部复用（同一个 Element 对象），不得销毁重建。$reuse',
      );
      expect(
        reuse.kept,
        greaterThanOrEqualTo(before.length - 3),
        reason: '只允许视口边缘（cacheExtent 之外）的极少数条目滚出。$reuse',
      );
      expect(reuse.kept, greaterThan(0));
    });

    testWidgets('A2 全可见视口：kept == 追加前挂载数（一条不重建、一条不消失）', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-append-tall',
        messages: _rows(0, 24),
        size: const Size(390, 3600),
      );
      final before = _mounted(tester);
      expect(before.length, 24, reason: '前置条件：24 条应全部落在视口内（无滚动）');

      controller.push(
        ChatState(sessionId: 's-append-tall', messages: _rows(0, 25)),
      );
      await _settle(tester);

      final after = _mounted(tester);
      final reuse = _reuse(before, after);
      debugPrint('[A2 末尾追加·全可见] $reuse');
      expect(
        reuse.recreated,
        0,
        reason: '已挂载元素必须全部复用。$reuse',
      );
      expect(
        reuse.gone,
        0,
        reason: '全可见视口下不该有条目消失。$reuse',
      );
      expect(reuse.kept, before.length, reason: 'kept 应等于追加前挂载数。$reuse');
    });
  });

  group('B. 头部插入一页历史（renderId 稳定）：已挂载元素必须复用', () {
    testWidgets('B1 常规视口 390x844 / 40 → 60 条：recreated == 0', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-prepend',
        messages: _rows(0, 40),
      );
      final before = _mounted(tester);
      expect(before.length, greaterThanOrEqualTo(20), reason: '前置条件：屏上应有已挂载条目');

      // 头部插入一页历史：messagesOffset 随之下移 20，
      // 既有条目的 renderId（= offset + i）因此**保持不变**（真实分页的形态）。
      controller.push(
        ChatState(
          sessionId: 's-prepend',
          messages: [..._rows(-20, 0), ..._rows(0, 40)],
          messagesOffset: -20,
        ),
      );
      await _settle(tester);

      final after = _mounted(tester);
      final reuse = _reuse(before, after);
      debugPrint('[B1 头部插入一页历史] $reuse');
      expect(
        reuse.recreated,
        0,
        reason: '头部插入一页历史后，既有条目（renderId 未变）必须复用同一元素。$reuse',
      );
      expect(
        reuse.kept,
        greaterThanOrEqualTo(before.length - 3),
        reason: '只允许视口边缘的极少数条目滚出。$reuse',
      );
      expect(reuse.kept, greaterThan(0));
    });

    testWidgets('B2 全可见视口：kept == 插入前挂载数（一条不重建、一条不消失）', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-prepend-tall',
        messages: _rows(0, 20),
        size: const Size(390, 3600),
      );
      final before = _mounted(tester);
      expect(before.length, 20, reason: '前置条件：20 条应全部落在视口内');

      controller.push(
        ChatState(
          sessionId: 's-prepend-tall',
          messages: [..._rows(-5, 0), ..._rows(0, 20)],
          messagesOffset: -5,
        ),
      );
      await _settle(tester);

      final after = _mounted(tester);
      final reuse = _reuse(before, after);
      debugPrint('[B2 头部插入·全可见] $reuse');
      expect(reuse.recreated, 0, reason: '已挂载元素必须全部复用。$reuse');
      expect(reuse.gone, 0, reason: '全可见视口下不该有条目消失。$reuse');
      expect(reuse.kept, before.length, reason: 'kept 应等于插入前挂载数。$reuse');
    });
  });

  group('C. 对照组：内容不变重推', () {
    testWidgets('C 同内容同下标重推 → 全部复用（证明 identical 判据本身有效）', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-same',
        messages: _rows(0, 40),
      );
      final before = _mounted(tester);
      expect(before.length, greaterThanOrEqualTo(20), reason: '前置条件：屏上应有已挂载条目');

      controller.push(ChatState(sessionId: 's-same', messages: _rows(0, 40)));
      await _settle(tester);

      final after = _mounted(tester);
      final reuse = _reuse(before, after);
      debugPrint('[C 内容不变重推] $reuse');
      expect(reuse.recreated, 0, reason: '下标未动时元素本就应复用（判据自证有效）。$reuse');
      expect(reuse.gone, 0, reason: '下标未动时不该有条目消失。$reuse');
      expect(reuse.kept, before.length, reason: 'kept 应等于全部已挂载条目。$reuse');
    });
  });

  group('D. 不串内容（反查错位的唯一鉴别判据）', () {
    testWidgets('D 追加 + 头部插入后：每个条目仍显示它自己的那一行（各只出现一次）', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-content',
        messages: _rows(0, 24),
        size: const Size(390, 3600),
      );
      _expectOwnTextOnce(tester, '初始');

      controller.push(ChatState(sessionId: 's-content', messages: _rows(0, 25)));
      await _settle(tester);
      _expectOwnTextOnce(tester, '末尾追加后');

      controller.push(
        ChatState(
          sessionId: 's-content',
          messages: [..._rows(-6, 0), ..._rows(0, 25)],
          messagesOffset: -6,
        ),
      );
      await _settle(tester);
      _expectOwnTextOnce(tester, '头部插入一页历史后');
    });
  });

  group('E. 高亮目标（独立前缀键 msg-item-hl:）同样走反查', () {
    testWidgets('E 高亮态下追加一条消息：高亮条目元素仍复用、高亮靶点不跑偏', (tester) async {
      final controller = await _pumpList(
        tester,
        sessionId: 's-hl',
        messages: _rows(0, 24),
        size: const Size(390, 3600),
        highlightQuery: '行 20',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      final before = _mountedByPrefix(tester, _highlightItemKeyPrefix);
      expect(
        before.keys,
        contains('transcript:20'),
        reason: '前置条件：高亮靶点应挂 msg-item-hl:transcript:20（实为 ${before.keys}）',
      );

      controller.push(ChatState(sessionId: 's-hl', messages: _rows(0, 25)));
      await _settle(tester);

      final after = _mountedByPrefix(tester, _highlightItemKeyPrefix);
      expect(
        after.keys.toSet(),
        before.keys.toSet(),
        reason: '高亮靶点键集合不得变化（键变了说明高亮语义被反查带偏）',
      );
      for (final id in before.keys) {
        expect(
          identical(before[id], after[id]),
          isTrue,
          reason: '高亮条目 $id 的元素必须复用（不传高亮键反查时会被整屏重建）',
        );
      }
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('${_highlightItemKeyPrefix}transcript:20'),
          ),
          matching: find.text('行 20'),
        ),
        findsOneWidget,
        reason: '高亮靶点子树里应仍是它自己的那一行',
      );
    });
  });

  group('F. live 时间线条目（msg-item:live:*）同样走反查', () {
    testWidgets('F 流式尾部新增一段：既有 live 段元素必须复用（不得整屏重建）', (tester) async {
      final controller = await _pumpState(
        tester,
        _liveState(
          sessionId: 's-live',
          content: 'AAA',
          points: _textPoints(3),
        ),
        size: const Size(390, 3600),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      final before = _mounted(tester);
      final liveIds = before.keys.where((k) => k.startsWith('live:')).toList();
      expect(
        liveIds.length,
        3,
        reason: '前置条件：3 段 live 正文应各挂一个 msg-item:live:text:<seq>（实为 ${before.keys}）',
      );

      // 流式推进：正文增长 + 尾部新增一段（既有段的 renderKey 不变）。
      controller.push(
        _liveState(sessionId: 's-live', content: 'AAAA', points: _textPoints(4)),
      );
      await _settle(tester);

      final after = _mounted(tester);
      final reuse = _reuse(before, after);
      debugPrint('[F live 尾部新增一段] $reuse');
      expect(
        reuse.recreated,
        0,
        reason: 'live 段错位（尾部新增一段 ⇒ 既有段 rawIndex 全体 +1）也必须复用同一元素。$reuse',
      );
      expect(reuse.kept, before.length, reason: 'kept 应等于新增前挂载数。$reuse');
    });
  });
}

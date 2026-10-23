import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';

/// done 帧落地路径的**坐标换算**守卫（2026-10-23 真机 bug）。
///
/// 服务端 done 帧给的是**全量** messages + **全量** tool_calls（`assistant_msg_idx`
/// 为全转写下标，`api/streaming.py::_session_payload_with_full_messages`），
/// 而客户端只把 messages 裁成尾部窗口。若把 persisted 原样交给
/// [ToolCallGroup.groups]，`_resolveLoadedMessageIndex` 的「相对候选优先」会把
/// **会话最早那批工具**当成窗口内下标 —— 现象：
/// ① 回合过程胶囊「终端×43 / 视觉×21」远超真值（真值 6 / 1）；
/// ② 最后一个文本节点之后冒出一张含 `read_file`（本回合根本没调过）的卡；
/// ③ 相邻折叠卡不合并。
///
/// 本文件钉住三件事：窗口起点可见（`_tailWindowRange`）、persisted 按窗口裁剪并
/// rebase（`_persistedToolCallsForWindow`）、以及「不换算 ⇒ 历史工具必然挂进来」
/// 这条 RED 判据（防止有人日后把换算删掉还以为测试在保护）。
void main() {
  /// 造一份「全转写」消息表：每回合 = user + assistant(带工具) + tool 结果。
  /// 历史回合的工具名统一用 `terminal`，最后一回合用 `vision_analyze` 作指纹。
  List<ChatMessage> buildAllMessages(int turns, {required int totalTurns}) {
    final out = <ChatMessage>[];
    for (var t = 0; t < turns; t++) {
      final isLastTurn = t == totalTurns - 1;
      final toolName = isLastTurn ? 'vision_analyze' : 'terminal';
      out.add(
        ChatMessage.fromJson({'role': 'user', 'content': 'question $t'}),
      );
      out.add(
        ChatMessage.fromJson({
          'role': 'assistant',
          'content': 'answer $t',
          'reasoning': 'reasoning $t',
          'tool_calls': [
            {
              'id': 'tid-$t',
              'function': {'name': toolName, 'arguments': '{}'},
            },
          ],
        }),
      );
      out.add(
        ChatMessage.fromJson({
          'role': 'tool',
          'name': toolName,
          'tool_call_id': 'tid-$t',
          'content': '{"ok": true}',
        }),
      );
    }
    return out;
  }

  /// persisted 调用：`assistant_msg_idx` 用**全转写坐标**（= 声明它的 assistant 行下标）。
  List<PersistedToolCall> buildPersisted(int totalTurns) {
    final out = <PersistedToolCall>[];
    for (var t = 0; t < totalTurns; t++) {
      out.add(
        PersistedToolCall(
          name: t == totalTurns - 1 ? 'vision_analyze' : 'terminal',
          tid: 'tid-$t',
          assistantMsgIdx: t * 3 + 1,
        ),
      );
    }
    return out;
  }

  const totalTurns = 40;

  test('tailWindowRange 给出窗口起点，rows 与 tailWindow 一致', () {
    final all = buildAllMessages(totalTurns, totalTurns: totalTurns);
    final range = ChatController.tailWindowRangeForTesting(all, 50);
    final rows = ChatController.tailWindowForTesting(all, 50);

    expect(range.rows.length, rows.length);
    expect(range.rows.first, rows.first);
    expect(range.start, all.length - range.rows.length);
    expect(range.start, greaterThan(0), reason: '本构造必须真的发生裁窗');
  });

  test('窗口不足/恰好命中时不裁窗，起点为 0', () {
    final all = buildAllMessages(5, totalTurns: 5);
    final range = ChatController.tailWindowRangeForTesting(all, 50);
    expect(range.start, 0);
    expect(range.rows.length, all.length);
  });

  test('persistedToolCallsForWindow：裁掉窗口外、窗口内下标 rebase', () {
    final all = buildAllMessages(totalTurns, totalTurns: totalTurns);
    final persisted = buildPersisted(totalTurns);
    final range = ChatController.tailWindowRangeForTesting(all, 50);

    final windowed = ChatController.persistedToolCallsForWindowForTesting(
      persisted,
      windowStart: range.start,
      windowLength: range.rows.length,
    );

    expect(windowed, isNotEmpty);
    expect(
      windowed.length,
      lessThan(persisted.length),
      reason: '窗口外的历史调用必须被裁掉',
    );
    for (final call in windowed) {
      final idx = call.assistantMsgIdx!;
      expect(idx, inInclusiveRange(0, range.rows.length - 1));
      expect(
        range.rows[idx].role,
        'assistant',
        reason: 'rebase 后下标必须仍指向 assistant 行',
      );
      expect(call.tid, isNot('tid-0'), reason: '会话最早的调用不得留在窗口里');
    }
  });

  test('窗口形态的 done 帧（windowStart == 0）不改动 persisted', () {
    final persisted = buildPersisted(3);
    final windowed = ChatController.persistedToolCallsForWindowForTesting(
      persisted,
      windowStart: 0,
      windowLength: 9,
    );
    expect(windowed, same(persisted));
  });

  group('端到端：窗口内的回合只挂自己的工具', () {
    late List<ChatMessage> all;
    late List<PersistedToolCall> persisted;
    late ({List<ChatMessage> rows, int start}) range;

    setUp(() {
      all = buildAllMessages(totalTurns, totalTurns: totalTurns);
      persisted = buildPersisted(totalTurns);
      range = ChatController.tailWindowRangeForTesting(all, 50);
    });

    /// 复刻 done 路径的装配（chat_controller._applyCompletedStreamSession）：
    /// 裁窗 → 换算 persisted → groups(coalesce: false, 与截图设置一致)。
    List<ToolCallGroup> groupsForDonePath({required bool convert}) {
      final windowed = convert
          ? ChatController.persistedToolCallsForWindowForTesting(
              persisted,
              windowStart: range.start,
              windowLength: range.rows.length,
            )
          : persisted; // 修复前的形态：全量坐标 + 裁窗后的 messages
      return ToolCallGroup.groups(
        persistedToolCalls: windowed,
        messages: range.rows,
        // 修复前 done 路径传的是**旧的** state.messagesOffset（真机上 133 远大于
        // 窗口行数 ⇒ 绝对候选全为负、只剩「相对」单解 ⇒ 旧代码不跑 tid 自证）。
        // 这里照真实场景复刻，否则 `messageOffset == windowStart` 会让两解重叠、
        // 自证兜底把错位救回来，RED 判据就失去鉴别力。
        messageOffset: convert ? range.start : 133,
        coalesce: false,
        hideThinking: false,
      );
    }

    /// 窗口内每条 assistant 行声明的工具 tid（= 「本该挂上来的调用」全集）。
    Set<String> expectedTidsInWindow() {
      final ids = <String>{};
      for (var i = 0; i < range.rows.length; i++) {
        if (range.rows[i].role != 'assistant') continue;
        // 合成数据里每回合 3 行（user / assistant / tool），assistant 在全转写
        // 坐标 `3t+1`，故 tid 由**全转写下标**反推（窗口局部下标不算）。
        final fullIndex = range.start + i;
        ids.add('tid-${(fullIndex - 1) ~/ 3}');
      }
      return ids;
    }

    Set<String> tidsInGroups(List<ToolCallGroup> groups) => {
      for (final g in groups)
        for (final c in g.toolCalls)
          if (!c.isThinking) c.id,
    };

    test('换算后：挂上来的调用恰好等于窗口内 assistant 声明的那些', () {
      final groups = groupsForDonePath(convert: true);
      final got = tidsInGroups(groups);
      final want = expectedTidsInWindow();
      expect(got, want);
      expect(got, isNot(contains('tid-0')), reason: '会话最早的调用不得挂进窗口');
      // 只数真实工具行（think 子卡行不算），口径与胶囊标题一致。
      final calls = groups.fold<int>(
        0,
        (a, g) => a + g.toolCalls.where((c) => !c.isThinking).length,
      );
      expect(calls, want.length);
    });

  });

  test('RED 判据：消息不带 per-message tool_calls 时，不做换算必然错位挂载', () {
    // 服务端注释明说：老消息可能只有 **session 级** tool_calls（无 per-message 变体，
    // 见 routes.py「Always include session-level tool_calls ... for messages that lack
    // the per-message variant」）。这种形态下 metadata 兜底派生不出组，错位无处可救
    // —— 正是真机「胶囊 终端×43 / 视觉×21（全量前 82 条统计）+ 卡里冒出本回合根本
    // 没调过的 read_file」的形态。
    final bareAll = <ChatMessage>[];
    for (var t = 0; t < totalTurns; t++) {
      bareAll.add(ChatMessage.fromJson({'role': 'user', 'content': 'q$t'}));
      bareAll.add(ChatMessage.fromJson({'role': 'assistant', 'content': 'a$t'}));
      bareAll.add(
        ChatMessage.fromJson({
          'role': 'tool',
          'name': 'terminal',
          'tool_call_id': 'tid-$t',
          'content': '{}',
        }),
      );
    }
    final bareRange = ChatController.tailWindowRangeForTesting(bareAll, 50);
    final persisted = buildPersisted(totalTurns);
    expect(bareRange.start, greaterThan(0));

    Set<String> tidsOf(List<ToolCallGroup> groups) => {
      for (final g in groups)
        for (final c in g.toolCalls)
          if (!c.isThinking) c.id,
    };

    // 修复前的形态：全量坐标 + 旧的 state.messagesOffset（真机 133 > 窗口行数）。
    final broken = ToolCallGroup.groups(
      persistedToolCalls: persisted,
      messages: bareRange.rows,
      messageOffset: 133,
      coalesce: false,
      hideThinking: false,
    );
    final brokenTids = tidsOf(broken);
    expect(
      brokenTids,
      contains('tid-0'),
      reason: '不换算时全量前缀被当成窗口内下标 —— 修复前正是靠这条红',
    );

    // 修复后的形态：按窗口裁剪 + rebase，offset 与 messages 同基准。
    final windowed = ChatController.persistedToolCallsForWindowForTesting(
      persisted,
      windowStart: bareRange.start,
      windowLength: bareRange.rows.length,
    );
    final fixed = ToolCallGroup.groups(
      persistedToolCalls: windowed,
      messages: bareRange.rows,
      messageOffset: bareRange.start,
      coalesce: false,
      hideThinking: false,
    );
    final fixedTids = tidsOf(fixed);
    expect(fixedTids, isNot(contains('tid-0')));
    expect(
      fixedTids,
      isNot(equals(brokenTids)),
      reason: '修复必须让装配结果与「修复前」不同，否则判据无鉴别力',
    );
    final windowAssistants =
        bareRange.rows.where((m) => m.role == 'assistant').length;
    expect(fixedTids.length, windowAssistants);
  });

  test('源码守卫：done 落地路径必须走窗口换算（防接线被删）', () {
    final src = File(
      'lib/features/chat/chat_controller.dart',
    ).readAsStringSync();
    final start = src.indexOf('void _applyCompletedStreamSession(');
    expect(start, greaterThan(0), reason: '找不到 done 落地函数');
    final body = src.substring(
      start,
      src.indexOf('/// 服务端 transcript 与本地合并', start),
    );
    expect(body, contains('_tailWindowRange('), reason: '必须拿到窗口起点');
    expect(
      body,
      contains('_persistedToolCallsForWindow('),
      reason: '全量 tool_calls 必须换算到窗口坐标，否则历史工具整批错位挂载',
    );
    expect(
      body,
      isNot(contains('_tailWindow(allLoaded,')),
      reason: '退回旧写法即复发（全量坐标 + 裁窗 messages）',
    );
  });
}

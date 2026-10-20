// 集成取证：用**真实后端会话数据**驱动客户端 done 帧处理路径，验证裁窗在
// 真实数据规模下的行为。
//
// 用法：
//   dart run tool/probe_done_real_session.dart \
//     "C:/Users/Admin/AppData/Local/hermes/webui_30002/sessions/<sid>.json"
//
// 目的：单元测试用的是合成数据（200 条）；本探针用真实会话（含 tool_calls
// 内嵌、user 双形态等真实形态），验证：
//   1) done 帧的**真实**全量 transcript 体积；
//   2) 裁窗后体积与行数；
//   3) 裁窗是否丢掉了本轮**最新**的 assistant 行（致命回归）。
import 'dart:convert';
import 'dart:io';

Object? findMsgs(Object? obj, [int depth = 0]) {
  if (depth > 4) return null;
  if (obj is Map) {
    final m = obj['messages'];
    if (m is List) return m;
    for (final v in obj.values) {
      final r = findMsgs(v, depth + 1);
      if (r != null) return r;
    }
  } else if (obj is List) {
    for (final v in obj) {
      final r = findMsgs(v, depth + 1);
      if (r != null) return r;
    }
  }
  return null;
}

bool isRenderable(Map<String, dynamic> m) {
  final role = m['role'];
  if (role == 'assistant') return true;
  if (role != 'user') return false;
  final tcid = m['tool_call_id'];
  final tuid = m['tool_use_id'];
  if ((tcid is String && tcid.isNotEmpty) ||
      (tuid is String && tuid.isNotEmpty)) {
    return false;
  }
  final content = (m['content'] ?? '').toString().trim();
  if (content.isNotEmpty) return true;
  final att = m['attachments'];
  return att is List && att.isNotEmpty;
}

/// 与客户端 `_tailWindow` 同构的裁窗。
List<Map<String, dynamic>> tailWindow(
  List<Map<String, dynamic>> msgs,
  int size,
) {
  if (msgs.length <= size) return msgs;
  var start = msgs.length;
  var renderable = 0;
  for (var i = msgs.length - 1; i >= 0; i--) {
    if (!isRenderable(msgs[i])) continue;
    renderable++;
    if (renderable >= size) {
      start = i;
      break;
    }
  }
  if (renderable < size) {
    start = 0;
    for (var i = 0; i < msgs.length; i++) {
      if (isRenderable(msgs[i])) continue;
      start = i + 1;
    }
  }
  final windowToolCallIds = <String>{};
  for (var i = start; i < msgs.length; i++) {
    final id = msgs[i]['tool_call_id'] ?? msgs[i]['tool_use_id'];
    if (id is String && id.isNotEmpty) windowToolCallIds.add(id);
  }
  while (start > 0) {
    final prev = msgs[start - 1];
    if (isRenderable(prev)) break;
    final id = prev['tool_call_id'] ?? prev['tool_use_id'];
    if (id is! String || !windowToolCallIds.contains(id)) break;
    start--;
  }
  return msgs.sublist(start);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/probe_done_real_session.dart <会话json>');
    exit(2);
  }
  final file = File(args.first);
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final msgs = ((findMsgs(decoded) as List?) ?? const [])
      .cast<Map<String, dynamic>>();

  stdout.writeln('=== 真实会话：${file.path.split(RegExp(r"[/\\\\]")).last} ===');
  stdout.writeln('全量消息: ${msgs.length} 条');
  stdout.writeln('总行数(含工具结果): ${msgs.length}');

  final fullPayload = jsonEncode({'session': {'messages': msgs}});
  final win = tailWindow(msgs, 50);
  final winPayload = jsonEncode({'session': {'messages': win}});

  stdout.writeln('');
  stdout.writeln('【旧】全量 done 帧: ${(fullPayload.length / 1024 / 1024).toStringAsFixed(2)} MB');
  stdout.writeln('【新】裁窗 50 条:   ${(winPayload.length / 1024).toStringAsFixed(1)} KB');
  stdout.writeln('帧体积缩减: ${(fullPayload.length / winPayload.length).toStringAsFixed(1)}×');
  stdout.writeln('行数: ${msgs.length} → ${win.length}');

  // 致命回归检查：裁窗后**必须**还含最后一条 assistant 行（本轮最终回复）。
  final lastAssistantFull = _lastAssistant(msgs);
  final lastAssistantWin = _lastAssistant(win);
  stdout.writeln('');
  stdout.writeln('=== 关键回归检查 ===');
  if (lastAssistantFull == null) {
    stdout.writeln('（无 assistant 行，跳过）');
  } else {
    final kept = lastAssistantWin != null &&
        (lastAssistantWin['id'] == lastAssistantFull['id'] ||
            lastAssistantWin['message_id'] == lastAssistantFull['message_id']);
    stdout.writeln('全量最后 assistant id: ${lastAssistantFull['id'] ?? lastAssistantFull['message_id']}');
    stdout.writeln('裁窗后最后 assistant id: ${lastAssistantWin?['id'] ?? lastAssistantWin?['message_id']}');
    stdout.writeln(kept ? '  ✓ 本轮最终回复仍在窗口内' : '  ✗ 致命：最终回复被裁掉了！');
    if (!kept) exitCode = 1;
  }

  // 工具结果行保真检查：窗口内 assistant 的 tool_call 是否都有对应结果行
  final winToolIds = <String>{
    for (final m in win)
      if (m['tool_call_id'] is String) m['tool_call_id'] as String,
  };
  final winAssistantToolIds = <String>{
    for (final m in win)
      if (m['role'] == 'assistant' && m['tool_calls'] is List)
        for (final tc in (m['tool_calls'] as List))
          if (tc is Map && tc['id'] is String) tc['id'] as String,
  };
  final orphan = winAssistantToolIds.difference(winToolIds);
  stdout.writeln('');
  stdout.writeln('=== 工具卡保真 ===');
  stdout.writeln('窗口内 assistant 工具调用: ${winAssistantToolIds.length} 个');
  stdout.writeln('窗口内工具结果行: ${winToolIds.length} 个');
  stdout.writeln(
    orphan.isEmpty
        ? '  ✓ 全部有对应结果行（工具卡片段不会丢）'
        : '  ! ${orphan.length} 个工具调用在窗口内缺结果行（工具卡可能缺摘要）',
  );
}

Map<String, dynamic>? _lastAssistant(List<Map<String, dynamic>> msgs) {
  for (var i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i]['role'] == 'assistant') return msgs[i];
  }
  return null;
}

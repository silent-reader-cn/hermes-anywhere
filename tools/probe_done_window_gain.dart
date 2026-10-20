// 取证探针：裁窗前后 done 帧的**客户端总代价**对比。
// 用法：dart run tool/probe_done_window_gain.dart <会话json路径>
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

List<Map<String, dynamic>> tailWindow(List<Map<String, dynamic>> msgs, int size) {
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
  return msgs.sublist(start);
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/probe_done_window_gain.dart <会话json>');
    exit(2);
  }
  final raw = File(args.first).readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final msgs = ((findMsgs(decoded) as List?) ?? const [])
      .cast<Map<String, dynamic>>();

  stdout.writeln('会话: ${args.first.split(RegExp(r"[/\\\\]")).last}');
  stdout.writeln('全量消息: ${msgs.length} 条');
  stdout.writeln('');

  // ── 旧路径：全量 done 帧 ──
  final swFull = Stopwatch()..start();
  final fullPayload = jsonEncode({'session': {'messages': msgs}});
  final fullEncodeMs = swFull.elapsedMilliseconds;

  final swDec = Stopwatch()..start();
  jsonDecode(fullPayload);
  final fullDecodeMs = swDec.elapsedMilliseconds;

  stdout.writeln('【旧】全量 done 帧');
  stdout.writeln('  帧体积: ${fullPayload.length / 1024 / 1024} MB');
  stdout.writeln('  客户端 jsonDecode: $fullDecodeMs ms');
  stdout.writeln('  state.messages 行数: ${msgs.length}');

  // ── 新路径：裁窗到 50 条 ──
  final swWin = Stopwatch()..start();
  final win = tailWindow(msgs, 50);
  final winPayload = jsonEncode({'session': {'messages': win}});
  final winEncodeMs = swWin.elapsedMilliseconds;

  final swDec2 = Stopwatch()..start();
  jsonDecode(winPayload);
  final winDecodeMs = swDec2.elapsedMilliseconds;

  stdout.writeln('');
  stdout.writeln('【新】裁窗 50 条 done 帧');
  stdout.writeln('  帧体积: ${winPayload.length / 1024} KB');
  stdout.writeln('  客户端 jsonDecode: $winDecodeMs ms');
  stdout.writeln('  state.messages 行数: ${win.length}');
  stdout.writeln('');

  final sizeRatio = fullPayload.length / winPayload.length;
  final decodeRatio =
      fullDecodeMs == 0 ? double.infinity : winDecodeMs / fullDecodeMs;
  stdout.writeln('=== 收益 ===');
  stdout.writeln('帧体积缩减: ${sizeRatio.toStringAsFixed(1)}× '
      '(${fullPayload.length / 1024 / 1024} MB → ${winPayload.length / 1024} KB)');
  stdout.writeln('jsonDecode 缩减: ${decodeRatio.toStringAsFixed(2)}× '
      '($fullDecodeMs ms → $winDecodeMs ms)');
  stdout.writeln('行数缩减: ${(msgs.length / win.length).toStringAsFixed(1)}× '
      '(${msgs.length} → ${win.length})');
}

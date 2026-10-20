// 取证探针：量测 done 帧 jsonDecode + SessionDetail 解析的真实耗时。
// 用法：dart run tool/probe_done_decode_cost.dart <会话json路径>
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

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/probe_done_decode_cost.dart <会话json>');
    exit(2);
  }
  final file = File(args.first);
  final raw = file.readAsStringSync();
  stdout.writeln('文件: ${file.path}');
  stdout.writeln('原始大小: ${raw.length / 1024 / 1024} MB');

  // 模拟 done 帧：{"session": {...,"messages":[...]}}
  final sw = Stopwatch()..start();
  final decoded = jsonDecode(raw);
  sw.stop();
  stdout.writeln('jsonDecode 耗时: ${sw.elapsedMilliseconds} ms');

  final msgs = (findMsgs(decoded) as List?) ?? const [];
  stdout.writeln('messages 条数: ${msgs.length}');

  // 模拟 done 帧的 payload 组装 + 序列化
  final sw2 = Stopwatch()..start();
  final payload = jsonEncode({'session': {'messages': msgs}});
  sw2.stop();
  stdout.writeln(
    'done 帧序列化耗时: ${sw2.elapsedMilliseconds} ms, '
    '体积: ${payload.length / 1024 / 1024} MB',
  );

  // 模拟客户端：jsonDecode(payload) —— 这是主 isolate 上真正发生的事
  final sw3 = Stopwatch()..start();
  final decoded2 = jsonDecode(payload);
  sw3.stop();
  stdout.writeln('客户端 jsonDecode(done payload) 耗时: ${sw3.elapsedMilliseconds} ms');

  final sw4 = Stopwatch()..start();
  final msgs2 = (findMsgs(decoded2) as List?) ?? const [];
  sw4.stop();
  stdout.writeln('SessionDetail 解析遍历耗时: ${sw4.elapsedMilliseconds} ms');
  stdout.writeln('二次解析条数: ${msgs2.length}');
}

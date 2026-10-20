import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 「+」附件按钮的**多选**链路（2026-10-20）。
///
/// 覆盖：一次选中多个文件 → 逐个上传 → 全部进待发条 → 随消息一并提交；
/// 单个失败不影响其余文件；超出服务端每条消息 20 个附件上限时显式提示。
void main() {
  group('聊天附件多选上传 Widget 测试', () {
    testWidgets('多选 3 个文件：逐个 uploadFile，全部入待发条，发送时一并提交', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        results: [
          FilePickerResult(name: 'a.png', bytes: Uint8List.fromList([1, 1])),
          FilePickerResult(name: 'b.pdf', bytes: Uint8List.fromList([2, 2])),
          FilePickerResult(name: 'c.txt', bytes: Uint8List.fromList([3, 3])),
        ],
      );
      final adapter = _RecordingAdapter(
        responder: (options) {
          final name = _filenameOf(options);
          return ResponseBody.fromString(
            '{"ok":true,"filename":"$name","path":"/files/$name","is_image":false}',
            200,
          );
        },
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 三个文件各发一次 upload 请求，文件名都正确
      final uploadReqs = adapter.requests
          .where((r) => r.uri.path == '/api/upload')
          .toList();
      expect(uploadReqs.length, 3);
      final bodies = uploadReqs
          .map((r) => utf8.decode(r.data as Uint8List, allowMalformed: true))
          .toList();
      expect(
        bodies.any((b) => b.contains('filename="a.png"')),
        isTrue,
        reason: 'a.png 应被上传',
      );
      expect(
        bodies.any((b) => b.contains('filename="b.pdf"')),
        isTrue,
        reason: 'b.pdf 应被上传',
      );
      expect(
        bodies.any((b) => b.contains('filename="c.txt"')),
        isTrue,
        reason: 'c.txt 应被上传',
      );

      // 不直接发送
      expect(chatApi.startChatCalls, 0);

      // 三个都进了待发附件条
      expect(
        find.byKey(const ValueKey('attachment-pending-list')),
        findsOneWidget,
      );
      expect(find.text('a.png'), findsOneWidget);
      expect(find.text('b.pdf'), findsOneWidget);
      expect(find.text('c.txt'), findsOneWidget);

      // 点发送 → 三个附件随消息提交
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(chatApi.startChatCalls, 1);
      final sent = chatApi.lastSentAttachments;
      expect(sent, isNotNull);
      expect(sent!.length, 3);
      expect(
        sent.map((a) => a['name']).toSet(),
        {'a.png', 'b.pdf', 'c.txt'},
      );

      await _unmount(tester);
    });

    testWidgets('部分文件失败：成功项仍入待发条，失败项在错误弹窗里点名', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        results: [
          FilePickerResult(name: 'ok.png', bytes: Uint8List.fromList([1])),
          FilePickerResult(name: 'bad1.png', bytes: Uint8List.fromList([2])),
          FilePickerResult(name: 'bad2.png', bytes: Uint8List.fromList([3])),
        ],
      );
      final adapter = _RecordingAdapter(
        responder: (options) {
          final name = _filenameOf(options);
          if (name.startsWith('bad')) {
            return ResponseBody.fromString('{"error":"服务器内部错误"}', 500);
          }
          return ResponseBody.fromString(
            '{"ok":true,"filename":"$name","path":"/files/$name","is_image":false}',
            200,
          );
        },
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 成功项进了待发条
      expect(find.text('ok.png'), findsOneWidget);
      // 失败项没进待发条，但错误弹窗逐个点名了它们
      expect(find.text('bad1.png'), findsNothing);
      expect(find.text('bad2.png'), findsNothing);
      expect(find.text('上传失败'), findsOneWidget);
      expect(find.textContaining('bad1.png'), findsOneWidget);
      expect(find.textContaining('bad2.png'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('超出单条消息附件上限（20）：只上传前 20 个并显式提示', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        results: [
          for (var i = 0; i < 21; i++)
            FilePickerResult(
              name: 'f$i.txt',
              bytes: Uint8List.fromList([i]),
            ),
        ],
      );
      final adapter = _RecordingAdapter(
        responder: (options) {
          final name = _filenameOf(options);
          return ResponseBody.fromString(
            '{"ok":true,"filename":"$name","path":"/files/$name","is_image":false}',
            200,
          );
        },
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 只上传了 20 个（服务端上限），第 21 个被客户端拦下
      final uploadReqs = adapter.requests
          .where((r) => r.uri.path == '/api/upload')
          .toList();
      expect(uploadReqs.length, 20);

      // 超限提示可见（不是无声截断）
      expect(find.text('附件数量已达上限'), findsOneWidget);

      await _unmount(tester);
    });
  });
}

/// 从 multipart 请求体里取 `filename="xxx"`（测试用最省事的读法）。
String _filenameOf(RequestOptions options) {
  final body = utf8.decode(options.data as Uint8List, allowMalformed: true);
  final match = RegExp('filename="([^"]*)"').firstMatch(body);
  return match?.group(1) ?? '';
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeChatApi chatApi,
  required FilePickerService filePicker,
  required ApiClient apiClient,
}) async {
  SharedPreferences.setMockInitialValues({kShowPerfMonitorKey: false});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        filePickerServiceProvider.overrideWithValue(filePicker),
        apiClientProvider.overrideWithValue(apiClient),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

ApiClient _buildClient(_RecordingAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = adapter;
  final publicDio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  publicDio.httpClientAdapter = adapter;
  return ApiClient(
    baseUrl: 'http://test.local:30002',
    dio: dio,
    publicMediaDio: publicDio,
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

typedef _FakeChatApi = FakeChatApi;

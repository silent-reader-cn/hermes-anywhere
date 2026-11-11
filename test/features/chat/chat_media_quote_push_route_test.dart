import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/upload_response.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/chat_session_scope.dart';

import '../../helpers/fake_download_service.dart';

/// 1x1 透明 PNG。
final Uint8List kPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const ValueKey<String> kQuoteKey = ValueKey<String>('media-quote-button');
const ValueKey<String> kOpenLightboxKey = ValueKey<String>('open-lightbox');
const ValueKey<String> kOpenChatKey = ValueKey<String>('open-chat');

class _RecordingUploader {
  final List<String> calls = <String>[];
  int count = 0;

  Future<UploadResponse> call({
    required String sessionId,
    required Uint8List data,
    required String filename,
  }) async {
    count++;
    calls.add('$sessionId|$filename|${data.length}');
    return UploadResponse(
      filename: filename,
      path: '/attachments/$sessionId/$filename',
      size: data.length,
      mime: 'image/png',
      isImage: true,
    );
  }
}

/// 真实壳层结构：ShellRoute → 会话列表 `/` → `context.push('/chat/:id')`
/// （窄屏进聊天页的唯一方式）→ 聊天页里用**原生 Navigator.push** 打灯箱
/// （与 `showAttachmentPreview` 同款）。
///
/// [withScope] 模拟聊天页是否挂 `ChatSessionScope`：
/// - true = 修复后（聊天页声明身份）；
/// - false = 修复前（只能靠路由猜会话）。
Future<void> _pumpPushedChatStack(
  WidgetTester tester, {
  required _RecordingUploader uploader,
  required bool withScope,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => child,
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  key: kOpenChatKey,
                  onPressed: () => context.push('/chat/phone-session'),
                  child: const Text('list'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (context, state) {
              final sessionId = state.pathParameters['sessionId'] ?? '';
              final body = CupertinoPageScaffold(
                navigationBar: const CupertinoNavigationBar(
                  middle: Text('chat'),
                ),
                child: Center(
                  child: CupertinoButton(
                    key: kOpenLightboxKey,
                    onPressed: () => showAttachmentPreview(
                      context,
                      bytes: kPngBytes,
                      name: 'pic.png',
                      isImage: true,
                      // 刻意不传 sessionId：模拟实时文本块 / 待发附件条这些
                      // 只靠上层的入口。
                    ),
                    child: const Text('open'),
                  ),
                ),
              );
              return withScope
                  ? ChatSessionScope(sessionId: sessionId, child: body)
                  : body;
            },
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        chatMediaUploaderProvider.overrideWithValue(uploader.call),
        routerProvider.overrideWithValue(router),
        ...createDownloadTestOverrides(),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openLightboxAndQuote(WidgetTester tester) async {
  await tester.tap(find.byKey(kOpenChatKey));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(kOpenLightboxKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  expect(find.byKey(kQuoteKey), findsOneWidget, reason: '灯箱应已打开');

  await tester.tap(find.byKey(kQuoteKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('图片「引用」按钮 · 会话来源解析', () {
    testWidgets('聊天页作用域：push 进聊天页后引用落到该会话（手机真机场景）', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpPushedChatStack(
        tester,
        uploader: uploader,
        withScope: true,
      );

      await _openLightboxAndQuote(tester);

      expect(
        find.text('引用失败'),
        findsNothing,
        reason: '明明是从对话里打开的图，不该报「没有打开的聊天会话」',
      );
      expect(uploader.calls.single, startsWith('phone-session|'));
    });

    testWidgets('无作用域时路由回退也认 push 出来的 /chat/<id>', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpPushedChatStack(
        tester,
        uploader: uploader,
        withScope: false,
      );

      await _openLightboxAndQuote(tester);

      // push 不更新 delegate 的 currentConfiguration（停在基路由 `/`），
      // 只有 routeInformationProvider 里有 /chat/<id> ⇒ 回退必须两处都看。
      expect(find.text('引用失败'), findsNothing);
      expect(uploader.calls.single, startsWith('phone-session|'));
    });
  });
}

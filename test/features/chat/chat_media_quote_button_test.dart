import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/upload_response.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/pending_attachments_provider.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';

import '../../helpers/fake_download_service.dart';

/// 1x1 透明 PNG。
final Uint8List kPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const ValueKey<String> kDownloadKey = ValueKey<String>(
  'attachment-download-button',
);
const ValueKey<String> kQuoteKey = ValueKey<String>('media-quote-button');
const ValueKey<String> kRefreshKey = ValueKey<String>('media-refresh-button');

/// 记录上传调用的替身（不碰网络）。
class _RecordingUploader {
  final List<String> calls = <String>[];
  int count = 0;
  Object? error;

  Future<UploadResponse> call({
    required String sessionId,
    required Uint8List data,
    required String filename,
  }) async {
    count++;
    calls.add('$sessionId|$filename|${data.length}');
    final e = error;
    if (e != null) throw e;
    return UploadResponse(
      filename: filename,
      path: '/attachments/$sessionId/$filename',
      size: data.length,
      mime: 'image/png',
      isImage: true,
    );
  }
}

Future<void> _pumpLightbox(
  WidgetTester tester, {
  required _RecordingUploader uploader,
  Uint8List? bytes,
  String? resolvedUrl,
  String? sessionId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        chatMediaUploaderProvider.overrideWithValue(uploader.call),
        ...createDownloadTestOverrides(),
      ],
      child: CupertinoApp(
        home: AttachmentLightbox(
          bytes: bytes,
          resolvedUrl: resolvedUrl,
          name: 'pic.png',
          isImage: true,
          sessionId: sessionId,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// 起一个**带真实路由**的灯箱（用于验证「当前聊天」回退路径）。
Future<void> _pumpLightboxWithRouter(
  WidgetTester tester, {
  required _RecordingUploader uploader,
  Uint8List? bytes,
  required String chatLocation,
}) async {
  final router = GoRouter(
    initialLocation: chatLocation,
    routes: [
      GoRoute(
        path: '/chat/:sessionId',
        builder: (context, state) =>
            AttachmentLightbox(bytes: bytes, name: 'pic.png', isImage: true),
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
        // 「当前聊天」是**从路由**解析的（resolveCurrentChatSessionId 读全局
        // routerProvider）⇒ 测试必须把自建路由注入全局 provider，否则解析不到。
        routerProvider.overrideWithValue(router),
        ...createDownloadTestOverrides(),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('灯箱导航栏 · 下载按钮去字样化', () {
    testWidgets('下载按钮只剩图标：不再有「下载」文字，且图标与刷新按钮同款（20px）', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(tester, uploader: uploader, bytes: kPngBytes);

      expect(find.byKey(kDownloadKey), findsOneWidget);
      // 字样已去掉（状态文案改由 Tooltip 承载）。
      expect(find.text('下载'), findsNothing);
      // 图标与刷新按钮同为 20px。
      final downloadIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kDownloadKey),
          matching: find.byIcon(CupertinoIcons.cloud_download),
        ),
      );
      expect(downloadIcon.size, 20);
    });

    testWidgets('状态字样改由 Tooltip 承载（下载中/已下载等仍可读）', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(tester, uploader: uploader, bytes: kPngBytes);

      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byKey(kDownloadKey),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, '下载');
    });

    testWidgets('刷新按钮与下载按钮同为 20px 图标（视觉一致）', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(
        tester,
        uploader: uploader,
        resolvedUrl: 'http://test.local:30002/api/media?path=pic.png',
      );

      final refreshIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kRefreshKey),
          matching: find.byIcon(CupertinoIcons.arrow_clockwise),
        ),
      );
      final downloadIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kDownloadKey),
          matching: find.byIcon(CupertinoIcons.cloud_download),
        ),
      );
      expect(refreshIcon.size, downloadIcon.size);
    });
  });

  group('灯箱导航栏 · 引用按钮', () {
    testWidgets('文档预览（非图片）不显示「引用」按钮', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            ...createDownloadTestOverrides(),
          ],
          child: CupertinoApp(
            home: AttachmentLightbox(
              name: 'report.pdf',
              bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
              isImage: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // 文档没有「引用到聊天」语义 ⇒ 不渲染该按钮。
      expect(find.byKey(kQuoteKey), findsNothing);
    });

    testWidgets('引用按钮出现在刷新按钮左侧', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(
        tester,
        uploader: uploader,
        resolvedUrl: 'http://test.local:30002/api/media?path=pic.png',
      );

      expect(find.byKey(kQuoteKey), findsOneWidget);
      expect(find.byKey(kRefreshKey), findsOneWidget);
      final quoteX = tester.getCenter(find.byKey(kQuoteKey)).dx;
      final refreshX = tester.getCenter(find.byKey(kRefreshKey)).dx;
      expect(quoteX, lessThan(refreshX), reason: '引用按钮应在刷新按钮左侧');
    });

    testWidgets('点引用：上传被调用 → 附件进入待发附件条', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(
        tester,
        uploader: uploader,
        bytes: kPngBytes,
        sessionId: 's1',
      );

      await tester.tap(find.byKey(kQuoteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(uploader.count, 1, reason: '应上传一次');
      expect(uploader.calls.single, startsWith('s1|pic.png|'));

      // 附件进入待发附件条（随下一条消息发出）。
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(kQuoteKey)),
      );
      expect(container.read(pendingAttachmentsProvider('s1')).length, 1);
    });

    testWidgets('目标会话：灯箱自带 sessionId 优先', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(
        tester,
        uploader: uploader,
        bytes: kPngBytes,
        sessionId: 'from-lightbox',
      );

      await tester.tap(find.byKey(kQuoteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(uploader.calls.single, startsWith('from-lightbox|'));
    });

    testWidgets('无灯箱 id 时回退「当前聊天的路由」会话', (tester) async {
      final uploader = _RecordingUploader();
      // 灯箱不带 sessionId；当前路由是 /chat/current-chat ⇒ 回退到它。
      await _pumpLightboxWithRouter(
        tester,
        uploader: uploader,
        bytes: kPngBytes,
        chatLocation: '/chat/current-chat',
      );

      await tester.tap(find.byKey(kQuoteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(uploader.count, 1);
      expect(uploader.calls.single, startsWith('current-chat|'));
    });

    testWidgets('无任何会话（灯箱无 id 且无当前聊天）：提示而不静默', (tester) async {
      final uploader = _RecordingUploader();
      await _pumpLightbox(tester, uploader: uploader, bytes: kPngBytes);

      await tester.tap(find.byKey(kQuoteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(uploader.count, 0, reason: '无处可引 ⇒ 不应上传');
      expect(find.text('引用失败'), findsOneWidget);
    });

    testWidgets('上传失败：有明确提示，灯箱不关闭', (tester) async {
      final uploader = _RecordingUploader()..error = StateError('boom');
      await _pumpLightbox(
        tester,
        uploader: uploader,
        bytes: kPngBytes,
        sessionId: 's1',
      );

      await tester.tap(find.byKey(kQuoteKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('引用失败'), findsOneWidget);
      expect(find.byKey(kQuoteKey), findsOneWidget, reason: '失败时灯箱不应关闭');
    });
  });
}

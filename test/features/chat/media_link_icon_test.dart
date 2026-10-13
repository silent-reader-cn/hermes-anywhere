import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_parser.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';
import 'package:hermes_ui/features/chat/widgets/media_kind_icons.dart';

/// 媒体链接的类型图标（emoji 字符 → 矢量图标）。
///
/// 锁死三件事：
/// 1. `MEDIA:` / 裸 `file://` 链接前置**图标**，链接文案恒等于纯文件名；
/// 2. 普通网页链接不带 `hermes-media` 标记 → 不加图标、点击行为不变；
/// 3. vendored `flutter_markdown` 的配套补丁（PATCH_NOTES 第 5 节）：`a` 构建器
///    返回 widget 时仍要正确弹掉链接识别器栈 —— 链接自身可点，链接**之后的**
///    普通文字不会被误挂上链接识别器。
Future<void> _pumpMarkdown(
  WidgetTester tester,
  String data, {
  void Function(String? text, String? href, String? title)? onTapLink,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: Builder(
              builder: (context) => MarkdownBody(
                data: data,
                selectable: false,
                builders: createAssistantMarkdownBuilders(context),
                onTapLink: onTapLink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 取最内层"文本包含 needle"的 span（用于断言识别器挂在哪个 span 上）。
/// `recognizer` 定义在 [TextSpan] 上（不是 [InlineSpan]），故返回 TextSpan。
TextSpan? _innermostSpanContaining(InlineSpan span, String needle) {
  if (span is! TextSpan) return null;
  final children = span.children;
  if (children != null) {
    for (final child in children) {
      final hit = _innermostSpanContaining(child, needle);
      if (hit != null) return hit;
    }
  }
  final text = span.text;
  if (text != null && text.contains(needle)) return span;
  return null;
}

void main() {
  group('媒体链接类型图标', () {
    testWidgets('音频 / 视频 / 文档各自渲染类型图标，链接文案为纯文件名', (tester) async {
      final data = ChatMediaParser.parseMediaMarkers(
        '录音：MEDIA:/tmp/voice.mp3\n\n视频：MEDIA:/tmp/clip.mp4\n\n文档：MEDIA:/tmp/spec.pdf',
      );
      await _pumpMarkdown(tester, data);

      expect(find.byKey(kMediaLinkIconKey), findsNWidgets(3));
      expect(find.byIcon(CupertinoIcons.music_note), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.film), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.doc_text), findsOneWidget);
      expect(find.textContaining('🎵'), findsNothing);
      expect(find.textContaining('🎬'), findsNothing);
      expect(find.textContaining('📎'), findsNothing);
      expect(find.textContaining('voice.mp3'), findsOneWidget);
      expect(find.textContaining('spec.pdf'), findsOneWidget);
    });

    testWidgets('普通网页链接不加类型图标', (tester) async {
      await _pumpMarkdown(tester, '参考 [官方文档](https://example.com/docs) 说明');

      expect(find.byKey(kMediaLinkIconKey), findsNothing);
      expect(find.textContaining('官方文档'), findsOneWidget);
    });

    testWidgets('媒体链接自身仍可点击，且 linkText 是纯文件名', (tester) async {
      final taps = <String?>[];
      await _pumpMarkdown(
        tester,
        ChatMediaParser.parseMediaMarkers('MEDIA:/tmp/spec.pdf'),
        onTapLink: (text, href, title) => taps.add(text),
      );

      await tester.tap(find.textContaining('spec.pdf'));
      await tester.pump();

      expect(taps, <String>['spec.pdf']);
    });

    testWidgets('链接之后的普通文字不带链接识别器（vendored 补丁回归）', (tester) async {
      final link = ChatMediaParser.parseMediaMarkers('MEDIA:/tmp/spec.pdf');
      await _pumpMarkdown(tester, '看 $link 后面这段是普通文字');

      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((w) => w.text.toPlainText().contains('普通文字'));
      final linkSpan = _innermostSpanContaining(rich.text, 'spec.pdf');
      final plainSpan = _innermostSpanContaining(rich.text, '普通文字');

      expect(linkSpan, isNotNull);
      expect(plainSpan, isNotNull);
      expect(linkSpan!.recognizer, isNotNull, reason: '媒体链接必须仍然可点');
      expect(plainSpan!.recognizer, isNull, reason: '链接后的普通文字不该可点');
    });
  });
}

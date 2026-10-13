import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_parser.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';

/// 中文名附件 404 的根因回归（2026-10-13 实测）。
///
/// `package:markdown` 会把链接目标里的非 ASCII 规范成百分号转义，于是
/// `onTapLink` 拿到的 href 已经是 `D:/…/docs/%E6%A0%91%E6%87%92…xlsx`；
/// `ChatMediaResolver.resolveMediaUrl` 若直接 `Uri.encodeComponent` 会把 `%E6`
/// 编成 `%25E6`（二次编码），服务端解一次码后去找字面量 `%E6%A0%91…` 的文件
/// ⇒ 404 not found。纯 ASCII 名的文件不受影响 —— 所以现象是「只有那几份中文名打不开」。
///
/// 两个层面都钉住：① 解析函数对「已编码的链接目标」幂等；
/// ② 走真实 markdown 渲染 + onTapLink 的整链，解析出来的 URL 只编一次。
const String _cnName = '树懒社交-招聘JD-BOSS直聘版-v2.2-20261013.xlsx';
const String _cnPath = 'D:/projects/sloth/docs/$_cnName';
const String _encodedHref =
    'D:/projects/sloth/docs/%E6%A0%91%E6%87%92%E7%A4%BE%E4%BA%A4-%E6%8B%9B%E8%81%98JD-BOSS%E7%9B%B4%E8%81%98%E7%89%88-v2.2-20261013.xlsx';

void main() {
  group('媒体 URL 解析：链接目标已百分号编码时不得二次编码', () {
    test('已编码的中文路径 → 只编一次（%E6 不得变 %25E6）', () {
      final resolved = ChatMediaResolver.resolveMediaUrl(
        _encodedHref,
        baseUrl: 'http://h:50001',
      );
      expect(resolved, contains('%E6%A0%91'));
      expect(resolved, isNot(contains('%25E6')));
      expect(resolved, isNot(contains('%25')));
    });

    test('原始中文路径与已编码链接目标解析结果一致（幂等）', () {
      final fromRaw = ChatMediaResolver.resolveMediaUrl(
        _cnPath,
        baseUrl: 'http://h:50001',
      );
      final fromEncoded = ChatMediaResolver.resolveMediaUrl(
        _encodedHref,
        baseUrl: 'http://h:50001',
      );
      expect(fromEncoded, fromRaw);
      expect(
        fromRaw,
        'http://h:50001/api/media?path='
        'D%3A%2Fprojects%2Fsloth%2Fdocs%2F'
        '%E6%A0%91%E6%87%92%E7%A4%BE%E4%BA%A4-%E6%8B%9B%E8%81%98JD-BOSS'
        '%E7%9B%B4%E8%81%98%E7%89%88-v2.2-20261013.xlsx',
      );
    });

    test('带 session_id 时同样只编一次', () {
      final resolved = ChatMediaResolver.resolveMediaUrl(
        _encodedHref,
        baseUrl: 'http://h:50001/',
        sessionId: 'e3a667903588',
      );
      expect(resolved, contains('session_id=e3a667903588'));
      expect(resolved, isNot(contains('%25E6')));
    });

    test('裸文件名走 /api/file/raw 时同样不得二次编码', () {
      final resolved = ChatMediaResolver.resolveMediaUrl(
        '%E6%A0%91%E6%87%92x.xlsx',
        baseUrl: 'http://h:50001',
        sessionId: 's1',
      );
      expect(resolved, contains('/api/file/raw'));
      expect(resolved, contains('path=%E6%A0%91%E6%87%92x.xlsx'));
      expect(resolved, isNot(contains('%25')));
    });

    test('非法百分号转义（文件名里真有 %）原样保留且不抛异常', () {
      expect(
        ChatMediaResolver.resolveMediaUrl('100%report.pdf'),
        '100%report.pdf',
      );
      expect(
        ChatMediaResolver.resolveMediaUrl(
          'D:/tmp/100%.pdf',
          baseUrl: 'http://h:50001',
        ),
        'http://h:50001/api/media?path=D%3A%2Ftmp%2F100%25.pdf',
      );
    });

    test('file:///d/…（MSYS 盘符形态）规整成 D:/…，不得落成反斜杠盘符形态', () {
      final resolved = ChatMediaResolver.resolveMediaUrl(
        'file:///d/projects/sloth/docs/$_cnName',
        baseUrl: 'http://h:50001',
        sessionId: 's1',
      );
      expect(resolved, contains('/api/media?path=D%3A%2Fprojects%2Fsloth%2Fdocs%2F'));
      expect(resolved, isNot(contains('%5Cd')));
      expect(resolved, isNot(contains('%5Cprojects')));
    });

    test('裸 MSYS 路径 /d/projects/… 同样规整成 D:/…', () {
      expect(
        ChatMediaResolver.resolveMediaUrl(
          '/d/projects/sloth/docs/a.xlsx',
          baseUrl: 'http://h:50001',
        ),
        'http://h:50001/api/media?path=D%3A%2Fprojects%2Fsloth%2Fdocs%2Fa.xlsx',
      );
    });

    test('工作区相对路径（含分隔符）改走 /api/file/raw（/api/media 只认绝对路径）', () {
      expect(
        ChatMediaResolver.resolveMediaUrl(
          'docs/a.xlsx',
          baseUrl: 'http://h:50001',
          sessionId: 's1',
        ),
        'http://h:50001/api/file/raw?session_id=s1&path=docs%2Fa.xlsx',
      );
    });

    test('相对路径但无 session_id：退回 /api/media（不静默吞掉）', () {
      expect(
        ChatMediaResolver.resolveMediaUrl(
          'docs/a.xlsx',
          baseUrl: 'http://h:50001',
        ),
        'http://h:50001/api/media?path=docs%2Fa.xlsx',
      );
    });

    test('绝对路径仍走 /api/media（未被相对路径分支抢走）', () {
      expect(
        ChatMediaResolver.resolveMediaUrl(
          'D:/projects/sloth/docs/a.xlsx',
          baseUrl: 'http://h:50001',
          sessionId: 's1',
        ),
        'http://h:50001/api/media?path=D%3A%2Fprojects%2Fsloth%2Fdocs%2Fa.xlsx'
            '&session_id=s1',
      );
    });
    test('http / data URI 原样透传（不动别人的 query）', () {
      const url = 'https://cdn.example.com/a%20b/c.png?x=%E4%B8%AD';
      expect(
        ChatMediaResolver.resolveMediaUrl(url, baseUrl: 'http://h:50001'),
        url,
      );
      const data = 'data:image/png;base64,iVBORw0KGgo=';
      expect(
        ChatMediaResolver.resolveMediaUrl(data, baseUrl: 'http://h:50001'),
        data,
      );
    });
  });

  group('整链回归：markdown 渲染 → onTapLink href → 解析', () {
    testWidgets('中文名 MEDIA 链接解析出的 URL 只编一次', (tester) async {
      final data = ChatMediaParser.parseMediaMarkers(
        'MEDIA:D:\\projects\\sloth\\docs\\$_cnName',
      );
      final tapped = <String?>[];

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
                    onTapLink: (text, href, title) => tapped.add(href),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('xlsx'));
      await tester.pump();

      expect(tapped, hasLength(1));
      // markdown 层交给我们的 href 本身就是编码过的（先证明这一点，防止上游变行为）
      expect(tapped.single, contains('%E6%A0%91'));

      final resolved = ChatMediaResolver.resolveMediaUrl(
        tapped.single!,
        baseUrl: 'http://221.176.152.14:50001',
        sessionId: 'e3a667903588',
      );
      expect(resolved, contains('%E6%A0%91%E6%87%92'));
      expect(resolved, isNot(contains('%25E6')));

      // 与「服务端真值」对照：这条就是当天实测 404 的那条 URL 的正确形态
      expect(
        resolved,
        'http://221.176.152.14:50001/api/media?path='
        'D%3A%2Fprojects%2Fsloth%2Fdocs%2F'
        '%E6%A0%91%E6%87%92%E7%A4%BE%E4%BA%A4-%E6%8B%9B%E8%81%98JD-BOSS'
        '%E7%9B%B4%E8%81%98%E7%89%88-v2.2-20261013.xlsx'
        '&session_id=e3a667903588',
      );
    });
  });
}

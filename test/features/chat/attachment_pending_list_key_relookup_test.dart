import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/upload_response.dart';
import 'package:hermes_ui/features/chat/pending_attachments_provider.dart';
import 'package:hermes_ui/features/chat/widgets/attachment_pending_bar.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// 待发附件横条（横向 ListView.separated）：行 key 与反查守卫。
//
// 危险形状：直接子节点 `_AttachmentThumb` 无 key，且未传 `findItemIndexCallback`
// ⇒ 删除前面一项后，后面的缩略图换下标就被销毁重建（`Image.memory` 重新解码、
// 缩略图闪白）。
//
// 判据：删除首项后，后两项的缩略图 element 是否 identical（另带「内容不变」
// 对照组 + 位置确实左移的证据）。取 element 用 `attachment-preview-<id>`
// 这个更深层的稳定 key —— 该取法在补 key 前后都成立。
// ---------------------------------------------------------------------------

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

PendingAttachment _att(String id) => PendingAttachment(
  id: id,
  name: '$id.pdf',
  path: '/files/$id.pdf',
  mime: 'application/pdf',
);

Element _thumb(WidgetTester tester, String id) =>
    tester.element(find.byKey(ValueKey('attachment-preview-$id')));

void main() {
  testWidgets('删除首项后，后两项缩略图 element 应复用而非重建', (tester) async {
    const sessionId = 's1';
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pendingAttachmentsProvider(sessionId).notifier);
    notifier.add(_att('a1'));
    notifier.add(_att('a2'));
    notifier.add(_att('a3'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          localizationsDelegates: _delegates,
          home: AttachmentPendingBar(sessionId: sessionId),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('attachment-pending-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('attachment-preview-a3')), findsOneWidget);

    // 对照组（内容不变）：不动列表，再 pump 一帧 ⇒ 三项 element 均复用。
    final controls = [
      for (final id in ['a1', 'a2', 'a3']) _thumb(tester, id),
    ];
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(
        identical(_thumb(tester, ['a1', 'a2', 'a3'][i]), controls[i]),
        isTrue,
        reason: '内容不变的对照组：无改动时缩略图 element 不该被重建',
      );
    }

    final capturedA2 = _thumb(tester, 'a2');
    final capturedA3 = _thumb(tester, 'a3');
    final xBefore = tester
        .getTopLeft(find.byKey(const ValueKey('attachment-preview-a2')))
        .dx;

    notifier.remove('a1');
    await tester.pump();

    expect(find.byKey(const ValueKey('attachment-preview-a1')), findsNothing);
    final xAfter = tester
        .getTopLeft(find.byKey(const ValueKey('attachment-preview-a2')))
        .dx;
    expect(xAfter, lessThan(xBefore), reason: 'a2 必须左移（否则判据空转）');

    expect(
      identical(_thumb(tester, 'a2'), capturedA2),
      isTrue,
      reason: '下标 1 → 0：直接子节点带稳定 key + findItemIndexCallback 才能复用',
    );
    expect(
      identical(_thumb(tester, 'a3'), capturedA3),
      isTrue,
      reason: '下标 2 → 1：同上（否则 Image.memory 重新解码、缩略图闪白）',
    );
  });
}

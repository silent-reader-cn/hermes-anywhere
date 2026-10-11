import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/kanban.dart';
import 'package:hermes_ui/features/kanban/kanban_page.dart';
import 'package:hermes_ui/features/kanban/kanban_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_kanban_api.dart';

// ---------------------------------------------------------------------------
// 看板列卡片：行 key 与「key → 条目下标」反查守卫（ListView.separated）。
//
// 危险形状：直接子节点 = 无 key 的 `LongPressDraggable`，稳定 key 挂在更深的
// `_KanbanCardTile` 上 ⇒ 框架拿不到直接子节点的 key，`findItemIndexByKey` 无从
// 触发，卡片换下标就被销毁重建（拖拽/状态变更动画、手势态一起丢）。
//
// 判据：同一张卡在「列内位置变化前 / 后」比 `tester.element(...)` 是否
// identical，外加「内容不变」对照组与「位置确实上移」证据。
// ---------------------------------------------------------------------------

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

KanbanCard _card(String id, String status) =>
    KanbanCard(cardID: id, title: '卡片 $id', status: KanbanStatus(status));

/// 直接子节点（LongPressDraggable）element：该取法在补 key 前后都成立，
/// RED/GREEN 用同一判据（补 key 后仍命中同一个 Draggable）。
Element _dragRow(WidgetTester tester, String cardId) => tester.element(
  find
      .ancestor(
        of: find.byKey(ValueKey('kanban-card-$cardId')),
        matching: find.byType(LongPressDraggable<KanbanCard>),
      )
      .first,
);

Future<ProviderContainer> _pump(WidgetTester tester, FakeKanbanApi api) async {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      kanbanApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        localizationsDelegates: _delegates,
        home: KanbanPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  testWidgets('同列首卡被拖走后（状态变更），后两张卡的 element 应复用而非重建', (
    tester,
  ) async {
    final api = FakeKanbanApi(
      boards: [const KanbanBoard(slug: 'default', name: '主看板')],
      currentSlug: 'default',
      snapshots: {
        'default': KanbanBoardSnapshot(
          columns: [
            KanbanColumn(
              name: 'todo',
              cards: [_card('c1', 'todo'), _card('c2', 'todo'), _card('c3', 'todo')],
            ),
            KanbanColumn(name: 'done', cards: [_card('c4', 'done')]),
          ],
        ),
      },
    );
    addTearDown(api.dispose);
    final container = await _pump(tester, api);

    expect(find.byKey(const ValueKey('kanban-card-c2')), findsOneWidget);

    // 对照组（内容不变）：不动状态，再 pump 一帧 ⇒ 三张卡 element 均复用。
    final controls = [
      for (final id in ['c1', 'c2', 'c3']) _dragRow(tester, id),
    ];
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      expect(
        identical(_dragRow(tester, ['c1', 'c2', 'c3'][i]), controls[i]),
        isTrue,
        reason: '内容不变的对照组：无改动时直接子节点不该被重建',
      );
    }

    final capturedC2 = _dragRow(tester, 'c2');
    final capturedC3 = _dragRow(tester, 'c3');
    final yBefore = tester
        .getTopLeft(find.byKey(const ValueKey('kanban-card-c2')))
        .dy;

    // 与跨列拖拽同一条状态路径：DragTarget.onAcceptWithDetails →
    // _moveCardLocally → controller.setStatus → _moveCard（首卡移出本列）。
    await container
        .read(kanbanControllerProvider.notifier)
        .setStatus(cardId: 'c1', status: 'done');
    await tester.pump();

    expect(api.setStatusCount, 1);
    expect(api.lastSetStatusCall, 'c1:done');
    // 重排确实发生：todo 列变 [c2, c3]，c2 上移一格。
    final yAfter = tester
        .getTopLeft(find.byKey(const ValueKey('kanban-card-c2')))
        .dy;
    expect(yAfter, lessThan(yBefore), reason: 'c2 必须上移（否则判据空转）');

    expect(
      identical(_dragRow(tester, 'c2'), capturedC2),
      isTrue,
      reason: '下标 1 → 0：直接子节点带稳定 key + 反查才能复用 element',
    );
    expect(
      identical(_dragRow(tester, 'c3'), capturedC3),
      isTrue,
      reason: '下标 2 → 1：同上',
    );
  });
}

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

/// #184 多选态批量栏的两处真机缺陷守卫（主人 2026-10-12 截图报告）。
///
/// ① 多选时右下角 FAB 与批量栏同屏 ⇒ 加号压在栏上（遮挡「全选」）；
///    现**多选态不渲染 FAB**。
/// ② 批量栏曾是 `Stack` 浮层（`Positioned(bottom: 0)`）⇒ 列表视口仍是整屏高，
///    长列表滚到底时末尾若干行停在栏**下面**、点不着；
///    现改为真正的底部 footer（`Column[Expanded(列表), 批量栏]`）⇒ 视口随栏收缩。
///
/// 判据取法（不能只看「栏渲染出来了」——缺陷版本下同样成立）：
/// - 几何：`batch-bar` 顶边 == 列表视口底边（footer 语义），且末尾行底边 ≤ 栏顶边；
/// - 命中：滚到底后**点末尾行**必须真的勾选它（缺陷版本下这一击打在栏上）。
/// 用例先自检列表真的溢出（`maxScrollExtent > 0`），防几何判据空转。
double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _session(String id, String title) => SessionSummary(
  sessionId: id,
  title: title,
  lastMessageAt: _sec(DateTime.now()),
);

/// 空项目 API stub：避免真实 [ApiClient] 发出 dio 请求残留超时 Timer。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

Future<void> _pumpList(
  WidgetTester tester,
  FakeSessionListApi api, {
  required Size size,
  bool sidebarReuse = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => sidebarReuse
            ? const SessionListPage(showUtilityRows: false, showFab: false)
            : const SessionListPage(),
      ),
      GoRoute(
        path: '/chat/:sessionId',
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        sessionListApiFactoryProvider.overrideWithValue((_) => api),
        projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

SessionListState _stateOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(SessionListPage)),
).read(sessionListControllerProvider).requireValue;

SessionListController _controllerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(SessionListPage)),
    ).read(sessionListControllerProvider.notifier);

/// 把会话列表滚到最底（`jumpTo(maxScrollExtent)`）——先断言真的溢出，
/// 否则「末尾行在栏上方」这类几何判据在列表根本没滚动空间时会**空转通过**。
void _jumpToBottom(WidgetTester tester) {
  final view = tester.widget<CustomScrollView>(
    find.byKey(const ValueKey('session-list-scroll')),
  );
  final position = view.controller!.position;
  expect(
    position.maxScrollExtent,
    greaterThan(0),
    reason: '用例前提：会话列表必须真的溢出（否则判据空转）',
  );
  position.jumpTo(position.maxScrollExtent);
}

/// 多选态批量栏的 footer 不变式：栏顶边 == 列表视口底边，且末尾行完整在栏上方；
/// 末尾再对这一行发一次真实点击（由调用方 await 后断言是否勾上）。
Future<void> _expectFooterInvariants(
  WidgetTester tester,
  String lastSessionId,
) async {
  final barRect = tester.getRect(find.byKey(const ValueKey('batch-bar')));
  final listRect = tester.getRect(
    find.byKey(const ValueKey('session-list-scroll')),
  );
  expect(
    barRect.top,
    closeTo(listRect.bottom, 0.51),
    reason: '批量栏必须是列表视口的 footer（栏顶 == 视口底），不能是盖在上面的浮层',
  );

  final lastRow = find.byKey(ValueKey('session-row-$lastSessionId'));
  expect(lastRow, findsOneWidget);
  final rowRect = tester.getRect(lastRow);
  expect(
    rowRect.bottom,
    lessThanOrEqualTo(barRect.top + 0.51),
    reason: '滚到底后末尾行必须完整落在批量栏上方（缺陷版本会被压住）',
  );

  // 命中判据：这一击必须真的勾选末尾行（缺陷版本下它打在批量栏上）。
  await tester.tap(lastRow);
}

void main() {
  group('#184 多选态批量栏：FAB 遮挡 + 末尾行被压住', () {
    testWidgets('多选态不渲染 FAB，退出多选后恢复（窄屏）', (tester) async {
      final api = FakeSessionListApi(
        sessions: [_session('s1', '会话一'), _session('s2', '会话二')],
      );
      await _pumpList(tester, api, size: const Size(400, 800));

      // 空闲态：FAB 在（长按扇出菜单的入口）。
      expect(find.byKey(const ValueKey('session-list-new')), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();

      expect(find.byKey(const ValueKey('batch-bar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-list-new')),
        findsNothing,
        reason: '多选态批量栏占据底部操作区，悬浮加号会压在它上面',
      );

      // 退出多选 → FAB 回来。
      _controllerOf(tester).clearSelection();
      await tester.pump();
      expect(find.byKey(const ValueKey('batch-bar')), findsNothing);
      expect(find.byKey(const ValueKey('session-list-new')), findsOneWidget);
    });

    testWidgets('长列表滚到底：末尾行完整在批量栏上方且可点（窄屏）', (tester) async {
      final api = FakeSessionListApi(
        sessions: [for (var i = 1; i <= 30; i++) _session('s$i', '会话 $i')],
      );
      await _pumpList(tester, api, size: const Size(400, 800));

      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('batch-bar')), findsOneWidget);

      _jumpToBottom(tester);
      await tester.pump();

      await _expectFooterInvariants(tester, 's30');
      await tester.pump();
      expect(
        _stateOf(tester).selectedSessionIds,
        contains('s30'),
        reason: '末尾行的点击必须命中该行（缺陷版本打在批量栏上，勾不上）',
      );
    });

    testWidgets('宽屏侧栏复用（两行式批量栏）同判据', (tester) async {
      final api = FakeSessionListApi(
        sessions: [for (var i = 1; i <= 30; i++) _session('s$i', '会话 $i')],
      );
      await _pumpList(
        tester,
        api,
        size: const Size(1280, 900),
        sidebarReuse: true,
      );

      // 宽屏侧栏的紧凑行把长按/右键让给了行操作菜单（#150），故这里直接由
      // controller 进多选态 —— 本用例只钉批量栏的 footer 几何（宽屏档的批量栏
      // 是两行式、高度与窄屏不同），不重复测入口。
      _controllerOf(tester).toggleSelection('s1');
      await tester.pump();
      expect(find.byKey(const ValueKey('batch-bar')), findsOneWidget);

      _jumpToBottom(tester);
      await tester.pump();

      await _expectFooterInvariants(tester, 's30');
      await tester.pump();
      expect(_stateOf(tester).selectedSessionIds, contains('s30'));
    });
  });
}

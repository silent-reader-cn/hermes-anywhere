// 守卫：宽屏侧栏（compact → `SliverList.builder`）在「刷新导致组内重排」之后，
// 必须**复用**已在屏上的会话行元素（State 保持 identical）。
//
// 为什么需要这条守卫：行自带稳定 key（`session-row-<id>`），但 sliver 只有在拿到
// 「key → 新下标」反查回调时才能**移动**已有元素；缺回调时组内插入/重排会让每个
// 下标上的 key 都变化，框架只能逐个销毁重建整段行 —— 用户看到的就是
// 「刷新闪一下 / 像把列表删了重新加一遍」。
//
// 判据取法（探针实测，2026-10-11，1200×1600 视口 + 30 条会话；把一条新会话插到
// 同一工作区分区最前 ⇒ 其后所有行下标 +1）：
//   · 缺 findChildIndexCallback（修复前）→ 3/3 行的 State 被重建，且刷新后第一帧
//     RenderSliverList 只剩 6 个子节点、maxScrollExtent 由 9637 归零；
//   · 窄屏 separated 分支（早有 findItemIndexCallback）→ 0/3；
//   · 宽屏补上 findChildIndexCallback 后 → 0/3（本用例即该结论的常驻版本）。
//
// 注意：`SliverList.builder` 的索引**不含分隔符**，findChildIndexCallback 必须
// 直接返回 item 下标（separated 才需要 ×2）。

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

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

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

/// 同一工作区下的第 [i] 条会话（i 越大越旧 ⇒ 列表顺序即声明顺序）。
SessionSummary _session(String id, int minutesAgo, {String? workspace}) {
  return SessionSummary(
    sessionId: id,
    title: 'T$id',
    workspace: workspace,
    lastMessageAt: _sec(DateTime.now().subtract(Duration(minutes: minutesAgo))),
  );
}

void main() {
  const workspace = r'D:\proj\same';

  Future<void> pumpWideSidebar(
    WidgetTester tester,
    FakeSessionListApi api,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const SessionListPage(
            // 宽屏侧栏复用形态（adaptive_shell 传参）。
            showUtilityRows: false,
            showSettingsTrailing: false,
            showFab: false,
          ),
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
        child: CupertinoApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('宽屏侧栏刷新导致组内重排：已有会话行元素必须被复用（不被整段重建）', (
    tester,
  ) async {
    final sessions = [
      for (var i = 0; i < 30; i++) _session('s$i', i, workspace: workspace),
    ];
    final api = FakeSessionListApi(sessions: sessions);
    await pumpWideSidebar(tester, api);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionListPage)),
    );

    // 探针行取「插入位点之下」的三条：重排会让它们的下标整体 +1。
    const probeIds = ['s10', 's18', 's25'];
    final stateBefore = <String, State>{};
    for (final id in probeIds) {
      final finder = find.byKey(ValueKey('session-row-$id'));
      expect(finder, findsOneWidget, reason: '$id 应已在屏上（否则判据无效）');
      stateBefore[id] = tester.state(finder);
    }

    // 刷新：服务端多出一条最新会话（插到同一分区最前）⇒ 结构变化。
    api.sessions = [
      _session('snew', -1, workspace: workspace),
      ...sessions,
    ];
    await container.read(sessionListControllerProvider.notifier).refresh();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      find.byKey(const ValueKey('session-row-snew')),
      findsOneWidget,
      reason: '刷新结果应已落地（新会话在列表里），否则本条断言无意义',
    );
    var recreated = 0;
    for (final id in probeIds) {
      final finder = find.byKey(ValueKey('session-row-$id'));
      expect(finder, findsOneWidget, reason: '$id 刷新后仍应在列表里');
      if (!identical(stateBefore[id], tester.state(finder))) recreated++;
    }
    expect(
      recreated,
      0,
      reason:
          '重排后行元素被重建 $recreated/${probeIds.length} 条 —— '
          'SliverList.builder 缺 findChildIndexCallback 会让整段行销毁重建'
          '（重排时应把 key 反查到新下标并移动元素）',
    );
  });

  testWidgets('宽屏侧栏刷新：不得把已展开的分页窗口打回 pageSize（列表当帧不塌陷）', (
    tester,
  ) async {
    // 这条守的是「列表被清空」的第二种成因：refresh() → _loadFirstPage 会把
    // visibleCount 无条件写成 min(pageSize, n)；深滚用户刷新后屏上那批行被整批撤掉，
    // 当帧 maxScrollExtent 归零（实测 9637 → 0、树里只剩 6 行），随后靠
    // _maybeLoadMore 逐页补回 ⇒ 观感就是「列表塌了再长回来」。
    final sessions = [
      for (var i = 0; i < 120; i++) _session('s$i', i, workspace: workspace),
    ];
    final api = FakeSessionListApi(sessions: sessions);
    await pumpWideSidebar(tester, api);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionListPage)),
    );
    final controller = container.read(sessionListControllerProvider.notifier);
    final scroll = tester
        .widget<CustomScrollView>(
          find.byKey(const ValueKey('session-list-scroll')),
        )
        .controller!;

    int rowsBuilt() => find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('session-row-'),
        )
        .evaluate()
        .length;

    SessionListState state() =>
        container.read(sessionListControllerProvider).valueOrNull!;

    await controller.loadMore();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final windowBefore = state().visibleCount;
    expect(
      windowBefore,
      greaterThan(SessionListState.pageSize),
      reason: '前置：窗口应已展开到一页以上，否则本条判据无效',
    );

    scroll.jumpTo(scroll.position.maxScrollExtent);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      scroll.position.maxScrollExtent,
      greaterThan(0),
      reason: '前置：列表应可滚（有内容）',
    );
    expect(rowsBuilt(), greaterThan(20), reason: '前置：树里应已建出足量行');

    // 同一份数据、同一顺序的刷新 —— 只考察「窗口是否被重置」这一个变量。
    await controller.refresh();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      state().visibleCount,
      windowBefore,
      reason: '刷新是重载数据，不该把用户已展开的分页窗口打回 pageSize',
    );
    expect(
      scroll.position.maxScrollExtent,
      greaterThan(0),
      reason: '刷新后当帧列表不该塌成不可滚（= 观感上的「被清空」）',
    );
    expect(
      rowsBuilt(),
      greaterThan(20),
      reason: '刷新后当帧树里仍应保有足量行（修复前实测只剩 6 行）',
    );
  });
}

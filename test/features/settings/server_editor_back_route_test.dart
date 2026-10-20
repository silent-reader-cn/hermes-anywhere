import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/shared/app_back_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #211 回归：「新增 / 编辑服务器」页必须与设置页**同栈**（go_router）。
///
/// 主人实机报告：新增服务器后按返回，设置页被一起关掉、退到主页 ⇒
/// 没法接着点「激活」。真凶 = 编辑页用原生 `Navigator.push` 推入，与
/// go_router 栈**分裂** ⇒ `AppBackButton` 的 `canPop()` 判据失真。
///
/// 判据（不看像素，看落点）：
///   · 编辑页的返回 ⇒ 落回 `/settings`（设置页仍在），**不是** `/`；
///   · 编辑页的保存成功 ⇒ 同样落回 `/settings`。

/// 最小激活连接 controller：直接给出已激活连接，避免路由守卫把页面
/// 重定向到 `/onboarding`（`routerProvider` 的 redirect 依赖
/// `activeConnectionProvider`）。
class _ActiveConnectionController extends ActiveConnectionController {
  @override
  ServerConnection? build() => ServerConnection(
    id: 'c1',
    name: 'Home',
    baseUrl: 'http://home.local:30002',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}
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

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required Size viewport,
  required GoRouter router,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());

  final api = FakeSessionListApi(
    sessions: [
      SessionSummary(
        sessionId: 's1',
        title: '测试会话',
        lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
      ),
    ],
  );

  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home',
      baseUrl: 'http://home.local:30002',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');

  final container = ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  // 设置页有常驻动画（呼吸/脉冲）⇒ pumpAndSettle 会挂死 ⇒ 关掉动画。
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

/// 真实路由表（用仓内 `routerProvider`）——必须用真的，否则测不到双栈分裂。
GoRouter _realRouter(ProviderContainer container) =>
    container.read(routerProvider);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (viewport, wide) in [
    (const Size(1400, 1000), true),
    (const Size(420, 900), false),
  ]) {
    testWidgets('宽屏=$wide：新增服务器页的返回落回设置页而非主页', (
      tester,
    ) async {
      late ProviderContainer container;
      late GoRouter router;

      // 先建容器再取 router（routerProvider 依赖容器里的 provider）。
      container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: InMemorySecureStorage()),
          ),
          activeConnectionProvider.overrideWith(
            _ActiveConnectionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      router = _realRouter(container);
      await _pumpApp(tester, viewport: viewport, router: router);

      // 从主页 push 进设置页（真实入口 `openAdaptiveRoute` = `context.push`）
      unawaited(router.push('/settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byType(SettingsPage),
        findsOneWidget,
        reason: '应停在设置页',
      );

      // 宽屏要先切到「服务器」分类；窄屏要滚出服务器分组。
      final navServer = find.byKey(const ValueKey('settings-nav-server'));
      if (navServer.evaluate().isNotEmpty) {
        await tester.tap(navServer);
        await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      }
      final addBtn = find.byKey(const ValueKey('server-add'));
      if (addBtn.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('server-add')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      }
      expect(addBtn, findsOneWidget);


      // 进「新增服务器」编辑页
      await tester.tap(addBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey('server-editor-url')),
        findsOneWidget,
        reason: '应进入服务器编辑页',
      );

      // 按编辑页的返回按钮 ⇒ 必须落回设置页
      await tester.tap(find.byType(AppBackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byType(SettingsPage),
        findsOneWidget,
        reason: '返回后应回到设置页（服务器列表），而不是主页',
      );
      // 落点判据 = go_router 的当前路由（比「找某个 widget」更准：
      // 宽屏左栏常驻会话列表，`SessionListPage` 在设置页时也存在）。
      // 判据用 **widget 层**（`currentConfiguration.uri` 在 ShellRoute 下
      // 恒为 '/'，不反映子路由 ⇒ 不能当判据）。
      expect(
        find.byKey(const ValueKey('server-editor-url')),
        findsNothing,
        reason: '编辑页应已关闭',
      );
      expect(
        find.byKey(const ValueKey('settings-scroll')),
        findsOneWidget,
        reason: '返回后应停在设置页（服务器列表）',
      );
    });
  }

  testWidgets('新增服务器保存成功后落回设置页的服务器列表', (tester) async {
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
        activeConnectionProvider.overrideWith(
          _ActiveConnectionController.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = _realRouter(container);
    await _pumpApp(
      tester,
      viewport: const Size(1400, 1000),
      router: router,
    );

    unawaited(router.push('/settings'));
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

    final navServer = find.byKey(const ValueKey('settings-nav-server'));
    if (navServer.evaluate().isNotEmpty) {
      await tester.tap(navServer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const ValueKey('server-add')));
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(
      find.byKey(const ValueKey('server-editor-name')),
      'Lab',
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-editor-url')),
      'http://lab.example.com:30002',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('server-editor-save')));
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

    // 落点 = 设置页，且新服务器已在列表里（用户可立即点「激活」）
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('server-editor-url')),
      findsNothing,
      reason: '保存后编辑页应已关闭',
    );
    expect(
      find.byKey(const ValueKey('settings-scroll')),
      findsOneWidget,
      reason: '保存成功后应落回设置页（服务器列表）',
    );
    expect(find.text('Lab'), findsOneWidget);
  });
}

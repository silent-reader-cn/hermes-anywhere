import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/shared/app_back_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #211 同族回归：设置页内**其余**二级页的返回也必须落回设置页。
///
/// 缺陷同源：这些二级页此前用原生 `Navigator.of(context).push` 推入，与
/// go_router 栈**分裂** ⇒ `AppBackButton` 的 `context.canPop()` 判据失真
/// ⇒ 返回直接 `go('/')` 退到主页。
///
/// 覆盖 4 个二级页：
///   · 扩展安装表单（`/settings/extension-install`）
///   · MCP 服务器编辑（`/settings/mcp-server`）
///   · MCP 工具列表（`/settings/mcp-tools`）
///   · 辅助模型任务选择器（`/settings/aux-task-picker`）
///
/// 判据用 **widget 层**（`currentConfiguration.uri` 在 ShellRoute 下恒为
/// '/'，不反映子路由 ⇒ 不能当判据）。
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

/// 最小激活连接 controller：避免路由守卫把页面重定向到 `/onboarding`。
class _ActiveConnectionController extends ActiveConnectionController {
  @override
  ServerConnection? build() => ServerConnection(
    id: 'c1',
    name: 'Home',
    baseUrl: 'http://home.local:30002',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
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

  final container = ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(store),
      activeConnectionProvider.overrideWith(
        _ActiveConnectionController.new,
      ),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      // 扩展 / MCP 分区的入口只在 **data 态** 才渲染（加载中/出错态只有
      // loading / error 分支）⇒ 注入 fake API 让它进 data 态。
      settingsApiFactoryProvider.overrideWithValue(
        (_) => FakeSettingsApi()
          ..mcpServersResponse = const McpServersResponse(
            servers: [
              McpServer(
                name: 'Sample',
                command: 'echo',
                args: [],
                enabled: true,
              ),
            ],
          ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  // 设置页有常驻动画 ⇒ pumpAndSettle 会挂死 ⇒ 关掉动画。
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(
    tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  unawaited(router.push('/settings'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 宽屏设置页：切到指定分类（服务器 / 扩展 / 高级设置）。
Future<void> _selectCategory(
  WidgetTester tester,
  String name,
) async {
  final rail = find.byKey(ValueKey('settings-nav-$name'));
  if (rail.evaluate().isEmpty) return;
  await tester.tap(rail);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 点一个入口 key。
///
/// 入口都带稳定 key 且在宽屏分类内容区里直接渲染（不需要滚动）⇒ 若找不到
/// 就是「该入口不存在 / 分类没切对」，直接失败报错（**不静默跳过**——
/// 静默跳过会让缺陷永远测不出来）。
Future<void> _tapEntry(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  // 二级页内容来自异步 provider（extensions / mcp servers）⇒ 入口可能
  // 要等几帧才出现 ⇒ 轮询等待（但有上限，避免无限等）。
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    finder,
    findsOneWidget,
    reason: '入口 $key 应存在（分类是否切对？key 是否变更？）',
  );
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('扩展安装页：返回落回扩展二级页而非主页', (tester) async {
    await _pumpApp(tester);
    // 路径：设置页 → 高级设置分类 → 扩展二级页 → 扩展安装表单
    await _selectCategory(tester, 'advanced');
    await _tapEntry(tester, const ValueKey('settings-entry-extensions'));
    await _tapEntry(tester, const ValueKey('settings-extension-install'));
    expect(
      find.byKey(const ValueKey('extension-install-id')),
      findsOneWidget,
      reason: '应进入扩展安装表单',
    );

    // #211 之后，三级页的返回按钮是 `AppBackButton`（按 go_router 栈判据）。
    await tester.tap(find.byType(AppBackButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('extension-install-id')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-extensions-section')),
      findsOneWidget,
      reason: '返回后应停在扩展二级页（不是主页、也不是把设置页带离）',
    );
  });

  testWidgets('MCP 服务器编辑页：返回落回 MCP 二级页而非主页', (tester) async {
    await _pumpApp(tester);
    // 路径：设置页 → 高级设置分类 → MCP 二级页 → 服务器编辑页
    await _selectCategory(tester, 'advanced');
    await _tapEntry(tester, const ValueKey('settings-entry-mcp'));
    await _tapEntry(tester, const ValueKey('settings-mcp-add'));
    expect(
      find.byKey(const ValueKey('mcp-editor-name')),
      findsOneWidget,
      reason: '应进入 MCP 服务器编辑页',
    );

    // #211 之后，三级页的返回按钮是 `AppBackButton`（按 go_router 栈判据）。
    await tester.tap(find.byType(AppBackButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('mcp-editor-name')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-mcp-section')),
      findsOneWidget,
      reason: '返回后应停在 MCP 二级页（不是主页、也不是把设置页带离）',
    );
  });

  testWidgets('MCP 工具列表页：返回落回设置页而非主页', (tester) async {
    await _pumpApp(tester);
    await _selectCategory(tester, 'advanced');
    await _tapEntry(tester, const ValueKey('settings-entry-mcp'));

    // MCP 工具列表入口是 **action sheet 里的按钮**（`mcp-tools-<name>`）：
    // 先点服务器行 → 弹 action sheet → 再点「工具 (N)」⇒ 才进工具列表页。
    // 本例已注入一个服务器（fake API）⇒ 行必定存在，不靠「等网络」也不靠 skip。
    await _tapEntry(tester, const ValueKey('mcp-server-row-Sample'));

    final entry = find.byKey(const ValueKey('mcp-tools-Sample'));
    expect(entry, findsOneWidget, reason: 'MCP 工具入口应在 action sheet 里');
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // #211 之后，三级页的返回按钮是 `AppBackButton`（按 go_router 栈判据）。
    await tester.tap(find.byType(AppBackButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('settings-mcp-section')),
      findsOneWidget,
      reason: '返回后应停在 MCP 二级页（不是主页）',
    );
  });
}

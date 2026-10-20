import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _EmptyProjectsController extends ProjectsController {
  @override
  Future<List<ProjectSummary>> build() async => const [];
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  final api = FakeSessionListApi(
    sessions: const [
      SessionSummary(
        sessionId: 'alpha',
        title: 'Alpha session',
        pinned: true,
        workspace: '/demo/alpha',
        messageCount: 8,
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
      projectsProvider.overrideWith(_EmptyProjectsController.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        theme: buildCupertinoTheme(brightness),
        home: const SessionListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 取窄屏会话分组卡片的描边（`DecoratedSliver` → `ShapeDecoration`）。
///
/// 窄屏分支 = `width < 900`（宽屏侧栏走「朴素行」，没有卡片容器）。
BorderSide? _narrowCardBorder(WidgetTester tester) {
  final sliver = tester.widget<DecoratedSliver>(find.byType(DecoratedSliver));
  final decoration = sliver.decoration;
  if (decoration is! ShapeDecoration) return null;
  final shape = decoration.shape;
  if (shape is! RoundedSuperellipseBorder) return null;
  return shape.side;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // #210：窄屏会话卡片两主题都必须描边 —— 此前暗色走 `BorderSide.none`，
  // 导致深色下会话项没有任何轮廓，与设置页「每项都有外框」并排看时
  // 不像同一套控件。
  testWidgets('窄屏会话卡片在暗色下也有 0.5pt 描边', (tester) async {
    await _pumpPage(tester, brightness: Brightness.dark);

    final side = _narrowCardBorder(tester);
    expect(side, isNotNull, reason: '窄屏会话卡片必须带描边');
    expect(side!.width, 0.5);
    expect(side.style, BorderStyle.solid);
    expect(
      side.color.toARGB32(),
      CupertinoColors.separator
          .resolveFrom(tester.element(find.byType(SessionListPage)))
          .toARGB32(),
    );
  });

  testWidgets('窄屏会话卡片在浅色下沿用 cardBorder 描边', (tester) async {
    await _pumpPage(tester, brightness: Brightness.light);

    final side = _narrowCardBorder(tester);
    expect(side, isNotNull);
    expect(side!.width, 0.5);
    expect(side.color.toARGB32(), LightSurfaces.cardBorder.toARGB32());
  });
}

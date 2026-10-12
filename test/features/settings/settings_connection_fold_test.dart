import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/update/update_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 设置页「服务器」列表的 installId 折叠（同机多地址）。
//
// 硬要求取证：
// - 折叠后每条地址仍**可切换**（点从属行 → active 落盘变化）；
// - 折叠不吞入口（展开后编辑/删除 key 与主行同款）；
// - builtin 不参与折叠；
// - installId 为空的旧连接：不折叠、行内 padding 仍是默认值（逐像素口径）。
// ---------------------------------------------------------------------------

class _NoUpdateController extends AutoCheckUpdateController {
  @override
  bool build() => false;
}

ServerConnection conn(
  String id, {
  required String name,
  required String baseUrl,
  String installId = '',
  ConnectionKind kind = ConnectionKind.remote,
}) => ServerConnection(
  id: id,
  name: name,
  baseUrl: baseUrl,
  createdAt: DateTime.utc(2026, 1, 1),
  kind: kind,
  installId: installId,
);

Future<void> pumpSettings(
  WidgetTester tester, {
  required ConnectionStore store,
}) async {
  // 宽屏档（≥900）：左栏分类导航 + 右栏只渲染「服务器」分类 —— 待测分组在首屏，
  // 断言不受惰性构建影响（同 settings_wide_category_nav_test 的口径）。
  tester.view.physicalSize = const Size(960, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://example.com'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => FakeSettingsApi()),
        autoCheckUpdateEnabledProvider.overrideWith(_NoUpdateController.new),
      ],
      child: CupertinoApp(
        theme: buildCupertinoTheme(Brightness.light),
        home: const SettingsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(const ValueKey('settings-nav-server')));
  await tester.pumpAndSettle();
}

/// 把某 key 滚进视口（懒构建区可能还没建出来）。
Future<void> revealKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  for (var i = 0; i < 20 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await revealKey(tester, key);
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// 折叠标注行（key 前缀固定）。
Finder groupToggle(String installId) =>
    find.byKey(ValueKey('server-group-toggle-$installId'));

Finder serverRow(String id) => find.byKey(ValueKey('server-row-$id'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('③ 同 installId 两地址 ⇒ 一条主行 + 「另有 1 个地址」，展开后两条都能切', (tester) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    await store.save(conn('a', name: '家 · 局域网', baseUrl: 'http://192.168.1.7:8787', installId: 'iid-1'));
    await store.save(conn('b', name: '家 · 公网', baseUrl: 'https://home.example.com', installId: 'iid-1'));
    await store.setActive('a');
    await pumpSettings(tester, store: store);

    // 折叠标注行在场（先滚到它，确保该 section 已构建）
    await revealKey(tester, 'server-group-toggle-iid-1');
    expect(groupToggle('iid-1'), findsOneWidget);
    expect(find.text('另有 1 个地址'), findsOneWidget);
    // 主行 = 组内首现那条；被折叠的 b 默认不在列表里
    expect(serverRow('a'), findsOneWidget);
    expect(serverRow('b'), findsNothing);

    // 展开 → b 的行原样出现（同 key / 同 builder）
    await tapKey(tester, 'server-group-toggle-iid-1');
    expect(serverRow('a'), findsOneWidget);
    expect(serverRow('b'), findsOneWidget);
    expect(storage.data[ConnectionStore.activeConnectionKey], 'a');

    // 点 b → 切换生效（写盘 active 指向 b）
    await tapKey(tester, 'server-row-b');
    expect(storage.data[ConnectionStore.activeConnectionKey], 'b');
    // 切换后主行变 b、a 成为从属行 —— 两条地址始终可达，标注数量仍为 1
    expect(find.text('另有 1 个地址'), findsOneWidget);
    expect(serverRow('a'), findsOneWidget);
  });

  testWidgets('③ 折叠不吞入口：展开后从属地址的编辑/删除入口与主行同款；收起可复现', (tester) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    await store.save(conn('a', name: '家 · 局域网', baseUrl: 'http://192.168.1.7:8787', installId: 'iid-1'));
    await store.save(conn('b', name: '家 · 公网', baseUrl: 'https://home.example.com', installId: 'iid-1'));
    await store.setActive('a');
    await pumpSettings(tester, store: store);

    await tapKey(tester, 'server-group-toggle-iid-1');
    await revealKey(tester, 'server-edit-b');
    expect(find.byKey(const ValueKey('server-edit-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-delete-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-edit-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-delete-a')), findsOneWidget);

    // 收起 → 从属行消失、主行仍在（折叠态收敛回一条）
    await tapKey(tester, 'server-group-toggle-iid-1');
    expect(serverRow('a'), findsOneWidget);
    expect(serverRow('b'), findsNothing);
    expect(find.text('另有 1 个地址'), findsOneWidget);
  });

  testWidgets('③ 主行优先取当前激活地址（折叠态就能看到「在用的是哪条」）', (tester) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    await store.save(conn('a', name: '家 · 局域网', baseUrl: 'http://192.168.1.7:8787', installId: 'iid-1'));
    await store.save(conn('b', name: '家 · 公网', baseUrl: 'https://home.example.com', installId: 'iid-1'));
    await store.setActive('b');
    await pumpSettings(tester, store: store);

    await revealKey(tester, 'server-group-toggle-iid-1');
    expect(serverRow('b'), findsOneWidget);
    expect(serverRow('a'), findsNothing);
    expect(find.text('另有 1 个地址'), findsOneWidget);

    // 折叠起来的 a 依然可切回去
    await tapKey(tester, 'server-group-toggle-iid-1');
    await tapKey(tester, 'server-row-a');
    expect(storage.data[ConnectionStore.activeConnectionKey], 'a');
  });

  testWidgets('③ 三地址同机 ⇒ 「另有 2 个地址」', (tester) async {
    final store = ConnectionStore(storage: InMemorySecureStorage());
    await store.save(conn('a', name: 'A', baseUrl: 'http://a.local:8787', installId: 'iid-3'));
    await store.save(conn('b', name: 'B', baseUrl: 'http://b.local:8787', installId: 'iid-3'));
    await store.save(conn('c', name: 'C', baseUrl: 'http://c.local:8787', installId: 'iid-3'));
    await store.setActive('a');
    await pumpSettings(tester, store: store);

    await revealKey(tester, 'server-group-toggle-iid-3');
    expect(find.text('另有 2 个地址'), findsOneWidget);
    await tapKey(tester, 'server-group-toggle-iid-3');
    expect(serverRow('b'), findsOneWidget);
    expect(serverRow('c'), findsOneWidget);
  });

  testWidgets('④ 不同 installId ⇒ 不折叠：两行都在，无折叠标注', (tester) async {
    final store = ConnectionStore(storage: InMemorySecureStorage());
    await store.save(conn('a', name: 'A', baseUrl: 'http://a.local:8787', installId: 'iid-1'));
    await store.save(conn('b', name: 'B', baseUrl: 'http://b.local:8787', installId: 'iid-2'));
    await store.setActive('a');
    await pumpSettings(tester, store: store);

    await revealKey(tester, 'server-row-b');
    expect(serverRow('a'), findsOneWidget);
    expect(serverRow('b'), findsOneWidget);
    expect(find.textContaining('另有 '), findsNothing);
  });

  testWidgets('④ installId 为空（旧连接）⇒ 与现状一致：不折叠、行内 padding 未改', (tester) async {
    final store = ConnectionStore(storage: InMemorySecureStorage());
    await store.save(conn('a', name: 'A', baseUrl: 'http://a.local:8787'));
    await store.save(conn('b', name: 'B', baseUrl: 'http://b.local:8787'));
    await store.setActive('a');
    await pumpSettings(tester, store: store);

    await revealKey(tester, 'server-row-b');
    expect(serverRow('a'), findsOneWidget);
    expect(serverRow('b'), findsOneWidget);
    expect(find.textContaining('另有 '), findsNothing);

    // 逐像素口径的取证：旧连接的行没有任何缩进（padding 保持 null = 框架默认）
    for (final id in ['a', 'b']) {
      final tile = tester.widget<CupertinoListTile>(serverRow(id));
      expect(tile.padding, isNull, reason: '旧连接行不得因折叠功能改变内边距');
    }
  });

  testWidgets('④ builtin 不参与折叠：内置连接单列，同 installId 的 remote 照常折叠', (tester) async {
    final store = ConnectionStore(storage: InMemorySecureStorage());
    await store.save(
      conn('builtin-sidecar', name: '内置', baseUrl: 'http://127.0.0.1:30002', kind: ConnectionKind.builtin),
    );
    await store.save(conn('a', name: 'A', baseUrl: 'http://a.local:8787', installId: 'iid-1'));
    await store.save(conn('b', name: 'B', baseUrl: 'http://b.local:8787', installId: 'iid-1'));
    await store.setActive('builtin-sidecar');
    await pumpSettings(tester, store: store);

    await revealKey(tester, 'server-group-toggle-iid-1');
    expect(serverRow('builtin-sidecar'), findsOneWidget);
    expect(groupToggle('iid-1'), findsOneWidget);
    expect(find.text('另有 1 个地址'), findsOneWidget);
  });

  testWidgets('折叠行的标注行可点（Affordance）：标注行自身是 CupertinoListTile 且带 chevron', (
    tester,
  ) async {
    final store = ConnectionStore(storage: InMemorySecureStorage());
    await store.save(conn('a', name: 'A', baseUrl: 'http://a.local:8787', installId: 'iid-1'));
    await store.save(conn('b', name: 'B', baseUrl: 'http://b.local:8787', installId: 'iid-1'));
    await store.setActive('a');
    await pumpSettings(tester, store: store);

    await revealKey(tester, 'server-group-toggle-iid-1');
    final tile = tester.widget<CupertinoListTile>(groupToggle('iid-1'));
    expect(tile.onTap, isNotNull);
    expect(
      find.descendant(
        of: groupToggle('iid-1'),
        matching: find.byIcon(CupertinoIcons.chevron_right),
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'server-group-toggle-iid-1');
    expect(
      find.descendant(
        of: groupToggle('iid-1'),
        matching: find.byIcon(CupertinoIcons.chevron_down),
      ),
      findsOneWidget,
    );
  });
}

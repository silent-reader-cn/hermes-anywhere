import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_secure_storage.dart';

/// #204 收尾：设置页入口接回本机向导 + 指路文案落到真实路径。
///
/// 三条守卫，各钉一件事（每条都要能回答「缺陷还在时它会不会同样通过」）：
/// ① 路由守卫：有活跃连接时 `/install-guide` **不被弹回主页**（改前是 `→ '/'`）；
/// ② 设置页入口的落点 = 本机向导（不是官网文档）；
/// ③ 文案：指路说的是**真实可点层级**「设置 → 桌面 → 内置 WebUI 服务」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('#204 设置页 → 本机向导 入口', () {
    testWidgets('有活跃连接时 /install-guide 不被守卫弹回主页', (tester) async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      final container = ProviderContainer(
        overrides: [connectionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      // 走**生产链**：先 upsert 进 connectionsProvider（它持有内存态），再
      // setActive 激活。直接往 store 里写不够 —— 守卫读的是
      // `activeConnectionProvider` 的内存 state。
      final conn = ServerConnection(
        id: 'remote-1',
        name: 'Remote',
        baseUrl: 'https://example.invalid',
        username: null,
        password: null,
        customHeaders: const {},
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.remote,
        enabled: true,
      );
      await container.read(connectionsProvider.notifier).upsert(conn);
      await container
          .read(activeConnectionProvider.notifier)
          .setActive(conn.id);

      final router = container.read(routerProvider);
      addTearDown(router.dispose);

      expect(
        container.read(activeConnectionProvider),
        isNotNull,
        reason: '前提：确有活跃连接',
      );

      // 必须挂到 app 上：go_router 的路由解析要在有 Navigator 的树上发生
      // （裸 container 里 `router.go()` 不解析，currentConfiguration 恒为空串）。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/install-guide');
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/install-guide',
        reason: '有活跃连接时进 /install-guide 必须留在向导，不能被守卫弹回主页'
            '（改前守卫是 hasActive && isInstallGuide → 主页）',
      );
    });

    testWidgets('无活跃连接时 /install-guide 仍可达（不得被守卫误伤）', (
      tester,
    ) async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      final container = ProviderContainer(
        overrides: [connectionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go('/install-guide');
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/install-guide',
      );
    });
  });

  group('#204 指路文案落到真实可点路径', () {
    test('端口/密码指路写明「设置 → 桌面 → 内置 WebUI 服务」', () {
      final l10n = const AppLocalizations(Locale('zh'));
      expect(
        l10n.installWizardBuiltinSettingsHint,
        contains('设置 → 桌面 → 内置 WebUI 服务'),
        reason: '指路必须写真实层级；原措辞只说「内置服务」而那个 section 挂在'
            '「桌面」子页下、标题叫「内置 WebUI 服务」⇒ 用户按原文找不到入口',
      );
    });

    test('凭据行不显示明文密码，但指到看密码的地方', () {
      final l10n = const AppLocalizations(Locale('zh'));
      expect(
        l10n.installWizardCredentialValueWithPath,
        contains('设置 → 桌面 → 内置 WebUI 服务'),
        reason: '桌面浏览器直连需要密码 ⇒ 必须指得到在哪看',
      );
      expect(
        l10n.installWizardCredentialValueWithPath,
        isNot(contains('配对码交接')),
        reason: '手机端配对向导已把配对码讲透 ⇒ 凭据行不再重复该措辞，只说密码在哪',
      );
    });
  });
}

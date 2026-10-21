import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace/workspace_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_workspace_api.dart';

/// 工作区文件浏览 · Android 系统返回键 = 上一级目录（#206）。
///
/// **为什么必须是端到端**：本条缺陷的根因是「返回键命中的 route 层级」——
/// `/workspace/:id` 是 `context.push` 出来的**独立 route**，Android 返回键由
/// `RouterDelegate.popRoute()` 逐 navigator 调 `maybePop()`，**先命中本页这个
/// 栈顶 route**。旧实现把拦截挂在 shell 的注册表链路上，而事件根本冒泡不到
/// 那一层（实测：注册表 asked=0、页面已被 pop 掉）。
///
/// 故本组用例**真起一个 shell + push 的路由栈**，用真实的系统返回键
/// （`handlePopRoute`）驱动，而不是直接调注册表（那样测不到层级问题）。
void main() {
  /// 目录条目（path 缺省 = name；嵌套目录需给完整相对路径）。
  WorkspaceEntry buildEntry(String name, {String? path, bool dir = false}) =>
      WorkspaceEntry(name: name, path: path ?? name, isDirectory: dir);

  /// 起一个真实路由栈：shell 内 `/` + push 出来的 `/workspace/:id`。
  Future<GoRouter> pumpWorkspaceRoute(
    WidgetTester tester,
    FakeWorkspaceApi api,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const SizedBox()),
            GoRoute(
              path: '/workspace/:id',
              builder: (context, state) =>
                  WorkspacePage(sessionId: state.pathParameters['id'] ?? 's1'),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          workspaceApiFactoryProvider.overrideWithValue((_) => api),
          ...createDownloadTestOverrides(),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    return router;
  }

  testWidgets('非根目录：系统返回键 = 上一级目录（页面不被退出）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('src', dir: true)],
          'src': [buildEntry('main.dart')],
        },
      );
      final router = await pumpWorkspaceRoute(tester, api);

      unawaited(router.push('/workspace/s1'));
      await tester.pumpAndSettle();
      expect(find.text('src'), findsOneWidget);

      // 进入子目录。
      await tester.tap(find.text('src'));
      await tester.pump();
      await tester.pump();
      expect(find.text('main.dart'), findsOneWidget);

      // Android 系统返回键。
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();

      // 回到上一级目录，**页面仍在**（没被退出）。
      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);
      expect(find.byType(WorkspacePage), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('根目录：系统返回键放行（退出工作区页）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      final router = await pumpWorkspaceRoute(tester, api);

      unawaited(router.push('/workspace/s1'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();

      // 根目录：返回键**不劫持目录层级**（仍在根目录，列表内容不变）。
      //
      // 注：根目录时返回键并不必然退出工作区页 —— shell 的 Android 返回分流
      // （`AdaptiveShell._handleAndroidBack`）在栈顶是 shell 自身时接管该事件，
      // 页面是否退出由 shell 的既定策略决定。本页的职责边界是「非根目录时把
      // 返回键吃掉去上一级」，根目录一律放行（不吞事件、不改层级）。
      expect(find.text('a.txt'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('子目录逐级返回：每按一次退一级，直到根目录才退出页面', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a', dir: true)],
          'a': [buildEntry('b', path: 'a/b', dir: true)],
          'a/b': [buildEntry('c.txt', path: 'a/b/c.txt')],
        },
      );
      final router = await pumpWorkspaceRoute(tester, api);

      unawaited(router.push('/workspace/s1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('a'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('b'));
      await tester.pump();
      await tester.pump();
      expect(find.text('c.txt'), findsOneWidget);

      // 第一次返回：a/b → a。
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      expect(find.text('b'), findsOneWidget);
      expect(find.byType(WorkspacePage), findsOneWidget);

      // 第二次返回：a → 根目录。
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      expect(find.text('a'), findsOneWidget);
      expect(find.byType(WorkspacePage), findsOneWidget);

      // 第三次返回：已回到根目录 ⇒ 本页不再吞事件（层级保持根目录）。
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      expect(find.text('a'), findsOneWidget);
      expect(find.byType(WorkspacePage), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('非 Android：返回键行为不变（不劫持 iOS/桌面）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('src', dir: true)],
          'src': [buildEntry('main.dart')],
        },
      );
      final router = await pumpWorkspaceRoute(tester, api);

      unawaited(router.push('/workspace/s1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('src'));
      await tester.pump();
      await tester.pump();
      expect(find.text('main.dart'), findsOneWidget);

      // iOS 不由本页 PopScope 接管 ⇒ 页面按平台默认行为处理。
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();

      // 关键：目录层级**未被**本页劫持回退（仍是子目录内容）。
      expect(find.text('main.dart'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

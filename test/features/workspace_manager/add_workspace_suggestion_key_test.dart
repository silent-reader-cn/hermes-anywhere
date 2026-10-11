import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/workspace_manager/add_workspace_sheet.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_workspace_manager_api.dart';

// ---------------------------------------------------------------------------
// 路径补全建议列表（ListView.separated）：key 必须是建议文本、而不是下标。
//
// 危险形状：`ValueKey('workspace-add-suggestion-$index')` —— 建议来自
// `/workspaces/suggest?prefix=`，前缀越具体，命中集合越小；**幸存项会换下标**，
// 而下标型 key 跟着换 ⇒ 那条建议被销毁重建（按压态/命中态丢失）。
//
// 判据：把前缀从 `/home/user` 收窄到 `/home/user/p`（幸存项 `/home/user/proj`
// 从下标 1 升到 0）后比 element 是否 identical；对照组是「换前缀但建议集合与
// 顺序完全不变」的一次真实重取（证明只有下标位移会被判负）。
// ---------------------------------------------------------------------------

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

const String _other = '/home/user/other';
const String _proj = '/home/user/proj';

/// 建议行 element：按文本定位其最近的 CupertinoButton 祖先（补 key 前后都成立）。
Element _suggestionRow(WidgetTester tester, String text) => tester.element(
  find
      .ancestor(of: find.text(text), matching: find.byType(CupertinoButton))
      .first,
);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('workspace-add-path')),
    text,
  );
  // 250ms 防抖 → 请求 → setState。
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('前缀收窄导致幸存建议换下标时，该行 element 应复用', (tester) async {
    final api = FakeWorkspaceManagerApi()
      ..suggestionsByPrefix['/home/user'] = [_other, _proj]
      // 前缀收窄后只命中 proj：它从下标 1 升到 0，内容一字不变。
      ..suggestionsByPrefix['/home/user/p'] = [_proj]
      // 对照组：换前缀但集合与顺序完全不变。
      ..suggestionsByPrefix['/home/user/'] = [_other, _proj];
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceManagerApiFactoryProvider.overrideWithValue((_) => api),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          localizationsDelegates: _delegates,
          home: AddWorkspaceSheet(),
        ),
      ),
    );
    await tester.pump();

    await _type(tester, '/home/user');
    expect(api.suggestionCalls, ['/home/user']);
    expect(find.text(_other), findsOneWidget);
    expect(find.text(_proj), findsOneWidget);
    final projBefore = tester.getTopLeft(find.text(_proj)).dy;
    expect(
      projBefore,
      greaterThan(tester.getTopLeft(find.text(_other)).dy),
      reason: '_proj 初始在下标 1',
    );

    // 对照组（内容不变）：换前缀但建议集合与顺序完全不变 ⇒ element 必须复用。
    final control = _suggestionRow(tester, _proj);
    await _type(tester, '/home/user/');
    expect(api.suggestionCalls, ['/home/user', '/home/user/']);
    expect(
      identical(_suggestionRow(tester, _proj), control),
      isTrue,
      reason: '内容不变的对照组：一次真实重取、集合不变时行 element 不该被重建',
    );

    // 判据点：前缀收窄 ⇒ 幸存项 _proj 从下标 1 升到 0。
    final captured = _suggestionRow(tester, _proj);
    await _type(tester, '/home/user/p');
    expect(api.suggestionCalls, ['/home/user', '/home/user/', '/home/user/p']);
    expect(find.text(_other), findsNothing);
    final projAfter = tester.getTopLeft(find.text(_proj)).dy;
    expect(projAfter, lessThan(projBefore), reason: '_proj 必须上移（否则判据空转）');

    expect(
      identical(_suggestionRow(tester, _proj), captured),
      isTrue,
      reason: '下标 1 → 0：下标型 key 在这里必然换 key 并重建；文本身份 + 反查才复用',
    );
  });
}

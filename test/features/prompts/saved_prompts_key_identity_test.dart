import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/prompts/widgets/saved_prompts_sheet.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_prompts_api.dart';

// ---------------------------------------------------------------------------
// 收藏提示词列表（ListView.separated）：key 必须是身份、而不是「身份 + 下标」。
//
// 危险形状：`ValueKey('saved-prompt-$id-$index')` —— key 里含下标，任何增删
// 都会换 key（同一条提示词换了下标 = 换了身份）⇒ 框架永远匹配不上，整段行
// 销毁重建。修复口径：id 非空时 key 就是 id（身份型），并补 findItemIndexCallback。
//
// 判据：删除首条后，第 3 条提示词的行 element 是否 identical（带「内容不变」
// 对照组 + 位置确实上移的证据）。行 element 用「文本祖先」取，
// 该取法在改 key 前后都成立，RED/GREEN 用同一判据。
// ---------------------------------------------------------------------------

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

SavedPrompt _prompt(String id, String text, String label) =>
    SavedPrompt(id: id, label: label, text: text, createdAt: 1700000000);

/// 行 element：按标题文本定位其最近的 CupertinoListTile 祖先。
Element _row(WidgetTester tester, String title) => tester.element(
  find
      .ancestor(
        of: find.text(title),
        matching: find.byType(CupertinoListTile),
      )
      .first,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('删除首条后，第 3 条的行 element 应复用（key 必须是身份型）', (
    tester,
  ) async {
    final api = FakePromptsApi(
      initialPrompts: [
        _prompt('a1', 'one', 'First'),
        _prompt('a2', 'two', 'Second'),
        _prompt('a3', 'three', 'Third'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        promptsApiFactoryProvider.overrideWithValue((_) => api),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(
          localizationsDelegates: _delegates,
          home: SavedPromptsSheet(onInsert: _noop),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Third'), findsOneWidget);

    // 对照组（内容不变）：不动数据，再 pump（含一次异步刷新窗口）⇒ element 复用。
    final control = _row(tester, 'Third');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      identical(_row(tester, 'Third'), control),
      isTrue,
      reason: '内容不变的对照组：数据源未变时行 element 不该被重建',
    );

    final captured = _row(tester, 'Third');
    final yBefore = tester.getTopLeft(find.text('Third')).dy;

    await tester.tap(find.byKey(const ValueKey('saved-prompt-delete-a1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(api.deleteCount, 1);
    expect(api.lastDeleteId, 'a1');
    expect(find.text('First'), findsNothing);
    // 重排确实发生：a3 从下标 2 升到 1。
    final yAfter = tester.getTopLeft(find.text('Third')).dy;
    expect(yAfter, lessThan(yBefore), reason: 'Third 必须上移（否则判据空转）');

    expect(
      identical(_row(tester, 'Third'), captured),
      isTrue,
      reason: '下标 2 → 1：key 若含下标则身份变了、必然重建；身份型 key + 反查才复用',
    );
  });
}

void _noop(String _) {}

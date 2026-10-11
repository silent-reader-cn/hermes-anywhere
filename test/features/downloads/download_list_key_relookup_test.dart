import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_page.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_download_service.dart';

// ---------------------------------------------------------------------------
// 行 key 与「key → 下标」反查守卫（下载页列表 / 宽屏两列网格）。
//
// SDK 依据：`SliverMultiBoxAdaptorElement.performRebuild` 只拿「直接子节点
// element 的 widget.key」去 `delegate.findIndexByKey(key)`；返回 null ⇒ 框架
// 不会移动该 element，而按旧下标 `updateChild(old, _build(旧下标))` 更新 ——
// key 与旧下标上的新 widget 不一致 ⇒ 旧 element 被停用、整行销毁重建。
//
// 判据形态：同一批条目在「顺序变化前 / 后」比 `tester.element(...)` 是否
// identical。**必须**同时带「内容不变」对照组，否则无法排除「本来就会重建」。
// 另断言几何位置确实变了（证明重排真的发生，判据不是空转）。
// ---------------------------------------------------------------------------

const List<LocalizationsDelegate<dynamic>> _delegates = [
  AppLocalizationsDelegate(),
  DefaultCupertinoLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// 任务列表的唯一可变来源（页面侧 `downloadTasksProvider` 从中派生）。
final _tasksState = StateProvider<List<DownloadTask>>(
  (ref) => const <DownloadTask>[],
);

DownloadTask _task(String id, int createdAt) => DownloadTask(
  id: id,
  sourceUrl: 'https://hermes.example.com/files/$id.bin',
  fileName: '$id.bin',
  mimeType: 'application/octet-stream',
  expectedBytes: 1024,
  createdAt: createdAt,
);

/// 4 条任务：display 顺序 = createdAt 倒序 ⇒ [t4, t3, t2, t1]。
/// 再加两条更新的（t6 > t5）时，display 顺序变 [t6, t5, t4, t3, t2, t1]。
List<DownloadTask> _baseTasks() => [
  _task('t1', 1780000000000),
  _task('t2', 1780000000001),
  _task('t3', 1780000000002),
  _task('t4', 1780000000003),
];

List<DownloadTask> _withTwoNewer() => [
  ..._baseTasks(),
  _task('t5', 1780000000004),
  _task('t6', 1780000000005),
];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Size size,
  List<DownloadTask> initial,
) async {
  final db = AppDatabase.memory();
  final tempDir = Directory.systemTemp.createTempSync('dl_listkey_test_');
  addTearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    await db.close();
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...createDownloadTestOverrides(db: db, tempDir: tempDir),
      downloadTasksProvider.overrideWith((ref) => ref.watch(_tasksState)),
    ],
  );
  addTearDown(container.dispose);
  container.read(_tasksState.notifier).state = initial;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: _delegates,
        theme: buildCupertinoTheme(Brightness.light),
        home: const DownloadPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

/// 窄屏：卡片本身就是列表的直接子节点 ⇒ 直接按键取 element。
Element _narrowCard(WidgetTester tester, String id) =>
    tester.element(find.byKey(ValueKey('download-task-$id')));

/// 宽屏：直接子节点是行（IntrinsicHeight），卡片在下一层 ⇒ 用「最近的行祖先」
/// 取 element —— 该取法在补 key 前后都成立，RED/GREEN 用同一判据。
Element _wideRow(WidgetTester tester, String leftId) => tester.element(
  find
      .ancestor(
        of: find.byKey(ValueKey('download-task-$leftId')),
        matching: find.byType(IntrinsicHeight),
      )
      .first,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('窄屏列表：直接子节点已带稳定 key，缺的只是 key → 子下标反查', () {
    testWidgets('插入更新的任务后，被下移的卡片 element 应复用（identical）', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        const Size(400, 2000),
        _baseTasks(),
      );
      expect(find.byKey(const ValueKey('downloads-list-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('download-task-t1')), findsOneWidget);

      // 对照组（内容不变）：不改变列表，再 pump 一帧 ⇒ element 必须复用。
      final beforeControl = _narrowCard(tester, 't1');
      await tester.pump();
      expect(
        identical(_narrowCard(tester, 't1'), beforeControl),
        isTrue,
        reason: '内容不变的对照组：无改动时本就不该重建',
      );

      // 改动前：t1 在 display 顺序末位（下标 3），位置记为 y0。
      final captured = _narrowCard(tester, 't1');
      final yBefore = tester.getTopLeft(
        find.byKey(const ValueKey('download-task-t1')),
      ).dy;

      container.read(_tasksState.notifier).state = _withTwoNewer();
      await tester.pump();

      // 重排确实发生：两条更新的任务插在前面，t1 被下移。
      final yAfter = tester.getTopLeft(
        find.byKey(const ValueKey('download-task-t1')),
      ).dy;
      expect(
        yAfter,
        greaterThan(yBefore),
        reason: 't1 必须被下移（否则判据空转）',
      );
      expect(
        find.byKey(const ValueKey('download-task-t6')),
        findsOneWidget,
      );

      expect(
        identical(_narrowCard(tester, 't1'), captured),
        isTrue,
        reason: '下标从 3 → 5：key 复用要求 delegate 给出 key → 子下标反查',
      );
    });
  });

  group('宽屏两列网格：key 必须落在直接子节点（行）上且可反查', () {
    testWidgets('插入两条更新的任务（偶数位移）后，行内卡片 element 应整体复用', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        const Size(1280, 900),
        _baseTasks(),
      );
      expect(find.byKey(const ValueKey('downloads-grid-view')), findsOneWidget);
      // display 顺序 [t4, t3, t2, t1] ⇒ 行 [t4|t3]、[t2|t1]，左卡 id 为 t4 / t2。
      expect(find.byKey(const ValueKey('download-task-t4')), findsOneWidget);
      expect(find.byKey(const ValueKey('download-task-t2')), findsOneWidget);

      // 对照组（内容不变）。
      final control = _wideRow(tester, 't4');
      await tester.pump();
      expect(
        identical(_wideRow(tester, 't4'), control),
        isTrue,
        reason: '内容不变对照：无改动时行 element 不该被重建',
      );

      final capturedRow = _wideRow(tester, 't4');
      final capturedRight = _narrowCard(tester, 't3');
      final yBefore = tester
          .getTopLeft(find.byKey(const ValueKey('download-task-t4')))
          .dy;

      container.read(_tasksState.notifier).state = _withTwoNewer();
      await tester.pump();

      // display [t6, t5, t4, t3, t2, t1] ⇒ 行 [t6|t5]、[t4|t3]、[t2|t1]：
      // [t4|t3] 这一行从行下标 0 移到 1，行内容不变。
      final yAfter = tester
          .getTopLeft(find.byKey(const ValueKey('download-task-t4')))
          .dy;
      expect(yAfter, greaterThan(yBefore), reason: 't4 所在行必须下移一行');

      expect(
        identical(_wideRow(tester, 't4'), capturedRow),
        isTrue,
        reason: '行内容不变、只换下标：key 必须在直接子节点上且能反查到新行下标',
      );
      expect(
        identical(_narrowCard(tester, 't3'), capturedRight),
        isTrue,
        reason: '行复用后行内右侧卡片 element 必须一并复用（未整行重建）',
      );
    });
  });
}

// 宽屏侧栏「槽」令牌守卫测试（v6，2026-10-14 主人拍板；令牌实现见
// `lib/app/theme/light_surfaces.dart` 的「侧栏槽」段）。
//
// 本文件只断言**契约**，不碰实现：派生表逐档比对实测 hex、三个不变量（WCAG
// 相对亮度 + CIE L* 本地实现，不引依赖）、自定义优先与复位、深色默认档的动态
// 色语义、以及宽屏外壳把槽色接到侧栏整列而窄屏不渲染该外壳。
//
// 断言口径：派生值全部是**实测值**（逐档 hex 硬钉），不变量遍历
// `PageSurfacePreset` / `DarkSurfacePreset` 枚举；每档输入各不相同 ⇒ 任何一档
// 回归都会红，不存在恒真断言。
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/page_surface.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session_list_api.dart';

// ───────────────────────────────────────────────────────────────────────────
// 与实现同口径的度量（测试自带，不引依赖）：WCAG 相对亮度 → CIE L*。
// 刻意在这里重算而不是复用实现的私有函数：实现改了公式，本文件的不变量必须跟着红。
// ───────────────────────────────────────────────────────────────────────────

/// WCAG 相对亮度（0 = 黑，1 = 白）。
double _relativeLuminance(Color color) {
  final argb = color.toARGB32();
  double channel(int v) {
    final s = v / 255.0;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel((argb >> 16) & 0xFF) +
      0.7152 * channel((argb >> 8) & 0xFF) +
      0.0722 * channel(argb & 0xFF);
}

/// CIE L*（感知明度：0 = 黑，100 = 白）。
double _lstar(Color color) {
  final y = _relativeLuminance(color);
  return y > 0.008856
      ? (116 * math.pow(y, 1 / 3) - 16).toDouble()
      : 903.3 * y;
}

/// 供失败信息用的 `#RRGGBB`（断言红时能一眼看出两边各是什么色）。
String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// 浅色页底色 → 槽底「实测派生表」（六档预设；`custom` 无预设色，不参与）。
const Map<PageSurfacePreset, int> _lightSlabTable = {
  PageSurfacePreset.iosGrouped: 0xFFE6E6EC,
  PageSurfacePreset.neutral: 0xFFE6E6E6,
  PageSurfacePreset.neutralDeep: 0xFFE1E1E1,
  PageSurfacePreset.neutralBright: 0xFFECECEC,
  PageSurfacePreset.warmNeutral: 0xFFE5E3DF,
  PageSurfacePreset.warmPaper: 0xFFEAE7E3,
};

/// 深色页底色实算表。
///
/// `system` 档（= 不覆盖深色页底色）起手就是纯黑：未覆盖时令牌走
/// [LightSurfaces.kDefaultDarkSidebar]，其注释声明该值就是
/// `sidebarFor(#000000, dark: true)` 的实算值 —— 本表按纯黑参与不变量。
const Map<String, int> _darkPageTable = {
  'system (#000000)': 0xFF000000,
  'neutral (#1C1C1C)': 0xFF1C1C1C,
  'deeper (#141414)': 0xFF141414,
  'warm (#1E1C1A)': 0xFF1E1C1A,
};

void main() {
  // [LightSurfaces] 是全局可变令牌（250 处调用点直接读它）：一条用例写了用户选择
  // 后必须复位，否则会污染同进程内其它用例（尤其本文件的宽屏外壳 pump）。
  tearDown(LightSurfaces.resetUserSurface);

  group('侧栏槽派生表（预设枚举 → 槽底实测 hex）', () {
    test('浅色六档：预设页底色 → 槽底逐档比对', () {
      // 先把表里引用的输入钉在枚举真值上：枚举改色而表没改时这条先红，
      // 避免「表与枚举一起漂移但测试仍绿」。
      expect(PageSurfacePreset.iosGrouped.color, const Color(0xFFF2F2F7));
      expect(PageSurfacePreset.neutral.color, const Color(0xFFF2F2F2));
      expect(PageSurfacePreset.neutralDeep.color, const Color(0xFFEDEDED));
      expect(PageSurfacePreset.neutralBright.color, const Color(0xFFF8F8F8));
      expect(PageSurfacePreset.warmNeutral.color, const Color(0xFFF1EFEA));
      expect(PageSurfacePreset.warmPaper.color, const Color(0xFFF6F3EE));
      // custom 无预设色（值来自用户输入）⇒ 派生表只有六档。
      expect(PageSurfacePreset.custom.color, isNull);
      expect(_lightSlabTable.length, PageSurfacePreset.values.length - 1);

      for (final entry in _lightSlabTable.entries) {
        final page = entry.key.color!;
        final slab = LightSurfaces.sidebarFor(page, dark: false);
        expect(
          slab.toARGB32(),
          entry.value,
          reason:
              '${entry.key.name}: ${_hex(page)} → 期望 ${_hex(Color(entry.value))}，'
              '实测 ${_hex(slab)}',
        );
      }
    });

    test('深色档：system(#000000) 与三档预设页底色 → 槽底逐档比对', () {
      expect(DarkSurfacePreset.system.color, isNull); // system = 不覆盖
      expect(DarkSurfacePreset.neutral.color, const Color(0xFF1C1C1C));
      expect(DarkSurfacePreset.deeper.color, const Color(0xFF141414));
      expect(DarkSurfacePreset.warm.color, const Color(0xFF1E1C1A));
      expect(DarkSurfacePreset.custom.color, isNull);
      // 表里四档 = 三档有预设色 + system；custom 不参与。
      expect(_darkPageTable.length, DarkSurfacePreset.values.length - 1);

      const expected = <String, int>{
        'system (#000000)': 0xFF1B1B1B,
        'neutral (#1C1C1C)': 0xFF131313,
        'deeper (#141414)': 0xFF1F1F1F,
        'warm (#1E1C1A)': 0xFF151414,
      };
      for (final entry in expected.entries) {
        final page = Color(_darkPageTable[entry.key]!);
        final slab = LightSurfaces.sidebarFor(page, dark: true);
        expect(
          slab.toARGB32(),
          entry.value,
          reason:
              '${entry.key}: ${_hex(page)} → 期望 ${_hex(Color(entry.value))}，'
              '实测 ${_hex(slab)}',
        );
      }

      // 令牌宣称的默认深色槽 == 纯黑档的实算值（两处口径不许漂移）。
      expect(
        LightSurfaces.kDefaultDarkSidebar.toARGB32(),
        LightSurfaces.sidebarFor(const Color(0xFF000000), dark: true).toARGB32(),
      );
      expect(LightSurfaces.kDefaultDarkSidebar.toARGB32(), 0xFF1B1B1B);
      expect(
        LightSurfaces.kDefaultDarkSidebarHighContrast.toARGB32(),
        0xFF262626,
      );
    });
  });

  group('侧栏槽三个不变量', () {
    test('不变量①：深色槽对 kSidebarBrightestFill 的 ΔL* ≥ kSidebarFillGap（逐档）', () {
      final fillL = _lstar(LightSurfaces.kSidebarBrightestFill);
      expect(fillL, greaterThan(0.0)); // 度量自检：不写恒真断言

      for (final entry in _darkPageTable.entries) {
        final page = Color(entry.value);
        final slab = LightSurfaces.sidebarFor(page, dark: true);
        final gap = fillL - _lstar(slab);
        expect(
          gap,
          greaterThanOrEqualTo(LightSurfaces.kSidebarFillGap),
          reason:
              '${entry.key}: 槽 ${_hex(slab)} L*=${_lstar(slab).toStringAsFixed(3)}'
              ' 与最亮填充 ${_hex(LightSurfaces.kSidebarBrightestFill)} '
              'L*=${fillL.toStringAsFixed(3)} 只差 ΔL*=${gap.toStringAsFixed(3)}'
              '（下限 ${LightSurfaces.kSidebarFillGap}）⇒ 芯片会糊在槽里',
        );
      }
    });

    test('不变量②：浅色槽 L* 不低于 kSidebarLightFloor 的 L*（逐档）', () {
      final floorL = _lstar(LightSurfaces.kSidebarLightFloor);

      for (final entry in _lightSlabTable.entries) {
        final slab = LightSurfaces.sidebarFor(entry.key.color!, dark: false);
        final slabL = _lstar(slab);
        expect(
          slabL,
          greaterThanOrEqualTo(floorL),
          reason:
              '${entry.key.name}: 槽 ${_hex(slab)} L*=${slabL.toStringAsFixed(3)}'
              ' 低于下限 ${_hex(LightSurfaces.kSidebarLightFloor)} '
              'L*=${floorL.toStringAsFixed(3)} ⇒ 槽会读作凹陷的灰块',
        );
      }
    });

    test('不变量③：台阶绝对值 ≥ kSidebarMinStep（明暗逐档都成立）', () {
      for (final entry in _lightSlabTable.entries) {
        final page = entry.key.color!;
        final slab = LightSurfaces.sidebarFor(page, dark: false);
        final step = _lstar(slab) - _lstar(page);
        expect(
          step.abs(),
          greaterThanOrEqualTo(LightSurfaces.kSidebarMinStep),
          reason:
              '浅色 ${entry.key.name}: ${_hex(page)} → ${_hex(slab)} 台阶 '
              'ΔL*=${step.toStringAsFixed(3)} 小于下限 '
              '${LightSurfaces.kSidebarMinStep} ⇒ 槽与页底色同色',
        );
        // 浅色方向恒为下沉（槽比页底色暗）。
        expect(step, lessThan(0.0), reason: '浅色槽应比页底色暗');
      }

      for (final entry in _darkPageTable.entries) {
        final page = Color(entry.value);
        final slab = LightSurfaces.sidebarFor(page, dark: true);
        final step = _lstar(slab) - _lstar(page);
        expect(
          step.abs(),
          greaterThanOrEqualTo(LightSurfaces.kSidebarMinStep),
          reason:
              '深色 ${entry.key}: ${_hex(page)} → ${_hex(slab)} 台阶 '
              'ΔL*=${step.toStringAsFixed(3)} 小于下限 '
              '${LightSurfaces.kSidebarMinStep} ⇒ 槽与页底色同色',
        );
      }
    });

    test('不变量③补充：抬不动则反向下沉 —— 深色 neutral(#1C1C1C) 档槽比页底色更暗', () {
      const page = Color(0xFF1C1C1C);
      final slab = LightSurfaces.sidebarFor(page, dark: true);
      final pageL = _lstar(page);
      final slabL = _lstar(slab);

      // 该档页底色的 L* 距最亮填充的上限不足一个 10 台阶 ⇒ 实算走「反向下沉」。
      expect(slab.toARGB32(), 0xFF131313);
      expect(slabL, lessThan(pageL), reason: '抬不动时必须反向下沉，而不是回落到同色');
      expect(
        pageL - slabL,
        greaterThanOrEqualTo(LightSurfaces.kSidebarMinStep),
        reason:
            '下沉幅度 ${(pageL - slabL).toStringAsFixed(3)} 不足 '
            '${LightSurfaces.kSidebarMinStep}',
      );

      // warm(#1E1C1A) 同样抬不动 ⇒ 也是下沉档（两档一起守，避免只保例外之一）。
      const warmPage = Color(0xFF1E1C1A);
      final warmSlab = LightSurfaces.sidebarFor(warmPage, dark: true);
      expect(warmSlab.toARGB32(), 0xFF151414);
      expect(_lstar(warmSlab), lessThan(_lstar(warmPage)));
    });
  });

  group('自定义槽优先与复位', () {
    const customLight = Color(0xFF123456);
    const customDark = Color(0xFF654321);

    test('sidebarFollowsPage:false + 自定义槽：sidebar / darkSidebar 直接回用户值', () {
      LightSurfaces.applyUserSurface(
        light: const Color(0xFFEDEDED),
        // 深色页底色同时被覆盖：自定义槽必须压过「按深色页底色派生」。
        dark: const Color(0xFF101010),
        sidebarFollowsPage: false,
        lightSidebar: customLight,
        darkSidebar: customDark,
      );

      expect(LightSurfaces.sidebar.toARGB32(), customLight.toARGB32());
      expect(LightSurfaces.darkSidebar.toARGB32(), customDark.toARGB32());
      // 自定义深色槽是普通 Color，不再是动态色对象（与默认档语义对立）。
      expect(LightSurfaces.darkSidebar, isNot(isA<CupertinoDynamicColor>()));
      expect(LightSurfaces.hasSidebarOverride, isTrue);

      // 反证：同样这两个页底色若走派生，值不等于用户自定义值 ⇒ 上面的相等不是巧合。
      expect(
        LightSurfaces.sidebarFor(
          const Color(0xFFEDEDED),
          dark: false,
        ).toARGB32(),
        isNot(customLight.toARGB32()),
      );
      expect(
        LightSurfaces.sidebarFor(
          const Color(0xFF101010),
          dark: true,
        ).toARGB32(),
        isNot(customDark.toARGB32()),
      );
    });

    test('sidebarFollowsPage:true 且未传自定义槽：回到按页底色派生的值', () {
      LightSurfaces.applyUserSurface(
        light: const Color(0xFFEDEDED),
        sidebarFollowsPage: true,
      );

      final derived = LightSurfaces.sidebarFor(
        const Color(0xFFEDEDED),
        dark: false,
      );
      expect(LightSurfaces.sidebar.toARGB32(), derived.toARGB32());
      expect(LightSurfaces.sidebar.toARGB32(), 0xFFE1E1E1); // neutralDeep 档
      // 深色侧同步回「未覆盖页底色」的默认动态色语义。
      expect(LightSurfaces.darkSidebar, isA<CupertinoDynamicColor>());
      expect(LightSurfaces.hasSidebarOverride, isFalse);
    });

    test('已知差异（哨兵）：sidebarFollowsPage:true 时自定义槽仍优先 —— getter 不读该标志', () {
      // 实测：`sidebar` 是 `_lightSidebar ?? 派生`、`darkSidebar` 先看 `_darkSidebar`，
      // 两个 getter 都**不看** `_sidebarFollowsPage`；该字段目前只进
      // `hasSidebarOverride`。这与字段自身注释「仅在 _sidebarFollowsPage 为 false
      // 时生效」不一致（全仓暂无调用点传这三个参数，属先占接口）。
      // 本例按**实测行为**钉住，并已在交付说明里标注差异：若后续把 getter 改成
      // 跟随该标志（`sidebarFollowsPage: true` ⇒ 忽略自定义值），本用例会红，
      // 提示同期同步这处契约。
      LightSurfaces.applyUserSurface(
        light: const Color(0xFFEDEDED),
        sidebarFollowsPage: true,
        lightSidebar: customLight,
        darkSidebar: customDark,
      );

      expect(LightSurfaces.sidebar.toARGB32(), customLight.toARGB32());
      expect(LightSurfaces.darkSidebar.toARGB32(), customDark.toARGB32());
      // 派生值与自定义值不同 ⇒ 上面的相等不是「两值恰好相同」的巧合。
      expect(
        LightSurfaces.sidebarFor(
          const Color(0xFFEDEDED),
          dark: false,
        ).toARGB32(),
        0xFFE1E1E1,
      );
      expect(LightSurfaces.hasSidebarOverride, isTrue);
    });

    test('resetUserSurface：回到默认档派生值，hasSidebarOverride == false', () {
      LightSurfaces.applyUserSurface(
        light: const Color(0xFF1E1C1A),
        dark: const Color(0xFF0A0A0A),
        sidebarFollowsPage: false,
        lightSidebar: customLight,
        darkSidebar: customDark,
      );
      expect(LightSurfaces.hasSidebarOverride, isTrue);

      LightSurfaces.resetUserSurface();

      expect(
        LightSurfaces.sidebar.toARGB32(),
        LightSurfaces.sidebarFor(
          LightSurfaces.kDefaultPage,
          dark: false,
        ).toARGB32(),
      );
      expect(LightSurfaces.sidebar.toARGB32(), 0xFFE6E6E6); // 默认档 = 中性同深
      expect(LightSurfaces.hasSidebarOverride, isFalse);
      expect(LightSurfaces.hasLightOverride, isFalse);
      expect(LightSurfaces.hasDarkOverride, isFalse);
      expect(LightSurfaces.darkSidebar, isA<CupertinoDynamicColor>());
    });

    test('hasSidebarOverride 只在「跟随页底色 + 无自定义」时为 false', () {
      LightSurfaces.resetUserSurface();
      expect(LightSurfaces.hasSidebarOverride, isFalse);

      LightSurfaces.applyUserSurface(
        light: LightSurfaces.kDefaultPage,
        sidebarFollowsPage: false,
      );
      expect(LightSurfaces.hasSidebarOverride, isTrue);

      LightSurfaces.resetUserSurface();
      LightSurfaces.applyUserSurface(
        light: LightSurfaces.kDefaultPage,
        lightSidebar: customLight,
      );
      expect(LightSurfaces.hasSidebarOverride, isTrue);

      LightSurfaces.resetUserSurface();
      LightSurfaces.applyUserSurface(
        light: LightSurfaces.kDefaultPage,
        darkSidebar: customDark,
      );
      expect(LightSurfaces.hasSidebarOverride, isTrue);
    });
  });

  group('深色默认档保留动态色语义', () {
    test('未覆盖深色页底色：darkSidebar 是 CupertinoDynamicColor，普通/高对比两档到位', () {
      LightSurfaces.resetUserSurface();
      final dynamicToken = LightSurfaces.darkSidebar;

      expect(dynamicToken, isA<CupertinoDynamicColor>());
      final slot = dynamicToken as CupertinoDynamicColor;
      expect(slot.color.toARGB32(), LightSurfaces.kDefaultDarkSidebar.toARGB32());
      expect(slot.darkColor.toARGB32(), 0xFF1B1B1B);
      expect(slot.highContrastColor.toARGB32(), 0xFF1B1B1B);
      expect(slot.darkHighContrastColor.toARGB32(), 0xFF262626);
      expect(
        slot.darkHighContrastColor.toARGB32(),
        LightSurfaces.kDefaultDarkSidebarHighContrast.toARGB32(),
      );
    });

    test('applyUserSurface(dark: 某色) 后：darkSidebar 变成普通派生色', () {
      LightSurfaces.applyUserSurface(
        light: LightSurfaces.kDefaultPage,
        dark: const Color(0xFF1C1C1C),
      );
      final slab = LightSurfaces.darkSidebar;

      expect(slab, isNot(isA<CupertinoDynamicColor>()));
      expect(slab.toARGB32(), 0xFF131313);
      expect(
        slab.toARGB32(),
        LightSurfaces.sidebarFor(const Color(0xFF1C1C1C), dark: true).toARGB32(),
      );
    });
  });

  group('宽屏外壳契约（AdaptiveShell）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      enableSessionAutoRefresh = false;
    });
    tearDown(() {
      enableSessionAutoRefresh = true;
    });

    const List<LocalizationsDelegate<dynamic>> testDelegates = [
      AppLocalizationsDelegate(),
      DefaultCupertinoLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ];

    /// 与 `test/app/adaptive_shell_test.dart` 同构的外壳 pump helper（假会话 API）。
    Widget buildShellTestApp({
      required String initialLocation,
      required Size size,
    }) {
      final router = GoRouter(
        initialLocation: initialLocation,
        routes: [
          ShellRoute(
            builder: (context, state, child) =>
                AdaptiveShell(state: state, child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Text(
                  'Session List Content',
                  key: ValueKey('root-child'),
                ),
              ),
              GoRoute(
                path: '/tasks',
                builder: (context, state) =>
                    const Text('Tasks Content', key: ValueKey('tasks-child')),
              ),
            ],
          ),
        ],
      );

      return ProviderScope(
        overrides: [
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: CupertinoApp.router(
            routerConfig: router,
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
          ),
        ),
      );
    }

    testWidgets('宽屏（1280）：侧栏容器存在，槽底 ColoredBox == LightSurfaces.sidebar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 令牌固定到默认档（中性同深）——页底色控制器在 ProviderScope 里也写默认档。
      LightSurfaces.applyUserSurface(light: LightSurfaces.kDefaultPage);

      await tester.pumpWidget(
        buildShellTestApp(initialLocation: '/', size: const Size(1280, 800)),
      );
      await tester.pumpAndSettle();

      final container = find.byKey(
        const ValueKey('adaptive-shell-sidebar-container'),
      );
      expect(container, findsOneWidget);
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsOneWidget,
      );

      // 容器子树里最外层 ColoredBox 就是「槽」底（descendant 为前序遍历、
      // 最外层优先）：只断言颜色，不依赖侧栏内部结构。
      final slotBox = tester.widget<ColoredBox>(
        find.descendant(of: container, matching: find.byType(ColoredBox)).first,
      );
      final expected = LightSurfaces.sidebar;
      expect(
        slotBox.color.toARGB32(),
        expected.toARGB32(),
        reason:
            '槽底色 ${_hex(slotBox.color)} != 令牌 '
            'LightSurfaces.sidebar ${_hex(expected)}',
      );
      // 期望值本身钉死在默认档派生值上（宽屏左栏观感不许静默变）。
      expect(expected.toARGB32(), 0xFFE6E6E6);
      expect(
        expected.toARGB32(),
        LightSurfaces.sidebarFor(
          LightSurfaces.kDefaultPage,
          dark: false,
        ).toARGB32(),
      );
    });

    testWidgets('窄屏（400）：不存在侧栏容器，也没有用槽色绘制的 ColoredBox', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      LightSurfaces.applyUserSurface(light: LightSurfaces.kDefaultPage);

      await tester.pumpWidget(
        buildShellTestApp(initialLocation: '/tasks', size: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // 窄屏契约：宽屏外壳整体不存在 ⇒ 侧栏槽不参与窄屏渲染（逐像素不变）。
      expect(find.byKey(const ValueKey('tasks-child')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('adaptive-shell-sidebar-container')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('adaptive-shell-wide-layout')),
        findsNothing,
      );

      final slabArgb = LightSurfaces.sidebar.toARGB32();
      expect(slabArgb, 0xFFE6E6E6);
      final slabBoxes = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color.toARGB32() == slabArgb);
      expect(
        slabBoxes,
        isEmpty,
        reason: '窄屏出现 ${slabBoxes.length} 个使用侧栏槽色的 ColoredBox',
      );
    });
  });
}
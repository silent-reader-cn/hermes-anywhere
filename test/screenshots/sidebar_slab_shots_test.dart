import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 宽屏「侧栏槽」主题 × 场景 真渲染工装（v6 侧栏槽，2026-10-14 主人拍板）
//
// 用法（Windows + git-bash；Flutter 必须走 .bat —— f.bat / cmd //c 在此 shell
// 下不生效）：
//   SIDEBAR_SLAB_SHOTS=1 "C:/Users/Admin/flutter/bin/flutter.bat" test \
//       test/screenshots/sidebar_slab_shots_test.dart
//
// 产物：仓库根 `.shots/sidebar-slab/*.png`（相对本文件 ../../.shots/sidebar-slab，
// 该目录已被 .gitignore 排除），1400×900 @dpr 1.0（逻辑 = 物理，逐像素对得上）。
//
// 门控：只有 SIDEBAR_SLAB_SHOTS=1 才跑。不设时全部 skip（`skip: !_capture`），
// **不参与 `flutter test` 全量结果、不进金照、不影响 CI**。
//
// ★ 本工装是目检用，不是金照基线 ★
//   它在 setUpAll 里把 `autoUpdateGoldenFiles` 置真（仅门控打开时），于是
//   `matchesGoldenFile` 走「写盘 + 恒成功」分支 —— 因此**不需要**
//   `--update-goldens`，也永不因观感变化而红。它只负责把「当前代码在若干
//   主题组合下的真实渲染」落盘给主人目检，不承担像素回归职责。
//
// 一张图两份证据（图 + 数值）：
//   ① 渲染层断言（widget 树）：
//      · 侧栏槽 = 外壳宽屏分支内『adaptive-shell-sidebar-container』下第一个
//        ColoredBox 的 color（`adaptive_shell.dart` 的槽底色绘制点）；
//      · 右侧内容区底色 = 右侧真实页面的根组件底色 —— 所有功能页的根组件都是
//        `CupertinoPageScaffold`（底色默认取主题 scaffoldBackgroundColor，即
//        页底色令牌），本工装按同一口径从主题解析；
//      · 并断言两栏底色**确实不同**（G 场景是对照，刻意同色）。
//   ② 文件级像素自证：把刚落盘的 PNG 用 `dart:ui` 解码回 RGBA，量左右两栏各自
//      的**主色（众数）**，验证屏上真的是那两个色 —— 全程只用 dart:io /
//      dart:ui，**不新增任何依赖**。
//
// 右侧内容区为什么不渲染真实功能页：本工装要量的是「槽 vs 页底色」这一个台阶，
// 真实页会在右栏插入卡片 / 文字（记忆页的卡片、设置页的分组行），页底色只剩缝
// 隙，众数取样不可靠、目检也被干扰。故自建一条**测试专用路由**
// [__PageSurfaceProbe]（形态与真实页同根：CupertinoPageScaffold + 空 body），
// 右栏即整块页底色。左侧栏是**真实**的 AdaptiveShell 侧栏（品牌条 / 工具区 /
// 会话列表 / 状态条，喂真连接 + 假会话数据），槽底在真实内容之下的观感可直接目
// 检（这也是「芯片糊在槽里」那条不变量的观察面）。
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip，日常 `flutter test` 零影响。
final bool _capture = Platform.environment['SIDEBAR_SLAB_SHOTS'] == '1';
const String _skipReason = '设置 SIDEBAR_SLAB_SHOTS=1 才生成侧栏槽目检图';

/// 产物目录（相对**本测试文件所在目录** `test/screenshots/` ⇒ 仓库根
/// `.shots/sidebar-slab/`；与 `matchesGoldenFile` 的 key 语义一致）。
const String _shotRoot = '../../.shots/sidebar-slab';

/// 视口：1400×900，dpr 1.0 ⇒ 逻辑尺寸 = 物理尺寸（≥ kAdaptiveBreakpoint=900，
/// 走宽屏双栏分支；PNG 就是 1400×900，可用肉眼直接量像素）。
const Size _viewport = Size(1400, 900);

/// 测试专用路由：右侧内容区 = 整块页底色（见文件头说明）。
const String _probeLocation = '/_sidebar-slab-probe';

/// 右栏取样基准 key。
const ValueKey<String> _probeKey = ValueKey<String>('sidebar-slab-page-surface');

/// 侧栏容器 key（`adaptive_shell.dart` 宽屏分支的绘制点）。
const ValueKey<String> _sidebarKey = ValueKey<String>(
  'adaptive-shell-sidebar-container',
);

const String _demoBaseUrl = 'https://hermes.example.com:8787';
const String _demoWorkspacePath = r'D:\projects\hermes-ui';

// ---------------------------------------------------------------------------
// 场景表
// ---------------------------------------------------------------------------

/// 一个「明暗 × 页底色 × 侧栏槽档位」场景。
///
/// 前三个字段组（[lightPage] / [darkPage] / [sidebarFollowsPage] /
/// [lightSidebar] / [darkSidebar]）直接喂给 [LightSurfaces.applyUserSurface] ——
/// 即设置页真正的写入口径；[expectedSlot] / [expectedPage] 是按主人拍板值
/// **独立硬编码**的，不从 `sidebarFor()` 反推（否则断言退化成同义反复）。
@immutable
class _SlabScene {
  const _SlabScene({
    required this.file,
    required this.title,
    required this.brightness,
    required this.lightPage,
    required this.expectedSlot,
    required this.expectedPage,
    this.darkPage,
    this.sidebarFollowsPage = true,
    this.lightSidebar,
    this.darkSidebar,
    this.expectZeroDiff = false,
  });

  /// PNG 文件名（语义化：<明暗>_<页底色>_<槽档位>）。
  final String file;

  /// 用例标题（中文，跑测时可读）。
  final String title;

  final Brightness brightness;

  /// 浅色页底色（始终写入；深色场景下不参与渲染）。
  final Color lightPage;

  /// 深色页底色；null = 不覆盖（走 Cupertino 原生 system 分组背景）。
  final Color? darkPage;

  /// 槽是否跟随页底色派生（true = 「自动」档）。
  final bool sidebarFollowsPage;

  /// 「自定义」档的浅色 / 深色槽（仅 [sidebarFollowsPage] 为 false 时生效）。
  final Color? lightSidebar;
  final Color? darkSidebar;

  /// 期望的槽色（hex 硬编码）。
  final Color expectedSlot;

  /// 期望的右侧页底色（hex 硬编码；深色 system 档按 Cupertino 解析值）。
  final Color expectedPage;

  /// 对照场景（G）：槽 == 页底色，刻意零色差 —— 断言「两栏不同」要反过来。
  final bool expectZeroDiff;
}

/// 七个场景（A–G）。期望槽色出处：`docs/specs` 侧栏槽档位表 +
/// `LightSurfaces.sidebarFor` 的实测值（本文件不引用函数，硬编码常量）。
const List<_SlabScene> _scenes = <_SlabScene>[
  // A 深色 · 页底色 = system（未覆盖）· 槽 = 自动 ⇒ 槽 #1B1B1B（主人拍板那档观感）。
  _SlabScene(
    file: 'dark_system_auto.png',
    title: 'A 深色 · 页底色 system(未覆盖) · 槽 自动',
    brightness: Brightness.dark,
    lightPage: LightSurfaces.kDefaultPage,
    expectedSlot: Color(0xFF1B1B1B),
    // 未覆盖深色页底色 ⇒ CupertinoColors.systemGroupedBackground，深色解析值
    // 为 #000000（base elevation 取 darkColor）。
    expectedPage: Color(0xFF000000),
  ),
  // B 深色 · 页底色 = deeper #141414 · 槽 = 自动 ⇒ 自动档抬升 ΔL*10，但撞上
  // 「不得接近侧栏内最亮填充 #2C2C2E」的夹紧 ⇒ #1F1F1F。
  _SlabScene(
    file: 'dark_deeper_auto.png',
    title: 'B 深色 · 页底色 deeper #141414 · 槽 自动',
    brightness: Brightness.dark,
    lightPage: LightSurfaces.kDefaultPage,
    darkPage: Color(0xFF141414),
    expectedSlot: Color(0xFF1F1F1F),
    expectedPage: Color(0xFF141414),
  ),
  // C 浅色 · 页底色 = neutral #F2F2F2（默认档）· 槽 = 自动 ⇒ 下沉一档 #E6E6E6。
  _SlabScene(
    file: 'light_neutral_auto.png',
    title: 'C 浅色 · 页底色 neutral #F2F2F2 · 槽 自动',
    brightness: Brightness.light,
    lightPage: LightSurfaces.kDefaultPage,
    expectedSlot: Color(0xFFE6E6E6),
    expectedPage: Color(0xFFF2F2F2),
  ),
  // D 浅色 · 页底色 = warmPaper #F6F3EE · 槽 = 自动 ⇒ 槽跟随**色相**（暖）：
  // #EAE7E3（不是中性的 #E6E6E6）。
  _SlabScene(
    file: 'light_warmpaper_auto.png',
    title: 'D 浅色 · 页底色 warmPaper #F6F3EE · 槽 自动（暖色相跟随）',
    brightness: Brightness.light,
    lightPage: Color(0xFFF6F3EE),
    expectedSlot: Color(0xFFEAE7E3),
    expectedPage: Color(0xFFF6F3EE),
  ),
  // E 深色 · system · 槽 = 自定义 #0E0E0E（下限对照：与 #000000 页底色几乎不可辨）。
  _SlabScene(
    file: 'dark_system_custom_0E0E0E.png',
    title: 'E 深色 · 页底色 system · 槽 自定义 #0E0E0E（下限对照）',
    brightness: Brightness.dark,
    lightPage: LightSurfaces.kDefaultPage,
    sidebarFollowsPage: false,
    darkSidebar: Color(0xFF0E0E0E),
    expectedSlot: Color(0xFF0E0E0E),
    expectedPage: Color(0xFF000000),
  ),
  // F 浅色 · neutral · 槽 = 自定义 #FFFFFF（反向对照：槽比正文页底色更亮）。
  _SlabScene(
    file: 'light_neutral_custom_FFFFFF.png',
    title: 'F 浅色 · 页底色 neutral · 槽 自定义 #FFFFFF（反向对照）',
    brightness: Brightness.light,
    lightPage: LightSurfaces.kDefaultPage,
    sidebarFollowsPage: false,
    lightSidebar: Color(0xFFFFFFFF),
    expectedSlot: Color(0xFFFFFFFF),
    expectedPage: Color(0xFFF2F2F2),
  ),
  // G 对照：槽 = 页底色 #000000（模拟改造前「整窗同底」零色差，供并排目检）。
  _SlabScene(
    file: 'dark_system_slot-eq-page_noslab.png',
    title: 'G 深色 · 页底色 #000000 · 槽 = 页底色（改造前零色差对照）',
    brightness: Brightness.dark,
    lightPage: LightSurfaces.kDefaultPage,
    darkPage: Color(0xFF000000),
    sidebarFollowsPage: false,
    darkSidebar: Color(0xFF000000),
    expectedSlot: Color(0xFF000000),
    expectedPage: Color(0xFF000000),
    expectZeroDiff: true,
  ),
];

// ---------------------------------------------------------------------------
// 演示数据 / 桩
// ---------------------------------------------------------------------------

/// 右侧内容区探针：形态与真实功能页同根（`CupertinoPageScaffold` 的底色默认取
/// 主题 scaffoldBackgroundColor = 页底色令牌），body 留空使右栏成为整块页底色。
class _PageSurfaceProbe extends StatelessWidget {
  const _PageSurfaceProbe();

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      key: _probeKey,
      child: SizedBox.expand(),
    );
  }
}

/// 演示活跃连接（侧栏状态条据此渲染「已连接」而非离线态）。
Future<ConnectionStore> _demoConnectionStore() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: _demoBaseUrl,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  return store;
}

/// 侧栏会话列表数据：槽底之上的**真实内容**（相对时间由固定 mtime 派生，跨次可比）。
FakeSessionListApi _demoSessionListApi() {
  final fixed = DateTime(2026, 10, 14, 12);
  double at(Duration ago) => fixed.subtract(ago).millisecondsSinceEpoch / 1000.0;
  return FakeSessionListApi(
    sessions: [
      SessionSummary(
        sessionId: 's-slab-1',
        title: '侧栏槽令牌：ΔL* 定档与夹紧口径',
        pinned: true,
        messageCount: 23,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(minutes: 20)),
      ),
      SessionSummary(
        sessionId: 's-slab-2',
        title: '宽屏重设计：逐页现状截图与落码复验',
        messageCount: 41,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(hours: 2)),
      ),
      SessionSummary(
        sessionId: 's-slab-3',
        title: '首连宽限状态机与端口顺延复盘',
        messageCount: 8,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(hours: 5)),
      ),
      SessionSummary(
        sessionId: 's-slab-4',
        title: 'Android 实况通知图标 24px 可读性实测',
        messageCount: 17,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(days: 1, hours: 3)),
      ),
      SessionSummary(
        sessionId: 's-slab-5',
        title: '发布包瘦身：embedded python 解绑',
        messageCount: 12,
        projectId: 'p-demo-reading',
        lastMessageAt: at(const Duration(days: 2)),
      ),
      SessionSummary(
        sessionId: 's-slab-6',
        title: 'Git 变更面板 diff 折叠体验',
        messageCount: 6,
        projectId: 'p-demo-hermes',
        workspace: _demoWorkspacePath,
        lastMessageAt: at(const Duration(days: 6)),
      ),
    ],
  );
}

/// 项目 API 桩（会话行副标题要 projectId → 项目名，避免真实请求）。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async => const ProjectsResponse(
    projects: [
      ProjectSummary(projectId: 'p-demo-hermes', name: 'Hermes'),
      ProjectSummary(projectId: 'p-demo-reading', name: '读书'),
    ],
  );

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

// ---------------------------------------------------------------------------
// 工装
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    if (_capture) {
      // 只出图、不比图（见文件头 ★）：matchesGoldenFile 走「写盘 + 恒成功」
      // 分支，因而无需 `--update-goldens`。仅本 isolate、仅门控打开时生效。
      autoUpdateGoldenFiles = true;
    }
    // 真字体：否则中文渲染成方块，目检无效。
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // LightSurfaces 是**全局可变态**：场景之间必须还原，否则上一个场景的页底色 /
  // 槽档位会带进下一张图，出图与断言互相污染。
  tearDown(LightSurfaces.resetUserSurface);

  for (final scene in _scenes) {
    testWidgets('宽屏 1400 侧栏槽 · ${scene.title}', (tester) async {
      await _captureScene(tester, scene);
    }, skip: !_capture);
  }

  test('工装环境自检', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);
}

/// 渲染一个场景：宽屏全壳（真实侧栏 + 页底色探针）出图，并做「渲染层 + 像素」
/// 双重自证。
Future<void> _captureScene(WidgetTester tester, _SlabScene scene) async {
  LocaleResolver.reset(mode: AppLocaleMode.zh);

  // 令牌写入必须早于 pumpWidget：主题（buildCupertinoTheme）在 build 期读
  // LightSurfaces.page / darkPage，pump 后再写只会在下一帧生效。
  LightSurfaces.resetUserSurface();
  LightSurfaces.applyUserSurface(
    light: scene.lightPage,
    dark: scene.darkPage,
    sidebarFollowsPage: scene.sidebarFollowsPage,
    lightSidebar: scene.lightSidebar,
    darkSidebar: scene.darkSidebar,
  );

  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = await _demoConnectionStore();
  final router = GoRouter(
    initialLocation: _probeLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AdaptiveShell(state: state, child: child),
        routes: [
          GoRoute(
            path: _probeLocation,
            builder: (context, state) => const _PageSurfaceProbe(),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(ApiClient(baseUrl: _demoBaseUrl)),
        projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => _demoSessionListApi(),
        ),
        workspaceRootsProvider.overrideWith(
          (ref) => Future.value(const [
            WorkspaceRoot(path: _demoWorkspacePath, name: 'hermes-ui'),
            WorkspaceRoot(path: r'D:\projects\book-hub', name: 'book-hub'),
          ]),
        ),
        availableModelIdsProvider.overrideWith(
          (ref) => Future.value(const [
            'claude-opus-4.6',
            'gemini-3.8-flash-high',
          ]),
        ),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: buildCupertinoTheme(scene.brightness),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
      ),
    ),
  );
  // 会话 / 工作区 / 模型清单走异步 provider：多给几帧让其落地，否则侧栏停在
  // 加载态（槽色仍在，但内容不足以目检）。
  for (var i = 0; i < 3; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // ── ① 渲染层断言 ────────────────────────────────────────────────────────
  // 槽底绘制点：侧栏容器下第一个 ColoredBox（`adaptive_shell.dart` 宽屏分支）。
  // 外壳已用 LightSurfaces.resolve 解析过（深色取 darkSidebar），故这里读到的是
  // **实际绘制值**而非未解析的动态色。
  final slotColor = tester
      .widget<ColoredBox>(
        find
            .descendant(of: find.byKey(_sidebarKey), matching: find.byType(ColoredBox))
            .first,
      )
      .color;

  // 右侧页底色：真实功能页根组件（CupertinoPageScaffold）的默认底色就是主题
  // scaffoldBackgroundColor，按同一口径解析。
  final pageContext = tester.element(find.byKey(_probeKey));
  final pageColor = CupertinoDynamicColor.resolve(
    CupertinoTheme.of(pageContext).scaffoldBackgroundColor,
    pageContext,
  );

  // ── 出图（手工落盘口径见文件头：autoUpdate + matchesGoldenFile）──────────
  final key = '$_shotRoot/${scene.file}';
  await expectLater(find.byType(CupertinoApp), matchesGoldenFile(key));

  final file = _shotFile(scene.file);
  expect(file.existsSync(), isTrue, reason: 'PNG 未落盘：${file.path}');
  final bytes = file.readAsBytesSync();
  expect(bytes, isNotEmpty, reason: 'PNG 为空：${file.path}');

  // ── ② 文件级像素自证：解码刚落盘的 PNG，量两栏主色 ──────────────────────
  final shot = await _decodeShot(tester, bytes);
  expect(shot.width, _viewport.width.toInt(), reason: '图宽应为视口宽');
  expect(shot.height, _viewport.height.toInt(), reason: '图高应为视口高');

  final sidebarRect = tester.getRect(find.byKey(_sidebarKey));
  // 侧栏带：去掉最右 12px（拖拽把手 / 分界线）与上下 4px 边角。
  final slotPixel = shot.dominantArgb(
    left: 1,
    top: 4,
    right: sidebarRect.width.round() - 12,
    bottom: shot.height - 4,
  );
  // 右栏带：从侧栏右缘再退 24px 起（避开把手与分界线），到最右 4px 止。
  final pagePixel = shot.dominantArgb(
    left: sidebarRect.width.round() + 24,
    top: 4,
    right: shot.width - 4,
    bottom: shot.height - 4,
  );

  // ── 打印数值证据（debugPrint：本仓测试取证的既有口径）────────────────────
  final twoPaneDiffer = slotColor.toARGB32() != pageColor.toARGB32();
  debugPrint('[侧栏槽工装] ${scene.file}');
  debugPrint('  场景      ：${scene.title}');
  debugPrint(
    '  侧栏槽    ：渲染层 ${_hex(slotColor)}（期望 ${_hex(scene.expectedSlot)}）'
    ' · 屏上主色 ${_hexArgb(slotPixel)}',
  );
  debugPrint(
    '  右侧页底色：渲染层 ${_hex(pageColor)}（期望 ${_hex(scene.expectedPage)}）'
    ' · 屏上主色 ${_hexArgb(pagePixel)}',
  );
  debugPrint(
    '  两栏色差  ：${twoPaneDiffer ? '有（槽 != 页底色）' : '无（对照场景，刻意同色）'}',
  );

  expect(
    slotColor.toARGB32(),
    scene.expectedSlot.toARGB32(),
    reason: '侧栏槽渲染值与期望槽色不符',
  );
  expect(
    pageColor.toARGB32(),
    scene.expectedPage.toARGB32(),
    reason: '右侧页底色渲染值与期望页底色不符',
  );
  expect(
    slotPixel,
    scene.expectedSlot.toARGB32(),
    reason: '屏上侧栏主色应为槽色（PNG 像素自证）',
  );
  expect(
    pagePixel,
    scene.expectedPage.toARGB32(),
    reason: '屏上右栏主色应为页底色（PNG 像素自证）',
  );
  if (scene.expectZeroDiff) {
    expect(
      slotColor.toARGB32(),
      pageColor.toARGB32(),
      reason: '对照场景（G）刻意槽 == 页底色，用于并排目检改造前零色差',
    );
  } else {
    expect(
      twoPaneDiffer,
      isTrue,
      reason: '两栏底色必须不同 —— 槽没生效（或与页底色撞色）',
    );
  }

  await unmountHermesPage(tester);
}

/// 一张图的落盘文件。
///
/// 与 `matchesGoldenFile('$_shotRoot/${file}')` 指向**同一个文件**：`flutter test`
/// 装的默认比较器是 [LocalFileComparator]，其 [LocalFileComparator.basedir] 就是
/// 本测试文件所在目录，golden key 相对它解析。这里复用同一 basedir ⇒ 「写盘」
/// 与「读回自证」不会各指一处（读不到就直接红，不会静默假绿）。
File _shotFile(String name) {
  final comparator = goldenFileComparator;
  final Uri key = Uri.parse('$_shotRoot/$name');
  if (comparator is LocalFileComparator) {
    return File.fromUri(comparator.basedir.resolveUri(key));
  }
  // 兜底：非 LocalFileComparator（例如直连 dart test）时按 cwd 解析。
  return File.fromUri(key);
}

/// 把落盘 PNG 解码回 RGBA（`dart:ui` 自带能力，**不新增依赖**）。
Future<_DecodedShot> _decodeShot(WidgetTester tester, Uint8List png) async {
  final shot = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = Uint8List.fromList(
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final width = image.width;
    final height = image.height;
    image.dispose();
    codec.dispose();
    return _DecodedShot(width: width, height: height, rgba: rgba);
  });
  return shot!;
}

/// 解码后的位图（RGBA8）。
@immutable
class _DecodedShot {
  const _DecodedShot({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  /// 某点的 ARGB（不透明）。
  int argbAt(int x, int y) {
    final i = (y * width + x) * 4;
    return (0xFF << 24) | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }

  /// 区间内的**主色（众数）**。
  ///
  /// 步进 3 采样：区间里无可避免混入文字 / 图标 / 描边的抗锯齿像素，取众数才是
  /// 「这块区域的底色」，比「取某个坐标」稳得多。
  int dominantArgb({
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) {
    final counts = <int, int>{};
    for (var y = top; y < bottom; y += 3) {
      for (var x = left; x < right; x += 3) {
        final argb = argbAt(x, y);
        counts[argb] = (counts[argb] ?? 0) + 1;
      }
    }
    var dominant = 0;
    var best = -1;
    counts.forEach((argb, count) {
      if (count > best) {
        best = count;
        dominant = argb;
      }
    });
    return dominant;
  }
}

String _hex(Color color) => _hexArgb(color.toARGB32());

String _hexArgb(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
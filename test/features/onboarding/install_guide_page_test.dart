import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/llm_onboarding.dart';
import 'package:hermes_ui/core/install/powershell_installer.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/core/tailscale/tailscale_contract.dart';
import 'package:hermes_ui/features/onboarding/install_guide_page.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/onboarding/widgets/horizontal_step_rail.dart';
import 'package:hermes_ui/features/onboarding/widgets/network_probe.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../golden/golden_helpers.dart';
import '../../golden/golden_platform.dart';
import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 本批（2026-10-12）契约变更摘要 —— 旧断言 → 新断言的理由见各用例注释：
//   1) 步骤区从「4 步垂直列表」改成「5 步横向步骤条（R1-B）」→ 步骤名断言从
//      l10n 的 4 个 stage 名改为 rail 5 步名，且不再断言「配置模型」是独立一步；
//   2) 4 步语义（prereqs/agent/agentDeps）保留，新增「启动服务」「手机配对」；
//      进度文案 0/4 → 0/5；
//   3) 原「模型配置页」不再是独立一步，降级为「启动服务」步内的子阶段：
//      保存/跳过之后不再直接写连接进会话列表，而是进入「手机配对」步；
//      写连接 + 进会话列表的动作移到新末步的成功判据（对端已连上 → 完成）；
//   4) 新增：网络环境探测两态、Tailscale 勾选默认值、配对码与对端接入验收。
// ---------------------------------------------------------------------------

/// 假安装探测（isWindows=true 才走向导主内容）。
class _FakeInstallDetector implements InstallDetector {
  _FakeInstallDetector();

  @override
  bool isWindows = true;

  @override
  String get localAppDataPath => r'C:\Users\Admin\AppData\Local';
  @override
  String get hermesHomePath => r'C:\Users\Admin\AppData\Local\hermes';
  @override
  String get hermesAgentPath =>
      r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';
  @override
  String get webuiPath => r'C:\Users\Admin\AppData\Local\hermes\webui';

  @override
  Future<bool> agentInstalled() async => false;

  @override
  bool bundledWebuiAvailable() => false;

  @override
  Future<bool> isInstalled() async => agentInstalled();
}

/// 假 PowerShell 安装器：记录执行过的 stage，可按 stage 注入失败。
class _FakePowershellInstaller implements PowershellInstaller {
  _FakePowershellInstaller();

  Map<String, String> stageFailures = {};
  final List<String> stagesExecuted = [];

  @override
  Future<String> ensureScriptCached({
    String url = PowershellInstaller.defaultScriptUrl,
    String? destinationPath,
  }) async =>
      destinationPath ?? r'C:\Users\Admin\AppData\Local\hermes\install.ps1';

  @override
  Future<List<String>> getManifest({String? scriptPath}) async =>
      ['prereqs', 'agent', 'deps'];

  @override
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  }) async* {
    stagesExecuted.add(stageName);
    yield InstallerEvent.stageStart(stageName, title: 'Starting $stageName');
    yield InstallerEvent.log('Running step $stageName...', stage: stageName);

    if (stageFailures.containsKey(stageName)) {
      yield InstallerEvent.stageFailure(stageName, stageFailures[stageName]!);
      return;
    }

    yield InstallerEvent.stageSuccess(stageName, message: '$stageName ok');
  }
}

/// 假 LLM 配置 API（记录最后一次提交，隔离真实 HTTP）。
class _FakeLlmOnboardingApi implements LlmOnboardingApi {
  _FakeLlmOnboardingApi();

  LlmOnboardingConfig? lastConfig;

  @override
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  }) async {
    lastConfig = config;
    return true;
  }
}

/// 可注入的网络环境探测（真实现会发外网请求；单测一律注入）。
class _FakeNetworkProbe implements NetworkProbe {
  /// 当前要返回的结果（用例里直接改这个字段来切换「正常 / 受限」两态）。
  NetworkProbeResult result = const NetworkProbeResult(reachable: true);

  int calls = 0;

  @override
  Future<NetworkProbeResult> probe({
    Duration timeout = DefaultNetworkProbe.defaultTimeout,
  }) async {
    calls++;
    return result;
  }
}

/// sidecar 安全存储 fake（避免真实 flutter_secure_storage 平台通道）。
class _FakeSidecarSecureStorage implements SidecarSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

/// 假内置 WebUI 服务：start() 直接置 running（不起进程）。
class _MockWebuiSidecarService implements WebuiSidecarService {
  _MockWebuiSidecarService();

  SidecarState _state = SidecarState.initial;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();
  int startCalls = 0;

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCalls++;
    _state = const SidecarState(status: SidecarStatus.running, pid: 4321);
    _controller.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = const SidecarState(status: SidecarStatus.stopped);
    _controller.add(_state);
  }

  @override
  Future<void> restart() async => start();
}

/// 假 Tailscale 服务：按注入的状态序列回放 installAndLogin()。
class _FakeTailscaleService implements TailscaleService {
  _FakeTailscaleService({this.statuses = const <TailscaleStatus>[]});

  final List<TailscaleStatus> statuses;
  int installCalls = 0;
  int cancelCalls = 0;

  @override
  Future<TailscaleStatus> probe() async => statuses.isEmpty
      ? const TailscaleStatus(state: TailscaleState.notInstalled)
      : statuses.last;

  @override
  Stream<TailscaleStatus> installAndLogin() async* {
    installCalls++;
    for (final status in statuses) {
      yield status;
    }
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

/// 假配对服务：记录 start() 入参，测试用 [emitAccepted] 模拟手机接入。
class _FakePairingService implements PairingService, AdvertisedAddressReporting {
  /// 探活校验后「对外公布」的 host（默认给局域网地址，与既有用例的 lastBaseUrl 口径一致）；
  /// 置空串可模拟「一块可用网卡都没有」。
  @override
  String? advertisedHost = '192.168.1.7';

  @override
  bool get hasAdvertisedLanAddress =>
      advertisedHost != null && advertisedHost!.isNotEmpty;
  PairingSession? _current;
  final StreamController<PairingAccepted> _acceptedController =
      StreamController<PairingAccepted>.broadcast();

  int startCalls = 0;
  String? lastBaseUrl;
  String? lastPassword;
  String? lastInstallId;

  @override
  PairingSession? get current => _current;

  @override
  Future<PairingSession> start({
    required String baseUrl,
    required String password,
    required String installId,
    Duration ttl = const Duration(minutes: 10),
  }) async {
    startCalls++;
    lastBaseUrl = baseUrl;
    lastPassword = password;
    lastInstallId = installId;
    final session = PairingSession(
      code: '${100000 + startCalls}',
      baseUrl: baseUrl,
      password: password,
      installId: installId,
      expiresAt: DateTime.now().add(ttl),
    );
    _current = session;
    return session;
  }

  @override
  Stream<PairingAccepted> get accepted => _acceptedController.stream;

  /// 模拟手机接入。
  void emitAccepted(String deviceLabel) {
    _acceptedController.add(
      PairingAccepted(deviceLabel: deviceLabel, at: DateTime.now()),
    );
  }

  @override
  Future<void> stop() async {}
}

/// 把 CJK 字体抢先注册为 monospace 族（金照里日志台的等宽中文，见 golden_helpers
/// 的已知坑注释：flutter_tester 同族多注册「先注册者胜」）。
Future<void> _registerMonospaceCjk() async {
  final path = firstExistingFont(cjkFallbackFontCandidates);
  if (path == null) return;
  final bytes = File(path).readAsBytesSync();
  await (FontLoader('monospace')
        ..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

void main() {
  setUpAll(() async {
    await _registerMonospaceCjk();
    await loadHermesGoldenFonts();
  });

  late InMemorySecureStorage storage;
  late _FakeInstallDetector detector;
  late _FakePowershellInstaller psInstaller;
  late _FakeLlmOnboardingApi llmApi;
  late _FakeNetworkProbe networkProbe;
  late _MockWebuiSidecarService sidecarService;
  late _FakeSidecarSecureStorage sidecarSecure;

  setUp(() {
    storage = InMemorySecureStorage();
    detector = _FakeInstallDetector();
    psInstaller = _FakePowershellInstaller();
    llmApi = _FakeLlmOnboardingApi();
    networkProbe = _FakeNetworkProbe();
    sidecarService = _MockWebuiSidecarService();
    sidecarSecure = _FakeSidecarSecureStorage();
    SharedPreferences.setMockInitialValues({'app_locale_mode': 'zh'});
  });

  /// 构造测试 App。
  ///
  /// 视口故意给到 1280×2200：本批向导内容列变长（轨 + 详情卡 + 服务卡 +
  /// 模型表单 + 日志台 + 列尾按钮），900 高的窗口会让列尾按钮落在 ListView
  /// 构建范围外，tap 直接找不到目标 —— 与产品形态无关，纯测试环境问题。
  Widget buildTestApp(
    WidgetTester tester, {
    bool isWindows = true,
    bool injectTailscale = false,
    bool injectPairing = false,
    _FakeTailscaleService? tailscale,
    _FakePairingService? pairing,
  }) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(1280, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    detector.isWindows = isWindows;
    return ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: storage),
        ),
        installDetectorProvider.overrideWithValue(detector),
        powershellInstallerProvider.overrideWithValue(psInstaller),
        llmOnboardingApiProvider.overrideWithValue(llmApi),
        networkProbeProvider.overrideWithValue(networkProbe),
        webuiSidecarServiceProvider.overrideWithValue(sidecarService),
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(secureStorage: sidecarSecure),
        ),
        lanAddressProvider.overrideWith((ref) => '192.168.1.7'),
        if (injectTailscale)
          tailscaleServiceProvider.overrideWithValue(
            tailscale ?? _FakeTailscaleService(),
          ),
        if (injectPairing)
          pairingServiceProvider.overrideWithValue(
            pairing ?? _FakePairingService(),
          ),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => FakeSessionListApi(),
        ),
      ],
      child: const HermesApp(),
    );
  }

  /// 打开向导页（经 OnboardingPage 的 router 跳转）。
  Future<void> openGuide(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();
  }

  /// 推进安装循环：含「启动服务」步的 250ms 轮询，多泵几轮确保收尾。
  Future<void> settleInstall(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle();
  }

  /// 都有 spinner（CupertinoActivityIndicator 无限动画）时不能用 pumpAndSettle
  /// —— 它永远等不到「无待处理帧」。固定泵几帧即可。
  Future<void> pumpFrames(WidgetTester tester, {int times = 6}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 跑到「启动服务」步末尾的模型配置子阶段。
  Future<void> reachConfiguringModel(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
    await settleInstall(tester);
  }

  /// 一路跑到「手机配对」步。
  Future<void> reachPairing(WidgetTester tester) async {
    await reachConfiguringModel(tester);
    await tester.tap(find.byKey(const ValueKey('install-guide-skip-model-btn')));
    await pumpFrames(tester);
  }

  BoxDecoration dotDecoration(WidgetTester tester, int index) {
    final container = tester.widget<Container>(
      find.byKey(ValueKey<String>('step-rail-dot-$index')),
    );
    return container.decoration! as BoxDecoration;
  }

  // -------------------------------------------------------------------------
  // 平台分流（原用例保留）
  // -------------------------------------------------------------------------

  testWidgets('非 Windows 平台进入安装引导页 → 显示「仅支持 Windows」提示并可返回', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, isWindows: false));
    await openGuide(tester);

    expect(find.text('本机部署向导仅支持 Windows 系统'), findsOneWidget);
    expect(find.text('返回远程连接'), findsOneWidget);

    await tester.tap(find.text('返回远程连接'));
    await tester.pumpAndSettle();

    // 首启已改版为决策树（M1）：返回后落到新的首问页，而非改造前的那张地址表单。
    // 可达性结论：`/install-guide` 在本仓**只有路由声明**（lib/app/router.dart:84），
    // lib/ 里没有任何 widget 入口指向它 —— 改造前后都只能由路由直接到达，
    // 故此处只是首屏契约变更，不是入口回归。
    expect(find.text('Hermes 跑在哪台电脑上？'), findsOneWidget);
    expect(find.text('连接你的 Hermes 服务器'), findsNothing);

    // 返回后仍能两步走到旧远程表单（兜底入口可达）
    await tester.tap(
      find.byKey(const ValueKey('pairing-start-manual-address')),
    );
    await tester.pumpAndSettle();
    expect(find.text('连接你的 Hermes 服务器'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 横向步骤条（R1-B）：三态 + 当前步高亮
  // -------------------------------------------------------------------------

  testWidgets('首屏：横向轨 5 步 + 第 1 步当前（蓝底白号 + 蓝字加粗）', (tester) async {
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);

    // 5 个圆 + 5 个标签，步名照主人拍板（≤6 字短词）。
    for (var i = 0; i < 5; i++) {
      expect(
        find.byKey(ValueKey<String>('step-rail-dot-$i')),
        findsOneWidget,
      );
    }
    expect(find.text('拉取 Agent'), findsOneWidget);
    expect(find.text('安装依赖'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(find.text('手机配对'), findsOneWidget);
    // 标签行逐个按 key 取值（首屏详情卡标题也会出现「环境检查」等同名字样，
    // 用 find.text 会撞两个，故钉在 rail 标签自己的 key 上）。
    const expectedLabels = [
      '环境检查',
      '拉取 Agent',
      '安装依赖',
      '启动服务',
      '手机配对',
    ];
    for (var i = 0; i < expectedLabels.length; i++) {
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey<String>('step-rail-label-$i')))
            .data,
        expectedLabels[i],
      );
    }

    // 当前步（第 1 步）= 主色底、白字、无灰边（设计稿 .railrow .num.cur）。
    final current = dotDecoration(tester, 0);
    expect(
      current.color,
      LightSurfaces.userDetail,
      reason: '当前步圆点必须是主色 #005FB8 底（横向轨高亮）',
    );
    expect(current.border, isNull);

    // 未达步（2~5）= 无填充 + 1.5px 灰边 #C8C8CC。
    for (var i = 1; i < 5; i++) {
      final pending = dotDecoration(tester, i);
      expect(pending.color, isNull, reason: '未达步不应有填充');
      expect(pending.border!.top.width, 1.5);
    }

    // 当前步标签：加粗 + 主文字色（浅色档 = 黑，非次级灰）。
    final label = tester.widget<Text>(
      find.byKey(const ValueKey('step-rail-label-0')),
    );
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.color, isNot(LightSurfaces.textSecondary));

    // 进度文案改 0 / 5 步骤（原 0 / 4）。
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-progress-label')))
          .data,
      '进度: 0 / 5 步骤',
    );
  });

  testWidgets('首屏：详情卡 = 「环境检查」 + 检查卡 4 行（含新增「网络环境」）', (tester) async {
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-current-step-title')))
          .data,
      '环境检查',
    );
    expect(find.byKey(const ValueKey('wizard-prereq-check-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-check-windows')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-check-agent')), findsOneWidget);
    expect(find.byKey(const ValueKey('wizard-check-service')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wizard-check-network')),
      findsOneWidget,
      reason: '检查卡第 4 行「网络环境」为本批新增',
    );
  });

  testWidgets('安装推进：「启动服务」步为当前时前三步转完成态（绿底白勾）', (tester) async {
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);
    await reachConfiguringModel(tester);

    // 前 3 步（prereqs/agent/agentDeps）已完成 → 绿底 + 白勾。
    for (var i = 0; i < 3; i++) {
      final done = dotDecoration(tester, i);
      expect(done.color, isNot(isNull));
      expect(
        find.descendant(
          of: find.byKey(ValueKey<String>('step-rail-dot-$i')),
          matching: find.byIcon(CupertinoIcons.checkmark),
        ),
        findsOneWidget,
        reason: '完成步的圆点应是勾',
      );
    }
    // 第 4 步（启动服务）服务已起、但仍在等用户收尾（模型配置 → 下一步）：
    // 轨上为当前步（主色底），详情卡状态「执行中…」，进度只算前 3 步 ——
    // 主人复验要求这三处口径必须自洽（不许出现「蓝点 + 已完成」）。
    expect(dotDecoration(tester, 3).color, LightSurfaces.userDetail);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-current-step-status')))
          .data,
      '执行中…',
    );
    // 第 5 步未达。
    expect(dotDecoration(tester, 4).color, isNull);

    expect(psInstaller.stagesExecuted, ['prereqs', 'agent', 'deps']);
    expect(sidecarService.startCalls, 1, reason: '「启动服务」步必须真的拉起内置服务');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-progress-label')))
          .data,
      '进度: 3 / 5 步骤',
      reason: '第 4 步未 close 前不能报 4/5（与轨上蓝点、执行中自洽）',
    );
    // 服务本体确实在跑，由服务状态行独立表达（与步骤状态解耦）。
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-service-status-row')))
          .data,
      '服务状态',
    );
    expect(find.text('● 运行中 0.0.0.0:8787'), findsOneWidget);
    // 该行图标也须据实为绿勾（与「运行中」文一致），不能停在等待态沙漏。
    expect(
      tester
          .widget<Icon>(
            find.byKey(const ValueKey('wizard-service-status-icon')),
          )
          .icon,
      CupertinoIcons.checkmark_circle_fill,
    );
  });

  testWidgets('步骤失败：轨上失败步为红底白叉 + 错误卡片可重试', (tester) async {
    psInstaller.stageFailures = {'agent': 'Git clone failed'};
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);

    await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
    await settleInstall(tester);

    expect(dotDecoration(tester, 1).color, isNotNull, reason: '失败步应为实底红点');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('step-rail-dot-1')),
        matching: find.byIcon(CupertinoIcons.xmark),
      ),
      findsOneWidget,
    );
    expect(find.text('步骤失败: 拉取 Agent'), findsOneWidget);
    expect(find.text('Git clone failed'), findsOneWidget);

    psInstaller.stageFailures = {};
    await tester.tap(find.byKey(const ValueKey('install-guide-retry-btn')));
    await settleInstall(tester);

    // 重试后继续推进：服务步完成 → 停在模型配置子阶段。
    expect(find.text('选择模型服务商'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 网络环境（规格 C）
  // -------------------------------------------------------------------------

  testWidgets('网络正常：第 4 行为灰色「正常」，不出现受限地区提示卡', (tester) async {
    networkProbe.result = const NetworkProbeResult(reachable: true);
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);

    expect(networkProbe.calls, 1, reason: '首屏应主动探测一次');
    final value = tester.widget<Text>(
      find.byKey(const ValueKey('wizard-check-network-value')),
    );
    expect(value.data, '正常');
    expect(value.style!.color, LightSurfaces.textSecondary);
    expect(
      find.byKey(const ValueKey('wizard-network-warning-card')),
      findsNothing,
    );
  });

  testWidgets('GitHub 不可达：橙色「GitHub 不可达 · 超时 3s」+ 提示卡 + 两按钮 + 微文案', (tester) async {
    networkProbe.result = const NetworkProbeResult(
      reachable: false,
      detail: 'GitHub 不可达 · 超时 3s',
    );
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);

    final value = tester.widget<Text>(
      find.byKey(const ValueKey('wizard-check-network-value')),
    );
    expect(value.data, 'GitHub 不可达 · 超时 3s');
    expect(
      value.style!.color,
      statusOrangeText.resolveFrom(tester.element(find.byType(InstallGuidePage))),
    );

    expect(
      find.byKey(const ValueKey('wizard-network-warning-card')),
      findsOneWidget,
    );
    // 文案铁律：**渲染出来的**提示卡正文里不出现 VPN 字样，统一写「网络加速（代理）」。
    final warningFinder = find.descendant(
      of: find.byKey(const ValueKey('wizard-network-warning-card')),
      matching: find.byType(Text),
    );
    expect(warningFinder, findsOneWidget);
    final warning = tester.widget<Text>(warningFinder).data!;
    expect(
      warning,
      '在中国大陆等网络受限地区部署时，建议先开启网络加速（代理）再安装，'
      '否则「拉取 Agent」与「安装依赖」两步容易超时失败。已开启加速就点重新检测。',
    );
    expect(warning.contains('VPN'), isFalse);
    expect(warning.contains('网络加速（代理）'), isTrue);
  });

  testWidgets('受限提示：「重新检测」会再探一次并随结果收起提示卡', (tester) async {
    networkProbe.result = const NetworkProbeResult(
      reachable: false,
      detail: 'GitHub 不可达 · 超时 3s',
    );
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);
    expect(
      find.byKey(const ValueKey('wizard-network-warning-card')),
      findsOneWidget,
    );

    // 仍不可达 → 提示卡留着，探测次数 +1。
    await tester.tap(find.byKey(const ValueKey('wizard-network-recheck-btn')));
    await tester.pumpAndSettle();
    expect(networkProbe.calls, 2);
    expect(
      find.byKey(const ValueKey('wizard-network-warning-card')),
      findsOneWidget,
    );

    // 加速开好了 → 重检通过 → 提示卡收起。
    networkProbe.result = const NetworkProbeResult(reachable: true);
    await tester.tap(find.byKey(const ValueKey('wizard-network-recheck-btn')));
    await tester.pumpAndSettle();
    expect(networkProbe.calls, 3);
    expect(
      find.byKey(const ValueKey('wizard-network-warning-card')),
      findsNothing,
      reason: '重新检测通过后提示卡应消失',
    );
  });

  testWidgets('受限提示：「仍然继续」收起提示卡并直接开装（检测不挡路）', (tester) async {
    networkProbe.result = const NetworkProbeResult(
      reachable: false,
      detail: 'GitHub 不可达 · 超时 3s',
    );
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);

    await tester.tap(find.byKey(const ValueKey('wizard-network-continue-btn')));
    await settleInstall(tester);

    expect(
      find.byKey(const ValueKey('wizard-network-warning-card')),
      findsNothing,
    );
    expect(psInstaller.stagesExecuted, ['prereqs', 'agent', 'deps']);
    expect(find.text('选择模型服务商'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Tailscale 勾选（规格 B）
  // -------------------------------------------------------------------------

  test('Tailscale 勾选态默认值 = 勾选（锁死产品约定）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(tailscaleOptInProvider), isTrue);
  });

  testWidgets('「启动服务」步：Tailscale 行默认勾选（主色底 + 白勾）且文案齐全', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, injectTailscale: true));
    await openGuide(tester);
    await reachConfiguringModel(tester);

    final box = tester.widget<Container>(
      find.byKey(const ValueKey('wizard-tailscale-checkbox')),
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      LightSurfaces.userDetail,
      reason: '默认勾选：复选框应为实心主色',
    );
    expect(
      find.byKey(const ValueKey('wizard-tailscale-checkbox-mark')),
      findsOneWidget,
    );
    expect(find.text('一起安装 Tailscale（内网穿透）'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('装好后手机在任何网络都能连（4G / 公司 / 外地），不需要同一个 Wi-Fi。'), findsOneWidget);
    expect(find.text('勾选后这一步会替你下载安装并打开登录页；需要 Tailscale 账号（Google / 微软 / GitHub / Apple），官方不支持邮箱注册。'), findsOneWidget);
    expect(find.text('不勾选也能用：同一 Wi-Fi 下手机可以直接连；跨网再走「远程访问」。Tailscale 只做组网，流量端到端加密，不经过我们的服务器。'), findsOneWidget);
  });

  testWidgets('点 Tailscale 行 → 取消勾选（空底 + 1.5px 灰边），再点恢复', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, injectTailscale: true));
    await openGuide(tester);
    await reachConfiguringModel(tester);

    await tester.tap(find.byKey(const ValueKey('wizard-tailscale-row')));
    await tester.pumpAndSettle();

    final unchecked = tester.widget<Container>(
      find.byKey(const ValueKey('wizard-tailscale-checkbox')),
    );
    final decoration = unchecked.decoration! as BoxDecoration;
    expect(decoration.color, isNull);
    expect(decoration.border!.top.width, 1.5);
    expect(
      find.byKey(const ValueKey('wizard-tailscale-checkbox-mark')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('wizard-tailscale-row')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('wizard-tailscale-checkbox-mark')),
      findsOneWidget,
    );
  });

  testWidgets('勾选后安装 Tailscale：过程走横向轨并可识认；就绪态收尾不阻断向导', (tester) async {
    final tailscale = _FakeTailscaleService(
      statuses: const [
        TailscaleStatus(
          state: TailscaleState.installing,
          detail: '正在下载官方安装包',
          progress: 0.1,
        ),
        TailscaleStatus(
          state: TailscaleState.ready,
          ipv4: '100.101.87.11',
          progress: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      buildTestApp(tester, injectTailscale: true, tailscale: tailscale),
    );
    await openGuide(tester);
    await reachConfiguringModel(tester);

    expect(tailscale.installCalls, 1);
    expect(
      find.byKey(const ValueKey('wizard-tailscale-progress-card')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-tailscale-summary')))
          .data,
      '已就绪 · 100.101.87.11',
    );
    // Tailscale 失败/就绪都不阻断向导：仍停在模型配置子阶段。
    expect(find.text('选择模型服务商'), findsOneWidget);
  });

  testWidgets('未注入 Tailscale 服务：该行降级为「服务不可用」提示，启动服务步仍成功', (tester) async {
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);
    await reachConfiguringModel(tester);

    expect(
      find.byKey(const ValueKey('wizard-tailscale-unavailable')),
      findsOneWidget,
    );
    // 行内提示 + 日志台里同一句话（日志是可复制的安装记录，不去重）。
    expect(find.text('Tailscale 服务不可用，已跳过内网穿透安装。'), findsWidgets);
    expect(find.byKey(const ValueKey('wizard-tailscale-checkbox')), findsNothing);
    // 不崩：服务步照常算完成。
    expect(dotDecoration(tester, 3).color, LightSurfaces.userDetail);
    expect(find.text('选择模型服务商'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 手机配对（规格 D）
  // -------------------------------------------------------------------------

  testWidgets('末步出 6 位配对码：6 格码面 + 等待文案 + 重新生成会再要一次码', (tester) async {
    final pairing = _FakePairingService();
    await tester.pumpWidget(
      buildTestApp(tester, injectPairing: true, pairing: pairing),
    );
    await openGuide(tester);
    await reachPairing(tester);

    expect(pairing.startCalls, 1);
    expect(pairing.lastBaseUrl, 'http://192.168.1.7:8787');
    expect(pairing.lastInstallId, isNotEmpty);

    final code = pairing.current!.code;
    expect(code.length, 6);
    for (var i = 0; i < 6; i++) {
      expect(
        find.byKey(ValueKey<String>('wizard-pairing-digit-$i')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey<String>('wizard-pairing-digit-$i')),
          matching: find.text(code[i]),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('等待手机接入…'), findsOneWidget);
    expect(find.text('打开手机上的 Hermes → 连接服务器，会自动发现这台电脑'), findsOneWidget);
    expect(find.text('配对码 10 分钟内有效，配对成功后立即失效'), findsOneWidget);

    // 口径自洽：第 4 步已 close（绿勾）、第 5 步为当前（蓝）、进度 4/5、
    // 详情卡是「手机配对 / 等待中」。
    expect(dotDecoration(tester, 3).color, isNotNull);
    expect(dotDecoration(tester, 4).color, LightSurfaces.userDetail);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-current-step-title')))
          .data,
      '手机配对',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-current-step-status')))
          .data,
      '等待中',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-progress-label')))
          .data,
      '进度: 4 / 5 步骤',
    );

    // 重新生成 → 再要一次码，码面跟着变。
    await tester.tap(
      find.byKey(const ValueKey('wizard-pairing-regenerate-btn')),
    );
    await pumpFrames(tester);
    expect(pairing.startCalls, 2);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('wizard-pairing-digit-0')),
        matching: find.text(pairing.current!.code[0]),
      ),
      findsOneWidget,
    );
  });

  testWidgets('成功判据 = 对端已连上：收到 PairingAccepted → 验收态 + 完成写入连接', (tester) async {
    final pairing = _FakePairingService();
    await tester.pumpWidget(
      buildTestApp(tester, injectPairing: true, pairing: pairing),
    );
    await openGuide(tester);
    await reachPairing(tester);

    // 手机还没接入 → 仍是等待态。
    expect(find.text('等待手机接入…'), findsOneWidget);

    pairing.emitAccepted('iPhone 15 Pro');
    await tester.pumpAndSettle();

    expect(find.text('手机已连上'), findsOneWidget);
    expect(find.text('iPhone 15 Pro'), findsOneWidget);
    expect(find.text('刚刚配对'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wizard-pairing-finish-btn')),
      findsOneWidget,
    );
    // 对端接入 = 第 5 步完成 → 全轨绿。
    for (var i = 0; i < 5; i++) {
      expect(dotDecoration(tester, i).color, isNotNull);
    }
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-progress-label')))
          .data,
      '进度: 5 / 5 步骤',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('wizard-current-step-status')))
          .data,
      '已完成',
    );

    await tester.tap(find.byKey(const ValueKey('wizard-pairing-finish-btn')));
    await tester.pumpAndSettle();

    final activeId = storage.data[ConnectionStore.activeConnectionKey];
    expect(activeId, isNotNull);
    expect(find.text('暂无会话'), findsOneWidget);
  });

  testWidgets('未注入配对服务：显示「配对服务不可用」并可跳过（不崩）', (tester) async {
    await tester.pumpWidget(buildTestApp(tester));
    await openGuide(tester);
    await reachPairing(tester);

    expect(
      find.byKey(const ValueKey('wizard-pairing-unavailable')),
      findsOneWidget,
    );
    expect(find.text('当前构建没有注入配对服务。可以跳过这一步，稍后在「设置 → 连接」里用配对码接入。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wizard-pairing-skip-btn')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('wizard-pairing-skip-btn')));
    await tester.pumpAndSettle();

    final activeId = storage.data[ConnectionStore.activeConnectionKey];
    expect(activeId, isNotNull);
    expect(find.text('暂无会话'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 模型配置子阶段（原「配置模型一步」的用例同步改造）
  // -------------------------------------------------------------------------

  testWidgets('模型配置：未填 API Key 校验提示；填入并保存 → 进入手机配对步', (tester) async {
    final pairing = _FakePairingService();
    await tester.pumpWidget(
      buildTestApp(tester, injectPairing: true, pairing: pairing),
    );
    await openGuide(tester);
    await reachConfiguringModel(tester);

    // 默认选 OpenRouter 需要 API Key。
    await tester.tap(find.byKey(const ValueKey('install-guide-save-model-btn')));
    await tester.pumpAndSettle();

    expect(find.text('❌ 该服务商需要填写 API Key'), findsOneWidget);
    expect(llmApi.lastConfig, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('install-guide-apikey-input')),
      'sk-or-v1-my-key',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('install-guide-save-model-btn')));
    await pumpFrames(tester);

    expect(llmApi.lastConfig?.provider, 'openrouter');
    expect(llmApi.lastConfig?.apiKey, 'sk-or-v1-my-key');
    // 新契约：保存后不再直接进会话列表，而是进入配对步。
    expect(pairing.startCalls, 1);
    expect(find.text('等待手机接入…'), findsOneWidget);
    expect(storage.data[ConnectionStore.activeConnectionKey], isNull);
  });

  testWidgets('模型配置：点「暂不配置，稍后设置」→ 不提交配置，进入手机配对步', (tester) async {
    final pairing = _FakePairingService();
    await tester.pumpWidget(
      buildTestApp(tester, injectPairing: true, pairing: pairing),
    );
    await openGuide(tester);
    await reachPairing(tester);

    expect(llmApi.lastConfig, isNull);
    expect(pairing.startCalls, 1);
    expect(find.text('等待手机接入…'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // 组件级判据（不需要整页）
  // -------------------------------------------------------------------------

  group('横向步骤条三态判据', () {
    test('完成 / 当前 / 未达 / 失败', () {
      expect(
        HorizontalStepRail.resolveDotState(0, currentIndex: 2, doneCount: 2),
        StepRailDotState.done,
      );
      expect(
        HorizontalStepRail.resolveDotState(2, currentIndex: 2, doneCount: 2),
        StepRailDotState.current,
      );
      expect(
        HorizontalStepRail.resolveDotState(4, currentIndex: 2, doneCount: 2),
        StepRailDotState.pending,
      );
      expect(
        HorizontalStepRail.resolveDotState(
          1,
          currentIndex: 2,
          doneCount: 2,
          failedIndex: 1,
        ),
        StepRailDotState.failed,
      );
      // 缺省 doneCount = currentIndex（常规：当前步之前都已完成）。
      expect(
        HorizontalStepRail.resolveDotState(1, currentIndex: 2),
        StepRailDotState.done,
      );
    });
  });

  group('网络探测模块', () {
    test('isPrivateIpv4：只认 RFC1918 私有段与 CGNAT', () {
      expect(isPrivateIpv4('192.168.1.7'), isTrue);
      expect(isPrivateIpv4('10.0.0.5'), isTrue);
      expect(isPrivateIpv4('172.16.0.1'), isTrue);
      expect(isPrivateIpv4('172.31.255.254'), isTrue);
      expect(isPrivateIpv4('172.32.0.1'), isFalse);
      expect(isPrivateIpv4('100.101.87.11'), isTrue, reason: 'CGNAT 段');
      expect(isPrivateIpv4('127.0.0.1'), isFalse);
      expect(isPrivateIpv4('8.8.8.8'), isFalse);
      expect(isPrivateIpv4('nonsense'), isFalse);
    });

    testWidgets('默认探测实现在 flutter_test 环境下可推进（金照工装依赖此行为）', (tester) async {
      // flutter_test 的 binding 会安装 HttpOverrides，把 HttpClient 换成一律返回
      // 400 的 mock —— 本项目「拿到任何 HTTP 响应即算可达」，故默认实现必然给出
      // 可达；这条同时锁住 train goldens 的可复现性（install_guide 金照用的是
      // 默认探测实现，若哪天 SDK 不再 mock，这里先红而不是金照先漂）。
      // 注意：fake async 下不能直接 await（超时定时器不会走），必须 unawaited +
      // pump —— 这正是本批临时探针验证到的做法，故固化在此。
      NetworkProbeResult? result;
      unawaited(
        const DefaultNetworkProbe().probe().then((r) => result = r),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNotNull, reason: '默认探测应能在测试环境下完成');
      expect(result!.reachable, isTrue);
    });

    testWidgets('局域网地址探测不抛不挂（真 IO 走 runAsync；取不到就交空串降级）', (tester) async {
      // NetworkInterface.list 是真实 dart:io IO，fake async 下不会推进，
      // 必须用 runAsync 放到真实事件循环里跑（这也是它能在生产里「取不到就
      // 返回空串、由调用方降级」的前提：绝不抛、绝不挂）。
      final addresses = await tester.runAsync(probeLanAddresses);

      expect(addresses, isNotNull);
      for (final address in addresses!) {
        expect(isPrivateIpv4(address), isTrue);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 本批新增两态的视觉基线
  //
  // 为什么这两张金照写在本文件、而不是 test/golden/：本批允许改动的测试只有
  // test/features/onboarding/**（任务书边界），但主人明确要求「人眼查勾选项
  // 是否默认勾上、橙卡文案是否完整、无溢出」——首屏 idle 金照里看不到这两态，
  // 故就地补两张。基线仍按仓规落到 test/golden/goldens/<平台>/（走 goldenKey），
  // 其它平台无基线时自动跳过（skipIfNoGoldenBaseline），不产生跨平台假红。
  // ---------------------------------------------------------------------------
  group('金照（本批新增两态）', () {
    /// 基线 key：金照路径按仓规落在 test/golden/goldens/<平台>/，但
    /// matchesGoldenFile 是**相对测试文件目录**解析的（既有金照文件在
    /// test/golden/ 下，故那边写 'goldens/...' 就够）——本文件在
    /// test/features/onboarding/，必须自己回到仓根那份。
    String canonicalGoldenKey(String name) =>
        '../../golden/goldens/$goldenPlatformKey/$name.png';

    List<Override> goldenOverrides({
      required _FakeNetworkProbe probe,
      _FakeTailscaleService? tailscale,
    }) =>
        [
          installDetectorProvider.overrideWithValue(_FakeInstallDetector()),
          powershellInstallerProvider.overrideWithValue(
            _FakePowershellInstaller(),
          ),
          llmOnboardingApiProvider.overrideWithValue(_FakeLlmOnboardingApi()),
          webuiSidecarServiceProvider.overrideWithValue(
            _MockWebuiSidecarService(),
          ),
          webuiSidecarConfigStorageProvider.overrideWithValue(
            WebuiSidecarConfigStorage(secureStorage: _FakeSidecarSecureStorage()),
          ),
          networkProbeProvider.overrideWithValue(probe),
          lanAddressProvider.overrideWith((ref) => '192.168.1.7'),
          if (tailscale != null)
            tailscaleServiceProvider.overrideWithValue(tailscale),
        ];

    for (final brightness in Brightness.values) {
      final themeName = brightness == Brightness.light ? 'light' : 'dark';

      testWidgets('install_guide_tailscale_step wide $themeName', (tester) async {
        final name = 'install_guide_tailscale_step_$themeName';
        if (skipIfNoGoldenBaseline(name)) return;
        await pumpHermesPage(
          tester,
          page: const InstallGuidePage(),
          brightness: brightness,
          size: goldenLandscapeSize,
          overrides: goldenOverrides(
            probe: _FakeNetworkProbe(),
            tailscale: _FakeTailscaleService(
              statuses: const [
                TailscaleStatus(
                  state: TailscaleState.installing,
                  detail: '正在静默安装：msiexec /qn',
                  progress: 0.5,
                ),
              ],
            ),
          ),
        );
        // 推到「启动服务」步（勾选行 + Tailscale 三态轨都在这一步）。
        // 列尾按钮在 1280×800 窗口下落在 ListView 构建范围外，故交互期临时把
        // 视口加高（内容仍在 offset 0，不产生滚动位），截图前恢复标准档。
        tester.view.physicalSize = const Size(2560, 4000);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
        // 不能用 settleInstall（其收尾 pumpAndSettle 会被品牌区 12s 呼吸循环
        // 拖超时）——固定帧数泵到安装收尾，与既有金照工装同款做法。
        await pumpFrames(tester, times: 16);
        tester.view.physicalSize = goldenLandscapeSize;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
        await expectLater(
          find.byType(CupertinoApp),
          matchesGoldenFile(canonicalGoldenKey(name)),
        );
        await unmountHermesPage(tester);
      });

      testWidgets('install_guide_network_warning wide $themeName', (tester) async {
        final name = 'install_guide_network_warning_$themeName';
        if (skipIfNoGoldenBaseline(name)) return;
        await pumpHermesPage(
          tester,
          page: const InstallGuidePage(),
          brightness: brightness,
          size: goldenLandscapeSize,
          overrides: goldenOverrides(
            probe: _FakeNetworkProbe()
              ..result = const NetworkProbeResult(
                reachable: false,
                detail: 'GitHub 不可达 · 超时 3s',
              ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 900));
        await expectLater(
          find.byType(CupertinoApp),
          matchesGoldenFile(canonicalGoldenKey(name)),
        );
        await unmountHermesPage(tester);
      });
    }
  });

  testWidgets('配对地址显示的是**探活校验过的 host**，不是向导自己猜的', (tester) async {
    final pairing = _FakePairingService()..advertisedHost = '10.20.30.40';
    await tester.pumpWidget(
      buildTestApp(tester, injectPairing: true, pairing: pairing),
    );
    await openGuide(tester);
    await reachPairing(tester);

    // 向导自己算出来的 baseUrl 是 192.168.1.7（见「末步出 6 位配对码」用例的 lastBaseUrl）；
    // 显示的必须是服务端探活校验过的那个 host，否则就是把「连不上」当「已就绪」展示。
    expect(
      find.byKey(const ValueKey('wizard-pairing-address')),
      findsOneWidget,
    );
    expect(find.textContaining('10.20.30.40'), findsOneWidget);
    expect(find.textContaining('192.168.1.7'), findsNothing);
  });

  testWidgets('没有可用局域网地址 → 明确告警卡 + 不显示地址行（不再静默 / 死地址）', (tester) async {
    final pairing = _FakePairingService()..advertisedHost = '';
    await tester.pumpWidget(
      buildTestApp(tester, injectPairing: true, pairing: pairing),
    );
    await openGuide(tester);
    await reachPairing(tester);

    expect(
      find.byKey(const ValueKey('wizard-no-lan-address-card')),
      findsOneWidget,
    );
    expect(find.textContaining('没找到手机能连上的局域网地址'), findsOneWidget);
    // 不显示地址行（日志台里出现的 127.0.0.1 是诊断日志，不是公布地址，故按 key 断言）
    expect(
      find.byKey(const ValueKey('wizard-pairing-address')),
      findsNothing,
    );
    // 码照常出（本机仍可自测 / 手输），只是不再公布死地址。
    for (var i = 0; i < 6; i++) {
      expect(
        find.byKey(ValueKey<String>('wizard-pairing-digit-$i')),
        findsOneWidget,
      );
    }
  });
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/nav_bar_hairline.dart';
import '../../core/install/install_detector.dart';
import '../../core/install/llm_onboarding.dart';
import '../../core/install/powershell_installer.dart';
import '../../core/pairing/pairing_contract.dart';
import '../../core/tailscale/tailscale_contract.dart';
import '../../l10n/app_localizations.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'builtin_service_connect.dart';
import 'widgets/horizontal_step_rail.dart';
import 'widgets/network_probe.dart';
import 'widgets/onboarding_field_style.dart';
import 'widgets/wide_dual_pane.dart';

/// 安装步骤定义（横向步骤条 5 步）。
///
/// 前 3 步保留原有语义与后端 stage 名（`prereqs` / `agent` / `deps`），
/// 「启动服务」「手机配对」为本批新增；原「配置模型」不再是独立一步 ——
/// 它降级成「启动服务」步里的子阶段（服务起来后顺手配），因为主人 2026-10-12
/// 拍板的 5 步轨是「让手机连上」这条主线（设计稿 §5 R1-B）。
enum InstallStageKey { prereqs, agent, agentDeps, service, pairing }

/// 步骤执行状态。
enum StageStatus { pending, running, success, failed }

/// 引导页整体运行阶段。
enum GuidePhase {
  idle,
  installing,
  failed,
  configuringModel,
  pairing,
  done,
}

/// 「一起安装 Tailscale」勾选态（**默认勾选**）。
///
/// 为什么做成 provider 而不只是页面 State：勾选值要被后续步骤（配对屏选地址）
/// 与测试读到；「默认勾选」是产品约定，必须有断言锁住，不能只靠肉眼看。
class TailscaleOptIn extends Notifier<bool> {
  @override
  bool build() => true;

  /// 切换勾选。
  void toggle() => state = !state;
}

/// 见 [TailscaleOptIn]。
final tailscaleOptInProvider = NotifierProvider<TailscaleOptIn, bool>(
  TailscaleOptIn.new,
);

/// Windows 本机一键安装部署引导页。
///
/// 本批（2026-10-12）改造：4 步垂直列表 → 5 步横向步骤条；「启动服务」步加
/// Tailscale 勾选（默认勾选）；首屏检查卡加「网络环境」行与受限地区提示；
/// 末步从「装完即完成」改成「对端已连上」才算成功。
class InstallGuidePage extends ConsumerStatefulWidget {
  /// 构造向导页。
  const InstallGuidePage({super.key});

  @override
  ConsumerState<InstallGuidePage> createState() => _InstallGuidePageState();
}

class _InstallGuidePageState extends ConsumerState<InstallGuidePage> {
  GuidePhase _phase = GuidePhase.idle;
  String _failureReason = '';
  InstallStageKey? _failedStage;
  final Map<InstallStageKey, StageStatus> _stageStatuses = {
    for (final k in InstallStageKey.values) k: StageStatus.pending,
  };
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  bool _showLogs = true;

  /// 官方 install.ps1 的 stage 名单（懒加载 + 缓存，见 [_resolveStageManifest]）。
  List<String>? _stageManifest;

  // ── 网络环境探测（首屏检查卡第 4 行） ─────────────────────────────────
  bool _networkReachable = false;
  bool _networkChecking = true;
  String _networkDetail = '';
  // 「仍然继续」后收起橙色提示卡（检测只影响速度，不该挡路）。
  bool _networkAcknowledged = false;

  // ── 启动服务步 ────────────────────────────────────────────────────────
  bool _lanEnabled = false;
  String _serviceAddress = '';
  String _serviceFailureReason = '';

  // ── Tailscale（勾选后的安装过程） ─────────────────────────────────────
  TailscaleStatus? _tailscaleStatus;
  bool _tailscaleUnavailable = false;
  TailscaleService? _tailscaleService;

  // ── 手机配对步 ────────────────────────────────────────────────────────
  PairingSession? _pairingSession;
  PairingAccepted? _accepted;
  bool _pairingUnavailable = false;
  String _pairingError = '';
  String _pairingAddress = '';
  StreamSubscription<PairingAccepted>? _pairingSub;

  // ── 模型配置表单（「启动服务」步内的子阶段） ───────────────────────────
  LlmProviderOption _selectedProvider =
      LlmProviderOption.builtinProviders.first;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  bool _savingModel = false;
  String? _modelFormError;

  // ── 末步收尾（写内置连接 → 进会话列表） ───────────────────────────────
  /// 收尾进行中（防重入 + 按钮转圈）。
  bool _finishing = false;
  /// 收尾失败原因（行内红字，可重试；不静默吞错）。
  String _finishError = '';

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _baseUrlController = TextEditingController(
      text: _selectedProvider.defaultBaseUrl,
    );
    _modelController = TextEditingController(
      text: _selectedProvider.defaultModel,
    );
    unawaited(_probeNetwork());
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    final pairingSub = _pairingSub;
    if (pairingSub != null) unawaited(pairingSub.cancel());
    final tailscale = _tailscaleService;
    if (tailscale != null) unawaited(tailscale.cancel());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 步骤轨的派生态
  // ---------------------------------------------------------------------------

  /// 已完成（success）的步数。
  int get _completedCount =>
      _stageStatuses.values.where((s) => s == StageStatus.success).length;

  /// 第一个未完成的步下标（idle / installing / failed 时的当前步）。
  int get _firstUnfinishedIndex {
    final values = InstallStageKey.values;
    for (var i = 0; i < values.length; i++) {
      if (_stageStatuses[values[i]] != StageStatus.success) return i;
    }
    return values.length - 1;
  }

  /// 当前步下标。
  ///
  /// 注意 [GuidePhase.configuringModel]：服务已起、模型表单还挂在这一步里等用户
  /// 点「下一步」，故当前步仍是「启动服务」，不能滑到配对步。
  int get _currentStepIndex {
    switch (_phase) {
      case GuidePhase.idle:
      case GuidePhase.installing:
      case GuidePhase.failed:
        return _firstUnfinishedIndex;
      case GuidePhase.configuringModel:
        return InstallStageKey.values.indexOf(InstallStageKey.service);
      case GuidePhase.pairing:
      case GuidePhase.done:
        return InstallStageKey.values.indexOf(InstallStageKey.pairing);
    }
  }

  /// 失败步下标（没有失败步时为 null）。
  int? get _failedStageIndex {
    final stage = _failedStage;
    if (stage == null) return null;
    return InstallStageKey.values.indexOf(stage);
  }

  String _stepTitle(AppLocalizations l10n, InstallStageKey stage) {
    switch (stage) {
      case InstallStageKey.prereqs:
        return l10n.installGuideStagePrereqs;
      case InstallStageKey.agent:
        return l10n.installGuideStageAgent;
      case InstallStageKey.agentDeps:
        return l10n.installGuideStageDeps;
      case InstallStageKey.service:
        return l10n.installWizardStepService;
      case InstallStageKey.pairing:
        // 对端已连上后，这一步的名字改成验收态标题（设计稿 D5）。
        return _accepted != null
            ? l10n.installWizardPairedTitle
            : l10n.installWizardStepPairing;
    }
  }

  /// 当前 locale 的文案包。
  ///
  /// 与直接 `AppLocalizations.of(context)` 的区别：安装/配对是长跑的异步链，用户
  /// 中途离开页面后仍可能走到 `_appendLog`／`_failureReason` 赋值 —— 那一刻对已
  /// defunct 的 element 做 inherited 查找会抛断言。这里未挂载时退回中文包，只为
  /// 保证「取文案」这一步不炸（日志本身仍由 [_appendLog] 按 mounted 丢弃）。
  AppLocalizations _l10n() {
    if (!mounted) return const AppLocalizations(Locale('zh'));
    return AppLocalizations.of(context);
  }

  /// 返回键：能退栈就退栈，退不回才回引导页。
  ///
  /// 为什么不能一律 `go('/onboarding')`：向导有两个入口 ——
  /// ① 引导页内置 Tab 的「进入安装向导」（`push` 进来，栈里有引导页）；
  /// ② 设置页「缺 agent」弹窗的「前往安装向导」（`push` 进来，栈里有设置页）。
  /// 一律 `go('/onboarding')` 会把 ② 的用户从设置页**弹到引导页** ——
  /// 设置页通常正连着远程（hasActive=true），而引导页在有活跃连接时会被
  /// `router.dart` 的守卫直接弹回主页 ⇒ 用户「进去→被弹回→像坏了」。
  ///
  /// 故：**有栈就 pop（回到来处），没栈才 go 引导页**（向导是顶层路由，
  /// 直接深链进来时栈里只有它自己）。
  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/onboarding');
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _logs.add(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 网络环境探测
  // ---------------------------------------------------------------------------

  Future<void> _probeNetwork() async {
    final NetworkProbe probe;
    try {
      probe = ref.read(networkProbeProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _networkChecking = false;
          _networkReachable = false;
          _networkDetail =
              AppLocalizations.of(context).installWizardNetworkFailed;
        });
      }
      return;
    }
    try {
      final result = await probe.probe(
        timeout: DefaultNetworkProbe.defaultTimeout,
      );
      if (!mounted) return;
      setState(() {
        _networkChecking = false;
        _networkReachable = result.reachable;
        _networkDetail = result.detail;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _networkChecking = false;
        _networkReachable = false;
        _networkDetail =
            AppLocalizations.of(context).installWizardNetworkFailed;
      });
    }
  }

  void _recheckNetwork() {
    setState(() {
      _networkChecking = true;
      _networkDetail = '';
    });
    unawaited(_probeNetwork());
  }

  /// 「仍然继续」：收起橙色提示卡并直接开装（检测只影响速度，不挡路）。
  void _continueDespiteNetwork() {
    setState(() => _networkAcknowledged = true);
    unawaited(_startOrResumeInstallation());
  }

  /// 是否展示受限地区提示卡。
  bool get _showNetworkWarning =>
      !_networkChecking && !_networkReachable && !_networkAcknowledged;

  // ---------------------------------------------------------------------------
  // 安装流程调度
  // ---------------------------------------------------------------------------

  Future<void> _startOrResumeInstallation([InstallStageKey? fromStage]) async {
    setState(() {
      _phase = GuidePhase.installing;
      _failureReason = '';
      _failedStage = null;
    });
    // 只跑「安装类」四步；配对步由「启动服务」步收尾时的用户动作触发。
    const installStages = [
      InstallStageKey.prereqs,
      InstallStageKey.agent,
      InstallStageKey.agentDeps,
      InstallStageKey.service,
    ];
    final rawIndex = fromStage != null ? installStages.indexOf(fromStage) : 0;
    final startIndex = rawIndex < 0 ? 0 : rawIndex;
    for (var i = startIndex; i < installStages.length; i++) {
      final stage = installStages[i];
      setState(() {
        _stageStatuses[stage] = StageStatus.running;
      });
      final success = await _executeStage(stage);
      if (!success) {
        setState(() {
          _phase = GuidePhase.failed;
          _stageStatuses[stage] = StageStatus.failed;
          _failedStage = stage;
        });
        return;
      }
      if (stage == InstallStageKey.service) {
        // 「启动服务」步的收尾挂在用户动作上（模型配置 → 下一步：配对），故这里
        // **不落 success**、保持 running：于是轨上该点是蓝（当前步）、详情卡右上
        // 是「执行中…」、进度只算前 3 步 —— 三处口径自洽（主人 2026-10-12 复验
        // 指出「蓝点 + 已完成」自相矛盾）。用户点保存/暂不配置时才 close 这一步
        // 并推进到「手机配对」。服务本身是否在跑，另由服务状态行独立表达。
        setState(() => _phase = GuidePhase.configuringModel);
        return;
      }
      setState(() {
        _stageStatuses[stage] = StageStatus.success;
      });
    }
    setState(() {
      _phase = GuidePhase.configuringModel;
    });
  }

  Future<bool> _executeStage(InstallStageKey stage) async {
    final psInstaller = ref.read(powershellInstallerProvider);
    final l10n = _l10n();
    try {
      switch (stage) {
        case InstallStageKey.prereqs:
          _appendLog(l10n.installWizardLogPrereqs);
          await psInstaller.ensureScriptCached();
          return await _runStageGroup(
            InstallStepGroup.prerequisites,
            l10n.installWizardFailPrereqs,
          );
        case InstallStageKey.agent:
          _appendLog(l10n.installWizardLogAgent);
          return await _runStageGroup(
            InstallStepGroup.repository,
            l10n.installWizardFailAgent,
          );
        case InstallStageKey.agentDeps:
          _appendLog(l10n.installWizardLogDeps);
          return await _runStageGroup(
            InstallStepGroup.dependencies,
            l10n.installWizardFailAgentDeps,
          );
        case InstallStageKey.service:
          return await _executeServiceStage();
        case InstallStageKey.pairing:
          // 不走自动循环（见 _startOrResumeInstallation）。
          return true;
      }
    } catch (e) {
      _failureReason = '$e';
      _appendLog(l10n.installWizardLogStepError('$e'));
      return false;
    }
  }

  void _handleInstallerEvent(InstallerEvent event) {
    if (event.type == InstallerEventType.stageFailure) {
      // 失败帧的原文是一条 JSON 机器帧（`{"ok":false,"stage":...}`），日志台给
      // 人看的是 reason；只打原文会让人看到一堆转义符号还得自己猜（主人 2026-10-25
      // 截图里的 `unknown stage: prereqs` 就是这么冒出来的）。
      _appendLog('[${event.stage ?? 'info'}] ${event.reason ?? event.raw}');
      return;
    }
    if (event.message != null && event.message!.isNotEmpty) {
      _appendLog('[${event.stage ?? 'info'}] ${event.message}');
    } else if (event.raw.isNotEmpty) {
      _appendLog(event.raw);
    }
  }

  /// 跑完一个抽象步对应的全部官方 stage（名字链来自 `-Manifest`）。
  ///
  /// 为什么一步可能跑多个 stage：官方 2026-10 把「装依赖」拆成
  /// `venv → python-deps → config → products → complete` 五个独立 stage，每个
  /// 是一次独立 PowerShell 进程；顺序不能乱（venv 必须先于 python-deps，
  /// products/complete 收尾）。
  Future<bool> _runStageGroup(
    InstallStepGroup group,
    String fallbackReason,
  ) async {
    final psInstaller = ref.read(powershellInstallerProvider);
    final l10n = _l10n();
    final chain = resolveInstallStageChain(group, await _resolveStageManifest());
    for (var i = 0; i < chain.length; i++) {
      final stageName = chain[i];
      if (chain.length > 1) {
        _appendLog(
          l10n.installWizardLogStageProgress(i + 1, chain.length, stageName),
        );
      }
      var failed = false;
      await for (final event in psInstaller.runStage(stageName)) {
        _handleInstallerEvent(event);
        if (event.type == InstallerEventType.stageFailure) {
          _failureReason = event.reason ?? fallbackReason;
          failed = true;
          break;
        }
      }
      if (failed) return false;
    }
    return true;
  }

  /// 取官方脚本的 stage 名单（一次向导只取一次：每次 `-Manifest` 都要起一个
  /// PowerShell 进程，约 1~2s）。取不到就返回空表，由
  /// [resolveInstallStageChain] 退回首项候选。
  Future<List<String>> _resolveStageManifest() async {
    final cached = _stageManifest;
    if (cached != null) return cached;
    List<String> manifest;
    try {
      manifest = await ref.read(powershellInstallerProvider).getManifest();
    } catch (_) {
      manifest = const <String>[];
    }
    _stageManifest = manifest;
    return manifest;
  }

  // ---------------------------------------------------------------------------
  // 「启动服务」步：拉起内置服务 + 可选 Tailscale
  // ---------------------------------------------------------------------------

  Future<bool> _executeServiceStage() async {
    final l10n = _l10n();
    _appendLog(l10n.installWizardLogService);
    try {
      final configNotifier = ref.read(webuiSidecarConfigProvider.notifier);
      final initial = ref.read(webuiSidecarConfigProvider);
      if (initial.host != '0.0.0.0') {
        _appendLog(l10n.installWizardLogHostSwitch(initial.host));
        await configNotifier.setHost('0.0.0.0');
      }
      await configNotifier.setEnabled(true);
      if (mounted) {
        setState(() => _lanEnabled = true);
      }
      await ref.read(webuiSidecarControllerProvider.notifier).start();
      final running = await _waitForServiceRunning();
      if (!running) {
        _failureReason = _serviceFailureReason.isEmpty
            ? l10n.installWizardFailService
            : _serviceFailureReason;
        _appendLog(l10n.installWizardLogServiceFailed(_failureReason));
        return false;
      }
      final config = ref.read(webuiSidecarConfigProvider);
      final address = '${config.host}:${config.port}';
      if (mounted) {
        setState(() => _serviceAddress = address);
      }
      _appendLog(l10n.installWizardLogServiceReady(address));
      if (ref.read(tailscaleOptInProvider)) {
        await _runTailscaleInstall();
      } else {
        _appendLog(l10n.installWizardLogTailscaleSkipped);
      }
      return true;
    } catch (e) {
      _failureReason = '$e';
      _appendLog(l10n.installWizardLogServiceError('$e'));
      return false;
    }
  }

  /// 轮询内置服务状态直到 running（30s 超时）。
  Future<bool> _waitForServiceRunning() async {
    const interval = Duration(milliseconds: 250);
    const timeout = Duration(seconds: 30);
    var waited = Duration.zero;
    while (waited < timeout) {
      final state = ref.read(webuiSidecarControllerProvider);
      if (state.status == SidecarStatus.running) return true;
      if (state.status == SidecarStatus.failed) {
        _serviceFailureReason = _mapSidecarFailure(state);
        return false;
      }
      await Future<void>.delayed(interval);
      waited += interval;
    }
    _serviceFailureReason = _l10n().installWizardServiceTimeout;
    return false;
  }

  String _mapSidecarFailure(SidecarState state) {
    final l10n = AppLocalizations.of(context);
    switch (state.reason) {
      case SidecarFailureReason.portOccupied:
        return l10n.webuiFailurePortOccupied;
      case SidecarFailureReason.missingBundle:
        return l10n.webuiFailureMissingBundle;
      case SidecarFailureReason.healthTimeout:
        return l10n.webuiFailureHealthTimeout;
      case SidecarFailureReason.startFailed:
        return state.detail ?? l10n.webuiFailureStartFailed;
      case SidecarFailureReason.none:
        return state.detail ?? l10n.webuiStatusFailed;
    }
  }

  /// Tailscale 一键安装（勾选时）：过程整体走横向轨，失败不阻断向导。
  Future<void> _runTailscaleInstall() async {
    final l10n = _l10n();
    final TailscaleService service;
    try {
      service = ref.read(tailscaleServiceProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _tailscaleUnavailable = true);
        _appendLog(l10n.installWizardTailscaleUnavailable);
      }
      return;
    }
    _tailscaleService = service;
    _appendLog(l10n.installWizardLogTailscale);
    try {
      await for (final status in service.installAndLogin()) {
        if (!mounted) return;
        setState(() => _tailscaleStatus = status);
        if (status.detail.isNotEmpty) {
          _appendLog('Tailscale: ${status.detail}');
        }
        if (status.isReady) {
          _appendLog(l10n.installWizardLogTailscaleReady(status.ipv4));
          return;
        }
        if (status.state == TailscaleState.failed) {
          _appendLog(l10n.installWizardTailscaleFailedHint);
          return;
        }
      }
    } catch (e) {
      _appendLog(l10n.installWizardLogTailscaleError('$e'));
    }
  }

  /// Tailscale 三态轨的当前步（0 下载 / 1 静默安装 / 2 登录生成地址）。
  int _tailscaleStepIndex(AppLocalizations l10n, TailscaleStatus status) {
    final progress = status.progress;
    switch (status.state) {
      case TailscaleState.ready:
      case TailscaleState.needsLogin:
        return l10n.installWizardTailscaleSteps.length - 1;
      case TailscaleState.unknown:
      case TailscaleState.notInstalled:
      case TailscaleState.installing:
      case TailscaleState.failed:
        if (progress < 0.34) return 0;
        if (progress < 0.8) return 1;
        return 2;
    }
  }

  // ---------------------------------------------------------------------------
  // 「手机配对」步
  // ---------------------------------------------------------------------------

  /// 进入配对步骤：先订阅成功事件，再生成配对码。
  Future<void> _beginPairing() async {
    final l10n = _l10n();
    setState(() {
      _phase = GuidePhase.pairing;
      _pairingError = '';
      _pairingUnavailable = false;
      _accepted = null;
    });
    final PairingService service;
    try {
      service = ref.read(pairingServiceProvider);
    } catch (_) {
      setState(() => _pairingUnavailable = true);
      _appendLog(l10n.installWizardLogPairingUnavailable);
      return;
    }
    // 先订阅再接码，避免手机接入事件抢在订阅之前（流可能是广播流）。
    final oldSub = _pairingSub;
    if (oldSub != null) await oldSub.cancel();
    _pairingSub = service.accepted.listen(_onPairingAccepted);
    await _startPairingSession(service);
  }

  Future<void> _startPairingSession(PairingService service) async {
    try {
      final config = ref.read(webuiSidecarConfigProvider);
      final host = await _resolvePairingHost();
      final baseUrl = 'http://$host:${config.port}';
      final session = await service.start(
        baseUrl: baseUrl,
        password: config.password,
        installId: ref.read(installIdProvider),
        ttl: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _pairingSession = session;
        // 显示/交给手机的地址 = **服务端探活校验过的 host** + WebUI 端口
        // （不能用向导自己猜的 baseUrl：可能是 127.0.0.1 / 虚拟网卡 / fake-ip）。
        _pairingAddress = _advertisedWebuiBaseUrl(service, baseUrl);
        _pairingError = '';
      });
      _appendLog(_l10n().installWizardLogPairingReady);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairingError =
            '${AppLocalizations.of(context).installWizardPairingErrorPrefix}$e';
      });
    }
  }

  /// 向导要显示、也是手机将要保存的 WebUI 地址。
  ///
  /// host 取**服务端探活校验过**的那块网卡（`AdvertisedAddressReporting`），端口沿用
  /// WebUI 端口；服务端 `/pair` 应答与 UDP 发现应答下发的是同一个地址（同一口径）。
  /// 没有可用地址时返回空串 —— 调用方据此显示明确提示，绝不回 `127.0.0.1`。
  String _advertisedWebuiBaseUrl(PairingService service, String fallback) {
    final reporting = service is AdvertisedAddressReporting
        ? service as AdvertisedAddressReporting
        : null;
    if (reporting == null) return fallback; // 未实现该能力的实现：按现状显示
    final host = reporting.advertisedHost;
    if (host == null || host.isEmpty) return '';
    final uri = Uri.tryParse(fallback.trim());
    final port = uri?.port ?? ref.read(webuiSidecarConfigProvider).port;
    return 'http://$host:$port';
  }

  /// 配对地址：Tailscale 就绪则用 tailnet 地址（跨网可连），否则局域网地址。
  Future<String> _resolvePairingHost() async {
    final tailscale = _tailscaleStatus;
    if (tailscale != null && tailscale.isReady && tailscale.ipv4.isNotEmpty) {
      return tailscale.ipv4;
    }
    try {
      final lan = await ref.read(lanAddressProvider.future);
      if (lan.isNotEmpty) return lan;
    } catch (_) {
      // 取不到局域网地址就退回本机地址（仅同机可用，日志里已说明）。
    }
    return '127.0.0.1';
  }

  /// 对端接入 = 这一步才算向导整体成功。
  void _onPairingAccepted(PairingAccepted accepted) {
    if (!mounted) return;
    setState(() {
      _accepted = accepted;
      _stageStatuses[InstallStageKey.pairing] = StageStatus.success;
      _phase = GuidePhase.done;
    });
    _appendLog(_l10n().installWizardLogPhoneConnected(accepted.deviceLabel));
  }

  void _regeneratePairingCode() {
    final PairingService service;
    try {
      service = ref.read(pairingServiceProvider);
    } catch (_) {
      return;
    }
    setState(() => _pairingError = '');
    unawaited(_startPairingSession(service));
  }

  // ---------------------------------------------------------------------------
  // 模型配置与收尾
  // ---------------------------------------------------------------------------

  /// 保存（或跳过）模型配置，然后进入配对步。
  Future<void> _submitModelConfigAndContinue({required bool skip}) async {
    final l10n = _l10n();
    setState(() {
      _savingModel = true;
      _modelFormError = null;
    });
    if (!skip && _selectedProvider.requiresApiKey) {
      final key = _apiKeyController.text.trim();
      if (key.isEmpty) {
        setState(() {
          _savingModel = false;
          _modelFormError = l10n.installGuideApiKeyRequired;
        });
        return;
      }
    }
    try {
      if (!skip) {
        final api = ref.read(llmOnboardingApiProvider);
        final config = LlmOnboardingConfig(
          provider: _selectedProvider.id,
          apiKey: _apiKeyController.text.trim(),
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
        );
        _appendLog(l10n.installWizardLogSavingModel);
        await api.saveConfig(
          serverBaseUrl: 'http://127.0.0.1:8787',
          config: config,
        );
        _appendLog(l10n.installWizardLogModelSaved);
      }
      if (mounted) setState(() => _savingModel = false);
      // 收尾「启动服务」步（用户在它里面配完/跳过了模型），再进配对步 —— 此刻
      // 轨上第 4 点转绿、当前步滑到第 5 点、进度 4/5，与配对步的「等待中」自洽。
      setState(() {
        _stageStatuses[InstallStageKey.service] = StageStatus.success;
      });
      await _beginPairing();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingModel = false;
        _modelFormError = l10n.installWizardModelSaveFailed('$e');
      });
      _appendLog(l10n.installWizardModelSaveFailed('$e'));
    }
  }

  /// 向导末步收尾（配对成功点「完成」、配对不可用点「跳过」都走这里）。
  ///
  /// 三级顺序不可换：
  /// 1. **先刷 agent 环境探测** —— 向导刚把 Agent 装好，而 `agentEnvPresentProvider`
  ///    是缓存值（全仓只有内置 Tab 的「重新检测」与设置页会刷新），不刷则用户回到
  ///    内置服务 Tab 仍看到「未检测到 Agent」+ 置灰的启动按钮，等于白装；
  /// 2. 再走 [BuiltinServiceConnector] 的「自动登录 + builtin upsert/activate」——
  ///    与内置 Tab 的「启动并连接」**同一份链**：地址/密码取 sidecar 实配
  ///    （端口可改、密码是首次加载生成的 24 位随机值），连接落在 `builtinId` 上；
  ///    此前这里自建 UUID 连接 + 硬编码 `127.0.0.1:8787` + 空密码 ⇒ 走完也登录不上，
  ///    且内置 Tab 认不出该连接（不归「内置不可删 / 可停用」铁律管）；
  /// 3. 最后进会话列表。
  ///
  /// 失败不静默：就地出红字（[installWizardFinishFailed]）并保留按钮可重试。
  Future<void> _finishWizard() async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _finishError = '';
    });
    final l10n = _l10n();
    try {
      await ref.read(agentEnvPresentProvider.notifier).refresh();
      await BuiltinServiceConnector(ref).loginAndActivate();
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _finishError = l10n.installWizardFinishFailed('$e');
      });
      _appendLog(l10n.installWizardLogConnectionFailed('$e'));
    }
  }

  void _showProviderPicker() {
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(
            AppLocalizations.of(ctx).installGuideSelectProvider,
            style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                ? const TextStyle(color: LightSurfaces.textSecondary)
                : null,
          ),
          actions: LlmProviderOption.builtinProviders.map((p) {
            return CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedProvider = p;
                  _baseUrlController.text = p.defaultBaseUrl;
                  _modelController.text = p.defaultModel;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: kFontItemTitle,
                          fontWeight: FontWeight.bold,
                          color:
                              CupertinoTheme.brightnessOf(ctx) ==
                                  Brightness.light
                              ? LightSurfaces.menuAction.resolveFrom(ctx)
                              : null,
                        ),
                      ),
                      Text(
                        p.description,
                        style: TextStyle(
                          fontSize: kFontCaption,
                          color: LightSurfaces.resolve(
                            context,
                            statusGreyText.resolveFrom(ctx),
                            dark: secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedProvider.id == p.id)
                    Icon(
                      CupertinoIcons.checkmark_alt,
                      color: statusGreenText.resolveFrom(context),
                    ),
                ],
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(ctx).cancel,
              style: CupertinoTheme.brightnessOf(ctx) == Brightness.light
                  ? TextStyle(color: LightSurfaces.menuAction.resolveFrom(ctx))
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isWindows = ref.read(installDetectorProvider).isWindows;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.brightnessOf(context) == Brightness.light
          ? LightSurfaces.page
          : null,
      navigationBar: CupertinoNavigationBar(
        border: null,
        bottom: const NavBarHairline(),
        backgroundColor:
            CupertinoTheme.brightnessOf(context) == Brightness.light
            ? LightSurfaces.page
            : null,
        middle: Text(l10n.installGuideTitle),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _handleBack,
          child: const Icon(CupertinoIcons.back),
        ),
      ),
      child: SafeArea(
        child: isWindows
            ? _buildMainContent(l10n)
            : _buildNonWindowsPlaceholder(l10n),
      ),
    );
  }

  Widget _buildNonWindowsPlaceholder(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 56,
              color: LightSurfaces.resolve(
                context,
                statusOrangeText.resolveFrom(context),
                dark: Color(CupertinoColors.systemYellow.toARGB32()),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.installGuideWindowsOnly,
              textAlign: TextAlign.center,
              // TODO(type): 未进梯子（非 Windows 占位大标题，宜 kFontPageTitle 17）
              style: const TextStyle(
                fontSize: kFontSectionTitleLg,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.userDetail
                  : null,
              onPressed: () => context.go('/onboarding'),
              child: Text(l10n.installGuideBackToConnect),
            ),
          ],
        ),
      ),
    );
  }

  /// 内容列（宽屏右栏与窄屏单列共用同一串）。
  List<Widget> _buildContentChildren(AppLocalizations l10n) {
    return [
      _buildHeader(l10n),
      const SizedBox(height: 18),
      _buildStepRail(l10n),
      ..._buildCurrentStepBody(l10n),
      if (_phase == GuidePhase.failed) ...[
        const SizedBox(height: 16),
        _buildErrorCard(l10n),
      ],
      const SizedBox(height: 20),
      _buildLogConsole(l10n),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildMainContent(AppLocalizations l10n) {
    return WideDualPane(
      wideChild: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          ..._buildContentChildren(l10n),
          _buildBottomBar(l10n),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: _buildContentChildren(l10n),
            ),
          ),
          _buildBottomBar(l10n),
        ],
      ),
    );
  }

  /// 标题行：左侧标题/副标题，右侧浮动主操作 icon button。
  ///
  /// 主操作原先挂在页面最下方，窄窗口或手机远程桌面（主人 2026-10-25 截图）下
  /// 要滚到内容末尾才看得见 ——「开始安装」干脆不在首屏，用户以为没有下一步。
  /// 移到标题行右侧后，任何窗口高度下都在首屏，且不随内容滚走。
  Widget _buildHeader(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.installGuideTitle,
                style: const TextStyle(
                  fontSize: kFontPageTitleLg,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.installGuideSubtitle,
                style: TextStyle(
                  fontSize: kFontBody,
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildHeaderAction(l10n),
      ],
    );
  }

  /// 标题行右侧的主操作（胶囊按钮：icon + 短文案）。
  ///
  /// 各阶段的主 CTA：开始安装 / 安装中(转圈) / 重试 / 保存并继续 / 完成。
  /// 禁用态用灰底而不是隐掉 —— 按钮位置固定，用户不会觉得「按钮跑了」。
  ///
  /// 为什么是胶囊而不是纯圆形 icon：40px 圆在标题行显得过大（主人 2026-10-25
  /// 反馈），且 icon-only 单靠语义标签猜不出动作。压到 30px 高、横向放 12px
  /// 短文案，既不抢标题，又让人一眼知道点下去会发生什么。
  Widget _buildHeaderAction(AppLocalizations l10n) {
    final spec = _headerActionSpec(l10n);
    final primaryColor = CupertinoTheme.brightnessOf(context) == Brightness.light
        ? LightSurfaces.userDetail
        : CupertinoTheme.of(context).primaryColor;
    final disabled = spec.onPressed == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: spec.tooltip,
      child: CupertinoButton(
        key: spec.key,
        padding: EdgeInsets.zero,
        // CupertinoButton 默认最小尺寸 44×44，会把胶囊顶回 44 高。
        minimumSize: const Size(0, 30),
        onPressed: spec.onPressed,
        // icon-only 按钮：语义标签由上面的 Semantics 提供（本页是 Cupertino
        // 体系，没有 Material 的 Tooltip 可用）。
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: disabled
                ? CupertinoColors.systemGrey4.resolveFrom(context)
                : primaryColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spec.busy)
                const CupertinoActivityIndicator(
                  radius: 6,
                  color: CupertinoColors.white,
                )
              else
                Icon(spec.icon, size: 14, color: CupertinoColors.white),
              const SizedBox(width: 6),
              Text(
                spec.label,
                style: const TextStyle(
                  fontSize: kFontCaption,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 当前阶段的主操作描述（每个阶段都有出口，不会返回空）。
  _HeaderActionSpec _headerActionSpec(AppLocalizations l10n) {
    switch (_phase) {
      case GuidePhase.idle:
        return _HeaderActionSpec(
          key: const ValueKey('install-guide-start-btn'),
          icon: CupertinoIcons.play_fill,
          label: l10n.installGuidePillStart,
          tooltip: l10n.installGuideStartInstall,
          onPressed: () => _startOrResumeInstallation(),
        );
      case GuidePhase.installing:
        return _HeaderActionSpec(
          key: const ValueKey('install-guide-installing-btn'),
          icon: CupertinoIcons.hourglass,
          label: l10n.installGuidePillInstalling,
          tooltip: l10n.installGuideInstalling,
          busy: true,
        );
      case GuidePhase.failed:
        // 错误卡里也有「重试当前步骤」；标题行这颗是免滚动的快捷入口，
        // key 与卡片内按钮区分（卡片内那颗被既有用例按 key 点击）。
        return _HeaderActionSpec(
          key: const ValueKey('install-guide-header-retry-btn'),
          icon: CupertinoIcons.arrow_clockwise,
          label: l10n.installGuideRetry,
          tooltip: l10n.installGuideRetryStage,
          onPressed: () => _startOrResumeInstallation(_failedStage),
        );
      case GuidePhase.configuringModel:
        return _HeaderActionSpec(
          key: const ValueKey('install-guide-save-model-btn'),
          icon: CupertinoIcons.checkmark_alt,
          label: l10n.installGuidePillSave,
          tooltip: l10n.installGuideSaveAndContinue,
          busy: _savingModel,
          onPressed: _savingModel
              ? null
              : () => _submitModelConfigAndContinue(skip: false),
        );
      case GuidePhase.pairing:
        return _HeaderActionSpec(
          key: const ValueKey('wizard-pairing-skip-btn'),
          icon: CupertinoIcons.checkmark_alt,
          label: l10n.installGuidePillSkip,
          tooltip: l10n.installWizardPairingSkip,
          busy: _finishing,
          onPressed: _finishing ? null : _finishWizard,
        );
      case GuidePhase.done:
        return _HeaderActionSpec(
          key: const ValueKey('wizard-pairing-finish-btn'),
          icon: CupertinoIcons.checkmark_alt,
          label: l10n.finish,
          tooltip: l10n.finish,
          busy: _finishing,
          onPressed: _finishing ? null : _finishWizard,
        );
    }
  }

  Widget _buildStepRail(AppLocalizations l10n) {
    // 当前步不该显示成「已完成」：模型配置还挂在「启动服务」步里等用户操作时，
    // 该步的状态已是 success（4 步完成），若把 4 直接交给轨，第 4 个点会变绿、
    // 整条轨没有蓝点 —— 违背「当前步必须明显高亮」。故未整体完成前，完成数最多
    // 算到当前步之前（本批实测用例「安装推进…」锁住该行为）。
    final doneCount = _phase == GuidePhase.done
        ? _completedCount
        : _completedCount.clamp(0, _currentStepIndex);
    return HorizontalStepRail(
      labels: [
        l10n.installGuideStagePrereqs,
        l10n.installGuideStageAgent,
        l10n.installGuideStageDeps,
        l10n.installWizardStepService,
        l10n.installWizardStepPairing,
      ],
      currentIndex: _currentStepIndex,
      doneCount: doneCount,
      failedIndex: _failedStageIndex,
    );
  }

  /// 当前步的附加内容（按步分派）。
  List<Widget> _buildCurrentStepBody(AppLocalizations l10n) {
    switch (InstallStageKey.values[_currentStepIndex]) {
      case InstallStageKey.prereqs:
        return _buildPrereqCheckBody(l10n);
      case InstallStageKey.service:
        return _buildServiceBody(l10n);
      case InstallStageKey.pairing:
        return _buildPairingBody(l10n);
      case InstallStageKey.agent:
      case InstallStageKey.agentDeps:
        return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // 首屏检查卡 + 网络受限提示（规格 C）
  // ---------------------------------------------------------------------------

  List<Widget> _buildPrereqCheckBody(AppLocalizations l10n) {
    return [
      const SizedBox(height: 12),
      _card(
        key: const ValueKey('wizard-prereq-check-card'),
        child: Column(
          children: [
            _statRow(
              titleKey: 'wizard-check-windows',
              icon: CupertinoIcons.checkmark_circle_fill,
              iconColor: statusGreenText.resolveFrom(context),
              title: l10n.installWizardCheckWindows,
              value: l10n.installWizardCheckWindowsValue,
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-check-agent',
              icon: CupertinoIcons.hourglass,
              iconColor: _secondary,
              title: l10n.installWizardCheckAgent,
              value:
                  _stageStatuses[InstallStageKey.agent] == StageStatus.success
                  ? l10n.installWizardCheckAgentInstalled
                  : l10n.installWizardCheckAgentPending,
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-check-service',
              icon: CupertinoIcons.lock,
              iconColor: _secondary,
              title: l10n.onboardingTabBuiltin,
              value: _serviceAddress.isEmpty
                  ? l10n.installWizardCheckServicePending
                  : l10n.installWizardServiceRunning(
                      _serviceAddress.split(':').first,
                      int.tryParse(_serviceAddress.split(':').last) ?? 0,
                    ),
              valueColor: _serviceAddress.isEmpty
                  ? null
                  : statusGreenText.resolveFrom(context),
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-check-network',
              valueKey: 'wizard-check-network-value',
              icon: _networkReachable
                  ? CupertinoIcons.wifi
                  : CupertinoIcons.exclamationmark_triangle,
              iconColor: _networkReachable
                  ? _secondary
                  : statusOrangeText.resolveFrom(context),
              title: l10n.installWizardCheckNetwork,
              value: _networkChecking
                  ? l10n.installWizardNetworkChecking
                  : (_networkReachable
                        ? l10n.installWizardNetworkNormal
                        : (_networkDetail.isEmpty
                              ? l10n.installWizardNetworkFailed
                              : _networkDetail)),
              valueColor: (_networkChecking || _networkReachable)
                  ? null
                  : statusOrangeText.resolveFrom(context),
            ),
          ],
        ),
      ),
      if (_showNetworkWarning) ...[
        const SizedBox(height: 12),
        _buildNetworkWarningCard(l10n),
      ],
    ];
  }

  /// 没有手机能连上的局域网地址时的告警卡（同 [_buildNetworkWarningCard] 的视觉 token）。
  Widget _buildNoLanAddressCard(AppLocalizations l10n) {
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.tintWarning,
      dark: statusOrangeText.resolveFrom(context).withValues(alpha: 0.14),
    );
    final border = LightSurfaces.resolve(
      context,
      const Color(0xFFF0D6B8),
      dark: statusOrangeText.resolveFrom(context).withValues(alpha: 0.36),
    );
    final textColor = LightSurfaces.resolve(
      context,
      const Color(0xFF5B3A16),
      dark: statusOrangeText.resolveFrom(context),
    );
    return Container(
      key: const ValueKey('wizard-no-lan-address-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 15,
            color: statusOrangeText.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.installWizardNoLanAddress,
              style: TextStyle(fontSize: kFontCaption, height: 1.5, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkWarningCard(AppLocalizations l10n) {
    // 设计稿 §5 N1 真值：底 #FFF4E8 / 边 #F0D6B8 / 文字 #5B3A16。
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.tintWarning,
      dark: statusOrangeText.resolveFrom(context).withValues(alpha: 0.14),
    );
    final border = LightSurfaces.resolve(
      context,
      const Color(0xFFF0D6B8),
      dark: statusOrangeText.resolveFrom(context).withValues(alpha: 0.36),
    );
    final textColor = LightSurfaces.resolve(
      context,
      const Color(0xFF5B3A16),
      dark: statusOrangeText.resolveFrom(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('wizard-network-warning-card'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 15,
                color: statusOrangeText.resolveFrom(context),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  l10n.installWizardNetworkWarning,
                  style: TextStyle(
                    fontSize: kFontCaption,
                    height: 1.5,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ghostButton(
                key: const ValueKey('wizard-network-recheck-btn'),
                label: l10n.installWizardNetworkRecheck,
                icon: CupertinoIcons.arrow_clockwise,
                onPressed: _recheckNetwork,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _filledButton(
                key: const ValueKey('wizard-network-continue-btn'),
                label: l10n.installWizardNetworkContinue,
                onPressed: _continueDespiteNetwork,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.installWizardNetworkSkipHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: kFontMicro, color: _secondary),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 「启动服务」步：局域网可见性 + Tailscale 勾选 + 模型配置
  // ---------------------------------------------------------------------------

  List<Widget> _buildServiceBody(AppLocalizations l10n) {
    final config = _serviceConfigOrNull();
    final host = config?.host ?? '';
    final port = config?.port ?? 0;
    final status =
        _stageStatuses[InstallStageKey.service] ?? StageStatus.pending;
    // 服务状态不再单开一行：它原来和「允许局域网设备访问」右侧报的是同一个地址
    // （主人 2026-10-25 反馈「已开启 · 0.0.0.0:8787」与「● 运行中 0.0.0.0:8787」
    // 重复）。运行态并入那一行，失败原因仍由错误卡承载。
    final String lanValue;
    final Color? lanValueColor;
    if (_serviceAddress.isNotEmpty) {
      // 服务真的在跑 —— 无论步骤是否 close，都据实报「运行中 + 地址」。
      lanValue = l10n.installWizardServiceRunning(
        _serviceAddress.split(':').first,
        int.tryParse(_serviceAddress.split(':').last) ?? port,
      );
      lanValueColor = statusGreenText.resolveFrom(context);
    } else if (status == StageStatus.running) {
      lanValue = l10n.webuiStatusStarting;
      lanValueColor = null;
    } else if (_lanEnabled && host.isNotEmpty) {
      lanValue = l10n.installWizardLanOn(host, port);
      lanValueColor = statusGreenText.resolveFrom(context);
    } else {
      lanValue = l10n.installWizardLanOff;
      lanValueColor = null;
    }
    return [
      const SizedBox(height: 12),
      _card(
        key: const ValueKey('wizard-service-card'),
        child: Column(
          children: [
            _statRow(
              titleKey: 'wizard-lan-row',
              icon: CupertinoIcons.antenna_radiowaves_left_right,
              iconColor: _secondary,
              title: l10n.installWizardLanTitle,
              value: lanValue,
              valueColor: lanValueColor,
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-credential-row',
              icon: CupertinoIcons.lock,
              iconColor: _secondary,
              title: l10n.installWizardCredentialTitle,
              // 带「密码在哪看」的真实路径指路（桌面浏览器直连需要密码；
              // 手机接入走配对码，不需要明文密码）。
              value: l10n.installWizardCredentialValueWithPath,
            ),
            _rowDivider(),
            _tailscaleRow(l10n),
          ],
        ),
      ),
      if (_tailscaleStatus != null) ...[
        const SizedBox(height: 12),
        _buildTailscaleProgressCard(l10n, _tailscaleStatus!),
      ],
      const SizedBox(height: 12),
      _noteCard(l10n.installWizardTailscaleExempt),
      const SizedBox(height: 12),
      // 首次放行提示：本步是内置服务首次绑 0.0.0.0:8787 的时点，Windows 会弹一次
      // 「是否允许访问网络」；点了取消 / 关掉后手机侧就静默连不上（同款 notecard 样式）。
      _noteCard(l10n.installWizardFirewallAllowHint),
      if (_phase == GuidePhase.configuringModel) ...[
        const SizedBox(height: 12),
        _buildModelConfigForm(l10n),
      ],
    ];
  }

  /// 读一次 sidecar 配置（拿不到就给 null，绝不因配置层异常崩向导）。
  SidecarConfig? _serviceConfigOrNull() {
    try {
      return ref.read(webuiSidecarConfigProvider);
    } catch (_) {
      return null;
    }
  }

  /// Tailscale 勾选行（规格 B：默认勾选；未注入服务时降级为提示，不崩）。
  Widget _tailscaleRow(AppLocalizations l10n) {
    if (_tailscaleUnavailable) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.info_circle, size: 16, color: _secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.installWizardTailscaleTitle,
                    key: const ValueKey('wizard-tailscale-unavailable'),
                    style: const TextStyle(fontSize: kFontItemTitle),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.installWizardTailscaleUnavailable,
                    style: TextStyle(
                      fontSize: kFontCaption,
                      height: 1.45,
                      color: _secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final checked = ref.watch(tailscaleOptInProvider);
    return GestureDetector(
      key: const ValueKey('wizard-tailscale-row'),
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(tailscaleOptInProvider.notifier).toggle(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _checkbox(checked: checked),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.installWizardTailscaleTitle,
                          style: const TextStyle(fontSize: kFontItemTitle),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _badge(l10n.installWizardTailscaleBadge),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.installWizardTailscaleSub1,
                    style: TextStyle(
                      // TODO(type): 设计稿 11.5，梯子无此档；本批按 kFontCaption(12)
                      fontSize: kFontCaption,
                      height: 1.45,
                      color: _secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.installWizardTailscaleSub2,
                    style: TextStyle(
                      fontSize: kFontCaption,
                      height: 1.45,
                      color: _secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkbox({required bool checked}) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Container(
      key: const ValueKey('wizard-tailscale-checkbox'),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked
            ? LightSurfaces.resolve(
                context,
                LightSurfaces.userDetail,
                dark: const Color(0xFF007AFF),
              )
            : null,
        borderRadius: BorderRadius.circular(6),
        border: checked
            ? null
            : Border.all(
                color: isDark
                    ? const Color(0xFF48484A)
                    : const Color(0xFFC8C8CC),
                width: 1.5,
              ),
      ),
      child: checked
          ? const Icon(
              CupertinoIcons.checkmark,
              key: ValueKey('wizard-tailscale-checkbox-mark'),
              size: 13,
              color: CupertinoColors.white,
            )
          : null,
    );
  }

  Widget _badge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: statusGreenText.resolveFrom(context),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          // TODO(type): 设计稿 10.5，本批按 kFontMicro(11)（同档含义：角标）
          fontSize: kFontMicro,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
        ),
      ),
    );
  }

  /// Tailscale 安装过程卡（同一条横向轨，不另起垂直列表 —— 主人追加要求）。
  Widget _buildTailscaleProgressCard(
    AppLocalizations l10n,
    TailscaleStatus status,
  ) {
    final index = _tailscaleStepIndex(l10n, status);
    final done = status.isReady
        ? l10n.installWizardTailscaleSteps.length
        : index;
    final String summary;
    if (status.isReady) {
      summary = '${l10n.installWizardTailscaleReadyPrefix}${status.ipv4}';
    } else if (status.detail.isNotEmpty) {
      summary = status.detail;
    } else {
      summary = l10n.installWizardTailscaleWorking;
    }
    return _card(
      key: const ValueKey('wizard-tailscale-progress-card'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HorizontalStepRail(
            labels: l10n.installWizardTailscaleSteps,
            currentIndex: index,
            doneCount: done,
            failedIndex: status.state == TailscaleState.failed ? index : null,
            // 这条轨在卡片里：圆点兜底底色要取卡片底，否则未达点会画成
            // 一块比卡片略深的灰饼（盖线用，必须与背后缸体同色）。
            surfaceColor: LightSurfaces.resolve(
              context,
              LightSurfaces.card,
              dark: CupertinoColors.secondarySystemGroupedBackground,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                status.isReady
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.arrow_down_circle,
                size: 15,
                color: status.isReady
                    ? statusGreenText.resolveFrom(context)
                    : LightSurfaces.resolve(
                        context,
                        LightSurfaces.userDetail,
                        dark: const Color(0xFF007AFF),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary,
                      key: const ValueKey('wizard-tailscale-summary'),
                      style: TextStyle(
                        fontSize: kFontCaption,
                        color: _secondary,
                        height: 1.45,
                      ),
                    ),
                    if (status.loginUrl.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.installWizardTailscaleLoginHint}${status.loginUrl}',
                        style: TextStyle(
                          fontSize: kFontCaption,
                          color: _secondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 「手机配对」步
  // ---------------------------------------------------------------------------

  List<Widget> _buildPairingBody(AppLocalizations l10n) {
    final accepted = _accepted;
    if (accepted != null) {
      return _buildPairedAcceptance(l10n, accepted);
    }
    return [
      const SizedBox(height: 12),
      _card(
        key: const ValueKey('wizard-pairing-card'),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: _pairingUnavailable
            ? _buildPairingUnavailable(l10n)
            : _buildPairingCode(l10n),
      ),
    ];
  }

  Widget _buildPairingUnavailable(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 15,
          color: statusOrangeText.resolveFrom(context),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.installWizardPairingUnavailable,
                key: const ValueKey('wizard-pairing-unavailable'),
                style: const TextStyle(
                  fontSize: kFontItemTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.installWizardPairingUnavailableHint,
                style: TextStyle(
                  fontSize: kFontCaption,
                  height: 1.45,
                  color: _secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPairingCode(AppLocalizations l10n) {
    final session = _pairingSession;
    final code = session?.code ?? '';
    final digits = List<String>.generate(
      6,
      (i) => i < code.length ? code[i] : '',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < digits.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                key: ValueKey<String>('wizard-pairing-digit-$i'),
                width: 44,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LightSurfaces.resolve(
                    context,
                    const Color.fromRGBO(120, 120, 128, 0.12),
                    dark: const Color.fromRGBO(120, 120, 128, 0.24),
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  digits[i],
                  style: const TextStyle(
                    // TODO(type): 设计稿 26，梯子无此档；本批按 kFontMetric(21)
                    fontSize: kFontMetric,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CupertinoActivityIndicator(radius: 7),
            const SizedBox(width: 8),
            Text(
              l10n.installWizardPairingWaiting,
              key: const ValueKey('wizard-pairing-waiting'),
              style: TextStyle(fontSize: kFontCaption, color: _secondary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          l10n.installWizardPairingHint,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: kFontCaption,
            height: 1.5,
            color: _secondary,
          ),
        ),
        if (_pairingAddress.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${l10n.installWizardPairingAddressPrefix}$_pairingAddress',
            key: const ValueKey('wizard-pairing-address'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: kFontMicro, color: _secondary),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          l10n.installWizardPairingTtl,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: kFontMicro, color: _secondary),
        ),
        // 出了码但**没有任何手机能连上的地址**：明确说清，不要让用户拿着配对码干等。
        if (_pairingSession != null && _pairingAddress.isEmpty) ...[
          const SizedBox(height: 10),
          _buildNoLanAddressCard(l10n),
        ],
        if (_pairingError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _pairingError,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: kFontCaption,
              color: statusRedText.resolveFrom(context),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Center(
          child: _ghostButton(
            key: const ValueKey('wizard-pairing-regenerate-btn'),
            label: l10n.installWizardPairingRegenerate,
            icon: CupertinoIcons.arrow_clockwise,
            onPressed: _regeneratePairingCode,
          ),
        ),
      ],
    );
  }

  /// 验收态：对端已连上（设计稿 D5）。
  List<Widget> _buildPairedAcceptance(
    AppLocalizations l10n,
    PairingAccepted accepted,
  ) {
    final config = _serviceConfigOrNull();
    final parts = _serviceAddress.split(':');
    final host = parts.first.isNotEmpty ? parts.first : (config?.host ?? '');
    final port = parts.length > 1
        ? (int.tryParse(parts.last) ?? 0)
        : (config?.port ?? 0);
    final deviceName = ref.read(installIdProvider);
    return [
      const SizedBox(height: 12),
      _card(
        key: const ValueKey('wizard-paired-card'),
        child: Column(
          children: [
            _statRow(
              titleKey: 'wizard-paired-device',
              icon: CupertinoIcons.checkmark_circle_fill,
              iconColor: statusGreenText.resolveFrom(context),
              title: accepted.deviceLabel,
              value: l10n.installWizardPairedJustNow,
              valueColor: statusGreenText.resolveFrom(context),
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-paired-host',
              icon: CupertinoIcons.desktopcomputer,
              iconColor: _secondary,
              title: deviceName.isEmpty
                  ? l10n.installWizardCheckWindows
                  : deviceName,
              value: l10n.installWizardPairedService(host, port),
            ),
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 通用小件
  // ---------------------------------------------------------------------------

  Color get _secondary => LightSurfaces.resolve(
    context,
    LightSurfaces.textSecondary,
    dark: secondaryText,
  );

  Color get _primary => LightSurfaces.resolve(
    context,
    LightSurfaces.userDetail,
    dark: const Color(0xFF007AFF),
  );

  Widget _card({
    Key? key,
    Widget? child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return Container(
      key: key,
      padding: padding,
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }

  Widget _rowDivider() {
    return Container(
      height: 0.5,
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.divider,
        dark: CupertinoColors.separator,
      ),
    );
  }

  /// 检查卡 / 服务卡一行：图标 + 标题 + 右侧值。
  Widget _statRow({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    String? titleKey,
    String? valueKey,
    String? iconKey,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Icon(
            icon,
            key: iconKey == null ? null : ValueKey<String>(iconKey),
            size: 16,
            color: iconColor,
          ),
          const SizedBox(width: 10),
          Text(
            title,
            key: titleKey == null ? null : ValueKey<String>(titleKey),
            style: const TextStyle(fontSize: kFontItemTitle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              key: valueKey == null ? null : ValueKey<String>(valueKey),
              textAlign: TextAlign.right,
              maxLines: 2,
              style: TextStyle(
                fontSize: kFontCaption,
                color: valueColor ?? _secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.card,
          dark: CupertinoColors.secondarySystemGroupedBackground,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 15, color: _secondary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kFontCaption,
                height: 1.5,
                color: _secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ghostButton({
    Key? key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      key: key,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.cardBorder,
              dark: CupertinoColors.separator,
            ),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: _primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: kFontButton, color: _primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filledButton({
    Key? key,
    required String label,
    required VoidCallback onPressed,
  }) {
    return CupertinoButton(
      key: key,
      padding: EdgeInsets.zero,
      color: _primary,
      onPressed: onPressed,
      child: SizedBox(
        height: 38,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: kFontButton,
              color: CupertinoColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LightSurfaces.resolve(
          context,
          LightSurfaces.tintError,
          dark: statusRedText.resolveFrom(context).withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.cardBorder,
            dark: statusRedText.resolveFrom(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.xmark_octagon_fill,
                size: 20,
                color: statusRedText.resolveFrom(context),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.installWizardStepFailed(
                  _failedStage != null ? _stepTitle(l10n, _failedStage!) : '',
                ),
                style: TextStyle(
                  fontSize: kFontItemTitle,
                  fontWeight: FontWeight.bold,
                  color: statusRedText.resolveFrom(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _failureReason,
            style: TextStyle(
              fontSize: kFontLabel,
              color: statusRedText.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              key: const ValueKey('install-guide-retry-btn'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: statusRedText.resolveFrom(context),
              onPressed: () => _startOrResumeInstallation(_failedStage),
              child: Text(
                l10n.installGuideRetryStage,
                style: const TextStyle(
                  fontSize: kFontButton,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelConfigForm(AppLocalizations l10n) {
    return _card(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.installGuideStageModel,
            style: const TextStyle(
              fontSize: kFontSectionTitleLg,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.installGuideStageModelDesc,
            style: TextStyle(fontSize: kFontLabel, color: _secondary),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.installGuideSelectProvider,
            style: const TextStyle(
              fontSize: kFontLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildProviderSelector(),
          const SizedBox(height: 16),
          if (_selectedProvider.requiresApiKey) ...[
            Text(
              l10n.installGuideApiKey,
              style: const TextStyle(
                fontSize: kFontLabel,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            CupertinoTextField(
              decoration: OnboardingFieldStyle.decoration(context),
              placeholderStyle: OnboardingFieldStyle.placeholder(context),
              key: const ValueKey('install-guide-apikey-input'),
              controller: _apiKeyController,
              placeholder: _selectedProvider.keyPlaceholder,
              obscureText: true,
              padding: const EdgeInsets.all(10),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            l10n.installGuideBaseUrl,
            style: const TextStyle(
              fontSize: kFontLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            decoration: OnboardingFieldStyle.decoration(context),
            placeholderStyle: OnboardingFieldStyle.placeholder(context),
            key: const ValueKey('install-guide-baseurl-input'),
            controller: _baseUrlController,
            placeholder: l10n.installGuideBaseUrlHint,
            padding: const EdgeInsets.all(10),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.installGuideModelName,
            style: const TextStyle(
              fontSize: kFontLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            decoration: OnboardingFieldStyle.decoration(context),
            placeholderStyle: OnboardingFieldStyle.placeholder(context),
            key: const ValueKey('install-guide-model-input'),
            controller: _modelController,
            placeholder: l10n.installGuideModelNameHint,
            padding: const EdgeInsets.all(10),
          ),
          if (_modelFormError != null) ...[
            const SizedBox(height: 10),
            Text(
              '❌ $_modelFormError',
              style: TextStyle(
                fontSize: kFontLabel,
                color: statusRedText.resolveFrom(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return GestureDetector(
      key: const ValueKey('install-guide-provider-dropdown'),
      onTap: _showProviderPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.card,
            dark: CupertinoColors.tertiarySystemFill,
          ),
          borderRadius: BorderRadius.circular(8),
          border: CupertinoTheme.brightnessOf(context) == Brightness.light
              ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedProvider.name,
                    style: const TextStyle(
                      fontSize: kFontItemTitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedProvider.description,
                    style: TextStyle(fontSize: kFontCaption, color: _secondary),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_up_chevron_down,
              size: 16,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.textSecondary,
                dark: Color(CupertinoColors.systemGrey.toARGB32()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The terminal remains an inverse surface in both themes. Its grey/green
  // content is readable on the fixed dark background; do not apply light grey.
  Widget _buildLogConsole(AppLocalizations l10n) {
    // 卡片自带 10 圆角 + 0.5 描边：外层 ClipRRect 把内部黑色日志区一起裁成同
    // 一圆角，避免「黑块方角从卡片圆角里戳出来」。
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.darkBackgroundGray,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.separator,
            ),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行：内距压到 6，并把两个文字按钮的点击热区下限从
            // CupertinoButton 默认的 44 收到 20 —— 否则这一行无论日志展开还是
            // 收起都白占 ~60pt，比下面的日志正文还高。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.chevron_left_slash_chevron_right,
                        size: 14,
                        color: CupertinoColors.systemGrey,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.installGuideLogs,
                        style: const TextStyle(
                          fontSize: kFontCaption,
                          color: CupertinoColors.systemGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 20),
                        onPressed: () {
                          unawaited(
                            Clipboard.setData(
                              ClipboardData(text: _logs.join('\n')),
                            ),
                          );
                        },
                        child: Text(
                          l10n.installGuideCopyLogs,
                          style: TextStyle(
                            // TODO(type): 按钮文字用了说明档 12，应 kFontButton 13；本批保持原值
                            fontSize: kFontButton,
                            color:
                                CupertinoTheme.brightnessOf(context) ==
                                    Brightness.light
                                ? CupertinoColors.white
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 20),
                        onPressed: () {
                          setState(() => _showLogs = !_showLogs);
                        },
                        child: Text(
                          _showLogs
                              ? l10n.installGuideHideLogs
                              : l10n.installGuideShowLogs,
                          style: TextStyle(
                            fontSize: kFontButton,
                            color:
                                CupertinoTheme.brightnessOf(context) ==
                                    Brightness.light
                                ? CupertinoColors.white
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_showLogs)
              // 黑底日志区必须吃满卡片整宽：旧写法的 Container 只包住那行
              // 「等待安装启动…」文字，左侧一小块黑、右侧露出灰色卡片底 ——
              // 就是「半个黑块」的观感来源。
              Container(
                width: double.infinity,
                height: 140,
                padding: const EdgeInsets.all(10),
                color: CupertinoColors.black,
                child: _logs.isEmpty
                    ? Text(
                        l10n.installWizardLogWaiting,
                        style: const TextStyle(
                          fontSize: kFontCode,
                          color: CupertinoColors.systemGrey,
                          fontFamily: 'monospace',
                        ),
                      )
                    : ListView.builder(
                        controller: _logScrollController,
                        itemCount: _logs.length,
                        itemBuilder: (context, idx) {
                          return Text(
                            _logs[idx],
                            style: const TextStyle(
                              // TODO(type): 等宽日志行用 11，语义应 kFontCode 12；本批保持原值
                              fontSize: kFontCode,
                              color: CupertinoColors.systemGreen,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// 末步（配对 / 完成）共用的收尾尾巴：指路文案 + 收尾失败红字。
  ///
  /// 指路文案为什么必须有：向导的「启动服务」步把监听地址绑到 `0.0.0.0` 且不提供
  /// 改端口 / 密码的入口，而两个入口共用同一份 sidecar 配置 —— 不说明的话用户会
  /// 以为「向导里没配就是没配」。
  List<Widget> _finishTailChildren(AppLocalizations l10n) {
    return [
      Text(
        l10n.installWizardBuiltinSettingsHint,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: kFontCaption, color: _secondary),
      ),
      if (_finishError.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          _finishError,
          key: const ValueKey('wizard-finish-error'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: kFontBody,
            color: statusRedText.resolveFrom(context),
          ),
        ),
      ],
      const SizedBox(height: 8),
    ];
  }

  /// 底栏：只放次级弱操作与收尾提示（主 CTA 已 float 到标题行右侧）。
  ///
  /// 这样窄窗口下即使滚不到底，也不影响推进主线 —— 看不见的只是「暂不配置」
  /// 「跳过配对」这类可选动作。
  Widget _buildBottomBar(AppLocalizations l10n) {
    return _buildFooterActions(l10n);
  }

  Widget _buildFooterActions(AppLocalizations l10n) {
    if (_phase == GuidePhase.configuringModel) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: CupertinoButton(
          key: const ValueKey('install-guide-skip-model-btn'),
          padding: EdgeInsets.zero,
          onPressed: _savingModel
              ? null
              : () => _submitModelConfigAndContinue(skip: true),
          child: Text(
            l10n.installGuideSkipModelConfig,
            style: TextStyle(fontSize: kFontButton, color: _secondary),
          ),
        ),
      );
    }
    if (_phase == GuidePhase.pairing || _phase == GuidePhase.done) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _finishTailChildren(l10n),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 标题行主操作按钮的描述（icon / 提示 / 回调 / 忙碌态）。
class _HeaderActionSpec {
  const _HeaderActionSpec({
    required this.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    this.busy = false,
  });

  /// 按钮 key（测试与既有用例按 key 定位主操作）。
  final Key key;

  /// 图标（胶囊内左侧，14px）。
  final IconData icon;

  /// 胶囊内文案（12px）：短到能塞进标题行，又足以说明动作。
  final String label;

  /// 无障碍标签 + 悬停提示（icon-only 按钮必须有文字语义）。
  final String tooltip;

  /// 点击回调；null = 禁用态。
  final Future<void> Function()? onPressed;

  /// 忙碌态：显示转圈而不是图标。
  final bool busy;
}

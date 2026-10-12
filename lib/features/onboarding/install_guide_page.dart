import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import '../../app/theme/light_surfaces.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/nav_bar_hairline.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../../core/install/install_detector.dart';
import '../../core/install/llm_onboarding.dart';
import '../../core/install/powershell_installer.dart';
import '../../core/pairing/pairing_contract.dart';
import '../../core/tailscale/tailscale_contract.dart';
import '../../core/utils/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'install_wizard_strings.dart';
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

  String _stepTitle(InstallStageKey stage) {
    switch (stage) {
      case InstallStageKey.prereqs:
        return WizardStrings.stepPrereqs;
      case InstallStageKey.agent:
        return WizardStrings.stepAgent;
      case InstallStageKey.agentDeps:
        return WizardStrings.stepDeps;
      case InstallStageKey.service:
        return WizardStrings.stepService;
      case InstallStageKey.pairing:
        // 对端已连上后，这一步的名字改成验收态标题（设计稿 D5）。
        return _accepted != null
            ? WizardStrings.pairedTitle
            : WizardStrings.stepPairing;
    }
  }

  String _stepDesc(InstallStageKey stage) {
    switch (stage) {
      case InstallStageKey.prereqs:
        return WizardStrings.descPrereqs;
      case InstallStageKey.agent:
        return WizardStrings.descAgent;
      case InstallStageKey.agentDeps:
        return WizardStrings.descDeps;
      case InstallStageKey.service:
        return WizardStrings.descService;
      case InstallStageKey.pairing:
        return _accepted != null
            ? WizardStrings.pairedSub
            : WizardStrings.descPairing;
    }
  }

  IconData _stepIcon(InstallStageKey stage) {
    switch (stage) {
      case InstallStageKey.prereqs:
        return CupertinoIcons.checkmark_shield;
      case InstallStageKey.agent:
        return CupertinoIcons.arrow_down_circle;
      case InstallStageKey.agentDeps:
        return CupertinoIcons.cube_box;
      case InstallStageKey.service:
        return CupertinoIcons.antenna_radiowaves_left_right;
      case InstallStageKey.pairing:
        return CupertinoIcons.qrcode;
    }
  }

  String _stepStatusText(StageStatus status) {
    switch (status) {
      case StageStatus.pending:
        return WizardStrings.stagePending;
      case StageStatus.running:
        return WizardStrings.stageRunning;
      case StageStatus.success:
        return WizardStrings.stageSuccess;
      case StageStatus.failed:
        return WizardStrings.stageFailed;
    }
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
          _networkDetail = WizardStrings.networkFailed;
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
        _networkDetail = WizardStrings.networkFailed;
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
    try {
      switch (stage) {
        case InstallStageKey.prereqs:
          _appendLog('===> [1/5] 检查安装环境与下载官方 install.ps1 ...');
          await psInstaller.ensureScriptCached();
          await for (final event in psInstaller.runStage('prereqs')) {
            _handleInstallerEvent(event);
            if (event.type == InstallerEventType.stageFailure) {
              _failureReason = event.reason ?? '环境检查失败';
              return false;
            }
          }
          return true;
        case InstallStageKey.agent:
          _appendLog('===> [2/5] 拉取与安装 Hermes Agent 源码 ...');
          await for (final event in psInstaller.runStage('agent')) {
            _handleInstallerEvent(event);
            if (event.type == InstallerEventType.stageFailure) {
              _failureReason = event.reason ?? '拉取 Agent 失败';
              return false;
            }
          }
          return true;
        case InstallStageKey.agentDeps:
          _appendLog('===> [3/5] 安装 Agent Python 虚拟环境及依赖 ...');
          await for (final event in psInstaller.runStage('deps')) {
            _handleInstallerEvent(event);
            if (event.type == InstallerEventType.stageFailure) {
              _failureReason = event.reason ?? '安装 Agent 依赖失败';
              return false;
            }
          }
          return true;
        case InstallStageKey.service:
          return await _executeServiceStage();
        case InstallStageKey.pairing:
          // 不走自动循环（见 _startOrResumeInstallation）。
          return true;
      }
    } catch (e) {
      _failureReason = '$e';
      _appendLog('执行步骤异常: $e');
      return false;
    }
  }

  void _handleInstallerEvent(InstallerEvent event) {
    if (event.message != null && event.message!.isNotEmpty) {
      _appendLog('[${event.stage ?? 'info'}] ${event.message}');
    } else if (event.raw.isNotEmpty) {
      _appendLog(event.raw);
    }
  }

  // ---------------------------------------------------------------------------
  // 「启动服务」步：拉起内置服务 + 可选 Tailscale
  // ---------------------------------------------------------------------------

  Future<bool> _executeServiceStage() async {
    _appendLog('===> [4/5] 拉起内置 WebUI 服务并开启局域网访问 ...');
    try {
      final configNotifier = ref.read(webuiSidecarConfigProvider.notifier);
      final initial = ref.read(webuiSidecarConfigProvider);
      if (initial.host != '0.0.0.0') {
        _appendLog('监听地址 ${initial.host} → 0.0.0.0（同一 Wi-Fi 的手机才能连上）');
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
            ? '内置服务启动失败'
            : _serviceFailureReason;
        _appendLog('内置服务启动失败：$_failureReason');
        return false;
      }
      final config = ref.read(webuiSidecarConfigProvider);
      final address = '${config.host}:${config.port}';
      if (mounted) {
        setState(() => _serviceAddress = address);
      }
      _appendLog('内置服务已就绪：$address');
      if (ref.read(tailscaleOptInProvider)) {
        await _runTailscaleInstall();
      } else {
        _appendLog('未勾选 Tailscale：跳过内网穿透（同一 Wi-Fi 下手机仍可直接连）');
      }
      return true;
    } catch (e) {
      _failureReason = '$e';
      _appendLog('启动服务异常: $e');
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
    _serviceFailureReason = '启动超时（30s 未就绪）';
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
    final TailscaleService service;
    try {
      service = ref.read(tailscaleServiceProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _tailscaleUnavailable = true);
      }
      _appendLog(WizardStrings.tailscaleUnavailable);
      return;
    }
    _tailscaleService = service;
    _appendLog('===> [4/5] 一起安装 Tailscale：静默安装 + 打开登录页 ...');
    try {
      await for (final status in service.installAndLogin()) {
        if (!mounted) return;
        setState(() => _tailscaleStatus = status);
        if (status.detail.isNotEmpty) {
          _appendLog('Tailscale: ${status.detail}');
        }
        if (status.isReady) {
          _appendLog('Tailscale 已就绪：${status.ipv4}');
          return;
        }
        if (status.state == TailscaleState.failed) {
          _appendLog(WizardStrings.tailscaleFailedHint);
          return;
        }
      }
    } catch (e) {
      _appendLog('Tailscale 安装异常：$e');
    }
  }

  /// Tailscale 三态轨的当前步（0 下载 / 1 静默安装 / 2 登录生成地址）。
  int _tailscaleStepIndex(TailscaleStatus status) {
    final progress = status.progress;
    switch (status.state) {
      case TailscaleState.ready:
      case TailscaleState.needsLogin:
        return WizardStrings.tailscaleSteps.length - 1;
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
      _appendLog('配对服务不可用：请稍后在「设置 → 连接」里用配对码接入');
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
        _pairingAddress = baseUrl;
        _pairingError = '';
      });
      _appendLog('配对码已生成，等待手机接入（10 分钟内有效）');
    } catch (e) {
      if (!mounted) return;
      setState(() => _pairingError = '${WizardStrings.pairingErrorPrefix}$e');
    }
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
    _appendLog('手机已连上：${accepted.deviceLabel}');
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
    final l10n = AppLocalizations.of(context);
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
        _appendLog('正在保存大模型配置到 WebUI...');
        await api.saveConfig(
          serverBaseUrl: 'http://127.0.0.1:8787',
          config: config,
        );
        _appendLog('模型配置已保存');
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
        _modelFormError = '保存配置失败: $e';
      });
      _appendLog('保存配置失败: $e');
    }
  }

  /// 写入并激活指向本机内置服务的连接，然后进入应用。
  Future<void> _finishWizard() async {
    try {
      const localUrl = 'http://127.0.0.1:8787';
      final connection = ServerConnection(
        id: uuidV4(),
        name: 'Localhost (8787)',
        baseUrl: localUrl,
        username: null,
        password: null,
        customHeaders: const {},
        createdAt: DateTime.now().toUtc(),
      );
      final saved = await ref
          .read(connectionsProvider.notifier)
          .upsert(connection);
      await ref.read(activeConnectionProvider.notifier).setActive(saved.id);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      _appendLog('写入本机连接失败: $e');
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
                              ? LightSurfaces.menuAction
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
                  ? const TextStyle(color: LightSurfaces.menuAction)
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
          onPressed: () => context.go('/onboarding'),
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
      const SizedBox(height: 16),
      _buildProgressRow(),
      const SizedBox(height: 14),
      _buildStepRail(),
      const SizedBox(height: 14),
      _buildCurrentStepCard(l10n),
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

  Widget _buildHeader(AppLocalizations l10n) {
    return Column(
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
    );
  }

  Widget _buildProgressRow() {
    final completed = _completedCount;
    final total = InstallStageKey.values.length;
    final progress = (completed / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              WizardStrings.progressText(completed, total),
              key: const ValueKey('wizard-progress-label'),
              style: TextStyle(
                fontSize: kFontCaption,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: kFontCaption,
                fontWeight: FontWeight.bold,
                color: LightSurfaces.resolve(
                  context,
                  LightSurfaces.textSecondary,
                  dark: secondaryText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.systemGrey5,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.userDetail,
                    dark: const Color(0xFF007AFF),
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepRail() {
    // 当前步不该显示成「已完成」：模型配置还挂在「启动服务」步里等用户操作时，
    // 该步的状态已是 success（4 步完成），若把 4 直接交给轨，第 4 个点会变绿、
    // 整条轨没有蓝点 —— 违背「当前步必须明显高亮」。故未整体完成前，完成数最多
    // 算到当前步之前（本批实测用例「安装推进…」锁住该行为）。
    final doneCount = _phase == GuidePhase.done
        ? _completedCount
        : _completedCount.clamp(0, _currentStepIndex);
    return HorizontalStepRail(
      labels: const [
        WizardStrings.stepPrereqs,
        WizardStrings.stepAgent,
        WizardStrings.stepDeps,
        WizardStrings.stepService,
        WizardStrings.stepPairing,
      ],
      currentIndex: _currentStepIndex,
      doneCount: doneCount,
      failedIndex: _failedStageIndex,
    );
  }

  /// 当前步详情卡（圆角 10 / 0.5px 描边 / 内距 13-14 / 18px 主色图标 + 标题 15
  /// + 副行 + 右侧状态），照设计稿 §5「当前步详情」。
  Widget _buildCurrentStepCard(AppLocalizations l10n) {
    final index = _currentStepIndex.clamp(
      0,
      InstallStageKey.values.length - 1,
    );
    final stage = InstallStageKey.values[index];
    final status = _stageStatuses[stage] ?? StageStatus.pending;
    final Color statusColor;
    switch (status) {
      case StageStatus.success:
        statusColor = statusGreenText.resolveFrom(context);
        break;
      case StageStatus.failed:
        statusColor = statusRedText.resolveFrom(context);
        break;
      case StageStatus.pending:
      case StageStatus.running:
        statusColor = _secondary;
        break;
    }
    return _card(
      key: const ValueKey('wizard-current-step-card'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _stepIcon(stage),
            size: 18,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.userDetail,
              dark: const Color(0xFF007AFF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stepTitle(stage),
                  key: const ValueKey('wizard-current-step-title'),
                  style: const TextStyle(
                    fontSize: kFontItemTitle,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _stepDesc(stage),
                  style: TextStyle(
                    // TODO(type): 设计稿 11.5，梯子无此档；本批按 kFontCaption(12)
                    fontSize: kFontCaption,
                    height: 1.45,
                    color: _secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _stepStatusText(status),
            key: const ValueKey('wizard-current-step-status'),
            style: TextStyle(fontSize: kFontCaption, color: statusColor),
          ),
        ],
      ),
    );
  }

  /// 当前步的附加内容（按步分派）。
  List<Widget> _buildCurrentStepBody(AppLocalizations l10n) {
    switch (InstallStageKey.values[_currentStepIndex]) {
      case InstallStageKey.prereqs:
        return _buildPrereqCheckBody();
      case InstallStageKey.service:
        return _buildServiceBody(l10n);
      case InstallStageKey.pairing:
        return _buildPairingBody();
      case InstallStageKey.agent:
      case InstallStageKey.agentDeps:
        return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // 首屏检查卡 + 网络受限提示（规格 C）
  // ---------------------------------------------------------------------------

  List<Widget> _buildPrereqCheckBody() {
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
              title: WizardStrings.checkWindows,
              value: WizardStrings.checkWindowsValue,
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-check-agent',
              icon: CupertinoIcons.hourglass,
              iconColor: _secondary,
              title: WizardStrings.checkAgent,
              value:
                  _stageStatuses[InstallStageKey.agent] == StageStatus.success
                  ? WizardStrings.checkAgentInstalled
                  : WizardStrings.checkAgentPending,
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-check-service',
              icon: CupertinoIcons.lock,
              iconColor: _secondary,
              title: WizardStrings.checkService,
              value: _serviceAddress.isEmpty
                  ? WizardStrings.checkServicePending
                  : WizardStrings.serviceRunning(
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
              title: WizardStrings.checkNetwork,
              value: _networkChecking
                  ? WizardStrings.networkChecking
                  : (_networkReachable
                        ? WizardStrings.networkNormal
                        : (_networkDetail.isEmpty
                              ? WizardStrings.networkFailed
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
        _buildNetworkWarningCard(),
      ],
    ];
  }

  Widget _buildNetworkWarningCard() {
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
                  WizardStrings.networkWarning,
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
                label: WizardStrings.networkRecheck,
                icon: CupertinoIcons.arrow_clockwise,
                onPressed: _recheckNetwork,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _filledButton(
                key: const ValueKey('wizard-network-continue-btn'),
                label: WizardStrings.networkContinue,
                onPressed: _continueDespiteNetwork,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          WizardStrings.networkSkipHint,
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
    final String serviceValue;
    final Color? serviceValueColor;
    if (_serviceAddress.isNotEmpty) {
      // 服务本身真的在跑 —— 无论步骤是否已 close，这一行都据实报「运行中」。
      serviceValue = WizardStrings.serviceRunning(
        _serviceAddress.split(':').first,
        int.tryParse(_serviceAddress.split(':').last) ?? port,
      );
      serviceValueColor = statusGreenText.resolveFrom(context);
    } else {
      switch (status) {
        case StageStatus.running:
          serviceValue = WizardStrings.serviceStarting;
          serviceValueColor = null;
          break;
        case StageStatus.failed:
          serviceValue = _serviceFailureReason.isEmpty
              ? WizardStrings.serviceStopped
              : _serviceFailureReason;
          serviceValueColor = statusRedText.resolveFrom(context);
          break;
        case StageStatus.pending:
        case StageStatus.success:
          serviceValue = WizardStrings.serviceStopped;
          serviceValueColor = null;
          break;
      }
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
              title: WizardStrings.lanTitle,
              value: _lanEnabled && host.isNotEmpty
                  ? WizardStrings.lanOn(host, port)
                  : WizardStrings.lanOff,
              valueColor: _lanEnabled
                  ? statusGreenText.resolveFrom(context)
                  : null,
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-credential-row',
              icon: CupertinoIcons.lock,
              iconColor: _secondary,
              title: WizardStrings.credentialTitle,
              value: WizardStrings.credentialValue,
            ),
            _rowDivider(),
            _tailscaleRow(),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-service-status-row',
              iconKey: 'wizard-service-status-icon',
              icon: _serviceAddress.isNotEmpty
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.hourglass,
              iconColor: _serviceAddress.isNotEmpty
                  ? statusGreenText.resolveFrom(context)
                  : _secondary,
              title: WizardStrings.serviceStatusTitle,
              value: serviceValue,
              valueColor: serviceValueColor,
            ),
          ],
        ),
      ),
      if (_tailscaleStatus != null) ...[
        const SizedBox(height: 12),
        _buildTailscaleProgressCard(_tailscaleStatus!),
      ],
      const SizedBox(height: 12),
      _noteCard(WizardStrings.tailscaleExempt),
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
  Widget _tailscaleRow() {
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
                  const Text(
                    WizardStrings.tailscaleTitle,
                    key: ValueKey('wizard-tailscale-unavailable'),
                    style: TextStyle(fontSize: kFontItemTitle),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    WizardStrings.tailscaleUnavailable,
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
                      const Flexible(
                        child: Text(
                          WizardStrings.tailscaleTitle,
                          style: TextStyle(fontSize: kFontItemTitle),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _badge(WizardStrings.tailscaleBadge),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    WizardStrings.tailscaleSub1,
                    style: TextStyle(
                      // TODO(type): 设计稿 11.5，梯子无此档；本批按 kFontCaption(12)
                      fontSize: kFontCaption,
                      height: 1.45,
                      color: _secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    WizardStrings.tailscaleSub2,
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
  Widget _buildTailscaleProgressCard(TailscaleStatus status) {
    final index = _tailscaleStepIndex(status);
    final done = status.isReady ? WizardStrings.tailscaleSteps.length : index;
    final String summary;
    if (status.isReady) {
      summary = '${WizardStrings.tailscaleReadyPrefix}${status.ipv4}';
    } else if (status.detail.isNotEmpty) {
      summary = status.detail;
    } else {
      summary = WizardStrings.tailscaleWorking;
    }
    return _card(
      key: const ValueKey('wizard-tailscale-progress-card'),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HorizontalStepRail(
            labels: WizardStrings.tailscaleSteps,
            currentIndex: index,
            doneCount: done,
            failedIndex: status.state == TailscaleState.failed ? index : null,
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
                        '${WizardStrings.tailscaleLoginHint}${status.loginUrl}',
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

  List<Widget> _buildPairingBody() {
    final accepted = _accepted;
    if (accepted != null) {
      return _buildPairedAcceptance(accepted);
    }
    return [
      const SizedBox(height: 12),
      _card(
        key: const ValueKey('wizard-pairing-card'),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: _pairingUnavailable
            ? _buildPairingUnavailable()
            : _buildPairingCode(),
      ),
    ];
  }

  Widget _buildPairingUnavailable() {
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
              const Text(
                WizardStrings.pairingUnavailable,
                key: ValueKey('wizard-pairing-unavailable'),
                style: TextStyle(
                  fontSize: kFontItemTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                WizardStrings.pairingUnavailableHint,
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

  Widget _buildPairingCode() {
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
              WizardStrings.pairingWaiting,
              key: const ValueKey('wizard-pairing-waiting'),
              style: TextStyle(fontSize: kFontCaption, color: _secondary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          WizardStrings.pairingHint,
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
            '${WizardStrings.pairingAddressPrefix}$_pairingAddress',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: kFontMicro, color: _secondary),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          WizardStrings.pairingTtl,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: kFontMicro, color: _secondary),
        ),
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
            label: WizardStrings.pairingRegenerate,
            icon: CupertinoIcons.arrow_clockwise,
            onPressed: _regeneratePairingCode,
          ),
        ),
      ],
    );
  }

  /// 验收态：对端已连上（设计稿 D5）。
  List<Widget> _buildPairedAcceptance(PairingAccepted accepted) {
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
              value: WizardStrings.pairedJustNow,
              valueColor: statusGreenText.resolveFrom(context),
            ),
            _rowDivider(),
            _statRow(
              titleKey: 'wizard-paired-host',
              icon: CupertinoIcons.desktopcomputer,
              iconColor: _secondary,
              title: deviceName.isEmpty
                  ? WizardStrings.checkWindows
                  : deviceName,
              value: WizardStrings.pairedService(host, port),
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
                '步骤失败: ${_failedStage != null ? _stepTitle(_failedStage!) : ""}',
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
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
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
            Container(
              height: 140,
              padding: const EdgeInsets.all(10),
              color: CupertinoColors.black,
              child: _logs.isEmpty
                  ? const Text(
                      '等待安装启动...',
                      style: TextStyle(
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
    );
  }

  /// 宽屏下按钮在内容列尾部自然滚动（设计稿 R1-B 口径）；窄屏给固定底栏。
  Widget _buildBottomBar(AppLocalizations l10n) {
    return _buildFooterActions(l10n);
  }

  Widget _buildFooterActions(AppLocalizations l10n) {
    if (_phase == GuidePhase.configuringModel) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                color: CupertinoTheme.brightnessOf(context) == Brightness.light
                    ? LightSurfaces.userDetail
                    : null,
                key: const ValueKey('install-guide-save-model-btn'),
                onPressed: _savingModel
                    ? null
                    : () => _submitModelConfigAndContinue(skip: false),
                child: _savingModel
                    ? CupertinoActivityIndicator(
                        color:
                            CupertinoTheme.brightnessOf(context) ==
                                Brightness.light
                            ? LightSurfaces.textSecondary
                            : null,
                      )
                    : Text(l10n.installGuideSaveAndContinue),
              ),
            ),
            const SizedBox(height: 6),
            CupertinoButton(
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
          ],
        ),
      );
    }
    if (_phase == GuidePhase.idle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            color: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? LightSurfaces.userDetail
                : null,
            key: const ValueKey('install-guide-start-btn'),
            onPressed: () => _startOrResumeInstallation(),
            child: Text(l10n.installGuideStartInstall),
          ),
        ),
      );
    }
    if (_phase == GuidePhase.installing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: CupertinoColors.systemGrey4,
            onPressed: null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 8),
                Text(
                  l10n.installGuideInstalling,
                  style: const TextStyle(color: CupertinoColors.black),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_phase == GuidePhase.pairing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            key: const ValueKey('wizard-pairing-skip-btn'),
            padding: EdgeInsets.zero,
            onPressed: _finishWizard,
            child: Text(
              WizardStrings.pairingSkip,
              style: TextStyle(fontSize: kFontButton, color: _secondary),
            ),
          ),
        ),
      );
    }
    if (_phase == GuidePhase.done) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            color: CupertinoTheme.brightnessOf(context) == Brightness.light
                ? LightSurfaces.userDetail
                : null,
            key: const ValueKey('wizard-pairing-finish-btn'),
            onPressed: _finishWizard,
            child: const Text(WizardStrings.pairedFinish),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

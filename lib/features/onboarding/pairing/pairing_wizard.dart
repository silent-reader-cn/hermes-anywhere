import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/widgets/nav_bar_hairline.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/connections/server_connection.dart';
import '../../../core/pairing/pairing_contract.dart';
import '../../../core/utils/uuid.dart';
import '../../../l10n/app_localizations.dart';
import '../widgets/wide_dual_pane.dart';
import 'pairing_strings.dart';
import 'pairing_style.dart';
import 'wizard_code_page.dart';
import 'wizard_discover_page.dart';
import 'wizard_download_page.dart';
import 'wizard_start_page.dart';

/// 手机端首启决策树的步骤（形态 B —— 非 Windows / 无内置包）。
enum PairingWizardStep {
  /// M1：先问「Hermes 跑在哪台电脑上？」
  start,

  /// M2：同一 Wi-Fi 自动发现。
  discover,

  /// M3：输入 6 位配对码。
  code,

  /// M4：还没装电脑端 → 下载引导。
  download,

  /// 兜底：旧远程表单（逐像素保留）。
  legacyForm,
}

/// 手机端首启引导宿主：M1→M2/M3/M4 决策树 + 旧远程表单兜底。
///
/// 分工：本件只管**流程**（步骤状态、导航栏、发现与兑换的编排、落地连接），
/// 四个屏各自只画自己的东西（见 `wizard_*_page.dart`）。
///
/// 与旧远程表单的关系：兜底步骤渲染调用方传进来的 [legacyNarrow] / [legacyWide]，
/// 那两块由 `onboarding_page.dart` 原样提供（字段 / placeholder / health 检查 /
/// 密码校验 / 提交逻辑一行未改），故兜底入口与改造前的首屏像素一致。
class PairingWizard extends ConsumerStatefulWidget {
  const PairingWizard({
    super.key,
    required this.legacyNarrow,
    required this.legacyWide,
  });

  /// 兜底（窄屏）旧远程表整体。
  final Widget Function(AppLocalizations l10n) legacyNarrow;

  /// 兜底（宽屏右列）旧远程表整体。
  final Widget Function(AppLocalizations l10n) legacyWide;

  @override
  ConsumerState<PairingWizard> createState() => _PairingWizardState();
}

class _PairingWizardState extends ConsumerState<PairingWizard> {
  /// 发现超时（设计稿 / 任务口径：4s 内没扫到就按「没找到」处理）。
  static const Duration _discoverTimeout = Duration(seconds: 4);

  PairingWizardStep _step = PairingWizardStep.start;

  /// 从发现页带进配对码页的候选（跨网入口为空 → 提交时先发现一次）。
  PairingCandidate? _candidate;

  /// 配对码页的返回目标。
  PairingWizardStep _codeBackTarget = PairingWizardStep.start;

  // ───────────────────────────────────────────────────────────────────────────
  // 配对客户端（provider 未注入即降级，不抛到界面上）
  // ───────────────────────────────────────────────────────────────────────────

  /// 取配对客户端；provider 未注入（`UnimplementedError` / Riverpod 的
  /// `ProviderException` 包装）或实现方在构造期抛错时返回 null。
  ///
  /// 这是**首启不崩**的兜底：没有实现时按「没找到配对服务」降级（见 [_discover]）。
  PairingClient? get _client {
    try {
      return ref.read(pairingClientProvider);
    } catch (_) {
      return null;
    }
  }

  /// 局域网发现；4s 超时、扫到 0 台、实现抛错、provider 未注入一律归为「空结果」。
  Future<List<PairingCandidate>> _discover() async {
    final client = _client;
    if (client == null) return const [];
    try {
      return await client.discover(timeout: _discoverTimeout);
    } catch (_) {
      return const [];
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 流程编排
  // ───────────────────────────────────────────────────────────────────────────

  void _goTo(PairingWizardStep step) => setState(() => _step = step);

  void _onSameWifi() {
    _candidate = null;
    _goTo(PairingWizardStep.discover);
  }

  void _onElsewhere() {
    _candidate = null;
    _codeBackTarget = PairingWizardStep.start;
    _goTo(PairingWizardStep.code);
  }

  void _onNotInstalled() => _goTo(PairingWizardStep.download);

  void _onManualAddress() => _goTo(PairingWizardStep.legacyForm);

  void _onPairCandidate(PairingCandidate candidate) {
    _candidate = candidate;
    _codeBackTarget = PairingWizardStep.discover;
    _goTo(PairingWizardStep.code);
  }

  /// 配对码页的返回目标；null = 本步无返回（M1 / 兜底表单）。
  ///
  /// 兜底表单不给返回箭头：设计目标是「旧远程表单逐像素不变」，加箭头即改动像素。
  PairingWizardStep? get _backTarget => switch (_step) {
    PairingWizardStep.discover || PairingWizardStep.download => PairingWizardStep.start,
    PairingWizardStep.code => _codeBackTarget,
    PairingWizardStep.start || PairingWizardStep.legacyForm => null,
  };

  void _goBack() {
    final target = _backTarget;
    if (target != null) _goTo(target);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 兑换配对码 → 落地连接
  // ───────────────────────────────────────────────────────────────────────────

  /// 解析本机要连的**配对服务地址**：优先用发现页选中的候选，其次就地发现一次。
  ///
  /// 跨网入口（M1 卡片②）不进发现页，故此处补一次发现；扫不到就没有可兑换的
  /// 地址，按 `unavailable` 档给文案（不是无声失败）。
  Future<String?> _resolvePairingBaseUrl() async {
    final selected = _candidate?.pairingBaseUrl;
    if (selected != null && selected.isNotEmpty) return selected;
    final found = await _discover();
    if (found.isEmpty) return null;
    _candidate = found.first;
    return found.first.pairingBaseUrl;
  }

  /// 提交配对码；返回错误文案（null = 成功或 cancelled 静默）。
  Future<String?> _submitCode(String code) async {
    final client = _client;
    if (client == null) return PairingStrings.m3ErrorUnavailable;
    final baseUrl = await _resolvePairingBaseUrl();
    if (baseUrl == null) return PairingStrings.m3ErrorUnavailable;
    if (!mounted) return null;
    try {
      final credentials = await client.redeem(
        pairingBaseUrl: baseUrl,
        code: code,
      );
      if (!mounted) return null;
      await _saveCredentials(credentials);
      return null;
    } on PairingException catch (error) {
      // cancelled：用户主动取消 / 对端关闭 —— 静默（空串 = 无文案）。
      return PairingStrings.pairingFailureMessage(error.reason);
    } catch (_) {
      return PairingStrings.m3ErrorNetwork;
    }
  }

  /// 兑换成功 → upsert 连接 + 置为 active + 进会话列表（与旧远程表单同一条落地链）。
  Future<void> _saveCredentials(PairingCredentials credentials) async {
    final host = Uri.tryParse(credentials.baseUrl)?.host;
    final connection = ServerConnection(
      id: uuidV4(),
      name: host == null || host.isEmpty ? credentials.baseUrl : host,
      baseUrl: credentials.baseUrl,
      username: null, // hermes-webui 认证只认密码，无用户名概念
      password: credentials.password.isEmpty ? null : credentials.password,
      customHeaders: const {},
      createdAt: DateTime.now().toUtc(),
    );
    final saved = await ref
        .read(connectionsProvider.notifier)
        .upsert(connection);
    await ref.read(activeConnectionProvider.notifier).setActive(saved.id);
    if (!mounted) return;
    context.go('/');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI
  // ───────────────────────────────────────────────────────────────────────────

  String _navTitle(AppLocalizations l10n) => switch (_step) {
    PairingWizardStep.start => PairingStrings.navStart,
    PairingWizardStep.discover => PairingStrings.navSameWifi,
    PairingWizardStep.code => PairingStrings.navPair,
    PairingWizardStep.download => PairingStrings.navDownload,
    // 兜底表单沿用改造前的导航标题（逐像素不变的口径之一）。
    PairingWizardStep.legacyForm => l10n.connectServer,
  };

  Widget _stepPage(AppLocalizations l10n) => switch (_step) {
    PairingWizardStep.start => WizardStartPage(
      onSameWifi: _onSameWifi,
      onElsewhere: _onElsewhere,
      onNotInstalled: _onNotInstalled,
      onManualAddress: _onManualAddress,
    ),
    PairingWizardStep.discover => WizardDiscoverPage(
      discover: _discover,
      onPair: _onPairCandidate,
      onManualAddress: _onManualAddress,
    ),
    PairingWizardStep.code => WizardCodePage(submit: _submitCode),
    PairingWizardStep.download => const WizardDownloadPage(),
    PairingWizardStep.legacyForm => widget.legacyNarrow(l10n),
  };

  /// 宽屏右列：决策树四屏与窄屏同一棵树（列宽由 WideDualPane 限 460）；
  /// 兜底表单则用调用方给的宽屏版本（与改造前的宽屏渲染同源）。
  Widget _widePage(AppLocalizations l10n) => _step == PairingWizardStep.legacyForm
      ? widget.legacyWide(l10n)
      : _stepPage(l10n);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final backTarget = _backTarget;
    return CupertinoPageScaffold(
      backgroundColor: isLight ? LightSurfaces.page : null,
      navigationBar: CupertinoNavigationBar(
        border: null,
        bottom: const NavBarHairline(),
        backgroundColor: isLight ? LightSurfaces.page : null,
        leading: backTarget == null
            ? null
            : CupertinoButton(
                key: const ValueKey('pairing-nav-back'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
                onPressed: _goBack,
                child: Icon(
                  CupertinoIcons.back,
                  size: 19,
                  color: PairingColors.primary(context),
                ),
              ),
        middle: Text(_navTitle(l10n)),
      ),
      child: SafeArea(
        child: WideDualPane(
          wideChild: _widePage(l10n),
          child: _stepPage(l10n),
        ),
      ),
    );
  }
}

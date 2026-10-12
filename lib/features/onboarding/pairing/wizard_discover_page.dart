import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../core/pairing/pairing_contract.dart';
import '../../../l10n/app_localizations.dart';
import 'pairing_style.dart';

/// M2 · 同一 Wi-Fi 自动发现（设计稿 §1 第二屏）。
///
/// 进入即调一次 [discover]（超时由调用方给定，本例 4s）：
/// - 拿到 ≥1 台 → 发现卡（机名 + 「内置服务 · 端口 · 同一网络」 + 「配对」小按钮）；
/// - 空列表 / 实现抛错 / provider 未注入（调用方已降级成空列表）→ 页大标题换成
///   「没找到你的电脑」，三条自检与「手动输入地址」依旧在场。
class WizardDiscoverPage extends StatefulWidget {
  const WizardDiscoverPage({
    super.key,
    required this.discover,
    required this.onPair,
    required this.onManualAddress,
  });

  /// 发现回调（返回空列表即「没找到」；不抛异常）。
  final Future<List<PairingCandidate>> Function() discover;

  /// 选中一台候选 → 进配对码页。
  final void Function(PairingCandidate candidate) onPair;

  /// 兜底：手动输入地址 → 旧远程表单。
  final VoidCallback onManualAddress;

  @override
  State<WizardDiscoverPage> createState() => _WizardDiscoverPageState();
}

class _WizardDiscoverPageState extends State<WizardDiscoverPage> {
  bool _searching = true;
  List<PairingCandidate> _candidates = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final found = await widget.discover();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _candidates = found;
    });
  }

  /// 发现卡副行：候选带了 WebUI 地址就按其实端口写，否则用设计稿默认口径。
  String _metaOf(AppLocalizations l10n, PairingCandidate candidate) {
    final uri = Uri.tryParse(candidate.webuiBaseUrl);
    if (uri != null && uri.hasPort) {
      return l10n.pairingDiscoverCandidateMetaOnPort(uri.port);
    }
    return l10n.pairingDiscoverCandidateMetaDefault;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nothingFound = !_searching && _candidates.isEmpty;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PairingPageIntro(
          title: nothingFound
              ? l10n.pairingDiscoverTitleEmpty
              : l10n.pairingDiscoverTitleSearching,
          subtitle: l10n.pairingDiscoverSubtitle,
        ),
        const _DiscoveryRadar(),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PairingMetrics.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              if (_candidates.isNotEmpty)
                PairingCard(
                  children: [
                    for (final candidate in _candidates)
                      PairingOptionRow(
                        key: ValueKey(
                          'pairing-candidate-${candidate.installId}',
                        ),
                        icon: CupertinoIcons.device_desktop,
                        title: candidate.deviceName,
                        description: _metaOf(l10n, candidate),
                        trailing: PairingSmallButton(
                          label: l10n.pairingDiscoverPairAction,
                          onPressed: () => widget.onPair(candidate),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              PairingMicroText(l10n.pairingDiscoverChecklistTitle, bold: true),
              const SizedBox(height: 6),
              PairingMicroText(
                '${l10n.pairingDiscoverCheck1}\n'
                '${l10n.pairingDiscoverCheck2}\n'
                '${l10n.pairingDiscoverCheck3}',
              ),
              const SizedBox(height: 16),
              PairingTextLink(
                key: const ValueKey('pairing-discover-manual-address'),
                label: l10n.pairingDiscoverManualEntryLink,
                onTap: widget.onManualAddress,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

/// 同心圆雷达：外圈 160 / 内圈 116 / 中心 64 白圆 + 26 主色 wifi 图标（全部居中）。
class _DiscoveryRadar extends StatelessWidget {
  const _DiscoveryRadar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PairingMetrics.radarBlockHeight,
      child: Stack(
        // 设计稿里外圈 160 超出本块 150 高度（底部 10 被后续卡片压住），
        // 故这里不裁剪，保持同一几何。
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: _ring(context, PairingMetrics.radarOuter),
          ),
          Positioned(
            top: 22,
            child: _ring(context, PairingMetrics.radarInner),
          ),
          Positioned(top: 48, child: _center(context)),
        ],
      ),
    );
  }

  Widget _ring(BuildContext context, double diameter) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: PairingColors.radarRing(context),
        width: 1,
      ),
    ),
  );

  Widget _center(BuildContext context) => Container(
    width: PairingMetrics.radarCenter,
    height: PairingMetrics.radarCenter,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: PairingColors.card(context),
      border: Border.all(
        color: PairingColors.cardBorder(context),
        width: 0.5,
      ),
    ),
    child: Icon(
      CupertinoIcons.wifi,
      size: PairingMetrics.radarIconSize,
      color: PairingColors.primary(context),
    ),
  );
}

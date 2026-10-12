import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../core/utils/safe_clipboard.dart';
import '../../../l10n/app_localizations.dart';
import 'pairing_constants.dart';
import 'pairing_style.dart';

/// M4 · 还没装电脑端 → 下载桌面版引导（设计稿 §1 第四屏）。
///
/// 三步行卡片 + 「复制下载链接」（走既有 [SafeClipboard]，不引新依赖）+
/// 小字短链 + 跨设备搬运微文案。
class WizardDownloadPage extends StatefulWidget {
  const WizardDownloadPage({super.key});

  @override
  State<WizardDownloadPage> createState() => _WizardDownloadPageState();
}

class _WizardDownloadPageState extends State<WizardDownloadPage> {
  bool _copied = false;

  Future<void> _copyLink() async {
    final result = await SafeClipboard.copyOrSave(
      hermesDownloadUrl,
      fileNamePrefix: 'hermes_download_link',
    );
    if (!mounted) return;
    setState(() => _copied = result.isClipboard || result.isFileSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PairingPageIntro(
          title: l10n.pairingDownloadTitle,
          subtitle: l10n.pairingDownloadSubtitle,
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PairingMetrics.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PairingCard(
                children: [
                  PairingOptionRow(
                    icon: CupertinoIcons.arrow_down_circle,
                    iconSize: PairingMetrics.stepIconSize,
                    iconColor: PairingColors.success(context),
                    title: l10n.pairingDownloadStep1Title,
                    description: l10n.pairingDownloadStep1Desc,
                  ),
                  PairingOptionRow(
                    icon: CupertinoIcons.device_desktop,
                    iconSize: PairingMetrics.stepIconSize,
                    iconColor: PairingColors.success(context),
                    title: l10n.pairingDownloadStep2Title,
                    description: l10n.pairingDownloadStep2Desc,
                  ),
                  PairingOptionRow(
                    icon: CupertinoIcons.checkmark_circle_fill,
                    iconSize: PairingMetrics.stepIconSize,
                    iconColor: PairingColors.success(context),
                    title: l10n.pairingDownloadStep3Title,
                    description: l10n.pairingDownloadStep3Desc,
                  ),
                ],
              ),
              const SizedBox(height: 26),
              PairingActionButton(
                key: const ValueKey('pairing-download-copy-link'),
                label: l10n.pairingDownloadCopyLink,
                icon: CupertinoIcons.doc_on_doc,
                onPressed: () => unawaited(_copyLink()),
              ),
              if (_copied) ...[
                const SizedBox(height: 8),
                PairingMicroText(
                  l10n.pairingDownloadLinkCopied,
                  align: TextAlign.center,
                  color: PairingColors.success(context),
                ),
              ],
              const SizedBox(height: 12),
              PairingMicroText(
                l10n.pairingDownloadLinkLabel,
                align: TextAlign.center,
              ),
              const SizedBox(height: 14),
              PairingMicroText(
                l10n.pairingDownloadFootnote,
                align: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

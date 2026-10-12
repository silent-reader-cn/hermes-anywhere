import 'package:flutter/cupertino.dart';

import 'pairing_strings.dart';
import 'pairing_style.dart';

/// M1 · 第一问「Hermes 跑在哪台电脑上？」（设计稿 §1 第一屏）。
///
/// 三张卡各分流一步；底部次级链接给出「我有服务器地址」兜底（旧远程表单）；
/// 最底部是绝对定位的微文案（长屏钉在底部 26，短屏随内容滚动）。
class WizardStartPage extends StatelessWidget {
  const WizardStartPage({
    super.key,
    required this.onSameWifi,
    required this.onElsewhere,
    required this.onNotInstalled,
    required this.onManualAddress,
  });

  /// 卡片①：同一 Wi-Fi → 自动发现。
  final VoidCallback onSameWifi;

  /// 卡片②：电脑在别处 → 直接进配对码页（跨网）。
  final VoidCallback onElsewhere;

  /// 卡片③：还没装桌面版 → 下载引导页。
  final VoidCallback onNotInstalled;

  /// 底部链接：我有服务器地址 → 旧远程表单。
  final VoidCallback onManualAddress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const PairingPageIntro(
                title: PairingStrings.m1Title,
                subtitle: PairingStrings.m1Subtitle,
              ),
              const SizedBox(height: PairingMetrics.titleToContent),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PairingMetrics.pagePadding,
                ),
                child: PairingCard(
                  children: [
                    PairingOptionRow(
                      key: const ValueKey('pairing-start-same-wifi'),
                      icon: CupertinoIcons.wifi,
                      title: PairingStrings.m1CardSameWifiTitle,
                      description: PairingStrings.m1CardSameWifiDesc,
                      trailing: const PairingChevron(),
                      onTap: onSameWifi,
                    ),
                    PairingOptionRow(
                      key: const ValueKey('pairing-start-elsewhere'),
                      icon: CupertinoIcons.qrcode,
                      title: PairingStrings.m1CardElsewhereTitle,
                      description: PairingStrings.m1CardElsewhereDesc,
                      trailing: const PairingChevron(),
                      onTap: onElsewhere,
                    ),
                    PairingOptionRow(
                      key: const ValueKey('pairing-start-not-installed'),
                      icon: CupertinoIcons.device_desktop,
                      title: PairingStrings.m1CardNotInstalledTitle,
                      description: PairingStrings.m1CardNotInstalledDesc,
                      trailing: const PairingChevron(),
                      onTap: onNotInstalled,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PairingMetrics.pagePadding,
                ),
                child: PairingTextLink(
                  key: const ValueKey('pairing-start-manual-address'),
                  label: PairingStrings.m1ManualEntryLink,
                  onTap: onManualAddress,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            PairingMetrics.pagePadding,
            8,
            PairingMetrics.pagePadding,
            26,
          ),
          child: PairingMicroText(
            PairingStrings.m1FooterNote,
            align: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

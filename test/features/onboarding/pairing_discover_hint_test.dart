import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/features/onboarding/pairing/wizard_discover_page.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// 本批（2026-10-12）新增：Windows 防火墙「首次放行」引导的用例。
//
// 覆盖两件事：
//   1) l10n 契约：新增两键（`pairingDiscoverCheck4` / `installWizardFirewallAllowHint`）
//      中英双语都在、中文为定稿原文、**四串里都不出现 VPN 字样**（仓内敏感措辞口径）；
//      同时钉住第 1~3 条自检原文不动（`pairing_wizard_test.dart` 就在断言这三条，
//      本批不许回退，故新文案只新增、不改写旧行）。
//   2) 手机端 M2 发现页：「没找到」态下四条自检在同一段文本内渲染，第 4 条点名
//      Windows 防火墙与「允许」。
//
// 桌面端那条提示由本批的金照（`install_guide_tailscale_step_*`，「启动服务」步）
// 连同 `install_guide_page_test.dart` 的既有用例一起覆盖 —— 本文件不再另造一整套
// 安装向导假件（会与那边重复且更脆）。
// ---------------------------------------------------------------------------

void main() {
  group('l10n 新键 · 防火墙首次放行', () {
    const zh = AppLocalizations(Locale('zh'));
    const en = AppLocalizations(Locale('en'));

    test('手机端自检第 4 条（中文）= 定稿原文', () {
      expect(
        zh.pairingDiscoverCheck4,
        '4. 检查电脑的 Windows 防火墙是否放行 8787（首次运行可能弹一次询问，请点「允许」）',
      );
    });

    test('手机端自检第 4 条（英文）自然成句、与第 3 条同句式', () {
      final text = en.pairingDiscoverCheck4;
      expect(text.startsWith('4. Check that'), isTrue);
      expect(text.contains('Windows Firewall'), isTrue);
      expect(text.contains('8787'), isTrue);
      expect(text.contains('first run'), isTrue);
      expect(text.contains('"Allow"'), isTrue);
    });

    test('桌面端向导提示（中文）= 定稿原文', () {
      expect(
        zh.installWizardFirewallAllowHint,
        '首次运行 Windows 可能弹一次网络访问询问，请点「允许」——否则手机连不上。',
      );
    });

    test('桌面端向导提示（英文）点出 Allow 与「连不上」', () {
      final text = en.installWizardFirewallAllowHint;
      expect(text.contains('Windows'), isTrue);
      expect(text.contains('"Allow"'), isTrue);
      expect(text.toLowerCase().contains('connect'), isTrue);
    });

    test('两条新键（中英四串）都不出现 VPN 字样', () {
      final values = <String>[
        zh.pairingDiscoverCheck4,
        en.pairingDiscoverCheck4,
        zh.installWizardFirewallAllowHint,
        en.installWizardFirewallAllowHint,
      ];
      for (final value in values) {
        expect(value.toUpperCase().contains('VPN'), isFalse, reason: value);
      }
    });

    test('第 1~3 条自检原文保持不动（另一路的断言依赖）', () {
      expect(zh.pairingDiscoverCheck1, '1. 确认电脑上的 Hermes 正在运行');
      expect(zh.pairingDiscoverCheck2, '2. 确认两台设备连的是同一个 Wi-Fi');
      expect(zh.pairingDiscoverCheck3, '3. 检查电脑防火墙是否放行 8787');
      expect(zh.pairingDiscoverChecklistTitle, '没找到？');
    });
  });

  group('M2 发现页 · 自检四条', () {
    /// 直接挂发现页（空候选 = 「没找到」态），只提供本页需要的本地化。
    ///
    /// 委托集照抄仓内既有能跑中文的工装（`test/app/widgets/hermes_dialog_test.dart`、
    /// `test/core/update/apk_installer_extra_test.dart` 同款，与 `lib/app/app.dart` 同源）：
    /// `GlobalCupertinoLocalizations` 才支持 zh，少了它 `CupertinoApp` 会在 debug 期抛
    /// 「zh 不被本地化委托支持」并把用例判红（英文档不报，正好印证）。
    Future<void> pumpDiscover(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(
        CupertinoApp(
          locale: locale,
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: WizardDiscoverPage(
            discover: () async => const <PairingCandidate>[],
            onPair: (_) {},
            onManualAddress: () {},
          ),
        ),
      );
      // 首帧 + 发现回调落地（空列表 → 页大标题换「没找到你的电脑」）。
      await tester.pump();
      await tester.pump();
    }

    testWidgets('中文：四条自检同段渲染，末条点名 Windows 防火墙 + 「允许」', (tester) async {
      await pumpDiscover(tester, const Locale('zh'));

      expect(find.text('没找到你的电脑'), findsOneWidget);
      expect(find.text('正在找你的电脑'), findsNothing);

      final checklist = tester.widget<Text>(
        find.textContaining('1. 确认电脑上的 Hermes 正在运行'),
      );
      final lines = checklist.data!.split('\n');
      expect(lines.length, 4);
      expect(
        lines.last,
        '4. 检查电脑的 Windows 防火墙是否放行 8787（首次运行可能弹一次询问，请点「允许」）',
      );
      expect(lines.last.contains('Windows 防火墙'), isTrue);
      expect(lines.last.contains('「允许」'), isTrue);
      expect(checklist.data!.toUpperCase().contains('VPN'), isFalse);
    });

    testWidgets('英文：四条自检同段渲染，末条为 Windows Firewall 行', (tester) async {
      await pumpDiscover(tester, const Locale('en'));

      expect(find.text('No computer found'), findsOneWidget);

      final checklist = tester.widget<Text>(
        find.textContaining('1. Make sure Hermes is running on the computer'),
      );
      final lines = checklist.data!.split('\n');
      expect(lines.length, 4);
      expect(lines.last.contains('Windows Firewall'), isTrue);
      expect(lines.last.contains('"Allow"'), isTrue);
      expect(checklist.data!.toUpperCase().contains('VPN'), isFalse);
    });
  });
}

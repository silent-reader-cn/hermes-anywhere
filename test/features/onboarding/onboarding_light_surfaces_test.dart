import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/status_colors.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/onboarding/widgets/builtin_tab.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

class _MissingAgent extends AgentEnvPresentNotifier {
  @override
  FutureOr<bool> build() => false;
}

class _PendingHealthApi extends FakeOnboardingLoginApi {
  final response = Completer<HealthResponse>();

  @override
  Future<HealthResponse> health() => response.future;
}

class _StoppedSidecar extends WebuiSidecarController {
  @override
  SidecarState build() => SidecarState.initial;
}

class _DemoConfig extends WebuiSidecarConfigController {
  @override
  SidecarConfig build() => const SidecarConfig(password: 'demo-password');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'connection form remains readable with $brightness, high contrast $highContrast',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(
                disableAnimations: true,
                highContrast: highContrast,
              );
          addTearDown(tester.view.reset);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final api = _PendingHealthApi();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                bundledWebuiAvailableProvider.overrideWithValue(false),
                onboardingApiFactoryProvider.overrideWithValue((_, _) => api),
              ],
              child: CupertinoApp(
                theme: buildCupertinoTheme(brightness),
                home: const OnboardingPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // 首启已改版为决策树（M1）：进兜底入口「我有服务器地址」才回到这张
          // 旧远程表单（表单本身与改造前逐像素一致 —— 见本批交付报告的取证）。
          await tester.tap(
            find.byKey(const ValueKey('pairing-start-manual-address')),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(OnboardingPage));
          final l10n = AppLocalizations.of(context);
          final description = tester.widget<Text>(
            find.text(l10n.inputServerAddressHint),
          );
          final url = tester.widget<CupertinoTextField>(
            find.byKey(const ValueKey('onboarding-url')),
          );
          final button = tester.widget<CupertinoButton>(
            find.byKey(const ValueKey('onboarding-connect')),
          );

          if (brightness == Brightness.light) {
            expect(description.style!.color, LightSurfaces.textSecondary);
            expect(
              _contrast(description.style!.color!, LightSurfaces.page),
              greaterThanOrEqualTo(4.5),
            );
            expect(url.decoration!.color, LightSurfaces.card);
            expect(url.decoration!.border!.top.color, LightSurfaces.cardBorder);
            expect(
              _contrast(url.placeholderStyle!.color!, url.decoration!.color!),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              _contrast(CupertinoColors.white, button.color!),
              greaterThanOrEqualTo(4.5),
            );
          } else {
            expect(
              description.style!.color,
              secondaryText.resolveFrom(context),
            );
            expect(url.decoration, const CupertinoTextField().decoration);
            expect(
              url.placeholderStyle,
              const CupertinoTextField().placeholderStyle,
            );
            expect(button.color, isNull);
          }

          // The password field appears only after the existing health/auth flow.
          await tester.enterText(
            find.byKey(const ValueKey('onboarding-url')),
            'https://hermes.example.com',
          );
          await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
          await tester.pump();
          final busyButton = tester.widget<CupertinoButton>(
            find.byKey(const ValueKey('onboarding-connect')),
          );
          final spinner = busyButton.child as CupertinoActivityIndicator;
          expect(busyButton.onPressed, isNull);
          if (brightness == Brightness.light) {
            // A busy filled button uses the SDK disabled fill, not its blue color.
            for (final surface in [LightSurfaces.card, LightSurfaces.page]) {
              final disabledFill = Color.alphaBlend(
                CupertinoDynamicColor.resolve(
                  busyButton.disabledColor,
                  context,
                ),
                surface,
              );
              expect(
                _contrast(spinner.color!, disabledFill),
                greaterThanOrEqualTo(3),
              );
            }
          } else {
            expect(spinner.color, isNull);
          }
          api.response.complete(const HealthResponse(status: 'ok'));
          await tester.pumpAndSettle();
          final password = tester.widget<CupertinoTextField>(
            find.byKey(const ValueKey('onboarding-password')),
          );
          expect(password.decoration, url.decoration);
          expect(password.placeholderStyle, url.placeholderStyle);
          expect(password.obscureText, isTrue);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }

    testWidgets('missing agent actions and warning surface $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bundledWebuiAvailableProvider.overrideWithValue(true),
            connectionStoreProvider.overrideWithValue(
              ConnectionStore(storage: InMemorySecureStorage()),
            ),
            agentEnvPresentProvider.overrideWith(_MissingAgent.new),
            webuiSidecarControllerProvider.overrideWith(_StoppedSidecar.new),
            webuiSidecarConfigProvider.overrideWith(_DemoConfig.new),
          ],
          child: CupertinoApp(
            theme: buildCupertinoTheme(brightness),
            home: const CupertinoPageScaffold(child: BuiltinTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(BuiltinTab));
      final iconCircle = tester.widget<Container>(
        find.byKey(const ValueKey('onboarding-missing-agent-icon')),
      );
      final circleColor = (iconCircle.decoration! as BoxDecoration).color!;
      final warningIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('onboarding-missing-agent-icon')),
          matching: find.byType(Icon),
        ),
      );
      final install = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-install-agent-btn')),
      );
      final recheck = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-recheck-agent-btn')),
      );
      // 图标色恒为语义橙（深色档底圈是半透明橙，无法直接算对比度，故锁色值）
      expect(warningIcon.color, statusOrangeText.resolveFrom(context));
      if (brightness == Brightness.light) {
        // 琥珀底圆：浅色档取 token 的 tintWarning，图标对底圈仍需 ≥4.5
        expect(circleColor, LightSurfaces.tintWarning);
        expect(
          _contrast(statusOrangeText.resolveFrom(context), circleColor),
          greaterThanOrEqualTo(4.5),
        );
        // 主按钮：白字压主色
        expect(
          _contrast(CupertinoColors.white, install.color!),
          greaterThanOrEqualTo(4.5),
        );
      } else {
        expect(
          circleColor,
          CupertinoColors.systemOrange
              .resolveFrom(context)
              .withValues(alpha: 0.12),
        );
        // 深色档主按钮交给 Cupertino 默认（与全仓暗色主按钮同口径）
        expect(install.color, isNull);
      }
      // 次按钮是无底文字按钮（不再是灰底方块），必须真的存在且可点
      expect(recheck.color, isNull);
      expect(recheck.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

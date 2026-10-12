import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/pairing/pairing_client.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/core/pairing/pairing_runtime_providers.dart';
import 'package:hermes_ui/core/pairing/pairing_service.dart';
import 'package:hermes_ui/core/tailscale/tailscale_contract.dart';
import 'package:hermes_ui/core/tailscale/tailscale_service.dart';

void main() {
  group('契约注入点的默认行为', () {
    test('未覆盖时三个注入点都明确抛 UnimplementedError（不会静默走空实现）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(() => container.read(pairingServiceProvider), throwsUnimplementedError);
      expect(() => container.read(pairingClientProvider), throwsUnimplementedError);
      expect(
        () => container.read(tailscaleServiceProvider),
        throwsUnimplementedError,
      );
    });
  });

  group('pairingRuntimeOverrides', () {
    test('把两个配对注入点指向真实实现，且同一容器内实例稳定', () {
      final container = ProviderContainer(
        overrides: pairingRuntimeOverrides(includeTailscale: false),
      );
      addTearDown(container.dispose);

      final service = container.read(pairingServiceProvider);
      expect(service, isA<DesktopPairingService>());
      expect(
        identical(container.read(pairingServiceProvider), service),
        isTrue,
        reason: 'provider 不应每次读取都新建 socket 服务实例',
      );

      final client = container.read(pairingClientProvider);
      expect(client, isA<MobilePairingClient>());
      expect(identical(container.read(pairingClientProvider), client), isTrue);

      // includeTailscale: false → Tailscale 注入点保持「未覆盖即抛错」。
      expect(
        () => container.read(tailscaleServiceProvider),
        throwsUnimplementedError,
      );
    });

    test('includeTailscale: true（默认）时 Tailscale 注入点指向真实实现', () {
      final container = ProviderContainer(overrides: pairingRuntimeOverrides());
      addTearDown(container.dispose);

      expect(
        container.read(tailscaleServiceProvider),
        isA<DesktopTailscaleService>(),
      );
    });

    test('容器销毁时释放配对服务（socket 关闭、current 归零）', () async {
      final container = ProviderContainer(
        overrides: pairingRuntimeOverrides(includeTailscale: false),
      );
      final service = container.read(pairingServiceProvider) as DesktopPairingService;

      await service.start(
        baseUrl: 'http://192.168.1.7:8787',
        password: 'pw',
        installId: 'i-1',
        ttl: const Duration(minutes: 10),
      );
      expect(service.current, isNotNull);

      container.dispose();
      // onDispose 走 unawaited(stop())：等一轮事件循环让关闭完成。
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.current, isNull);
      expect(service.pairingEndpoint, isNull);
    });
  });
}

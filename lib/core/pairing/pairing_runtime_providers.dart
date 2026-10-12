/// 配对域 + Tailscale 的**真实实现** provider 覆盖入口。
///
/// 为什么需要这个文件：`pairing_contract.dart` / `tailscale_contract.dart` 里的注入点
/// 默认「未覆盖即抛 UnimplementedError」—— 这是刻意的，让忘记注入的场景立刻炸而不是
/// 静默走空实现。真实实现只应在一个地方被点亮，即 App 启动时的 `ProviderScope`：
///
/// ```dart
/// ProviderScope(
///   overrides: pairingRuntimeOverrides(),
///   child: const HermesApp(),
/// );
/// ```
///
/// 单测/其他平台若不调用它，读到注入点仍然是「未覆盖」的明确报错，不会被真实实现
/// （起 socket、跑 winget）意外拖下水。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tailscale/tailscale_contract.dart';
import '../tailscale/tailscale_service.dart';
import 'pairing_client.dart';
import 'pairing_contract.dart';
import 'pairing_service.dart';

/// 桌面端配对服务（真实实现）。惰性创建；容器销毁时关闭 socket 与事件流。
final desktopPairingServiceProvider = Provider<PairingService>((ref) {
  final service = DesktopPairingService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// 手机端配对客户端（真实实现：UDP 广播发现 + HTTP 兑换）。
final mobilePairingClientProvider = Provider<PairingClient>(
  (ref) => MobilePairingClient(),
);

/// 启动时可用的覆盖列表。
///
/// 三个注入点各自指向对应的真实实现；`includeTailscale: false` 用于
/// 不需要内网穿透入口的构建（例如手机端，装不了也装不上 Tailscale）。
List<Override> pairingRuntimeOverrides({bool includeTailscale = true}) {
  return <Override>[
    pairingServiceProvider.overrideWith(
      (ref) => ref.watch(desktopPairingServiceProvider),
    ),
    pairingClientProvider.overrideWith(
      (ref) => ref.watch(mobilePairingClientProvider),
    ),
    if (includeTailscale)
      tailscaleServiceProvider.overrideWith(
        (ref) => ref.watch(desktopTailscaleServiceProvider),
      ),
  ];
}

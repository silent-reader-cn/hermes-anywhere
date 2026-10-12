/// Tailscale（内网穿透）契约 —— 桌面向导与实现方共用的接口出口。
///
/// 分工：
/// - 本文件：状态模型 + 抽象服务 + 注入点；
/// - 实现：`lib/core/tailscale/tailscale_service.dart`（探测 / 一键安装 / 打开登录页 / 轮询出地址）。
///
/// 诚实边界（照抄进实现注释，别在 UI 上假装能做到）：
/// Tailscale **不支持邮箱注册**，登录必须走第三方 IdP（Google / 微软 / GitHub / Apple），
/// 因此浏览器里那一次授权**无法代劳** —— App 能做的是静默安装、打开登录页、轮询到地址出现。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
/// Tailscale 在用户机器上的状态。
enum TailscaleState {
  /// 尚未探测。
  unknown,

  /// 未安装（可一键安装）。
  notInstalled,

  /// 正在下载 / 安装 / 等待登录。
  installing,

  /// 已安装但未登录（需要用户去浏览器授权）。
  needsLogin,

  /// 已就绪：拿到了 100.x.y.z 地址。
  ready,

  /// 失败（见 detail）。
  failed,
}

/// 一次探测 / 安装过程的状态快照。
class TailscaleStatus {
  const TailscaleStatus({
    required this.state,
    this.ipv4 = '',
    this.loginUrl = '',
    this.detail = '',
    this.progress = 0,
  });

  final TailscaleState state;

  /// 就绪时的 tailnet 地址（IPv4），例：`100.101.87.11`。
  final String ipv4;

  /// 需要登录时 Tailscale 打印的授权 URL（由 App 打开浏览器）。
  final String loginUrl;

  /// 失败原因 / 进行中的一步说明（展示给用户，别塞堆栈）。
  final String detail;

  /// 0.0~1.0 的粗粒度进度（仅用于进度条；无进度时保持 0）。
  final double progress;

  bool get isReady => state == TailscaleState.ready && ipv4.isNotEmpty;
}

/// Tailscale 服务：探测 → 一键安装 → 引导登录 → 出地址。
abstract class TailscaleService {
  /// 探测当前状态（不改动系统）。
  Future<TailscaleStatus> probe();

  /// 一键安装并等待登录：下载官方安装包 → 静默安装 → 打开登录页 → 轮询出地址。
  /// 过程通过 [status] 流式上报；用户取消或失败时以 `failed` / `cancelled` 收尾。
  Stream<TailscaleStatus> installAndLogin();

  /// 取消进行中的安装流程（幂等）。
  Future<void> cancel();
}

/// 注入点。默认未实现 —— 由 `core/tailscale/tailscale_service.dart` 覆盖。
final tailscaleServiceProvider = Provider<TailscaleService>(
  (ref) => throw UnimplementedError(
    'tailscaleServiceProvider 未覆盖：桌面端需注入真实实现（见 core/tailscale/tailscale_service.dart）',
  ),
);

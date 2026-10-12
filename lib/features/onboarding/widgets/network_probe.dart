/// 本机网络 / 环境探测（可注入）—— 向导首屏「网络环境」检查行的数据源。
///
/// 为什么单独成文件：探测必须能在测试里注入。真实实现要对外网发 HTTPS 请求，
/// 而单测与金照既不能真联网，也不能让「正常 / 受限」两态随宿主网络随机漂移。
/// 同时把「网络受限」的判据与文案完全收在这一层，页面只消费结果。
///
/// 判据（与设计稿 §5 N1 一致）：逐个探测 [DefaultNetworkProbe.targets]，
/// **任一可达即算正常**，全都不可达才给橙色提示。「可达」的定义放宽到
/// 「拿到了任何 HTTP 响应」—— 网络受限地区的典型症状是连接超时或被重置，
/// 而 3xx/4xx 恰恰说明链路通（代理返回 401/403 也算通）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一次网络环境探测的结果。
class NetworkProbeResult {
  const NetworkProbeResult({required this.reachable, this.detail = ''});

  /// 是否可达（任一目标可达即为 true）。
  final bool reachable;

  /// 不可达时的短说明（例：`GitHub 不可达 · 超时 3s`）；可达时为空串。
  final String detail;
}

/// 网络环境探测接口（测试注入 fake）。
abstract interface class NetworkProbe {
  /// 探测网络环境；[timeout] 为单个目标的超时上限。
  Future<NetworkProbeResult> probe({Duration timeout});
}

/// 默认探测实现：对 github.com / pypi.org 各发一次 HTTPS GET。
///
/// 选这两个目标是因为它们正好对应向导里最容易超时的两步：
/// github.com → 「拉取 Agent」（git clone / install.ps1），pypi.org → 「安装依赖」。
class DefaultNetworkProbe implements NetworkProbe {
  /// 构造默认探测（目标可换，测试用不上）。
  const DefaultNetworkProbe({this.targets = defaultTargets});

  /// 探测目标主机（顺序即失败时的报错顺序）。
  static const List<String> defaultTargets = <String>['github.com', 'pypi.org'];

  /// 设计稿口径的默认超时 —— 提示文案里写死「超时 3s」，改这里要同步改文案。
  static const Duration defaultTimeout = Duration(seconds: 3);

  /// 探测目标。
  final List<String> targets;

  @override
  Future<NetworkProbeResult> probe({
    Duration timeout = defaultTimeout,
  }) async {
    final failed = <String>[];
    var reason = _ProbeFailure.unreachable;
    for (final host in targets) {
      final failure = await _probeHost(host, timeout);
      if (failure == null) {
        return const NetworkProbeResult(reachable: true);
      }
      failed.add(_displayName(host));
      reason = failure;
    }
    final reasonText = reason == _ProbeFailure.timeout
        ? '超时 ${timeout.inSeconds}s'
        : '连接失败';
    return NetworkProbeResult(
      reachable: false,
      detail: '${failed.join(' / ')} 不可达 · $reasonText',
    );
  }

  /// 探测单台主机；可达返回 null，否则返回失败分类。
  Future<_ProbeFailure?> _probeHost(String host, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('https://$host/'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'hermes-desktop-onboarding');
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      // 拿到响应即认定链路可达（不看状态码，见文件头）。
      return null;
    } on TimeoutException {
      return _ProbeFailure.timeout;
    } on SocketException {
      return _ProbeFailure.unreachable;
    } catch (_) {
      return _ProbeFailure.unreachable;
    } finally {
      client.close(force: true);
    }
  }

  String _displayName(String host) {
    switch (host) {
      case 'github.com':
        return 'GitHub';
      case 'pypi.org':
        return 'PyPI';
      default:
        return host;
    }
  }
}

/// 探测失败分类（决定文案里的「超时 3s」还是「连接失败」）。
enum _ProbeFailure { timeout, unreachable }

/// 网络环境探测注入点。默认走真实网络；测试与金照注入 fake。
final networkProbeProvider = Provider<NetworkProbe>(
  (ref) => const DefaultNetworkProbe(),
);

// ---------------------------------------------------------------------------
// 本机身份与网卡地址（配对步要用：手机得知道连哪个地址）
// ---------------------------------------------------------------------------

/// 本机安装标识注入点（配对会话的 `installId`）。
///
/// 真实来源应是后端 `/api/status` 的 `install_id`（见 pairing_contract 注释）；
/// 该接口尚未接入，本批先用主机名占位 —— 它在本机内稳定、且天生对用户可读
/// （配对屏 D5 要展示电脑名）。后端 install_id 就绪后只改这个默认实现。
final installIdProvider = Provider<String>((ref) => defaultInstallId());

/// 主机名（探测失败时返回空串，绝不抛）。
String defaultInstallId() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return '';
  }
}

/// 本机局域网 IPv4 地址注入点（配对屏交给手机的那个地址）。
///
/// 取不到（无网卡 / 只有环回）时返回空串，调用方自行降级。
final lanAddressProvider = FutureProvider<String>((ref) async {
  final addresses = await probeLanAddresses();
  return addresses.isEmpty ? '' : addresses.first;
});

/// 枚举本机局域网 IPv4（排除环回 / 链路本地 / 非私有段）。
Future<List<String>> probeLanAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final result = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback || address.isLinkLocal) continue;
        if (!isPrivateIpv4(address.address)) continue;
        result.add(address.address);
      }
    }
    return result;
  } catch (_) {
    return const <String>[];
  }
}

/// 是否 RFC1918 私有网段地址（192.168/16、10/8、172.16/12）。
bool isPrivateIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final first = int.tryParse(parts[0]);
  final second = int.tryParse(parts[1]);
  if (first == null || second == null) return false;
  if (first == 10) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  // CGNAT（部分企业网 / 运营商大内网）也算局域网可达目标。
  if (first == 100 && second >= 64 && second <= 127) return true;
  return false;
}

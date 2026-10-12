/// 局域网「手机可达地址」选路 —— 纯逻辑 + 全可注入（单测不起真网络）。
///
/// ## 为什么需要它
/// 原先的兜底实现是「遍历网卡取第一个非回环 IPv4，取不到回落 `127.0.0.1`」。
/// 在本机式多网卡环境里这会**大概率选中手机根本连不上的地址**：
/// - `198.18.0.0/15`：Clash/Meta(mihomo) 的 TUN fake-ip 网段，只有本机代理栈认；
/// - `169.254.0.0/16`：未接线 / 没拿到 DHCP 的链路本地地址（APIPA）；
/// - `vEthernet` / Hyper-V / WSL / Docker / VirtualBox / VMware：宿主机内部交换机，
///   手机不在那个虚拟网段里；
/// - 取不到时静默回落 `127.0.0.1` —— 手机**永远**连不上它。
///
/// 后果是桌面端显示「配对已就绪」并公布一个死地址，手机侧只看到「连不上」，
/// 两边都无法定位。本文件把选路逻辑做成三重门槛：
/// 1. **排除**：[isUsableLanAddress] + [isVirtualInterfaceName]（环回、链路本地、
///    fake-ip、组播，以及网卡名命中 [kVirtualInterfaceMarkers] 的虚拟网卡）；
/// 2. **排序**：与默认路由同网段 > 其他普通私网（10/8、172.16/12、192.168/16）
///    > tailnet（`100.64.0.0/10`，且只在前两档都为空时才算候选）；
/// 3. **探活门禁**：每个候选都要经 [LanAddressSelector.probe] 真的连得上才采用，
///    失败换下一个；全失败返回 `null` —— 调用方**不得**回落回环地址。
///
/// 网卡枚举、默认路由读取、探活都是构造参数（默认实现走 dart:io / 系统命令），
/// 单测全部注入假实现，不碰真网络、不依赖跑测主机的网卡状态。
library;

import 'dart:async';
import 'dart:io';

/// 默认探针对单个候选的时间上限（1.5s）。
const Duration kLanProbeTimeout = Duration(milliseconds: 1500);

/// 默认探针请求的路径（配对服务的探活端点）。
const String kLanProbePath = '/health';

/// 「与默认路由同网段」判定用的前缀长度。
///
/// 系统路由表里读到的是网关地址、拿不到掩码，按 /24 比 —— 家用/办公局域网
/// 基本都是 /24，误判代价也只是档位内先后顺序（候选仍要过探活门禁）。
const int kLanSubnetPrefixLength = 24;

/// 已知虚拟网卡名标记表（**不区分大小写**的子串匹配）。
///
/// 命中即整块网卡的地址都不当候选：这些地址要么只在本机栈内可达
/// （Hyper-V/WSL/Docker 的内部交换机），要么是代理软件的伪栈（Clash.Meta）。
/// 刻意**不含** `tailscale`：tailnet 地址是合法候选，只是排在最后。
const List<String> kVirtualInterfaceMarkers = <String>[
  'vethernet', // Hyper-V / WSL 虚拟交换机（WLAN 之外的常见 172.x）
  'virtual ethernet',
  'hyper-v',
  'hyper_v',
  'vmware',
  'virtualbox',
  'vbox',
  'loopback',
  'wsl',
  'docker',
  'clash',
  'meta', // Clash.Meta / mihomo 的 TUN 网卡
  'npcap',
  'virbr', // libvirt 网桥
];

/// 一块网卡上的 IPv4 地址集合。
class LanInterface {
  const LanInterface({required this.name, required this.ipv4});

  /// 网卡名（Windows 例：`WLAN`、`vEthernet (Default Switch)`、`Meta`）。
  final String name;

  /// 该网卡上的 IPv4 点分十进制地址（可能多个）。
  final List<String> ipv4;

  @override
  String toString() => 'LanInterface($name, $ipv4)';
}

/// 网卡枚举注入点；默认 [systemLanInterfaces]。
typedef LanInterfaceLister = Future<List<LanInterface>> Function();

/// 默认路由网关注入点；默认 [systemDefaultGateways]。
typedef LanDefaultGatewayReader = Future<List<String>> Function();

/// 候选探活注入点；默认 [probeLanHealth]。
typedef LanAddressProbe = Future<bool> Function(String host, int port);

/// 默认网卡枚举：IPv4、排除环回网卡；枚举失败（沙箱 / 无权限）返回空表，绝不抛。
Future<List<LanInterface>> systemLanInterfaces() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return <LanInterface>[
      for (final interface in interfaces)
        LanInterface(
          name: interface.name,
          ipv4: <String>[
            for (final address in interface.addresses) address.address,
          ],
        ),
    ];
  } catch (_) {
    return const <LanInterface>[];
  }
}

/// 默认默认路由读取：按平台读系统路由表里的 `0.0.0.0/0` 网关。
///
/// 返回**全部**默认路由网关：装了 VPN / 代理 TUN 的机器会同时有多条
/// （例：WLAN 的 `192.168.1.1` 与 Clash Meta 的 `198.18.0.2`）。
/// 命令缺失 / 权限不足 / 输出格式不对 → 空表，绝不抛。
Future<List<String>> systemDefaultGateways() async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('route', <String>['print', '-4']);
      return parseWindowsDefaultGateways('${result.stdout}');
    }
    if (Platform.isMacOS) {
      final result = await Process.run('netstat', <String>['-rn', '-f', 'inet']);
      return parseDarwinDefaultGateways('${result.stdout}');
    }
    final result = await Process.run('ip', <String>['route', 'show', 'default']);
    return parseLinuxDefaultGateways('${result.stdout}');
  } catch (_) {
    return const <String>[];
  }
}

/// 解析 `route print -4` 的 Active Routes 表，取 `0.0.0.0/0` 行的网关列。
List<String> parseWindowsDefaultGateways(String output) {
  final gateways = <String>[];
  for (final line in output.split('\n')) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    if (tokens.length < 3) continue;
    if (tokens[0] != '0.0.0.0' || tokens[1] != '0.0.0.0') continue;
    final gateway = tokens[2];
    if (gateway.isEmpty || gateway == 'On-link' || gateway == '0.0.0.0') {
      continue;
    }
    if (!isIpv4Literal(gateway)) continue;
    if (!gateways.contains(gateway)) gateways.add(gateway);
  }
  return gateways;
}

/// 解析 `netstat -rn -f inet` 的 `default` 行，取网关列。
List<String> parseDarwinDefaultGateways(String output) {
  final gateways = <String>[];
  for (final line in output.split('\n')) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    if (tokens.length < 2 || tokens[0] != 'default') continue;
    final gateway = tokens[1];
    if (!isIpv4Literal(gateway)) continue;
    if (!gateways.contains(gateway)) gateways.add(gateway);
  }
  return gateways;
}

/// 解析 `ip route show default` 的 `default via <网关>` 行。
List<String> parseLinuxDefaultGateways(String output) {
  final gateways = <String>[];
  final pattern = RegExp(r'\bdefault\s+via\s+(\S+)');
  for (final match in pattern.allMatches(output)) {
    final gateway = match.group(1) ?? '';
    if (!isIpv4Literal(gateway)) continue;
    if (!gateways.contains(gateway)) gateways.add(gateway);
  }
  return gateways;
}

/// 默认探针：`GET http://host:port/health`，[kLanProbeTimeout] 内拿不到
/// 200 就算不可达（超时 / 连接被拒 / 连接重置 / 非 200 / DNS 失败一律 false）。
Future<bool> probeLanHealth(String host, int port) async {
  final client = HttpClient()..connectionTimeout = kLanProbeTimeout;
  try {
    return await _getProbeHealth(client, host, port).timeout(kLanProbeTimeout);
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<bool> _getProbeHealth(HttpClient client, String host, int port) async {
  final request = await client.getUrl(
    Uri.parse('http://$host:$port$kLanProbePath'),
  );
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode == HttpStatus.ok;
}

/// 候选优先级档（[rank] 越小越优先）。
enum LanCandidateTier {
  /// 调用方显式给出的主机（WebUI 地址的 host）—— 用户的意图优先，但仍要过探活。
  requested(0),

  /// 与某条默认路由同网段的网卡地址。
  defaultRoute(1),

  /// 其他普通私网地址（10/8、172.16/12、192.168/16）。
  private(2),

  /// tailnet（`100.64.0.0/10`，Tailscale 用）：只在前两档都为空时当候选。
  tailnet(3);

  const LanCandidateTier(this.rank);

  /// 排序用档位序号。
  final int rank;
}

/// 一个候选地址（地址 + 来源 + 档位）。
class LanAddressCandidate {
  const LanAddressCandidate({
    required this.address,
    required this.interfaceName,
    required this.tier,
  });

  /// IPv4 点分十进制地址。
  final String address;

  /// 来源网卡名；显式给出的主机记为 `<requested>`。
  final String interfaceName;

  /// 优先级档。
  final LanCandidateTier tier;

  @override
  String toString() =>
      'LanAddressCandidate($address, $interfaceName, ${tier.name})';
}

/// 选路器：网卡枚举 / 默认路由 / 探活全部可注入。
///
/// 用法：
/// ```dart
/// final host = await const LanAddressSelector().select(
///   probePort: boundHttpPort,      // 必须是真实在监听的端口，探活才有意义
///   requestedHost: Uri.tryParse(baseUrl)?.host ?? '',
/// );
/// if (host == null) { /* 没有可用局域网地址：给 UI 一个明确状态，不回落回环 */ }
/// ```
class LanAddressSelector {
  const LanAddressSelector({
    this.listInterfaces = systemLanInterfaces,
    this.readDefaultGateways = systemDefaultGateways,
    this.probe = probeLanHealth,
  });

  /// 网卡枚举。
  final LanInterfaceLister listInterfaces;

  /// 默认路由网关读取。
  final LanDefaultGatewayReader readDefaultGateways;

  /// 候选探活门禁。
  final LanAddressProbe probe;

  /// 按档位选出**第一个探活通过**的候选地址；没有可用地址时返回 `null`。
  ///
  /// [probePort] 是探活目标端口（桌面端传自己刚绑定好的 HTTP 端口：
  /// 「这个地址能不能连到我」才是要回答的问题）。
  Future<String?> select({
    required int probePort,
    String requestedHost = '',
  }) async {
    final candidates = await rankCandidates(requestedHost: requestedHost);
    for (final candidate in candidates) {
      final reachable = await _probeSafely(candidate.address, probePort);
      if (reachable) return candidate.address;
    }
    return null;
  }

  /// 只排序、不探活（诊断与单测用）。
  ///
  /// 返回按 [LanCandidateTier.rank] 分档、档内保持网卡枚举顺序的候选表；
  /// 被排除 / 不属于任何档的地址不会出现在结果里。
  Future<List<LanAddressCandidate>> rankCandidates({
    String requestedHost = '',
  }) async {
    final gateways = await _readGatewaysSafely();
    final interfaces = await _listInterfacesSafely();
    final buckets = <LanCandidateTier, List<LanAddressCandidate>>{
      for (final tier in LanCandidateTier.values) tier: <LanAddressCandidate>[],
    };
    final seen = <String>{};

    void add(String address, String interfaceName, LanCandidateTier tier) {
      if (!isUsableLanAddress(address) || !seen.add(address)) return;
      buckets[tier]!.add(
        LanAddressCandidate(
          address: address,
          interfaceName: interfaceName,
          tier: tier,
        ),
      );
    }

    add(requestedHost.trim(), _requestedInterfaceName, LanCandidateTier.requested);

    for (final interface in interfaces) {
      if (isVirtualInterfaceName(interface.name)) continue;
      for (final address in interface.ipv4) {
        final tier = _tierOf(address, gateways);
        if (tier == null) continue;
        add(address, interface.name, tier);
      }
    }

    return <LanAddressCandidate>[
      for (final tier in LanCandidateTier.values) ...buckets[tier]!,
    ];
  }

  /// 显式主机在候选表里的来源标签。
  static const String _requestedInterfaceName = '<requested>';

  LanCandidateTier? _tierOf(String address, List<String> gateways) {
    if (!isUsableLanAddress(address)) return null;
    for (final gateway in gateways) {
      if (isSameSubnet24(address, gateway)) {
        return LanCandidateTier.defaultRoute;
      }
    }
    if (isPrivateLanAddress(address)) return LanCandidateTier.private;
    if (isTailnetAddress(address)) return LanCandidateTier.tailnet;
    // 既非私网也非 tailnet：不是局域网可达目标（多为运营商公网/测试保留段）。
    return null;
  }

  Future<bool> _probeSafely(String host, int port) async {
    try {
      return await probe(host, port);
    } catch (_) {
      // 探针自己抛（注入方写错 / 平台异常）也算不可达：换下一个，不拖垮调用方。
      return false;
    }
  }

  Future<List<String>> _readGatewaysSafely() async {
    try {
      return await readDefaultGateways();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<LanInterface>> _listInterfacesSafely() async {
    try {
      return await listInterfaces();
    } catch (_) {
      return const <LanInterface>[];
    }
  }
}

/// 网卡名是否命中虚拟网卡标记表（不区分大小写的子串匹配）。
bool isVirtualInterfaceName(String name) {
  final normalized = name.toLowerCase();
  for (final marker in kVirtualInterfaceMarkers) {
    if (normalized.contains(marker)) return true;
  }
  return false;
}

/// 是否可用作候选的 IPv4：排除非法字面量、环回 / 未指定、链路本地、fake-ip、
/// 组播与保留段。
bool isUsableLanAddress(String address) {
  final octets = _octetsOf(address);
  if (octets == null) return false;
  final first = octets[0];
  if (first == 0 || first == 127) return false; // 未指定 / 环回：手机永远连不上
  if (isLinkLocalIpv4Address(address)) return false; // APIPA
  if (isFakeIpv4Address(address)) return false; // 代理 TUN fake-ip
  if (first >= 224) return false; // 组播 / 保留
  return true;
}

/// 是否 IPv4 点分十进制字面量（四段、每段 0-255）。
bool isIpv4Literal(String address) => _octetsOf(address) != null;

/// 链路本地地址（`169.254.0.0/16`，Windows/macOS 拿不到 DHCP 时的 APIPA 地址）。
bool isLinkLocalIpv4Address(String address) {
  final octets = _octetsOf(address);
  return octets != null && octets[0] == 169 && octets[1] == 254;
}

/// 代理软件 fake-ip 网段（Clash / Surge 系约定：`198.18.0.0/15`）。
bool isFakeIpv4Address(String address) {
  final octets = _octetsOf(address);
  return octets != null && octets[0] == 198 && (octets[1] == 18 || octets[1] == 19);
}

/// RFC1918 私网地址（192.168/16、10/8、172.16/12）。
bool isPrivateLanAddress(String address) {
  final octets = _octetsOf(address);
  if (octets == null) return false;
  final first = octets[0];
  final second = octets[1];
  if (first == 10) return true;
  if (first == 192 && second == 168) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  return false;
}

/// tailnet 地址（Tailscale 用的 CGNAT 段 `100.64.0.0/10`）。
bool isTailnetAddress(String address) {
  final octets = _octetsOf(address);
  if (octets == null) return false;
  return octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127;
}

/// 两个 IPv4 是否落在同一个 /24 网段（[kLanSubnetPrefixLength] = 24）。
bool isSameSubnet24(String a, String b) {
  final left = _octetsOf(a);
  final right = _octetsOf(b);
  if (left == null || right == null) return false;
  return left[0] == right[0] && left[1] == right[1] && left[2] == right[2];
}

List<int>? _octetsOf(String address) {
  final parts = address.trim().split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  return octets;
}

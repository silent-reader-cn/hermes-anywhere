import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/pairing/lan_address_selector.dart';

/// 主人机器实测网卡 —— 正是旧「取第一个非回环 IPv4」踩坑的现场：
/// 它第一个撞上的是 `vEthernet` 的 172.23.48.1（Hyper-V 内部交换机），
/// 手机不在那个网段里；其次是 Clash Meta 的 fake-ip 198.18.0.1。
const List<LanInterface> _localInterfaces = <LanInterface>[
  LanInterface(
    name: 'vEthernet (Default Switch)',
    ipv4: <String>['172.23.48.1'],
  ),
  LanInterface(name: '本地连接* 9', ipv4: <String>['169.254.168.89']),
  LanInterface(name: '本地连接* 10', ipv4: <String>['169.254.37.127']),
  LanInterface(name: '本地连接* 11', ipv4: <String>['169.254.137.35']),
  LanInterface(name: 'Meta', ipv4: <String>['198.18.0.1']),
  LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
  LanInterface(name: 'Tailscale', ipv4: <String>['100.71.87.11']),
];

/// 造一个全注入的选路器：不起真网络、不看跑测主机的网卡状态。
///
/// [reachable] 内的地址视为「探活通过」；[probeLog] 记录探活顺序（未通过也记）。
LanAddressSelector _selector({
  List<LanInterface> interfaces = _localInterfaces,
  List<String> gateways = const <String>[],
  Set<String> reachable = const <String>{},
  List<String>? probeLog,
  List<int>? portLog,
}) {
  return LanAddressSelector(
    listInterfaces: () async => interfaces,
    readDefaultGateways: () async => gateways,
    probe: (String host, int port) async {
      probeLog?.add(host);
      portLog?.add(port);
      return reachable.contains(host);
    },
  );
}

List<String> _addresses(List<LanAddressCandidate> candidates) =>
    candidates.map((LanAddressCandidate c) => c.address).toList();

void main() {
  group('候选排序（rankCandidates：纯逻辑，不探活）', () {
    test('本机式多网卡：与默认路由同网段的 WLAN 排最前，vEthernet/link-local/fake-ip 一律不入候选，tailnet 垫底', () async {
      final candidates =
          await _selector(gateways: <String>['192.168.1.1']).rankCandidates();

      expect(_addresses(candidates), <String>['192.168.1.95', '100.71.87.11']);
      expect(candidates.first.tier, LanCandidateTier.defaultRoute);
      expect(candidates.first.interfaceName, 'WLAN');
      expect(candidates.last.tier, LanCandidateTier.tailnet);
      // 虚拟网卡 / 链路本地 / fake-ip 全部不入候选。
      for (final excluded in <String>[
        '172.23.48.1',
        '169.254.168.89',
        '169.254.37.127',
        '169.254.137.35',
        '198.18.0.1',
      ]) {
        expect(_addresses(candidates).contains(excluded), isFalse,
            reason: '$excluded 不该成为候选');
      }
    });

    test('默认路由在 Meta(198.18.0.2) 时，198.18.0.1 仍不入候选（档位退化为普通私网）', () async {
      final candidates =
          await _selector(gateways: <String>['198.18.0.2']).rankCandidates();

      expect(_addresses(candidates), <String>['192.168.1.95', '100.71.87.11']);
      expect(candidates.first.tier, LanCandidateTier.private);
    });

    test('读到两条默认路由（WLAN + Meta TUN）时，与物理网卡同网段的那条决定最高档', () async {
      final candidates = await _selector(
        gateways: <String>['198.18.0.2', '192.168.1.1'],
      ).rankCandidates();

      expect(candidates.first.address, '192.168.1.95');
      expect(candidates.first.tier, LanCandidateTier.defaultRoute);
    });

    test('默认路由读不到（路由表命令失败）时，仍按普通私网档排出 WLAN', () async {
      final candidates = await _selector().rankCandidates();

      expect(_addresses(candidates), <String>['192.168.1.95', '100.71.87.11']);
      expect(candidates.first.tier, LanCandidateTier.private);
    });

    test('tailnet 垫底：私网候选探得通时，tailnet 连探都不探（轮不到它）', () async {
      final probeLog = <String>[];
      final host = await _selector(
        interfaces: const <LanInterface>[
          LanInterface(name: 'Tailscale', ipv4: <String>['100.71.87.11']),
          LanInterface(name: '以太网', ipv4: <String>['192.168.1.95']),
        ],
        gateways: <String>['192.168.1.1'],
        reachable: <String>{'192.168.1.95', '100.71.87.11'},
        probeLog: probeLog,
      ).select(probePort: 38911);

      expect(host, '192.168.1.95');
      expect(probeLog, <String>['192.168.1.95']);
    });

    test('前两档都没有候选（只有 tailnet + 被排除项）时才退到 tailnet', () async {
      final candidates = await _selector(
        interfaces: const <LanInterface>[
          LanInterface(name: 'Tailscale', ipv4: <String>['100.71.87.11']),
          LanInterface(name: 'Meta', ipv4: <String>['198.18.0.1']),
          LanInterface(name: '本地连接* 9', ipv4: <String>['169.254.168.89']),
        ],
        gateways: <String>['198.18.0.2'],
      ).rankCandidates();

      expect(_addresses(candidates), <String>['100.71.87.11']);
      expect(candidates.single.tier, LanCandidateTier.tailnet);
      expect(
        await _selector(
          interfaces: const <LanInterface>[
            LanInterface(name: 'Tailscale', ipv4: <String>['100.71.87.11']),
          ],
          gateways: <String>['198.18.0.2'],
          reachable: <String>{'100.71.87.11'},
        ).select(probePort: 38911),
        '100.71.87.11',
      );
    });

    test('私网与 tailnet 都为空、只有公网地址 ⇒ 无候选（非局域网可达目标不入表）', () async {
      final candidates = await _selector(
        interfaces: const <LanInterface>[
          LanInterface(name: '以太网', ipv4: <String>['203.0.113.9']),
        ],
      ).rankCandidates();

      expect(candidates, isEmpty);
    });

    test('显式主机（WebUI 地址的 host）排在最前，档位 requested', () async {
      final candidates = await _selector(gateways: <String>['192.168.1.1'])
          .rankCandidates(requestedHost: '10.0.0.7');

      expect(candidates.first.address, '10.0.0.7');
      expect(candidates.first.tier, LanCandidateTier.requested);
      expect(_addresses(candidates), <String>['10.0.0.7', '192.168.1.95', '100.71.87.11']);
    });

    test('同一地址出现在多块网卡上只保留一次（去重后按首次出现定档）', () async {
      final candidates = await _selector(
        interfaces: const <LanInterface>[
          LanInterface(name: '以太网', ipv4: <String>['192.168.1.95']),
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
        ],
      ).rankCandidates();

      expect(candidates, hasLength(1));
      expect(candidates.single.interfaceName, '以太网');
    });
  });

  group('探活门禁（select：候选必须真的连得上）', () {
    test('① 本机式多网卡 + 只有 WLAN 探活通过 ⇒ 选中 192.168.1.95（只探了一次）', () async {
      final probeLog = <String>[];
      final host = await _selector(
        gateways: <String>['192.168.1.1'],
        reachable: <String>{'192.168.1.95'},
        probeLog: probeLog,
      ).select(probePort: 38911);

      expect(host, '192.168.1.95');
      expect(probeLog, <String>['192.168.1.95']);
    });

    test('② 默认路由在 Meta 时，即便 198.18.0.1 探得通也不得选它（它连候选都不是）', () async {
      final probeLog = <String>[];
      final host = await _selector(
        gateways: <String>['198.18.0.2'],
        reachable: <String>{'198.18.0.1', '100.71.87.11'},
        probeLog: probeLog,
      ).select(probePort: 38911);

      expect(host, '100.71.87.11');
      expect(probeLog.contains('198.18.0.1'), isFalse);
    });

    test('③ 第一个候选自连失败 ⇒ 自动换下一个（探活顺序 = 档内顺序）', () async {
      final probeLog = <String>[];
      final host = await _selector(
        interfaces: const <LanInterface>[
          LanInterface(name: '以太网', ipv4: <String>['192.168.1.77']),
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
        ],
        gateways: <String>['192.168.1.1'],
        reachable: <String>{'192.168.1.95'},
        probeLog: probeLog,
      ).select(probePort: 38911);

      expect(host, '192.168.1.95');
      expect(probeLog, <String>['192.168.1.77', '192.168.1.95']);
    });

    test('④ 全部候选都不可达 ⇒ 返回 null，且绝不回落 127.0.0.1', () async {
      final probeLog = <String>[];
      final host = await _selector(
        gateways: <String>['192.168.1.1'],
        probeLog: probeLog,
      ).select(probePort: 38911);

      expect(host, isNull);
      expect(host, isNot('127.0.0.1'));
      expect(
        probeLog,
        <String>['192.168.1.95', '100.71.87.11'],
        reason: '每个候选都要真的探一次，不能跳着猜',
      );
    });

    test('没有任何候选（网卡枚举失败 / 全是排除项）⇒ 直接 null，探针一次都不调', () async {
      final probeLog = <String>[];
      final host = await _selector(
        interfaces: const <LanInterface>[],
        reachable: <String>{'192.168.1.95'},
        probeLog: probeLog,
      ).select(probePort: 38911);

      expect(host, isNull);
      expect(probeLog, isEmpty);
    });

    test('探针自己抛异常 ⇒ 记作不可达、换下一个，不拖垮调用方', () async {
      final selector = LanAddressSelector(
        listInterfaces: () async => const <LanInterface>[
          LanInterface(name: '以太网', ipv4: <String>['192.168.1.77']),
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
        ],
        readDefaultGateways: () async => const <String>[],
        probe: (String host, int port) async {
          if (host == '192.168.1.77') throw StateError('探针炸了');
          return true;
        },
      );

      expect(await selector.select(probePort: 38911), '192.168.1.95');
    });

    test('网卡枚举与路由表读取都抛异常 ⇒ 当「没有候选」，返回 null 而不是抛', () async {
      final selector = LanAddressSelector(
        listInterfaces: () async => throw StateError('枚举失败'),
        readDefaultGateways: () async => throw StateError('路由表读不到'),
        probe: (String host, int port) async => true,
      );

      expect(await selector.select(probePort: 38911), isNull);
    });

    test('显式主机排最前但同样要过探活；探针收到的端口就是调用方给的端口', () async {
      final probeLog = <String>[];
      final portLog = <int>[];
      final host = await _selector(
        gateways: <String>['192.168.1.1'],
        reachable: <String>{'192.168.1.95'},
        probeLog: probeLog,
        portLog: portLog,
      ).select(probePort: 38911, requestedHost: '192.168.1.95');

      expect(host, '192.168.1.95');
      expect(probeLog, <String>['192.168.1.95']);
      expect(portLog, <int>[38911]);
    });

    test('显式主机是回环 / localhost / ::1 ⇒ 不入候选，落到可用网卡', () async {
      for (final requested in <String>['127.0.0.1', 'localhost', '::1']) {
        final probeLog = <String>[];
        final host = await _selector(
          gateways: <String>['192.168.1.1'],
          reachable: <String>{'192.168.1.95'},
          probeLog: probeLog,
        ).select(probePort: 38911, requestedHost: requested);

        expect(host, '192.168.1.95', reason: 'requested=$requested');
        expect(probeLog.contains(requested), isFalse);
      }
    });

    test('显式主机是 fake-ip（Clash 伪栈）⇒ 不入候选，仍按网卡选路', () async {
      final probeLog = <String>[];
      final host = await _selector(
        gateways: <String>['198.18.0.2'],
        reachable: <String>{'192.168.1.95', '198.18.0.1'},
        probeLog: probeLog,
      ).select(probePort: 38911, requestedHost: '198.18.0.1');

      expect(host, '192.168.1.95');
      expect(probeLog.contains('198.18.0.1'), isFalse);
    });
  });

  group('排除表（地址与网卡名）', () {
    test('⑤ 虚拟网卡名匹配表：不分大小写、子串命中；物理网卡与 Tailscale 不误伤', () {
      const virtualNames = <String>[
        'vEthernet (Default Switch)',
        'VEthernet (WSL)',
        'Hyper-V Virtual Ethernet Adapter',
        'HYPER_V switch',
        'VMware Network Adapter VMnet8',
        'VirtualBox Host-Only Network',
        'vboxnet0',
        'Loopback Pseudo-Interface 1',
        'WSL (vEthernet (Default Switch))',
        'Docker Desktop',
        'Meta',
        'CLASH Tunnel',
        'Npcap Loopback Adapter',
        'virbr0',
      ];
      for (final name in virtualNames) {
        expect(isVirtualInterfaceName(name), isTrue, reason: '$name 应判为虚拟网卡');
      }

      const physicalNames = <String>[
        'WLAN',
        '以太网',
        'Ethernet',
        'Wi-Fi 2',
        'en0',
        '本地连接* 9',
        'Tailscale',
      ];
      for (final name in physicalNames) {
        expect(
          isVirtualInterfaceName(name),
          isFalse,
          reason: '$name 不该误判（尤其 Tailscale：tailnet 地址要留作候选）',
        );
      }
    });

    test('虚拟网卡上的地址整块丢：即便 172.23.48.1 是私网也不当选', () async {
      final candidates = await _selector(
        interfaces: const <LanInterface>[
          LanInterface(
            name: 'vEthernet (Default Switch)',
            ipv4: <String>['172.23.48.1'],
          ),
        ],
      ).rankCandidates();

      expect(candidates, isEmpty);
    });

    test('地址排除表：链路本地 / fake-ip / 环回 / 未指定 / 组播 / 非法字面量', () {
      const excluded = <String>[
        '169.254.0.1',
        '169.254.255.254',
        '198.18.0.1',
        '198.19.255.255',
        '127.0.0.1',
        '127.1.2.3',
        '0.0.0.0',
        '224.0.0.1',
        '255.255.255.255',
        '',
        'not-an-ip',
        '192.168.1',
        '1.2.3.256',
        '::1',
        '8.8.8.8.8',
      ];
      for (final address in excluded) {
        expect(isUsableLanAddress(address), isFalse, reason: address);
      }

      const kept = <String>[
        '192.168.1.95',
        '10.0.0.5',
        '172.23.48.1',
        '100.71.87.11',
        '198.20.0.1',
        '203.0.113.9',
      ];
      for (final address in kept) {
        expect(isUsableLanAddress(address), isTrue, reason: address);
      }
    });

    test('fake-ip 只认 198.18/198.19；198.20 起是正常地址', () {
      expect(isFakeIpv4Address('198.18.0.1'), isTrue);
      expect(isFakeIpv4Address('198.19.255.255'), isTrue);
      expect(isFakeIpv4Address('198.20.0.1'), isFalse);
      expect(isFakeIpv4Address('198.17.0.1'), isFalse);
    });

    test('链路本地只认 169.254/16', () {
      expect(isLinkLocalIpv4Address('169.254.1.1'), isTrue);
      expect(isLinkLocalIpv4Address('169.253.1.1'), isFalse);
      expect(isLinkLocalIpv4Address('169.255.1.1'), isFalse);
    });

    test('tailnet 边界：100.64.0.0/10 内是候选，100.128.0.1 起不是', () {
      for (final inside in <String>[
        '100.64.0.1',
        '100.100.1.1',
        '100.127.255.255',
      ]) {
        expect(isTailnetAddress(inside), isTrue, reason: inside);
      }
      for (final outside in <String>[
        '100.63.255.255',
        '100.128.0.1',
        '99.64.0.1',
        '192.168.1.1',
      ]) {
        expect(isTailnetAddress(outside), isFalse, reason: outside);
      }
    });

    test('私网与 /24 同网段判定边界', () {
      expect(isPrivateLanAddress('172.16.0.1'), isTrue);
      expect(isPrivateLanAddress('172.31.255.255'), isTrue);
      expect(isPrivateLanAddress('172.15.0.1'), isFalse);
      expect(isPrivateLanAddress('172.32.0.1'), isFalse);
      expect(isPrivateLanAddress('192.169.1.1'), isFalse);
      expect(isSameSubnet24('192.168.1.95', '192.168.1.1'), isTrue);
      expect(isSameSubnet24('192.168.1.95', '192.168.2.1'), isFalse);
      expect(isSameSubnet24('192.168.1.95', 'not-an-ip'), isFalse);
    });
  });

  group('默认实现（真实 socket / 真实系统命令）', () {
    test('probeLanHealth：只有 /health 返回 200 才算通；非 200 算不可达', () async {
      final healthy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final broken = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => healthy.close(force: true));
      addTearDown(() => broken.close(force: true));
      final healthySub = healthy.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write('{}');
        await request.response.close();
      });
      final brokenSub = broken.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('{}');
        await request.response.close();
      });
      addTearDown(healthySub.cancel);
      addTearDown(brokenSub.cancel);

      // 探活路径固定 /health（配对服务的探活端点）：别的响应不算「这里能配对」。
      expect(kLanProbePath, '/health');
      expect(await probeLanHealth('127.0.0.1', healthy.port), isTrue);
      expect(await probeLanHealth('127.0.0.1', broken.port), isFalse);
    });

    test('probeLanHealth：没人监听的端口 ⇒ false（不抛）', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = probe.port;
      await probe.close();

      expect(await probeLanHealth('127.0.0.1', closedPort), isFalse);
    });

    test('probeLanHealth：只连上不回应 ⇒ 1.5s 超时门禁兜底算不可达', () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <Socket>[];
      final subscription = silent.listen(accepted.add);
      addTearDown(() {
        for (final socket in accepted) {
          socket.destroy();
        }
      });
      addTearDown(subscription.cancel);
      addTearDown(silent.close);

      expect(kLanProbeTimeout, const Duration(milliseconds: 1500));
      final started = DateTime.now();
      expect(await probeLanHealth('127.0.0.1', silent.port), isFalse);
      expect(
        DateTime.now().difference(started) < const Duration(seconds: 5),
        isTrue,
        reason: '探针必须被 1.5s 超时掐掉，不能无限等',
      );
    });

    test('路由表解析：Windows / Linux / macOS 输出样本（多条默认路由都读出来）', () {
      const windowsOutput = 'Interface List\n'
          ' 14...8a 4b ... ......Realtek\n'
          '===========================================================================\n'
          'IPv4 Route Table\n'
          'Active Routes:\n'
          'Network Destination        Netmask          Gateway       Interface  Metric\n'
          '          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.95     45\n'
          '          0.0.0.0          0.0.0.0       198.18.0.2       198.18.0.1      1\n'
          '        192.168.1.0    255.255.255.0         On-link     192.168.1.95    301\n';
      expect(
        parseWindowsDefaultGateways(windowsOutput),
        <String>['192.168.1.1', '198.18.0.2'],
      );
      // On-link / 非法网关一律丢弃。
      expect(
        parseWindowsDefaultGateways(
          '          0.0.0.0          0.0.0.0         On-link     127.0.0.1     45\n',
        ),
        isEmpty,
      );

      const linuxOutput = 'default via 192.168.1.1 dev wlan0 proto dhcp metric 600\n'
          'default via 198.18.0.2 dev meta0 metric 10\n'
          '192.168.1.0/24 dev wlan0 scope link\n';
      expect(
        parseLinuxDefaultGateways(linuxOutput),
        <String>['192.168.1.1', '198.18.0.2'],
      );
      // 没有 via 的默认路由（ppp / 点对点）读不出网关：丢掉而不是编一个。
      expect(parseLinuxDefaultGateways('default dev ppp0\n'), isEmpty);

      const darwinOutput = 'Destination        Gateway            Flags        Netif Expire\n'
          'default            192.168.1.1        UGScg          en0\n'
          '192.168.1/24       link#4             UCS            en0\n';
      expect(
        parseDarwinDefaultGateways(darwinOutput),
        <String>['192.168.1.1'],
      );
      expect(parseDarwinDefaultGateways(''), isEmpty);
    });

    test('默认注入点（真实系统）不抛，返回结构合法', () async {
      final interfaces = await systemLanInterfaces();
      for (final interface in interfaces) {
        expect(interface.name.isNotEmpty, isTrue);
        for (final address in interface.ipv4) {
          expect(isIpv4Literal(address), isTrue, reason: address);
        }
      }

      final gateways = await systemDefaultGateways();
      for (final gateway in gateways) {
        expect(isIpv4Literal(gateway), isTrue, reason: gateway);
      }
    });
  });
}

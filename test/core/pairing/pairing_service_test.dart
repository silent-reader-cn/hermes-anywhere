import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/pairing/lan_address_selector.dart';
import 'package:hermes_ui/core/pairing/pairing_client.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/core/pairing/pairing_service.dart';

/// 固定配对码生成器（去掉随机性，让断言可预期）。
class _FixedCodeGenerator implements PairingCodeGenerator {
  _FixedCodeGenerator(this.code);

  String code;
  int calls = 0;

  @override
  String generate() {
    calls++;
    return code;
  }
}

const String _host = 'TEST-PC';
const String _webuiBaseUrl = 'http://192.168.1.7:8787';
const String _password = 'pw-MUST-NOT-LEAK-123';
const String _installId = 'install-abc';
const String _lanHost = '192.168.1.7';

final DateTime _baseNow = DateTime.utc(2026, 10, 12, 12);

DateTime _defaultClock() => _baseNow;

/// 全部走回环 + 临时端口：既验证真实 socket 线协议，又不碰主机网络状态、
/// 不占用固定 39393 端口（并发跑测试不会互撞）。
DesktopPairingService _buildService({
  DateTime Function()? clock,
  PairingCodeGenerator? generator,
}) {
  return DesktopPairingService(
    codeGenerator: generator ?? _FixedCodeGenerator('123456'),
    clock: clock ?? _defaultClock,
    hostNameResolver: () => _host,
    advertisedHostResolver: (String baseUrl) async => _lanHost,
    httpBindAddress: InternetAddress.loopbackIPv4,
    discoveryBindAddress: InternetAddress.loopbackIPv4,
    discoveryPort: 0,
  );
}

/// 选路器路径下的服务：不注入 `advertisedHostResolver`，改注入假选路器
/// （假网卡 + 假探针）—— 默认 resolver 的实际行为就是这么被驱动的。
DesktopPairingService _buildSelectorService(
  LanAddressSelector selector, {
  PairingAdvertisedHostResolver? resolver,
  PairingCodeGenerator? generator,
}) {
  return DesktopPairingService(
    codeGenerator: generator ?? _FixedCodeGenerator('123456'),
    clock: _defaultClock,
    hostNameResolver: () => _host,
    advertisedHostResolver: resolver,
    lanAddressSelector: selector,
    httpBindAddress: InternetAddress.loopbackIPv4,
    discoveryBindAddress: InternetAddress.loopbackIPv4,
    discoveryPort: 0,
  );
}

/// 服务**对外公布**的地址是注入的局域网 IP（手机端就用这个地址连）。
///
/// 测试进程只连得上回环，所以真正发请求时换成 `127.0.0.1` + 同一个端口；
/// 「公布地址 = 局域网 IP」由这里断言钉死，而不是靠「连得上/连不上」来判
/// —— 曾经直接拿假 IP 发请求：那台机器根本不存在 → TCP 连接被重置，
/// 报出来的却是「Connection closed before full header」，误导成服务端不写响应。
String _loopbackOf(String advertisedEndpoint) {
  final uri = Uri.parse(advertisedEndpoint);
  expect(uri.host, _lanHost, reason: '对外公布的必须是局域网地址');
  return 'http://127.0.0.1:${uri.port}';
}

String _errorOf(PairingHttpResponse response) =>
    (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String;

Future<PairingHttpResponse> _rawPost(String url, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close();
    return PairingHttpResponse(
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<PairingHttpResponse> _rawGet(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    return PairingHttpResponse(
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}

Future<PairingHttpResponse> _redeem(String endpoint, Map<String, Object?> body) {
  return _rawPost('$endpoint$kPairingRedeemPath', jsonEncode(body));
}

/// 发一个 UDP 包，收集 [wait] 内收到的全部应答原文。
Future<List<String>> _udpProbe(
  int port,
  String payload, {
  Duration wait = const Duration(milliseconds: 300),
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final replies = <String>[];
    socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      replies.add(utf8.decode(datagram.data, allowMalformed: true));
    });
    final done = Completer<void>();
    Timer(wait, () {
      if (!done.isCompleted) done.complete();
    });
    socket.send(utf8.encode(payload), InternetAddress.loopbackIPv4, port);
    await done.future;
    return replies;
  } finally {
    socket.close();
  }
}

void main() {
  group('DesktopPairingService.start', () {
    test('生成 6 位数字码、按 ttl 定过期时刻、暴露兑换端点与发现端口', () async {
      final generator = _FixedCodeGenerator('042917');
      final service = _buildService(generator: generator);
      addTearDown(service.stop);
      final service2 = _buildService(generator: _FixedCodeGenerator('111111'));
      addTearDown(service2.stop);

      final session = await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      expect(session.code, '042917');
      expect(RegExp(r'^\d{6}$').hasMatch(session.code), isTrue);
      expect(session.baseUrl, _webuiBaseUrl);
      expect(session.installId, _installId);
      expect(session.expiresAt, _baseNow.add(const Duration(minutes: 10)));
      expect(session.isExpiredAt(_baseNow), isFalse);
      // password 是秘密：模型 toString 里不允许出现它。
      expect(session.toString().contains(_password), isFalse);

      expect(identical(service.current, session), isTrue);
      expect(service.pairingEndpoint, startsWith('http://$_lanHost:'));
      expect(service.discoveryBoundPort, isNotNull);
      expect(service.discoveryBoundPort! > 0, isTrue);

      // 自定义 ttl 生效
      final shortSession = await service2.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(seconds: 30),
      );
      expect(shortSession.expiresAt, _baseNow.add(const Duration(seconds: 30)));
      expect(generator.calls, 1, reason: '重新 start 才重新出码');
    });

    test('重复 start 视为重新生成：旧端点关闭、旧码作废', () async {
      final generator = _FixedCodeGenerator('111111');
      final service = _buildService(generator: generator);
      addTearDown(service.stop);

      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final firstAdvertised = service.pairingEndpoint!;

      generator.code = '222222';
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final secondAdvertised = service.pairingEndpoint!;

      expect(secondAdvertised, isNot(firstAdvertised));
      expect(service.current!.code, '222222');
      // 旧端点必须已经彻底关掉（否则旧码还能被兑换）。
      await expectLater(
        _rawGet('${_loopbackOf(firstAdvertised)}$kPairingHealthPath'),
        throwsA(anything),
        reason: '重新出码后旧端点必须已关闭',
      );
      final health = await _rawGet(
        '${_loopbackOf(secondAdvertised)}$kPairingHealthPath',
      );
      expect(health.statusCode, 200);
    });
  });

  group('GET /health', () {
    test('返回 ok/device/installId，且不含密码', () async {
      final service = _buildService();
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      final response = await _rawGet(
        '${_loopbackOf(service.pairingEndpoint!)}$kPairingHealthPath',
      );
      expect(response.statusCode, 200);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      expect(payload['ok'], isTrue);
      expect(payload['device'], _host);
      expect(payload['installId'], _installId);
      expect(response.body.contains(_password), isFalse);
    });
  });

  group('POST /pair', () {
    test('正确配对码 → 200 + 凭据齐备', () async {
      final service = _buildService(generator: _FixedCodeGenerator('654321'));
      addTearDown(service.stop);
      final session = await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      final response = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': session.code,
        'device': 'iPhone 15 Pro',
      });

      expect(response.statusCode, 200);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      expect(payload['baseUrl'], _webuiBaseUrl);
      expect(payload['installId'], _installId);
      // 唯一允许出现密码的地方：这一次性 200 响应体。
      expect(payload['password'], _password);
    });

    test('码错 → 409 wrong_code（不是 expired），且码错不作废会话', () async {
      final service = _buildService(generator: _FixedCodeGenerator('654321'));
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      final response = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '000000',
      });
      expect(response.statusCode, 409);
      expect(_errorOf(response), PairingErrorCodes.wrongCode);
      expect(response.body.contains(_password), isFalse);
      // 码错不作废会话：正确码仍然可用。
      final ok = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '654321',
      });
      expect(ok.statusCode, 200);
    });

    test('过期 → 410 expired（注入时钟推进），且会话原文仍可读供 UI 显示已过期', () async {
      var now = _baseNow;
      final service = _buildService(
        clock: () => now,
        generator: _FixedCodeGenerator('222222'),
      );
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      now = now.add(const Duration(minutes: 10, seconds: 1));

      final response = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '222222',
      });
      expect(response.statusCode, 410);
      expect(_errorOf(response), PairingErrorCodes.expired);
      expect(response.body.contains(_password), isFalse);
      // 模型自带 isExpiredAt：过期不清空 current，UI 才能区分「从未开启」与「刚过期」。
      expect(service.current, isNotNull);
      expect(service.current!.isExpiredAt(now), isTrue);
    });

    test('一次成功兑换即作废：第二次同码 → 410 expired 且不再吐密码', () async {
      final service = _buildService(generator: _FixedCodeGenerator('333333'));
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      final first = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '333333',
      });
      expect(first.statusCode, 200);

      final second = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '333333',
      });
      expect(second.statusCode, 410);
      expect(_errorOf(second), PairingErrorCodes.expired);
      expect(second.body.contains(_password), isFalse);
    });

    test('body 非 JSON / 缺 code / 空 code → 400 bad_request', () async {
      final service = _buildService();
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final endpoint =
          '${_loopbackOf(service.pairingEndpoint!)}$kPairingRedeemPath';

      for (final body in <String>['not-json', '[]', '{}', '{"code":""}', '']) {
        final response = await _rawPost(endpoint, body);
        expect(response.statusCode, 400, reason: 'body=$body');
        expect(
          (jsonDecode(response.body) as Map<String, dynamic>)['error'],
          PairingErrorCodes.badRequest,
        );
        expect(response.body.contains(_password), isFalse);
      }
    });

    test('未知路径 / 错误方法 → 404 not_found', () async {
      final service = _buildService();
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      final unknown = await _rawGet(
        '${_loopbackOf(service.pairingEndpoint!)}/api/status',
      );
      expect(unknown.statusCode, 404);
      expect(_errorOf(unknown), PairingErrorCodes.notFound);
      final wrongMethod = await _rawGet(
        '${_loopbackOf(service.pairingEndpoint!)}$kPairingRedeemPath',
      );
      expect(wrongMethod.statusCode, 404);
      expect(_errorOf(wrongMethod), PairingErrorCodes.notFound);
      expect(unknown.body.contains(_password), isFalse);
      expect(wrongMethod.body.contains(_password), isFalse);
    });

    test('stop 后重新出码：旧码被拒（校验绑定到新会话的码），新码可用', () async {
      final generator = _FixedCodeGenerator('111111');
      final service = _buildService(generator: generator);
      addTearDown(service.stop);

      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final firstEndpoint = _loopbackOf(service.pairingEndpoint!);
      final first = await _redeem(firstEndpoint, <String, Object?>{
        'code': '111111',
      });
      expect(first.statusCode, 200);

      // 重新出码：新会话 + 新码（不复用旧 session 对象/旧校验）
      generator.code = '222222';
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final secondEndpoint = _loopbackOf(service.pairingEndpoint!);

      final oldCode = await _redeem(secondEndpoint, <String, Object?>{
        'code': '111111',
      });
      expect(oldCode.statusCode, 409);
      expect(_errorOf(oldCode), PairingErrorCodes.wrongCode);
      expect(oldCode.body.contains(_password), isFalse);

      final newCode = await _redeem(secondEndpoint, <String, Object?>{
        'code': '222222',
      });
      expect(newCode.statusCode, 200);
      expect(newCode.body.contains(_password), isTrue);
    });
  });

  group('accepted 流', () {
    test('成功兑换时推 PairingAccepted(deviceLabel 来自 body.device, at)', () async {
      final service = _buildService(generator: _FixedCodeGenerator('444444'));
      addTearDown(service.stop);
      final events = <PairingAccepted>[];
      final subscription = service.accepted.listen(events.add);
      addTearDown(subscription.cancel);

      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '000000',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isEmpty, reason: '码错不是一次成功接入');

      await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '444444',
        'device': 'iPhone 15 Pro',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, hasLength(1));
      expect(events.single.deviceLabel, 'iPhone 15 Pro');
      expect(events.single.at, _baseNow);
    });

    test('device 缺省 → 标签退化为「未知设备」', () async {
      final service = _buildService(generator: _FixedCodeGenerator('555555'));
      addTearDown(service.stop);
      final events = <PairingAccepted>[];
      final subscription = service.accepted.listen(events.add);
      addTearDown(subscription.cancel);

      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '555555',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.single.deviceLabel, '未知设备');
    });
  });

  group('UDP 发现应答', () {
    test('收到 HERMEX-PAIR-DISCOVER → 回应答 JSON（含 deviceName/pairingBaseUrl/installId/webuiBaseUrl，不含密码）', () async {
      final service = _buildService(generator: _FixedCodeGenerator('777777'));
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      final replies = await _udpProbe(
        service.discoveryBoundPort!,
        kPairingProbePayload,
      );

      expect(replies, hasLength(1));
      final payload = jsonDecode(replies.single) as Map<String, dynamic>;
      expect(payload['deviceName'], _host);
      expect(payload['pairingBaseUrl'], service.pairingEndpoint);
      expect(payload['installId'], _installId);
      expect(payload['webuiBaseUrl'], _webuiBaseUrl);
      expect(replies.single.contains(_password), isFalse);
      expect(payload.containsKey('password'), isFalse);
    });

    test('非探测包不应答；stop() 后连探测包也不应答', () async {
      final service = _buildService(generator: _FixedCodeGenerator('888888'));
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final port = service.discoveryBoundPort!;

      expect(await _udpProbe(port, 'HELLO-WORLD'), isEmpty);

      await service.stop();
      expect(await _udpProbe(port, kPairingProbePayload), isEmpty);
    });
  });

  group('stop', () {
    test('幂等：连调两次不抛；停后 current 归零、端点不再应答、发现端口释放', () async {
      final service = _buildService();
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      final endpoint = service.pairingEndpoint!;

      await service.stop();
      await service.stop();

      expect(service.current, isNull);
      expect(service.pairingEndpoint, isNull);
      expect(service.discoveryBoundPort, isNull);
      await expectLater(_rawGet('$endpoint$kPairingHealthPath'), throwsA(anything));
    });

    test('stop 后重新 start 仍可用（重新生成）', () async {
      final service = _buildService(generator: _FixedCodeGenerator('999999'));
      addTearDown(service.stop);
      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      await service.stop();

      final session = await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      expect(service.current!.code, session.code);
      final ok = await _redeem(
        _loopbackOf(service.pairingEndpoint!), <String, Object?>{
        'code': '999999',
      });
      expect(ok.statusCode, 200);
    });
  });

  group('安全铁律', () {
    test('配对码用安全随机（1000 次抽样均为 6 位数字且不恒定）', () {
      const generator = SecurePairingCodeGenerator();
      final seen = <String>{};
      for (var i = 0; i < 1000; i++) {
        final code = generator.generate();
        expect(code.length, kPairingCodeLength);
        expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
        seen.add(code);
      }
      expect(seen.length > 100, isTrue, reason: '安全随机不应退化成恒定码');
    });
  });

  group('局域网地址选路器接入（无可用地址不静默、不回落回环）', () {
    test('选路器全探不通 ⇒ 码照出，但 advertisedHost 与 pairingEndpoint 均为 null，发现通道不发假地址', () async {
      final selector = LanAddressSelector(
        listInterfaces: () async => const <LanInterface>[
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
          LanInterface(name: 'Tailscale', ipv4: <String>['100.71.87.11']),
        ],
        readDefaultGateways: () async => const <String>['192.168.1.1'],
        probe: (String host, int port) async => false,
      );
      final service = _buildSelectorService(selector);
      addTearDown(service.stop);

      final session = await service.start(
        baseUrl: 'http://127.0.0.1:8787',
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      expect(session.baseUrl, 'http://127.0.0.1:8787');
      expect(session.code.length, kPairingCodeLength);
      expect(service.current, isNotNull, reason: '出码照常：本机仍可自测 / 手输');
      // 明确状态：没有可用局域网地址 —— 不是「静默公布 127.0.0.1」。
      expect(service.advertisedHost, isNull);
      expect(service.hasAdvertisedLanAddress, isFalse);
      expect(service.pairingEndpoint, isNull);

      expect(
        await _udpProbe(service.discoveryBoundPort!, kPairingProbePayload),
        isEmpty,
        reason: '没有可用地址就不许公布任何地址（更不许公布回环）',
      );
    });

    test('第一个候选探不通、第二个通 ⇒ 公布第二个；探活打的就是本服务刚绑定的端口', () async {
      final probedPorts = <int>[];
      final selector = LanAddressSelector(
        listInterfaces: () async => const <LanInterface>[
          LanInterface(name: '以太网', ipv4: <String>['192.168.1.77']),
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
        ],
        readDefaultGateways: () async => const <String>['192.168.1.1'],
        probe: (String host, int port) async {
          probedPorts.add(port);
          return host == '192.168.1.95';
        },
      );
      final service = _buildSelectorService(selector);
      addTearDown(service.stop);

      await service.start(
        baseUrl: 'http://127.0.0.1:8787',
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      expect(probedPorts, hasLength(2), reason: '第一个探不通要换下一个继续探');
      expect(probedPorts.toSet(), hasLength(1), reason: '同一轮的探活端口必须一致');
      expect(service.advertisedHost, '192.168.1.95');
      expect(service.hasAdvertisedLanAddress, isTrue);

      final endpoint = Uri.parse(service.pairingEndpoint!);
      expect(endpoint.host, '192.168.1.95');
      expect(
        endpoint.port,
        probedPorts.first,
        reason: '探活端口 = 刚绑定的配对端口，而不是 baseUrl 里的 8787',
      );
      // 证明确实是本服务的端口：同端口回环能拿到 /health 200。
      final health = await _rawGet(
        'http://127.0.0.1:${endpoint.port}$kPairingHealthPath',
      );
      expect(health.statusCode, 200);
      expect(health.body.contains(_password), isFalse);
    });

    test('stop() 后公布地址归零，不留上一轮残留', () async {
      final selector = LanAddressSelector(
        listInterfaces: () async => const <LanInterface>[
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
        ],
        readDefaultGateways: () async => const <String>['192.168.1.1'],
        probe: (String host, int port) async => true,
      );
      final service = _buildSelectorService(selector);
      addTearDown(service.stop);

      await service.start(
        baseUrl: 'http://127.0.0.1:8787',
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );
      expect(service.advertisedHost, '192.168.1.95');

      await service.stop();
      expect(service.advertisedHost, isNull);
      expect(service.hasAdvertisedLanAddress, isFalse);
      expect(service.pairingEndpoint, isNull);
    });

    test('resolvePairingAdvertisedHost 把 baseUrl 的 host 当显式候选交给选路器；回环 baseUrl 不会被当成可公布地址', () async {
      final seen = <String>[];
      final selector = LanAddressSelector(
        listInterfaces: () async => const <LanInterface>[],
        readDefaultGateways: () async => const <String>[],
        probe: (String host, int port) async {
          seen.add('$host:$port');
          return host == '192.168.1.95';
        },
      );

      expect(
        await resolvePairingAdvertisedHost(
          'http://192.168.1.95:8787',
          probePort: 38911,
          selector: selector,
        ),
        '192.168.1.95',
      );
      expect(seen, <String>['192.168.1.95:38911']);

      expect(
        await resolvePairingAdvertisedHost(
          'http://127.0.0.1:8787',
          probePort: 38911,
          selector: selector,
        ),
        isNull,
        reason: '回环 host 不入候选，且没有网卡时返回 null 而不是 127.0.0.1',
      );
      expect(seen, <String>['192.168.1.95:38911'], reason: '回环 host 连线都不该进候选');
    });
  });

  group('注入点优先级（老 advertisedHostResolver 仍然说了算）', () {
    test('注入了 advertisedHostResolver ⇒ 选路器完全不参与（一次探活都不做）', () async {
      final probed = <String>[];
      final selector = LanAddressSelector(
        listInterfaces: () async => const <LanInterface>[
          LanInterface(name: 'WLAN', ipv4: <String>['192.168.1.95']),
        ],
        readDefaultGateways: () async => const <String>[],
        probe: (String host, int port) async {
          probed.add(host);
          return true;
        },
      );
      final service = _buildSelectorService(
        selector,
        resolver: (String baseUrl) async => '10.9.9.9',
      );
      addTearDown(service.stop);

      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      expect(service.advertisedHost, '10.9.9.9');
      expect(service.pairingEndpoint, startsWith('http://10.9.9.9:'));
      expect(probed, isEmpty);
    });

    test('注入的 resolver 返回空串 ⇒ 同样算「没有可用地址」，不回落回环', () async {
      final service = _buildSelectorService(
        const LanAddressSelector(),
        resolver: (String baseUrl) async => '',
      );
      addTearDown(service.stop);

      await service.start(
        baseUrl: _webuiBaseUrl,
        password: _password,
        installId: _installId,
        ttl: const Duration(minutes: 10),
      );

      expect(service.current, isNotNull);
      expect(service.advertisedHost, isNull);
      expect(service.hasAdvertisedLanAddress, isFalse);
      expect(service.pairingEndpoint, isNull);
    });

    test('注入的 resolver 抛异常 ⇒ start 抛出，且不留半截会话 / 半开监听', () async {
      final service = _buildSelectorService(
        const LanAddressSelector(),
        resolver: (String baseUrl) async => throw StateError('boom'),
      );
      addTearDown(service.stop);

      await expectLater(
        service.start(
          baseUrl: _webuiBaseUrl,
          password: _password,
          installId: _installId,
          ttl: const Duration(minutes: 10),
        ),
        throwsA(isA<StateError>()),
      );

      expect(service.current, isNull);
      expect(service.advertisedHost, isNull);
      expect(service.pairingEndpoint, isNull);
      expect(service.discoveryBoundPort, isNull);
    });
  });
}

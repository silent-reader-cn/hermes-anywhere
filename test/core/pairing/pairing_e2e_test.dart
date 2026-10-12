import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/pairing/pairing_client.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/core/pairing/pairing_service.dart';

/// 桌面端服务 + 手机端客户端的**真实全链路**测试：真实 HttpServer、真实 UDP 广播、
/// 真实 HttpClient。验证两端线协议（路径 / 字段名 / 错误码）确实对得上 ——
/// 这是 fake 之间互相自证永远发现不了的那类故障。
void main() {
  const String password = 'e2e-pw-SECRET';
  const String installId = 'e2e-install';
  const String webuiBaseUrl = 'http://192.168.1.7:8787';
  const String code = '246810';

  late DesktopPairingService service;

  setUp(() async {
    service = DesktopPairingService(
      codeGenerator: const _ConstCodeGenerator(code),
      hostNameResolver: () => 'E2E-PC',
      // 广播出去的地址必须是**这台测试机真能连上**的地址，否则「全链路」跑不通：
      // 假 LAN IP 会让 TCP 连接被重置，测出来的只是网络环境而不是协议。
      // 「公布地址用局域网 IP」由 pairing_service_test 的 _loopbackOf 断言钉住。
      advertisedHostResolver: (String baseUrl) async => '127.0.0.1',
      httpBindAddress: InternetAddress.loopbackIPv4,
      discoveryBindAddress: InternetAddress.loopbackIPv4,
      discoveryPort: 0,
    );
  });

  tearDown(() async {
    await service.stop();
  });

  /// 指向本机回环 + 服务的临时发现端口的客户端（生产用广播地址）。
  MobilePairingClient buildClient({String deviceLabel = ''}) {
    return MobilePairingClient(
      discoveryAddress: '127.0.0.1',
      discoveryPort: service.discoveryBoundPort!,
      deviceLabel: deviceLabel,
      redeemTimeout: const Duration(seconds: 5),
    );
  }

  test('发现 → 兑换 → 拿到可用凭据（真实 HTTP + UDP 全链路）', () async {
    final accepted = <PairingAccepted>[];
    final subscription = service.accepted.listen(accepted.add);
    addTearDown(subscription.cancel);

    final session = await service.start(
      baseUrl: webuiBaseUrl,
      password: password,
      installId: installId,
      ttl: const Duration(minutes: 10),
    );
    expect(session.code, code);

    final client = buildClient(deviceLabel: 'iPhone 15 Pro');
    final candidates = await client.discover(
      timeout: const Duration(milliseconds: 500),
    );

    expect(candidates, hasLength(1));
    final candidate = candidates.single;
    expect(candidate.deviceName, 'E2E-PC');
    expect(candidate.installId, installId);
    expect(candidate.webuiBaseUrl, webuiBaseUrl);
    expect(candidate.pairingBaseUrl, service.pairingEndpoint);
    expect(Uri.parse(candidate.pairingBaseUrl).port, Uri.parse(service.pairingEndpoint!).port);

    final credentials = await client.redeem(
      pairingBaseUrl: candidate.pairingBaseUrl,
      code: session.code,
    );
    expect(credentials.baseUrl, webuiBaseUrl);
    expect(credentials.password, password);
    expect(credentials.installId, installId);

    // 桌面端从 accepted 流看到「手机已连上」（标签由手机端上报）。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(accepted, hasLength(1));
    expect(accepted.single.deviceLabel, 'iPhone 15 Pro');
  });

  test('配对码一次性：第二次兑换 → expired（且不再吐密码）', () async {
    final session = await service.start(
      baseUrl: webuiBaseUrl,
      password: password,
      installId: installId,
      ttl: const Duration(minutes: 10),
    );
    final client = buildClient();

    final first = await client.redeem(
      pairingBaseUrl: service.pairingEndpoint!,
      code: session.code,
    );
    expect(first.password, password);

    try {
      await client.redeem(
        pairingBaseUrl: service.pairingEndpoint!,
        code: session.code,
      );
      fail('第二次兑换不该成功');
    } on PairingException catch (error) {
      expect(error.reason, PairingFailure.expired);
      expect(error.detail.contains(password), isFalse);
    }
  });

  test('对端取消/停止配对后兑换 → network（连接被拒）', () async {
    final session = await service.start(
      baseUrl: webuiBaseUrl,
      password: password,
      installId: installId,
      ttl: const Duration(minutes: 10),
    );
    final endpoint = service.pairingEndpoint!;
    final client = buildClient();

    await service.stop();

    try {
      await client.redeem(pairingBaseUrl: endpoint, code: session.code);
      fail('停止配对后不该还能兑换');
    } on PairingException catch (error) {
      expect(error.reason, PairingFailure.network);
    }
  });

  test('没有对端时 discover 超时 → 空列表，不抛异常', () async {
    final session = await service.start(
      baseUrl: webuiBaseUrl,
      password: password,
      installId: installId,
      ttl: const Duration(minutes: 10),
    );
    expect(session.code, code);
    final port = service.discoveryBoundPort!;
    await service.stop();

    final client = MobilePairingClient(
      discoveryAddress: '127.0.0.1',
      discoveryPort: port,
    );
    final candidates = await client.discover(
      timeout: const Duration(milliseconds: 300),
    );
    expect(candidates, isEmpty);
  });
}

class _ConstCodeGenerator implements PairingCodeGenerator {
  const _ConstCodeGenerator(this.code);

  final String code;

  @override
  String generate() => code;
}

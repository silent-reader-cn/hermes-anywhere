import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/pairing/pairing_client.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/core/pairing/pairing_service.dart';

/// 记录调用参数的发现传输 fake。
class _FakeDiscoveryTransport implements DiscoveryTransport {
  _FakeDiscoveryTransport({this.replies = const <String>[], this.error});

  List<String> replies;
  Object? error;
  int calls = 0;
  String? lastPayload;
  String? lastAddress;
  int? lastPort;
  Duration? lastTimeout;

  @override
  Future<List<String>> probe({
    required String payload,
    required String address,
    required int port,
    required Duration timeout,
  }) async {
    calls++;
    lastPayload = payload;
    lastAddress = address;
    lastPort = port;
    lastTimeout = timeout;
    final failure = error;
    if (failure != null) throw failure;
    return replies;
  }
}

/// 记录调用参数的 HTTP 传输 fake。
class _FakeHttpTransport implements PairingHttpTransport {
  _FakeHttpTransport({this.response, this.error});

  PairingHttpResponse? response;
  Object? error;
  int calls = 0;
  String? lastUrl;
  Map<String, Object?>? lastBody;
  Duration? lastTimeout;

  @override
  Future<PairingHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Duration timeout = kPairingRedeemTimeout,
  }) async {
    calls++;
    lastUrl = url;
    lastBody = body;
    lastTimeout = timeout;
    final failure = error;
    if (failure != null) throw failure;
    return response!;
  }
}

/// 一个「假对端」：用真实 HttpServer 按路径返回脚本化响应，
/// 让映射表跑在真实 HTTP 之上（不是拿 fake 自证 fake）。
class _MiniPeer {
  HttpServer? _server;

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((HttpRequest request) {
      unawaited(_handle(request));
    });
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await utf8.decoder.bind(request).join();
      // 客户端会往 `<base>/pair` 打请求，所以按**首段路径**路由，不能整段相等比较。
      final segments = request.uri.pathSegments;
      final route = segments.isEmpty ? '' : segments.first;
      switch (route) {
        case 'ok':
          await _write(
            request,
            200,
            '{"baseUrl":"http://peer:8787","password":"peer-pw","installId":"peer-1"}',
          );
        case 'html':
          await _write(request, 200, '<html><body>nginx</body></html>');
        case 'leak':
          // 200 但 schema 不对，且响应体里带着像密码的字段 —— 绝不能被回显到错误里。
          await _write(
            request,
            200,
            '{"password":"LEAKED-SECRET","baseUrl":"","note":"not-hermes"}',
          );
        case 'wrong':
          // 401 + 显式错误码（不少服务/网关把「凭据不对」报成 401）。
          await _write(request, 401, '{"error":"wrong_code"}');
        case 'unauth':
          await _write(request, 401, '{}');
        case 'conflict':
          await _write(request, 409, '{}');
        case 'conflictcode':
          await _write(request, 409, '{"error":"wrong_code"}');
        case 'gone':
          await _write(request, 410, '{"error":"expired"}');
        case 'goneplain':
          await _write(request, 410, '{}');
        case 'nosession':
          await _write(request, 503, '{"error":"no_session"}');
        case 'busy':
          await _write(request, 503, '{}');
        case 'missing':
          await _write(request, 404, '<html>404 nope</html>');
        case 'notfound':
          await _write(request, 404, '{"error":"not_found"}');
        case 'boom':
          await _write(request, 500, 'internal boom');
        case 'slow':
          await Future<void>.delayed(const Duration(seconds: 3));
          await _write(request, 200, '{}');
        default:
          await _write(request, 404, '{}');
      }
    } catch (_) {
      // 客户端提前断开（超时用例）—— 忽略。
    }
  }

  Future<void> _write(HttpRequest request, int statusCode, String body) async {
    try {
      request.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(body);
      await request.response.close();
    } catch (_) {
      // 对端已断开。
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}

String _candidateReply({
  String deviceName = 'DESKTOP-7F3A',
  String pairingBaseUrl = 'http://192.168.1.7:38911',
  String installId = 'install-1',
  String webuiBaseUrl = 'http://192.168.1.7:8787',
}) {
  return jsonEncode(<String, Object?>{
    'deviceName': deviceName,
    'pairingBaseUrl': pairingBaseUrl,
    'installId': installId,
    'webuiBaseUrl': webuiBaseUrl,
  });
}

/// 断言 [action] 抛出指定原因的 [PairingException]。
Future<PairingException> _expectFailure(
  Future<void> Function() action,
  PairingFailure expected,
) async {
  try {
    await action();
  } on PairingException catch (error) {
    expect(error.reason, expected);
    return error;
  }
  fail('期望抛 PairingException(${expected.name})，但没有抛异常');
}

void main() {
  group('discover', () {
    test('解析应答为候选，并把探测内容/目标地址/端口/超时透传给传输层', () async {
      final transport = _FakeDiscoveryTransport(
        replies: <String>[_candidateReply()],
      );
      final client = MobilePairingClient(discoveryTransport: transport);

      final candidates = await client.discover(
        timeout: const Duration(milliseconds: 750),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.deviceName, 'DESKTOP-7F3A');
      expect(candidates.single.pairingBaseUrl, 'http://192.168.1.7:38911');
      expect(candidates.single.installId, 'install-1');
      expect(candidates.single.webuiBaseUrl, 'http://192.168.1.7:8787');

      expect(transport.calls, 1);
      expect(transport.lastPayload, kPairingProbePayload);
      expect(transport.lastAddress, '255.255.255.255');
      expect(transport.lastPort, kPairingDiscoveryPort);
      expect(transport.lastTimeout, const Duration(milliseconds: 750));
    });

    test('同一 installId 去重（多网卡重复应答只留一条）', () async {
      final transport = _FakeDiscoveryTransport(
        replies: <String>[
          _candidateReply(pairingBaseUrl: 'http://192.168.1.7:38911'),
          _candidateReply(pairingBaseUrl: 'http://10.0.0.7:38911'),
          _candidateReply(installId: 'install-2', deviceName: 'PC-2'),
        ],
      );
      final client = MobilePairingClient(discoveryTransport: transport);

      final candidates = await client.discover();

      expect(candidates, hasLength(2));
      expect(candidates.first.installId, 'install-1');
      expect(candidates.first.pairingBaseUrl, 'http://192.168.1.7:38911');
      expect(candidates.last.installId, 'install-2');
    });

    test('垃圾应答（非 JSON / 缺关键字段 / 非法地址）被跳过', () async {
      final transport = _FakeDiscoveryTransport(
        replies: <String>[
          'not json at all',
          '[]',
          '{"installId":"x"}',
          '{"pairingBaseUrl":"http://a:1"}',
          '{"pairingBaseUrl":"ftp://a:1","installId":"y"}',
          '{"pairingBaseUrl":"","installId":"z"}',
          _candidateReply(),
        ],
      );
      final client = MobilePairingClient(discoveryTransport: transport);

      final candidates = await client.discover();

      expect(candidates, hasLength(1));
      expect(candidates.single.installId, 'install-1');
    });

    test('deviceName 缺失 → 退化为「未知设备」', () async {
      final transport = _FakeDiscoveryTransport(
        replies: <String>['{"pairingBaseUrl":"http://a:1","installId":"z"}'],
      );
      final client = MobilePairingClient(discoveryTransport: transport);

      final candidates = await client.discover();

      expect(candidates.single.deviceName, '未知设备');
      expect(candidates.single.webuiBaseUrl, '');
    });

    test('超时（传输层抛 TimeoutException）→ 返回空列表，不抛异常', () async {
      final transport = _FakeDiscoveryTransport(
        error: TimeoutException('discover timeout'),
      );
      final client = MobilePairingClient(discoveryTransport: transport);

      expect(await client.discover(), isEmpty);
      expect(transport.calls, 1);
    });

    test('网络不可用（传输层抛 SocketException）→ 返回空列表，不抛异常', () async {
      final transport = _FakeDiscoveryTransport(
        error: const SocketException('no route to host'),
      );
      final client = MobilePairingClient(discoveryTransport: transport);

      expect(await client.discover(), isEmpty);
    });
  });

  group('redeem（fake 传输：超时 / 不可达 / 本地格式校验）', () {
    test('码格式非法（非 6 位数字）→ wrongCode，且不做网络往返', () async {
      final transport = _FakeHttpTransport(
        response: const PairingHttpResponse(statusCode: 200, body: '{}'),
      );
      final client = MobilePairingClient(httpTransport: transport);

      for (final code in <String>['12345', '1234567', '12a456', '', '  ']) {
        final error = await _expectFailure(
          () => client.redeem(
            pairingBaseUrl: 'http://192.168.1.7:38911',
            code: code,
          ),
          PairingFailure.wrongCode,
        );
        expect(error.detail.isNotEmpty, isTrue);
      }
      expect(transport.calls, 0, reason: '格式错误不该打扰对端');
    });

    test('连接失败（SocketException）→ network', () async {
      final transport = _FakeHttpTransport(
        error: const SocketException('connection refused'),
      );
      final client = MobilePairingClient(httpTransport: transport);

      final error = await _expectFailure(
        () => client.redeem(
          pairingBaseUrl: 'http://192.168.1.7:38911',
          code: '123456',
        ),
        PairingFailure.network,
      );
      expect(error.detail.contains('123456'), isFalse, reason: '错误文案不回显配对码');
    });

    test('网络超时（TimeoutException）→ network', () async {
      final transport = _FakeHttpTransport(
        error: TimeoutException('redeem timeout'),
      );
      final client = MobilePairingClient(httpTransport: transport);

      await _expectFailure(
        () => client.redeem(
          pairingBaseUrl: 'http://192.168.1.7:38911',
          code: '123456',
        ),
        PairingFailure.network,
      );
    });

    test('未预期的传输异常 → network（不把异常抛给 UI 层）', () async {
      final transport = _FakeHttpTransport(error: StateError('boom'));
      final client = MobilePairingClient(httpTransport: transport);

      await _expectFailure(
        () => client.redeem(
          pairingBaseUrl: 'http://192.168.1.7:38911',
          code: '123456',
        ),
        PairingFailure.network,
      );
    });

    test('配对地址非法（空 / 非 http）→ unavailable，不打网络', () async {
      final transport = _FakeHttpTransport();
      final client = MobilePairingClient(httpTransport: transport);

      for (final url in <String>['', 'not-a-url', 'ftp://host:1']) {
        await _expectFailure(
          () => client.redeem(pairingBaseUrl: url, code: '123456'),
          PairingFailure.unavailable,
        );
      }
      expect(transport.calls, 0);
    });

    test('deviceLabel 随请求上报（桌面端据此显示接入设备）', () async {
      final transport = _FakeHttpTransport(
        response: const PairingHttpResponse(
          statusCode: 200,
          body:
              '{"baseUrl":"http://pc:8787","password":"pw","installId":"i-1"}',
        ),
      );
      final client = MobilePairingClient(
        httpTransport: transport,
        deviceLabel: 'iPhone 15 Pro',
      );

      await client.redeem(
        pairingBaseUrl: 'http://192.168.1.7:38911',
        code: '123456',
      );

      expect(transport.lastUrl, 'http://192.168.1.7:38911$kPairingRedeemPath');
      expect(transport.lastBody, <String, Object?>{
        'code': '123456',
        'device': 'iPhone 15 Pro',
      });
    });
  });

  group('redeem（真实 HTTP：状态码/错误体映射表）', () {
    late _MiniPeer peer;

    setUp(() async {
      peer = _MiniPeer();
      await peer.start();
    });

    tearDown(() async {
      await peer.stop();
    });

    Future<PairingException> redeemPath(
      String path,
      PairingFailure expected, {
      Duration timeout = const Duration(seconds: 5),
    }) {
      final client = MobilePairingClient(redeemTimeout: timeout);
      return _expectFailure(
        () => client.redeem(pairingBaseUrl: '${peer.baseUrl}$path', code: '123456'),
        expected,
      );
    }

    test('200 + 合法 schema → 返回凭据', () async {
      final client = MobilePairingClient();
      final credentials = await client.redeem(
        pairingBaseUrl: '${peer.baseUrl}/ok',
        code: '123456',
      );

      expect(credentials.baseUrl, 'http://peer:8787');
      expect(credentials.password, 'peer-pw');
      expect(credentials.installId, 'peer-1');
      // 凭据模型没有 toJson / 自定义 toString，密码不会随日志打印出去。
      expect(credentials.toString().contains('peer-pw'), isFalse);
    });

    test('200 但内容不是 Hermes schema（HTML）→ unavailable', () async {
      await redeemPath('/html', PairingFailure.unavailable);
    });

    test('200 但 schema 不对且响应体带敏感字段 → unavailable，且错误里不回显响应体', () async {
      final error = await redeemPath('/leak', PairingFailure.unavailable);
      expect(error.detail.contains('LEAKED-SECRET'), isFalse);
      expect(error.toString().contains('LEAKED-SECRET'), isFalse);
      // 错误文案是一组写死的中文短语，不掺任何响应体内容。
      expect(error.detail, '对方不是 Hermes 配对服务');
    });

    test('401 + wrong_code → wrongCode（兼容把凭据错误报成 401 的对端）', () async {
      await redeemPath('/wrong', PairingFailure.wrongCode);
    });

    test('401 无错误体 → wrongCode（状态码回落）', () async {
      await redeemPath('/unauth', PairingFailure.wrongCode);
    });

    test('409 无错误体 → wrongCode', () async {
      await redeemPath('/conflict', PairingFailure.wrongCode);
    });

    test('409 + wrong_code → wrongCode', () async {
      await redeemPath('/conflictcode', PairingFailure.wrongCode);
    });

    test('410 + expired → expired', () async {
      await redeemPath('/gone', PairingFailure.expired);
    });

    test('410 无错误体 → expired（状态码回落）', () async {
      await redeemPath('/goneplain', PairingFailure.expired);
    });

    test('503 + no_session（对端已关闭配对）→ cancelled', () async {
      await redeemPath('/nosession', PairingFailure.cancelled);
    });

    test('503 无错误体 → unavailable（对端不可用，不是码错）', () async {
      await redeemPath('/busy', PairingFailure.unavailable);
    });

    test('404 非 JSON（多半不是 Hermes 服务）→ unavailable', () async {
      await redeemPath('/missing', PairingFailure.unavailable);
    });

    test('404 JSON not_found → unavailable', () async {
      await redeemPath('/notfound', PairingFailure.unavailable);
    });

    test('500 → unavailable（对端异常，不是码错）', () async {
      await redeemPath('/boom', PairingFailure.unavailable);
    });

    test('对端不可达（端口已关）→ network', () async {
      final deadPort = peer.baseUrl;
      await peer.stop();
      final client = MobilePairingClient();
      await _expectFailure(
        () => client.redeem(pairingBaseUrl: deadPort, code: '123456'),
        PairingFailure.network,
      );
    });

    test('网络超时（对端不响应，客户端 200ms 超时）→ network', () async {
      await redeemPath(
        '/slow',
        PairingFailure.network,
        timeout: const Duration(milliseconds: 200),
      );
    });
  });
}

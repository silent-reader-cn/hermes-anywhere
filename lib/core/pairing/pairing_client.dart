/// 手机端配对客户端实现（纯 Dart + dart:io，不依赖 UI）。
///
/// 职责（对照 `pairing_contract.dart` 的 [PairingClient]）：
/// - `discover()`：向 `255.255.255.255:39393` 广播探测包，收集应答并解析成候选；
///   超时/无网卡权限一律返回**空列表**，绝不抛异常；
/// - `redeem()`：`POST /pair` 用配对码换凭据，按 HTTP 状态 + 错误体映射 [PairingFailure]。
///
/// ## 线协议常量来自哪
/// 探测包内容 / 发现端口 / 路径 / 错误码定义在 `pairing_service.dart`（服务端一侧），
/// 本文件引用它们而不是复制一份 —— 契约文件本次冻结不可改，且两端字符串一旦漂移
/// 会静默变成「发现不到设备」这种最难查的故障。
///
/// ## 线协议（服务端 `pairing_service.dart` 出同一张表）
/// | 状态码 | 错误体 | 失败原因 |
/// | --- | --- | --- |
/// | 200 | 合法 schema | 成功（唯一会看到 password 的分支） |
/// | 200 | 非本服务 schema | [PairingFailure.unavailable] |
/// | 400 / 401 / 409 | 无 error 字段 | [PairingFailure.wrongCode] |
/// | 409 | `wrong_code` | [PairingFailure.wrongCode] |
/// | 410 | `expired`（或空） | [PairingFailure.expired] |
/// | 503 | `no_session` | [PairingFailure.cancelled] |
/// | 404 | 任意 | [PairingFailure.unavailable] |
/// | 其它 4xx/5xx | 任意 | [PairingFailure.unavailable] |
/// | 连接被拒 / 超时 | — | [PairingFailure.network] |
///
/// ## 安全铁律
/// 凭据里的 password 是秘密：不写日志、不进 `toString`、不进错误 detail。
/// 服务端异常响应体（可能带敏感字段）也**只**用于判定失败原因，不会被回显
/// ——错误文案一律取自本文件里写死的固定短语。
///
/// ## 可测性
/// HTTP 传输与 UDP 发现都抽成可注入接口；单测用 fake 覆盖超时 / 不可达 / 码错 / 过期，
/// 另有真实回环 socket 的端到端用例（见 test/core/pairing/）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pairing_contract.dart';
import 'pairing_service.dart'
    show
        PairingErrorCodes,
        decodePairingJsonObject,
        kPairingDiscoveryPort,
        kPairingProbePayload,
        kPairingRedeemPath;

/// 兑换请求默认超时。
const Duration kPairingRedeemTimeout = Duration(seconds: 6);

/// 发现请求默认超时。
const Duration kPairingDiscoverTimeout = Duration(seconds: 3);

/// 配对码格式：6 位数字。
final RegExp pairingCodePattern = RegExp('^\\d{6}\$');

/// 一次 HTTP 响应（只保留判定失败所需的最小信息）。
class PairingHttpResponse {
  const PairingHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

/// 兑换用的 HTTP 传输接缝（单测注入 fake）。
abstract interface class PairingHttpTransport {
  /// `POST [url]`，JSON 请求体；超时抛 [TimeoutException]，连接失败抛 [SocketException]。
  Future<PairingHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Duration timeout,
  });
}

/// 生产传输：`dart:io HttpClient`。
class DartPairingHttpTransport implements PairingHttpTransport {
  const DartPairingHttpTransport();

  @override
  Future<PairingHttpResponse> postJson(
    String url,
    Map<String, Object?> body, {
    Duration timeout = kPairingRedeemTimeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(Uri.parse(url)).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      return PairingHttpResponse(
        statusCode: response.statusCode,
        body: text,
      );
    } finally {
      // 超时/失败都要把连接强制收掉，否则半开连接会攒在 HttpClient 里。
      client.close(force: true);
    }
  }
}

/// 局域网发现传输接缝（单测注入 fake）。
abstract interface class DiscoveryTransport {
  /// 广播 [payload] 到 `[address]:[port]`，收集 [timeout] 内收到的应答原文。
  Future<List<String>> probe({
    required String payload,
    required String address,
    required int port,
    required Duration timeout,
  });
}

/// 生产发现传输：UDP 广播 + 收包到超时。
class UdpDiscoveryTransport implements DiscoveryTransport {
  const UdpDiscoveryTransport();

  @override
  Future<List<String>> probe({
    required String payload,
    required String address,
    required int port,
    required Duration timeout,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    StreamSubscription<RawSocketEvent>? subscription;
    final replies = <String>[];
    try {
      try {
        socket.broadcastEnabled = true;
      } catch (_) {
        // 受限环境不允许广播 → 交给外层超时兜底为「空列表」。
      }
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        replies.add(utf8.decode(datagram.data, allowMalformed: true));
      });
      final done = Completer<void>();
      final timer = Timer(timeout, () {
        if (!done.isCompleted) done.complete();
      });
      socket.send(utf8.encode(payload), InternetAddress(address), port);
      await done.future;
      timer.cancel();
    } finally {
      if (subscription != null) {
        try {
          await subscription.cancel();
        } catch (_) {}
      }
      socket.close();
    }
    return replies;
  }
}

/// 手机端配对客户端。
class MobilePairingClient implements PairingClient {
  MobilePairingClient({
    this.httpTransport = const DartPairingHttpTransport(),
    this.discoveryTransport = const UdpDiscoveryTransport(),
    this.discoveryAddress = '255.255.255.255',
    this.discoveryPort = kPairingDiscoveryPort,
    this.redeemTimeout = kPairingRedeemTimeout,
    this.deviceLabel = '',
  });

  /// 兑换请求传输（可注入供单测替换）。
  final PairingHttpTransport httpTransport;

  /// 局域网发现传输（可注入供单测替换）。
  final DiscoveryTransport discoveryTransport;

  /// 发现广播目标地址（默认全广播；单测/特殊网络可指向具体地址）。
  final String discoveryAddress;

  /// 发现广播目标端口。
  final int discoveryPort;

  /// 兑换请求超时。
  final Duration redeemTimeout;

  /// 本机设备标签，随兑换请求上报，桌面端据此在向导里显示「XX 已连上」。
  /// 契约的 `redeem()` 没有该参数（模型 `PairingAccepted.deviceLabel` 却需要它），
  /// 故改为构造期注入，见终报「契约缺口」。
  final String deviceLabel;

  @override
  Future<List<PairingCandidate>> discover({
    Duration timeout = kPairingDiscoverTimeout,
  }) async {
    List<String> replies;
    try {
      replies = await discoveryTransport.probe(
        payload: kPairingProbePayload,
        address: discoveryAddress,
        port: discoveryPort,
        timeout: timeout,
      );
    } catch (_) {
      // 契约明文：发现失败返回空列表，不抛异常。
      return const <PairingCandidate>[];
    }

    final seenInstallIds = <String>{};
    final candidates = <PairingCandidate>[];
    for (final reply in replies) {
      final candidate = parsePairingCandidate(reply);
      if (candidate == null) continue;
      // 多网卡 / 重复应答会带来同一 installId 的多条结果 —— 去重（保留首条）。
      if (!seenInstallIds.add(candidate.installId)) continue;
      candidates.add(candidate);
    }
    return candidates;
  }

  @override
  Future<PairingCredentials> redeem({
    required String pairingBaseUrl,
    required String code,
  }) async {
    final base = _normalizeBaseUrl(pairingBaseUrl);
    if (base == null) {
      throw const PairingException(
        PairingFailure.unavailable,
        '配对地址无效，请重新发现设备',
      );
    }
    final normalizedCode = code.trim();
    if (!pairingCodePattern.hasMatch(normalizedCode)) {
      // 本地就能判定的格式错误：不要打扰对端，也别把它记成网络故障。
      throw const PairingException(
        PairingFailure.wrongCode,
        '配对码应为 6 位数字',
      );
    }

    PairingHttpResponse response;
    try {
      response = await httpTransport.postJson(
        '$base$kPairingRedeemPath',
        <String, Object?>{
          'code': normalizedCode,
          if (deviceLabel.isNotEmpty) 'device': deviceLabel,
        },
        timeout: redeemTimeout,
      );
    } on TimeoutException {
      throw const PairingException(
        PairingFailure.network,
        '连接超时，请确认手机与电脑在同一局域网',
      );
    } on SocketException {
      throw const PairingException(
        PairingFailure.network,
        '无法连接对方，请确认电脑端配对仍开启',
      );
    } on HttpException {
      throw const PairingException(PairingFailure.network, '网络异常，请稍后重试');
    } on FormatException {
      throw const PairingException(PairingFailure.unavailable, '配对地址格式不正确');
    } catch (_) {
      throw const PairingException(PairingFailure.network, '网络异常，请稍后重试');
    }

    final payload = decodePairingJsonObject(response.body);
    if (response.statusCode == HttpStatus.ok) {
      // 非 Hermes 对端可能回 200 但内容不是我们的 schema —— 判为不可用。
      // 注意：响应体（可能带敏感字段）只用于判定，绝不回显到错误里。
      final baseUrl = _stringOf(payload?['baseUrl']);
      final password = _stringOf(payload?['password']);
      final installId = _stringOf(payload?['installId']);
      if (payload == null || baseUrl.isEmpty || password.isEmpty) {
        throw const PairingException(
          PairingFailure.unavailable,
          '对方不是 Hermes 配对服务',
        );
      }
      return PairingCredentials(
        baseUrl: baseUrl,
        password: password,
        installId: installId,
      );
    }

    final reason = _mapFailure(
      response.statusCode,
      _stringOf(payload?['error']),
    );
    throw PairingException(reason, _detailForFailure(reason));
  }

  String? _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

/// 状态码 + 错误体 → 失败原因。
///
/// 优先级：**服务端显式 error 字段 > 状态码**。桌面端需要用
/// `410 + {"error":"expired"}`（码过期或已被兑换）与
/// `503 + {"error":"no_session"}`（用户已取消/配对已停止）区分两种「码用不了」；
/// 只按状态码会把「配对已停止」误报成「码已过期」，用户按提示重试必然再次失败。
///
/// 无显式 error 字段时的状态码口径（与桌面端实现同一张表）：
/// - 400 / 401 / 409 → [PairingFailure.wrongCode]（401 是不少服务/网关对
///   「凭据不对」的口径，一并容忍）；
/// - 410 → [PairingFailure.expired]（对端明确说「这东西没了」）；
/// - 404 及其它 → [PairingFailure.unavailable]（路径都没有 ⇒ 多半不是 Hermes
///   配对服务，而不是「码写错了」——选 unavailable 更能让界面给出可行动的文案）。
PairingFailure _mapFailure(int statusCode, String errorCode) {
  switch (errorCode) {
    case PairingErrorCodes.wrongCode:
    case PairingErrorCodes.badRequest:
      return PairingFailure.wrongCode;
    case PairingErrorCodes.expired:
      return PairingFailure.expired;
    case PairingErrorCodes.noSession:
      return PairingFailure.cancelled;
    case PairingErrorCodes.notFound:
      return PairingFailure.unavailable;
  }
  switch (statusCode) {
    case HttpStatus.badRequest:
    case HttpStatus.unauthorized:
    case HttpStatus.conflict:
      return PairingFailure.wrongCode;
    case HttpStatus.gone:
      return PairingFailure.expired;
    default:
      return PairingFailure.unavailable;
  }
}

/// 失败原因的**中文文案**（给用户看，不含任何响应体内容/堆栈）。
String _detailForFailure(PairingFailure reason) {
  switch (reason) {
    case PairingFailure.wrongCode:
      return '配对码不正确，请核对电脑上显示的 6 位数字';
    case PairingFailure.expired:
      return '配对码已失效，请在电脑端重新配对';
    case PairingFailure.cancelled:
      return '电脑端已关闭配对，请重新开启后再试';
    case PairingFailure.unavailable:
      return '对方不是 Hermes 配对服务';
    case PairingFailure.network:
      return '网络异常，请稍后重试';
  }
}

/// 容错解析一条发现应答（非 JSON / 缺关键字段 / 非法 URL → null）。
PairingCandidate? parsePairingCandidate(String raw) {
  final payload = decodePairingJsonObject(raw);
  if (payload == null) return null;
  final pairingBaseUrl = _stringOf(payload['pairingBaseUrl']);
  if (pairingBaseUrl.isEmpty) return null;
  final uri = Uri.tryParse(pairingBaseUrl);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final installId = _stringOf(payload['installId']);
  if (installId.isEmpty) return null;
  final deviceName = _stringOf(payload['deviceName']);
  return PairingCandidate(
    deviceName: deviceName.isEmpty ? '未知设备' : deviceName,
    pairingBaseUrl: pairingBaseUrl,
    installId: installId,
    webuiBaseUrl: _stringOf(payload['webuiBaseUrl']),
  );
}

String _stringOf(Object? value) {
  if (value is String) return value.trim();
  if (value == null) return '';
  return value.toString().trim();
}

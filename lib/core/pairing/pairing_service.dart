/// 桌面端配对服务实现（纯 Dart + dart:io，不依赖 UI）。
///
/// 职责（对照 `pairing_contract.dart` 的 [PairingService]）：
/// - 生成 6 位数字配对码（安全随机），有效期默认 10 分钟，成功兑换一次即作废；
/// - 起一个**临时端口**的本地 HTTP 端点：`POST /pair` 兑换凭据、`GET /health` 探活；
/// - 同时监听 UDP [kPairingDiscoveryPort]，对内容为 [kPairingProbePayload] 的广播回
///   JSON 应答（deviceName / pairingBaseUrl / installId / webuiBaseUrl）。
///
/// ## 为什么常量定义在这里
/// 线协议常量（探测包内容、发现端口、路径、错误码）是**桌面端与手机端共用**的，
/// 但契约定稿后在本次任务里被冻结（禁止改动），故把服务端一侧的线协议常量放在本文件，
/// 手机端 `pairing_client.dart` 直接引用（见该文件顶部注释）。
///
/// ## 线协议（手机端 `pairing_client.dart` 按同一张表映射失败原因）
/// | 场景 | 状态码 | 响应体 |
/// | --- | --- | --- |
/// | `GET /health` | 200 | `{ok, device, installId}` |
/// | 兑换成功 | 200 | `{baseUrl, password, installId}` |
/// | 请求体非 JSON object / 缺 code | 400 | `{"error":"bad_request"}` |
/// | 配对码不匹配 | 409 | `{"error":"wrong_code"}` |
/// | 码过期 / 已被兑换作废 | 410 | `{"error":"expired"}` |
/// | 当前未开启配对（用户已取消） | 503 | `{"error":"no_session"}` |
/// | 未知路径 / 方法不对 | 404 | `{"error":"not_found"}` |
/// | 服务端内部异常 | 500 | `{"error":"internal"}` |
///
/// **任何路径都必须先写出完整 HTTP 响应再结束**（含错误分支）——绝不在写出响应前
/// 关 socket：手机端只会看到「连接被重置」这种没法定位的 network 失败。
///
/// ## 安全铁律
/// `PairingSession.password` 是秘密：**只在兑换成功那一次 200 响应体里出现**。
/// 它不进日志、不进 `toString`、不进任何错误 detail、也不进发现应答。
///
/// ## 可测性
/// 时钟、配对码生成器、主机名、局域网地址解析、监听地址与发现端口全部可注入；
/// 单测用回环地址 + 临时端口跑真实 socket（既验证线协议又不碰主机网络状态）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'pairing_contract.dart';

/// UDP 发现端口（手机端广播、桌面端应答）。
const int kPairingDiscoveryPort = 39393;

/// 探测包内容：手机端把它广播出去，桌面端据此应答。
const String kPairingProbePayload = 'HERMEX-PAIR-DISCOVER';

/// 兑换路径。
const String kPairingRedeemPath = '/pair';

/// 探活路径。
const String kPairingHealthPath = '/health';

/// 配对码位数。
const int kPairingCodeLength = 6;

/// 默认配对码有效期。
const Duration kPairingDefaultTtl = Duration(minutes: 10);

/// 线协议错误码（响应体 `error` 字段取值）。客户端据此映射 [PairingFailure]。
abstract final class PairingErrorCodes {
  /// 配对码不匹配。
  static const String wrongCode = 'wrong_code';

  /// 配对码过期 / 已被兑换作废。
  static const String expired = 'expired';

  /// 对端当前没有开启配对（用户已取消 / 还没出码）。
  static const String noSession = 'no_session';

  /// 请求体不合法。
  static const String badRequest = 'bad_request';

  /// 路径不存在（多半不是 Hermes 配对服务）。
  static const String notFound = 'not_found';
}

/// 配对码生成器接口（**必须**用密码学安全随机；禁 `Random()` / `Math.random`）。
abstract interface class PairingCodeGenerator {
  /// 生成一个 6 位数字配对码。
  String generate();
}

/// 生产用生成器：`Random.secure()` 逐位取数字。
class SecurePairingCodeGenerator implements PairingCodeGenerator {
  const SecurePairingCodeGenerator();

  @override
  String generate() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < kPairingCodeLength; i++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }
}

/// 主机名解析（默认取系统 hostname）。
typedef PairingHostNameResolver = String Function();

/// 局域网地址解析：由 WebUI 地址推出手机端可达的主机部分。
typedef PairingAdvertisedHostResolver = Future<String> Function(String baseUrl);

/// 默认主机名解析：`Platform.localHostname`，失败时退回占位名（绝不抛）。
String systemPairingHostName() {
  try {
    final name = Platform.localHostname.trim();
    return name.isEmpty ? 'Hermes 主机' : name;
  } catch (_) {
    return 'Hermes 主机';
  }
}

/// 默认局域网地址解析。
///
/// 优先用 WebUI 地址自身的 host —— 用户能把 WebUI 地址填成局域网 IP，
/// 那它就是手机可达的地址；只有 host 是回环/localhost 时才去遍历网卡。
Future<String> resolvePairingAdvertisedHost(String baseUrl) async {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  if (host.isNotEmpty && !_isLoopbackHost(host)) {
    return host;
  }
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.address.isNotEmpty) {
          return address.address;
        }
      }
    }
  } catch (_) {
    // 网卡枚举在沙箱/受限环境可能失败 —— 退回回环，让本机自测仍可用。
  }
  return InternetAddress.loopbackIPv4.address;
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '::1' ||
      normalized.startsWith('127.');
}

/// 桌面端配对服务。
///
/// 生命周期：`start()` 起 socket → `accepted` 上报接入 → `stop()` 关 socket（幂等）。
class DesktopPairingService implements PairingService {
  DesktopPairingService({
    this.codeGenerator = const SecurePairingCodeGenerator(),
    DateTime Function()? clock,
    PairingHostNameResolver? hostNameResolver,
    PairingAdvertisedHostResolver? advertisedHostResolver,
    this.httpBindAddress,
    this.discoveryBindAddress,
    this.discoveryPort = kPairingDiscoveryPort,
  })  : _clock = clock ?? DateTime.now,
        _hostNameResolver = hostNameResolver ?? systemPairingHostName,
        _advertisedHostResolver =
            advertisedHostResolver ?? resolvePairingAdvertisedHost;

  /// 配对码生成器（可注入供单测替换成固定码）。
  final PairingCodeGenerator codeGenerator;
  final DateTime Function() _clock;
  final PairingHostNameResolver _hostNameResolver;
  final PairingAdvertisedHostResolver _advertisedHostResolver;

  /// HTTP 端点绑定地址（生产用 `0.0.0.0`；单测传回环）。
  final InternetAddress? httpBindAddress;

  /// UDP 发现绑定地址（生产用 `0.0.0.0`；单测传回环）。
  final InternetAddress? discoveryBindAddress;

  /// UDP 发现端口；传 `0` 让系统分配（单测避免占用固定端口）。
  final int discoveryPort;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  StreamSubscription<HttpRequest>? _httpSubscription;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  final StreamController<PairingAccepted> _accepted =
      StreamController<PairingAccepted>.broadcast();

  /// 当前会话原文。过期**不置空** —— 模型自带 `isExpiredAt`，UI 需要区分
  /// 「从未开启」与「刚过期」，这里保持原文由调用方判定。
  PairingSession? _current;
  String _installId = '';
  bool _redeemed = false;

  /// 兑换端点地址（例 `http://192.168.1.7:38911`）：契约模型里没有这个字段，
  /// 但对端要从发现应答拿到它，故实现内部持有并对外暴露只读 getter。
  String? _pairingEndpoint;

  @override
  PairingSession? get current => _current;

  @override
  Stream<PairingAccepted> get accepted => _accepted.stream;

  /// 兑换端点地址；未开启时为 null。
  String? get pairingEndpoint => _pairingEndpoint;

  /// 发现应答实际监听的 UDP 端口（[discoveryPort] 传 0 时为系统分配值）；
  /// 未开启发现通道时为 null。
  int? get discoveryBoundPort => _udp?.port;

  @override
  Future<PairingSession> start({
    required String baseUrl,
    required String password,
    required String installId,
    Duration ttl = kPairingDefaultTtl,
  }) async {
    // 重复调用视为重新生成：先彻底关掉上一轮的 socket。
    await stop();

    final code = codeGenerator.generate();
    final host = await _advertisedHostResolver(baseUrl);
    // 先绑定，拿到端口再登记会话 —— 绑定失败时不留下半截会话。
    final server = await HttpServer.bind(
      httpBindAddress ?? InternetAddress.anyIPv4,
      0,
    );

    final session = PairingSession(
      code: code,
      baseUrl: baseUrl,
      password: password,
      installId: installId,
      expiresAt: _clock().add(ttl),
    );

    _http = server;
    _httpSubscription = server.listen(
      (request) => unawaited(_handleHttpRequest(request)),
      onError: (Object _) {},
    );
    _current = session;
    _installId = installId;
    _redeemed = false;
    _pairingEndpoint = 'http://$host:${server.port}';

    await _startDiscovery();

    return session;
  }

  @override
  Future<void> stop() async {
    final http = _http;
    final udp = _udp;
    final httpSubscription = _httpSubscription;
    final udpSubscription = _udpSubscription;
    _http = null;
    _udp = null;
    _httpSubscription = null;
    _udpSubscription = null;
    _current = null;
    _installId = '';
    _redeemed = false;
    _pairingEndpoint = null;

    if (http != null) {
      try {
        await http.close(force: true);
      } catch (_) {
        // 已经关掉了（或对端提前断开）—— 幂等收尾，不打扰调用方。
      }
    }
    if (udp != null) {
      try {
        udp.close();
      } catch (_) {}
    }
    if (httpSubscription != null) {
      try {
        await httpSubscription.cancel();
      } catch (_) {}
    }
    if (udpSubscription != null) {
      try {
        await udpSubscription.cancel();
      } catch (_) {}
    }
  }

  /// 关闭并释放流（provider 容器销毁时调用）。停止后本实例不再可用。
  Future<void> dispose() async {
    await stop();
    if (!_accepted.isClosed) {
      await _accepted.close();
    }
  }

  Future<void> _startDiscovery() async {
    try {
      final socket = await RawDatagramSocket.bind(
        discoveryBindAddress ?? InternetAddress.anyIPv4,
        discoveryPort,
      );
      try {
        socket.broadcastEnabled = true;
      } catch (_) {
        // 部分平台/受限环境禁广播 —— 收包不受影响，忽略。
      }
      _udp = socket;
      _udpSubscription = socket.listen(_handleDatagram);
    } catch (_) {
      // 发现通道起不来（端口被占 / 权限不足）**不**让整次配对失败：
      // HTTP 兑换仍可用，手机端也能手输地址。不假装能发现，也不假装失败。
      _udp = null;
    }
  }

  void _handleDatagram(RawSocketEvent event) {
    final socket = _udp;
    if (socket == null || event != RawSocketEvent.read) return;
    Datagram? datagram;
    try {
      datagram = socket.receive();
    } catch (_) {
      return;
    }
    if (datagram == null) return;
    if (utf8.decode(datagram.data, allowMalformed: true).trim() !=
        kPairingProbePayload) {
      return;
    }
    final session = _current;
    final endpoint = _pairingEndpoint;
    if (session == null || endpoint == null) return;
    if (_redeemed || session.isExpiredAt(_clock())) return;

    // 注意：应答体里**只有**可公开信息，绝不含 password。
    final payload = jsonEncode(<String, Object?>{
      'deviceName': _hostNameResolver(),
      'pairingBaseUrl': endpoint,
      'installId': session.installId,
      'webuiBaseUrl': session.baseUrl,
    });
    try {
      socket.send(utf8.encode(payload), datagram.address, datagram.port);
    } catch (_) {
      // 应答丢失由客户端超时兜底，不升级为错误。
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == kPairingHealthPath) {
        return await _writeJson(request, HttpStatus.ok, <String, Object?>{
          'ok': true,
          'device': _hostNameResolver(),
          'installId': _installId,
        });
      }
      if (request.method == 'POST' && path == kPairingRedeemPath) {
        return await _handleRedeem(request);
      }
      return await _writeJson(
        request,
        HttpStatus.notFound,
        <String, Object?>{'error': PairingErrorCodes.notFound},
      );
    } catch (_) {
      // 单个请求出错不能拖垮应答循环，也**不能裸关连接**：任何异常都回一个
      // 完整 500 响应（响应体里同样不含任何凭据）。
      await _writeJson(
        request,
        HttpStatus.internalServerError,
        <String, Object?>{'error': 'internal'},
      );
    }
  }

  Future<void> _handleRedeem(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final payload = decodePairingJsonObject(raw);
    if (payload == null) {
      return await _writeJson(
        request,
        HttpStatus.badRequest,
        <String, Object?>{'error': PairingErrorCodes.badRequest},
      );
    }
    final code = _stringOf(payload['code']);
    if (code.isEmpty) {
      return await _writeJson(
        request,
        HttpStatus.badRequest,
        <String, Object?>{'error': PairingErrorCodes.badRequest},
      );
    }

    final session = _current;
    if (session == null) {
      // 用户已取消 / 还没出码：配对服务当前不可用（不是码的问题）。
      return await _writeJson(
        request,
        HttpStatus.serviceUnavailable,
        <String, Object?>{'error': PairingErrorCodes.noSession},
      );
    }
    if (_redeemed) {
      // 一次性：成功兑换过就作废，绝不第二次吐密码。
      return await _writeJson(
        request,
        HttpStatus.gone,
        <String, Object?>{'error': PairingErrorCodes.expired},
      );
    }
    if (session.isExpiredAt(_clock())) {
      return await _writeJson(
        request,
        HttpStatus.gone,
        <String, Object?>{'error': PairingErrorCodes.expired},
      );
    }
    // 每次校验都对着**当前**会话的码比较：stop → start 后旧码必然失效，
    // 因为 _current 整个被新会话替换（不复用旧对象/旧闭包）。
    if (code != session.code) {
      return await _writeJson(
        request,
        HttpStatus.conflict,
        <String, Object?>{'error': PairingErrorCodes.wrongCode},
      );
    }

    _redeemed = true;
    final label = _stringOf(payload['device']);
    if (!_accepted.isClosed) {
      _accepted.add(
        PairingAccepted(
          deviceLabel: label.isEmpty ? '未知设备' : label,
          at: _clock(),
        ),
      );
    }
    return await _writeJson(request, HttpStatus.ok, <String, Object?>{
      'baseUrl': session.baseUrl,
      'password': session.password,
      'installId': session.installId,
    });
  }

  Future<void> _writeJson(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    try {
      request.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    } catch (_) {
      // 客户端提前断开（用户取消）—— 忽略。
    }
  }
}

/// 容错解析 JSON object（非 object / 非法 JSON 一律 null）。
Map<String, dynamic>? decodePairingJsonObject(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _stringOf(Object? value) {
  if (value is String) return value.trim();
  if (value == null) return '';
  return value.toString().trim();
}

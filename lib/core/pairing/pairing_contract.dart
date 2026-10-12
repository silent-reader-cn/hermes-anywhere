/// 配对域契约 —— 三路并行实现的唯一接口出口。
///
/// 角色划分（谁实现什么）：
/// - 桌面端 `PairingService`：生成 6 位配对码、在局域网内应答手机的发现与兑换请求；
/// - 手机端 `PairingClient`：发现同一局域网内的后端、用配对码换取 WebUI 凭据；
/// - UI 层（手机引导页 / 桌面向导）只依赖本文件的模型与抽象类。
///
/// 约定：本文件不含任何平台实现；实现见
/// `lib/core/pairing/pairing_service.dart`（桌面）与
/// `lib/core/pairing/pairing_client.dart`（移动）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
/// 配对失败原因 —— UI 据此分档给文案（不要用一句「失败」糊过去）。
enum PairingFailure {
  /// 配对码已过期（默认 10 分钟）。
  expired,

  /// 配对码不匹配。
  wrongCode,

  /// 对方没有开启配对（或不是 Hermes 后端）。
  unavailable,

  /// 网络不可达 / 超时。
  network,

  /// 用户取消或对端主动关闭。
  cancelled,
}

/// 配对过程中的可抛异常。
class PairingException implements Exception {
  const PairingException(this.reason, [this.detail = '']);

  final PairingFailure reason;
  final String detail;

  @override
  String toString() => 'PairingException(${reason.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// 一次配对会话（桌面端产生，手机端兑换后得到同一份凭据）。
class PairingSession {
  const PairingSession({
    required this.code,
    required this.baseUrl,
    required this.password,
    required this.installId,
    required this.expiresAt,
  });

  /// 6 位数字配对码（展示给用户手输，或编码进二维码）。
  final String code;

  /// 手机端要连的 WebUI 地址，例如 `http://192.168.1.7:8787`。
  final String baseUrl;

  /// 内置服务密码。**秘密**：禁止写入日志、禁止进 toJson、禁止放进错误详情。
  final String password;

  /// 后端安装标识（`/api/status` 的 install_id），用于折叠重复连接。
  final String installId;

  /// 过期时刻（默认创建后 10 分钟）。
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  PairingSession copyWith({String? code, DateTime? expiresAt}) => PairingSession(
        code: code ?? this.code,
        baseUrl: baseUrl,
        password: password,
        installId: installId,
        expiresAt: expiresAt ?? this.expiresAt,
      );

  @override
  String toString() =>
      'PairingSession(code: $code, baseUrl: $baseUrl, installId: $installId, expiresAt: $expiresAt)';
}

/// 手机端在局域网里发现到的候选后端。
class PairingCandidate {
  const PairingCandidate({
    required this.deviceName,
    required this.pairingBaseUrl,
    required this.installId,
    this.webuiBaseUrl = '',
  });

  /// 电脑名（例：`DESKTOP-7F3A`），可直接展示给用户。
  final String deviceName;

  /// 配对服务地址（临时端口），例如 `http://192.168.1.7:38911`。
  final String pairingBaseUrl;

  /// 后端安装标识。
  final String installId;

  /// 该后端的 WebUI 地址（若能一次拿到就直接带上，省一次往返）。
  final String webuiBaseUrl;

  @override
  String toString() => 'PairingCandidate($deviceName, $pairingBaseUrl)';
}

/// 手机端兑换成功后落地的连接凭据。
class PairingCredentials {
  const PairingCredentials({
    required this.baseUrl,
    required this.password,
    required this.installId,
  });

  final String baseUrl;
  final String password;
  final String installId;
}

/// 桌面端观察到的一次成功接入（用于向导的「手机已连上」验收步）。
class PairingAccepted {
  const PairingAccepted({required this.deviceLabel, required this.at});

  /// 接入设备标签（手机端自报，例：`iPhone 15 Pro`）。
  final String deviceLabel;

  /// 接入时刻。
  final DateTime at;
}

/// 桌面端配对服务：出码 + 局域网应答。
/// 可选能力：服务能报告「对外公布地址」的状态。
///
/// 契约主体 [PairingService] 只保证「出码 / 应答 / 收到接入」；而「手机到底该连哪个
/// 地址」是**桌面端实现才知道**的事（要枚举网卡 + 逐个探活校验）。UI 通过本接口读该
/// 状态，从而在**没有可用地址**时给明确提示，而不是显示一个必然连不上的地址。
///
/// 未实现本接口的实现（测试 fake / 未来其它端）：UI 退化为按调用方传入的地址显示。
abstract class AdvertisedAddressReporting {
  /// 探活校验通过的对外 host；没有可用地址时为 null。
  String? get advertisedHost;

  /// 是否存在探活校验通过的对外地址。
  bool get hasAdvertisedLanAddress;
}

abstract class PairingService {
  /// 当前会话；未开启时为 null。
  PairingSession? get current;

  /// 开启一次配对（生成 6 位码并启动应答）。重复调用视为重新生成。
  Future<PairingSession> start({
    required String baseUrl,
    required String password,
    required String installId,
    Duration ttl,
  });

  /// 成功接入事件（向导「等待手机接入」用它做验收）。
  Stream<PairingAccepted> get accepted;

  /// 关闭配对（取消配对码、停止监听）。幂等。
  Future<void> stop();
}

/// 手机端配对客户端：发现 + 兑换。
abstract class PairingClient {
  /// 局域网发现，[timeout] 内没扫到就返回空列表（不抛异常）。
  Future<List<PairingCandidate>> discover({Duration timeout});

  /// 用配对码换取凭据；失败抛 [PairingException]。
  Future<PairingCredentials> redeem({
    required String pairingBaseUrl,
    required String code,
  });
}

/// 桌面端配对服务注入点。默认未实现 —— 由桌面端实现覆盖（测试可注入 fake）。
final pairingServiceProvider = Provider<PairingService>(
  (ref) => throw UnimplementedError(
    'pairingServiceProvider 未覆盖：桌面端需在 provider 容器里注入真实实现（见 core/pairing/pairing_service.dart）',
  ),
);

/// 手机端配对客户端注入点。默认未实现 —— 由移动端实现覆盖（测试可注入 fake）。
final pairingClientProvider = Provider<PairingClient>(
  (ref) => throw UnimplementedError(
    'pairingClientProvider 未覆盖：移动端需在 provider 容器里注入真实实现（见 core/pairing/pairing_client.dart）',
  ),
);

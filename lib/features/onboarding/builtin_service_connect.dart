import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/connections/server_connection.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'onboarding_providers.dart';

/// 内置服务「自动登录 → 建/激活内置连接」的统一收尾链。
///
/// 为什么必须只有一份：内置服务有两个用户入口 —— 引导页内置 Tab 的
/// 「启动并连接」（`builtin_tab.dart`）与本机部署向导末步收尾
/// （`install_guide_page.dart`）。两者必须落到**同一个连接对象**
/// （`ServerConnection.builtinId` + [ConnectionKind.builtin]，否则内置 Tab 认不出
/// 「已激活并运行」、停用/删除铁律也管不到）并走同一次自动登录。
///
/// 此前向导自建了 UUID 连接 + 硬编码 `http://127.0.0.1:8787` + 空密码，而 sidecar
/// 实际配置是**可改端口**且**首次加载即生成 24 位随机密码**
/// （见 `WebuiSidecarConfigStorage.load`）⇒ 走完向导也登录不上、连接行还不归内置管。
/// 故抽此一处，两个入口共用。
class BuiltinServiceConnector {
  /// 构造收尾器（[ref] 为调用方页面的 WidgetRef）。
  const BuiltinServiceConnector(this.ref);

  /// 调用方 Provider 容器。
  final WidgetRef ref;

  /// 由 sidecar 配置推导**本机自身**可连接的 baseUrl。
  ///
  /// 监听地址为 `0.0.0.0`（对外广播）或空串时，本机连接一律回落到 `127.0.0.1`
  /// —— 浏览/HTTP 客户端可以连 `0.0.0.0` 在某些栈上不成立，回环才是稳定解。
  static String baseUrlOf(SidecarConfig config) {
    final host = (config.host == '0.0.0.0' || config.host.isEmpty)
        ? '127.0.0.1'
        : config.host;
    return 'http://$host:${config.port}';
  }

  /// 自动登录 + 内置连接 upsert/activate；返回本次使用的 baseUrl。
  ///
  /// 登录失败（[ApiException]）会原样抛出，由调用方决定如何呈现；**不吞错**。
  Future<String> loginAndActivate() async {
    final config = ref.read(webuiSidecarConfigProvider);
    final baseUrl = baseUrlOf(config);
    final password = config.password;

    final factory = ref.read(onboardingApiFactoryProvider);
    await factory(baseUrl, const []).login(password);

    await ref
        .read(connectionsProvider.notifier)
        .upsertBuiltinAndActivate(
          ServerConnection(
            id: ServerConnection.builtinId,
            name: 'Hermes',
            baseUrl: baseUrl,
            username: null,
            password: password.isEmpty ? null : password,
            customHeaders: const {},
            createdAt: DateTime.now().toUtc(),
            kind: ConnectionKind.builtin,
            enabled: true,
          ),
        );
    return baseUrl;
  }
}

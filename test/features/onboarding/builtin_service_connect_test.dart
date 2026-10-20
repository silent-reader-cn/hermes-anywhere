import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/onboarding/builtin_service_connect.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 假 sidecar 安全存储（避免真实 flutter_secure_storage 平台通道）。
class _FakeSecure implements SidecarSecureStorage {
  _FakeSecure(this.data);

  final Map<String, String> data;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  // sidecar 配置 load() 走 SharedPreferences + 安全存储 ⇒ 必须先给 platform 通道打桩，
  // 否则 getInstance() 在测试环境挂死（表现为 10 分钟 TimeoutException）。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BuiltinServiceConnector.baseUrlOf', () {
    test('0.0.0.0 / 空 host 回落 127.0.0.1，其余主机原样保留', () {
      // 向导「启动服务」步把监听地址绑到 0.0.0.0（对外广播），本机自身连接必须回落回环。
      expect(
        BuiltinServiceConnector.baseUrlOf(
          const SidecarConfig(host: '0.0.0.0', port: 8787),
        ),
        'http://127.0.0.1:8787',
      );
      expect(
        BuiltinServiceConnector.baseUrlOf(
          const SidecarConfig(host: '', port: 9123),
        ),
        'http://127.0.0.1:9123',
      );
      expect(
        BuiltinServiceConnector.baseUrlOf(
          const SidecarConfig(host: '192.168.1.7', port: 8787),
        ),
        'http://192.168.1.7:8787',
      );
    });
  });

  testWidgets('loginAndActivate：登录用 sidecar 实配地址 + 连接落在 builtinId 并激活', (tester) async {
    final storage = InMemorySecureStorage();
    final api = FakeOnboardingLoginApi();
    final secure = _FakeSecure({
      WebuiSidecarConfigStorage.keyPassword: 'p@ss-24chars',
    });
    WidgetRef? captured;

    // 实配落盘：监听 0.0.0.0（向导「启动服务」步就是这么绑的）+ 非默认端口。
    // 直接写进 mock 首选项而不是事后改 provider —— 后者会撞上 ConfigController.build()
    // 里 `unawaited(load())` 的覆盖竞态（实测把端口刷回 8787）。
    SharedPreferences.setMockInitialValues({
      WebuiSidecarConfigStorage.keyHost: '0.0.0.0',
      WebuiSidecarConfigStorage.keyPort: 9321,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: storage),
          ),
          onboardingApiFactoryProvider.overrideWithValue((_, _) => api),
          webuiSidecarConfigStorageProvider.overrideWithValue(
            WebuiSidecarConfigStorage(secureStorage: secure),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );
    // 显式等一次 load 落地（对齐 `webui_sidecar_section_test.dart:161` 的既有范式）。
    //
    // 为什么不能只靠 pump 帧：`WebuiSidecarConfigController.build()` 里是
    // `unawaited(load())` —— 它在 provider 首次被读时**立刻**发起，而
    // `SharedPreferences.getInstance()` 的完成时刻不受 tester 的 pump 帧驱动
    // （实测 pump 两帧后 provider 仍停在默认 `127.0.0.1:8787`，而同一时刻
    // 单独调 `storage.load()` 却能读到 `0.0.0.0:9321` ⇒ 是**竞态**不是逻辑错）。
    // 故此处显式 await，避免依赖 pump 时序。
    await container.read(webuiSidecarConfigProvider.notifier).load();
    final loaded = container.read(webuiSidecarConfigProvider);
    expect(loaded.host, '0.0.0.0');
    expect(loaded.port, 9321);
    expect(loaded.password, 'p@ss-24chars');

    final baseUrl = await BuiltinServiceConnector(captured!).loginAndActivate();

    // 收尾必须用「0.0.0.0 → 回落 127.0.0.1 + 实配端口」，而不是硬编码 8787。
    expect(baseUrl, 'http://127.0.0.1:9321');
    expect(api.loginCalls, 1);
    expect(api.lastPassword, 'p@ss-24chars');

    final saved = (await ConnectionStore(storage: storage).loadAll()).single;
    expect(saved.id, ServerConnection.builtinId);
    expect(saved.kind, ConnectionKind.builtin);
    expect(saved.baseUrl, 'http://127.0.0.1:9321');
    expect(saved.password, 'p@ss-24chars');
    expect(
      storage.data[ConnectionStore.activeConnectionKey],
      ServerConnection.builtinId,
    );
  });
}

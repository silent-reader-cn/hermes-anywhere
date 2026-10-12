import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/pairing/pairing_contract.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:hermes_ui/features/onboarding/pairing/pairing_constants.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 手机端首启决策树（形态 B）的用例。
//
// 覆盖：M1 首问分流 / M2 发现（未注入 provider、空结果、命中）/ M3 配对码
// （成功、五档失败、跨网无候选）/ M4 下载引导（含剪贴板）/ 旧远程表单兜底。
//
// 形态 B 的构造方式：`bundledWebuiAvailableProvider=false`（非 Windows / 无内置包
// 的平台语义），与 test/golden/golden_onboarding_wide_test.dart 同款。
// ---------------------------------------------------------------------------

const String _fallbackEntryKey = 'pairing-start-manual-address';

/// 假配对客户端：记录调用参数，按需返回候选 / 抛分档异常。
class _FakePairingClient implements PairingClient {
  _FakePairingClient({
    this.candidates = const <PairingCandidate>[],
    this.redeemError,
    this.credentials,
  });

  List<PairingCandidate> candidates;
  PairingException? redeemError;
  PairingCredentials? credentials;

  int discoverCalls = 0;
  int redeemCalls = 0;
  Duration? lastDiscoverTimeout;
  String? lastPairingBaseUrl;
  String? lastCode;

  @override
  Future<List<PairingCandidate>> discover({Duration timeout = const Duration(seconds: 4)}) async {
    discoverCalls++;
    lastDiscoverTimeout = timeout;
    return candidates;
  }

  @override
  Future<PairingCredentials> redeem({
    required String pairingBaseUrl,
    required String code,
  }) async {
    redeemCalls++;
    lastPairingBaseUrl = pairingBaseUrl;
    lastCode = code;
    final error = redeemError;
    if (error != null) throw error;
    return credentials ??
        const PairingCredentials(
          baseUrl: 'http://192.168.1.7:8787',
          password: 'pw-from-pairing',
          installId: 'install-1',
        );
  }
}

PairingCandidate _candidate({
  String deviceName = 'DESKTOP-7F3A',
  String pairingBaseUrl = 'http://192.168.1.7:38911',
  String webuiBaseUrl = 'http://192.168.1.7:8787',
}) => PairingCandidate(
  deviceName: deviceName,
  pairingBaseUrl: pairingBaseUrl,
  installId: 'install-1',
  webuiBaseUrl: webuiBaseUrl,
);

void main() {
  late InMemorySecureStorage storage;

  setUp(() {
    storage = InMemorySecureStorage();
    SharedPreferences.setMockInitialValues({'app_locale_mode': 'zh'});
  });

  /// 起 HermesApp（真实 router + 守卫）并钉死形态 B。
  ///
  /// 无连接 → 守卫重定向到 /onboarding，与真机首启同一条路径。
  Future<void> pumpWizard(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: storage),
          ),
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(),
          ),
          // 会话列表页 build 期会 watch 项目（筛选 chips）：不注空 stub 就会真发
          // HTTP，widget 测试里表现为收尾的 !timersPending（本仓已知坑，同
          // test/golden/golden_screens_test.dart 的 _StubProjectApi）。
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
          bundledWebuiAvailableProvider.overrideWithValue(false),
          ...overrides,
        ],
        child: const HermesApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 推进若干帧（fake 客户端的 Future 在同一帧内结算）。
  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump();
    }
  }

  /// 进入兜底入口（M1 底部「我有服务器地址」）。
  Future<void> openLegacyForm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey(_fallbackEntryKey)));
    await settle(tester);
  }

  /// 进入 M3 配对码页并填满 6 位码。
  Future<void> fillCode(WidgetTester tester, [String code = '348126']) async {
    await tester.enterText(
      find.byKey(const ValueKey('pairing-code-field')),
      code,
    );
    await settle(tester);
  }

  // ─────────────────────────────────────────────────────────────────────────
  group('M1 · 首问「Hermes 跑在哪台电脑上？」', () {
    testWidgets('首启不再直接渲染旧远程表单：三张卡 + 兜底链接 + 底部微文案在场', (
      tester,
    ) async {
      await pumpWizard(tester);

      // 导航标题
      expect(find.text('开始使用'), findsOneWidget);
      // 页大标题 + 副文
      expect(find.text('Hermes 跑在哪台电脑上？'), findsOneWidget);
      expect(find.text('Hermes 需要一个常驻的后端电脑。选一种情况，剩下的几步会引导你完成。'), findsOneWidget);
      // 三张卡（标题 + 副行）
      expect(find.text('电脑就在同一个 Wi-Fi'), findsOneWidget);
      expect(find.text('自动发现，配对后即可连接'), findsOneWidget);
      expect(find.text('电脑在别处'), findsOneWidget);
      expect(find.text('4G／公司／外地：用配对码连接，需先开启远程访问'), findsOneWidget);
      expect(find.text('我还没在电脑上装 Hermes'), findsOneWidget);
      expect(find.text('先下载桌面版，装好再回到这里'), findsOneWidget);
      // 兜底链接 + 底部微文案
      expect(find.text('我有服务器地址'), findsOneWidget);
      expect(find.text('多台电脑可以稍后在「设置 → 连接」里添加'), findsOneWidget);

      // 旧远程表单**不再是首屏**（字段/提交按钮都不在）
      expect(find.byKey(const ValueKey('onboarding-url')), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-connect')), findsNothing);
      // 形态 B 依旧不渲染形态 A 的分段控件
      expect(
        find.byKey(const ValueKey('onboarding-segmented-control')),
        findsNothing,
      );
    });

    testWidgets('底部「我有服务器地址」→ 兜底旧远程表单（逐像素保留的那张）', (tester) async {
      await pumpWizard(tester);
      await openLegacyForm(tester);

      expect(find.text('Hermes 跑在哪台电脑上？'), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-connect')),
        findsOneWidget,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('M2 · 同一 Wi-Fi 自动发现', () {
    testWidgets('provider 未注入（默认 UnimplementedError）→ 不崩，展示「没找到你的电脑」+ 三条自检 + 手动入口', (
      tester,
    ) async {
      await pumpWizard(tester);

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);

      expect(find.text('同一 Wi-Fi 连接'), findsOneWidget);
      // 搜索结束后落到「没找到」态
      expect(find.text('没找到你的电脑'), findsOneWidget);
      expect(find.text('正在找你的电脑'), findsNothing);
      // 三条自检（同一段文本内的三行）
      expect(find.textContaining('1. 确认电脑上的 Hermes 正在运行'), findsOneWidget);
      expect(find.textContaining('2. 确认两台设备连的是同一个 Wi-Fi'), findsOneWidget);
      expect(find.textContaining('3. 检查电脑防火墙是否放行 8787'), findsOneWidget);
      // 兜底手动入口
      expect(
        find.byKey(const ValueKey('pairing-discover-manual-address')),
        findsOneWidget,
      );
      // 无候选 → 不渲染发现卡
      expect(find.text('配对'), findsNothing);
    });

    testWidgets('发现返回空列表 → 同上，不崩', (tester) async {
      final client = _FakePairingClient();
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);

      expect(client.discoverCalls, 1);
      // 发现超时按任务口径 4s
      expect(client.lastDiscoverTimeout, const Duration(seconds: 4));
      expect(find.text('没找到你的电脑'), findsOneWidget);
    });

    testWidgets('发现实现抛错（网络/权限）→ 归到「没找到」态，不崩', (tester) async {
      final client = _ThrowingPairingClient();
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);

      expect(find.text('没找到你的电脑'), findsOneWidget);
    });

    testWidgets('扫到 DESKTOP-7F3A → 发现卡（机名 / 内置服务 · 8787 · 同一网络 / 配对按钮）', (
      tester,
    ) async {
      final client = _FakePairingClient(candidates: [_candidate()]);
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);

      expect(find.text('正在找你的电脑'), findsOneWidget);
      expect(find.text('DESKTOP-7F3A'), findsOneWidget);
      expect(
        find.text('内置服务 · 8787 · 同一网络'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pairing-candidate-install-1')),
        findsOneWidget,
      );
      expect(find.text('配对'), findsOneWidget);
    });

    testWidgets('候选自带 WebUI 端口 → 发现卡副行按实端口写', (tester) async {
      final client = _FakePairingClient(
        candidates: [_candidate(webuiBaseUrl: 'http://192.168.1.7:9090')],
      );
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);

      expect(find.text('内置服务 · 9090 · 同一网络'), findsOneWidget);
    });

    testWidgets('发现卡「配对」→ 配对码页（nav 配对 + 六格 + 主按钮 + 扫一扫禁用占位）', (
      tester,
    ) async {
      final client = _FakePairingClient(candidates: [_candidate()]);
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(find.text('配对'));
      await settle(tester);

      expect(find.text('配对'), findsOneWidget);
      expect(find.text('输入电脑上的配对码'), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-code-cell-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-code-cell-5')), findsOneWidget);
      expect(find.text('配对并连接'), findsOneWidget);
      expect(find.text('改用扫一扫'), findsOneWidget);
      expect(find.text('配对码 10 分钟内有效，配对成功后立即失效。'), findsOneWidget);

      // v1 扫码按钮是禁用占位（不引新依赖）
      final scan = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.text('改用扫一扫'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(scan.onPressed, isNull);
    });

    testWidgets('返回箭头回 M1', (tester) async {
      final client = _FakePairingClient(candidates: [_candidate()]);
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pairing-nav-back')));
      await settle(tester);

      expect(find.text('Hermes 跑在哪台电脑上？'), findsOneWidget);
    });

    testWidgets('发现页「手动输入地址」→ 兜底旧远程表单', (tester) async {
      await pumpWizard(tester);

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('pairing-discover-manual-address')),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-connect')), findsOneWidget);
    });
  });
    testWidgets('兜底旧表单给返回箭头：M1 底部链接进入 → 返回回首问页', (tester) async {
      await pumpWizard(tester);
      await openLegacyForm(tester);

      // 表单本体仍逐像素保留，但导航栏现在有返回箭头（主人 2026-10-12 拍板：不再做死胡同）
      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-nav-back')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pairing-nav-back')));
      await settle(tester);

      expect(find.text('Hermes 跑在哪台电脑上？'), findsOneWidget);
      // 回首问页即根，不该再有返回箭头
      expect(find.byKey(const ValueKey('pairing-nav-back')), findsNothing);
    });

    testWidgets('兜底旧表单的返回回到「来路」：发现页手动入口进入 → 回发现页', (tester) async {
      await pumpWizard(tester);

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('pairing-discover-manual-address')),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('onboarding-url')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pairing-nav-back')));
      await settle(tester);

      // 回到发现页（同 Wi-Fi 连接），而不是首问页
      expect(find.text('同一 Wi-Fi 连接'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pairing-discover-manual-address')),
        findsOneWidget,
      );
    });

  // ─────────────────────────────────────────────────────────────────────────
  group('M3 · 配对码兑换', () {
    testWidgets('候选入页：redeem 收到该候选的 pairingBaseUrl 与 6 位码', (tester) async {
      final client = _FakePairingClient(candidates: [_candidate()]);
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(find.text('配对'));
      await settle(tester);
      await fillCode(tester, '348126');

      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester);

      expect(client.redeemCalls, 1);
      expect(client.lastCode, '348126');
      expect(client.lastPairingBaseUrl, 'http://192.168.1.7:38911');
    });

    testWidgets('未填满 6 位：主按钮仍可点（照设计稿不灰化），按下给「配对码不对」且不调 redeem', (tester) async {
      final client = _FakePairingClient(candidates: [_candidate()]);
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(find.text('配对'));
      await settle(tester);
      await fillCode(tester, '348');

      final submit = tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.text('配对并连接'),
          matching: find.byType(CupertinoButton),
        ),
      );
      expect(submit.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester);

      expect(client.redeemCalls, 0);
      expect(find.text('配对码不对，请核对电脑上显示的 6 位码'), findsOneWidget);
    });

    for (final tier in <PairingFailure, String>{
      PairingFailure.expired: '配对码已过期，请在电脑上重新生成',
      PairingFailure.wrongCode: '配对码不对，请核对电脑上显示的 6 位码',
      PairingFailure.unavailable: '没有找到配对服务，确认电脑上的 Hermes 正在运行',
      PairingFailure.network: '网络不可达，确认两台设备在同一个 Wi-Fi',
    }.entries) {
      testWidgets('失败分档 ${tier.key.name} → 「${tier.value}」', (tester) async {
        final client = _FakePairingClient(
          candidates: [_candidate()],
          redeemError: PairingException(tier.key),
        );
        await pumpWizard(
          tester,
          overrides: [pairingClientProvider.overrideWithValue(client)],
        );

        await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
        await settle(tester);
        await tester.tap(find.text('配对'));
        await settle(tester);
        await fillCode(tester);
        await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
        await settle(tester);

        expect(find.text(tier.value), findsOneWidget);
        // 停留在本页（未跳会话列表）
        expect(find.text('暂无会话'), findsNothing);
      });
    }

    testWidgets('cancelled → 静默（无任何分档红字）', (tester) async {
      final client = _FakePairingClient(
        candidates: [_candidate()],
        redeemError: const PairingException(PairingFailure.cancelled),
      );
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(find.text('配对'));
      await settle(tester);
      await fillCode(tester);
      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester);

      for (final message in [
        '配对码已过期，请在电脑上重新生成',
        '配对码不对，请核对电脑上显示的 6 位码',
        '没有找到配对服务，确认电脑上的 Hermes 正在运行',
        '网络不可达，确认两台设备在同一个 Wi-Fi',
      ]) {
        expect(find.text(message), findsNothing);
      }
      expect(client.redeemCalls, 1);
    });

    testWidgets('跨网入口（M1 卡②）无候选：提交前先发现一次，扫不到按 unavailable 文案', (tester) async {
      final client = _FakePairingClient();
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-elsewhere')));
      await settle(tester);
      expect(find.text('输入电脑上的配对码'), findsOneWidget);

      await fillCode(tester);
      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester);

      expect(client.discoverCalls, 1);
      expect(client.redeemCalls, 0);
      expect(find.text('没有找到配对服务，确认电脑上的 Hermes 正在运行'), findsOneWidget);
    });

    testWidgets('跨网入口：就地发现到一台 → 用它的配对服务地址 redeem', (tester) async {
      final client = _FakePairingClient(candidates: [_candidate()]);
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-elsewhere')));
      await settle(tester);
      await fillCode(tester);
      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester);

      expect(client.redeemCalls, 1);
      expect(client.lastPairingBaseUrl, 'http://192.168.1.7:38911');
    });

    testWidgets('provider 未注入时提交配对码 → 不崩，给 unavailable 文案', (tester) async {
      await pumpWizard(tester);

      await tester.tap(find.byKey(const ValueKey('pairing-start-elsewhere')));
      await settle(tester);
      await fillCode(tester);
      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester);

      expect(find.text('没有找到配对服务，确认电脑上的 Hermes 正在运行'), findsOneWidget);
    });

    testWidgets('兑换成功 → 落一条连接 + 置为 active + 进会话列表', (tester) async {
      final client = _FakePairingClient(
        candidates: [_candidate()],
        credentials: const PairingCredentials(
          baseUrl: 'http://192.168.1.7:8787',
          password: 'pw-from-pairing',
          installId: 'install-1',
        ),
      );
      await pumpWizard(
        tester,
        overrides: [pairingClientProvider.overrideWithValue(client)],
      );

      await tester.tap(find.byKey(const ValueKey('pairing-start-same-wifi')));
      await settle(tester);
      await tester.tap(find.text('配对'));
      await settle(tester);
      await fillCode(tester);
      await tester.tap(find.byKey(const ValueKey('pairing-code-submit')));
      await settle(tester, 8);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('暂无会话'), findsOneWidget);

      final raw = storage.data[ConnectionStore.connectionsKey];
      expect(raw, isNotNull);
      final list = jsonDecode(raw!) as List;
      expect(list, hasLength(1));
      final saved = list.single as Map<String, Object?>;
      expect(saved['base_url'], 'http://192.168.1.7:8787');
      expect(saved['name'], '192.168.1.7');
      expect(saved.containsKey('username'), isFalse);
      expect((saved['custom_headers'] as Map), isEmpty);
      expect(
        storage.data[ConnectionStore.passwordKey(saved['id'] as String)],
        'pw-from-pairing',
      );
      expect(
        storage.data[ConnectionStore.activeConnectionKey],
        saved['id'],
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('M4 · 下载桌面版引导', () {
    testWidgets('卡③ → M4：三步行 + 短链 + 微文案在场', (tester) async {
      await pumpWizard(tester);

      await tester.tap(
        find.byKey(const ValueKey('pairing-start-not-installed')),
      );
      await settle(tester);

      expect(find.text('下载桌面版'), findsOneWidget);
      expect(find.text('先在电脑上装 Hermes'), findsOneWidget);
      expect(find.text('桌面版装好后会自动启动后端，不需要配置任何东西。'), findsOneWidget);
      expect(find.text('下载 Windows / macOS 桌面版'), findsOneWidget);
      expect(find.text('安装包已内置后端，无需装 Python'), findsOneWidget);
      expect(find.text('安装并打开，点「让手机连上」'), findsOneWidget);
      expect(find.text('桌面版会显示 6 位配对码'), findsOneWidget);
      expect(find.text('回到手机输入配对码'), findsOneWidget);
      expect(find.text('完成，之后打开 App 自动连接'), findsOneWidget);
      expect(find.text(hermesDownloadUrl), findsOneWidget);
      expect(find.text('复制后发到电脑上的微信 / QQ，打开就能下载'), findsOneWidget);
      expect(find.text('复制下载链接'), findsOneWidget);
    });

    testWidgets('「复制下载链接」把完整下载 URL 写进剪贴板（走既有 SafeClipboard）', (tester) async {
      String? copied;
      SafeClipboard.clipboardSetterOverride = (text) async => copied = text;
      addTearDown(SafeClipboard.resetOverridesForTesting);

      await pumpWizard(tester);

      await tester.tap(
        find.byKey(const ValueKey('pairing-start-not-installed')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('pairing-download-copy-link')),
      );
      await settle(tester);

      expect(copied, hermesDownloadUrl);
      expect(find.text('下载链接已复制'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 兜底：旧远程表单（改造前那张，逐字段/逐 placeholder/逐行为不变）
  // ─────────────────────────────────────────────────────────────────────────
  group('兜底 · 旧远程表单不变性', () {
    testWidgets('字段、placeholder、提交按钮与改造前逐项一致（只换了入口，不再是首屏）', (
      tester,
    ) async {
      await pumpWizard(tester);
      await openLegacyForm(tester);

      // 导航标题沿用改造前的 l10n.connectServer
      expect(find.text('连接服务器'), findsOneWidget);
      expect(find.text('连接你的 Hermes 服务器'), findsOneWidget);
      expect(find.text('输入 hermes-webui 的地址（含端口），例如 https://hermes.example.com:8787'), findsOneWidget);

      final url = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('onboarding-url')),
      );
      expect(url.placeholder, 'https://hermes.example.com:8787');
      expect(url.autocorrect, isFalse);
      expect(url.keyboardType, TextInputType.url);

      final submit = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('onboarding-connect')),
      );
      expect(
        (submit.child as Text).data,
        '连接并保存',
      );
    });

    testWidgets('两阶段链路照旧：需密码 → 密码框就地出现且自动聚焦；填密码提交 → 保存并进会话列表', (
      tester,
    ) async {
      final api = _LegacyFormApi();
      await pumpWizard(
        tester,
        overrides: [onboardingApiFactoryProvider.overrideWithValue((_, _) => api)],
      );
      await openLegacyForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('onboarding-url')),
        'http://hermes.local:30002',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
      await settle(tester);

      // 阶段一：health → authStatus；需密码 → 就地出密码框 + 自动聚焦，且不调 login
      expect(api.healthCalls, 1);
      expect(api.authCalls, 1);
      expect(api.loginCalls, 0);
      final passwordField = find.byKey(const ValueKey('onboarding-password'));
      expect(passwordField, findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: passwordField, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);

      // 阶段二：login → upsert + setActive → 跳会话列表
      await tester.enterText(passwordField, 'pw123');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
      await settle(tester, 8);
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.loginCalls, 1);
      expect(api.lastPassword, 'pw123');
      expect(find.text('暂无会话'), findsOneWidget);

      final raw = storage.data[ConnectionStore.connectionsKey];
      expect(raw, isNotNull);
      final saved = (jsonDecode(raw!) as List).single as Map<String, Object?>;
      expect(saved['base_url'], 'http://hermes.local:30002');
      expect(saved['name'], 'hermes.local');
      expect(storage.data[ConnectionStore.passwordKey(saved['id'] as String)], 'pw123');
      expect(storage.data[ConnectionStore.activeConnectionKey], saved['id']);
    });
  });
}

/// 旧远程表单链路用的最小 fake（health 恒 ok、需密码、login 恒成功）。
class _LegacyFormApi implements OnboardingServerApi {
  int healthCalls = 0;
  int authCalls = 0;
  int loginCalls = 0;
  String? lastPassword;

  @override
  Future<HealthResponse> health() async {
    healthCalls++;
    return const HealthResponse(status: 'ok');
  }

  @override
  Future<AuthStatusResponse> authStatus() async {
    authCalls++;
    return const AuthStatusResponse(authEnabled: true);
  }

  @override
  Future<LoginResponse> login(String password) async {
    loginCalls++;
    lastPassword = password;
    return const LoginResponse(ok: true);
  }
}

/// 项目 API 空 stub：只喂固定空结果，杜绝 widget 测试里真发 HTTP。
class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

/// 发现阶段抛错的假客户端（网络 / 权限类异常）。
class _ThrowingPairingClient extends _FakePairingClient {
  @override
  Future<List<PairingCandidate>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    discoverCalls++;
    lastDiscoverTimeout = timeout;
    throw Exception('discovery failed');
  }
}

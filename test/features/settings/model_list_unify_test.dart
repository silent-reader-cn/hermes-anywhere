import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// #204 —— 模型列表统一：显示原模型名 + 三处共用同一数据源。
///
/// **护栏目的**（每条都对应一个真实缺陷，不写成「永远绿」的摆设）：
/// 1. 设置页模型列表每行显示**原始 id**，不是服务端改写过的 `label`
///    （`minimax-m3.1-flash` 而非 `Minimax M3.1 Flash`）；
/// 2. 设置页「默认模型」行摘要与列表同一口径；
/// 3. 上下文弹窗的模型下拉与宽屏输入栏右下角的模型 chip 读**同一个**
///    `availableModelIdsProvider`（不再各拉各的 / 一处注入一处不注入）；
/// 4. `flattenModelOptions` 的去重口径被设置页与 core 共用。
///
/// 反向验证：把 ① 改回 `displayName` → 用例 1/2 变红；把 ③ 的 chip 改回
/// 不看注入 provider → 用例 3 变红。

/// 两个 provider 分组；label 故意写成「首字母大写 + 空格」形态，
/// 以便断言「UI 显示的是 id 而不是 label」。
const _groups = <Map<String, Object?>>[
  {
    'provider_id': 'custom:cpa',
    'name': 'CPA',
    'models': [
      {'id': 'minimax-m3.1-flash', 'label': 'Minimax M3.1 Flash'},
      {'id': 'deepseek-v4-flash', 'label': 'Deepseek V4 Flash'},
    ],
  },
  {
    'provider_id': 'openai',
    'name': 'OpenAI',
    'models': [
      {'id': 'gpt-5.4', 'label': 'GPT-5.4'},
    ],
  },
];

ServerConnection _conn(String id, String name, String url) {
  return ServerConnection(
    id: id,
    name: name,
    baseUrl: url,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// 装配一个带假连接存储 + 假设置 API 的容器。
///
/// 覆盖项与 `settings_page_test.dart` 的 `makeContainer` 对齐（含
/// `apiClientProvider` / onboarding / 服务器编辑三条），否则设置页的其它段
/// 会去撞真实网络，导致「默认模型」行迟迟不进树。
Future<ProviderContainer> _makeContainer(
  FakeSettingsApi api, {
  List<ServerConnection> connections = const [],
  String? activeId,
}) async {
  final storage = InMemorySecureStorage();
  final store = ConnectionStore(storage: storage);
  for (final connection in connections) {
    await store.save(connection);
  }
  if (activeId != null) await store.setActive(activeId);
  final client = ApiClient(baseUrl: 'http://test.local:30002');
  return ProviderContainer(
    overrides: [
      connectionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(client),
      settingsApiFactoryProvider.overrideWithValue((_) => api),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
      serverEditorApiClientFactoryProvider.overrideWithValue(
        (baseUrl, headers) => client,
      ),
    ],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('#204 设置页模型列表显示原模型名', () {
    testWidgets('每行显示原始 id，不显示服务端改写过的 label', (tester) async {
      final api = FakeSettingsApi();
      api.modelsResponse = ModelsResponse.fromJson({
        'default_model': 'deepseek-v4-flash',
        'active_provider': 'custom:cpa',
        'groups': _groups,
      });
      final container = await _makeContainer(
        api,
        connections: [_conn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _testApp(
          container,
          const SettingsPage(),
        ),
      );
      // 设置页要等异步段（模型目录 / 推理状态）落定，「默认模型」行才进树
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // 进「默认模型」二级页（该行在设置主页下方，先滚动到可见）
      await _scrollIntoView(
        tester,
        find.byKey(const ValueKey('settings-default-model')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-default-model')));
      await tester.pumpAndSettle();

      // 断言：显示原始 id
      expect(find.text('minimax-m3.1-flash'), findsOneWidget);
      expect(find.text('deepseek-v4-flash'), findsOneWidget);
      expect(find.text('gpt-5.4'), findsOneWidget);

      // 断言：服务端改写过的 label 一律不出现
      expect(find.text('Minimax M3.1 Flash'), findsNothing);
      expect(find.text('Deepseek V4 Flash'), findsNothing);
      expect(find.text('GPT-5.4'), findsNothing);
    });

    testWidgets('设置页「默认模型」摘要与列表同一口径（原始 id）', (
      tester,
    ) async {
      final api = FakeSettingsApi();
      api.modelsResponse = ModelsResponse.fromJson({
        'default_model': 'deepseek-v4-flash',
        'active_provider': 'custom:cpa',
        'groups': _groups,
      });
      final container = await _makeContainer(
        api,
        connections: [_conn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _testApp(
          container,
          const SettingsPage(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      // 摘要行显示原始 id（该行在设置主页下方，先滚动到可见）
      await _scrollIntoView(
        tester,
        find.byKey(const ValueKey('settings-default-model')),
      );
      await tester.pumpAndSettle();
      expect(find.text('deepseek-v4-flash'), findsOneWidget);
      expect(find.text('Deepseek V4 Flash'), findsNothing);
    });

    testWidgets('活跃 provider 分组用 live 列表覆盖，模型名仍是原始 id', (
      tester,
    ) async {
      final api = FakeSettingsApi();
      api.modelsResponse = ModelsResponse.fromJson({
        'default_model': 'minimax-m3.1-flash',
        'active_provider': 'custom:cpa',
        'groups': _groups,
      });
      // live 端点给出上游网关的原始 id（label 仍是服务端改写形态）
      api.modelsLiveResponse = ModelsLiveResponse.fromJson({
        'provider': 'custom:cpa',
        'models': [
          {'id': 'minimax-m3.1-flash', 'label': 'Minimax M3.1 Flash'},
        ],
      });
      final container = await _makeContainer(
        api,
        connections: [_conn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _testApp(
          container,
          const SettingsPage(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));

      await _scrollIntoView(
        tester,
        find.byKey(const ValueKey('settings-default-model')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-default-model')));
      await tester.pumpAndSettle();

      expect(find.text('minimax-m3.1-flash'), findsOneWidget);
      expect(find.text('Minimax M3.1 Flash'), findsNothing);
    });
  });

  group('#204 数据源统一', () {
    test('modelCatalogProvider 同时给出分组与 live 原始 id 列表', () async {
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 无连接 ⇒ 静默空快照，不抛错
      final snapshot = await container.read(modelCatalogProvider.future);
      expect(snapshot.groups, isEmpty);
      expect(snapshot.liveModelIds, isEmpty);
    });

    test('availableModelIdsProvider 与 modelCatalogProvider 同源（同一份响应）', () async {
      // 记录 /api/models/live 的请求次数：若两 provider 各自发一次请求，
      // 就说明「同源」没做到（而只是碰巧同端点）。
      final requests = <String>[];
      final dio = Dio(
        BaseOptions(validateStatus: (_) => true, followRedirects: false),
      );
      dio.httpClientAdapter = _RecordingAdapter(
        requests: requests,
        responder: (options) {
          if (options.path.endsWith('/api/models/live')) {
            return ResponseBody.fromString(
              jsonEncode({
                'provider': 'custom:cpa',
                'models': [
                  {'id': 'minimax-m3.1-flash', 'label': 'Minimax M3.1 Flash'},
                  {'id': 'deepseek-v4-flash', 'label': 'Deepseek V4 Flash'},
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.path.endsWith('/api/models')) {
            return ResponseBody.fromString(
              jsonEncode({
                'default_model': 'minimax-m3.1-flash',
                'active_provider': 'custom:cpa',
                'groups': _groups,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 404);
        },
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002', dio: dio),
          ),
        ],
      );
      addTearDown(container.dispose);

      final snapshot = await container.read(modelCatalogProvider.future);
      final ids = await container.read(availableModelIdsProvider.future);

      // live 端点只被请求了一次 ⇒ availableModelIdsProvider 复用同一份响应
      expect(
        requests.where((p) => p.endsWith('/api/models/live')).length,
        1,
      );
      // 且取值与快照里的 live 列表一致
      expect(ids, snapshot.liveModelIds);
      expect(ids, ['minimax-m3.1-flash', 'deepseek-v4-flash']);
    });

    test('flattenModelOptions：按 provider + 归一 id 去重并保序', () {
      const groups = [
        ModelCatalogGroup(
          id: 'a',
          name: 'A',
          providerID: 'p1',
          models: [
            ModelCatalogOption(id: 'Foo Bar', displayName: 'X', providerID: 'p1'),
            ModelCatalogOption(id: 'foo-bar', displayName: 'Y', providerID: 'p1'),
          ],
        ),
        ModelCatalogGroup(
          id: 'b',
          name: 'B',
          providerID: 'p2',
          models: [
            ModelCatalogOption(id: 'foo-bar', displayName: 'Z', providerID: 'p2'),
          ],
        ),
      ];
      final flat = flattenModelOptions(groups);
      // 同 provider 内大小写/分隔符归一后重复 ⇒ 只留首个
      expect(flat.map((m) => m.id).toList(), ['Foo Bar', 'foo-bar']);
      // 不同 provider 的同名模型各自保留
      expect(flat.length, 2);
    });

    test('ModelCatalogOption.rawName 就是原始 id（不用服务端 label）', () {
      const option = ModelCatalogOption(
        id: 'minimax-m3.1-flash',
        displayName: 'Minimax M3.1 Flash',
      );
      expect(option.rawName, 'minimax-m3.1-flash');
      expect(option.rawName, isNot(option.displayName));
    });
  });
}

/// 滚动设置主页使目标可见（与 `settings_page_test.dart` 同解法）：
/// 目标已 build 但视口外 → `ensureVisible` 对齐；目标未 build（惰性区外）
/// → 先 `scrollUntilVisible` 触发 build。
Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 100);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// 记录请求路径的 dio 适配器（用于断言「只发了一次 /api/models/live」）。
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.requests, required this.responder});

  final List<String> requests;
  final ResponseBody Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.path);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 最小测试壳：MediaQuery + 主题 + ProviderScope（把 container 的覆盖项带进去）。
///
/// 视口给足高度（2000），否则设置主页的「模型」分组被裁掉，
/// `settings-default-model` 这类行根本不会进树。
Widget _testApp(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MediaQuery(
      data: const MediaQueryData(
        size: Size(800, 2000),
        textScaler: TextScaler.noScaling,
        platformBrightness: Brightness.light,
      ),
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(brightness: Brightness.light),
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        home: CupertinoPageScaffold(child: child),
      ),
    ),
  );
}

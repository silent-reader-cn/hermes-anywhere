import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/golden_helpers.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// 「默认模型选择页：显示原模型名」真渲染取证工装（**非金照基线**）
//
// 用途：主人要看的真图 —— 设置页进「默认模型」二级页后的列表，验证
// 每行显示的是**原始模型 id**（`minimax-m3.1-flash`）而不是服务端改写过的
// label（`Minimax M3.1 Flash`）。
//
// 数据取自本机真实服务端形态：`label` 故意写成服务端 `_make_label()` 的
// 产物（拆词 + 首字母大写 + 空格），`id` 是上游网关的原始模型名。
//
// 用法：
//   MODEL_LIST_SHOTS=1 C:/tmp/f.bat test test/screenshots/model_list_shots_test.dart \
//       --update-goldens
//   不带 MODEL_LIST_SHOTS=1 时全部 skip，`flutter test` 全量零影响。
//
// 产物：`.shots/model-list/model-picker-<light|dark>.png`
//   （DPR 2.0；`.shots/` 已在 .gitignore，故不进金照基线）
// ---------------------------------------------------------------------------

/// 环境门控：默认 skip。
final bool _capture = Platform.environment['MODEL_LIST_SHOTS'] == '1';
const String _skipReason = '设置 MODEL_LIST_SHOTS=1 才生成默认模型列表取证图';

/// 产物根目录（相对本文件：test/screenshots/ → 仓库根 .shots）。
const String _shotRoot = '../../.shots/model-list';

/// 视口（物理像素，DPR 2.0 ⇒ 逻辑 390×2400，窄屏单列长卷）。
///
/// 用**窄屏**：宽屏（≥900）设置页是左栏分类导航，「模型」分组在独立分类页里，
/// 截图工装要先点分类才能看到列表；窄屏是单列长卷，模型分组直接可见。
const Size _size = Size(780, 4800);

/// 真实形态的目录：`id` = 上游网关原始模型名；`label` = 服务端改写形态。
const _groups = <Map<String, Object?>>[
  {
    'provider_id': 'custom:cpa',
    'name': 'CPA',
    'models': [
      {'id': 'minimax-m3.1-flash', 'label': 'Minimax M3.1 Flash'},
      {'id': 'deepseek-v4-flash', 'label': 'Deepseek V4 Flash'},
      {'id': 'gpt-5.6-sol', 'label': 'Gpt 5.6 Sol'},
      {'id': 'muse-spark-1.3', 'label': 'Muse Spark 1.3'},
    ],
  },
  {
    'provider_id': 'custom:ark.cn-beijing.volces.com',
    'name': 'Ark.cn-beijing.volces.com',
    'models': [
      {
        'id': '@custom:ark.cn-beijing.volces.com:doubao-lite-128k-240428',
        'label': 'doubao-lite-128k',
      },
      {
        'id': '@custom:ark.cn-beijing.volces.com:mistral-7b-instruct-v0.2',
        'label': 'mistral-7b',
      },
    ],
  },
  {
    'provider_id': 'openai',
    'name': 'OpenAI',
    'models': [
      {'id': 'gpt-5.4', 'label': 'GPT-5.4'},
      {'id': 'gpt-5.4-mini', 'label': 'GPT-5.4 Mini'},
    ],
  },
];

Future<List<Override>> _overrides() async {
  final store = ConnectionStore(storage: InMemorySecureStorage());
  await store.save(
    ServerConnection(
      id: 'c1',
      name: 'Home 服务器',
      baseUrl: 'http://hermes.local:30002',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await store.setActive('c1');
  final api = FakeSettingsApi();
  api.modelsResponse = ModelsResponse.fromJson({
    'default_model': 'minimax-m3.1-flash',
    'active_provider': 'custom:cpa',
    'groups': _groups,
  });
  api.modelsLiveResponse = ModelsLiveResponse.fromJson({
    'provider': 'custom:cpa',
    'models': [
      {'id': 'minimax-m3.1-flash', 'label': 'Minimax M3.1 Flash'},
      {'id': 'deepseek-v4-flash', 'label': 'Deepseek V4 Flash'},
      {'id': 'gpt-5.6-sol', 'label': 'Gpt 5.6 Sol'},
      {'id': 'muse-spark-1.3', 'label': 'Muse Spark 1.3'},
    ],
  });
  return [
    connectionStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWithValue(
      ApiClient(baseUrl: 'http://hermes.local:30002'),
    ),
    settingsApiFactoryProvider.overrideWithValue((_) => api),
  ];
}

void main() {
  setUpAll(() async {
    await loadHermesGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('默认模型选择页（原始 id） $suffix', (tester) async {
      await pumpHermesPage(
        tester,
        page: const SettingsPage(),
        brightness: brightness,
        overrides: await _overrides(),
        size: _size,
      );
      await tester.pumpAndSettle();

      // 进「默认模型」二级页
      final entry = find.byKey(const ValueKey('settings-default-model'));
      if (entry.evaluate().isEmpty) {
        await tester.scrollUntilVisible(entry, 100);
      }
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      Directory(_shotRoot).createSync(recursive: true);
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('$_shotRoot/model-picker-$suffix.png'),
      );

      await unmountHermesPage(tester);
    }, skip: !_capture);
  }

  test('工装门控', () {
    expect(_capture, isTrue, reason: _skipReason);
  }, skip: !_capture);
}

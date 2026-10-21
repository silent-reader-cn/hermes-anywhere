import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_client_server_panels.dart';
import '../api/api_client_workspace.dart';
import '../connections/connection_providers.dart';
import '../models/server_catalog.dart';
import '../models/workspace.dart';

/// 桌面端外壳共享目录 provider（#145）。
///
/// 侧栏工作区选择器与输入区「工作区 / 模型」元信息 chip 需要同一份
/// 目录数据，故集中在此，避免两处各自拉取（两处口径不一致会造出
/// 「侧栏显示 A 工作区、chip 显示 B」这类自相矛盾的界面）。
///
/// 容错口径与上下文弹层（`context_window_popover._fetchWorkspaces`）
/// 保持一致：**无激活连接或网络失败一律返回空列表，
/// 不抛错、不弹窗**——调用方按「空列表 = 未知」静默退化，绝不因目录拉取
/// 失败阻断聊天或侧栏。

/// 模型 id 归一化键：大小写不敏感，空格 / 下划线一律视作连字符。
///
/// 避免 `Foo Bar` / `foo_bar` / `foo-bar` 这类同模型重复出现；
/// 保留**首个出现**的原始写法供显示与回传（显示必须是原模型名）。
String modelIdDedupeKey(String id) {
  return id.toLowerCase().replaceAll(' ', '-').replaceAll('_', '-');
}

/// 展平各分组的模型选项（models + extraModels），按「provider + 归一 id」
/// 大小写不敏感去重并保序。
///
/// 设置页（`SettingsState.allModels`）与 core 的模型目录快照共用本实现，
/// 保证两处的模型集合口径完全一致（#204）。
List<ModelCatalogOption> flattenModelOptions(
  List<ModelCatalogGroup> groups,
) {
  final result = <ModelCatalogOption>[];
  final seen = <String>{};
  for (final group in groups) {
    for (final model in [...group.models, ...group.extraModels]) {
      final key = model.providerID == null
          ? modelIdDedupeKey(model.id)
          : '${model.providerID!.toLowerCase()}/'
                '${modelIdDedupeKey(model.id)}';
      if (seen.add(key)) result.add(model);
    }
  }
  return result;
}

/// 模型目录快照：`/api/models` 的分组 + 活跃 provider 的实时 id 列表。
class ModelCatalogSnapshot {
  const ModelCatalogSnapshot({
    this.groups = const [],
    this.liveModelIds = const [],
    this.defaultModel,
    this.activeProvider,
  });

  /// provider 分组（分组标题来自 `/api/models`；每组模型为原始 id）。
  final List<ModelCatalogGroup> groups;

  /// 活跃 provider 的实时模型 id（`/api/models/live`，原始写法）。
  final List<String> liveModelIds;

  /// 服务端默认模型 id。
  final String? defaultModel;

  /// 服务端回显的活跃 provider id。
  final String? activeProvider;

  /// 全部模型选项（展平各分组 models + extraModels，大小写归一去重保序）。
  ///
  /// 与设置页共用 [flattenModelOptions]（#204）。
  List<ModelCatalogOption> get allModels => flattenModelOptions(groups);
}

/// 模型目录统一数据源（#204）。
///
/// 设置页「默认模型」列表、上下文弹窗模型下拉、聊天窗口右下角模型 chip
/// **三处共用这一份**——此前三处各拉各的（`/api/models` / `/api/models/live` /
/// 自带兜底拉取），导致模型集合与显示形态都不一致。
///
/// **显示口径：原模型名**。服务端 `/api/models` 下发的 `label` 是「人写名」
/// （`api/routes.py:19912` 的 `_make_label()` 把 id 拆词后首字母大写并以空格
/// 拼接，如 `minimax-m3.1-flash` → `Minimax M3.1 Flash`），而 `/api/models/live`
/// 的 `id` 是**上游网关返回的原始模型名**（本机 CPA 网关实测：
/// `minimax-m3.1-flash` / `deepseek-v4-flash` …）。主人 2026-10-21 明确：
/// 模型名要显示原模型名，不要服务端改写过的形态。
///
/// **仍保留 provider 分组**：设置页的默认模型列表要能选到非活跃 provider 的
/// 模型（只有 `/api/models` 的 `groups` 才有全套 provider），分组标题也来自
/// `/api/models`；但**每行的模型名一律取原始 id**。
final modelCatalogProvider = FutureProvider<ModelCatalogSnapshot>((ref) async {
  final ApiClient client;
  try {
    client = ref.watch(apiClientProvider);
  } catch (_) {
    // 未配置 / 未激活任何服务器连接。
    return const ModelCatalogSnapshot();
  }

  // 两份数据并行取：分组骨架来自缓存目录，实时 id 来自 live 端点。
  // 两者任一失败都不拖垮另一份（失败的那份退化为空）。
  final results = await Future.wait<Object?>([
    _tryFetch(() => client.models()),
    _tryFetch(() => client.modelsLive()),
  ]);

  final modelsResponse = results[0] as ModelsResponse?;
  final liveResponse = results[1] as ModelsLiveResponse?;

  var groups = modelsResponse?.catalogGroups ?? const <ModelCatalogGroup>[];
  final liveIds = _liveModelIds(liveResponse);

  // 活跃 provider 的分组用实时列表覆盖（对齐 iOS `mergingLiveModels`）：
  // 缓存未刷新时也能拿到上游最新模型，避免「设置页少了几个模型」。
  if (liveResponse != null) {
    groups = groups.mergingLiveModels(liveResponse);
  }

  return ModelCatalogSnapshot(
    groups: groups,
    liveModelIds: liveIds,
    defaultModel: modelsResponse?.defaultModel,
    activeProvider: modelsResponse?.activeProvider,
  );
});

/// 取活跃 provider 的实时模型 id（原始写法，去重保序）。
List<String> _liveModelIds(ModelsLiveResponse? live) {
  if (live == null) return const [];
  final ids = <String>[];
  final seen = <String>{};
  for (final option in live.liveOptions) {
    final id = option.id.trim();
    if (id.isEmpty) continue;
    if (seen.add(modelIdDedupeKey(id))) ids.add(id);
  }
  return ids;
}

/// 静默取一份数据：失败返回 null（不抛错、不弹窗）。
Future<T?> _tryFetch<T>(Future<T> Function() fetch) async {
  try {
    return await fetch();
  } catch (_) {
    return null;
  }
}

/// 可用模型 id 列表（`GET /api/models/live`）。
///
/// 与 [modelCatalogProvider] 同源（同一份 live 响应、同一套去重规则），
/// 供聊天侧两个模型选择器共用；**显示与回传都用原始模型名**。
final availableModelIdsProvider = FutureProvider<List<String>>((ref) async {
  final snapshot = await ref.watch(modelCatalogProvider.future);
  return snapshot.liveModelIds;
});

/// 工作区根列表（`GET /api/workspaces`）。
///
/// 端点为「已登记的工作区根」，供侧栏聚合视图与 chip 选择器使用；
/// 与按会话浏览文件树的 `workspaceControllerProvider`（family by sessionId）
/// 不是同一件事，勿混用。
final workspaceRootsProvider = FutureProvider<List<WorkspaceRoot>>((
  ref,
) async {
  final ApiClient client;
  try {
    client = ref.watch(apiClientProvider);
  } catch (_) {
    return const <WorkspaceRoot>[];
  }
  try {
    final response = await client.workspaces();
    return response.workspaces ?? const <WorkspaceRoot>[];
  } catch (_) {
    return const <WorkspaceRoot>[];
  }
});

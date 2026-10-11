// 守卫：注册表 mutation（添加/重命名/移除）后，**缓存型**的 `workspaceRootsProvider`
// 必须被失效 —— 否则聊天输入栏的工作区选择器读到的仍是旧名单。
//
// 现象（主人报）：新建的工作区在 App 里不能马上用 —— 聊天里选择工作区时看不到，
// 要重启 App 才出现。
// 根因：`lib/core/providers/catalog_providers.dart` 的 `workspaceRootsProvider` 是
// **缓存型** FutureProvider（`GET /api/workspaces`，无 autoDispose），而
// workspace_manager 的 mutation 只更新自己的 state（`WorkspaceManagerState`），
// 从不让它失效 ⇒ 选择器（composer_meta_chips）一直读旧名单。
//
// 判据必须能鉴别：只断言「管理页 state 里有新工作区」在**缺陷版本下同样通过**
// （manager state 本来就会用响应替换列表）⇒ 换成「**再读一次
// `workspaceRootsProvider` 会重新发 GET，且拿到含新工作区的名单**」——
// 这一条只有修好的版本才成立（缺陷版本读到的永远是首个缓存值，请求数不增）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/core/providers/catalog_providers.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_providers.dart';

import '../../helpers/fake_workspace_manager_api.dart';

/// 只服务 `GET /api/workspaces` 的假适配器：名单与 manager fake **共享同一份
/// 「服务端真值」**，并记录请求路径（判据要用请求次数）。
class _WorkspacesAdapter implements HttpClientAdapter {
  _WorkspacesAdapter(this.server);

  final FakeWorkspaceManagerApi server;
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode({
        'workspaces': [
          for (final w in server.workspaces) {'path': w.path, 'name': w.name},
        ],
        'last': server.last,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

WorkspaceRoot _root(String path, [String? name]) =>
    WorkspaceRoot(path: path, name: name);

void main() {
  ({
    ProviderContainer container,
    FakeWorkspaceManagerApi api,
    _WorkspacesAdapter adapter,
  })
  makeContainer({List<WorkspaceRoot>? workspaces}) {
    final api = FakeWorkspaceManagerApi(workspaces: workspaces ?? []);
    final adapter = _WorkspacesAdapter(api);
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002', dio: dio),
        ),
        workspaceManagerApiFactoryProvider.overrideWithValue((_) => api),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, api: api, adapter: adapter);
  }

  List<String?> pathsOf(List<WorkspaceRoot> roots) =>
      [for (final r in roots) r.path];

  test('新建工作区后缓存的工作区根列表必须失效（聊天选择器能立刻看到）', () async {
    final ctx = makeContainer(workspaces: [_root('/a', 'A')]);
    final container = ctx.container;

    final before = await container.read(workspaceRootsProvider.future);
    expect(pathsOf(before), ['/a']);
    expect(ctx.adapter.paths.length, 1, reason: '前置：首次读会拉一次');

    await container.read(workspaceManagerControllerProvider.future);
    final err = await container
        .read(workspaceManagerControllerProvider.notifier)
        .addWorkspace(path: '/b', name: 'B');
    expect(err, isNull, reason: '前置：添加应成功');

    // 管理页自己的 state 更新了（这条在缺陷版本下也成立，只作前置，不作判据）。
    expect(
      pathsOf(
        container
            .read(workspaceManagerControllerProvider)
            .valueOrNull!
            .workspaces,
      ),
      ['/a', '/b'],
    );

    // 关键判据：缓存 provider 必须重新拉取。
    final after = await container.read(workspaceRootsProvider.future);
    expect(
      ctx.adapter.paths.length,
      2,
      reason: '添加工作区后必须让 workspaceRootsProvider 失效（重新 GET 一次）',
    );
    expect(
      pathsOf(after),
      ['/a', '/b'],
      reason: '选择器读到的名单应已含新建的工作区（否则就是「新建后聊天里看不到」）',
    );
  });

  test('重命名 / 移除工作区后同样必须失效（选择器不显示旧名单）', () async {
    final ctx = makeContainer(workspaces: [_root('/a', 'A'), _root('/b', 'B')]);
    final container = ctx.container;

    await container.read(workspaceManagerControllerProvider.future);
    final before = await container.read(workspaceRootsProvider.future);
    expect(pathsOf(before), ['/a', '/b']);
    final fetchCountAfterInitial = ctx.adapter.paths.length;

    final renamed = await container
        .read(workspaceManagerControllerProvider.notifier)
        .renameWorkspace(path: '/a', name: 'A2');
    expect(renamed, isTrue, reason: '前置：重命名应成功');

    final afterRename = await container.read(workspaceRootsProvider.future);
    expect(
      ctx.adapter.paths.length,
      fetchCountAfterInitial + 1,
      reason: '重命名后必须失效并重新 GET',
    );
    expect(
      afterRename.firstWhere((w) => w.path == '/a').name,
      'A2',
      reason: '选择器读到的名单应已反映新名字',
    );

    final removed = await container
        .read(workspaceManagerControllerProvider.notifier)
        .removeWorkspace('/b');
    expect(removed, isTrue, reason: '前置：移除应成功');

    final afterRemove = await container.read(workspaceRootsProvider.future);
    expect(pathsOf(afterRemove), ['/a'], reason: '移除后选择器不该再看到该工作区');
  });
}

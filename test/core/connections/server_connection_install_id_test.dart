import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';

// ---------------------------------------------------------------------------
// 配对契约 installId 落地：模型侧（容错解析 / 往返 / copyWith / 相等性）
// + 折叠分组纯函数 [groupConnectionsByInstallId]。
//
// 口径要点：installId **可选**，旧 JSON（无 install_id）解析结果必须与加字段前
// 逐字段一致（installId == ''）、且 toJson 不写出空 install_id。
// ---------------------------------------------------------------------------

/// 加 install_id 之前 [ServerConnection.toJson] 的**逐键**输出（旧连接的 blob 形状）。
Map<String, Object?> legacyJson({
  String id = 'c1',
  String? username,
  String kind = 'remote',
  bool enabled = true,
}) => {
  'id': id,
  'name': 'Home',
  'base_url': 'http://hermes.local:30002',
  'username': ?username,
  'custom_headers': const <String, String>{},
  'created_at': '2026-01-01T00:00:00.000Z',
  'kind': kind,
  'enabled': enabled,
};

ServerConnection buildConn(
  String id, {
  String baseUrl = 'http://hermes.local:30002',
  String installId = '',
  ConnectionKind kind = ConnectionKind.remote,
  Map<String, String> headers = const {},
  String? password,
  String name = 'Home',
  bool enabled = true,
}) => ServerConnection(
  id: id,
  name: name,
  baseUrl: baseUrl,
  password: password,
  customHeaders: headers,
  createdAt: DateTime.utc(2026, 1, 1),
  kind: kind,
  installId: installId,
  enabled: enabled,
);

void main() {
  group('installId · 旧 JSON 兼容（不含 install_id）', () {
    test('① 缺字段 ⇒ installId 为空串，其余字段与加字段前逐字段一致', () {
      final conn = ServerConnection.fromJson(legacyJson());

      expect(conn.installId, '');
      // 逐字段核对「现状」（= 加字段前的解析口径）
      expect(conn.id, 'c1');
      expect(conn.name, 'Home');
      expect(conn.baseUrl, 'http://hermes.local:30002');
      expect(conn.username, isNull);
      expect(conn.password, isNull);
      expect(conn.customHeaders, isEmpty);
      expect(conn.createdAt, DateTime.utc(2026, 1, 1));
      expect(conn.kind, ConnectionKind.remote);
      expect(conn.enabled, isTrue);
      // 与「手写同值连接」相等 —— 证明 == 未因新字段改变旧连接的比较结果
      expect(conn, buildConn('c1'));
      expect(conn.hashCode, buildConn('c1').hashCode);
    });

    test('① 旧 JSON 解析后再序列化：键集合与加字段前逐键一致（无 install_id）', () {
      final json = ServerConnection.fromJson(legacyJson()).toJson();

      expect(json.keys.toSet(), legacyJson().keys.toSet());
      expect(json.containsKey('install_id'), isFalse);
      expect(json, legacyJson());
    });

    test('① builtin 旧 JSON（enabled / username / kind 边界）同样不受影响', () {
      final conn = ServerConnection.fromJson(
        legacyJson(id: 'builtin-sidecar', username: 'admin', kind: 'builtin'),
      );

      expect(conn.kind, ConnectionKind.builtin);
      expect(conn.username, 'admin');
      expect(conn.enabled, isTrue);
      expect(conn.installId, '');
    });
  });

  group('installId · 新字段往返与容错', () {
    test('② toJson → fromJson 保真（非空写出、值原样回来）', () {
      const raw = 'iid-9f3a-77';
      final json = buildConn('c1', installId: raw).toJson();

      expect(json['install_id'], raw);
      expect(ServerConnection.fromJson(json).installId, raw);
    });

    test('② 空 installId 不写出 install_id，往返后仍是空串', () {
      final json = buildConn('c1').toJson();

      expect(json.containsKey('install_id'), isFalse);
      expect(ServerConnection.fromJson(json).installId, '');
    });

    test('② 容错：install_id 非字符串（数字 / 布尔 / null / 列表 / 字典）⇒ 空串，不崩', () {
      for (final bad in <Object?>[42, true, null, <String>['x'], <String, String>{}]) {
        final conn = ServerConnection.fromJson({
          ...legacyJson(),
          'install_id': bad,
        });
        expect(conn.installId, '', reason: '$bad 应被容错为空串');
      }
    });

    test('② copyWith：可设置 installId，不传时保留原值', () {
      final base = buildConn('c1', installId: 'iid-1');

      expect(base.copyWith().installId, 'iid-1');
      expect(base.copyWith(installId: 'iid-2').installId, 'iid-2');
      expect(base.copyWith(name: 'Renamed').installId, 'iid-1');
      // 其余字段不被 installId 的 copyWith 顺带改动
      expect(base.copyWith(installId: 'iid-2').baseUrl, base.baseUrl);
    });

    test('② == / hashCode 进 installId：同位不同机 ⇒ 不等；同值 ⇒ 相等且同 hash', () {
      final a = buildConn('c1', installId: 'iid-1');
      final sameA = buildConn('c1', installId: 'iid-1');
      final b = buildConn('c1', installId: 'iid-2');
      final empty = buildConn('c1');

      expect(a, isNot(b));
      expect(a, isNot(empty));
      expect(a, sameA);
      expect(a.hashCode, sameA.hashCode);
    });
  });

  group('groupConnectionsByInstallId · 折叠分组', () {
    test('③ 同 installId 两个地址 ⇒ 一条分组、主行首现、others 一条', () {
      final groups = groupConnectionsByInstallId([
        buildConn('a', baseUrl: 'http://192.168.1.7:8787', installId: 'iid-1'),
        buildConn('b', baseUrl: 'https://home.example.com', installId: 'iid-1'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.isMulti, isTrue);
      expect(groups.single.installId, 'iid-1');
      expect(groups.single.primary.id, 'a');
      expect(groups.single.others.map((c) => c.id), ['b']);
      // 组内成员无丢失（切换路径靠它）
      expect(groups.single.members.map((c) => c.id), ['a', 'b']);
    });

    test('③ 主行优先取「组内当前激活」的那条（折叠态也看得到在用地址）', () {
      final groups = groupConnectionsByInstallId([
        buildConn('a', installId: 'iid-1'),
        buildConn('b', baseUrl: 'https://home.example.com', installId: 'iid-1'),
      ], activeId: 'b');

      expect(groups.single.primary.id, 'b');
      expect(groups.single.others.map((c) => c.id), ['a']);
      expect(groups.single.members.length, 2);
    });

    test('④ installId 为空（旧连接）⇒ 不合并：每条各自成组、无 others', () {
      final groups = groupConnectionsByInstallId([
        buildConn('a'),
        buildConn('b', baseUrl: 'https://b.example.com'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.every((g) => !g.isMulti), isTrue);
      expect(groups.map((g) => g.primary.id), ['a', 'b']);
      expect(groups.first.installId, '');
    });

    test('④ 空 installId 与同值的非空 installId 也不合并（空 = 未知，不是一台机器）', () {
      final groups = groupConnectionsByInstallId([
        buildConn('a', installId: ''),
        buildConn('b', installId: '', baseUrl: 'https://b.example.com'),
      ]);
      expect(groups.every((g) => !g.isMulti), isTrue);

      final mixed = groupConnectionsByInstallId([
        buildConn('a', installId: ''),
        buildConn('b', installId: 'iid-1', baseUrl: 'https://b.example.com'),
      ]);
      expect(mixed, hasLength(2));
      expect(mixed.every((g) => !g.isMulti), isTrue);
    });

    test('④ 不同 installId ⇒ 各自成组，互不折叠', () {
      final groups = groupConnectionsByInstallId([
        buildConn('a', installId: 'iid-1'),
        buildConn('b', installId: 'iid-2', baseUrl: 'https://b.example.com'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.map((g) => g.installId), ['iid-1', 'iid-2']);
      expect(groups.every((g) => !g.isMulti), isTrue);
    });

    test('④ builtin 不参与折叠：与 remote 同 installId 也各自单列（位置不变）', () {
      final groups = groupConnectionsByInstallId([
        buildConn('builtin-sidecar', kind: ConnectionKind.builtin, installId: 'iid-1'),
        buildConn('a', installId: 'iid-1'),
        buildConn('b', baseUrl: 'https://b.example.com', installId: 'iid-1'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.primary.kind, ConnectionKind.builtin);
      expect(groups.first.isMulti, isFalse);
      expect(groups.last.primary.id, 'a');
      expect(groups.last.others.map((c) => c.id), ['b']);
    });

    test('组位置取 installId 首现处，单条连接保持原顺序（分组不重排列表）', () {
      final groups = groupConnectionsByInstallId([
        buildConn('x', installId: 'iid-9'),
        buildConn('a', installId: 'iid-1'),
        buildConn('b', baseUrl: 'https://b.example.com', installId: 'iid-1'),
        buildConn('y', installId: 'iid-9', baseUrl: 'https://y.example.com'),
        buildConn('z', installId: ''),
      ]);

      expect(groups.map((g) => g.primary.id), ['x', 'a', 'z']);
      expect(groups[0].others.map((c) => c.id), ['y']);
      expect(groups[1].others.map((c) => c.id), ['b']);
      expect(groups[2].isMulti, isFalse);
    });

    test('空输入 / 单条输入：不产生多余分组，也不崩', () {
      expect(groupConnectionsByInstallId(const []), isEmpty);

      final single = groupConnectionsByInstallId([
        buildConn('a', installId: 'iid-1'),
      ]);
      expect(single, hasLength(1));
      expect(single.single.isMulti, isFalse);
    });

    test('三地址同机 ⇒ 一条主行 + others 两条（「另有 2 个地址」的数据源）', () {
      final group = groupConnectionsByInstallId([
        buildConn('a', installId: 'iid-1'),
        buildConn('b', installId: 'iid-1', baseUrl: 'https://b.example.com'),
        buildConn('c', installId: 'iid-1', baseUrl: 'https://c.example.com'),
      ]).single;

      expect(group.isMulti, isTrue);
      expect(group.others, hasLength(2));
      expect(group.members, hasLength(3));
    });
  });
}

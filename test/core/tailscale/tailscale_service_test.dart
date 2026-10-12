import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/tailscale/tailscale_contract.dart';
import 'package:hermes_ui/core/tailscale/tailscale_service.dart';

const String _tempDir = r'C:\Temp\hermes\ts';

ProcessResult _result(int exitCode, [String stdout = '']) =>
    ProcessResult(0, exitCode, stdout, '');

/// 记录调用并按 `exe + 首个参数` 派发脚本化结果的执行器 fake。
///
/// [failAll] 模拟生产默认执行器的测试硬闸门（测试环境真跑系统命令直接抛错）——
/// 用来验证漏注入替身时实现会诚实报 failed，而不是伪装成「未安装」。
class _FakeProcessExecutor implements ProcessExecutor {
  _FakeProcessExecutor({this.failAll = false});

  final bool failAll;
  final List<String> calls = <String>[];
  final Map<String, ProcessResult Function(List<String>)> _handlers =
      <String, ProcessResult Function(List<String>)>{};

  void on(String key, ProcessResult Function(List<String>) handler) {
    _handlers[key] = handler;
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    calls.add('$executable ${arguments.join(' ')}'.trim());
    if (failAll) {
      throw StateError('测试环境禁止真跑系统命令（run: $executable）');
    }
    final joined = arguments.join(' ');
    final first = arguments.isEmpty ? '' : arguments.first;
    final handler = _handlers['$executable $joined'] ??
        _handlers['$executable $first'] ??
        _handlers[executable];
    if (handler == null) {
      throw ProcessException(executable, arguments, 'not found');
    }
    return handler(arguments);
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    throw UnimplementedError('本测试一律注入 fake launcher，不起真实进程');
  }
}

class _FakeLoginLauncher implements TailscaleLoginLauncher {
  final StreamController<String> _output = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  int launchCalls = 0;
  int terminateCalls = 0;

  void emitLine(String line) {
    if (!_output.isClosed) _output.add(line);
  }

  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  Future<void> closeOutput() async {
    if (!_output.isClosed) await _output.close();
  }

  @override
  Future<TailscaleLoginProcess> launchUp() async {
    launchCalls++;
    return TailscaleLoginProcess(
      output: _output.stream,
      exitCode: _exit.future,
      terminate: () async {
        terminateCalls++;
      },
    );
  }
}

class _FakeDownloader implements TailscalePackageDownloader {
  _FakeDownloader({this.error});

  String path = 'C:\\Temp\\hermes\\ts\\tailscale.msi';
  Object? error;
  int calls = 0;
  String? lastUrl;
  String? lastDirectory;

  @override
  Future<String> download({
    required String url,
    required String directory,
  }) async {
    calls++;
    lastUrl = url;
    lastDirectory = directory;
    final failure = error;
    if (failure != null) throw failure;
    return path;
  }
}

class _FakeFileSystemAdapter implements FileSystemAdapter {
  const _FakeFileSystemAdapter({this.isWindows = true});

  @override
  final bool isWindows;

  @override
  String get localAppData => r'C:\Users\Tester\AppData\Local';

  @override
  String get executablePath => r'C:\Program Files\Hermes\hermes.exe';

  @override
  bool directoryExists(String path) => false;

  @override
  bool fileExists(String path) => false;

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  Future<void> writeString(String path, String content) async {}

  @override
  Future<String> readString(String path) async => '';
}

DesktopTailscaleService _buildService(
  _FakeProcessExecutor executor, {
  _FakeLoginLauncher? launcher,
  _FakeDownloader? downloader,
  bool isWindows = true,
  Duration pollInterval = const Duration(milliseconds: 5),
  Duration installTimeout = const Duration(seconds: 3),
}) {
  return DesktopTailscaleService(
    processExecutor: executor,
    fileSystem: _FakeFileSystemAdapter(isWindows: isWindows),
    loginLauncher: launcher,
    packageDownloader: downloader,
    pollInterval: pollInterval,
    installTimeout: installTimeout,
    tempDirectory: _tempDir,
  );
}

/// 收集整条状态流并在流关闭后返回（实现保证必定 close，不会挂住）。
Future<List<TailscaleStatus>> _collect(Stream<TailscaleStatus> stream) {
  final events = <TailscaleStatus>[];
  final done = Completer<void>();
  stream.listen(events.add, onDone: done.complete);
  return done.future.then((_) => events);
}

Future<void> _waitFor(
  bool Function() condition, {
  String reason = '条件',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待「$reason」超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 已安装 + 有地址的手感（`where tailscale` / `tailscale ip -4` 都成功）。
void _scriptInstalledWithAddress(_FakeProcessExecutor executor, String ipv4) {
  executor.on('where tailscale', (_) => _result(0, r'C:\Program Files\Tailscale\ts.exe'));
  executor.on('tailscale ip', (_) => _result(0, '$ipv4\n'));
}

void main() {
  group('probe', () {
    test('未安装（where tailscale 无结果）→ notInstalled', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1));
      final service = _buildService(executor);

      final status = await service.probe();

      expect(status.state, TailscaleState.notInstalled);
      expect(status.isReady, isFalse);
      expect(executor.calls, contains('where tailscale'));
    });

    test('已安装且 tailscale ip -4 给出 100.x → ready(ipv4)', () async {
      final executor = _FakeProcessExecutor();
      _scriptInstalledWithAddress(executor, '100.101.87.11');
      final service = _buildService(executor);

      final status = await service.probe();

      expect(status.state, TailscaleState.ready);
      expect(status.ipv4, '100.101.87.11');
      expect(status.isReady, isTrue);
      expect(status.progress, 1);
    });

    test('已安装但未登录（ip -4 无输出）→ needsLogin', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(0, r'C:\ts.exe'))
        ..on('tailscale ip', (_) => _result(1));
      final service = _buildService(executor);

      final status = await service.probe();

      expect(status.state, TailscaleState.needsLogin);
      expect(status.ipv4, isEmpty);
    });

    test('非 Windows 平台用 which 探测', () async {
      final executor = _FakeProcessExecutor()
        ..on('which tailscale', (_) => _result(1));
      final service = _buildService(executor, isWindows: false);

      final status = await service.probe();

      expect(status.state, TailscaleState.notInstalled);
      expect(executor.calls, contains('which tailscale'));
      expect(executor.calls.any((c) => c.startsWith('where ')), isFalse);
    });

    test('系统命令被硬闸门拦下 → failed，不伪装成「未安装」', () async {
      final executor = _FakeProcessExecutor(failAll: true);
      final service = _buildService(executor);

      final status = await service.probe();

      expect(status.state, TailscaleState.failed);
      expect(status.detail, isNotEmpty);
      expect(status.detail.contains('Exception'), isFalse);
    });
  });

  group('installAndLogin', () {
    test('已就绪：直接 ready，不装任何东西', () async {
      final executor = _FakeProcessExecutor();
      _scriptInstalledWithAddress(executor, '100.64.0.5');
      final downloader = _FakeDownloader();
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        downloader: downloader,
      );

      final events = await _collect(service.installAndLogin());

      expect(events.last.state, TailscaleState.ready);
      expect(events.last.ipv4, '100.64.0.5');
      expect(launcher.launchCalls, 0);
      expect(downloader.calls, 0);
      expect(executor.calls.any((c) => c.startsWith('winget')), isFalse);
      expect(executor.calls.any((c) => c.startsWith('msiexec')), isFalse);
    });

    test('未安装：winget 安装 → 抓授权 URL 报 needsLogin → 轮询出地址报 ready', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1))
        ..on('where winget', (_) => _result(0, r'C:\winget.exe'))
        ..on('winget install', (_) => _result(0));
      var addressOutput = '';
      executor.on('tailscale ip', (_) => _result(0, addressOutput));
      final downloader = _FakeDownloader();
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        downloader: downloader,
      );

      final future = _collect(service.installAndLogin());

      await _waitFor(() => launcher.launchCalls == 1, reason: '启动 tailscale up');
      launcher.emitLine(
        'To authenticate, visit: https://login.tailscale.com/a/0f3c9d21.',
      );
      addressOutput = '100.88.12.7\n';

      final events = await future;

      // winget 参数正确
      expect(
        executor.calls,
        contains('winget install --id Tailscale.Tailscale -e --silent'),
      );
      // 没有走回落路径
      expect(downloader.calls, 0);
      expect(executor.calls.any((c) => c.startsWith('msiexec')), isFalse);

      final needsLogin = events
          .where((s) => s.state == TailscaleState.needsLogin)
          .toList();
      expect(needsLogin, isNotEmpty);
      expect(needsLogin.first.loginUrl, 'https://login.tailscale.com/a/0f3c9d21');
      expect(needsLogin.first.detail.contains('Exception'), isFalse);

      expect(events.last.state, TailscaleState.ready);
      expect(events.last.ipv4, '100.88.12.7');
      expect(events.last.progress, 1);
      // 进度单调不减
      var previous = 0.0;
      for (final status in events) {
        expect(status.progress >= previous, isTrue, reason: '进度不应回退');
        previous = status.progress;
      }
    });

    test('winget 不存在 → 回落下载官方 MSI + msiexec /qn /norestart', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1))
        ..on('where winget', (_) => _result(1))
        ..on('msiexec /i', (_) => _result(0));
      var addressOutput = '';
      executor.on('tailscale ip', (_) => _result(0, addressOutput));
      final downloader = _FakeDownloader();
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        downloader: downloader,
      );

      final future = _collect(service.installAndLogin());
      await _waitFor(() => launcher.launchCalls == 1, reason: '启动 tailscale up');
      launcher.emitLine('visit https://login.tailscale.com/a/abc123');
      addressOutput = '100.7.7.7\n';

      final events = await future;

      expect(downloader.calls, 1);
      expect(downloader.lastUrl, kTailscaleInstallerUrl);
      expect(downloader.lastDirectory, _tempDir);
      expect(
        executor.calls,
        contains(
          r'msiexec /i C:\Temp\hermes\ts\tailscale.msi /qn /norestart',
        ),
      );
      expect(events.last.state, TailscaleState.ready);
      expect(events.last.ipv4, '100.7.7.7');
    });

    test('winget 安装失败（退出码非 0）→ 同样回落 MSI', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1))
        ..on('where winget', (_) => _result(0, r'C:\winget.exe'))
        ..on('winget install', (_) => _result(1))
        ..on('msiexec /i', (_) => _result(0))
        ..on('tailscale ip', (_) => _result(0, '100.9.9.9\n'));
      final downloader = _FakeDownloader();
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        downloader: downloader,
      );

      final events = await _collect(service.installAndLogin());

      expect(downloader.calls, 1);
      expect(executor.calls.any((c) => c.startsWith('msiexec')), isTrue);
      expect(
        events.any(
          (s) => s.detail.contains('winget 安装未成功'),
        ),
        isTrue,
      );
      expect(events.last.state, TailscaleState.ready);
    });

    test('msiexec 失败 → failed（detail 带退出码，不含堆栈）', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1))
        ..on('where winget', (_) => _result(1))
        ..on('msiexec /i', (_) => _result(1603));
      final service = _buildService(
        executor,
        launcher: _FakeLoginLauncher(),
        downloader: _FakeDownloader(),
      );

      final events = await _collect(service.installAndLogin());

      expect(events.last.state, TailscaleState.failed);
      expect(events.last.detail.contains('1603'), isTrue);
      expect(events.last.detail.contains('Exception'), isFalse);
    });

    test('安装包下载失败 → failed（提示手动安装）', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1))
        ..on('where winget', (_) => _result(1));
      final service = _buildService(
        executor,
        launcher: _FakeLoginLauncher(),
        downloader: _FakeDownloader(error: const SocketException('download')),
      );

      final events = await _collect(service.installAndLogin());

      expect(events.last.state, TailscaleState.failed);
      expect(events.last.detail.contains('下载'), isTrue);
      expect(events.last.detail.contains('SocketException'), isFalse);
    });

    test('tailscale up 非 0 退出且拿不到地址 → failed（detail 带退出码）', () async {
      final executor = _FakeProcessExecutor();
      _scriptInstalledWithAddress(executor, '100.1.1.1');
      executor.on('where tailscale', (_) => _result(0, r'C:\ts.exe'));
      executor.on('tailscale ip', (_) => _result(1));
      final launcher = _FakeLoginLauncher();
      final service = _buildService(executor, launcher: launcher);

      final future = _collect(service.installAndLogin());
      await _waitFor(() => launcher.launchCalls == 1, reason: '启动 tailscale up');
      launcher.exit(1);

      final events = await future;

      expect(events.last.state, TailscaleState.failed);
      expect(events.last.detail.contains('1'), isTrue);
      expect(launcher.terminateCalls, greaterThanOrEqualTo(1));
    });

    test('等待授权超时 → failed（提示去浏览器完成登录）', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(0, r'C:\ts.exe'))
        ..on('tailscale ip', (_) => _result(1));
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        installTimeout: const Duration(milliseconds: 120),
      );

      final events = await _collect(service.installAndLogin());

      expect(events.last.state, TailscaleState.failed);
      expect(events.last.detail.contains('超时'), isTrue);
    });

    test('非 Windows 且未安装 → failed（不做一键安装），且不碰 winget', () async {
      final executor = _FakeProcessExecutor()
        ..on('which tailscale', (_) => _result(1));
      final downloader = _FakeDownloader();
      final service = _buildService(
        executor,
        isWindows: false,
        downloader: downloader,
      );

      final events = await _collect(service.installAndLogin());

      expect(events.last.state, TailscaleState.failed);
      expect(downloader.calls, 0);
      expect(executor.calls.any((c) => c.startsWith('winget')), isFalse);
    });

    test('用户取消：cancel() 中断轮询并以 failed(已取消) 收尾，幂等且终止进程', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(0, r'C:\ts.exe'))
        ..on('tailscale ip', (_) => _result(1));
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        installTimeout: const Duration(seconds: 5),
      );

      final future = _collect(service.installAndLogin());
      await _waitFor(() => launcher.launchCalls == 1, reason: '启动 tailscale up');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await service.cancel();
      await service.cancel(); // 幂等：第二次不应抛也不应再发状态

      final events = await future;

      expect(events.last.state, TailscaleState.failed);
      expect(events.last.detail, '已取消安装');
      expect(
        events.where((s) => s.detail == '已取消安装').length,
        1,
        reason: '取消只应上报一次',
      );
      expect(launcher.terminateCalls, greaterThanOrEqualTo(1));
    });

    test('空闲时 cancel() 是空操作（幂等，不抛）', () async {
      final executor = _FakeProcessExecutor();
      _scriptInstalledWithAddress(executor, '100.2.2.2');
      final service = _buildService(executor, launcher: _FakeLoginLauncher());

      await service.cancel();
      await service.cancel();

      final status = await service.probe();
      expect(status.state, TailscaleState.ready);
    });

    test('所有上报 detail 都是中文短语（不塞堆栈/异常类名）', () async {
      final executor = _FakeProcessExecutor()
        ..on('where tailscale', (_) => _result(1))
        ..on('where winget', (_) => _result(0, r'C:\winget.exe'))
        ..on('winget install', (_) => _result(0))
        ..on('tailscale ip', (_) => _result(0, '100.3.3.3\n'));
      final launcher = _FakeLoginLauncher();
      final service = _buildService(
        executor,
        launcher: launcher,
        downloader: _FakeDownloader(),
      );

      final events = await _collect(service.installAndLogin());
      final cjk = RegExp(r'[\u4e00-\u9fa5]');

      expect(events, isNotEmpty);
      for (final status in events) {
        expect(status.detail.contains('Exception'), isFalse);
        expect(status.detail.contains('#0'), isFalse);
        expect(status.detail.contains('package:'), isFalse);
        if (status.detail.isNotEmpty) {
          expect(
            cjk.hasMatch(status.detail),
            isTrue,
            reason: 'detail 必须是给用户看的中文短语：${status.detail}',
          );
        }
      }
    });
  });

  group('extractTailscaleLoginUrl', () {
    test('从真实输出行里抽授权 URL 并去掉尾随标点', () {
      expect(
        extractTailscaleLoginUrl(
          'To authenticate, visit: https://login.tailscale.com/a/0f3c9d21.',
        ),
        'https://login.tailscale.com/a/0f3c9d21',
      );
      expect(
        extractTailscaleLoginUrl(
          'see (https://login.tailscale.com/a/beef) for details',
        ),
        'https://login.tailscale.com/a/beef',
      );
      expect(extractTailscaleLoginUrl('no url here'), isNull);
      expect(extractTailscaleLoginUrl(''), isNull);
    });
  });
}

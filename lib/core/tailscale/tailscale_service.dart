/// Tailscale 服务实现：探测 → 一键安装 → 引导登录 → 轮询出地址。
///
/// ## 诚实边界（照契约的话再说一遍）
/// Tailscale **不支持邮箱注册**，登录必须走第三方 IdP（Google / 微软 / GitHub / Apple），
/// 浏览器里那一次授权**无法代劳**。本实现能做的只有三件：
/// 静默安装（winget，失败回落官方 MSI + msiexec）、把授权 URL 交给 UI 打开、轮询到地址出现。
///
/// ## 可测性
/// 所有系统调用都走 [ProcessExecutor]（生产 = `dart:io Process`，测试 = fake）；
/// `tailscale up` 的流式输出通过 [TailscaleLoginLauncher] 注入（测试无需起真实进程）；
/// 安装包下载通过 [TailscalePackageDownloader] 注入；轮询间隔 / 超时 / 安装包地址可调，
/// 测试用毫秒级间隔跑完整流程。默认执行器在 `flutter test` 里会**硬闸门抛错**，
/// 所以漏注入替身的用例会立刻变红，而不是偷偷跑真实系统命令。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../install/install_detector.dart'
    show
        FileSystemAdapter,
        ProcessExecutor,
        SystemFileSystemAdapter,
        SystemProcessExecutor;
import 'tailscale_contract.dart';

/// 官方安装包地址（winget 不可用时的回落路径）。
const String kTailscaleInstallerUrl =
    'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi';

/// tailnet 地址形态：`100.x.y.z`（IPv4，Tailscale 保留段）。
final RegExp tailnetIpv4Pattern = RegExp(r'^100\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

/// 从 `tailscale up` 的输出行里抽授权 URL（没有则 null）。
///
/// 兼容真实输出形态：URL 后面可能跟句号/右括号，或被 ANSI 码/引号包住。
String? extractTailscaleLoginUrl(String line) {
  final match = RegExp(r'''https://login\.tailscale\.com/[^\s"'<>)]+''')
      .firstMatch(line);
  final url = match?.group(0);
  if (url == null || url.isEmpty) return null;
  return url.replaceAll(RegExp(r'[.,;]+$'), '');
}

/// `tailscale up` 进程句柄：输出行流 + 退出码 + 终止手段。
///
/// 不直接暴露 `Process` —— 测试里伪造 `Process` 需要连 `IOSink` 一起实现，
/// 太大且容易伪造出与真实行为不符的替身；这里只保留实现真正用到的三件事。
class TailscaleLoginProcess {
  const TailscaleLoginProcess({
    required this.output,
    required this.exitCode,
    required this.terminate,
  });

  /// stdout + stderr 合并后的行流。
  final Stream<String> output;

  /// 进程退出码。
  final Future<int> exitCode;

  /// 终止进程（幂等由调用方保证）。
  final Future<void> Function() terminate;
}

/// `tailscale up` 启动器接缝（测试注入 fake）。
abstract interface class TailscaleLoginLauncher {
  Future<TailscaleLoginProcess> launchUp();
}

/// 生产启动器：`Process.start('tailscale', ['up'])`。
class SystemTailscaleLoginLauncher implements TailscaleLoginLauncher {
  const SystemTailscaleLoginLauncher(this.processExecutor);

  final ProcessExecutor processExecutor;

  @override
  Future<TailscaleLoginProcess> launchUp() async {
    final process = await processExecutor.start('tailscale', const ['up']);
    final lines = StreamController<String>();
    void addLine(String line) {
      if (!lines.isClosed) lines.add(line);
    }

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(addLine)
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(addLine)
        .asFuture<void>();
    // 输出排空后再关流：否则退出瞬间的最后几行（含授权 URL）会丢。
    unawaited(() async {
      try {
        await Future.wait<void>([stdoutDone, stderrDone]);
      } catch (_) {
        // 输出流异常不影响退出码判定。
      }
      if (!lines.isClosed) await lines.close();
    }());

    return TailscaleLoginProcess(
      output: lines.stream,
      exitCode: process.exitCode,
      terminate: () async {
        process.kill();
      },
    );
  }
}

/// 安装包下载器接缝（测试注入 fake，避免真下载几百 MB）。
abstract interface class TailscalePackageDownloader {
  /// 下载 [url] 到 [directory]，返回本地路径。
  Future<String> download({required String url, required String directory});
}

/// 生产下载器：`HttpClient` 落盘。
class SystemTailscalePackageDownloader implements TailscalePackageDownloader {
  const SystemTailscalePackageDownloader();

  @override
  Future<String> download({
    required String url,
    required String directory,
  }) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final fileName = url.split('/').last;
    final name = fileName.isEmpty ? 'tailscale-setup.msi' : fileName;
    final target = File('$directory${Platform.pathSeparator}$name');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          '下载 Tailscale 安装包失败：HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      // pipe 会关闭 sink。
      await response.pipe(target.openWrite());
      return target.path;
    } finally {
      client.close(force: true);
    }
  }
}

/// Tailscale 服务实现。
class DesktopTailscaleService implements TailscaleService {
  DesktopTailscaleService({
    this.processExecutor = const SystemProcessExecutor(),
    this.fileSystem = const SystemFileSystemAdapter(),
    TailscaleLoginLauncher? loginLauncher,
    TailscalePackageDownloader? packageDownloader,
    this.pollInterval = const Duration(seconds: 2),
    this.installTimeout = const Duration(minutes: 10),
    this.installerUrl = kTailscaleInstallerUrl,
    this.tempDirectory,
  })  : _loginLauncher =
            loginLauncher ?? SystemTailscaleLoginLauncher(processExecutor),
        _packageDownloader =
            packageDownloader ?? const SystemTailscalePackageDownloader();

  /// 系统命令执行器（生产 = dart:io Process；测试 = fake）。
  final ProcessExecutor processExecutor;

  /// 文件系统/平台适配（测试可伪造平台，例如验证非 Windows 分支）。
  final FileSystemAdapter fileSystem;

  final TailscaleLoginLauncher _loginLauncher;
  final TailscalePackageDownloader _packageDownloader;

  /// 安装包落盘目录（默认系统临时目录；测试注入假目录免写盘）。
  final String? tempDirectory;

  /// 轮询 `tailscale ip -4` 的间隔（生产 2 秒）。
  final Duration pollInterval;

  /// 等待授权的最长时间。
  final Duration installTimeout;

  /// 回落安装包地址。
  final String installerUrl;

  StreamController<TailscaleStatus>? _active;
  TailscaleLoginProcess? _loginProcess;
  bool _cancelled = false;

  @override
  Future<TailscaleStatus> probe() async {
    final installed = await _detectInstalled();
    if (installed == null) {
      // 探测本身没跑成：诚实报 failed，不伪装成「未安装」。
      return const TailscaleStatus(
        state: TailscaleState.failed,
        detail: '无法探测 Tailscale（系统命令执行失败）',
      );
    }
    if (!installed) {
      return const TailscaleStatus(
        state: TailscaleState.notInstalled,
        detail: '未检测到 Tailscale',
      );
    }
    final ipv4 = await _readTailnetIpv4();
    if (ipv4 != null) {
      return TailscaleStatus(
        state: TailscaleState.ready,
        ipv4: ipv4,
        progress: 1,
        detail: 'Tailscale 已就绪：$ipv4',
      );
    }
    return const TailscaleStatus(
      state: TailscaleState.needsLogin,
      detail: '已安装但尚未登录',
    );
  }

  @override
  Stream<TailscaleStatus> installAndLogin() {
    final controller = StreamController<TailscaleStatus>();
    _cancelled = false;
    _loginProcess = null;
    _active = controller;
    unawaited(_run(controller));
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final controller = _active;
    final login = _loginProcess;
    _loginProcess = null;
    if (login != null) {
      try {
        await login.terminate();
      } catch (_) {
        // 进程可能已退出 —— 取消本身不该失败。
      }
    }
    if (controller == null || controller.isClosed) {
      _active = null;
      return;
    }
    // 契约的 TailscaleState 没有 cancelled 取值，故以 failed + 中文说明收尾
    //（契约缺口，见任务终报）。
    _emit(
      controller,
      const TailscaleStatus(
        state: TailscaleState.failed,
        detail: '已取消安装',
      ),
    );
    _active = null;
    await controller.close();
  }

  Future<void> _run(StreamController<TailscaleStatus> controller) async {
    try {
      _emit(
        controller,
        const TailscaleStatus(
          state: TailscaleState.installing,
          progress: 0.05,
          detail: '正在检测 Tailscale',
        ),
      );
      final installed = await _detectInstalled();
      if (_cancelled) return;
      if (installed == null) {
        _emit(
          controller,
          const TailscaleStatus(
            state: TailscaleState.failed,
            progress: 0.05,
            detail: '无法探测 Tailscale（系统命令执行失败）',
          ),
        );
        return;
      }

      if (installed) {
        final ipv4 = await _readTailnetIpv4();
        if (_cancelled) return;
        if (ipv4 != null) {
          _emit(
            controller,
            TailscaleStatus(
              state: TailscaleState.ready,
              ipv4: ipv4,
              progress: 1,
              detail: 'Tailscale 已就绪：$ipv4',
            ),
          );
          return;
        }
        await _loginAndPoll(controller);
        return;
      }

      if (!fileSystem.isWindows) {
        _emit(
          controller,
          const TailscaleStatus(
            state: TailscaleState.failed,
            progress: 0.05,
            detail: '当前平台不支持一键安装，请手动安装 Tailscale',
          ),
        );
        return;
      }

      final installedNow = await _install(controller);
      if (_cancelled) return;
      if (!installedNow) return;
      await _loginAndPoll(controller);
    } catch (_) {
      _emit(
        controller,
        const TailscaleStatus(
          state: TailscaleState.failed,
          detail: '安装过程出现异常，请手动安装 Tailscale',
        ),
      );
    } finally {
      _loginProcess = null;
      if (identical(_active, controller)) _active = null;
      if (!controller.isClosed) await controller.close();
    }
  }

  /// 安装阶段；返回 true = 装好了可以继续登录，false = 已上报失败，终止。
  Future<bool> _install(StreamController<TailscaleStatus> controller) async {
    var installed = false;
    if (await _hasWinget()) {
      if (_cancelled) return false;
      _emit(
        controller,
        const TailscaleStatus(
          state: TailscaleState.installing,
          progress: 0.2,
          detail: '正在用 winget 安装 Tailscale',
        ),
      );
      final code = await _runCommand('winget', const [
        'install',
        '--id',
        'Tailscale.Tailscale',
        '-e',
        '--silent',
      ]);
      installed = code == 0;
      if (!installed) {
        _emit(
          controller,
          const TailscaleStatus(
            state: TailscaleState.installing,
            progress: 0.3,
            detail: 'winget 安装未成功，改用官方安装包',
          ),
        );
      }
    }

    if (!installed) {
      if (_cancelled) return false;
      _emit(
        controller,
        const TailscaleStatus(
          state: TailscaleState.installing,
          progress: 0.35,
          detail: '正在下载 Tailscale 官方安装包',
        ),
      );
      final directory = tempDirectory ?? Directory.systemTemp.path;
      String? msiPath;
      try {
        msiPath = await _packageDownloader.download(
          url: installerUrl,
          directory: directory,
        );
      } catch (_) {
        msiPath = null;
      }
      if (_cancelled) return false;
      if (msiPath == null || msiPath.isEmpty) {
        _emit(
          controller,
          const TailscaleStatus(
            state: TailscaleState.failed,
            progress: 0.35,
            detail: '下载 Tailscale 安装包失败，请检查网络或手动安装',
          ),
        );
        return false;
      }
      _emit(
        controller,
        const TailscaleStatus(
          state: TailscaleState.installing,
          progress: 0.55,
          detail: '正在静默安装 Tailscale',
        ),
      );
      final code = await _runCommand('msiexec', [
        '/i',
        msiPath,
        '/qn',
        '/norestart',
      ]);
      // 3010 = 成功但需要重启。
      installed = code == 0 || code == 3010;
      if (!installed) {
        _emit(
          controller,
          TailscaleStatus(
            state: TailscaleState.failed,
            progress: 0.55,
            detail: '安装 Tailscale 失败（退出码 ${code ?? '未知'}）',
          ),
        );
        return false;
      }
    }
    return true;
  }

  /// 启动 `tailscale up` 抓授权 URL，然后每 [pollInterval] 轮询出地址。
  Future<void> _loginAndPoll(
    StreamController<TailscaleStatus> controller,
  ) async {
    _emit(
      controller,
      const TailscaleStatus(
        state: TailscaleState.installing,
        progress: 0.6,
        detail: '正在启动 Tailscale 授权',
      ),
    );

    TailscaleLoginProcess? login;
    try {
      login = await _loginLauncher.launchUp();
    } catch (_) {
      // up 进程起不来（例如已登录）也能靠轮询判定，不因此失败。
      login = null;
    }
    _loginProcess = login;

    StreamSubscription<String>? subscription;
    var exited = false;
    var exitCode = 0;
    var urlSeen = false;

    if (login != null) {
      subscription = login.output.listen((line) {
        final url = extractTailscaleLoginUrl(line);
        if (url == null || urlSeen) return;
        urlSeen = true;
        _emit(
          controller,
          TailscaleStatus(
            state: TailscaleState.needsLogin,
            loginUrl: url,
            progress: 0.7,
            detail: '请在浏览器里用 Google / 微软 / GitHub 账号完成授权',
          ),
        );
      });
      unawaited(
        login.exitCode.then<void>((code) {
          exited = true;
          exitCode = code;
        }).catchError((Object _) {
          exited = true;
        }),
      );
    }

    final deadline = DateTime.now().add(installTimeout);
    try {
      while (true) {
        if (_cancelled) return;
        final ipv4 = await _readTailnetIpv4();
        if (_cancelled) return;
        if (ipv4 != null) {
          _emit(
            controller,
            TailscaleStatus(
              state: TailscaleState.ready,
              ipv4: ipv4,
              progress: 1,
              detail: 'Tailscale 已就绪：$ipv4',
            ),
          );
          return;
        }
        if (exited && !urlSeen && exitCode != 0) {
          _emit(
            controller,
            TailscaleStatus(
              state: TailscaleState.failed,
              progress: 0.7,
              detail: 'Tailscale 启动失败（退出码 $exitCode），请手动运行 tailscale up',
            ),
          );
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          _emit(
            controller,
            const TailscaleStatus(
              state: TailscaleState.failed,
              progress: 0.7,
              detail: '等待授权超时，请确认已在浏览器里完成登录',
            ),
          );
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      if (subscription != null) {
        try {
          await subscription.cancel();
        } catch (_) {}
      }
      _loginProcess = null;
      if (login != null) {
        try {
          await login.terminate();
        } catch (_) {
          // 进程可能已自行退出。
        }
      }
    }
  }

  /// 探测是否已安装；返回 null 表示探测本身失败（不伪装成未安装）。
  Future<bool?> _detectInstalled() async {
    try {
      final command = fileSystem.isWindows ? 'where' : 'which';
      final result = await processExecutor.run(command, const ['tailscale']);
      if (result.exitCode != 0) return false;
      return result.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  /// 读取 tailnet 的 100.x 地址；未登录 / 命令失败返回 null。
  Future<String?> _readTailnetIpv4() async {
    try {
      final result = await processExecutor.run('tailscale', const [
        'ip',
        '-4',
      ]);
      if (result.exitCode != 0) return null;
      for (final line in const LineSplitter().convert(result.stdout.toString())) {
        final candidate = line.trim();
        if (tailnetIpv4Pattern.hasMatch(candidate)) return candidate;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool> _hasWinget() async {
    if (!fileSystem.isWindows) return false;
    try {
      final result = await processExecutor.run('where', const ['winget']);
      return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _runCommand(String executable, List<String> arguments) async {
    try {
      final result = await processExecutor.run(executable, arguments);
      return result.exitCode;
    } catch (_) {
      return null;
    }
  }

  void _emit(
    StreamController<TailscaleStatus> controller,
    TailscaleStatus status,
  ) {
    if (controller.isClosed) return;
    controller.add(status);
  }
}

/// [TailscaleService] 的真实实现 provider。
///
/// 契约里的注入点 [tailscaleServiceProvider] 仍是「未覆盖即抛错」，
/// 由 `core/pairing/pairing_runtime_providers.dart` 的覆盖入口点亮（桌面端启动时使用）。
final desktopTailscaleServiceProvider = Provider<TailscaleService>(
  (ref) => DesktopTailscaleService(),
);

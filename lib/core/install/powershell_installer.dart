import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'install_detector.dart';

/// 安装事件类型。
enum InstallerEventType {
  manifest,
  stageStart,
  progress,
  log,
  stageSuccess,
  stageFailure,
}

/// 安装事件帧。
class InstallerEvent {
  const InstallerEvent({
    required this.type,
    this.stage,
    this.title,
    this.message,
    this.progress,
    this.reason,
    this.stages,
    this.raw = '',
  });

  final InstallerEventType type;
  final String? stage;
  final String? title;
  final String? message;
  final double? progress; // 0.0 ~ 1.0
  final String? reason;
  final List<String>? stages;
  final String raw;

  factory InstallerEvent.manifest(List<String> stages, {String raw = ''}) =>
      InstallerEvent(
        type: InstallerEventType.manifest,
        stages: stages,
        raw: raw,
      );

  factory InstallerEvent.stageStart(
    String stage, {
    String? title,
    String? message,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.stageStart,
        stage: stage,
        title: title,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.progress(
    String stage,
    double progress, {
    String? message,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.progress,
        stage: stage,
        progress: progress,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.log(
    String message, {
    String? stage,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.log,
        stage: stage,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.stageSuccess(
    String stage, {
    String? message,
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.stageSuccess,
        stage: stage,
        message: message,
        raw: raw,
      );

  factory InstallerEvent.stageFailure(
    String stage,
    String reason, {
    String raw = '',
  }) =>
      InstallerEvent(
        type: InstallerEventType.stageFailure,
        stage: stage,
        reason: reason,
        raw: raw,
      );

  /// 逐行解析 stdout / stderr 为事件帧（非 JSON 字符串优雅降级为 log）。
  factory InstallerEvent.parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return InstallerEvent.log('', raw: line);
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        // 1. 处理 { "ok": false, "stage": ..., "reason": ... }
        if (decoded['ok'] == false) {
          return InstallerEvent.stageFailure(
            decoded['stage']?.toString() ?? 'unknown',
            decoded['reason']?.toString() ??
                decoded['message']?.toString() ??
                decoded['error']?.toString() ??
                'Stage failed',
            raw: line,
          );
        }

        // 2. 处理 { "ok": true, "stage": ... }
        if (decoded['ok'] == true && decoded['event'] == null) {
          return InstallerEvent.stageSuccess(
            decoded['stage']?.toString() ?? '',
            message: decoded['message']?.toString(),
            raw: line,
          );
        }

        // 3. 处理具名 event 结构
        final event =
            decoded['event']?.toString() ?? decoded['type']?.toString();

        // 3a. 官方 `-Manifest` 的实际输出是
        // `{protocol_version, stages: [{name, title, category, ...}]}` ——
        // **没有** `event` 字段。只按 event 名分支会永远落进 default，名单便永远
        // 取不到（调用方只能硬编码旧名）。故先按「带 stages 数组」识别。
        final rawStages = decoded['stages'];
        if (event == null && rawStages is List) {
          return InstallerEvent.manifest(
            _manifestStagesOf(rawStages),
            raw: line,
          );
        }

        switch (event) {
          case 'manifest':
            // 兼容显式打 event:manifest 的旧脚本；项可以是对象
            // （`{name, title, ...}`）或字符串，两种都要读出 stage 名。
            final list = rawStages is List
                ? _manifestStagesOf(rawStages)
                : const <String>[];
            return InstallerEvent.manifest(list, raw: line);
          case 'stage_start':
          case 'start':
            return InstallerEvent.stageStart(
              decoded['stage']?.toString() ?? '',
              title:
                  decoded['title']?.toString() ?? decoded['name']?.toString(),
              message: decoded['message']?.toString(),
              raw: line,
            );
          case 'progress':
            final pct = decoded['percent'] ?? decoded['progress'];
            double progressVal = 0.0;
            if (pct is num) {
              progressVal = pct > 1.0 ? pct / 100.0 : pct.toDouble();
            }
            return InstallerEvent.progress(
              decoded['stage']?.toString() ?? '',
              progressVal,
              message: decoded['message']?.toString(),
              raw: line,
            );
          case 'stage_success':
          case 'stage_done':
          case 'done':
            return InstallerEvent.stageSuccess(
              decoded['stage']?.toString() ?? '',
              message: decoded['message']?.toString(),
              raw: line,
            );
          case 'stage_failure':
          case 'error':
            return InstallerEvent.stageFailure(
              decoded['stage']?.toString() ?? '',
              decoded['reason']?.toString() ??
                  decoded['message']?.toString() ??
                  'Stage failed',
              raw: line,
            );
          case 'log':
          default:
            return InstallerEvent.log(
              decoded['message']?.toString() ??
                  decoded['line']?.toString() ??
                  trimmed,
              stage: decoded['stage']?.toString(),
              raw: line,
            );
        }
      }
    } catch (_) {
      // 非 JSON 格式 → 降级为 log
    }
    return InstallerEvent.log(trimmed, raw: line);
  }

  /// 从 manifest 的 `stages` 数组里读出 stage 名列表（兼容对象项与字符串项）。
  static List<String> _manifestStagesOf(List<dynamic> raw) => raw
      .map(_stageNameOf)
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  /// 从 manifest 的单项里取 stage 名（兼容字符串项与对象项）。
  static String _stageNameOf(dynamic item) {
    if (item is Map) {
      return (item['name'] ?? item['stage'] ?? '').toString();
    }
    return item?.toString() ?? '';
  }
}

/// HTTP 脚本下载器抽象（测试可注入 fake）。
abstract interface class ScriptDownloader {
  Future<String> downloadScript(String url);
}

/// 默认生产脚本下载器（基于 HttpClient）。
class SystemScriptDownloader implements ScriptDownloader {
  const SystemScriptDownloader();

  @override
  Future<String> downloadScript(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return await res.transform(utf8.decoder).join();
      }
      throw HttpException('Failed to download script: HTTP ${res.statusCode}');
    } finally {
      client.close();
    }
  }
}

/// PowerShell 安装器接口。
abstract interface class PowershellInstaller {
  static const String defaultScriptUrl =
      'https://hermes-agent.nousresearch.com/install.ps1';

  /// 确保 install.ps1 脚本已缓存到本地。
  Future<String> ensureScriptCached({
    String url = defaultScriptUrl,
    String? destinationPath,
  });

  /// 获取官方支持的 stage 列表清单。
  Future<List<String>> getManifest({String? scriptPath});

  /// 运行单个 stage，逐行流式产生事件帧。
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  });
}

/// [PowershellInstaller] 生产默认实现。
class DefaultPowershellInstaller implements PowershellInstaller {
  DefaultPowershellInstaller({
    this.processExecutor = const SystemProcessExecutor(),
    this.fileSystem = const SystemFileSystemAdapter(),
    this.downloader = const SystemScriptDownloader(),
  });

  final ProcessExecutor processExecutor;
  final FileSystemAdapter fileSystem;
  final ScriptDownloader downloader;

  String get _defaultScriptPath {
    final base = fileSystem.localAppData;
    if (base.isEmpty) return 'install.ps1';
    return '$base\\hermes\\install.ps1';
  }

  @override
  Future<String> ensureScriptCached({
    String url = PowershellInstaller.defaultScriptUrl,
    String? destinationPath,
  }) async {
    final targetPath = destinationPath ?? _defaultScriptPath;
    if (fileSystem.fileExists(targetPath)) {
      return targetPath;
    }

    // 确保父目录存在
    final lastSlash = targetPath.lastIndexOf(Platform.pathSeparator);
    if (lastSlash > 0) {
      final dir = targetPath.substring(0, lastSlash);
      await fileSystem.createDirectory(dir);
    }

    try {
      final content = await downloader.downloadScript(url);
      await fileSystem.writeString(targetPath, content);
      return targetPath;
    } catch (e) {
      // 若下载失败且本地不存在，抛出带提示的异常
      throw Exception(
        '下载官方 install.ps1 失败，请检查网络或手动下载并放置到: $targetPath\n原因: $e',
      );
    }
  }

  @override
  Future<List<String>> getManifest({String? scriptPath}) async {
    final path = scriptPath ?? _defaultScriptPath;
    try {
      final res = await processExecutor.run('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        path,
        '-Manifest',
        '-NonInteractive',
        '-Json',
      ]);
      if (res.exitCode == 0) {
        final lines = LineSplitter.split(res.stdout.toString());
        for (final line in lines) {
          final event = InstallerEvent.parseLine(line);
          if (event.type == InstallerEventType.manifest &&
              event.stages != null &&
              event.stages!.isNotEmpty) {
            return event.stages!;
          }
        }
      }
    } catch (_) {
      // 忽略异常，降级到默认清单
    }
    // 取不到 manifest 时按当前官方脚本的 stage 名单兜底：旧名
    // （prereqs/agent/deps）已被脚本判 unknown stage，不能再用作默认值。
    return const [
      'prerequisites',
      'repository',
      'venv',
      'python-deps',
      'config',
      'products',
      'setup',
      'gateway',
      'complete',
    ];
  }

  @override
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  }) {
    final controller = StreamController<InstallerEvent>();
    final path = scriptPath ?? _defaultScriptPath;
    final home = hermesHome ??
        (fileSystem.localAppData.isNotEmpty
            ? '${fileSystem.localAppData}\\hermes'
            : null);

    controller.add(InstallerEvent.stageStart(
      stageName,
      title: 'Executing stage: $stageName',
    ));

    final args = <String>[
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path,
      '-Stage',
      stageName,
      '-NonInteractive',
      '-Json',
    ];
    if (home != null && home.isNotEmpty) {
      args.addAll(['-HermesHome', home]);
      // 同时钉死安装目录。官方脚本的 `-InstallDir` 默认**只跟随 `$env:HERMES_HOME`
      // 环境变量**，不跟 `-HermesHome` 参数（实机实测：两者共存时 hermes_home 取
      // 参数值、install_dir 取环境变量值）⇒ agent 与依赖环境会装到另一个 home 下，
      // 而客户端只在 `<LOCALAPPDATA>\hermes\hermes-agent` 里找解释器，随后必然报
      // 「解释器缺失」。显式传 `-InstallDir` ⇒ 装到哪儿 = 客户端要看的哪儿。
      args.addAll(['-InstallDir', '$home\\hermes-agent']);
    }

    unawaited(() async {
      Process? process;
      try {
        process = await processExecutor.start('powershell', args);
      } catch (e) {
        controller.add(InstallerEvent.stageFailure(
          stageName,
          '无法启动 PowerShell 进程: $e',
        ));
        await controller.close();
        return;
      }

      var hadFailure = false;
      void handleLine(String line) {
        final event = InstallerEvent.parseLine(line);
        if (event.type == InstallerEventType.stageFailure) {
          hadFailure = true;
        }
        controller.add(event);
      }

      final outSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);

      final errSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) {
          handleLine(line);
        }
      });

      // ⚠️ asFuture 必须在流 close 之前挂上：进程退出后 stdout/stderr 已 done，
      // 此时再调 asFuture 永远不会收到完成事件 → Future.wait 永不 resolve
      //（stdout 零输出的 stage 会静默卡死，既无成功终帧也无失败终帧）。
      final outDone = outSub.asFuture<void>();
      final errDone = errSub.asFuture<void>();
      final exitCode = await process.exitCode;
      await Future.wait([outDone, errDone]);

      if (exitCode != 0 && !hadFailure) {
        controller.add(InstallerEvent.stageFailure(
          stageName,
          'PowerShell 退出异常，退出码: $exitCode',
        ));
      } else if (exitCode == 0 && !hadFailure) {
        controller.add(InstallerEvent.stageSuccess(
          stageName,
          message: 'Stage $stageName completed successfully',
        ));
      }
      await controller.close();
    }());

    return controller.stream;
  }
}

/// [PowershellInstaller] Provider。
final powershellInstallerProvider = Provider<PowershellInstaller>(
  (ref) => DefaultPowershellInstaller(),
);

/// 客户端安装轨的抽象步：只描述「要跑官方脚本的哪一段」。
///
/// 与 UI 的 5 步轨（环境检查 / 拉取 / 依赖 / 启动服务 / 配对）解耦：UI 步数会
/// 随产品调整，这里只认官方脚本的语义段。
enum InstallStepGroup { prerequisites, repository, dependencies }

/// 抽象步 → 官方 `install.ps1` 的 stage 名候选（按执行顺序）。
///
/// 官方 2026-10 改版把 stage 从 `prereqs / agent / deps` 重命名为
/// `prerequisites / repository / venv / python-deps / config / products /
/// complete`，并把「装依赖」拆成多个独立 stage。客户端此前硬编码旧名，脚本
/// 直接判 `unknown stage: prereqs` 后 exit 2 ⇒ 第一步必然失败。
///
/// 这里同时保留两代名字，**真实跑哪几个由 `-Manifest` 的实际名单决定**
/// （见 [resolveInstallStageChain]）。硬编码单一名字是这次故障的根因，不许回退。
const Map<InstallStepGroup, List<String>> installStepStageCandidates = {
  InstallStepGroup.prerequisites: ['prerequisites', 'prereqs'],
  InstallStepGroup.repository: ['repository', 'agent'],
  InstallStepGroup.dependencies: [
    'venv',
    'python-deps',
    'config',
    'products',
    'complete',
    'deps',
  ],
};

/// 把抽象步解析成 manifest 里真实存在的 stage 名链。
///
/// - manifest 命中哪个候选就跑哪个：新协议一次跑多个 stage
///   （venv → python-deps → config → products → complete），旧协议只跑 `deps`；
/// - manifest 为空（脚本不认 `-Manifest` 或解析失败）时退回候选表首项，即当前
///   官方脚本的名字；
/// - 候选全不命中时同样退回首项 —— 让脚本自己报 `unknown stage` 并把原因原样
///   上抛给用户，不做静默降级（静默降级会变成「装了一半、界面显示成功」）。
List<String> resolveInstallStageChain(
  InstallStepGroup group,
  List<String> manifest,
) {
  final candidates = installStepStageCandidates[group] ?? const <String>[];
  if (candidates.isEmpty) return const <String>[];
  if (manifest.isEmpty) return <String>[candidates.first];
  final known = manifest.toSet();
  final matched = candidates.where(known.contains).toList(growable: false);
  return matched.isEmpty ? <String>[candidates.first] : matched;
}

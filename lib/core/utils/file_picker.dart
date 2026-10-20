import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;

/// 文件选择结果（跨平台封装）。
///
/// 来自 [FilePickerService.pickFile] / [FilePickerService.pickFiles]；
/// `bytes` 为完整文件内容，`size` 为其字节数（与 `bytes.length` 一致）。
class FilePickerResult {
  const FilePickerResult({
    required this.name,
    required this.bytes,
  });

  /// 文件名（含扩展名，如 `report.pdf`）。
  final String name;

  /// 文件二进制内容。
  final Uint8List bytes;

  /// 文件大小（字节）。
  int get size => bytes.length;
}

/// 多选结果条目：文件名 + **惰性**读取字节。
///
/// 惰性是必须的：一次多选可能选中几十个大文件（单文件上限 20 MiB），
/// 若在选择器返回前就把全部字节读进内存，移动端极易被系统杀掉。
/// 调用方逐个 `await readBytes()`，用完即随上传释放。
class FilePickerEntry {
  const FilePickerEntry({required this.name, required this.readBytes});

  /// 文件名（含扩展名）。
  final String name;

  /// 读取完整文件内容。
  final Future<Uint8List> Function() readBytes;
}

/// 跨平台文件选择器抽象。
///
/// 生产实现 [PlatformFilePickerService] 走 `file_picker` 包；
/// 测试注入 [FakeFilePickerService] 或自定义 fake，避免碰平台通道。
abstract interface class FilePickerService {
  /// 弹出系统文件选择器，返回所选文件；用户取消返回 null。
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions});

  /// 弹出系统文件选择器（**可多选**），返回用户选中的全部文件。
  ///
  /// 用户取消返回空列表（不是 null）——「取消」与「选了 0 个」是同一语义。
  Future<List<FilePickerEntry>> pickFiles({List<String>? allowedExtensions});
}

/// 生产实现：包装 `file_picker` 包（^12 静态 API）。
class PlatformFilePickerService implements FilePickerService {
  const PlatformFilePickerService();

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    final file = await fp.FilePicker.pickFile(
      type: allowedExtensions == null ? fp.FileType.any : fp.FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (file == null || file.name.isEmpty) return null;
    final bytes = await file.readAsBytes();
    return FilePickerResult(name: file.name, bytes: bytes);
  }

  /// 多选：`file_picker` 的 `pickFiles` 在各平台实现里恒为多选语义
  /// （Windows `FOS_ALLOWMULTISELECT` / Android `EXTRA_ALLOW_MULTIPLE` /
  /// macOS `allowsMultipleSelection` / Linux `multiple=true`）。
  @override
  Future<List<FilePickerEntry>> pickFiles({
    List<String>? allowedExtensions,
  }) async {
    final files = await fp.FilePicker.pickFiles(
      type: allowedExtensions == null ? fp.FileType.any : fp.FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    final entries = <FilePickerEntry>[];
    for (final file in files) {
      if (file.name.isEmpty) continue;
      entries.add(
        FilePickerEntry(name: file.name, readBytes: file.readAsBytes),
      );
    }
    return entries;
  }
}

/// 测试用：固定返回一个文件（或抛错/返回 null 模拟取消/失败）。
class FakeFilePickerService implements FilePickerService {
  FakeFilePickerService({this.result, this.results, this.error});

  /// 要返回的结果；null 表示用户取消。
  final FilePickerResult? result;

  /// 多选时要返回的结果列表；null 时 [pickFiles] 回落到 [result]。
  final List<FilePickerResult>? results;

  /// 若设置，pickFile / pickFiles 直接抛此异常（模拟平台失败）。
  final Object? error;

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<List<FilePickerEntry>> pickFiles({
    List<String>? allowedExtensions,
  }) async {
    if (error != null) throw error!;
    final list = results;
    if (list != null) {
      return [
        for (final r in list)
          FilePickerEntry(name: r.name, readBytes: () async => r.bytes),
      ];
    }
    final single = result;
    if (single == null) return const <FilePickerEntry>[];
    return [
      FilePickerEntry(name: single.name, readBytes: () async => single.bytes),
    ];
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/hermes_dialog.dart';
import '../../../core/models/upload_response.dart';
import '../../../l10n/app_localizations.dart';
import '../../downloads/download_save_service.dart';
import '../chat_providers.dart';
import '../pending_attachments_provider.dart';

/// 媒体预览的「引用」按钮：把当前图像上传到**当前聊天**的附件（待发附件条）。
///
/// 语义与输入栏的「粘贴/上传附件」完全一致：
/// 上传 → 进 `pendingAttachmentsProvider(sessionId)` → 待发附件条出现缩略图
/// → 随下一条消息一起发出。**不直接发消息**（引用只是备料）。
///
/// 目标会话：优先灯箱自带的 [sessionId]（从该会话的附件进入时最准），
/// 回退「当前聊天会话」（[resolveCurrentChatSessionId] 走路由解析）—— 灯箱也可能从
/// 别的会话入口进入，此时引用应落到用户当前正在聊的会话。
class MediaQuoteButton extends ConsumerStatefulWidget {
  const MediaQuoteButton({
    super.key,
    required this.resolvedUrl,
    this.bytes,
    this.name,
    this.sessionId,
    this.foreground,
  });

  /// 媒体来源 URL（http(s) / data: URI / 本地文件路径）。
  final String? resolvedUrl;

  /// 已在内存里的字节（`Image.memory` 场景）。
  final Uint8List? bytes;

  /// 文件名（用于上传时的文件名；缺省时从 URL 推断）。
  final String? name;

  /// 灯箱自带的会话 id（优先作为引用目标）。
  final String? sessionId;

  /// 图标前景色（媒体查看器 = 白；文档阅读器 = 主题字色）。
  final Color? foreground;

  @override
  ConsumerState<MediaQuoteButton> createState() => _MediaQuoteButtonState();
}

class _MediaQuoteButtonState extends ConsumerState<MediaQuoteButton> {
  bool _quoting = false;

  /// 引用目标会话 id（灯箱自带优先，回退「当前聊天的路由」）。
  String? _targetSessionId() {
    final own = widget.sessionId;
    if (own != null && own.isNotEmpty) return own;
    final current = resolveCurrentChatSessionId(ref);
    if (current != null && current.isNotEmpty) return current;
    return null;
  }

  Future<void> _onPressed() async {
    if (_quoting) return;
    final l10n = AppLocalizations.of(context);
    final sessionId = _targetSessionId();
    if (sessionId == null) {
      await _showError(l10n.mediaQuoteFailed, l10n.mediaQuoteNoSession);
      return;
    }
    setState(() => _quoting = true);
    try {
      final bytes = await _resolveBytes();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('empty media bytes');
      }
      final filename = _fileName();
      final response = await ref.read(chatMediaUploaderProvider)(
        sessionId: sessionId,
        data: bytes,
        filename: filename,
      );
      if (!mounted) return;
      // 进待发附件条（与输入栏上传/粘贴同一条链路）⇒ 随下一条消息发出。
      ref
          .read(pendingAttachmentsProvider(sessionId).notifier)
          .add(
            PendingAttachment(
              name: response.filename ?? filename,
              path: response.path ?? filename,
              mime: response.mime ?? 'image/png',
              size: response.size ?? bytes.length,
              isImage: response.isImage ?? true,
              thumbnailData: bytes,
            ),
          );
      // 回到聊天页，让主人直接看到待发附件条。
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      await _showError(l10n.mediaQuoteFailed, error.toString());
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  /// 取回媒体字节：内存字节 → data: URI → 本地文件 → 远端 URL。
  Future<Uint8List?> _resolveBytes() async {
    final inline = widget.bytes;
    if (inline != null && inline.isNotEmpty) return inline;

    final url = widget.resolvedUrl;
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma == -1) return null;
      try {
        return base64Decode(url.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }

    if (!kIsWeb) {
      final file = File(url);
      if (file.existsSync()) {
        try {
          return await file.readAsBytes();
        } catch (_) {
          return null;
        }
      }
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ref.read(chatMediaBytesLoaderProvider)(url);
    }
    return null;
  }

  /// 上传文件名：优先显式名字 → URL 末段 → 兜底 `image.png`。
  String _fileName() {
    final explicit = widget.name?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return DownloadSaveService.sanitizeFileName(
        explicit,
        mimeType: 'image/png',
      );
    }
    final url = widget.resolvedUrl ?? '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final last = Uri.parse(url).pathSegments.lastOrNull;
      if (last != null && last.isNotEmpty) {
        return DownloadSaveService.sanitizeFileName(
          last,
          mimeType: 'image/png',
        );
      }
    }
    return 'image.png';
  }

  Future<void> _showError(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showHermesDialog<void>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(title),
      content: (_) => Text(message),
      actions: [
        HermesDialogAction(
          key: const ValueKey('media-quote-error-ok'),
          builder: (_) => Text(l10n.ok),
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = widget.foreground ?? CupertinoColors.white;
    final l10n = AppLocalizations.of(context);
    if (_quoting) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        // key 与按钮态保持一致：上传中/失败后仍是同一个可定位的控件。
        child: CupertinoActivityIndicator(
          key: const ValueKey('media-quote-button'),
          radius: 8,
          color: fg,
        ),
      );
    }
    return Tooltip(
      message: l10n.mediaQuoteToChat,
      child: CupertinoButton(
        key: const ValueKey('media-quote-button'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        onPressed: _onPressed,
        child: Icon(CupertinoIcons.quote_bubble, color: fg, size: 20),
      ),
    );
  }
}

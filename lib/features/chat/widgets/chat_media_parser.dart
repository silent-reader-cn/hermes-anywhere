import '../../../core/models/message_attachment.dart';

/// 聊天媒体标记解析器与 URL 解析工具。
///
/// 对齐 Hermes WebUI (static/ui.js) 的媒体标记处理逻辑：
/// 1. `MEDIA:<ref>` 标记解析为 Markdown 内联图片或媒体芯片链接；
/// 2. 裸 `file://` 引用解析为对应媒体 Markdown；
/// 3. 代码块及行内反引号内容受保护不被错误转换；
/// 4. 将本地路径或服务端相对路径解析为 `/api/media` 完整 URL。
class ChatMediaParser {
  const ChatMediaParser._();

  /// 媒体链接的 `title` 标记：`[文件名](url "hermes-media")`。
  ///
  /// [MediaLinkIconBuilder] 只给带这个标记的链接前置类型图标，普通网页链接
  /// 不带标记、走默认链接渲染（点击与换行行为一概不变）。
  ///
  /// 标记写在 `title` 而不是链接文案里，是为了让链接文案恒等于真实文件名：
  /// 下载文件名、附件预览页标题、`onTapLink` 的 linkText 都不再夹带装饰字符
  /// （历史上把类型写成 🎵/🎬/📎 emoji 前缀，一路漏到了
  /// `Downloads/📎 spec.pdf`）。
  static const String mediaLinkTitle = 'hermes-media';

  /// 匹配 `MEDIA:<ref>` 标记（非空白、非右括号或右中括号）。
  static final RegExp _mediaTokenRegex = RegExp(r'MEDIA:([^\s\)\]]+)');

  /// 匹配行首、空白或标点符号后的裸 `file://` 链接。
  static final RegExp _bareFileUriRegex = RegExp(
    r'(^|\s|[\p{P}\p{S}])(file:\/\/[^\s<>"'
    "'"
    r'\)\]]+)',
    unicode: true,
  );

  /// 匹配多行围栏代码块。
  static final RegExp _fencedBlockRegex = RegExp(
    r'(^|\n)[ ]{0,3}(`{3,})[^\n`]*\n[\s\S]*?\n[ ]{0,3}\2`*(?=\n|$)',
  );

  /// 匹配行内代码反引号跨度。
  static final RegExp _inlineCodeRegex = RegExp(r'`[^`\n]+`');

  /// 解析消息文本中的媒体标记并转换为标准 Markdown 语法。
  static String parseMediaMarkers(String text) {
    if (text.isEmpty) return text;
    if (!text.contains('MEDIA:') && !text.contains('file://')) {
      return text;
    }

    final codeStash = <String>[];

    // 1. 暂存多行代码块
    var processed = text.replaceAllMapped(_fencedBlockRegex, (match) {
      final matchedText = match.group(0)!;
      codeStash.add(matchedText);
      return '\x00FENCE_${codeStash.length - 1}\x00';
    });

    // 2. 暂存行内代码
    processed = processed.replaceAllMapped(_inlineCodeRegex, (match) {
      final matchedText = match.group(0)!;
      codeStash.add(matchedText);
      return '\x00CODE_${codeStash.length - 1}\x00';
    });

    // 3. 处理 MEDIA: 标记
    processed = processed.replaceAllMapped(_mediaTokenRegex, (match) {
      final rawRef = match.group(1)!;
      return _formatMediaMarkdown(rawRef);
    });

    // 4. 处理裸 file:// 链接
    processed = processed.replaceAllMapped(_bareFileUriRegex, (match) {
      final lead = match.group(1)!;
      final rawRef = match.group(2)!;
      return '$lead${_formatMediaMarkdown(rawRef)}';
    });

    // 5. 还原暂存代码块
    processed = processed.replaceAllMapped(
      RegExp(r'\x00(?:FENCE|CODE)_(\d+)\x00'),
      (match) {
        final index = int.tryParse(match.group(1) ?? '') ?? -1;
        if (index >= 0 && index < codeStash.length) {
          return codeStash[index];
        }
        return match.group(0)!;
      },
    );

    return processed;
  }

  static String _formatMediaMarkdown(String rawRef) {
    var ref = rawRef.trim();
    final trailingMatch = RegExp(r'[.,;:!?]+$').firstMatch(ref);
    var trailing = '';
    if (trailingMatch != null) {
      trailing = trailingMatch.group(0)!;
      ref = ref.substring(0, ref.length - trailing.length);
    }

    final displayName = _displayNameForRef(ref);
    final safeUrl = _safeMarkdownUrl(ref);
    final kind = MessageAttachment.mediaKindForName(ref);

    // 图片走 Markdown 图片语法（由 img 块级构建器渲染成媒体卡）；其余类型
    // 一律渲染成**纯文件名链接**，类型改由链接前的矢量图标表达
    // （见 [mediaLinkTitle] 与 MediaLinkIconBuilder）。
    //
    // 这里过去把类型写成 🎵 / 🎬 / 📎 emoji 前缀，两个问题：字形随平台不同
    // （Windows / Android / iOS 三套），且前缀属于"正文文案"，会一路漏进
    // 附件预览页标题与下载文件名（Downloads/📎 spec.pdf）。
    final String md;
    if (kind == MessageMediaKind.image) {
      md = '![$displayName]($safeUrl)';
    } else {
      md = '[$displayName]($safeUrl "$mediaLinkTitle")';
    }
    return '$md$trailing';
  }

  static String _displayNameForRef(String rawRef) {
    if (rawRef.startsWith('data:image/')) return 'image';
    var clean = rawRef.split('?').first.split('#').first;
    if (clean.startsWith('file://')) {
      try {
        clean = Uri.decodeFull(clean.substring(7));
      } catch (_) {
        clean = clean.substring(7);
      }
    }
    while (clean.endsWith('/') || clean.endsWith(r'\')) {
      clean = clean.substring(0, clean.length - 1);
    }
    final forwardSlash = clean.lastIndexOf('/');
    final backSlash = clean.lastIndexOf(r'\');
    final idx = forwardSlash > backSlash ? forwardSlash : backSlash;
    final name = idx == -1 ? clean : clean.substring(idx + 1);
    return name.isEmpty ? 'media' : name;
  }

  static String _safeMarkdownUrl(String rawRef) {
    return rawRef.replaceAll(r'\', '/');
  }
}

/// 媒体资源 URL 解析器。
class ChatMediaResolver {
  const ChatMediaResolver._();

  /// 将各种形式的媒体引用（http/https/data:image/file:///相对路径/绝对路径）解析为可访问的完整 URL。
  ///
  /// ⚠️ 入口先做一次**链接目标解码**：`package:markdown` 会把链接目标里的非 ASCII 字符
  /// 规范化成百分号转义（`树懒.xlsx` → `%E6%A0%91…xlsx`），而本函数随后要
  /// `Uri.encodeComponent` 拼 query——直接拼会把 `%E6` 编成 `%25E6`（**二次编码**），
  /// 服务端解一次码后拿到字面量 `%E6%A0%91…xlsx`，找不到文件 ⇒ **404 not found**。
  /// 实测：带中文名的引用（聊天 `onTapLink` 的 href、markdown 图片 URI）走这条链路必 404，
  /// 纯 ASCII 名则正常——这正是「只有那几份中文名文件打不开」的原因。
  static String resolveMediaUrl(
    String rawUrl, {
    String? baseUrl,
    String? sessionId,
  }) {
    final trimmed = _decodeLinkDestination(rawUrl.trim());
    if (trimmed.isEmpty) return '';

    // data:image/* 直接使用
    if (trimmed.startsWith('data:image/')) {
      return trimmed;
    }

    // http/https 网络地址
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    var path = trimmed;

    // file:// 解包
    if (path.startsWith('file://')) {
      try {
        final uri = Uri.parse(path);
        path = uri.toFilePath();
      } catch (_) {
        path = path.substring(7);
        try {
          path = Uri.decodeFull(path);
        } catch (_) {}
      }
      path = _normalizeDriveForm(path);
    }
    // 裸 MSYS 风格盘符路径（`/d/projects/...`，agent 在 bash 里常这么写）：
    // 不规整会被服务端按 cwd 解析成 `D:\d\projects\...` ⇒ 403。
    path = _normalizeDriveForm(path);

    final normalizedBase = _normalizeBaseUrl(baseUrl);
    if (normalizedBase.isEmpty) return path;

    // 已经是 api/media 相对路径
    if (path.startsWith('api/media') || path.startsWith('/api/media')) {
      final sep = path.startsWith('/') ? '' : '/';
      return '$normalizedBase$sep$path';
    }

    // 裸文件名（无目录分隔符）+ 有会话 id：走 `/api/file/raw`。
    //
    // 服务端口径（与 WebUI 前端一致）：`/api/file/raw` 先把 path 当会话
    // 工作区内的相对路径解析，找不到再落到**该会话的上传收件箱**
    // （`_session_attachment_dir(sid)`）；而 `/api/media` 只认绝对路径，
    // 收到裸文件名必然 404。历史消息里 `[Attached files:]` 常只留文件名
    // （或服务端只回 name），此时只有 file/raw 能取到字节。
    final hasSeparator = path.contains('/') || path.contains(r'\');
    // 绝对路径判定：`D:/…`、`D:\…`、UNC `//server/share`。
    final isAbsolute =
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        path.startsWith('/') ||
        path.startsWith(r'\');
    // 含分隔符但**不是绝对路径** ⇒ 工作区/会话相对路径。`/api/media` 只认绝对
    // 路径（相对路径会被服务端按 cwd 解析 → 403 Path not in allowed location），
    // 只有 `/api/file/raw` 会按「会话工作区 → 会话上传收件箱」两级解析。
    if (hasSeparator && !isAbsolute) {
      if (sessionId != null && sessionId.isNotEmpty) {
        return '$normalizedBase/api/file/raw'
            '?session_id=${Uri.encodeComponent(sessionId)}'
            '&path=${Uri.encodeComponent(path)}';
      }
      // 无会话 id 时退回旧行为（绝对根路径下的同名文件仍可能命中）。
      return '$normalizedBase/api/media?path=${Uri.encodeComponent(path)}';
    }
    if (!hasSeparator) {
      if (sessionId != null && sessionId.isNotEmpty) {
        return '$normalizedBase/api/file/raw'
            '?session_id=${Uri.encodeComponent(sessionId)}'
            '&path=${Uri.encodeComponent(path)}';
      }
      // 无会话 id 时退回旧行为（绝对根路径下的同名文件仍可能命中）。
      return '$normalizedBase/api/media?path=${Uri.encodeComponent(path)}';
    }

    // 本地文件路径或服务器相对路径 -> 拼接 /api/media
    final encodedPath = Uri.encodeComponent(path);
    var apiUrl = '$normalizedBase/api/media?path=$encodedPath';
    if (sessionId != null && sessionId.isNotEmpty) {
      apiUrl += '&session_id=${Uri.encodeComponent(sessionId)}';
    }
    return apiUrl;
  }

  /// 把 MSYS / Windows 两种非原生盘符形态规整成 `D:/...`。
  ///
  /// 处理三形态（都实测会导致 `/api/media` 403 —— 服务端会把它按 cwd 解析）：
  /// - `Uri.toFilePath()` 在 Windows 上把 `file:///d/projects/x` 变成 `\d\projects\x`；
  /// - 裸 `file:///d/…` 解包后的 `/d/projects/x`（MSYS 风格，agent 在 bash 里常写）；
  /// - 前导分隔符 + 单字母盘符的 `\d\projects\x`。
  /// 仅在这些形态命中时改写，其余原样返回。
  static String _normalizeDriveForm(String value) {
    final msys = RegExp(r'^/([A-Za-z])/(.*)$').firstMatch(value);
    if (msys != null) {
      return '${msys.group(1)!.toUpperCase()}:/${msys.group(2)!}';
    }
    final win = RegExp(r'^[\\/]([A-Za-z])[\\/](.*)$')
        .firstMatch(value);
    if (win != null) {
      final rest = win.group(2)!.replaceAll(r'\', '/');
      return '${win.group(1)!.toUpperCase()}:/$rest';
    }
    return value;
  }

  /// 安全解码 markdown 链接目标里的百分号转义。
  ///
  /// 只处理含 `%` 的串；完整 URL / data URI 原样透传（不动别人的 query）；
  /// 解码失败（文件名里真有非法转义的 `%`）时原样返回，**绝不抛异常**——
  /// 本函数直接接在点击、预览与下载链路上。
  static String _decodeLinkDestination(String value) {
    if (!value.contains('%')) return value;
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('data:')) {
      return value;
    }
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  static String _normalizeBaseUrl(String? baseUrl) {
    if (baseUrl == null) return '';
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }
}

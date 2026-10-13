import 'package:flutter/cupertino.dart';

import '../../../core/models/message_attachment.dart';

/// 媒体 / 附件类型图标（**唯一出口**）。
///
/// 同一个类型语义在聊天里出现多处 —— 正文里的媒体链接（[MediaLinkIconBuilder]
/// 前置图标）、用户气泡附件条、附件预览页 —— 一律从这里取图标，避免各处各画
/// 一套。历史上正文那处用的是 🎵 / 🎬 / 📎 emoji 字符，字形随平台不同
/// （Windows / Android / iOS 三套），且被当成正文文案漏进了下载文件名。
IconData mediaKindIcon(MessageMediaKind kind) {
  switch (kind) {
    case MessageMediaKind.image:
      return CupertinoIcons.photo;
    case MessageMediaKind.audio:
      return CupertinoIcons.music_note;
    case MessageMediaKind.video:
      return CupertinoIcons.film;
    case MessageMediaKind.document:
      return CupertinoIcons.doc_text;
    case MessageMediaKind.file:
      return CupertinoIcons.paperclip;
  }
}

/// 按引用串（路径 / URL / 文件名）判定类型并取图标。
IconData mediaKindIconForReference(String reference) =>
    mediaKindIcon(MessageAttachment.mediaKindForName(reference));

/// 正文媒体链接图标的尺寸（与 13pt 链接文字同高，细线风格）。
const double kMediaLinkIconSize = 13;

/// 图标与文件名之间的间距。
const double kMediaLinkIconGap = 4;

/// 正文媒体链接图标的稳定 key（测试锚点：断言"这个链接带类型图标"）。
const ValueKey<String> kMediaLinkIconKey = ValueKey<String>('media-link-icon');

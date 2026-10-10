import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 产品指令（2026-10-10）：**全应用移除蓝色焦点环** —— 源码级守卫。
///
/// 只删代码不设闸门，下次「顺手加回来」没人拦得住：本守卫扫 `lib/` 的全部 Dart 源，
/// 断言焦点环的**绘制入口与令牌**都不再出现。注释行豁免（记录「被删事实」的说明性注释
/// 应当留在源码里，例如 `chat_message_list.dart` 里那段根因记录）。
void main() {
  test('lib/ 不得再出现焦点环绘制入口与令牌', () {
    const needles = <String>[
      'onShowFocusHighlight', // 焦点环唯一的触发钩子（FocusableActionDetector）
      'kFocusRingWidth', // 焦点环线宽令牌（已随本次一并删除）
      'kFocusRingOffset', // 焦点环外扩令牌（已随本次一并删除）
    ];
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final needle in needles) {
          if (line.contains(needle)) {
            hits.add('${entity.path}:${i + 1} → $needle');
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          '焦点环已按产品指令全应用移除：lib/ 下不得再出现绘制入口（onShowFocusHighlight）'
          '或令牌（kFocusRingWidth / kFocusRingOffset）。实测命中：$hits',
    );
  });
}

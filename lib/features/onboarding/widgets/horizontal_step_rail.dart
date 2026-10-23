import 'package:flutter/cupertino.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';

/// 步骤点直径（圆内序号/对勾、连接线的垂直锚点都以它为基准）。
const double kStepRailDotSize = 26;

/// 连接线粗细。
const double kStepRailSegmentHeight = 2;

/// 圆点三态 + 失败态（供测试断言用；渲染由 [HorizontalStepRail] 决定）。
enum StepRailDotState {
  /// 未达：1.5px 灰边 + 灰字。
  pending,

  /// 当前：主色底 + 白字。
  current,

  /// 完成：绿底 + 白勾。
  done,

  /// 失败：红底 + 白叉（设计稿没给这一态，但失败必须能在轨上指认，
  /// 否则用户只看到「全灰」而不知道卡在哪一步）。
  failed,
}

/// 横向步骤条（设计稿 §5 R1-B，主人 2026-10-12 拍板）。
///
/// 形态照设计稿真值：26px 圆 + 圆间 2px 段线（弹性撑满）；圆下方标签行等分、
/// 11px 居中，当前步加粗并用主文字色、已完成步用绿、未达步用次级灰。
///
/// 只画「我在第几步」这一件事，不承载任何业务：向导主流程（5 步）与 Tailscale
/// 安装过程（3 步，设计稿 §6 T2）共用同一个组件 —— 主人追加要求是「安装过程
/// 也统一走横向步骤条，不另起垂直列表」。
class HorizontalStepRail extends StatelessWidget {
  /// 构造横向步骤条。
  ///
  /// [surfaceColor]：圆点未达态的兜底底色，必须等于**该条轨所在容器的底色**
  /// （页面底 / 卡片底），用来盖住下层连接线。缺省取页面底色。
  const HorizontalStepRail({
    super.key,
    required this.labels,
    required this.currentIndex,
    this.doneCount,
    this.failedIndex,
    this.surfaceColor,
  }) : assert(labels.length > 0);

  /// 各步短名（标签区只放短词，长说明挪进当前步的详情卡）。
  final List<String> labels;

  /// 当前步下标（0 基）。
  final int currentIndex;

  /// 已完成的**前导**步数，缺省 = [currentIndex]（常规：当前步之前的都已完成）。
  final int? doneCount;

  /// 失败步下标（为 null 表示没有失败步）。
  final int? failedIndex;

  /// 圆点未达态的兜底底色（= 轨所在容器底色，用来盖住背后的连接线）。
  final Color? surfaceColor;

  /// 单步的解析后状态（供测试与内部渲染共用同一判据）。
  static StepRailDotState resolveDotState(
    int index, {
    required int currentIndex,
    int? doneCount,
    int? failedIndex,
  }) {
    if (failedIndex == index) return StepRailDotState.failed;
    final done = doneCount ?? currentIndex;
    if (index < done) return StepRailDotState.done;
    if (index == currentIndex) return StepRailDotState.current;
    return StepRailDotState.pending;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    // 段线：设计稿 #E2E2E6 / 深色 #3A3A3C（token 里没有这一档，同页只有这一处）。
    final segmentColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFE2E2E6);
    final done = (doneCount ?? currentIndex).clamp(0, labels.length);
    // 一条横向网格：每步占等宽一列，圆点与标签都在**同一列内居中** ⇒ 标签
    // 天然落在各自圆点的正下方（旧实现把圆点摆在「段线之间」、标签另起一行
    // 按 1/N 等分，两套坐标不同源，首末两个标签必然偏出去）。
    // 连接线单独画在底层，从首圆圆心连到末圆圆心。
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = constraints.maxWidth / labels.length;
        return Stack(
          children: [
            Positioned(
              left: columnWidth / 2,
              right: columnWidth / 2,
              top: (kStepRailDotSize - kStepRailSegmentHeight) / 2,
              child: Container(
                height: kStepRailSegmentHeight,
                color: segmentColor,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Center(child: _buildDot(context, i, done)),
                      ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Text(
                          labels[i],
                          key: ValueKey<String>('step-rail-label-$i'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _labelStyle(context, i, done),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDot(BuildContext context, int index, int done) {
    final state = resolveDotState(
      index,
      currentIndex: currentIndex,
      doneCount: done,
      failedIndex: failedIndex,
    );
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    // 圆点的兜底底色 = 轨所在容器底色（页面底或卡片底）：只为盖住背后那条
    // 连接线，不参与状态语义。显式传 surfaceColor 时优先用它。
    final pageBackground =
        surfaceColor ??
        (isDark
            ? CupertinoColors.systemBackground.resolveFrom(context)
            : LightSurfaces.page);
    // 未达态描边：设计稿 #C8C8CC / 深色 #48484A。
    final pendingBorder = isDark
        ? const Color(0xFF48484A)
        : const Color(0xFFC8C8CC);
    // 主色（浅 #005FB8 / 深 #007AFF，设计稿 §3）。
    final primary = LightSurfaces.resolve(
      context,
      LightSurfaces.userDetail,
      dark: const Color(0xFF007AFF),
    );
    final green = statusGreenText.resolveFrom(context);
    final red = statusRedText.resolveFrom(context);

    Color? fill;
    Widget child;
    switch (state) {
      case StepRailDotState.done:
        fill = green;
        child = const Icon(
          CupertinoIcons.checkmark,
          size: 11,
          color: CupertinoColors.white,
        );
        break;
      case StepRailDotState.current:
        fill = primary;
        child = Text(
          '${index + 1}',
          style: const TextStyle(
            // TODO(type): 未进梯子（26px 圆内的 1 位序号，梯子无此档；本批照设计稿 12）
            fontSize: kFontCaption,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.white,
          ),
        );
        break;
      case StepRailDotState.failed:
        fill = red;
        child = const Icon(
          CupertinoIcons.xmark,
          size: 11,
          color: CupertinoColors.white,
        );
        break;
      case StepRailDotState.pending:
        child = Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: kFontCaption,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: const Color(0xFF8A8A8F),
            ),
          ),
        );
        break;
    }
    return Container(
      key: ValueKey<String>('step-rail-dot-$index'),
      width: kStepRailDotSize,
      height: kStepRailDotSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 未达态也必须带**不透明页底色**：连接线画在圆点下层，透明底会让线
        // 从圈里穿过去（主人 2026-10-23 指出）。完成/当前/失败本来就有实底。
        color: fill ?? pageBackground,
        shape: BoxShape.circle,
        border: fill == null ? Border.all(color: pendingBorder, width: 1.5) : null,
      ),
      child: child,
    );
  }

  TextStyle _labelStyle(BuildContext context, int index, int done) {
    final base = TextStyle(
      fontSize: kFontMicro,
      fontWeight: FontWeight.w400,
      color: LightSurfaces.resolve(
        context,
        LightSurfaces.textSecondary,
        dark: const Color(0xFF8A8A8F),
      ),
      height: 1.25,
    );
    if (index >= done && index != currentIndex) return base;
    if (index == currentIndex) {
      return base.copyWith(
        fontWeight: FontWeight.w600,
        // 主文字色（浅黑 / 深白）—— 动态色，按当前主题解析。
        color: CupertinoColors.label.resolveFrom(context),
      );
    }
    return base.copyWith(color: statusGreenText.resolveFrom(context));
  }
}

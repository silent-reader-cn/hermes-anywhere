/// 配对向导共用的度量、配色与基础部件（设计稿 §1 真值 + 真渲染测量）。
///
/// 三条硬约束（来自本仓既有规范，别在这里破例）：
/// 1. **字号只走令牌**（`app/theme/typography_tokens.dart`），本文件不写字号字面量；
///    M3 六格里的 26 是**装饰数值**（44×54 格子的几何配套，同 kFontTiny/kFontHeroMark
///    的处理），单列 [PairingMetrics.codeDigitSize] 并标 TODO(type)。
/// 2. **颜色只走令牌**：浅色取 `LightSurfaces` / `status_*`，深色取系统动态色，
///    且**必须**经 `resolveFrom`/`LightSurfaces.resolve` 解析后再用于自绘盒或内联
///    TextStyle（裸动态色不解析在暗黑下会退化）。
/// 3. 导航栏发丝线一律走 [NavBarHairline]（并给 `CupertinoNavigationBar` 传
///    `border: null`），卡片描边走 [Dividers] 语义分级。
library;

import 'package:flutter/cupertino.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';

import '../../../app/theme/divider_tokens.dart';
import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';

/// 配对向导的度量真值。
abstract final class PairingMetrics {
  /// 页面左右内边距。
  static const double pagePadding = 24;

  /// 导航栏高（发丝线另计 0.5，由 [NavBarHairline] 自带宽高）。
  static const double navHeight = 44;

  /// 导航栏下沿 → 页大标题顶部的留白。
  static const double topGap = 34;

  /// 页大标题 → 后续内容的留白。
  static const double titleToContent = 26;

  /// 卡片（白底 + 0.5 描边 + 圆角 10）。
  static const double cardRadius = 10;

  /// 卡片行最小行高。
  static const double cardRowMinHeight = 66;

  /// 卡片行内边距。
  static const double cardRowPaddingH = 14;
  static const double cardRowPaddingV = 13;

  /// 卡片行首图标列宽 / 图标尺寸。
  static const double cardIconWidth = 26;
  static const double cardIconSize = 20;

  /// M4 三步行的小图标尺寸。
  static const double stepIconSize = 17;

  /// 图标列与文字列间距。
  static const double cardIconGap = 12;

  /// 主按钮（高 55、圆角 8）。
  static const double buttonHeight = 55;
  static const double buttonRadius = 8;

  /// 小按钮（发现卡右侧「配对」）。
  static const double smallButtonHeight = 32;
  static const double smallButtonPaddingH = 14;

  /// M3 配对码六格。
  static const double codeCellWidth = 44;
  static const double codeCellHeight = 54;
  static const double codeCellRadius = 9;
  static const double codeCellGap = 8;

  /// M3 码格数字字号。
  ///
  /// TODO(type): 26 是**装饰数值**（44×54 格子的几何配套，设计稿 `codebox`），
  /// 不属内容排版梯子，故不进 `typography_tokens.dart`（同 kFontTiny 的处理）。
  static const double codeDigitSize = 26;

  /// M2 同心圆雷达：外圈 / 内圈 / 中心圆直径。
  static const double radarOuter = 160;
  static const double radarInner = 116;
  static const double radarCenter = 64;

  /// M2 雷达中心圆里的 wifi 图标尺寸。
  static const double radarIconSize = 26;

  /// M2 雷达区块高度（外圈直径 160 > 150，底部 10 由后续卡片覆盖，照设计稿几何）。
  static const double radarBlockHeight = 150;
}

/// 配对向导配色解析（全部经 `resolveFrom` / `LightSurfaces.resolve`）。
abstract final class PairingColors {
  /// 卡片/雷达中心圆的白色面（深色 = 系统二级分组背景 #1C1C1E）。
  static Color card(BuildContext context) => LightSurfaces.resolve(
    context,
    LightSurfaces.card,
    dark: CupertinoColors.secondarySystemGroupedBackground,
  );

  /// 卡片描边（L2 容器描边）。
  static Color cardBorder(BuildContext context) =>
      Dividers.containerOutline(context);

  /// 卡内行间线（L3 行间线）。
  static Color rowSeparator(BuildContext context) =>
      Dividers.rowSeparator(context);

  /// 主文字（浅色固定黑，深色取系统 label）。
  static Color label(BuildContext context) => LightSurfaces.resolve(
    context,
    CupertinoColors.black,
    dark: CupertinoColors.label,
  );

  /// 次级文字（#6A6A6F / 深色 secondaryText）。
  static Color secondary(BuildContext context) => LightSurfaces.resolve(
    context,
    LightSurfaces.textSecondary,
    dark: secondaryText,
  );

  /// 主色（#005FB8 / 深色系统蓝 #007AFF）。
  static Color primary(BuildContext context) => LightSurfaces.resolve(
    context,
    LightSurfaces.userDetail,
    dark: CupertinoColors.systemBlue,
  );

  /// 行尾 chevron（#C7C7CC / 深色 #48484A）。
  static Color chevron(BuildContext context) => LightSurfaces.resolve(
    context,
    const Color(0xFFC7C7CC),
    dark: const Color(0xFF48484A),
  );

  /// M3 码格底色 rgba(120,120,128,.12) / 深色 .24。
  static Color codeFill(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.light
      ? const Color.fromRGBO(120, 120, 128, 0.12)
      : const Color.fromRGBO(120, 120, 128, 0.24);

  /// M2 雷达外/内圈描边（浅色 #E0E0E4 / #E6E6EA，深色取系统 separator）。
  static Color radarRing(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.light
      ? const Color(0xFFE0E0E4)
      : CupertinoColors.separator.resolveFrom(context);

  /// 成功（M4 三步行图标）。
  static Color success(BuildContext context) => statusGreenText.resolveFrom(context);

  /// 警示 / 主色文字（配对码失效提示备用）。
  static Color warning(BuildContext context) => statusOrangeText.resolveFrom(context);

  /// 错误文案色。
  static Color danger(BuildContext context) => statusRedText.resolveFrom(context);

  /// 禁用态动作文字（v1 的「改用扫一扫」占位）。
  static Color disabledAction(BuildContext context) =>
      statusGreyText.resolveFrom(context);

  /// 按钮上的白字（浅深浅三态同值：主色底白字）。
  static const Color onPrimary = CupertinoColors.white;
}

/// 页首区：34 留白 → 页大标题（28 粗）→ 9 → 副文（12 次级）。
class PairingPageIntro extends StatelessWidget {
  const PairingPageIntro({
    super.key,
    required this.title,
    required this.subtitle,
  });

  /// 页大标题文案。
  final String title;

  /// 副文文案。
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PairingMetrics.pagePadding,
        PairingMetrics.topGap,
        PairingMetrics.pagePadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: kFontPageTitleXl,
              fontWeight: FontWeight.bold,
              height: 1.22,
              letterSpacing: 0.1,
              color: PairingColors.label(context),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: kFontCaption,
              height: 1.5,
              color: PairingColors.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 白底卡片：0.5 描边 + 圆角 10，行之间自动插入 0.5 发丝行间线。
class PairingCard extends StatelessWidget {
  const PairingCard({super.key, required this.children});

  /// 卡片内的行（行间线由本件插入）。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          SizedBox(
            height: Dividers.hairlineWidth,
            child: ColoredBox(color: PairingColors.rowSeparator(context)),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: PairingColors.card(context),
        border: Border.all(
          color: PairingColors.cardBorder(context),
          width: Dividers.hairlineWidth,
        ),
        borderRadius: BorderRadius.circular(PairingMetrics.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// 卡片行：左图标（26 列宽）+ 标题 15 粗 + 副行 12 灰 + 右侧槽位（chevron / 小按钮）。
class PairingOptionRow extends StatelessWidget {
  const PairingOptionRow({
    super.key,
    required this.icon,
    required this.title,
    this.description = '',
    this.trailing,
    this.iconColor,
    this.iconSize = PairingMetrics.cardIconSize,
    this.onTap,
  });

  /// 行首图标。
  final IconData icon;

  /// 行标题。
  final String title;

  /// 行副行（空则不渲染）。
  final String description;

  /// 行尾部件（chevron / 小按钮）。
  final Widget? trailing;

  /// 行首图标色（缺省跟随主文字，同设计稿 M1/M2 卡片）。
  final Color? iconColor;

  /// 行首图标尺寸。
  final double iconSize;

  /// 整行点击。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(
        minHeight: PairingMetrics.cardRowMinHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PairingMetrics.cardRowPaddingH,
        vertical: PairingMetrics.cardRowPaddingV,
      ),
      child: Row(
        children: [
          SizedBox(
            width: PairingMetrics.cardIconWidth,
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor ?? PairingColors.label(context),
            ),
          ),
          const SizedBox(width: PairingMetrics.cardIconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: kFontItemTitle,
                    fontWeight: FontWeight.w600,
                    color: PairingColors.label(context),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: kFontCaption,
                      height: 1.35,
                      color: PairingColors.secondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: PairingMetrics.cardIconGap),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

/// 行尾 chevron（浅色 #C7C7CC / 深色 #48484A）。
class PairingChevron extends StatelessWidget {
  const PairingChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.chevron_forward,
    size: 15,
    color: PairingColors.chevron(context),
  );
}

/// 主按钮（高 55、圆角 8、主色底白字）与其次级/幽灵变体。
///
/// [onPressed] 为 null 即禁用（幽灵变体呈灰字，用于 v1 的「改用扫一扫」占位）。
class PairingActionButton extends StatelessWidget {
  const PairingActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.ghost = false,
  });

  /// 按钮文案。
  final String label;

  /// 点击回调（null = 禁用）。
  final VoidCallback? onPressed;

  /// 文案前的小图标。
  final IconData? icon;

  /// 加载中（转圈 + 不可重复点击）。
  final bool busy;

  /// 幽灵变体（透明底蓝字，用于次级动作）。
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final Color labelColor;
    if (ghost) {
      labelColor = enabled
          ? PairingColors.primary(context)
          : PairingColors.disabledAction(context);
    } else {
      labelColor = PairingColors.onPrimary;
    }
    final child = busy
        ? CupertinoActivityIndicator(
            color: ghost
                ? PairingColors.primary(context)
                : PairingColors.secondary(context),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: labelColor),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: kFontButton,
                  fontWeight: ghost ? FontWeight.w400 : FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ],
          );
    return SizedBox(
      height: PairingMetrics.buttonHeight,
      width: double.infinity,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: ghost ? null : PairingColors.primary(context),
        borderRadius: BorderRadius.circular(PairingMetrics.buttonRadius),
        onPressed: enabled ? onPressed : null,
        child: child,
      ),
    );
  }
}

/// 小按钮（发现卡右侧「配对」：高 32、圆角 8、主色底白字）。
class PairingSmallButton extends StatelessWidget {
  const PairingSmallButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  /// 按钮文案。
  final String label;

  /// 点击回调。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PairingMetrics.smallButtonHeight,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(
          horizontal: PairingMetrics.smallButtonPaddingH,
        ),
        minimumSize: const Size(0, PairingMetrics.smallButtonHeight),
        color: PairingColors.primary(context),
        borderRadius: BorderRadius.circular(PairingMetrics.buttonRadius),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: kFontButton,
            fontWeight: FontWeight.w600,
            color: PairingColors.onPrimary,
          ),
        ),
      ),
    );
  }
}

/// 蓝色文字链接（居中，动作语义 → 按钮字号档）。
class PairingTextLink extends StatelessWidget {
  const PairingTextLink({super.key, required this.label, required this.onTap});

  /// 链接文案。
  final String label;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: kFontButton,
            color: PairingColors.primary(context),
          ),
        ),
      ),
    );
  }
}

/// 微文案（11 次级，行高 1.55），可选居中。
class PairingMicroText extends StatelessWidget {
  const PairingMicroText(
    this.text, {
    super.key,
    this.align = TextAlign.left,
    this.color,
    this.bold = false,
  });

  /// 文案。
  final String text;

  /// 对齐方式。
  final TextAlign align;

  /// 覆盖色（缺省次级灰）。
  final Color? color;

  /// 加粗（「没找到？」小标题）。
  final bool bold;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: TextStyle(
      fontSize: kFontMicro,
      height: 1.55,
      fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
      color: color ?? (bold ? PairingColors.label(context) : PairingColors.secondary(context)),
    ),
  );
}

// 浅色面令牌：固定不透明 sRGB；仅由选择接入的页面消费，不改全局主题。
//
// ── 页面底色可调（主人 2026-10-06 拍板）────────────────────────────────────
// 页底色 [page] 与其配套描边 [cardBorder] / [divider] 由用户在
// 设置 → 外观 → 页面底色 中选择（预设六档 + 自定义），默认「中性同深」
// （#F2F2F2，去掉了原 iOS 分组灰 #F2F2F7 的蓝味）。
//
// 实现要点：这三个令牌是 **getter 而非 const**，值读自本类的全局可变态，由
// PageSurfaceController 写入、`app.dart` 依状态变化重建整棵树生效。之所以
// 不改 250 处调用点：全仓引用这三个令牌的 const 上下文极少，getter 化后
// 调用侧写法一字不动（规格见 docs/specs/page-surface-selection.md）。
//
// ── 对比度（对白卡 #FFFFFF）──────────────────────────────────────────────
// 描边不参与正文 AA 判级（装饰层级），但需要「看得见」：改造前后统一按
// **对白卡 1.543866:1**（= 原 #CCD0DA 实测值）派生，只换色相不换可见度。
// 选「iOS 分组灰」档时描边回到原设计值 #CCD0DA（冷灰紫），保证该档能
// 完整还原改造前像素。
//
// 其余令牌仍为 const，取值与改造前逐字节一致：
// card          #FFFFFF   对 page 1.119500  对 card 1.000000
// textSecondary #6A6A6F   对 page 4.838553  对 card 5.379116
// selection     #E0ECFF   对 page 1.068576  对 card 1.192393
// tertiaryLabel/placeholderText 合成到 page/card 后仅 1.683235/1.725396，
// 可读占位文案使用 placeholder，不通过降低透明度制造文字层级。
//
// v3（2026-09-13 主人拍板「分栏线/区域线提到同档拉平」）：divider 由
// #C6C6C8 改为 cardBorder 别名 —— 原 divider 比描边更深且为中性灰，与冷灰紫
// 描边色相分家，产生「结构线比卡片边界散」的观感；统一后全页线族/描边
// 同一族同一档。
// v4（2026-09-27 主人拍板 L2 选中态）：新增 selectedSurface / hoverSurface /
// currentStroke / selectionForeground —— 前者们是**半透明叠加层**，不参与上面的
// 不透明对比度表（合成值见各令牌 doc）。出处均为设计稿
// `sketches/selection-light-mode-proposal.html` §3/§4（L2 规格表）。
// v5（2026-10-06 主人拍板页面底色可调）：page / cardBorder / divider 改为
// 可注入 getter，默认档由 #F2F2F7 改为 #F2F2F2。

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// 浅色面与文字令牌；深色由调用方传入原有颜色，逐字节保留。
abstract final class LightSurfaces {
  // ───────────────────────────────────────────────────────────────────────
  // 可调页底色（用户选择）
  // ───────────────────────────────────────────────────────────────────────

  /// 改造前的 iOS 分组灰 —— 即主人反馈「灰蓝灰蓝」的原值。仅作预设保留。
  static const Color kLegacyIosPage = Color(0xFFF2F2F7);

  /// iOS 分组灰档的配套描边（原设计值，冷灰紫）。
  static const Color kLegacyIosBorder = Color(0xFFCCD0DA);

  /// 默认浅色页底色（中性同深）。
  static const Color kDefaultPage = Color(0xFFF2F2F2);

  /// 描边对白卡的对比度基准（= 原 [kLegacyIosBorder] 实测值）。
  static const double kBorderContrastVsWhite = 1.543866;

  // ───────────────────────────────────────────────────────────────────────
  // 侧栏槽（v6，2026-10-14 主人拍板）
  // ───────────────────────────────────────────────────────────────────────
  // 宽屏左侧栏「槽」= 外壳面，比右侧内容区（页底色）抬一个感知台阶，解决
  // 「整窗同底 ⇒ 两栏分区只剩一条 10% 发丝线」的分界弱问题。台阶按 **ΔL*
  // （感知明度）** 定档而非固定 RGB 差：预设六档 + 任意自定义页底色都能得到
  // 同一种「看得出但不脏」的层次。
  //
  // 三个不变量（[sidebarFor] 里夹紧）：
  // ① 深色 = 抬升 ΔL* 10（#000000 → #1B1B1B，即主人拍板的那档观感）；
  //    抬不动（余量 < [kSidebarMinStep]）则反向下沉，避免退化成「无差」。
  // ② 槽不得撞侧栏内最亮的填充（暗色 hover/选中/底部芯片 #2C2C2E）：必须留
  //    [kSidebarFillGap] 的 ΔL* 间隔，否则芯片糊在槽里。
  // ③ 浅色 = 下沉 ΔL* 4（#F2F2F2 → #E6E6E6）：页底色本身要给白卡当衬底，槽再亮
  //    就压平卡片；下限 [kSidebarLightFloor]。实测白卡对槽 1.248:1 > 对页底色
  //    1.119:1 ⇒ 卡片反而更立得住。

  /// 深色槽的感知明度台阶（ΔL*，抬升）。
  static const double kSidebarStepDark = 10.0;

  /// 浅色槽的感知明度台阶（ΔL*，下沉）。
  static const double kSidebarStepLight = -4.0;

  /// 正向台阶下限：抬升余量不足时反向下沉同值，避免槽与页底色同色。
  static const double kSidebarMinStep = 4.0;

  /// 槽与侧栏内最亮填充之间必须保住的最小 ΔL* 间隔。
  static const double kSidebarFillGap = 6.0;

  /// 侧栏内最亮填充（暗色 hover / 选中 / 底部芯片）。
  static const Color kSidebarBrightestFill = Color(0xFF2C2C2E);

  /// 浅色槽下限（再深就读作凹陷的灰块）。
  static const Color kSidebarLightFloor = Color(0xFFE0E0E0);

  /// 未覆盖深色页底色时槽的普通档（= sidebarFor(#000000, dark: true) 实算值）。
  static const Color kDefaultDarkSidebar = Color(0xFF1B1B1B);

  /// 未覆盖深色页底色时槽的高对比度档（台阶再加大一档）。
  static const Color kDefaultDarkSidebarHighContrast = Color(0xFF262626);

  /// 生效中的浅色页底色（默认「中性同深」；由用户选择覆盖）。
  static Color _page = kDefaultPage;

  /// 生效中的配套描边（默认按 [_page] 派生，此处与 [resetUserSurface]
  /// 保持同一来源，避免两处各写一个值而漂移）。
  static Color _border = _deriveBorder(kDefaultPage);

  /// 生效中的深色页底色；null = 不覆盖，沿用 Cupertino 原生分组背景。
  static Color? _darkPage;

  /// 侧栏槽是否跟随页底色派生（默认 true；用户「自定义」时置 false）。
  static bool _sidebarFollowsPage = true;

  /// 自定义浅色槽；仅在 [_sidebarFollowsPage] 为 false 时生效。
  static Color? _lightSidebar;

  /// 自定义深色槽；仅在 [_sidebarFollowsPage] 为 false 时生效。
  static Color? _darkSidebar;

  /// 页面与会话侧边栏列表区的分组背景。
  static Color get page => _page;

  /// 分组卡片轮廓（0.5–1 逻辑像素 hairline），随 [page] 派生。
  static Color get cardBorder => _border;

  /// 结构线与卡片描边同值同族（v3 拍板），随 [page] 派生。
  static Color get divider => _border;

  /// 深色模式的页底色。
  ///
  /// 用户未覆盖时返回 Cupertino 原生分组背景（`#1C1C1E`），**保留其动态色
  /// 语义**（高对比度模式下有专属变体），因此默认路径与改造前逐像素一致。
  static Color get darkPage =>
      _darkPage ?? CupertinoColors.systemGroupedBackground;

  /// 宽屏左侧栏「槽」底（浅色态）。
  ///
  /// [_sidebarFollowsPage] 是**权威开关**：「自动」档一律由 [page] 派生（此时即使
  /// 传了自定义值也不生效 —— 与 `PageSurfaceState.lightSidebar` 在自动档返回 null
  /// 同源）；「自定义」档才回用户值。
  static Color get sidebar {
    if (!_sidebarFollowsPage) {
      final custom = _lightSidebar;
      if (custom != null) return custom;
    }
    return sidebarFor(_page, dark: false);
  }

  /// 宽屏左侧栏「槽」底（深色态）。
  ///
  /// 未覆盖深色页底色时返回 [CupertinoDynamicColor]，保留动态色语义（高对比度
  /// 档再抬一档）—— 与 [darkPage] 的既有口径一致，默认路径不丢语义。
  static Color get darkSidebar {
    if (!_sidebarFollowsPage) {
      final custom = _darkSidebar;
      if (custom != null) return custom;
    }
    final page = _darkPage;
    if (page != null) return sidebarFor(page, dark: true);
    // elevated 四档与普通档同值：槽底不落在抬升面（弹层/浮卡）上，保留字段
    // 只为满足 CupertinoDynamicColor 的构造契约。
    return const CupertinoDynamicColor(
      color: kDefaultDarkSidebar,
      darkColor: kDefaultDarkSidebar,
      highContrastColor: kDefaultDarkSidebar,
      darkHighContrastColor: kDefaultDarkSidebarHighContrast,
      elevatedColor: kDefaultDarkSidebar,
      darkElevatedColor: kDefaultDarkSidebar,
      highContrastElevatedColor: kDefaultDarkSidebar,
      darkHighContrastElevatedColor: kDefaultDarkSidebarHighContrast,
    );
  }

  /// 由页底色派生侧栏槽（**纯函数**，供设置页预览草稿色用 —— 草稿尚未写入
  /// 全局令牌，不能读 [sidebar] / [darkSidebar]）。
  ///
  /// [dark] 走「抬升优先、抬不动则下沉」；浅色走「下沉、不破下限」。
  static Color sidebarFor(Color page, {required bool dark}) {
    final pageL = _lstar(page);
    if (!dark) {
      final target = math.max(
        pageL + kSidebarStepLight,
        _lstar(kSidebarLightFloor),
      );
      return _atLstar(page, target);
    }
    final cap = _lstar(kSidebarBrightestFill) - kSidebarFillGap;
    var target = math.min(pageL + kSidebarStepDark, cap);
    if (target - pageL < kSidebarMinStep) target = pageL - kSidebarMinStep;
    return _atLstar(page, target);
  }

  /// 保持色相、饱和度降到五成（≤0.20）、二分到目标感知明度 L* 的色。
  ///
  /// 「大面比描边更不该抢色」：槽的饱和度折半（描边见 [_deriveBorder] 取六成）。
  static Color _atLstar(Color base, double targetL) {
    final hsl = HSLColor.fromColor(base);
    final saturation = (hsl.saturation * 0.5).clamp(0.0, 0.20);
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 32; i++) {
      final mid = (lo + hi) / 2;
      final candidate = HSLColor.fromAHSL(1, hsl.hue, saturation, mid).toColor();
      if (_lstar(candidate) < targetL) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return HSLColor.fromAHSL(1, hsl.hue, saturation, lo).toColor();
  }

  /// CIE L*（感知明度：0 = 黑，100 = 白）。
  static double _lstar(Color color) {
    final y = _relativeLuminance(color);
    return y > 0.008856 ? 116 * math.pow(y, 1 / 3) - 16 : 903.3 * y;
  }

  /// 用户是否覆盖过浅色页底色（默认档 == 未覆盖；供 `app.dart` 决定全局
  /// scaffold 底色是否跟随，避免默认路径丢动态色语义）。
  static bool get hasLightOverride => _page.toARGB32() != kDefaultPage.toARGB32();

  /// 用户是否覆盖过深色页底色。
  static bool get hasDarkOverride => _darkPage != null;

  /// 用户是否把侧栏槽切到了「自定义」档（= 不再跟随页底色派生）。
  static bool get hasSidebarOverride => !_sidebarFollowsPage;

  /// 写入用户选择（**唯一入口**，由 PageSurfaceController 调用）。
  ///
  /// [dark] 传 null 表示深色不覆盖。配套描边由 [light] 派生：选 iOS 分组灰档
  /// 时回到原设计值，其余按对白卡对比度基准派生。
  static void applyUserSurface({
    required Color light,
    Color? dark,
    bool sidebarFollowsPage = true,
    Color? lightSidebar,
    Color? darkSidebar,
  }) {
    _page = light;
    _darkPage = dark;
    _border = _deriveBorder(light);
    _sidebarFollowsPage = sidebarFollowsPage;
    _lightSidebar = lightSidebar;
    _darkSidebar = darkSidebar;
  }

  /// 还原到默认（供测试 tearDown 与「恢复默认」共用）。
  static void resetUserSurface() {
    _page = kDefaultPage;
    _border = _deriveBorder(kDefaultPage);
    _darkPage = null;
    _sidebarFollowsPage = true;
    _lightSidebar = null;
    _darkSidebar = null;
  }

  /// 由页底色派生配套描边：色相随底色（饱和度降到六成，描边不该比底色更
  /// 彩），明度二分到「对白卡 [kBorderContrastVsWhite]」。
  ///
  /// 公开版本 [borderFor] 供设置页选择器**预览草稿色**用（草稿尚未写入全局
  /// 令牌，不能读 [cardBorder]）。
  static Color borderFor(Color page) => _deriveBorder(page);

  static Color _deriveBorder(Color page) {
    // iOS 分组灰档：还原原设计值，保证该档逐像素还原改造前。
    if (page.toARGB32() == kLegacyIosPage.toARGB32()) return kLegacyIosBorder;
    final hsl = HSLColor.fromColor(page);
    final saturation = (hsl.saturation * 0.6).clamp(0.0, 0.20);
    var lo = 0.0;
    var hi = hsl.lightness;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final candidate = HSLColor.fromAHSL(1, hsl.hue, saturation, mid).toColor();
      if (_contrastVsWhite(candidate) > kBorderContrastVsWhite) {
        lo = mid; // 太暗 → 往亮的一侧收敛
      } else {
        hi = mid;
      }
    }
    return HSLColor.fromAHSL(1, hsl.hue, saturation, lo).toColor();
  }

  /// WCAG 相对亮度对比度（对纯白）。
  static double _contrastVsWhite(Color color) =>
      (1.0 + 0.05) / (_relativeLuminance(color) + 0.05);

  /// WCAG 相对亮度（0 = 黑，1 = 白）。
  static double _relativeLuminance(Color color) {
    final argb = color.toARGB32();
    double channel(int v) {
      final s = v / 255.0;
      return s <= 0.04045
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4) as double;
    }

    return 0.2126 * channel((argb >> 16) & 0xFF) +
        0.7152 * channel((argb >> 8) & 0xFF) +
        0.0722 * channel(argb & 0xFF);
  }

  // ───────────────────────────────────────────────────────────────────────
  // 固定令牌（不随页面底色变化）
  // ───────────────────────────────────────────────────────────────────────

  /// 分组卡片、输入框及普通浮层的白色面。
  static const Color card = Color(0xFFFFFFFF);

  /// 次级文字和需要辨认的图标；页面、白卡、选中面均满足正文 AA。
  static const Color textSecondary = Color(0xFF6A6A6F);

  /// 可读占位文案，与次级文字共用对比度下限。
  static const Color placeholder = textSecondary;

  /// 旧浅蓝选中面（#E0ECFF，≈ primary 12% 叠白）。
  ///
  /// L2 起**不再用于「选中行」**（改由 [selectedSurface] 承担）：主人判定该色
  /// 「在白纸上贴了张便利贴」。剩余用途是文本选区底（`DefaultSelectionStyle`
  /// 的 selectionColor）与诊断级别色相，本令牌值保持不变以维持那些场景原样。
  static const Color selection = Color(0xFFE0ECFF);

  /// 选中态底（L2 浅色规格）。半透明中性灰、零色相，叠加在白卡与 [page] 上
  /// 都立得住（合成后：白卡 ≈ #E9E9EB、[page] ≈ #DEDEE4）。
  /// 出处：`sketches/selection-light-mode-proposal.html` §4「选中 · 底 rgba(120,120,128,.16)」。
  static const Color selectedSurface = Color.fromRGBO(120, 120, 128, 0.16);

  /// 悬停态底（L2 浅色规格）：比 [selectedSurface] 淡一档、同样不带色相，
  /// 扫列表时不会「闪蓝」。与选中的差别 = 有蓝字 vs 无蓝字。
  /// 出处：同设计稿 §3「hover · 底 rgba(120,120,128,.10)」。
  static const Color hoverSurface = Color.fromRGBO(120, 120, 128, 0.10);

  /// 「当前」持久态内描边（1px，圆角内），叠在 [selectedSurface] 之上，
  /// 用于侧栏「当前会话」与文件树「当前文件」，比选中「更停得住」。
  /// 出处：同设计稿 §4「当前 · 内描边 rgba(0,95,184,.28)」。
  static const Color currentStroke = Color.fromRGBO(0, 95, 184, 0.28);

  /// 选中态前景（文字**和**图标）。
  ///
  /// 与 [userDetail] **同值同源**（#005FB8，浅色正文 AA），此处按语义另设
  /// 别名，避免选中态语义挂在「用户气泡详情」令牌上。
  static const Color selectionForeground = userDetail;

  /// 会话行按下面，与白色静止行形成可见差异。
  static Color get pressed => page;

  /// Success notices and clarification answers; secondary text 5.036250:1.
  static const Color tintGreen = Color(0xFFF0FAF2);

  /// Approval/warning surface; statusOrangeText 4.790918:1.
  static const Color tintWarning = Color(0xFFFFF4E8);

  /// Error surface; keeps the status label independent of the page beneath.
  static const Color tintError = Color(0xFFFFF4F3);

  /// Clarification surface; secondary text 4.855495:1.
  static const Color tintClarification = Color(0xFFF3F2FF);

  /// Local code/link/attachment surface inside the unchanged brand-blue bubble.
  /// White content reaches 6.308159:1; the main bubble stays #007AFF.
  static const Color userDetail = Color(0xFF005FB8);

  /// Action-sheet blue from the existing high-contrast status palette.
  /// Keeps native translucent pressed rows readable without changing their skin.
  static const Color menuAction = Color(0xFF004A94);

  /// 浅色使用固定 [light]，深色显式解析调用点原有的 [dark] 语义色。
  ///
  /// 保留深色高对比度及 elevated 分支；原来直接绘制的未解析颜色应传
  /// 原绘制值（普通 [Color]），防止此次浅色接入顺带改变深色像素。
  static Color resolve(
    BuildContext context,
    Color light, {
    required Color dark,
  }) {
    return CupertinoTheme.brightnessOf(context) == Brightness.light
        ? light
        : CupertinoDynamicColor.resolve(dark, context);
  }
}

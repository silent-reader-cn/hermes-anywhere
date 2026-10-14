import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart' show kAdaptiveBreakpoint;
import 'package:hermes_ui/app/theme/light_surfaces.dart';
import 'package:hermes_ui/app/theme/page_surface.dart';
import 'package:hermes_ui/app/theme/typography_tokens.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

/// 浅色预设的展示名（l10n 真值，不写死双语表）。
String lightPresetLabel(AppLocalizations l10n, PageSurfacePreset preset) =>
    switch (preset) {
      PageSurfacePreset.iosGrouped => l10n.surfacePresetIosGrouped,
      PageSurfacePreset.neutral => l10n.surfacePresetNeutral,
      PageSurfacePreset.neutralDeep => l10n.surfacePresetNeutralDeep,
      PageSurfacePreset.neutralBright => l10n.surfacePresetNeutralBright,
      PageSurfacePreset.warmNeutral => l10n.surfacePresetWarmNeutral,
      PageSurfacePreset.warmPaper => l10n.surfacePresetWarmPaper,
      PageSurfacePreset.custom => l10n.surfaceCustom,
    };

/// 深色预设的展示名。
String darkPresetLabel(AppLocalizations l10n, DarkSurfacePreset preset) =>
    switch (preset) {
      DarkSurfacePreset.system => l10n.surfaceDarkSystem,
      DarkSurfacePreset.neutral => l10n.surfaceDarkNeutral,
      DarkSurfacePreset.deeper => l10n.surfaceDarkDeeper,
      DarkSurfacePreset.warm => l10n.surfaceDarkWarm,
      DarkSurfacePreset.custom => l10n.surfaceCustom,
    };

/// 打开「页面底色」选择器（设置 → 外观）。
///
/// 承载形态：宽屏（≥ [kAdaptiveBreakpoint]）居中卡片，窄屏贴底 sheet。
///
/// **草稿态是硬需求**：提交会把新值写进 [LightSurfaces] 全局令牌，而
/// `app.dart` 依状态换 key 重建整棵树 —— 弹层正挂在被重建的 Navigator 上，
/// 边选边提交会立刻把弹层销毁。因此选择器内所有改动先落本地草稿（并实时
/// 预览），点「应用」才一次性写入；用户可连续试色。
Future<void> showPageSurfacePicker(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => _PageSurfaceSheet(wide: wide),
  );
}

class _PageSurfaceSheet extends ConsumerStatefulWidget {
  const _PageSurfaceSheet({required this.wide});

  final bool wide;

  @override
  ConsumerState<_PageSurfaceSheet> createState() => _PageSurfaceSheetState();
}

class _PageSurfaceSheetState extends ConsumerState<_PageSurfaceSheet> {
  late PageSurfacePreset _lightPreset;
  late DarkSurfacePreset _darkPreset;
  late final TextEditingController _lightCtrl;
  late final TextEditingController _darkCtrl;
  late bool _sidebarFollowsPage;

  /// 明暗两态各有一个槽输入框，界面上只显示当前态那一个。
  ///
  /// 不共用单框：槽是分态生效的，浅色态填的值若被当成深色槽落盘，切到深色
  /// 会得到一个与页底色无关的灰。
  late final TextEditingController _lightSidebarCtrl;
  late final TextEditingController _darkSidebarCtrl;

  @override
  void initState() {
    super.initState();
    final current = ref.read(pageSurfaceProvider);
    _lightPreset = current.lightPreset;
    _darkPreset = current.darkPreset;
    _lightCtrl = TextEditingController(text: current.lightCustomHex);
    _darkCtrl = TextEditingController(text: current.darkCustomHex);
    _sidebarFollowsPage = current.sidebarFollowsPage;
    _lightSidebarCtrl = TextEditingController(
      text: current.lightSidebarCustomHex,
    );
    _darkSidebarCtrl = TextEditingController(
      text: current.darkSidebarCustomHex,
    );
  }

  @override
  void dispose() {
    _lightCtrl.dispose();
    _darkCtrl.dispose();
    _lightSidebarCtrl.dispose();
    _darkSidebarCtrl.dispose();
    super.dispose();
  }

  /// 草稿的浅色页底色（自定义且非法时回落到默认档，与落码口径一致）。
  Color get _draftLightPage => _lightPreset.isCustom
      ? (parseHexColor(_lightCtrl.text) ?? PageSurfacePreset.neutral.color!)
      : _lightPreset.color!;

  /// 草稿的深色页底色；null = 跟随系统。
  Color? get _draftDarkPage {
    if (_darkPreset.followsSystem) return null;
    if (_darkPreset.isCustom) return parseHexColor(_darkCtrl.text);
    return _darkPreset.color;
  }

  /// 草稿的浅色槽「自动档」值（= 由草稿页底色派生）。
  Color get _draftAutoLightSidebar =>
      LightSurfaces.sidebarFor(_draftLightPage, dark: false);

  /// 草稿的深色槽「自动档」值（= 由草稿深色页底色派生）。
  ///
  /// 深色页底色未覆盖时**不能**拿 `CupertinoColors.systemGroupedBackground`
  /// 去 resolveFrom(context)：浅色态下它解析出的是浅色值，会把深色槽算成灰白。
  /// 未覆盖时原生深色分组背景（#000000）的派生值就是
  /// [LightSurfaces.kDefaultDarkSidebar]，直接取它，两侧口径一致。
  Color get _draftAutoDarkSidebar {
    final page = _draftDarkPage;
    return page == null
        ? LightSurfaces.kDefaultDarkSidebar
        : LightSurfaces.sidebarFor(page, dark: true);
  }

  /// 自定义位色块要显示的值：输入合法就显示输入值，否则显示派生值
  /// （与落码「非法回落自动档」同口径，色块不会空成一块白）。
  Color _customSidebarSwatch(bool dark) {
    final ctrl = dark ? _darkSidebarCtrl : _lightSidebarCtrl;
    return parseHexColor(ctrl.text) ??
        (dark ? _draftAutoDarkSidebar : _draftAutoLightSidebar);
  }

  /// 当前明暗态下生效的草稿槽色（自动档 = 派生；自定义 = 输入值）。
  Color _draftSidebar(bool dark) {
    if (_sidebarFollowsPage) {
      return dark ? _draftAutoDarkSidebar : _draftAutoLightSidebar;
    }
    return _customSidebarSwatch(dark);
  }

  Future<void> _apply() async {
    await ref
        .read(pageSurfaceProvider.notifier)
        .applySelection(
          lightPreset: _lightPreset,
          lightCustomHex: _lightCtrl.text,
          darkPreset: _darkPreset,
          darkCustomHex: _darkCtrl.text,
          sidebarFollowsPage: _sidebarFollowsPage,
          lightSidebarCustomHex: _lightSidebarCtrl.text,
          darkSidebarCustomHex: _darkSidebarCtrl.text,
        );
    if (mounted) Navigator.of(context).pop();
  }

  void _restoreDefaults() {
    const defaults = PageSurfaceState();
    setState(() {
      _lightPreset = defaults.lightPreset;
      _darkPreset = defaults.darkPreset;
      _lightCtrl.text = PageSurfaceState.defaultLightCustomHex;
      _darkCtrl.text = PageSurfaceState.defaultDarkCustomHex;
      _sidebarFollowsPage = defaults.sidebarFollowsPage;
      _lightSidebarCtrl.text = PageSurfaceState.defaultLightSidebarCustomHex;
      _darkSidebarCtrl.text = PageSurfaceState.defaultDarkSidebarCustomHex;
    });
  }

  /// 槽切回「自动」：只翻开关，输入框里的值留着 —— 用户来回试色不丢输入。
  void _selectSidebarAuto() => setState(() => _sidebarFollowsPage = true);

  /// 槽切到「自定义」：把输入框预填成**当前派生值**。
  ///
  /// 这是「切到自定义这一步本身不改变像素」的实现：预填值取自当前草稿页底色
  /// 的派生结果，所以点下去前后槽色逐字节相同（页底色「切到自定义」同口径）。
  /// 两态都预填：只填可见的那一个，另一态在切主题时会露出一个凭空的值。
  void _selectSidebarCustom() {
    if (!_sidebarFollowsPage) return;
    setState(() {
      _sidebarFollowsPage = false;
      _lightSidebarCtrl.text = hexFromColor(_draftAutoLightSidebar);
      _darkSidebarCtrl.text = hexFromColor(_draftAutoDarkSidebar);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLightMode =
        CupertinoTheme.brightnessOf(context) == Brightness.light;
    final isDarkMode = !isLightMode;
    final previewPage = isLightMode
        ? _draftLightPage
        : (_draftDarkPage ??
              CupertinoColors.systemGroupedBackground.resolveFrom(context));
    // 预览里的槽取**当前态**的草稿值：浅色态看浅色槽，深色态看深色槽。
    final previewSidebar = _draftSidebar(isDarkMode);
    final sidebarCtrl = isDarkMode ? _darkSidebarCtrl : _lightSidebarCtrl;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsPageSurface,
            style: const TextStyle(
              fontSize: kFontSectionTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _preview(l10n, previewPage, previewSidebar, dark: isDarkMode),
          const SizedBox(height: 18),
          _groupTitle(l10n.surfaceGroupLight),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in PageSurfacePreset.values)
                  _Swatch(
                    size: _swatchSizeFor(
                      constraints.maxWidth,
                      PageSurfacePreset.values.length,
                    ),
                    key: ValueKey('surface-light-${preset.name}'),
                    color: preset.isCustom
                        ? (parseHexColor(_lightCtrl.text) ??
                              PageSurfacePreset.neutral.color!)
                        : preset.color!,
                    selected: _lightPreset == preset,
                    isCustomEntry: preset.isCustom,
                    customEntryActive: _lightPreset.isCustom,
                    onTap: () => setState(() => _lightPreset = preset),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _currentLine(l10n, lightPresetLabel(l10n, _lightPreset),
              _lightPreset.isCustom ? _lightCtrl.text : null),
          if (_lightPreset.isCustom) ...[
            const SizedBox(height: 8),
            _hexField(
              key: const ValueKey('surface-light-hex'),
              controller: _lightCtrl,
              invalid: parseHexColor(_lightCtrl.text) == null,
              l10n: l10n,
            ),
            const SizedBox(height: 6),
            _hslSliders(
              key: const ValueKey('surface-light-sliders'),
              controller: _lightCtrl,
              l10n: l10n,
              onChanged: () => setState(() {}),
            ),
          ],
          const SizedBox(height: 18),
          _groupTitle(l10n.surfaceGroupDark),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in DarkSurfacePreset.values)
                  _Swatch(
                    size: _swatchSizeFor(
                      constraints.maxWidth,
                      DarkSurfacePreset.values.length,
                    ),
                    key: ValueKey('surface-dark-${preset.name}'),
                    color: preset.followsSystem
                        ? CupertinoColors.systemGroupedBackground.resolveFrom(
                            context,
                          )
                        : preset.isCustom
                        ? (parseHexColor(_darkCtrl.text) ??
                              const Color(0xFF1C1C1E))
                        : preset.color!,
                    selected: _darkPreset == preset,
                    isCustomEntry: preset.isCustom,
                    customEntryActive: _darkPreset.isCustom,
                    onTap: () => setState(() => _darkPreset = preset),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _currentLine(l10n, darkPresetLabel(l10n, _darkPreset),
              _darkPreset.isCustom ? _darkCtrl.text : null),
          if (_darkPreset.isCustom) ...[
            const SizedBox(height: 8),
            _hexField(
              key: const ValueKey('surface-dark-hex'),
              controller: _darkCtrl,
              invalid: parseHexColor(_darkCtrl.text) == null,
              l10n: l10n,
            ),
            const SizedBox(height: 6),
            _hslSliders(
              key: const ValueKey('surface-dark-sliders'),
              controller: _darkCtrl,
              l10n: l10n,
              onChanged: () => setState(() {}),
            ),
          ],
          const SizedBox(height: 18),
          _groupTitle(l10n.surfaceSidebarGroup),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _sidebarOption(
                  key: const ValueKey('surface-sidebar-auto'),
                  label: l10n.surfaceSidebarAuto,
                  onTap: _selectSidebarAuto,
                  swatch: _Swatch(
                    size: 40,
                    color: isDarkMode
                        ? _draftAutoDarkSidebar
                        : _draftAutoLightSidebar,
                    selected: _sidebarFollowsPage,
                    onTap: _selectSidebarAuto,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sidebarOption(
                  key: const ValueKey('surface-sidebar-custom'),
                  label: l10n.surfaceSidebarCustom,
                  onTap: _selectSidebarCustom,
                  swatch: _Swatch(
                    size: 40,
                    color: _customSidebarSwatch(isDarkMode),
                    selected: !_sidebarFollowsPage,
                    isCustomEntry: true,
                    customEntryActive: !_sidebarFollowsPage,
                    onTap: _selectSidebarCustom,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 当前值行在自动档也给出衍生值：自动档没有输入框，用户想核对
          // 「槽现在到底是什么色」只有这一处。
          _currentLine(
            l10n,
            _sidebarFollowsPage
                ? l10n.surfaceSidebarAuto
                : l10n.surfaceSidebarCustom,
            hexFromColor(previewSidebar),
          ),
          if (!_sidebarFollowsPage) ...[
            const SizedBox(height: 8),
            _hexField(
              key: const ValueKey('surface-sidebar-hex'),
              controller: sidebarCtrl,
              invalid: parseHexColor(sidebarCtrl.text) == null,
              l10n: l10n,
            ),
            const SizedBox(height: 6),
            _hslSliders(
              key: const ValueKey('surface-sidebar-sliders'),
              controller: sidebarCtrl,
              l10n: l10n,
              // 槽在深色态本就是暗色（#1B1B1B 的 HSL 明度只有 0.106），
              // 页底色那套 0.60–1.00 的下限会把滑杆顶死在最小值上。
              minLightness: 0,
              onChanged: () => setState(() {}),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              CupertinoButton(
                key: const ValueKey('surface-restore-default'),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _restoreDefaults,
                child: Text(
                  l10n.surfaceRestoreDefault,
                  style: const TextStyle(fontSize: kFontItemTitle),
                ),
              ),
              const Spacer(),
              CupertinoButton.filled(
                key: const ValueKey('surface-apply'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 8,
                ),
                onPressed: () => unawaited(_apply()),
                child: Text(l10n.surfaceApply),
              ),
            ],
          ),
        ],
      ),
    );

    // 内容要能滚：弹层是贴底/居中的定高形态，而内容会随档位长高 —— 实测
    // 自动档 505、三组都切自定义 850（420 宽）；矮窗（640 高）差 210 才能
    // 装下，844 高的手机屏也差 6。不加滚动就会把「应用」和槽组顶出屏幕。
    if (widget.wide) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
            child: SingleChildScrollView(child: body),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(14),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(child: body),
        ),
      ),
    );
  }

  /// 草稿预览：左竖条 = 侧栏槽，右侧 = 页底色 + 一张卡，中间一条 0.5pt
  /// 分栏线（三段都是真色块，不是灰占位）。
  ///
  /// 之所以要画槽：宽屏两栏的分区感全靠「槽比内容区差一个台阶」，只画页底色
  /// 的预览看不出这件事，用户改完才有感觉就晚了。
  Widget _preview(
    AppLocalizations l10n,
    Color page,
    Color sidebar, {
    required bool dark,
  }) {
    final border = LightSurfaces.borderFor(page);
    // 线族按主题解析：浅色用页底色派生的描边（与全页线族同源，v3 拍板），
    // 深色用 Cupertino 分隔线 —— 深色下沿用浅色描边会在黑底上画出一圈亮框。
    final hairline = LightSurfaces.resolve(
      context,
      border,
      dark: CupertinoColors.separator,
    );
    const radius = 10.0;
    return Container(
      key: const ValueKey('surface-preview'),
      height: 62,
      width: double.infinity,
      decoration: BoxDecoration(
        color: page,
        borderRadius: const BorderRadius.all(Radius.circular(radius)),
        border: Border.all(color: hairline, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 槽竖条：只取左侧圆角，半径减去外层描边宽度，与外框内缘对齐。
          Container(
            key: const ValueKey('surface-preview-sidebar'),
            width: 56,
            decoration: BoxDecoration(
              color: sidebar,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radius - 0.5),
                bottomLeft: Radius.circular(radius - 0.5),
              ),
            ),
          ),
          // 分栏线：真的 0.5pt 线，不是两块色之间的硬边。
          Container(width: 0.5, color: hairline),
          Expanded(
            child: Center(
              child: Container(
                width: 150,
                height: 34,
                decoration: BoxDecoration(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.card,
                    dark: CupertinoColors.secondarySystemGroupedBackground,
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(7)),
                  border: Border.all(color: hairline, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  l10n.surfacePreviewLabel,
                  style: TextStyle(
                    fontSize: kFontCaption,
                    color: LightSurfaces.resolve(
                      context,
                      LightSurfaces.textSecondary,
                      dark: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 侧栏槽的一个选项位：色块 + 选项名，整块可点。
  ///
  /// 只有排布是新的，色块本体仍用 [_Swatch]（勾选、「+」入口、选中描边都在
  /// 那里），避免第二套语义相同的色块控件各自漂移；整块套一层 GestureDetector
  /// 是因为选项名占的宽度比色块大得多 —— 只让色块可点的话，点在名字上是死的。
  Widget _sidebarOption({
    required Key key,
    required String label,
    required Widget swatch,
    required VoidCallback onTap,
  }) => GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        swatch,
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: kFontCaption,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.textSecondary,
              dark: CupertinoColors.secondaryLabel,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _groupTitle(String label) => Text(
    label,
    style: const TextStyle(
      fontSize: kFontCaption,
      color: LightSurfaces.textSecondary,
    ),
  );

  /// 当前档名（+ 自定义档时的输入值）。
  Widget _currentLine(AppLocalizations l10n, String name, String? hex) => Text(
    hex == null ? name : '$name · $hex',
    style: const TextStyle(fontSize: kFontCaption),
  );

  Widget _hexField({
    required Key key,
    required TextEditingController controller,
    required bool invalid,
    required AppLocalizations l10n,
  }) => Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 150,
        child: CupertinoTextField(
          controller: controller,
          placeholder: l10n.surfaceCustomHint,
          autocorrect: false,
          enableSuggestions: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          // 输入过程只更新草稿（不提交 ⇒ 不重建整棵树 ⇒ 输入框不失焦）。
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => setState(() {}),
        ),
      ),
      if (invalid) ...[
        const SizedBox(height: 4),
        Text(
          l10n.surfaceCustomInvalid,
          style: const TextStyle(
            fontSize: kFontCaption,
            color: CupertinoColors.systemRed,
          ),
        ),
      ],
    ],
  );

  /// 自定义色的**色相 / 明度**滑杆（主人 2026-10-06 追加的易用入口）。
  ///
  /// 只调 H 与 L，饱和度沿用当前值。明度默认给 **0.60–1.00** —— 页面底色
  /// 本质是浅色面，更暗的取值在界面上必然读不了字；需要极暗色仍可用 HEX
  /// 精确输入（输入框不设限，滑杆只是"顺手"的入口，不是门禁）。
  /// 侧栏槽传 [minLightness]=0：槽在深色态本来就是暗色。
  ///
  /// 滑杆是自绘的：CupertinoSlider 的轨道（activeColor + tertiarySystemFill）
  /// 会盖住渐变轨，用它就画不出「彩虹条 / 灰阶条」这种带语义的轨道。
  Widget _hslSliders({
    required Key key,
    required TextEditingController controller,
    required AppLocalizations l10n,
    required VoidCallback onChanged,
    double minLightness = 0.60,
    double maxLightness = 1.0,
  }) {
    final current =
        parseHexColor(controller.text) ?? PageSurfacePreset.neutral.color!;
    final hsl = HSLColor.fromColor(current);
    void apply(double hue, double lightness) {
      controller.text = hexFromColor(
        HSLColor.fromAHSL(1, hue, hsl.saturation, lightness).toColor(),
      );
      onChanged();
    }

    // 色相轨用固定中高饱和绘制（当前色可能是灰的，但轨道要表达"能选到什么色"）。
    const hueSat = 0.55;
    const hueLight = 0.72;
    Widget labelled(String label, Widget slider) => Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: kFontCaption,
              color: LightSurfaces.textSecondary,
            ),
          ),
        ),
        Expanded(child: slider),
      ],
    );

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelled(
          l10n.surfaceHue,
          _gradientSlider(
            key: const ValueKey('surface-hue-slider'),
            value: hsl.hue,
            min: 0,
            max: 360,
            gradient: LinearGradient(
            colors: [
              for (final stop in const [0, 60, 120, 180, 240, 300, 360])
                HSLColor.fromAHSL(
                  1,
                  stop.toDouble(),
                  hueSat,
                  hueLight,
                ).toColor(),
            ],
          ),
            onChanged: (v) =>
                apply(v, hsl.lightness.clamp(minLightness, maxLightness)),
          ),
        ),
        const SizedBox(height: 2),
        labelled(
          l10n.surfaceLightness,
          _gradientSlider(
            key: const ValueKey('surface-lightness-slider'),
            value: hsl.lightness.clamp(minLightness, maxLightness),
            min: minLightness,
            max: maxLightness,
            gradient: LinearGradient(
            colors: [
              HSLColor.fromAHSL(
                1,
                hsl.hue,
                hsl.saturation,
                minLightness,
              ).toColor(),
              HSLColor.fromAHSL(
                1,
                hsl.hue,
                hsl.saturation,
                maxLightness,
              ).toColor(),
            ],
          ),
            onChanged: (v) => apply(hsl.hue, v),
          ),
        ),
      ],
    );
  }

  /// 自绘渐变轨滑杆：渐变条铺满、白色圆滑块浮在其上。
  Widget _gradientSlider({
    required Key key,
    required double value,
    required double min,
    required double max,
    required Gradient gradient,
    required ValueChanged<double> onChanged,
  }) {
    final ratio = ((value.clamp(min, max) - min) / (max - min)).clamp(0.0, 1.0);
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(Offset local) {
          final r = (local.dx / width).clamp(0.0, 1.0);
          onChanged(min + r * (max - min));
        }

        const thumb = 22.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition),
          onHorizontalDragStart: (d) => seek(d.localPosition),
          onHorizontalDragUpdate: (d) => seek(d.localPosition),
          child: SizedBox(
            height: 34,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: const BorderRadius.all(Radius.circular(7)),
                      border: Border.all(
                        color: CupertinoColors.separator.resolveFrom(context),
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
                // 滑块位置 = 比例 × 可用宽（两端各留半个滑块，避免溢出）。
                Positioned(
                  left: (ratio * (width - thumb)).clamp(0.0, width - thumb),
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: BoxDecoration(
                        color: CupertinoColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: CupertinoColors.separator.resolveFrom(context),
                          width: 0.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 单个色块；[isCustomEntry] 为「自定义」入口位。
class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.size,
    this.isCustomEntry = false,
    this.customEntryActive = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// 边长（由调用方按可用宽自适应，见 [_swatchSizeFor]）。
  final double size;
  final bool isCustomEntry;
  final bool customEntryActive;

  @override
  Widget build(BuildContext context) {
    // 勾选色按底色亮度自适应，浅底用深勾、深底用白勾。
    final checkColor = color.computeLuminance() > 0.55
        ? const Color(0xFF3C3C43)
        : const Color(0xFFFFFFFF);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 40×40 + 8 间距：400 逻辑 pt（真机档）下 7 个色块仍能一行放下。
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(11)),
          border: Border.all(
            color: selected
                ? const Color(0xFF007AFF)
                : CupertinoColors.separator.resolveFrom(context),
            width: selected ? 2.5 : 0.5,
          ),
        ),
        child: Center(
          child: selected
              ? Icon(
                  CupertinoIcons.check_mark,
                  size: size * 0.42,
                  color: checkColor,
                )
              : (isCustomEntry && !customEntryActive
                    ? Icon(
                        CupertinoIcons.add,
                        size: size * 0.38,
                        color: checkColor,
                      )
                    : null),
        ),
      ),
    );
  }
}

/// 一组色块的自适应边长：按可用宽与格数反算，clamp 到 32–44。
///
/// 目的 = **任何屏宽下一组都排在一行不折行** —— 固定 44+10 间距在 400 逻辑 pt
/// （真机档）时 7×44+6×10=368 > 可用 360，会折成 6+1 两行。窄到排不下时
/// 由 [Wrap] 兜底换行，不会溢出。
double _swatchSizeFor(double maxWidth, int count) {
  const gap = 8.0;
  if (count <= 1) return 44;
  final raw = (maxWidth - gap * (count - 1)) / count;
  return raw.clamp(32.0, 44.0);
}

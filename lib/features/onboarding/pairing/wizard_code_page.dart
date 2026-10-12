import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'pairing_strings.dart';
import 'pairing_style.dart';

/// M3 · 输入电脑上的配对码（设计稿 §1 第三屏）。
///
/// 6 个码格（44×54、圆角 9、底色 rgba(120,120,128,.12)，当前格换主色 0.5 描边）
/// 由一只**透明输入框**驱动：系统键盘、粘贴、光标都由它承载，格子只做展示，
/// 点击格子区即聚焦（设计稿里第 6 格的蓝描边就是「当前位」）。
///
/// [submit] 由向导注入（负责「解析配对服务地址 → redeem → 落地连接」），
/// 返回 `null` 表示无错误文案（成功已跳转，或 cancelled 静默）；
/// 返回非空串即就地红字。
class WizardCodePage extends StatefulWidget {
  const WizardCodePage({super.key, required this.submit});

  /// 提交配对码；返回错误文案或 null。
  final Future<String?> Function(String code) submit;

  @override
  State<WizardCodePage> createState() => _WizardCodePageState();
}

class _WizardCodePageState extends State<WizardCodePage> {
  /// 配对码位数（契约：6 位数字）。
  static const int _codeLength = 6;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCodeChanged);
    _focusNode.addListener(_onFocusChanged);
    // 进页即聚焦：设计稿第 6 格带蓝描边的「当前位」即聚焦态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onCodeChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  bool get _complete => _controller.text.length == _codeLength;

  Future<void> _onSubmit() async {
    if (_busy) return;
    if (!_complete) {
      // 位数不足：不发请求，就地按「配对码不对」分档提示（设计稿里主按钮
      // 始终是主色可点态，不做禁用灰化）。
      setState(() => _error = PairingStrings.m3ErrorWrongCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.submit(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // cancelled（静默）与成功都返回 null —— 成功时向导已导航走，本页通常已卸载。
      _error = (message == null || message.isEmpty) ? null : message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const PairingPageIntro(
          title: PairingStrings.m3Title,
          subtitle: PairingStrings.m3Subtitle,
        ),
        const SizedBox(height: 34),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PairingMetrics.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCodeCells(context),
              const SizedBox(height: 30),
              PairingActionButton(
                key: const ValueKey('pairing-code-submit'),
                label: PairingStrings.m3Submit,
                busy: _busy,
                // 照设计稿：主按钮恒为主色可点态（不做「不足 6 位就灰掉」），
                // 位数不足由 _onSubmit 就地按分档文案提示。
                onPressed: () => _onSubmit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                PairingMicroText(
                  _error!,
                  align: TextAlign.center,
                  color: PairingColors.danger(context),
                ),
              ],
              const SizedBox(height: 14),
              // v1 禁用占位：扫码入口不引新依赖，灰字即「暂不可用」。
              const PairingActionButton(
                key: ValueKey('pairing-code-scan'),
                label: PairingStrings.m3ScanAction,
                icon: CupertinoIcons.camera,
                ghost: true,
              ),
              const SizedBox(height: 16),
              const PairingMicroText(
                PairingStrings.m3Footnote,
                align: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 六格：已输入的位显示数字；「当前位」（聚焦且未满）用主色 0.5 描边 + 透明底。
  Widget _buildCodeCells(BuildContext context) {
    final code = _controller.text;
    final currentIndex = _focusNode.hasFocus && code.length < _codeLength
        ? code.length
        : -1;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // 透明输入框：承担系统键盘 / 粘贴 / 光标，格子只做展示。
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: CupertinoTextField(
              key: const ValueKey('pairing-code-field'),
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_codeLength),
              ],
              autocorrect: false,
              enableSuggestions: false,
              autofocus: false,
              decoration: null,
              cursorColor: CupertinoColors.transparent,
              style: const TextStyle(color: CupertinoColors.transparent),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusNode.requestFocus(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _codeLength; i++) ...[
                if (i > 0) const SizedBox(width: PairingMetrics.codeCellGap),
                _buildCell(context, i, i < code.length ? code[i] : '', i == currentIndex),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCell(BuildContext context, int index, String digit, bool current) {
    return Container(
      key: ValueKey('pairing-code-cell-$index'),
      width: PairingMetrics.codeCellWidth,
      height: PairingMetrics.codeCellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: current
            ? CupertinoColors.transparent
            : PairingColors.codeFill(context),
        border: current
            ? Border.all(color: PairingColors.primary(context), width: 0.5)
            : null,
        borderRadius: BorderRadius.circular(PairingMetrics.codeCellRadius),
      ),
      child: Text(
        digit,
        style: TextStyle(
          fontSize: PairingMetrics.codeDigitSize,
          fontWeight: FontWeight.bold,
          color: PairingColors.label(context),
        ),
      ),
    );
  }
}

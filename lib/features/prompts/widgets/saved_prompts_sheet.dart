import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/light_surfaces.dart';
import '../../../app/theme/status_colors.dart';
import '../../../app/theme/typography_tokens.dart';
import '../../../app/widgets/hermes_dialog.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/saved_prompt.dart';
import '../../../l10n/app_localizations.dart';
import '../prompts_providers.dart';

/// 收藏提示词行 key 前缀（`saved-prompt-<id>`）。
const String _kSavedPromptRowKeyPrefix = 'saved-prompt-';

/// 行 key：**身份优先**，不再是「身份 + 下标」。
///
/// 旧形态 `ValueKey('saved-prompt-$id-$index')` 把下标写进了 key —— 增删一条就
/// 换 key（同一条提示词换了下标 = 换了身份），而
/// `SliverMultiBoxAdaptorElement.performRebuild` 只比**直接子节点**的
/// `widget.key` ⇒ 身份永远匹配不上，整段行销毁重建。改成身份型 key 后，缺的
/// 只是「key → 条目下标」反查（见 [_savedPromptIndexByKey]）。
///
/// id 为空时的兜底口径：`SavedPrompt.id` 是 `String?`，来源是
/// `SavedPrompt.fromJson` 的 `optString`（服务端不回 `id` 即解析为 null；本地
/// 缓存 `saved_prompts_cache_v1` 走同一个解析器），本页对这类行的删除按钮本就
/// 禁用（`onPressed` 的 `id == null || id.isEmpty`）。没有 id 就没有稳定身份，
/// 只能退回「文本 + 下标」（只保证同批渲染内唯一）；这类行换下标仍会重建 ——
/// 无法做得更好，在此显式承认。服务端正常路径（`/api/prompts` 带 id）不受影响。
String _savedPromptRowKey(SavedPrompt prompt, int index) {
  final id = prompt.id;
  if (id != null && id.isNotEmpty) return '$_kSavedPromptRowKeyPrefix$id';
  return '${_kSavedPromptRowKeyPrefix}text-${prompt.text ?? ''}#$index';
}

/// 反查：行 key → 条目下标。
///
/// 兜底形态（`saved-prompt-text-<文本>#<下标>`）天然匹配不到任何 `prompt.id`，
/// 因此自动落到 null（不搬家、按旧逻辑重建）；身份型 key 则命中 id。
/// 行内删除按钮的 `saved-prompt-delete-<id>` 不在直接子节点上、也不会被本函数
/// 命中（`delete-<id>` 不等于任何 `prompt.id`）。
int? _savedPromptIndexByKey(Key key, List<SavedPrompt> prompts) {
  if (key is! ValueKey<String>) return null;
  final value = key.value;
  if (!value.startsWith(_kSavedPromptRowKeyPrefix)) return null;
  final identity = value.substring(_kSavedPromptRowKeyPrefix.length);
  if (identity.isEmpty) return null;
  final index = prompts.indexWhere((prompt) => prompt.id == identity);
  return index < 0 ? null : index;
}

/// 收藏提示词列表面板（内容层，供底部 Sheet 与桌面 Popover 两种容器复用）。
///
/// - 列表由 [savedPromptsControllerProvider] 驱动；
/// - 行点击回调 [onInsert] 并关闭浮层（由调用方负责）；
/// - 底部「收藏当前输入」按钮需外部传入当前输入（[currentInput] 或 [getCurrentInput]）。
class SavedPromptsPanel extends ConsumerStatefulWidget {
  const SavedPromptsPanel({
    super.key,
    required this.onInsert,
    this.currentInput,
    this.getCurrentInput,
    this.onInserted,
  });

  /// 选中某条收藏后的插入回调（由调用方负责写入输入框并关闭浮层）。
  final ValueChanged<String> onInsert;

  /// 当前输入快照（静态值）。
  final String? currentInput;

  /// 当前输入回调（动态读取，优先于 [currentInput]）。
  final String Function()? getCurrentInput;

  /// 行插入成功后回调（用于让调用方关闭容器）。
  final VoidCallback? onInserted;

  @override
  ConsumerState<SavedPromptsPanel> createState() => _SavedPromptsPanelState();
}

class _SavedPromptsPanelState extends ConsumerState<SavedPromptsPanel> {
  bool _saving = false;
  final Set<String> _deletingIds = <String>{};

  String _resolveCurrentInput() {
    if (widget.getCurrentInput != null) return widget.getCurrentInput!.call();
    return widget.currentInput ?? '';
  }

  Future<void> _handleSaveCurrent() async {
    final l10n = AppLocalizations.of(context);
    final raw = _resolveCurrentInput();
    final text = raw.trim();
    if (text.isEmpty) {
      await _showAlert(l10n.notice, l10n.savedPromptsEmptyInput);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prompt = await ref
          .read(savedPromptsControllerProvider.notifier)
          .create(text: text);
      if (!mounted) return;
      if (prompt != null) {
        await _showAlert(l10n.promptSaved, l10n.promptSaved);
      } else {
        await _showAlert(
          l10n.savePromptFailed,
          l10n.savePromptFailed,
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      // ApiException 已带面向用户的中文 message（服务端拒绝原因也走这条，
      // 如「已达上限 (max 200)」），直接展示；其余异常保留 toString 便于排查。
      final detail = error is ApiException ? error.message : error.toString();
      await _showAlert(l10n.savePromptFailed, detail, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete(String id) async {
    if (id.isEmpty || _deletingIds.contains(id)) return;
    setState(() => _deletingIds.add(id));
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(savedPromptsControllerProvider.notifier).remove(id);
    } catch (error) {
      if (!mounted) return;
      final detail = error is ApiException ? error.message : error.toString();
      await _showAlert(l10n.deletePromptFailed, detail, isError: true);
    } finally {
      if (mounted) setState(() => _deletingIds.remove(id));
    }
  }

  Future<void> _showAlert(
    String title,
    String message, {
    bool isError = false,
  }) {
    final l10n = AppLocalizations.of(context);
    // 动作配色的浅色判据原先取自 dialogContext 亮度；`HermesDialogAction`
    // 的 `textStyle` 在构造期就要定值（builder 才收 dialogContext），故改从
    // 调用点 context 取 —— 浮层与调用页共用同一 CupertinoTheme，亮度一致。
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    // 批 5 · C4：D1 四档宽「确认框 380」（窄屏仍是系统 alert，逐像素不变；
    // 正文红字与动作配色逐字段保留）。
    return showHermesDialog<void>(
      context,
      kind: HermesDialogKind.confirm,
      title: (_) => Text(title),
      content: (dialogContext) => Text(
        message,
        style: isError
            ? TextStyle(color: statusRedText.resolveFrom(dialogContext))
            : null,
      ),
      actions: [
        HermesDialogAction(
          textStyle: isLight
              ? const TextStyle(color: LightSurfaces.userDetail)
              : null,
          builder: (_) => Text(l10n.ok),
          onPressed: (dialogContext) => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(savedPromptsControllerProvider);

    // 覆盖式小 indicator：有数据时不替换整板，仅叠加顶部细线 loading
    final hasData = async.valueOrNull != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (async.isLoading && hasData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: CupertinoActivityIndicator(radius: 10),
          ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _buildBody(context, async),
          ),
        ),
        Container(
          height: 0.5,
          color: LightSurfaces.resolve(
            context,
            LightSurfaces.divider,
            dark: CupertinoColors.separator,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              key: const ValueKey('saved-prompts-save-current'),
              color: CupertinoTheme.brightnessOf(context) == Brightness.light
                  ? LightSurfaces.userDetail
                  : null,
              onPressed: _saving ? null : _handleSaveCurrent,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _saving
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : Text(l10n.saveCurrentInput),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AsyncValue<List<SavedPrompt>> async) {
    final l10n = AppLocalizations.of(context);
    return async.when(
      data: (prompts) {
        if (prompts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Text(
                l10n.savedPromptsEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                ),
              ),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: prompts.length,
          // 身份型 key + 反查条目下标（separated 内部自己 ×2 换算成子下标）：
          // 删除/新增导致的下标平移才不会把整段行销毁重建。
          findItemIndexCallback: (key) => _savedPromptIndexByKey(key, prompts),
          separatorBuilder: (_, _) => Container(
            height: 0.5,
            color: LightSurfaces.resolve(
              context,
              LightSurfaces.divider,
              dark: CupertinoColors.separator,
            ),
            margin: const EdgeInsets.only(left: 16),
          ),
          itemBuilder: (context, index) {
            final prompt = prompts[index];
            final id = prompt.id;
            final displayLabel = savedPromptDisplayLabel(prompt);
            final rawLabel = prompt.label?.trim();
            final title = (rawLabel != null && rawLabel.isNotEmpty)
                ? rawLabel
                : (displayLabel.isEmpty ? (prompt.text ?? '') : displayLabel);
            final subtitleText = prompt.text ?? '';
            final isDeleting = id != null && _deletingIds.contains(id);
            final isLight =
                CupertinoTheme.brightnessOf(context) == Brightness.light;
            return CupertinoListTile(
              // 身份型 key（id 非空时就是 id）；含下标的旧形态已废弃，见
              // _savedPromptRowKey 的注释。
              key: ValueKey(_savedPromptRowKey(prompt, index)),
              backgroundColor: isLight ? LightSurfaces.card : null,
              backgroundColorActivated: isLight ? LightSurfaces.pressed : null,
              title: Text(
                title.isEmpty ? l10n.unnamed : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: LightSurfaces.resolve(
                    context,
                    LightSurfaces.textSecondary,
                    dark: CupertinoColors.secondaryLabel,
                  ),
                  fontSize: kFontLabel,
                ),
              ),
              trailing: CupertinoButton(
                key: ValueKey('saved-prompt-delete-$id'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: (id == null || id.isEmpty || isDeleting)
                    ? null
                    : () => _handleDelete(id),
                child: isDeleting
                    ? const CupertinoActivityIndicator(radius: 10)
                    : Icon(
                        CupertinoIcons.delete,
                        size: 20,
                        color: statusRedText.resolveFrom(context),
                      ),
              ),
              onTap: () {
                widget.onInsert(prompt.text ?? '');
                widget.onInserted?.call();
              },
            );
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CupertinoActivityIndicator(),
        ),
      ),
      error: (error, _) {
        // 有缓存数据时错误不替换整板，仅显示重试行（由上层覆盖式 indicator 处理）
        // 无缓存才展示全板错误
        final isLight =
            CupertinoTheme.brightnessOf(context) == Brightness.light;
        if (async.valueOrNull != null && async.valueOrNull!.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: CupertinoButton(
                key: const ValueKey('saved-prompts-retry'),
                onPressed: () =>
                    ref.read(savedPromptsControllerProvider.notifier).refresh(),
                child: Text(
                  l10n.retry,
                  style: isLight
                      ? const TextStyle(color: LightSurfaces.userDetail)
                      : null,
                ),
              ),
            ),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: statusRedText.resolveFrom(context)),
                ),
                const SizedBox(height: 12),
                CupertinoButton(
                  key: const ValueKey('saved-prompts-retry'),
                  onPressed: () => ref
                      .read(savedPromptsControllerProvider.notifier)
                      .refresh(),
                  child: Text(
                    l10n.retry,
                    style: isLight
                        ? const TextStyle(color: LightSurfaces.userDetail)
                        : null,
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

/// 收藏提示词底部 Sheet（移动端窄屏容器：占底部的全宽弹层）。
///
/// 内容委托给 [SavedPromptsPanel]；桌面/平板宽屏请改用 popover 容器
/// （见 `lib/app/widgets/cupertino_popover.dart`）。
class SavedPromptsSheet extends StatelessWidget {
  const SavedPromptsSheet({
    super.key,
    required this.onInsert,
    this.currentInput,
    this.getCurrentInput,
  });

  /// 选中某条收藏后的插入回调（由调用方负责写入输入框）。
  final ValueChanged<String> onInsert;

  /// 当前输入快照（静态值）。
  final String? currentInput;

  /// 当前输入回调（动态读取，优先于 [currentInput]）。
  final String Function()? getCurrentInput;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = CupertinoTheme.brightnessOf(context) == Brightness.light;
    final bg = LightSurfaces.resolve(
      context,
      LightSurfaces.card,
      dark: CupertinoColors.systemGrey6,
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: isLight
            ? Border.all(color: LightSurfaces.cardBorder, width: 0.5)
            : null,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // 拖拽手柄保持 systemGrey3 装饰填充（非文字信息层，豁免正文 AA）。
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.savedPromptsTitle,
              // TODO(type): 未进梯子（弹层标题 16）。
              style: const TextStyle(
                fontSize: kFontItemTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 0.5,
              color: LightSurfaces.resolve(
                context,
                LightSurfaces.divider,
                dark: CupertinoColors.separator,
              ),
            ),
            SavedPromptsPanel(
              onInsert: onInsert,
              currentInput: currentInput,
              getCurrentInput: getCurrentInput,
              onInserted: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

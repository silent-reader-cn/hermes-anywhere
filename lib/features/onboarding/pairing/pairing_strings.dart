/// 手机端首启配对向导（形态 B 决策树）的全部新增文案 —— **本批的唯一文案出口**。
///
/// 为什么不是直接写进 `lib/l10n/app_localizations.dart`：本批文件白名单不含
/// `lib/l10n/**`（三路并行实现共享该文件，就地改会冲突）。故文案先在此收口，
/// **每一条**都带 `// TODO(l10n): 收口并入 app_localizations.dart` 标记；领头人
/// 合并时按同名 getter 迁进 `AppLocalizations`，随后删除本文件、调用点改用
/// `AppLocalizations.of(context)`（迁移映射：`PairingStrings.xxx` → `l10n.xxx`）。
library;

import '../../../core/pairing/pairing_contract.dart';

/// 配对向导文案（真值来自设计稿 `sketches/onboarding-pairing-wizard.html` §1）。
abstract final class PairingStrings {
  // ───────────────────────────────────────────────────────────────────────────
  // 导航栏标题
  // ───────────────────────────────────────────────────────────────────────────

  /// M1 首问页导航标题。
  static const String navStart = '开始使用'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 发现页导航标题。
  static const String navSameWifi = '同一 Wi-Fi 连接'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M3 配对码页导航标题。
  static const String navPair = '配对'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 下载引导页导航标题。
  static const String navDownload = '下载桌面版'; // TODO(l10n): 收口并入 app_localizations.dart

  // ───────────────────────────────────────────────────────────────────────────
  // M1 · 第一问「Hermes 跑在哪台电脑上？」
  // ───────────────────────────────────────────────────────────────────────────

  /// M1 页大标题。
  static const String m1Title = 'Hermes 跑在哪台电脑上？'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 副文。
  static const String m1Subtitle =
      'Hermes 需要一个常驻的后端电脑。选一种情况，下面这几步本机会自动做完。'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 卡片①标题（同一 Wi-Fi）。
  static const String m1CardSameWifiTitle = '电脑就在同一个 Wi-Fi'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 卡片①副行。
  static const String m1CardSameWifiDesc = '自动发现，配对后即可连接'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 卡片②标题（电脑在别处）。
  static const String m1CardElsewhereTitle = '电脑在别处'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 卡片②副行。
  static const String m1CardElsewhereDesc =
      '4G／公司／外地：用配对码连接，需先开启远程访问'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 卡片③标题（还没装桌面版）。
  static const String m1CardNotInstalledTitle = '我还没在电脑上装 Hermes'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 卡片③副行。
  static const String m1CardNotInstalledDesc = '先下载桌面版，装好再回到这里'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 底部次级链接（进入旧远程表单兜底入口）。
  static const String m1ManualEntryLink = '我有服务器地址'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M1 最底部微文案。
  static const String m1FooterNote = '多台电脑可以稍后在「设置 → 连接」里添加'; // TODO(l10n): 收口并入 app_localizations.dart

  // ───────────────────────────────────────────────────────────────────────────
  // M2 · 同一 Wi-Fi 自动发现
  // ───────────────────────────────────────────────────────────────────────────

  /// M2 搜索中页大标题。
  static const String m2TitleSearching = '正在找你的电脑'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 未发现任何电脑时的页大标题。
  static const String m2TitleEmpty = '没找到你的电脑'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 副文。
  static const String m2Subtitle =
      '请保持手机与电脑在同一个 Wi-Fi，并确认电脑上的 Hermes 已经打开。'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 发现卡右侧小按钮。
  static const String m2PairAction = '配对'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 发现卡副行（候选未带 WebUI 地址时的默认口径：内置服务固定 8787）。
  static const String m2CandidateMetaDefault =
      '内置服务 · 8787 · 同一网络'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 自检小标题。
  static const String m2ChecklistTitle = '没找到？'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 自检第 1 条。
  static const String m2Check1 = '1. 确认电脑上的 Hermes 正在运行'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 自检第 2 条。
  static const String m2Check2 = '2. 确认两台设备连的是同一个 Wi-Fi'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 自检第 3 条。
  static const String m2Check3 = '3. 检查电脑防火墙是否放行 8787'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 兜底链接（进入旧远程表单）。
  static const String m2ManualEntryLink = '手动输入地址'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M2 发现卡副行（候选自带 WebUI 地址时按其端口显示）。
  static String m2CandidateMetaOnPort(int port) =>
      '内置服务 · $port · 同一网络'; // TODO(l10n): 收口并入 app_localizations.dart

  // ───────────────────────────────────────────────────────────────────────────
  // M3 · 配对码
  // ───────────────────────────────────────────────────────────────────────────

  /// M3 页大标题。
  static const String m3Title = '输入电脑上的配对码'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M3 副文。
  static const String m3Subtitle =
      '在电脑上点「让手机连上」，会显示 6 位配对码。密码由 App 后台交接，不需要你抄。'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M3 主按钮。
  static const String m3Submit = '配对并连接'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M3 次级按钮（v1 禁用占位）。
  static const String m3ScanAction = '改用扫一扫'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M3 底部微文案。
  static const String m3Footnote = '配对码 10 分钟内有效，配对成功后立即失效。'; // TODO(l10n): 收口并入 app_localizations.dart

  // ── 失败分档文案（一一对应 PairingFailure；cancelled 静默无文案）──

  /// 配对码过期。
  static const String m3ErrorExpired = '配对码已过期，请在电脑上重新生成'; // TODO(l10n): 收口并入 app_localizations.dart

  /// 配对码不匹配。
  static const String m3ErrorWrongCode = '配对码不对，请核对电脑上显示的 6 位码'; // TODO(l10n): 收口并入 app_localizations.dart

  /// 对端没有开启配对 / 不是 Hermes 后端（也用于「压根没有可用的配对服务地址」）。
  static const String m3ErrorUnavailable =
      '没有找到配对服务，确认电脑上的 Hermes 正在运行'; // TODO(l10n): 收口并入 app_localizations.dart

  /// 网络不可达。
  static const String m3ErrorNetwork = '网络不可达，确认两台设备在同一个 Wi-Fi'; // TODO(l10n): 收口并入 app_localizations.dart

  // ───────────────────────────────────────────────────────────────────────────
  // M4 · 下载桌面版引导
  // ───────────────────────────────────────────────────────────────────────────

  /// M4 页大标题。
  static const String m4Title = '先在电脑上装 Hermes'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 副文。
  static const String m4Subtitle =
      '桌面版装好后会自动启动后端，不需要配置任何东西。'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 步骤①标题。
  static const String m4Step1Title = '下载 Windows / macOS 桌面版'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 步骤①副行。
  static const String m4Step1Desc = '安装包已内置后端，无需装 Python'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 步骤②标题。
  static const String m4Step2Title = '安装并打开，点「让手机连上」'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 步骤②副行。
  static const String m4Step2Desc = '桌面版会显示 6 位配对码'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 步骤③标题。
  static const String m4Step3Title = '回到手机输入配对码'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 步骤③副行。
  static const String m4Step3Desc = '完成，之后打开 App 自动连接'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 主按钮。
  static const String m4CopyLink = '复制下载链接'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 复制成功回执（设计稿无此条，就地反馈用；仅本页出现）。
  static const String m4Copied = '下载链接已复制'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 界面展示的短链。
  static const String m4LinkLabel =
      'github.com/silent-reader-cn/hermes-keep/releases/latest'; // TODO(l10n): 收口并入 app_localizations.dart

  /// M4 底部微文案。
  static const String m4Footnote =
      '复制后发到电脑上的微信 / QQ，打开就能下载'; // TODO(l10n): 收口并入 app_localizations.dart

  /// 复制进剪贴板的完整地址（非文案：跨设备可打开的 URL，不参与 l10n）。
  static const String downloadUrl =
      'https://github.com/silent-reader-cn/hermes-keep/releases/latest';

  // ───────────────────────────────────────────────────────────────────────────
  // 语义映射
  // ───────────────────────────────────────────────────────────────────────────

  /// [PairingFailure] → 分档文案；[PairingFailure.cancelled] 返回空串（静默）。
  static String pairingFailureMessage(PairingFailure reason) {
    return switch (reason) {
      PairingFailure.expired => m3ErrorExpired,
      PairingFailure.wrongCode => m3ErrorWrongCode,
      PairingFailure.unavailable => m3ErrorUnavailable,
      PairingFailure.network => m3ErrorNetwork,
      PairingFailure.cancelled => '',
    };
  }
}

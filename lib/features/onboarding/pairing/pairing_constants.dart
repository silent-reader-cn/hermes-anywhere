/// 手机端配对向导的**非文案**常量与文案映射。
///
/// 本件只放两类东西（其余全部用户可见文案已进 `lib/l10n/app_localizations.dart`，
/// 见其中 `pairing*` 前缀段）：
/// 1. 跨设备可打开的下载 URL —— 各语言同一地址，不是可译文案；
/// 2. [PairingFailure] → 分档文案的小映射函数 —— 需要 `AppLocalizations` 取值，
///    放在调用点旁边比塞进 l10n 目录更透亮。
library;

import '../../../core/pairing/pairing_contract.dart';
import '../../../l10n/app_localizations.dart';

/// 复制进剪贴板的完整下载地址（非文案：跨设备可打开的 URL，不参与 l10n）。
const String hermesDownloadUrl =
    'https://github.com/silent-reader-cn/hermes-anywhere/releases/latest';

/// [PairingFailure] → 分档文案；[PairingFailure.cancelled] 返回空串（静默）。
String pairingFailureText(AppLocalizations l10n, PairingFailure reason) {
  return switch (reason) {
    PairingFailure.expired => l10n.pairingCodeErrorExpired,
    PairingFailure.wrongCode => l10n.pairingCodeErrorWrongCode,
    PairingFailure.unavailable => l10n.pairingCodeErrorUnavailable,
    PairingFailure.network => l10n.pairingCodeErrorNetwork,
    PairingFailure.cancelled => '',
  };
}

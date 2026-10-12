/// 桌面端本机部署向导（usr:/install-guide）本批新增/改写的文案常量。
///
/// 为什么单开一个文件：本批**禁改 `lib/l10n/**`**（该目录由 l10n 批次独占），
/// 但向导新增的每一句中文都得有唯一的落点 —— 散进 widget 树会让后续迁进 l10n
/// 时到处翻。故本批新增文案一律经这里取用；能与既有 l10n 对齐的（页面标题、
/// 副标题、按钮「开始一键安装」等）继续走 `AppLocalizations`，不在此重复。
///
/// 设计出处：`sketches/onboarding-pairing-wizard.html` §5 R1-B / N1 / N2 / N3。
library;

/// 向导文案常量（全部为中文原文，禁止在 widget 里再写字面量）。
abstract final class WizardStrings {
  // ── 进度与步骤名（横向轨 5 步） ───────────────────────────────────────────

  /// 进度行：`进度: 0 / 5 步骤`。
  static String progressText(int done, int total) => '进度: $done / $total 步骤';

  /// 第 1 步（原 prereqs 语义保留）。
  static const String stepPrereqs = '环境检查';

  /// 第 2 步（原 agent 语义保留）。
  static const String stepAgent = '拉取 Agent';

  /// 第 3 步（原 agentDeps 语义保留）。
  static const String stepDeps = '安装依赖';

  /// 第 4 步（本批新增）。
  static const String stepService = '启动服务';

  /// 第 5 步（本批新增）。
  static const String stepPairing = '手机配对';

  // ── 各步副行（详情卡第二行） ─────────────────────────────────────────────

  /// 环境检查副行。
  static const String descPrereqs = '检查 Python、Git 及 PowerShell 环境';

  /// 拉取 Agent 副行。
  static const String descAgent = '下载并通过 install.ps1 安装 Hermes Agent';

  /// 安装依赖副行。
  static const String descDeps = '配置 Python 虚拟环境并安装核心依赖';

  /// 启动服务副行。
  static const String descService = '拉起 WebUI 并开启局域网访问';

  /// 手机配对副行。
  static const String descPairing = '生成配对码，等待手机接入';

  // ── 步骤状态（详情卡右侧） ───────────────────────────────────────────────

  /// 等待中。
  static const String stagePending = '等待中';

  /// 执行中。
  static const String stageRunning = '执行中…';

  /// 已完成。
  static const String stageSuccess = '已完成';

  /// 失败。
  static const String stageFailed = '失败';

  // ── 首屏检查卡（第 4 行「网络环境」为本批新增） ───────────────────────────

  /// Windows 行标题。
  static const String checkWindows = 'Windows 11';

  /// Windows 行值。
  static const String checkWindowsValue = '系统与权限检查通过';

  /// Agent 行标题。
  static const String checkAgent = 'Hermes Agent';

  /// Agent 行值（未安装）。
  static const String checkAgentPending = '待安装 · 使用官方 install.ps1';

  /// Agent 行值（已装完）。
  static const String checkAgentInstalled = '已安装 · 使用官方 install.ps1';

  /// 内置服务行标题。
  static const String checkService = '内置服务';

  /// 内置服务行值（未启动）。
  static const String checkServicePending = '安装后自动启动';

  /// 网络环境行标题。
  static const String checkNetwork = '网络环境';

  /// 网络环境行值（正常）。
  static const String networkNormal = '正常';

  /// 网络环境行值（检测中）。
  static const String networkChecking = '检测中…';

  /// 网络环境行值（探测过程本身出错）。
  static const String networkFailed = '检测失败';

  /// 「重新检测」按钮。
  static const String networkRecheck = '重新检测';

  /// 「仍然继续」按钮。
  static const String networkContinue = '仍然继续';

  /// 受限地区提示卡正文。
  ///
  /// 用词铁律：只写「网络加速（代理）」，**不出现 VPN 字样**（主人 2026-10-12 拍板）。
  static const String networkWarning =
      '在中国大陆等网络受限地区部署时，建议先开启网络加速（代理）再安装，'
      '否则「拉取 Agent」与「安装依赖」两步容易超时失败。已开启加速就点重新检测。';

  /// 提示卡下方微文案。
  static const String networkSkipHint = '也可以先跳过：检测只影响安装速度，不影响功能';

  // ── 启动服务步：Tailscale 勾选（默认勾选） ───────────────────────────────

  /// Tailscale 行标题。
  static const String tailscaleTitle = '一起安装 Tailscale（内网穿透）';

  /// Tailscale 行「推荐」徽标。
  static const String tailscaleBadge = '推荐';

  /// Tailscale 副行 1。
  static const String tailscaleSub1 =
      '装好后手机在任何网络都能连（4G / 公司 / 外地），不需要同一个 Wi-Fi。';

  /// Tailscale 副行 2（诚实边界：浏览器授权无法代劳）。
  static const String tailscaleSub2 =
      '勾选后这一步会替你下载安装并打开登录页；需要 Tailscale 账号'
      '（Google / 微软 / GitHub / Apple），官方不支持邮箱注册。';

  /// Tailscale 豁免说明（未勾选也能用）。
  static const String tailscaleExempt =
      '不勾选也能用：同一 Wi-Fi 下手机可以直接连；跨网再走「远程访问」。'
      'Tailscale 只做组网，流量端到端加密，不经过我们的服务器。';

  /// Tailscale 服务未注入时的降级提示（不崩，只是没得装）。
  static const String tailscaleUnavailable = 'Tailscale 服务不可用，已跳过内网穿透安装。';

  /// Tailscale 安装三态轨的步骤名（与主步骤条同一形态）。
  static const List<String> tailscaleSteps = <String>[
    '下载安装包',
    '静默安装',
    '登录生成地址',
  ];

  /// Tailscale 就绪摘要前缀（后接 100.x 地址）。
  static const String tailscaleReadyPrefix = '已就绪 · ';

  /// Tailscale 未就绪（失败）时的收尾说明：不阻断向导，可稍后重试。
  static const String tailscaleFailedHint =
      'Tailscale 未就绪，不影响本次向导；可稍后在本机部署向导或「远程访问」里重试。';

  /// Tailscale 需要去浏览器授权时的提示前缀（后接授权 URL）。
  static const String tailscaleLoginHint = '请在浏览器完成 Tailscale 授权：';

  /// Tailscale 进行中的占位说明（状态流还没吐 detail 时）。
  static const String tailscaleWorking = '正在处理…';

  // ── 启动服务步：局域网可见性 / 凭据 / 服务状态 ───────────────────────────

  /// 局域网访问行标题。
  static const String lanTitle = '允许局域网设备访问';

  /// 局域网访问行值（开启，含监听地址）。
  static String lanOn(String host, int port) => '已开启 · $host:$port';

  /// 局域网访问行值（关闭）。
  static const String lanOff = '仅本机（127.0.0.1）';

  /// 凭据行标题。
  static const String credentialTitle = '访问凭据';

  /// 凭据行值。
  static const String credentialValue = '配对码交接 · 不使用明文密码';

  /// 服务状态行标题。
  static const String serviceStatusTitle = '服务状态';

  /// 服务状态行值（运行中）。
  static String serviceRunning(String host, int port) => '● 运行中 $host:$port';

  /// 服务状态行值（未启动）。
  static const String serviceStopped = '未启动';

  /// 服务状态行值（启动中）。
  static const String serviceStarting = '启动中…';

  /// 启动服务步尾部主按钮（进入配对）。
  static const String nextPairing = '下一步：配对';

  // ── 手机配对步 ───────────────────────────────────────────────────────────

  /// 等待手机接入。
  static const String pairingWaiting = '等待手机接入…';

  /// 配对引导句。
  static const String pairingHint = '打开手机上的 Hermes → 连接服务器，会自动发现这台电脑';

  /// 配对码有效期微文案。
  static const String pairingTtl = '配对码 10 分钟内有效，配对成功后立即失效';

  /// 「重新生成」次级按钮。
  static const String pairingRegenerate = '重新生成';

  /// 配对地址前缀（后接 http://host:port）。
  static const String pairingAddressPrefix = '配对地址：';

  /// 配对服务未注入时的标题。
  static const String pairingUnavailable = '配对服务不可用';

  /// 配对服务未注入时的说明（允许跳过，不崩）。
  static const String pairingUnavailableHint =
      '当前构建没有注入配对服务。可以跳过这一步，稍后在「设置 → 连接」里用配对码接入。';

  /// 生成配对码失败前缀。
  static const String pairingErrorPrefix = '配对码生成失败：';

  /// 跳过配对的次级按钮。
  static const String pairingSkip = '跳过配对，先进入应用';

  /// 验收态标题（对端已连上才算向导成功）。
  static const String pairedTitle = '手机已连上';

  /// 验收态副行。
  static const String pairedSub = '配对完成。以后打开 App 会自动连接这台电脑。';

  /// 验收态设备行的值。
  static const String pairedJustNow = '刚刚配对';

  /// 验收态本机行的值前缀（后接 host:port）。
  static String pairedService(String host, int port) => '内置服务 · $host:$port';

  /// 完成按钮。
  static const String pairedFinish = '完成';
}

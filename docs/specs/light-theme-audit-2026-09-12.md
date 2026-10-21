# 浅色主题全仓审计 · 2026-09-12

本报告按 TASK.md §1 的方案执行。阶段一完成令牌层和会话列表；阶段二完成 P0 聊天与 P1 外壳/导航，P2+ 页面保持只读。视觉取舍由 Leader 验收。

## 范围与复验方法

- 扫描 `lib/` 全部 **293** 个 Dart 文件，记录 **2143** 个颜色引用/常量/别名透明度使用点。按实际目录补入下载、诊断和内置服务，不沿用旧目录快照假定覆盖。
- 语义色取自 Flutter **3.47.0** / Dart **3.13.0** 的 `packages/flutter/lib/src/cupertino/colors.dart` 普通浅色分支；增强对比度和暗色保留分支另标豁免。
- WCAG：sRGB 通道 `c<=0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`；相对亮度 `0.2126R+0.7152G+0.0722B`；比值 `(L高+0.05)/(L低+0.05)`。先按实际 alpha 在 sRGB 合成，再线性化；中间值不取整，表格保留六位小数。
- 正文 AA 门槛 4.5:1，功能图标/数据图形按 3:1；纯装饰面、边框、投影不套正文 AA。低对比度卡片面仍可存在视觉分层问题，不能用“装饰豁免”宣称已经分层充分。
- 逐文件表三向列为：该色合成到**页面底 P**、**白卡 C**、**黑色 label L** 后各自的对比度。会话列表、聊天及侧栏工具条 P 用新 page，空态详情 P 用白面，其余文件 P 用现行全局分组背景。它们是明确的承载面参考值；反色内容和已知彩色组合另列附录，不能拿白字对白卡的参考值误判反色 tooltip。
- 静态审计列出所有可解析颜色及来源、透明度和组件默认色。运行时透明度/任意图片内容不能由单个基色证明 AA，表中明确保留限制；本轮没有逐页启动所有状态，也不声称全仓视觉验收通过。
- `python tools/light_theme_contrast.py` 输出本报告全文；`--tokens` 复算令牌注释；`--write-report` 生成文件；`--check-report` 校验报告与当前源码/SDK 完全一致。无第三方 Python 依赖。没有 `.dart_tool/package_config.json` 时可传 `--flutter-sdk <SDK根目录>`。

## 阶段一结果及保留项

- page/card 的对比度由 1.115871 变为 1.119495；cardBorder 对白卡为 1.543866，对新页面为 1.379074。描边取 #CCD0DA、0.5–1 逻辑像素（v2：主人实机反馈灰底过深后，page 退回 #F2F2F2 并以加深描边承担分层），视觉差由 before/after 供 Leader 判断。
- 原候选 #6E6E73 对新页面仅 4.530009；保持 R=G、B=R+5，#6A6A6F 为最浅整字节达标值；再浅一档 #6B6B70 为 4.734345。
- 新 page 仅用于会话列表和其侧栏复用区，局部导航背景同步；全局 buildCupertinoTheme 未改。白卡、搜索框、次级文案/菜单图标、过滤 Sheet、批量栏、弃用 disclosure 计数、FAB 工作区浮层接入。选中和按下反馈只在浅色分支启用。
- 源码未渲染时间戳文字（时间只参与分组排序），没有为满足任务描述而新增时间戳或改业务数据流。三点菜单/副标题/置顶图标使用新次级色。
- #EEFFFFFF 与 #B3FFFFFF 的普通浮层面归 card；#1F000000 作为普通浮层边框的调用归 cardBorder，作为投影的调用保留。#F0000000 是反色 tooltip，白字组合见附录，保留其语义。
- 深色 helper 使用原语义色并显式 resolve；历史未 resolve 的灰图标和选中蓝图标保留原实际绘制 ARGB，避免顺手改变深色增强对比度像素。暗色路径无新增按下/选中填色。
- README 截图工装原样调用，通过外部 comparator 重定向到 `C:/tmp/light-theme-shots/before/` 与 `after/`；没有写入 `docs/screenshots/`。该工装的 CupertinoApp 未接 buildCupertinoTheme，改造前页面使用其默认背景；全局主题数值以源码和正式金照为准。

## 阶段二 P0 结果及保留项

- 聊天页局部 page/bar 接 LightSurfaces.page（现 #F2F2F2）；动作色 #005FB8，不改全局主题。次级文字、占位符、功能灰图标按各自承载面接令牌。
- 审批/澄清/错误/绿色提示面固定为不透明 tint，输入框、工具卡、选中上下文、注入卡和媒体占位接白面/描边；模型/工作区/推理选择保留勾选并增加选中、按下面。
- 用户主气泡 #007AFF + 白字按 Leader 决定保留（实算 4.016976:1，未达正文 AA）。白字降透明度或加字重不能达到 4.5:1；代码/链接/附件/引用的局部底 #005FB8 与白字为 6.308159:1。主气泡后续可选 #006FE8（白字 4.730779:1），待 Leader 裁决，未实施。
- assistant Markdown 新样式由聊天调用点 useLightSurfaces 显式启用；记忆页和文件预览的共享默认保持不变。普通用户消息仍为原纯文本渲染，未改动 Markdown 触发条件。
- 暗色语义色保留原 resolve；历史未解析图标保留原实际 ARGB。固定黑底媒体、Mermaid 深底配置、重复文字语义的状态圆点及装饰轨线保留且显式标注用途。
- 本阶段截图目录 `C:/tmp/light-theme-shots-p2/before/`、`after/`；P0 单区留证另存 `after-p0/`。P0 验收：analyze 零告警，test 2710 passed / 8 skipped；13 张既有暗色金照、7 张 README 暗色截图和 24 张暗色状态图共 44/44 SHA256 一致。证据在 `after-p0-verification.json`，docs/screenshots 的 7 张原图未写入。
- README 演示数据固定在 2026-09-12，原工装的分组时钟却读取系统日期；跨午夜后出现今天/昨天漂移。临时工装仅补 sessionListNowProvider 固定为演示日期，重录后与原始改码前暗色 PNG 字节一致；生产代码和原工装均未修改。

## 阶段二 P1 结果及保留项

- 侧栏工具条固定 page、inactive 图标接 textSecondary（对 page 4.804950:1），激活图标用 statusBlueText 配 selection。空态详情保持白面，副标题/图标接 textSecondary，新建按钮仅浅色改用可读深蓝底。分栏手柄复用 divider，命中区、拖拽和导航回调不变。
- 通用 popover/dropdown 面接 card、1px cardBorder；菜单标题和普通/强调/危险文字分开校验。桌面菜单按下用 pressed；原生 ActionSheet 保留 SDK 面和遮罩，动作文字用 menuAction #004A94（既有状态调色板增强蓝），其半透明按下面另算，不只拿白卡证明 AA。
- AdaptiveMenuItem 没有禁用项 API，未新增业务状态；现有空内容消息菜单的禁用文字在实际白卡/原生操作表普通面核验。AppBackButton 和快捷导航入口只有图标，继承主色对本区页面面色达图标 3:1，源码和路由保持不变。
- 原生按钮的短暂透明反馈、遮罩与装饰阴影保留；不把任意图片作为背景或动画过渡每一帧宣称为已审计。固定反色退出 toast 的白字组合已达标，未改码；分隔线/投影明确按装饰层级处理。
- 双主题菜单按下/禁用态与普通/增强对比度、base/elevated 外壳截图另存 before/shell、after/shell；P1 改码前先拍补充基线。最终共 43 张暗态截图和 13 张既有暗色金照，56/56 SHA256 一致；证据为 `C:/tmp/light-theme-shots-p2/after-verification.json`。12 张范围外浅色金照、7 张 docs 截图及 185 个范围外 lib 文件均与任务前散列相同。
- P1 本地验收：analyze 零告警，test 2726 passed / 8 skipped，金照单独复跑 26 passed；fake gateway 15 项检查全部 PASS。浅色筛选重录曾产生范围外引导页金照差异，完整测试捕获图与原基线 SHA256 完全一致，因此恢复原基线并全量复验；引导页代码未改。

## 阶段二优先级

| 顺序 | 改法建议 | 预估影响面 |
|---|---|---|
| P0 聊天 | 蓝气泡白字/代码、可读次级文字、提示卡与工具卡轮廓 | chat_page + chat/widgets，历史/流式/输入/审批/媒体 |
| P1 外壳/导航 | 工具条、空态提示、菜单文字与浮层面分开迁移 | app/shell + app/widgets，所有宽屏及弹层入口 |
| P2 看板/用量 | 白卡轮廓、状态文字/轴标签、保留图形触摸态 | Kanban 主/详情/创建，Insights 总览/图表 |
| P3 设置 | 次级说明、地址、placeholder，子区逐一接入 | settings 全部子页/表单及 sidecar 设置 |
| P4 引导 | 表单/步骤/日志优先，hero 装饰独立评估 | onboarding 宽/窄屏、连接及安装向导 |
| 后续配套 | 按共用令牌修元数据与表单，预览反色 UI 单独验收 | 工作区、Git、技能、记忆、任务、下载、诊断、通知、项目、提示词库 |

## 2026-10-21 媒体预览与菜单色的深浅适配补修

主人实机报了三处「看起来没做深浅适配」的问题，逐一实测定位并修复：

- **聊天附件 Lightbox（`chat/widgets/chat_media_view.dart`）**：原实现整页恒黑（scaffold + 导航栏 + 白字），文档类预览（PDF/Office/音视频/文本）在**浅色主题下是「黑色导航栏 + 白色正文面」的割裂**（已实拍确认）。现按内容类型分流 chrome：**图片大图浏览仍是媒体查看器语义**（恒黑背板 + 白字，浅色主题下也保持，与桌面端看图器惯例一致、照片不与浅色背景混）；**其余按文档阅读器语义跟随主题**（导航栏底色/标题/关闭按钮/下载按钮与正文面同族）。正文承载面由 `systemBackground` 改为跟随主题页底色。
- **筛选弹层描边（`session_list/session_list_page.dart`）**：`CupertinoListSection.insetGrouped` 的 1px 描边画在**子项之下**，而 `CupertinoListTile` 的行底铺满整段宽度 ⇒ 不透明行底把描边整段盖住，只有**半透明**的选中行让描边透出来，视觉上成了「**只有被选中的那行四周有描边，没选中的都没有**」（主人报障）。深色态同病。改法：行**一律不画底**，由段统一提供卡面 + 描边（宽窄两态同口径），选中态仍由「半透明中性灰底 + 右侧勾」表达。像素级验证：修复前段的外框列在 89 行采样中命中 **0** 行，修复后连续命中 **72** 行。
- **窄屏折叠菜单项颜色（`app/widgets/adaptive_action_menu.dart` + `app/theme/light_surfaces.dart`）**：`LightSurfaces.menuAction` 此前是**写死**的 `Color(0xFF004A94)` —— 而 #004A94 恰是 `statusBlueText` 的**高对比度档**（普通档 #005FB8），于是**不开高对比度开关也显示高对比度配色**（主人报障）。现改为 `CupertinoDynamicColor`，由 `resolveFrom(context)` 按「主题 × 高对比度开关」解析；全部 37 处 `const TextStyle(color: LightSurfaces.menuAction)` 调用点同步改为解析式（动态色直接塞进 `const TextStyle` 不会自动解析，会冻结在浅色档）。浅色普通档取 **#00508F**（比 `statusBlueText` 普通档深一档）：原生 ActionSheet 的按下底是半透明 #E0E0E0 叠遮罩 ⇒ 实底 #DADADA，#005FB8 对该底仅 4.498588:1（差 0.0014 未达正文 AA），#00508F 为 5.886524:1 宽裕达标。高对比档沿用 #004A94。
- **审计工具修复（`tools/light_theme_contrast.py`）**：工具最后一次更新早于 `light_surfaces.dart` 的 getter 化与 `Color.fromRGBO` 化，**`--check-report` 整体不可用**（KeyError）。补齐：字面量/别名判定（`Color.fromRGBO(` / `Color.fromARGB(` 原被误当别名）、别名前向引用（`selectionForeground = userDetail`）、getter 形式令牌（`page` / `cardBorder` / `divider` / `sidebar` / `darkPage` 等）、`CupertinoDynamicColor` 令牌，以及「`LightSurfaces.foo(...)` 是函数调用而非颜色引用」的排除。

## 硬编码定位与代码可判定的发现

- `lib/features/chat/chat_page.dart:1697,1798`：绿色提示卡已接 tintGreen + cardBorder；正文、状态图标和关闭图标的实际组合见附录 P0。暗色 #2C2C2E 及原描边、投影保留。
- `lib/features/onboarding/widgets/onboarding_hero_motion.dart:259`：品牌图标承载面；halo 的透明渐变、轨道线在同文件 _HaloPainter 中，属无交互装饰，按设计保留/后续整体评估。
- `lib/features/chat/widgets/mermaid_block.dart:59,64,69`：`core.Color` 是 Mermaid 深色 theme 的 primaryText/text/title 配置，不是浅色 Flutter 卡片面，归配置豁免。
- 旧 secondaryText/secondaryLabel 实际浅色是 #3C3C43/153，不符合旧注释所述正文 AA；参见附录的逐背景实算。tertiaryLabel/placeholderText 更浅；输入占位属于可读信息，不能因为名字含 tertiary 就豁免。
- 主色 #007AFF 的小字号白字/蓝字也不自动满足正文 AA。阶段一保持品牌/全局按钮语义；会话搜索命中改用 statusBlueText，批量栏危险文字使用 statusRedText 的浅色分支。其他品牌动作/禁用态列入后续，不宣称会话页所有文字已全域达标。

## 框架默认面和文字（逐文件的“默认控件”引用此表）

| 控件/默认路径 | 来源及浅色语义 | 验证要点 |
|---|---|---|
| CupertinoPageScaffold / NavigationBar / SliverNavigationBar | buildCupertinoTheme.scaffold/bar → systemGroupedBackground；label 黑；primaryColor #007AFF | 会话列表局部 page 例外；导航底边/遮罩另算装饰 |
| CupertinoListSection.insetGrouped / CupertinoListTile | 分组底 systemGroupedBackground；白卡 secondarySystemGroupedBackground；separator；label / secondaryLabel；按下 systemGrey4 | 没有显式 color 的页面也使用这些语义；选中/按下不等于卡片边框 |
| CupertinoTextField | systemBackground / 默认输入框装饰，placeholderText，label；边框与光标另算 | 默认 placeholder 的 AA 数字见附录 |
| CupertinoSearchTextField | tertiarySystemFill 透明面，secondaryLabel 占位和图标 | 会话列表已显式白底+placeholder；其余按各页面底合成 |
| CupertinoButton / filled / AccessibleButton | primaryColor 动作字或按钮底，primaryContrastingColor 白字；禁用色由框架控制 | 普通动作正文、白字按钮、图标和禁用态分开验收 |
| CupertinoAlertDialog / CupertinoActionSheet / ModalPopup | SDK 动态背景/模糊/遮罩；label、destructiveRed、primaryColor | 透明背景/模糊须结合下层截图，不能静态保证所有任意下层 AA |

## 逐页、逐组件源色清单

每个表包含该文件的所有可解析显式颜色（含定义、分支和透明度别名），同色同用途合并行号。无显式颜色的 UI 文件仍列出默认控件；纯逻辑文件也单列覆盖清单。表内“复用色”按普通文字做保守的承载面参考，具体反色或非文本用途依局部组合/说明判定。

### P0 聊天

阶段二已接入局部 page/bar、可读次级文字及状态色、输入框/工具/审批/注入卡/媒体占位轮廓和选中按下面。assistant 正文仍直接落在页面底；共享 Markdown 默认不影响记忆和文件预览。用户主蓝气泡是 Leader 授权保留项；代码、链接、附件和引用局部底单独达 AA。确认弹窗仅调整浅色动作文字，保留 SDK 暗色默认。完整组合与限制见附录 P0。

#### `lib/features/chat/chat_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L263 | 面 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L319,1287,1505,1764,1869 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L320,331 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.725943 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L330,1267,1384 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L449,450 | 复用色；按承载面判级 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.userDetail` L451 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L467,741,749,772,830,838,866,916,935 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L722,810,1332 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L723,811,1169,1233,1334,1443,1539,1602,1717,1813 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L730,818,1348 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L781,875,1560 | 文字 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintWarning` L1164,1595 | 面 | #FFF4E8 | 1.031935 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemOrange @ 0.12` L1165 | 暗色保留豁免 | #FF9500 / α=0.120000 | 1.090369 | 1.101384 | 1.142773 | 暗色保留豁免 |
| `statusOrangeText` L1182,1264,1616 | 文字 | #B25000 | 4.642655 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L1183 | 暗色保留豁免 | #FF9500 | 1.964036 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.tintClarification` L1228 | 面 | #F3F2FF | 1.010519 | 1.107841 | 18.955790 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemIndigo @ 0.12` L1229 | 暗色保留豁免 | #5856D6 / α=0.120000 | 1.173775 | 1.182180 | 1.073074 | 暗色保留豁免 |
| `CupertinoColors.systemIndigo` L1244 | 图标/图形 | #5856D6 | 5.046579 | 5.649619 | 3.717065 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemIndigo` L1252 | 文字 | #5856D6 | 5.046579 | 5.649619 | 3.717065 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L1268,1288,1385 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.placeholderText` L1349 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698090 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.selection` L1436 | 面 | #E0ECFF | 1.065117 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBlue @ 0.1` L1437 | 暗色保留豁免 | #007AFF / α=0.100000 | 1.130608 | 1.137765 | 1.068037 | 暗色保留豁免 |
| `CupertinoColors.systemBlue @ 0.2` L1444 | 暗色保留豁免 | #007AFF / α=0.200000 | 1.282587 | 1.300076 | 1.181780 | 暗色保留豁免 |
| `statusBlueText` L1456 | 图标/图形 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L1457,1471,1489 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L1470,1488 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L1506,1765,1870 | 暗色保留豁免 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.tintError` L1532 | 面 | #FFF4F3 | 1.038810 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemRed @ 0.1` L1533 | 暗色保留豁免 | #FF3B30 / α=0.100000 | 1.135989 | 1.142997 | 1.070337 | 暗色保留豁免 |
| `CupertinoColors.systemRed @ 0.2` L1540 | 暗色保留豁免 | #FF3B30 / α=0.200000 | 1.293398 | 1.310797 | 1.196593 | 暗色保留豁免 |
| `CupertinoColors.systemRed` L1550,1571 | 图标/图形 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow @ 0.15` L1596 | 暗色保留豁免 | #FFCC00 / α=0.150000 | 1.055867 | 1.071510 | 1.275209 | 暗色保留豁免 |
| `CupertinoColors.systemYellow @ 0.25` L1603 | 暗色保留豁免 | #FFCC00 / α=0.250000 | 1.093031 | 1.120768 | 1.689856 | 暗色保留豁免 |
| `CupertinoColors.systemBrown` L1617 | 暗色保留豁免 | #A2845E | 3.127238 | 3.500926 | 5.998413 | 暗色保留豁免 |
| `Color(0xFF2C2C2E)` L1697,1798 | 暗色保留豁免 | #2C2C2E | 12.449050 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `LightSurfaces.tintGreen` L1697,1798 | 面/复用 | #F0FAF2 | 1.048138 | 1.068080 | 19.661457 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white @ 0.92` L1699,1800 | 暗色保留豁免 | #FFFFFF / α=0.920000 | 1.109629 | 1.000000 | 17.551417 | 暗色保留豁免 |
| `CupertinoColors.label` L1700,1801 | 文字/复用 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey @ 0.18` L1714,1810 | 暗色保留豁免 | #8E8E93 / α=0.180000 | 1.178452 | 1.195123 | 1.201993 | 暗色保留豁免 |
| `CupertinoColors.black` L1722,1818 | 装饰线/投影豁免 | #000000 | 18.758462 | 21.000000 | 1.000000 | 装饰线/投影豁免 |
| `statusGreenText` L1737,1833 | 图标/图形 | #1E7A34 | 4.823958 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L1738,1834 | 暗色保留豁免 | #34C759 | 1.983000 | 2.219959 | 9.459636 | 暗色保留豁免 |

#### `lib/features/chat/widgets/attachment_pending_bar.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L35,109 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L36,110 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L114 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L115 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L119 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L120 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L176 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L177 | 暗色保留豁免 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 暗色保留豁免 |

#### `lib/features/chat/widgets/chat_input_bar.dart`

默认控件：`CupertinoTextField`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L653,697 | 文字 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L654 | 文字 | #3C3C43 / α=0.741176 | 4.725943 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L660,690 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L750 | 面 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L751 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.divider` L860 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey4` L861 | 暗色保留豁免 | #D1D1D6 | 1.359087 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L901,920,1316,1335 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L902,921,1317,1336 | 暗色保留豁免 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.card` L987,1225 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L989,1227 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L1000,1237 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L1094,1394 | 图标/图形 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L1107,1125,1407,1425 | 图标/图形 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/chat_media_view.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L256,1571,1610 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L257,1572,1611 | 暗色保留豁免 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L263,1617 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey4` L264,1618,1690 | 暗色保留豁免 | #D1D1D6 | 1.359087 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L296,900,1635 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L297,314,1636,1653 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L313,931,1652,1666 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L331,1714 | 面 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `theme.primaryColor` L332,1715 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `CupertinoColors.white` L347,913,1745 | 文字 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L774,952,1041,1373 | 复用色；按承载面判级 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusBlueText` L775 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L802,812,897,1424,1431 | 图标/图形 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L861 | 面 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkPage` L862 | 暗色保留豁免 | #1C1C1E | 15.198584 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `CupertinoColors.systemGrey` L901 | 暗色保留豁免 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `CupertinoColors.label` L914,1701 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L928,1252 | 文字 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 固定黑底媒体文字；实际组合见 P0/media inverse secondary |
| `secondaryText` L932 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.725943 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.7` L949 | 面/复用 | #000000 / α=0.700000 | 8.092986 | 8.520033 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L953 | 复用色；按承载面判级 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.black` L957 | 面 | #000000 | 18.758462 | 21.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiaryLabel` L1667 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698090 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.pressed` L1689 | 面 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |

#### `lib/features/chat/widgets/chat_message_list.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L243,278 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L2937 | 复用色；按承载面判级 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemGroupedBackground` L2939 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L2944 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L2946 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.12` L2964 | 装饰线/投影豁免 | #000000 / α=0.120000 | 1.311586 | 1.315107 | 1.000000 | 装饰线/投影豁免 |
| `statusRedText` L3137 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L3138 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L3147,3158 | 复用色；按承载面判级 | #B25000 | 4.642655 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L3148,3159 | 暗色保留豁免 | #FF9500 | 1.964036 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L3169 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L3170,3269 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusYellowText` L3181 | 复用色；按承载面判级 | #8A6100 | 4.948767 | 5.540119 | 3.790532 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow` L3182 | 暗色保留豁免 | #FFCC00 | 1.350584 | 1.511972 | 13.889146 | 暗色保留豁免 |
| `statusGreenText` L3195,3209 | 复用色；按承载面判级 | #1E7A34 | 4.823958 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L3196,3210 | 暗色保留豁免 | #34C759 | 1.983000 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L3268 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/chat_outline_sheet.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L186 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L187 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.divider` L193 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L194,221 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.12` L200 | 装饰线/投影豁免 | #000000 / α=0.120000 | 1.311586 | 1.315107 | 1.000000 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L220 | 面 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L258 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L259 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `CupertinoColors.label` L263 | 文字/复用 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L280 | 面 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L281 | 暗色保留豁免 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L295 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L296 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/chat/widgets/collapsible_process_capsule.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L94,179 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L95,180 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.725943 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `Color(0x1F000000)` L101 | 复用色；按承载面判级 | #000000 / α=0.121569 | 1.316495 | 1.320084 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0x26FFFFFF)` L102 | 其他主题定义豁免 | #FFFFFF / α=0.149020 | 1.017283 | 1.000000 | 1.387647 | 其他主题定义豁免 |
| `statusBlueText` L121,212 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L193 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L194 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698090 | 1.725396 | 1.121334 | 暗色保留豁免 |

#### `lib/features/chat/widgets/composer_meta_chips.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L278,422 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L279,423 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L642 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF2C2C2E)` L643 | 暗色保留豁免 | #2C2C2E | 12.449050 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `Color(0xFFE8B9B5)` L651 | 复用色；按承载面判级 | #E8B9B5 | 1.558273 | 1.744478 | 12.037985 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF5A2A2A)` L652 | 暗色保留豁免 | #5A2A2A | 10.425126 | 11.670874 | 1.799351 | 暗色保留豁免 |
| `Color(0xFFB4B9C4)` L657 | 复用色；按承载面判级 | #B4B9C4 | 1.756846 | 1.966780 | 10.677349 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF5A5A5E)` L658 | 暗色保留豁免 | #5A5A5E | 6.132565 | 6.865375 | 3.058828 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L663 | 复用色；按承载面判级 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L664 | 暗色保留豁免 | #3A3A3C | 10.137630 | 11.349024 | 1.850379 | 暗色保留豁免 |
| `Color(0xFF8A8A8F)` L669 | 复用色；按承载面判级 | #8A8A8F | 3.068779 | 3.435481 | 6.112680 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFB3261E)` L677 | 复用色；按承载面判级 | #B3261E | 5.838785 | 6.536489 | 3.212734 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L678 | 暗色保留豁免 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 暗色保留豁免 |
| `Color(0xFF1C1C1E)` L685 | 复用色；按承载面判级 | #1C1C1E | 15.198584 | 17.014735 | 1.234224 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFEBEBF0)` L685 | 复用色；按承载面判级 | #EBEBF0 | 1.061358 | 1.188185 | 17.674020 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/chat/widgets/context_window_indicator.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.white @ 0.12` L82 | 暗色保留豁免 | #FFFFFF / α=0.120000 | 1.013903 | 1.000000 | 1.268235 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.12` L83 | 复用色；按承载面判级 | #000000 / α=0.120000 | 1.311586 | 1.315107 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.92` L85 | 暗色保留豁免 | #FFFFFF / α=0.920000 | 1.109629 | 1.000000 | 17.551417 | 暗色保留豁免 |
| `CupertinoColors.black @ 0.82` L86 | 复用色；按承载面判级 | #000000 / α=0.820000 | 12.550671 | 13.598961 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L93 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L94 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L99 | 复用色；按承载面判级 | #B25000 | 4.642655 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L100 | 暗色保留豁免 | #FF9500 | 1.964036 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `CupertinoColors.label` L108 | 文字/复用 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L111 | 文字/复用 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L112 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/chat/widgets/context_window_popover.dart`

默认控件：`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L517,766,1493,1511 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L518,767,1317,1363,1494,1512 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L761,1576,1581 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L762,1577,1582 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L1014,1075,1191,1249 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L1015,1076,1192,1250 | 暗色保留豁免 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.label` L1034,1099,1206 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1316 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1362 | 文字/复用 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L1367 | 复用色；按承载面判级 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L1421 | 复用色；按承载面判级 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey4` L1422 | 暗色保留豁免 | #D1D1D6 | 1.359087 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L1426 | 面/复用 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeBlue` L1427 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusRedText` L1499 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L1500,1566 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L1505 | 复用色；按承载面判级 | #B25000 | 4.642655 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L1506,1572 | 暗色保留豁免 | #FF9500 | 1.964036 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.tintError` L1536 | 面 | #FFF4F3 | 1.038810 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemRed @ 0.12` L1537 | 暗色保留豁免 | #FF3B30 / α=0.120000 | 1.165678 | 1.174456 | 1.090290 | 暗色保留豁免 |
| `LightSurfaces.tintWarning` L1544 | 面 | #FFF4E8 | 1.031935 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemOrange @ 0.12` L1545 | 暗色保留豁免 | #FF9500 / α=0.120000 | 1.090369 | 1.101384 | 1.142773 | 暗色保留豁免 |
| `LightSurfaces.page` L1551,1556 | 面 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L1552,1557 | 暗色保留豁免 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `statusRedText` L1565 | 装饰线/投影豁免 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 装饰线/投影豁免 |
| `statusOrangeText` L1571 | 装饰线/投影豁免 | #B25000 | 4.642655 | 5.197428 | 4.040460 | 装饰线/投影豁免 |

#### `lib/features/chat/widgets/injected_notice_card.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.cardBorder` L38 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L39 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.label` L41 | 文字/复用 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L44 | 文字/复用 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L45 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L54 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L55 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `LightSurfaces.tintError` L60 | 面/复用 | #FFF4F3 | 1.038810 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L60 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemRed @ 0.08` L62 | 暗色保留豁免 | #FF3B30 / α=0.080000 | 1.107158 | 1.112530 | 1.052766 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemBackground` L65 | 面/复用 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L69 | 面/复用 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L70 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |

#### `lib/features/chat/widgets/markdown_styles.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L125,604 | 文字/复用 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L131 | 文字/复用 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.link` L132 | 文字/复用 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 非聊天共享默认/暗色分支；聊天浅色已显式传入令牌 |
| `LightSurfaces.card` L134,609 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L135,610 | 面/复用 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 非聊天共享默认/暗色分支；聊天浅色已显式传入令牌 |
| `LightSurfaces.divider` L137 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L138 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `LightSurfaces.cardBorder` L140,615 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `statusBlueText` L210 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L210 | 文字 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L227 | 复用色；按承载面判级 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.userDetail` L245,645 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L277,284,293 | 面 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `white @ 0.22` L278 | 暗色保留豁免 | #FFFFFF / α=0.220000 | 1.025579 | 1.000000 | 1.793638 | 暗色保留豁免 |
| `white @ 0.15` L285 | 暗色保留豁免 | #FFFFFF / α=0.150000 | 1.017397 | 1.000000 | 1.392133 | 暗色保留豁免 |
| `white @ 0.12` L294 | 暗色保留豁免 | #FFFFFF / α=0.120000 | 1.013903 | 1.000000 | 1.268235 | 暗色保留豁免 |
| `white @ 0.4` L307 | 装饰线/投影豁免 | #FFFFFF / α=0.400000 | 1.046805 | 1.000000 | 3.657366 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey5` L381 | 复用色；按承载面判级 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 非聊天共享默认/暗色分支；聊天浅色已显式传入令牌 |
| `CupertinoColors.label` L391 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0x00000000)` L396 | 文字/复用 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue` L490 | 复用色；按承载面判级 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.22` L646 | 暗色保留豁免 | #FFFFFF / α=0.220000 | 1.025579 | 1.000000 | 1.793638 | 暗色保留豁免 |
| `CupertinoColors.white` L653 | 文字 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/chat/widgets/mermaid_block.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `core.Color(0x00000000)` L57 | 图表深色配置豁免 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 图表深色配置豁免 |
| `core.Color(0xff2c2c2e)` L58,66,70 | 图表深色配置豁免 | #2C2C2E | 12.449050 | 13.936646 | 1.506819 | 图表深色配置豁免 |
| `core.Color(0xffffffff)` L59,64,69 | 图表深色配置豁免 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 图表深色配置豁免 |
| `core.Color(0xff48484a)` L60,65,68 | 图表深色配置豁免 | #48484A | 8.150991 | 9.124992 | 2.301372 | 图表深色配置豁免 |
| `core.Color(0xff3a3a3c)` L61 | 图表深色配置豁免 | #3A3A3C | 10.137630 | 11.349024 | 1.850379 | 图表深色配置豁免 |
| `core.Color(0xff8e8e93)` L62,63 | 图表深色配置豁免 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 图表深色配置豁免 |
| `core.Color(0xff1c1c1e)` L67 | 图表深色配置豁免 | #1C1C1E | 15.198584 | 17.014735 | 1.234224 | 图表深色配置豁免 |
| `CupertinoColors.label` L119 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L271 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L272,283 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L282 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/mermaid_fullscreen_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L34 | 面/复用 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF1C1C1E)` L35 | 暗色保留豁免 | #1C1C1E | 15.198584 | 17.014735 | 1.234224 | 暗色保留豁免 |

#### `lib/features/chat/widgets/message_action_menu.dart`

默认控件：`CupertinoActionSheet`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.userDetail` L80,350 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L83,358 | 文字 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L86,95 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/message_bubble.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.activeBlue` L148 | 面 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white` L332 | 文字 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L418,575 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L510 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L511 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L562 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L563 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L566 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |

#### `lib/features/chat/widgets/message_highlight.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemYellow @ 0.28` L69 | 面 | #FFCC00 / α=0.280000 | 1.104131 | 1.135763 | 1.858581 | 装饰面豁免；分层强弱见三向值 |

#### `lib/features/chat/widgets/perf_monitor_panel.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L242 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L243 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusOrangeText` L249 | 复用色；按承载面判级 | #B25000 | 4.642655 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L250 | 暗色保留豁免 | #FF9500 | 1.964036 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L255,274,523 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L256,275,524 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/chat/widgets/selected_context_card.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.cardBorder` L29 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L30 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L34 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L35 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L39 | 文字/复用 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L40 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusBlueText` L44 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L45 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |

#### `lib/features/chat/widgets/selection_chips.dart`

默认控件：`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L55 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L56,95 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L84,211 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L85 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L89 | 面/复用 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L90 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L94 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L138 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L139 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `LightSurfaces.card` L209 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.placeholder` L220 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L233,240 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/steer_banner.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF2C2C2E)` L33,102 | 暗色保留豁免 | #2C2C2E | 12.449050 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `LightSurfaces.card` L36,105 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L37,106 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L43,112 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L44,113 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L56,125 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L57,72,126,145,161 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.725943 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L71,144,160 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selection` L175 | 面 | #E0ECFF | 1.065117 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeBlue @ 0.12` L176 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159188 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `statusBlueText` L187 | 文字 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L188 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |

#### `lib/features/chat/widgets/tool_call_card.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L91 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L92,489,528 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusBlueText` L97 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L98,160,260,293,475 | 暗色保留豁免 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusGreenText` L102 | 复用色；按承载面判级 | #1E7A34 | 4.823958 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L103,494 | 暗色保留豁免 | #34C759 | 1.983000 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `CupertinoColors.systemRed @ 0.08` L106 | 面/复用 | #FF3B30 / α=0.080000 | 1.107158 | 1.112530 | 1.052766 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeBlue @ 0.08` L108 | 面/复用 | #007AFF / α=0.080000 | 1.102881 | 1.108385 | 1.052763 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemTeal @ 0.08` L111 | 面/复用 | #5AC8FA / α=0.080000 | 1.044827 | 1.052306 | 1.093510 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.tintError` L132 | 面 | #FFF4F3 | 1.038810 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L134,446 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.tintGreen` L135 | 面 | #F0FAF2 | 1.048138 | 1.068080 | 19.661457 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L139,453,866 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `statusBlueText` L159,259,292,474 | 图标/图形 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L193,211,271,304,539 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L194,212,225,272,305,540,553,850 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L224,552 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L327 | 面 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey4` L328,454 | 暗色保留豁免 | #D1D1D6 | 1.359087 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.label` L347,436,889 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey6` L447 | 暗色保留豁免 | #F2F2F7 | 1.003248 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `statusRedText` L488 | 图标/图形 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L493 | 图标/图形 | #1E7A34 | 4.823958 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L527 | 文字 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L849 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintClarification` L860 | 面 | #F3F2FF | 1.010519 | 1.107841 | 18.955790 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemPurple @ 0.08` L861 | 暗色保留豁免 | #AF52DE / α=0.080000 | 1.098180 | 1.103836 | 1.055732 | 暗色保留豁免 |
| `CupertinoColors.systemPurple` L881 | 图标/图形 | #AF52DE | 3.689346 | 4.130204 | 5.084495 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/chat/widgets/user_attachment_block.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.white` L482 | 图标/图形 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L491 | 文字 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.72` L501 | 文字 | #FFFFFF / α=0.720000 | 1.085200 | 1.000000 | 10.539996 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.18` L512 | 复用色；按承载面判级 | #FFFFFF / α=0.180000 | 1.020899 | 1.000000 | 1.544236 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/chat/chat_controller.dart`、`lib/features/chat/chat_diff_merge.dart`、`lib/features/chat/chat_draft_provider.dart`、`lib/features/chat/chat_models.dart`、`lib/features/chat/chat_providers.dart`、`lib/features/chat/chat_server_api.dart`、`lib/features/chat/chat_session_channel.dart`、`lib/features/chat/chat_state.dart`、`lib/features/chat/pending_attachments_provider.dart`、`lib/features/chat/selection_provider.dart`、`lib/features/chat/widgets/chat_media_parser.dart`、`lib/features/chat/widgets/chat_text_selection.dart`、`lib/features/chat/widgets/media_kind_icons.dart`。

### P1 自适应外壳

侧栏工具条接 page、textSecondary、selection，空态详情使用白面和可读次级文字，新建按钮使用局部状态蓝。分栏手柄及工具条结构线复用 divider。固定反色退出 toast 保持原样，附录 P1 给出实算。导航/拖拽回调、外壳布局和所有暗色分支不变。

#### `lib/app/shell/adaptive_shell.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.black @ 0.82` L226 | 面 | #000000 / α=0.820000 | 12.580032 | 13.598961 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.black @ 0.2` L230 | 装饰线/投影豁免 | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰线/投影豁免 |
| `CupertinoColors.white` L239 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.sidebar` L281 | 面 | #E6E6E6 | 1.118473 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkSidebar` L282 | 暗色保留豁免 | #1B1B1B | 15.435821 | 17.224383 | 1.219202 | 暗色保留豁免 |

#### `lib/app/shell/empty_detail_pane.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`。

参考页面 P=#FFFFFF；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L25 | 面 | #FFFFFF | 1.000000 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L40 | 图标/图形 | #6A6A6F | 5.379116 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L41 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.725396 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.label` L51 | 文字 | #000000 | 21.000000 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L65 | 文字 | #6A6A6F | 5.379116 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L66 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.438200 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusBlueText` L72 | 面 | #005FB8 | 6.308159 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |

#### `lib/app/shell/sidebar_brand_bar.dart`

默认控件：`CupertinoSearchTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusBlueText` L69 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L70 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L73 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L74 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L120 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L123 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.tertiarySystemFill` L128 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.placeholder` L137 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L141 | 文字 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF1C1C1E)` L168 | 文字 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L169 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `Color(0xFF8E8E93)` L186 | 文字 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.placeholderText` L187 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.sidebar` L260 | 面 | #E6E6E6 | 1.118473 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkSidebar` L261 | 暗色保留豁免 | #1B1B1B | 15.435821 | 17.224383 | 1.219202 | 暗色保留豁免 |

#### `lib/app/shell/sidebar_hover_tip.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xE61C1C1E)` L63 | 面 | #1C1C1E / α=0.901961 | 11.632827 | 12.748701 | 1.199109 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFE5E5EA)` L66 | 面 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF48484A)` L67 | 暗色保留豁免 | #48484A | 8.177462 | 9.124992 | 2.301372 | 暗色保留豁免 |
| `CupertinoColors.white` L77 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L78 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/app/shell/sidebar_secondary_tools.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusBlueText` L54 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L55 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L58 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L59 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L63 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.transparent` L169 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/shell/sidebar_status_bar.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.sidebar` L70 | 面/复用 | #E6E6E6 | 1.118473 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkSidebar` L71 | 暗色保留豁免 | #1B1B1B | 15.435821 | 17.224383 | 1.219202 | 暗色保留豁免 |
| `Color(0xFFE8F6EC)` L141 | 面/复用 | #E8F6EC | 1.000282 | 1.115556 | 18.824694 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF2C2C2E)` L142,189,267 | 暗色保留豁免 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `Color(0xFF1E7B3C)` L146 | 文字/复用 | #1E7B3C | 4.760018 | 5.311566 | 3.953636 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF34C759)` L147 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `Color(0xFF34C759)` L161 | 面 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFFFEFEE)` L188 | 面/复用 | #FFEFEE | 1.000735 | 1.115052 | 18.833210 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFB3261E)` L193 | 文字/复用 | #B3261E | 5.857747 | 6.536489 | 3.212734 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF453A)` L194,229 | 暗色保留豁免 | #FF453A | 3.052940 | 3.406687 | 6.164346 | 暗色保留豁免 |
| `Color(0xFFFF3B30)` L208 | 面 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFB3261E)` L228 | 复用色；按承载面判级 | #B3261E | 5.857747 | 6.536489 | 3.212734 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFEBEBF0)` L266 | 面/复用 | #EBEBF0 | 1.064805 | 1.188185 | 17.674020 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF4A4A4F)` L271 | 文字/复用 | #4A4A4F | 7.895415 | 8.810264 | 2.383584 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFC4C4C9)` L272 | 暗色保留豁免 | #C4C4C9 | 1.557054 | 1.737471 | 12.086533 | 暗色保留豁免 |

#### `lib/app/shell/sidebar_tools_list.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusBlueText` L50 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L51 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L54 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L55 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L59 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.sidebar` L130 | 面 | #E6E6E6 | 1.118473 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkSidebar` L131 | 暗色保留豁免 | #1B1B1B | 15.435821 | 17.224383 | 1.219202 | 暗色保留豁免 |
| `CupertinoColors.transparent` L207 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF1C1C1E)` L235 | 文字 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L236 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `Color(0xFFE5E5EA)` L252 | 面 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF2C2C2E)` L253 | 暗色保留豁免 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 暗色保留豁免 |

#### `lib/app/shell/sidebar_utility_toolbar.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusBlueText` L38 | 复用色；按承载面判级 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L39 | 复用色；按承载面判级 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L42 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L43 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L93 | 复用色；按承载面判级 | #787880 / α=0.160000 | 1.195230 | 1.208629 | 1.133049 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L95 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectionForeground` L106 | 图标/图形 | #005FB8 | 5.634827 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.sidebar` L131 | 面 | #E6E6E6 | 1.114853 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkSidebar` L132 | 暗色保留豁免 | #1B1B1B | 15.385854 | 17.224383 | 1.219202 | 暗色保留豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/shell/android_back_interceptor.dart`、`lib/app/shell/session_sidebar.dart`、`lib/app/shell/sidebar_nav_order.dart`、`lib/app/shell/sidebar_resize_handle.dart`、`lib/app/shell/sidebar_utility_item.dart`。

### P1 通用导航、菜单和浮层

通用 popover/dropdown 接白面与 cardBorder，标题、副标、普通/强调/危险动作文字和按下面完成局部核验。原生操作表用更深动作蓝适配半透明按下面，保留原生面、遮罩和行为；阴影只作装饰豁免。导航代理本身无独立低对比文字，返回/下拉图标继承色按 3:1 验收。

#### `lib/app/widgets/adaptive_action_menu.dart`

默认控件：`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.placeholder` L149 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L150 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `statusRedText` L155 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.destructiveRed` L156 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusBlueText` L161 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L162 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `CupertinoColors.label` L164 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L167 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L168,442 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.divider` L217 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L218 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L441,467 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L497 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L498,512 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/app/widgets/adaptive_popover.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0x00000000)` L437 | 面 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L479 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L480 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L489 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey4` L490 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.systemGrey3 @ 0.5` L496 | 装饰线/投影豁免 | #C7C7CC / α=0.500000 | 1.218767 | 1.281204 | 3.531785 | 装饰线/投影豁免 |

#### `lib/app/widgets/adaptive_sliver_navigation_bar.dart`

默认控件：`CupertinoNavigationBar`。

无额外显式颜色，继承上表语义。

#### `lib/app/widgets/app_scrollbar.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color.fromRGBO(60,60,67,0.32)` L54 | 复用色；按承载面判级 | #3C3C43 / α=0.320000 | 1.774288 | 1.804708 | 1.133760 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromRGBO(60,60,67,0.55)` L57 | 复用色；按承载面判级 | #3C3C43 / α=0.550000 | 2.922599 | 3.032230 | 1.308735 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromRGBO(235,235,245,0.30)` L60 | 复用色；按承载面判级 | #EBEBF5 / α=0.300000 | 1.017842 | 1.050847 | 2.250320 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromRGBO(235,235,245,0.42)` L63 | 复用色；按承载面判级 | #EBEBF5 / α=0.420000 | 1.025099 | 1.072183 | 3.495997 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/widgets/hermes_dialog.dart`

默认控件：`CupertinoButton`、`CupertinoAlertDialog`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L285,306 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L338 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L339 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.systemRed` L411 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `theme.primaryColor` L412 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L430,433 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/widgets/icon_hover_disk.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.selectedSurface` L122 | 复用色；按承载面判级 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/widgets/large_title_sliver_header.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L159 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/app/widgets/menu_row.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color.fromRGBO(120,120,128,0.24)` L10 | 面/复用 | #787880 / α=0.240000 | 1.313522 | 1.335938 | 1.244945 | 装饰面豁免；分层强弱见三向值 |
| `Color.fromRGBO(120,120,128,0.14)` L11 | 面/复用 | #787880 / α=0.140000 | 1.168410 | 1.179434 | 1.111094 | 装饰面豁免；分层强弱见三向值 |
| `Color.fromRGBO(120,120,128,0.32)` L12 | 面/复用 | #787880 / α=0.320000 | 1.448015 | 1.482468 | 1.398295 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.pressed` L109 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L116 | 复用色；按承载面判级 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.hoverSurface` L123 | 复用色；按承载面判级 | #787880 / α=0.100000 | 1.116530 | 1.123899 | 1.073930 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L129 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBackground` L130 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L140 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L141 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/app/widgets/picker_menu_content.dart`

默认控件：`CupertinoSearchTextField`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L69 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L70,235,440 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusBlueText` L129 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L130,157,227 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `LightSurfaces.selectionForeground` L156 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L159,427 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selectionForeground` L226 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L231 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L234,439 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L400 | 面/复用 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF2C2C2E)` L401 | 暗色保留豁免 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L405 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L406 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.placeholder` L433 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L434 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |

#### `lib/app/widgets/popover_dropdown.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L45 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L46 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L50 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L51 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.systemGrey3 @ 0.35` L62 | 装饰线/投影豁免 | #C7C7CC / α=0.350000 | 1.146727 | 1.186447 | 2.217171 | 装饰线/投影豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/widgets/app_refresh_control.dart`、`lib/app/widgets/cupertino_popover.dart`、`lib/app/widgets/focus_gated_ticker_mode.dart`、`lib/app/widgets/hermes_page_route.dart`、`lib/app/widgets/menu_metrics.dart`、`lib/app/widgets/narrow_navigation_dropdown.dart`、`lib/app/widgets/nav_bar_hairline.dart`、`lib/app/widgets/popover_anchor.dart`、`lib/app/widgets/popover_menu_shell.dart`、`lib/app/widgets/reading_width_box.dart`。

### P2 看板

卡片 secondarySystemBackground 与旧分组页面底同为浅灰，不能形成卡片层级；灰色描边只提供弱轮廓。顶部选中标签为蓝底白字，详情/元数据 secondaryText，failed 状态仍返回 systemRed。建议白卡+轮廓、可读状态文字、选择状态和详情空占位一起迁移；预计涉及看板列/卡片/详情/创建弹层，不涉及 WS 或排序逻辑。

#### `lib/features/kanban/kanban_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF111113)` L26 | 复用色；按承载面判级 | #111113 | 16.902364 | 18.860856 | 1.113417 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L27 | 装饰线/投影豁免 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 装饰线/投影豁免 |
| `Color(0xFF2C2C2E)` L28 | 面/复用 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF4A3F14)` L30 | 面/复用 | #4A3F14 | 9.352299 | 10.435958 | 2.012273 | 装饰面豁免；分层强弱见三向值 |
| `statusGreyText` L98 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L100,1067,1548,1552 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L104 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L108 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusTealText` L119,120 | 复用色；按承载面判级 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L123 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusRedText` L124,125 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L128 | 复用色；按承载面判级 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L129 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemPurple` L132,133 | 复用色；按承载面判级 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L272,280 | 复用色；按承载面判级 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L274,1070 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L275,1468 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.activeBlue` L277 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L281 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusBlueText` L294 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L295,299,762,845,981 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.black` L298 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L310 | 面 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L328,741,1462,1565,1575 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L362 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L404,447,488,776,1287 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L405,448,489,777,1288 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L422,463,616,636,790,978,1038,1136,1161,1386,1421,1490 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L423,464,617,637,791,979,1039,1137,1162,1387,1422,1491 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `statusRedText` L506,1307 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L551,1261 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.pressed` L733 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L733,1561,1573 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L734 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.tintWarning` L820 | 面 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `statusOrangeText` L833 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow` L834 | 暗色保留豁免 | #FFCC00 | 1.354970 | 1.511972 | 13.889146 | 暗色保留豁免 |
| `LightSurfaces.page` L955,1007,1088,1114,1546,1547 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.darkPage` L956,1008,1089,1115 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.divider` L960,1012,1093,1119 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L1070,1469,1551 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.placeholder` L1583 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/kanban/kanban_api.dart`、`lib/features/kanban/kanban_providers.dart`。

### P2 洞察/用量

分组统计卡继承白卡，secondaryText 用于时间、说明及坐标轴；蓝色柱本身可按非文本图形判级，但轴标签仍须正文 AA。#004999 是柱图触摸态，属于数据图形，不能当浅色卡片替换。建议卡片轮廓及轴标签优先，保留现有柱形高亮；预计影响统计总览、模型列表及日用量图。

#### `lib/features/insights/insights_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L86,87 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L124 | 面/复用 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkPage` L125 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.divider` L129 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L130,594 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L135,514,953 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L137,519,593,958 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L249,267,495,687,784,1015,1178 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L250,268,496,582,688,785,946,1179 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemGroupedBackground` L515,954 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.label` L530,613,989 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L581,945 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L710,763 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L712,765 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L729 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L736 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L912,1129 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L1027 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF007AFF)` L1029 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `Color(0xFF004999)` L1128 | 图标/图形 | #004999 | 7.799167 | 8.702863 | 2.412999 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L1258 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/insights/insights_api.dart`、`lib/features/insights/insights_providers.dart`。

### P3 设置及全部子区

settings_page / settings_subpages / profile / extensions / MCP / auxiliary_models / webui_sidecar 都继承分组面。先修服务器地址、说明、辅助模型元数据以及输入框 placeholder；各状态色虽有 AA 版，仍要核对 resolve 与真实背景。新增面令牌按子区接入，影响全部设置表单、子页和弹层；不改持久化键或文案。

#### `lib/features/settings/auxiliary_models_section.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L88,133,272,343 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L89,134,273,344 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L143 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L144 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.menuAction` L162 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L165 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/settings/extensions_section.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L82,124,390 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L83,125,391 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `statusGreenText` L121 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L213 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L216,446 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L400 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L401 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |

#### `lib/features/settings/mcp_section.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L111 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L111 | 文字 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L201 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L204,502 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L556,580 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L557,581 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |

#### `lib/features/settings/settings_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L388 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkPage` L390 | 面 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L396 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L397 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L649,1558,2066,2093,2120,2133,2487,2765 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L650,1508,1559,2067,2094,2121,2134,2488 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L660,885,903,918,934,953,971,989,1007,1025 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L661,886,904,919,935,954,972,990,1008,1026 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.menuAction` L1265,1599,1706,1853,2594,2630 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L1366 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1507 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L1571 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1594,1709,1861,2158,2443 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L1595 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L1600 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusRedText` L1633,2431,2469 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF3B30)` L1634,2432,2444,2470 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `LightSurfaces.tintError` L2408 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.destructiveRed` L2409,2418 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `LightSurfaces.divider` L2417 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `secondaryText` L2766 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |

#### `lib/features/settings/settings_subpages.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoNavigationBar`。

无额外显式颜色，继承上表语义。

#### `lib/features/settings/settings_surfaces.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoButton`、`CupertinoAlertDialog`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L25,26,594 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L29 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `secondaryText` L69,128 | 文字 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L157,167 | 图标/图形 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L177 | 复用色；按承载面判级 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L182 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L183 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.white` L188 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.black` L189 | 其他主题定义豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 其他主题定义豁免 |
| `Color(0x33000000)` L194 | 装饰线/投影豁免 | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰线/投影豁免 |
| `Color(0x33FFFFFF)` L195 | 其他主题定义豁免 | #FFFFFF / α=0.200000 | 1.022544 | 1.000000 | 1.662095 | 其他主题定义豁免 |
| `LightSurfaces.placeholder` L208 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L209 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L217,533,598 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L218,536 | 复用色；按承载面判级 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.black` L286,289 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L287 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemFill` L290 | 复用色；按承载面判级 | #787880 / α=0.156863 | 1.191278 | 1.203984 | 1.129452 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L291,292,333 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.tertiarySystemFill` L332 | 复用色；按承载面判级 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L361 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L362 | 文字/复用 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L488 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L489 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L535 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L543 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L571,586,598,612 | 复用色；按承载面判级 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L595 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.cardBorder` L596 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L597 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L599 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L606 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemGroupedBackground` L607 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L610,611 | 复用色；按承载面判级 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L612 | 复用色；按承载面判级 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey4` L613 | 复用色；按承载面判级 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/settings/sidebar_nav_order_settings.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.secondaryLabel` L106,107 | 文字 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.activeBlue` L203,204 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L205 | 复用色；按承载面判级 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/settings/webui_sidecar_section.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.menuAction` L154 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L293,395,467 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L294,304,468,542 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L303,541 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L338,364,422 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L396 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusGreenText` L491 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L511 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L514,524 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L527 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/settings/widgets/page_surface_picker.dart`

默认控件：`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.kDefaultDarkSidebar` L123 | 复用色；按承载面判级 | #1B1B1B | 15.435821 | 17.224383 | 1.219202 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L197,279 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF1C1C1E)` L284 | 复用色；按承载面判级 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBackground` L419,431 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L461 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.card` L498 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L499 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L511,550,563,646 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L512,551 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.systemRed` L601 | 文字 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L748,766,829 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `CupertinoColors.white` L763 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `Color(0x33000000)` L771 | 装饰线/投影豁免 | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰线/投影豁免 |
| `Color(0xFF3C3C43)` L814 | 复用色；按承载面判级 | #3C3C43 | 9.804188 | 10.940208 | 1.919525 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFFFFFF)` L815 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF007AFF)` L828 | 装饰线/投影豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 装饰线/投影豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/settings/accessibility_settings.dart`、`lib/features/settings/chat_send_shortcut_settings.dart`、`lib/features/settings/composer_settings.dart`、`lib/features/settings/cron_visibility_settings.dart`、`lib/features/settings/injected_notice_settings.dart`、`lib/features/settings/perf_monitor_settings.dart`、`lib/features/settings/settings_providers.dart`、`lib/features/settings/smooth_streaming_settings.dart`、`lib/features/settings/tool_group_settings.dart`。

### P4 引导页、连接向导与安装向导

hero 中 #E5E5EA 是品牌图标承载面，柔光/轨道/配准线为 ExcludeSemantics 内的装饰，不承担表单可读性；保持动画设计，不用提高装饰对比度替代文字修复。优先修连接表单 placeholder、说明、错误/步骤状态和安装日志的真实承载面。预计影响宽屏品牌/表单双栏及窄屏连接表单，保持 reduceMotion 和窄屏几何。

#### `lib/features/onboarding/install_guide_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L813,1018,1044,1056 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L840,872 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L850 | 文字 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L851,1019,1045,1057,1962 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `statusGreenText` L860,1705 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L891,898 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `statusOrangeText` L927,1314,1362,1775 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemYellow` L928 | 暗色保留豁免 | #FFCC00 | 1.354970 | 1.511972 | 13.889146 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L944,1967,2550,2590,2656 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L1069,2004 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L1070 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L1082,1622 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF007AFF)` L1083,1151,1623,1709,1968 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusGreenText` L1129,1220,1249,1427,1462,1485,1934,1937 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1132,1438 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L1150,1708 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L1260,1271 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintWarning` L1287,1332 | 面/复用 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `statusOrangeText @ 0.14` L1288,1333 | 暗色保留豁免 | #B25000 / α=0.140000 | 1.207373 | 1.217037 | 1.089924 | 暗色保留豁免 |
| `Color(0xFFF0D6B8)` L1292,1337 | 装饰线/投影豁免 | #F0D6B8 | 1.253304 | 1.398525 | 15.015818 | 装饰线/投影豁免 |
| `statusOrangeText @ 0.36` L1293,1338 | 暗色保留豁免 | #B25000 / α=0.360000 | 1.660336 | 1.701031 | 1.392326 | 暗色保留豁免 |
| `Color(0xFF5B3A16)` L1297,1342 | 文字/复用 | #5B3A16 | 9.128367 | 10.186079 | 2.061637 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L1298,1343 | 暗色保留豁免 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 暗色保留豁免 |
| `Color(0xFF48484A)` L1631 | 暗色保留豁免 | #48484A | 8.177462 | 9.124992 | 2.301372 | 暗色保留豁免 |
| `Color(0xFFC8C8CC)` L1632 | 装饰线/投影豁免 | #C8C8CC | 1.494846 | 1.668055 | 12.589509 | 装饰线/投影豁免 |
| `CupertinoColors.white` L1641 | 图标/图形 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L1651 | 面 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.white` L1660,2150,2220,2441,2461 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromRGBO(120,120,128,0.12)` L1829 | 面 | #787880 / α=0.120000 | 1.142064 | 1.151203 | 1.091412 | 装饰面豁免；分层强弱见三向值 |
| `Color.fromRGBO(120,120,128,0.24)` L1830 | 暗色保留豁免 | #787880 / α=0.240000 | 1.313522 | 1.335938 | 1.244945 | 暗色保留豁免 |
| `statusRedText` L1896,2195,2205,2318,2526 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1961 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L1982,2061,2336 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L1983,2062 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.divider` L1989,2068,2390 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L1990,2005,2069,2113,2391 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L2112,2172,2341 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.tintError` L2165 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `statusRedText @ 0.08` L2166 | 暗色保留豁免 | #B3001B / α=0.080000 | 1.157968 | 1.161333 | 1.020135 | 暗色保留豁免 |
| `statusRedText @ 0.3` L2173 | 暗色保留豁免 | #B3001B / α=0.300000 | 1.790104 | 1.816604 | 1.158749 | 暗色保留豁免 |
| `statusRedText` L2185 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L2214 | 面 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemFill` L2337 | 暗色保留豁免 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L2370,2561 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L2371 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `CupertinoColors.darkBackgroundGray` L2385 | 面 | #171717 | 16.066232 | 17.927840 | 1.171363 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey` L2409 | 图标/图形 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 非文本：页面不达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L2416,2481 | 文字 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.black` L2475 | 面 | #000000 | 18.819381 | 21.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGreen` L2494 | 文字 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey4` L2605 | 复用色；按承载面判级 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.black` L2614 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/onboarding_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L330,615,733 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L338 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L403,410 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L478,553,594,635,673,712 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L479,554,595,636,674,713 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L508 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L515 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L606,656,724 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L648 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/pairing/pairing_style.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L92 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemGroupedBackground` L93 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.black` L107 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L108 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L114 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L115 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L121 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L122 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `Color(0xFFC7C7CC)` L128 | 复用色；按承载面判级 | #C7C7CC | 1.509207 | 1.684080 | 12.469719 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF48484A)` L129 | 暗色保留豁免 | #48484A | 8.177462 | 9.124992 | 2.301372 | 暗色保留豁免 |
| `Color.fromRGBO(120,120,128,0.12)` L135 | 复用色；按承载面判级 | #787880 / α=0.120000 | 1.142064 | 1.151203 | 1.091412 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromRGBO(120,120,128,0.24)` L136 | 复用色；按承载面判级 | #787880 / α=0.240000 | 1.313522 | 1.335938 | 1.244945 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFE0E0E4)` L141 | 复用色；按承载面判级 | #E0E0E4 | 1.179750 | 1.316449 | 15.952008 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L142 | 复用色；按承载面判级 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L145 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L148 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L151 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L155 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L158 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/onboarding/pairing/pairing_wizard.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L262,266 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |

#### `lib/features/onboarding/pairing/wizard_code_page.dart`

默认控件：`CupertinoTextField`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.transparent` L168 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L169 | 文字 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.transparent` L198 | 面 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |

#### `lib/features/onboarding/widgets/builtin_tab.dart`

默认控件：`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L358,441,741,884 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L359,442,742,755,885 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.tintWarning` L394 | 面 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemOrange @ 0.12` L395,529 | 暗色保留豁免 | #FF9500 / α=0.120000 | 1.091038 | 1.101384 | 1.142773 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L403,592,629,779 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemOrange @ 0.35` L404 | 暗色保留豁免 | #FF9500 / α=0.350000 | 1.287731 | 1.327518 | 1.921126 | 暗色保留豁免 |
| `statusOrangeText` L418 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L428 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L458 | 面 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.activeOrange` L459 | 暗色保留豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 暗色保留豁免 |
| `CupertinoColors.white` L470 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L485 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L486 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `CupertinoColors.label` L497 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L525 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintWarning` L528 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L542 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintGreen` L545 | 复用色；按承载面判级 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen @ 0.12` L546 | 暗色保留豁免 | #34C759 / α=0.120000 | 1.091985 | 1.102490 | 1.142405 | 暗色保留豁免 |
| `statusBlueText` L552 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selection` L555 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.12` L556 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `statusRedText` L562 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintError` L565 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemRed @ 0.12` L566 | 暗色保留豁免 | #FF3B30 / α=0.120000 | 1.166066 | 1.174456 | 1.090290 | 暗色保留豁免 |
| `statusGreyText` L572 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L575 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey @ 0.12` L576 | 暗色保留豁免 | #8E8E93 / α=0.120000 | 1.114697 | 1.124644 | 1.112837 | 暗色保留豁免 |
| `LightSurfaces.tintError` L622 | 面 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 装饰面豁免；分层强弱见三向值 |
| `statusRedText @ 0.08` L623 | 暗色保留豁免 | #B3001B / α=0.080000 | 1.157968 | 1.161333 | 1.020135 | 暗色保留豁免 |
| `statusRedText @ 0.25` L630 | 暗色保留豁免 | #B3001B / α=0.250000 | 1.614942 | 1.633458 | 1.113405 | 暗色保留豁免 |
| `statusRedText` L643,798,838,923 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L660 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L679,702 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L709,754,952 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L777 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L784 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L785 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.secondaryLabel` L953 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

#### `lib/features/onboarding/widgets/horizontal_step_rail.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF3A3A3C)` L72 | 暗色保留豁免 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 暗色保留豁免 |
| `Color(0xFFE2E2E6)` L73 | 复用色；按承载面判级 | #E2E2E6 | 1.157765 | 1.291916 | 16.254927 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF48484A)` L117 | 暗色保留豁免 | #48484A | 8.177462 | 9.124992 | 2.301372 | 暗色保留豁免 |
| `Color(0xFFC8C8CC)` L118 | 装饰线/投影豁免 | #C8C8CC | 1.494846 | 1.668055 | 12.589509 | 装饰线/投影豁免 |
| `LightSurfaces.userDetail` L122 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF007AFF)` L123 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusGreenText` L125,206 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L126 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L136,156 | 图标/图形 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white` L147 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L166,193 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8A8A8F)` L167,194 | 暗色保留豁免 | #8A8A8F | 3.078745 | 3.435481 | 6.112680 | 暗色保留豁免 |
| `CupertinoColors.label` L203 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/widgets/onboarding_field_style.dart`

默认控件：`CupertinoTextField`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L12 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.cardBorder` L13 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L22 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/onboarding/widgets/onboarding_hero_motion.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L124 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L236 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L237 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `Color(0xFF1C1C1E)` L258 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `Color(0xFFE5E5EA)` L259 | 面 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L262 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `CupertinoColors.white` L274 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `CupertinoColors.black` L275 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0x384F6076)` L299 | 纯装饰豁免 | #4F6076 / α=0.219608 | 1.357617 | 1.375907 | 1.147194 | 纯装饰豁免 |
| `Color(0x18546983)` L299 | 纯装饰豁免 | #546983 / α=0.094118 | 1.126773 | 1.133098 | 1.058581 | 纯装饰豁免 |
| `Color(0x00546983)` L299 | 纯装饰豁免 | #546983 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 纯装饰豁免 |
| `Color(0xE6FFFFFF)` L300 | 纯装饰豁免 | #FFFFFF / α=0.901961 | 1.104161 | 1.000000 | 16.825959 | 纯装饰豁免 |
| `Color(0x1895A4B9)` L300 | 纯装饰豁免 | #95A4B9 / α=0.094118 | 1.069922 | 1.078070 | 1.097879 | 纯装饰豁免 |
| `Color(0x0095A4B9)` L300 | 纯装饰豁免 | #95A4B9 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 纯装饰豁免 |
| `Color(0x26CCD4DF)` L304 | 纯装饰豁免 | #CCD4DF / α=0.149020 | 1.042478 | 1.057795 | 1.280875 | 纯装饰豁免 |
| `Color(0x22596879)` L305 | 纯装饰豁免 | #596879 / α=0.133333 | 1.186782 | 1.196394 | 1.085103 | 纯装饰豁免 |
| `Color(0x466F8299)` L307 | 纯装饰豁免 | #6F8299 / α=0.274510 | 1.342829 | 1.370545 | 1.338633 | 纯装饰豁免 |
| `Color(0x3864788E)` L308 | 纯装饰豁免 | #64788E / α=0.219608 | 1.290641 | 1.310354 | 1.204910 | 纯装饰豁免 |
| `Color(0x405F6C7D)` L310 | 纯装饰豁免 | #5F6C7D / α=0.250980 | 1.378437 | 1.401588 | 1.216382 | 纯装饰豁免 |
| `Color(0x305D626B)` L311 | 纯装饰豁免 | #5D626B / α=0.188235 | 1.288334 | 1.303141 | 1.124429 | 纯装饰豁免 |
| `Color(0x998CA4BC)` L313 | 纯装饰豁免 | #8CA4BC / α=0.600000 | 1.604304 | 1.698227 | 3.376596 | 纯装饰豁免 |
| `Color(0x80778CA1)` L314 | 纯装饰豁免 | #778CA1 / α=0.501961 | 1.672526 | 1.746116 | 2.191687 | 纯装饰豁免 |

#### `lib/features/onboarding/widgets/wide_dual_pane.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.divider` L55 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L56 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `Color(0xFF0A0A0C)` L88 | 暗色保留豁免 | #0A0A0C | 17.726852 | 19.780878 | 1.061631 | 暗色保留豁免 |
| `LightSurfaces.page` L89 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/onboarding/builtin_service_connect.dart`、`lib/features/onboarding/onboarding_providers.dart`、`lib/features/onboarding/pairing/pairing_constants.dart`、`lib/features/onboarding/pairing/wizard_discover_page.dart`、`lib/features/onboarding/pairing/wizard_download_page.dart`、`lib/features/onboarding/pairing/wizard_start_page.dart`、`lib/features/onboarding/widgets/network_probe.dart`。

### 后续 会话工作区

文件列表、空态和选中文件信息仍使用分组面及 secondaryText。建议白卡轮廓、可读的文件大小/路径/空态提示；选中态和媒体反色控件单列。影响单会话浏览/上传/预览，不改文件/API 操作。

#### `lib/features/workspace/workspace_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L319 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L321 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L323 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L387,464 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L388,465 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L561,603,662,1025,1063,1110,1316,1335 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L562,604,663 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L573,676,985,1036,1074,1133,1160,1188,1298 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L574,677,986,1161,1189,1299 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `statusRedText` L621 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L628 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.quaternaryLabel` L1012,1050,1121 | 复用色；按承载面判级 | #3C3C43 / α=0.176471 | 1.351231 | 1.362437 | 1.064897 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.userDetail` L1026,1064 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L1037,1075,1134,1202 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L1111,1317 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.systemRed` L1176 | 图标/图形 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selectionForeground` L1253 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L1254 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L1336 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L1353 | 面 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `theme.primaryColor @ 0.12` L1354 | 面 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemFill` L1380 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemFill` L1381 | 面 | #787880 / α=0.156863 | 1.191278 | 1.203984 | 1.129452 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondaryLabel` L1393,1458 | 复用色；按承载面判级 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1394 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGreen` L1396,1421,1440 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L1397 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemTeal` L1399,1425,1430 | 复用色；按承载面判级 | #5AC8FA | 1.698980 | 1.895843 | 11.076868 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusTealText` L1400 | 复用色；按承载面判级 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L1407 | 复用色；按承载面判级 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue` L1413,1448 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemPurple` L1415,1453 | 复用色；按承载面判级 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemPink` L1417,1456 | 复用色；按承载面判级 | #FF2D55 | 3.268088 | 3.646764 | 5.758530 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/workspace/workspace_api.dart`、`lib/features/workspace/workspace_providers.dart`。

### 后续 工作区管理及共享文件预览

注册表、添加 Sheet、文件预览正文分属不同承载面。预览代码背景 systemGrey6 与页面灰接近；多媒体黑底上的白字属于反色 UI，保留语义并按实际黑底测量。建议目录/路径/元数据先修，office/媒体预览单独做视觉验收。影响注册表及聊天附件/下载复用的预览入口。

#### `lib/features/workspace_manager/add_workspace_sheet.dart`

默认控件：`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemBlue` L131,229 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L132 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.inactiveGray` L134 | 暗色保留豁免 | #999999 | 2.553188 | 2.849028 | 7.370936 | 暗色保留豁免 |
| `LightSurfaces.placeholder` L135 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L143 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBackground` L144 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `statusRedText` L172 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L198 | 面 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L230 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemBackground` L271 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L272 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L276 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L292,329 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L293,330 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `CupertinoColors.transparent` L299,336 | 面 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L389 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L390 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.divider` L413,447 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L414,448 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.pressed` L433 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemFill` L434 | 暗色保留豁免 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L469 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/workspace_manager/file_preview_body.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L787,1212,1274 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L788,1213,1275 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `CupertinoColors.systemBackground` L827 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.divider` L973 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L974,1081 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemBackground` L983 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.card` L986 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L990 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.tertiarySystemFill` L1001 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L1013,1057,1116,1192,1232,1440,1451 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L1014,1058,1117,1193,1233,1441,1452 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.divider` L1080 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.userDetail` L1245,1303 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1292 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.activeBlue` L1407 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/workspace_manager/file_preview_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`。

无额外显式颜色，继承上表语义。

#### `lib/features/workspace_manager/workspace_manager_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L144 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L147 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L154 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L161,265,617 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L162,266,618 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L199,248,644 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L200,249 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L214,442,580 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L221 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0x99000000)` L343 | 复用色；按承载面判级 | #000000 / α=0.600000 | 5.554744 | 5.741836 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L371,385,428,480 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L645 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `CupertinoColors.tertiarySystemFill` L667 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L673 | 图标/图形 | #000000 | 18.819381 | 21.000000 | 1.000000 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.15` L691 | 暗色保留豁免 | #007AFF / α=0.150000 | 1.203594 | 1.215577 | 1.116793 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L694 | 面 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L701 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/workspace_manager/office_document.dart`、`lib/features/workspace_manager/workspace_manager_api.dart`、`lib/features/workspace_manager/workspace_manager_providers.dart`。

### 后续 Git 面板

分组列表、分支树、diff 增删及操作提示存在多套灰阶与状态色。优先次级元数据和 diff 正文对比度，新增白卡描边；状态圆点不能替代文件变更文字语义。影响分支、状态和差异视图，不改 Git 操作。

#### `lib/features/git/git_branch_tree.dart`

默认控件：`CupertinoListSection`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemBlue` L59 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemTeal` L60 | 复用色；按承载面判级 | #5AC8FA | 1.698980 | 1.895843 | 11.076868 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemPurple` L61 | 复用色；按承载面判级 | #AF52DE | 3.701328 | 4.130204 | 5.084495 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemOrange` L62 | 复用色；按承载面判级 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemIndigo` L63 | 复用色；按承载面判级 | #5856D6 | 5.062968 | 5.649619 | 3.717065 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemPink` L64 | 复用色；按承载面判级 | #FF2D55 | 3.268088 | 3.646764 | 5.758530 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L90 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L92,291,358 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L94 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.07` L192 | 暗色保留豁免 | #007AFF / α=0.070000 | 1.089269 | 1.094052 | 1.045714 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L195,264,430 | 面 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemBlue` L212,245 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L213 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L217,357 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.divider` L218 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L248,273 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L249 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.16` L261 | 暗色保留豁免 | #007AFF / α=0.160000 | 1.218886 | 1.231923 | 1.128448 | 暗色保留豁免 |
| `CupertinoColors.systemGrey5` L285 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.page` L286,353 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `secondaryText` L302,312,369,386,400,464 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L303 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L313,370,387,401,444,465,505 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L325 | 文字 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L334 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemBackground` L351 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `CupertinoColors.systemGreen` L417 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `statusGreenText` L418 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemBlue @ 0.12` L427 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L442 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L445,506 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L480 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L488 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L597 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.white @ 0.8` L608 | 装饰线/投影豁免 | #FFFFFF / α=0.800000 | 1.092065 | 1.000000 | 13.076547 | 装饰线/投影豁免 |

#### `lib/features/git/git_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.systemRed` L110,988 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen` L111,986 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L235,334 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L236,335 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L303,714,765 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L304,713,764 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L316,415,463,477,489,784,817,916,936,1133 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L317,416,785,1134 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.card` L441,533,575,647 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L443,535,577,649,1181 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L445,537,579,651 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue` L451 | 暗色保留豁免 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 暗色保留豁免 |
| `statusBlueText` L452 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L478,937 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L596 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.placeholderText` L597 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L608,662,673,684,737 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L731 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L829,839 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor @ 0.12` L900 | 暗色保留豁免 | #007AFF / α=0.120000 | 1.159087 | 1.168124 | 1.085680 | 暗色保留豁免 |
| `LightSurfaces.selectedSurface` L902 | 复用色；按承载面判级 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemRed` L950 | 暗色保留豁免 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `statusRedText` L951 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemOrange` L990 | 复用色；按承载面判级 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey` L992 | 复用色；按承载面判级 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey2` L994 | 复用色；按承载面判级 | #AEAEB2 | 1.981608 | 2.211219 | 9.497025 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemBlue` L997 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreenText` L1003,1180 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L1005,1179 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L1007 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1009 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L1011 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L1014 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L1057 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemBackground` L1058 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `CupertinoColors.systemGreen` L1117 | 暗色保留豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 暗色保留豁免 |
| `statusGreenText` L1118 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.tintError` L1177 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintGreen` L1177 | 复用色；按承载面判级 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/git/git_api.dart`、`lib/features/git/git_providers.dart`。

### 后续 技能

白色分组列表/搜索与灰色摘要，空态图标和说明须分别判级。建议摘要、路径和 placeholder 使用达标次级文字，白卡补轮廓。影响技能列表/详情及搜索。

#### `lib/features/skills/skills_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoSearchTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L242,469,639,674,945 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L243,470,640,675,810,946 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `CupertinoColors.label` L252,642,952,984 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L298,356 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L300,359 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L304 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L308,809 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L309,757,822 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.page` L350 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.darkPage` L351 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.divider` L353,560 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L397,449,657 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L399,451 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L417 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L423 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L510 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L554 | 文字/复用 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8A8A90)` L555 | 复用色；按承载面判级 | #8A8A90 | 3.075681 | 3.432063 | 6.118770 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L561 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.tertiaryLabel` L658 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.selectionForeground` L787 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L788 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L790 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L815 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `CupertinoColors.transparent` L836 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.secondarySystemFill` L975 | 面 | #787880 / α=0.156863 | 1.191278 | 1.203984 | 1.129452 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemFill` L976 | 面 | #767680 / α=0.117647 | 1.141332 | 1.150191 | 1.087601 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/skills/skills_api.dart`、`lib/features/skills/skills_providers.dart`。

### 后续 记忆

分组卡、记忆编辑框、覆盖提示、字数和空态共享次级灰。建议可读文字与装饰分隔分开，编辑背景和 placeholder 配套修复。影响记忆列表与编辑表单，不改写入行为。

#### `lib/features/memory/memory_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoTextField`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L371 | 面/复用 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkPage` L372 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.card` L376,800 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L378,802 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L381 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L537,585,1072 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L539,587 | 暗色保留豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L553,821 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L559,850 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L598,882,921 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L599,692,883,922,1025,1096 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L691,1024,1095 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L706,1039 | 图标/图形 | #000000 | 18.819381 | 21.000000 | 1.000000 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.placeholder` L811 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L839 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L966 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L967 | 面/复用 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondaryLabel` L1073 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/memory/memory_api.dart`、`lib/features/memory/memory_providers.dart`。

### 后续 定时任务

列表和编辑/详情页继承 Cupertino 分组面，副标题及参数提示使用 secondaryText；状态颜色按文字和图标分别核对。建议卡片轮廓、次级文字、输入占位依次落地。影响任务列表/创建/详情。

#### `lib/features/tasks/tasks_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoTextField`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L65 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L68,163,1399 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L70,76 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreyText` L72 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L74 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L133,1363,1365 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L164,165,211,1400,1401 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.darkPage` L212 | 复用色；按承载面判级 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L213,706 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L216,1567 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L219,1570 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L230,521,1001,1555 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L397,1086,1221 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L400,1089,1094,1224 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L401,522,1002,1090,1556 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.divider` L405,1099,1229 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L406,707,1100,1230 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L460,506,1031 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L461,507,731,793,1032,1095,1225 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L477,646 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L636,671 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L700 | 文字/复用 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8A8A90)` L701 | 复用色；按承载面判级 | #8A8A90 | 3.075681 | 3.432063 | 6.118770 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectionForeground` L774 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L775 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L777 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L786 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `CupertinoColors.transparent` L807 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L978 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.pressed` L1057 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L1083 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemBackground` L1084 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.page` L1218 | 面/复用 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemBackground` L1219 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.selection` L1404 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.placeholder` L1578 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/tasks/tasks_api.dart`、`lib/features/tasks/tasks_providers.dart`。

### 后续 项目选择 Sheet

主要使用标准 Cupertino 列表与输入控件，显式颜色少不代表没有默认 placeholder/按下色。建议随通用 Sheet 令牌迁移；影响项目选择、新建及移动会话入口。

#### `lib/features/projects/project_picker_sheet.dart`

默认控件：`CupertinoTextField`、`CupertinoActionSheet`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L39 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L52,85,97,211 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L132 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L134 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L143 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L153,161,281 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L221 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L222 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L291 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/projects/project_providers.dart`。

### 后续 提示词库

收藏列表/编辑 Sheet 的 secondaryLabel、搜索占位和空态需随白卡一起迁移。影响聊天输入栏提示词选择和编辑，不改收藏内容。

#### `lib/features/prompts/widgets/saved_prompts_sheet.dart`

默认控件：`CupertinoListTile`、`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusRedText` L160,362 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L166,346,373 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.divider` L200,260,457 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L201,261,458 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L211 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L217 | 图标/图形 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L241,295 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L242,296 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L281 | 复用色；按承载面判级 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.pressed` L282 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusRedText` L313 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L413 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L414 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L422 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey3` L439 | 面 | #C7C7CC | 1.509207 | 1.684080 | 12.469719 | 装饰面豁免；分层强弱见三向值 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/prompts/prompts_providers.dart`。

### 后续 下载

灰色进度轨道、白卡和多类状态色共存；文件路径/字节进度 secondaryLabel 未达正文 AA。进度轨道属于非文本对照物，按钮白图标需按其真实底色判定。建议先修可读元数据，保留下载状态机。

#### `lib/features/downloads/download_confirm_dialog.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.menuAction` L52 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/downloads/download_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.menuAction` L146,157,248,303 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L381 | 复用色；按承载面判级 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `theme.primaryColor` L383,697,772,823 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L442,446,885 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkPage` L443 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L464 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L465 | 文字 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L553,759,808,851 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.tertiaryLabel` L554 | 暗色保留豁免 | #3C3C43 / α=0.298039 | 1.698832 | 1.725396 | 1.121334 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L565 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L566,760,809,852 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusGreyText` L612,655 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L634 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L640 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L643,651 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.pressed` L670 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGrey4` L671 | 暗色保留豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 暗色保留豁免 |
| `CupertinoColors.label` L682,908 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L696,771,822 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L722,789,833 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L866 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L867 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L871 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.systemGrey6` L886 | 暗色保留豁免 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L893 | 图标/图形 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/downloads/download_controller.dart`、`lib/features/downloads/download_models.dart`、`lib/features/downloads/download_providers.dart`、`lib/features/downloads/download_repository.dart`、`lib/features/downloads/download_save_service.dart`。

### 后续 诊断及详情 Sheet

日志级别、筛选标签、展开箭头、代码/复制区共享灰面，动态级别 tint 叠加透明底。建议逐级别测量真实 tint/background 组合，修时间、来源、正文灰。影响诊断列表及详情，不改日志采集。

#### `lib/features/diagnostics/diagnostics_detail_sheet.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.tintWarning` L17 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintError` L19 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L21 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintClarification` L23 | 复用色；按承载面判级 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L25 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.menuAction` L49,295 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.card` L88,213,249 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L89,214,250 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L93,218,254 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.page` L131,283,285 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L132 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L143,157,172,201,237 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L144,158,173,202,238 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `statusRedText` L184 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/diagnostics/diagnostics_models.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreyText` L54 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `_statusDebugText` L56,68 | 复用色；按承载面判级 | #4A6B82 | 5.063617 | 5.650343 | 3.716588 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusBlueText` L58 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L60 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L62 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF4A6B82)` L70 | 文字/复用 | #4A6B82 | 5.063617 | 5.650343 | 3.716588 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF7AA5C2)` L71 | 其他主题定义豁免 | #7AA5C2 | 2.355787 | 2.628754 | 7.988577 | 其他主题定义豁免 |
| `Color(0xFF2C4D64)` L72 | 其他主题定义豁免 | #2C4D64 | 7.999175 | 8.926046 | 2.352665 | 其他主题定义豁免 |
| `Color(0xFF99C2DF)` L73 | 其他主题定义豁免 | #99C2DF | 1.689850 | 1.885654 | 11.136718 | 其他主题定义豁免 |

#### `lib/features/diagnostics/diagnostics_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoSearchTextField`、`CupertinoButton`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.tintWarning` L25 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintError` L27 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selection` L29,500 | 复用色；按承载面判级 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.tintClarification` L31 | 复用色；按承载面判级 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L33,636 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L76 | 文字/复用 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFB3001B)` L168 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.menuAction` L178,204,287,299,890 | 文字 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.page` L264,266,1356 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L486,969 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `blue @ 0.2` L500 | 复用色；按承载面判级 | #005FB8 / α=0.200000 | 1.348721 | 1.364493 | 1.119613 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.menuAction` L545 | 复用色；按承载面判级 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L546,1155 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L611 | 面 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.separator` L612,861,1293 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.darkPage` L637 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.divider` L639 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.card` L642,691,853 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L644,693,925,974,1170 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L658,773,1041,1059,1075,1368,1381,1394 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L659,774,1042,1060,1076,1178,1369,1382,1395 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `LightSurfaces.placeholder` L697 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L701,1177 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L702 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.userDetail` L790,819 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.userDetail` L799,828 | 文字 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondarySystemGroupedBackground` L854 | 暗色保留豁免 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.divider` L860,1292 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.userDetail` L899 | 面 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L922,971,1167 | 面/复用 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey6` L923,972,1168 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey4` L926,975,1171 | 装饰线/投影豁免 | #D1D1D6 | 1.363500 | 1.521490 | 13.802256 | 装饰线/投影豁免 |
| `LightSurfaces.textSecondary` L928,977,1173 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L929,978,1174 | 文字/复用 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L990,1283 | 面 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `activeColor @ 0.15` L991 | 面 | #005FB8 / α=0.150000 | 1.248206 | 1.258718 | 1.080556 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L1031,1312,1431 | 图标/图形 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L1032,1313 | 图标/图形 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 非文本：页面不达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selectionForeground` L1154 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L1157 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L1164 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `CupertinoColors.transparent` L1191 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `statusBlueText @ 0.1` L1284 | 面 | #005FB8 / α=0.100000 | 1.157261 | 1.163506 | 1.050244 | 装饰面豁免；分层强弱见三向值 |
| `statusBlueText` L1310 | 图标/图形 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey5` L1357 | 暗色保留豁免 | #E5E5EA | 1.125061 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `statusRedText` L1407 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFC7C7CC)` L1432 | 图标/图形 | #C7C7CC | 1.509207 | 1.684080 | 12.469719 | 非文本：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/diagnostics/diagnostics_interceptor.dart`、`lib/features/diagnostics/diagnostics_providers.dart`、`lib/features/diagnostics/diagnostics_service.dart`。

### 后续 通知浮条与后台保活设置

应用内通知白卡、次级消息和关闭图标需迁移；系统通知平台外观不属于 lib 静态页面面色。保活说明/错误状态仍按正文核对。影响 in-app 通知及保活设置，系统通知发送不动。

#### `lib/features/notifications/background_keepalive_settings_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoListSection`、`CupertinoListTile`、`CupertinoNavigationBar`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.page` L28,30 | 面 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.textSecondary` L54 | 复用色；按承载面判级 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L55 | 复用色；按承载面判级 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.page` L64,208 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.darkPage` L65,209 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.card` L69,213 | 面 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L71,215 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.divider` L76,220 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.textSecondary` L82,93,115,153,190,226,257 | 文字 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L134,180 | 图标/图形 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusRedText` L139,143,175 | 文字 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `statusGreenText` L159 | 图标/图形 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF34C759)` L160 | 图标/图形 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 非文本：页面不达 / 白卡不达；反色见局部组合 |
| `statusGreyText` L195 | 图标/图形 | #595959 | 6.277365 | 7.004729 | 2.997975 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L244 | 图标/图形 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `statusOrangeText` L250 | 文字 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/notifications/background_keepalive_service.dart`、`lib/features/notifications/live_update_service.dart`、`lib/features/notifications/notification_lifecycle_observer.dart`、`lib/features/notifications/notification_providers.dart`、`lib/features/notifications/turn_notification_service.dart`、`lib/features/notifications/workmanager_registration_probe.dart`。

### 共享组件

AppBackButton / app_navigation 无独立颜色常量；返回图标与 NarrowNavigationDropdownButton 的继承动作色已由 P1 widget 测试按实际背景验证，导航逻辑不改。

#### `lib/features/shared/app_back_button.dart`

默认控件：`CupertinoButton`。

无额外显式颜色，继承上表语义。

#### `lib/features/shared/wide_nav_rail.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFF3A3A3C)` L22 | 文字/复用 | #3A3A3C | 10.170553 | 11.349024 | 1.850379 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8A8A90)` L26 | 复用色；按承载面判级 | #8A8A90 | 3.075681 | 3.432063 | 6.118770 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.divider` L31 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L32 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.secondaryLabel` L79,137 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.selectionForeground` L120 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `theme.primaryColor` L121 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.selectedSurface` L123 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L130 | 暗色保留豁免 | #000000 | 18.819381 | 21.000000 | 1.000000 | 暗色保留豁免 |
| `CupertinoColors.transparent` L150 | 复用色；按承载面判级 | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/shared/app_navigation.dart`。

### 桌面能力

本目录是窗口、托盘、快捷键及启动服务，没有 Flutter 页面面色；桌面设置的 UI 在 settings 中审计，托盘操作系统主题不由这里的 Dart Color 控制。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/desktop/desktop_lifecycle_observer.dart`、`lib/features/desktop/desktop_settings.dart`、`lib/features/desktop/desktop_shortcuts.dart`、`lib/features/desktop/startup_registrar.dart`、`lib/features/desktop/tray_manager_service.dart`、`lib/features/desktop/window_memory.dart`、`lib/features/desktop/window_title_service.dart`。

### 内置服务

配置、状态模型、Provider 与服务，无独立 Flutter 面色；可见设置区在 settings/webui_sidecar_section.dart，引导入口在 onboarding/widgets/builtin_tab.dart。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/webui_sidecar/webui_sidecar_config.dart`、`lib/features/webui_sidecar/webui_sidecar_models.dart`、`lib/features/webui_sidecar/webui_sidecar_providers.dart`、`lib/features/webui_sidecar/webui_sidecar_service.dart`。

### 阶段一 会话列表

主列表、紧凑侧栏复用区、搜索框、菜单图标、副标题、选中/按下态、筛选弹层、批量栏和 FAB 工作区浮层按浅色令牌接入。session_list_header 不改源码，由页面局部 bar/page 主题消费；scheduled_session_disclosure 是弃用兼容组件，仍同步修正计数和标题。下面暗色原值/反色 tooltip 另有明确豁免，业务状态与分组逻辑不改。

#### `lib/features/session_list/scheduled_session_disclosure.dart`

默认控件：`CupertinoListSection`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.textSecondary` L64 | 文字/复用 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L65 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `LightSurfaces.card` L99,150 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.systemGrey5` L100 | 暗色保留豁免 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L106,152 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.page` L144 | 复用色；按承载面判级 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `LightSurfaces.darkPage` L145 | 暗色保留豁免 | #1C1C1E | 15.198584 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.divider` L147 | 复用色；按承载面判级 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/session_list/session_list_header.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.label` L200 | 文字/复用 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

#### `lib/features/session_list/session_list_page.dart`

默认控件：`CupertinoPageScaffold`、`CupertinoSearchTextField`、`CupertinoButton`、`CupertinoActionSheet`。

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.sidebar` L291 | 面 | #E6E6E6 | 1.114853 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.darkSidebar` L292 | 暗色保留豁免 | #1B1B1B | 15.385854 | 17.224383 | 1.219202 | 暗色保留豁免 |
| `LightSurfaces.page` L294 | 面 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.sidebar` L432 | 面/复用 | #E6E6E6 | 1.114853 | 1.248072 | 16.825959 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.page` L433 | 面/复用 | #F2F2F2 | 1.000000 | 1.119495 | 18.758462 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.card` L478,726,1003 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.cardBorder` L480,1025 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `LightSurfaces.placeholder` L484 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L488,623,1127 | 复用色；按承载面判级 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L489,624 | 暗色保留豁免 | #3C3C43 / α=0.600000 | 3.291332 | 3.438200 | 1.358277 | 暗色保留豁免 |
| `statusRedText` L618 | 复用色；按承载面判级 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemRed` L619 | 暗色保留豁免 | #FF3B30 | 3.168517 | 3.547138 | 5.920266 | 暗色保留豁免 |
| `CupertinoColors.systemBackground` L727 | 暗色保留豁免 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.divider` L733 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.separator` L734,1026,1056 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.659506 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `CupertinoColors.activeBlue` L809 | 面/复用 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFE5E5EA)` L812 | 复用色；按承载面判级 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF3A3A3C)` L813 | 暗色保留豁免 | #3A3A3C | 10.137630 | 11.349024 | 1.850379 | 暗色保留豁免 |
| `CupertinoColors.secondarySystemGroupedBackground` L1005 | 暗色保留豁免 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.divider` L1055 | 面 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰面豁免；分层强弱见三向值 |
| `LightSurfaces.sidebarSecondary` L1126 | 复用色；按承载面判级 | #5E5E63 | 5.759096 | 6.447278 | 3.257189 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `secondaryText` L1128,1359 | 暗色保留豁免 | #3C3C43 / α=0.741176 | 4.725943 | 5.035494 | 1.521987 | 暗色保留豁免 |
| `Color(0xFFE5E5EA)` L1132 | 面/复用 | #E5E5EA | 1.121419 | 1.255423 | 16.727430 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF2C2C2E)` L1133 | 暗色保留豁免 | #2C2C2E | 12.449050 | 13.936646 | 1.506819 | 暗色保留豁免 |
| `LightSurfaces.textSecondary` L1258,1338 | 图标/图形 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGrey` L1261,1341 | 暗色保留豁免 | #8E8E93 | 2.912500 | 3.260528 | 6.440674 | 暗色保留豁免 |
| `statusRedText` L1278,2329,2574 | 文字 | #B3001B | 6.396600 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `LightSurfaces.textSecondary` L1358 | 文字 | #6A6A6F | 4.804950 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.black @ 0.82` L2494 | 面 | #000000 / α=0.820000 | 12.550671 | 13.598961 | 1.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.black @ 0.2` L2498 | 装饰线/投影豁免 | #000000 / α=0.200000 | 1.597843 | 1.605929 | 1.000000 | 装饰线/投影豁免 |
| `CupertinoColors.white` L2507 | 文字 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color.fromRGBO(120,120,128,0.20)` L4222 | 复用色；按承载面判级 | #787880 / α=0.200000 | 1.252160 | 1.270087 | 1.184053 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF2C2C2E)` L4223 | 复用色；按承载面判级 | #2C2C2E | 12.449050 | 13.936646 | 1.506819 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L4228 | 复用色；按承载面判级 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.white` L4229 | 复用色；按承载面判级 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/features/session_list/session_list_utility_rows.dart`

参考页面 P=#F2F2F2；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.card` L139 | 面 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.secondarySystemGroupedBackground` L140 | 暗色保留豁免 | #FFFFFF | 1.119495 | 1.000000 | 21.000000 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L144 | 装饰线/投影豁免 | #CCD0DA | 1.379074 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `CupertinoColors.activeBlue` L182 | 图标/图形 | #007AFF | 3.588204 | 4.016976 | 5.227813 | 非文本：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.label` L190 | 文字 | #000000 | 18.758462 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/features/session_list/session_auto_refresh.dart`、`lib/features/session_list/session_entry_visibility.dart`、`lib/features/session_list/session_events_client.dart`、`lib/features/session_list/session_list_providers.dart`、`lib/features/session_list/session_list_shell_requests.dart`、`lib/features/session_list/session_row_subtitle_settings.dart`。

### 共用主题与语义令牌

全局主题保持原样，仅新建 LightSurfaces opt-in 层。旧 status_colors 注释不作数字来源：以源码 ARGB 实算。状态色在白卡达标不代表叠加任意彩色面也达标；secondaryText 的 alpha 必须先合成。

#### `lib/app/theme/cupertino_theme.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.darkPage` L20 | 暗色保留豁免 | #1C1C1E | 15.247942 | 17.014735 | 1.234224 | 暗色保留豁免 |
| `LightSurfaces.page` L20 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF007AFF)` L23 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.label` L36,66,74,81 | 文字 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF007AFF)` L43,58 | 文字 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.inactiveGray` L51 | 文字 | #999999 | 2.553188 | 2.849028 | 7.370936 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/theme/divider_tokens.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `LightSurfaces.divider` L45 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L46,55 | 暗色保留豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 暗色保留豁免 |
| `LightSurfaces.cardBorder` L54 | 复用色；按承载面判级 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

#### `lib/app/theme/light_surfaces.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `Color(0xFFF2F2F7)` L48 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFCCD0DA)` L51 | 装饰线/投影豁免 | #CCD0DA | 1.383553 | 1.543866 | 13.602215 | 装饰线/投影豁免 |
| `Color(0xFFF2F2F2)` L54 | 复用色；按承载面判级 | #F2F2F2 | 1.003248 | 1.119495 | 18.758462 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF2C2C2E)` L89 | 面/复用 | #2C2C2E | 12.489479 | 13.936646 | 1.506819 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFFE0E0E0)` L92 | 复用色；按承载面判级 | #E0E0E0 | 1.183007 | 1.320084 | 15.908084 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF1B1B1B)` L95 | 复用色；按承载面判级 | #1B1B1B | 15.435821 | 17.224383 | 1.219202 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF262626)` L98 | 复用色；按承载面判级 | #262626 | 13.562079 | 15.133529 | 1.387647 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.systemGroupedBackground` L141 | 复用色；按承载面判级 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFFFFFFF)` L362 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `Color(0xFF6A6A6F)` L365 | 文字/复用 | #6A6A6F | 4.820554 | 5.379116 | 3.903987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFE0ECFF)` L375 | 面/复用 | #E0ECFF | 1.068576 | 1.192393 | 17.611640 | 装饰面豁免；分层强弱见三向值 |
| `Color.fromRGBO(120,120,128,0.16)` L380 | 面/复用 | #787880 / α=0.160000 | 1.195601 | 1.208629 | 1.133049 | 装饰面豁免；分层强弱见三向值 |
| `Color.fromRGBO(120,120,128,0.10)` L385 | 面/复用 | #787880 / α=0.100000 | 1.116530 | 1.123899 | 1.073930 | 装饰面豁免；分层强弱见三向值 |
| `Color.fromRGBO(0,95,184,0.28)` L390 | 复用色；按承载面判级 | #005FB8 / α=0.280000 | 1.532466 | 1.559295 | 1.201856 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFF0FAF2)` L402 | 复用色；按承载面判级 | #F0FAF2 | 1.044745 | 1.068080 | 19.661457 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFFFF4E8)` L405 | 复用色；按承载面判级 | #FFF4E8 | 1.028595 | 1.084850 | 19.357512 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFFFF4F3)` L408 | 复用色；按承载面判级 | #FFF4F3 | 1.035448 | 1.077670 | 19.486486 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFFF3F2FF)` L411 | 复用色；按承载面判级 | #F3F2FF | 1.007248 | 1.107841 | 18.955790 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `Color(0xFF005FB8)` L415 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF00508F)` L439 | 复用色；按承载面判级 | #00508F | 7.397270 | 8.254398 | 2.544098 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF0A84FF)` L440 | 其他主题定义豁免 | #0A84FF | 3.268723 | 3.647472 | 5.757412 | 其他主题定义豁免 |
| `Color(0xFF004A94)` L441 | 其他主题定义豁免 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 其他主题定义豁免 |
| `Color(0xFF45A3FF)` L442 | 其他主题定义豁免 | #45A3FF | 2.371418 | 2.646196 | 7.935919 | 其他主题定义豁免 |

#### `lib/app/theme/status_colors.dart`

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `statusGreenText` L17 | 复用色；按承载面判级 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF1E7A34)` L19 | 文字/复用 | #1E7A34 | 4.839624 | 5.400396 | 3.888604 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF34C759)` L20 | 其他主题定义豁免 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 其他主题定义豁免 |
| `Color(0xFF0E6B2C)` L21 | 其他主题定义豁免 | #0E6B2C | 5.959045 | 6.649525 | 3.158120 | 其他主题定义豁免 |
| `Color(0xFF40DD74)` L22 | 其他主题定义豁免 | #40DD74 | 1.593139 | 1.777737 | 11.812769 | 其他主题定义豁免 |
| `statusOrangeText` L26 | 复用色；按承载面判级 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFB25000)` L28 | 文字/复用 | #B25000 | 4.657733 | 5.197428 | 4.040460 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF9500)` L29 | 其他主题定义豁免 | #FF9500 | 1.970414 | 2.198728 | 9.550978 | 其他主题定义豁免 |
| `Color(0xFF9A3F00)` L30 | 其他主题定义豁免 | #9A3F00 | 6.100271 | 6.807114 | 3.085008 | 其他主题定义豁免 |
| `Color(0xFFFFB340)` L31 | 其他主题定义豁免 | #FFB340 | 1.598375 | 1.783580 | 11.774073 | 其他主题定义豁免 |
| `statusBlueText` L35 | 复用色；按承载面判级 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF005FB8)` L37 | 文字/复用 | #005FB8 | 5.653126 | 6.308159 | 3.329022 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF0A84FF)` L38 | 其他主题定义豁免 | #0A84FF | 3.268723 | 3.647472 | 5.757412 | 其他主题定义豁免 |
| `Color(0xFF004A94)` L39 | 其他主题定义豁免 | #004A94 | 7.818165 | 8.724063 | 2.407135 | 其他主题定义豁免 |
| `Color(0xFF45A3FF)` L40 | 其他主题定义豁免 | #45A3FF | 2.371418 | 2.646196 | 7.935919 | 其他主题定义豁免 |
| `statusGreyText` L44 | 复用色；按承载面判级 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF595959)` L46 | 文字/复用 | #595959 | 6.277365 | 7.004729 | 2.997975 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8E8E93)` L47 | 其他主题定义豁免 | #8E8E93 | 2.921958 | 3.260528 | 6.440674 | 其他主题定义豁免 |
| `Color(0xFF3E3E44)` L48 | 其他主题定义豁免 | #3E3E44 | 9.517489 | 10.620289 | 1.977347 | 其他主题定义豁免 |
| `Color(0xFFAEAEB6)` L49 | 其他主题定义豁免 | #AEAEB6 | 1.974827 | 2.203652 | 9.529635 | 其他主题定义豁免 |
| `statusTealText` L53 | 复用色；按承载面判级 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `Color(0xFF0E7C86)` L55 | 文字/复用 | #0E7C86 | 4.432283 | 4.945856 | 4.245979 | 正文 AA：页面不达 / 白卡达；反色见局部组合 |
| `Color(0xFF30B0C7)` L56 | 其他主题定义豁免 | #30B0C7 | 2.306152 | 2.573367 | 8.160514 | 其他主题定义豁免 |
| `Color(0xFF0A6169)` L57 | 其他主题定义豁免 | #0A6169 | 6.430090 | 7.175151 | 2.926768 | 其他主题定义豁免 |
| `Color(0xFF40C4D6)` L58 | 其他主题定义豁免 | #40C4D6 | 1.866081 | 2.082305 | 10.084977 | 其他主题定义豁免 |
| `statusYellowText` L66 | 复用色；按承载面判级 | #8A6100 | 4.964839 | 5.540119 | 3.790532 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFF8A6100)` L68 | 文字/复用 | #8A6100 | 4.964839 | 5.540119 | 3.790532 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFFD60A)` L69 | 其他主题定义豁免 | #FFD60A | 1.265168 | 1.411764 | 14.875010 | 其他主题定义豁免 |
| `Color(0xFF6E4E00)` L70 | 其他主题定义豁免 | #6E4E00 | 6.836562 | 7.628721 | 2.752755 | 其他主题定义豁免 |
| `Color(0xFFFFE04F)` L71 | 其他主题定义豁免 | #FFE04F | 1.174218 | 1.310275 | 16.027164 | 其他主题定义豁免 |
| `statusRedText` L78 | 复用色；按承载面判级 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFB3001B)` L80 | 文字/复用 | #B3001B | 6.417374 | 7.160960 | 2.932568 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color(0xFFFF453A)` L81 | 其他主题定义豁免 | #FF453A | 3.052940 | 3.406687 | 6.164346 | 其他主题定义豁免 |
| `Color(0xFF8F0018)` L82 | 其他主题定义豁免 | #8F0018 | 8.628321 | 9.628092 | 2.181118 | 其他主题定义豁免 |
| `Color(0xFFFF6961)` L83 | 其他主题定义豁免 | #FF6961 | 2.527705 | 2.820593 | 7.445244 | 其他主题定义豁免 |
| `secondaryText` L102 | 复用色；按承载面判级 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color.fromARGB(0xBD,0x3C,0x3C,0x43)` L104 | 文字/复用 | #3C3C43 / α=0.741176 | 4.734341 | 5.035494 | 1.521987 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `Color.fromARGB(0x99,0xEB,0xEB,0xF5)` L105 | 其他主题定义豁免 | #EBEBF5 / α=0.600000 | 1.036118 | 1.105316 | 6.363811 | 其他主题定义豁免 |
| `Color.fromARGB(0xCC,0x3C,0x3C,0x43)` L106 | 其他主题定义豁免 | #3C3C43 / α=0.800000 | 5.559067 | 5.969965 | 1.600976 | 其他主题定义豁免 |
| `Color.fromARGB(0xAD,0xEB,0xEB,0xF5)` L107 | 其他主题定义豁免 | #EBEBF5 / α=0.678431 | 1.040970 | 1.120194 | 8.024222 | 其他主题定义豁免 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/theme/layout_tokens.dart`、`lib/app/theme/page_surface.dart`、`lib/app/theme/theme_provider.dart`、`lib/app/theme/typography_tokens.dart`、`lib/app/theme/ui_scale_provider.dart`。

### 本地化

语言 Provider/Resolver，无颜色或可视页面；不改文案。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/locale/locale_provider.dart`、`lib/app/locale/locale_resolver.dart`。

### 应用壳接线

CupertinoApp 使用 buildCupertinoTheme；Material 桥接在 main.dart，不是本轮功能页改造范围。这里只读审计，保留路由/本地化/启动逻辑。

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/app/app.dart`、`lib/app/deep_link.dart`、`lib/app/router.dart`。

### 启动与 Material 桥接

Material 桥接把 Cupertino 的面和语义色传给依赖组件；错误页/详情使用红色文字与反色按钮。属于允许的壳桥接例外，不据此向业务 UI 引入 Material。

#### `lib/main.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.secondarySystemGroupedBackground` L113 | 面/复用 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.tertiarySystemGroupedBackground` L115 | 面/复用 | #F2F2F7 | 1.000000 | 1.115871 | 18.819381 | 装饰面豁免；分层强弱见三向值 |
| `CupertinoColors.label` L116 | 文字/复用 | #000000 | 18.819381 | 21.000000 | 1.000000 | 正文 AA：页面达 / 白卡达；反色见局部组合 |
| `CupertinoColors.secondaryLabel` L118 | 文字/复用 | #3C3C43 / α=0.600000 | 3.295321 | 3.438200 | 1.358277 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemRed` L119 | 复用色；按承载面判级 | #FF3B30 | 3.178807 | 3.547138 | 5.920266 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.activeBlue` L120 | 复用色；按承载面判级 | #007AFF | 3.599857 | 4.016976 | 5.227813 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.systemGreen` L121 | 复用色；按承载面判级 | #34C759 | 1.989440 | 2.219959 | 9.459636 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `CupertinoColors.separator` L122 | 装饰线/投影豁免 | #3C3C43 / α=0.286275 | 1.660195 | 1.684855 | 1.114966 | 装饰线/投影豁免 |
| `redColor @ 0.35` L134 | 装饰线/投影豁免 | #FF3B30 / α=0.350000 | 1.576119 | 1.616708 | 1.539928 | 装饰线/投影豁免 |
| `CupertinoColors.white` L212 | 文字 | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |
| `separatorColor @ 0.4` L227 | 装饰线/投影豁免 | #3C3C43 / α=0.400000 | 2.090916 | 2.139428 | 1.185133 | 装饰线/投影豁免 |

### 核心层

模型/API/缓存不渲染 UI。accessibility.dart 的 AccessibleButton 复用 CupertinoButton 颜色；数据解析中的整数不是颜色。

#### `lib/core/utils/accessibility.dart`

默认控件：`CupertinoButton`。

参考页面 P=#F2F2F7；C=#FFFFFF；L=#000000。

| 来源 / 行号 | 用途 | 浅色 RGB / alpha | 对 P | 对 C | 对 L | 判级 / 豁免 |
|---|---|---|---:|---:|---:|---|
| `CupertinoColors.quaternarySystemFill` L17,30 | 复用色；按承载面判级 | #747480 / α=0.078431 | 1.092772 | 1.098258 | 1.055643 | 正文 AA：页面不达 / 白卡不达；反色见局部组合 |

无自有颜色/标准页面构造的文件（Provider/模型/路由/工具或纯委托组件）：`lib/core/api/api_client.dart`、`lib/core/api/api_client_chat.dart`、`lib/core/api/api_client_cron.dart`、`lib/core/api/api_client_extensions.dart`、`lib/core/api/api_client_git.dart`、`lib/core/api/api_client_kanban.dart`、`lib/core/api/api_client_mcp.dart`、`lib/core/api/api_client_memory_skills.dart`、`lib/core/api/api_client_prompts.dart`、`lib/core/api/api_client_server_panels.dart`、`lib/core/api/api_client_sessions.dart`、`lib/core/api/api_client_upload.dart`、`lib/core/api/api_client_workspace.dart`、`lib/core/api/api_exception.dart`、`lib/core/api/cookie_store.dart`、`lib/core/api/custom_header.dart`、`lib/core/api/endpoints.dart`、`lib/core/api/sse_channel_base.dart`、`lib/core/api/sse_client.dart`、`lib/core/api/stream_toggle_controller.dart`、`lib/core/api/ws_client.dart`、`lib/core/cache/app_database.dart`、`lib/core/cache/app_database.g.dart`、`lib/core/cache/app_database_connection.dart`、`lib/core/cache/app_database_connection_native.dart`、`lib/core/cache/app_database_connection_web.dart`、`lib/core/cache/cache_providers.dart`、`lib/core/cache/cache_service.dart`、`lib/core/cache/media_cache_service.dart`、`lib/core/connections/connection_providers.dart`、`lib/core/connections/connection_store.dart`、`lib/core/connections/server_connection.dart`、`lib/core/install/install_detector.dart`、`lib/core/install/llm_onboarding.dart`、`lib/core/install/powershell_installer.dart`、`lib/core/install/webui_bootstrap.dart`、`lib/core/models/approval.dart`、`lib/core/models/auxiliary_model.dart`、`lib/core/models/chat_message.dart`、`lib/core/models/clarification.dart`、`lib/core/models/context_window_snapshot.dart`、`lib/core/models/cron.dart`、`lib/core/models/extensions.dart`、`lib/core/models/git_workspace.dart`、`lib/core/models/goal.dart`、`lib/core/models/insights.dart`、`lib/core/models/json_value.dart`、`lib/core/models/kanban.dart`、`lib/core/models/mcp.dart`、`lib/core/models/memory.dart`、`lib/core/models/message_attachment.dart`、`lib/core/models/model_favorite.dart`、`lib/core/models/saved_prompt.dart`、`lib/core/models/server_account.dart`、`lib/core/models/server_catalog.dart`、`lib/core/models/server_info.dart`、`lib/core/models/session.dart`、`lib/core/models/skills.dart`、`lib/core/models/slash_skill_formatter.dart`、`lib/core/models/system_health.dart`、`lib/core/models/tool_call.dart`、`lib/core/models/transcribe_response.dart`、`lib/core/models/turn_file_change.dart`、`lib/core/models/upload_response.dart`、`lib/core/models/workspace.dart`、`lib/core/pairing/lan_address_selector.dart`、`lib/core/pairing/pairing_client.dart`、`lib/core/pairing/pairing_contract.dart`、`lib/core/pairing/pairing_runtime_providers.dart`、`lib/core/pairing/pairing_service.dart`、`lib/core/platform/external_opener.dart`、`lib/core/platform/test_environment.dart`、`lib/core/platform_paths.dart`、`lib/core/providers/catalog_providers.dart`、`lib/core/providers/clipboard_paste_provider.dart`、`lib/core/providers/file_picker_provider.dart`、`lib/core/tailscale/tailscale_contract.dart`、`lib/core/tailscale/tailscale_service.dart`、`lib/core/update/apk_installer.dart`、`lib/core/update/github_release.dart`、`lib/core/update/update_checker_service.dart`、`lib/core/update/update_providers.dart`、`lib/core/update/version_info.dart`、`lib/core/utils/attachment_audio_detection.dart`、`lib/core/utils/clipboard_paste.dart`、`lib/core/utils/context_window_formatter.dart`、`lib/core/utils/equality.dart`、`lib/core/utils/file_picker.dart`、`lib/core/utils/injected_message.dart`、`lib/core/utils/injection_markers.dart`、`lib/core/utils/lossy_json.dart`、`lib/core/utils/safe_clipboard.dart`、`lib/core/utils/selected_context.dart`、`lib/core/utils/uuid.dart`、`lib/driver_main.dart`、`lib/l10n/app_localizations.dart`。

## 附录：脚本实算输出

以下表与上文逐页数字全部由同一脚本输出，正文不手填比值。执行默认命令输出本报告全文，`--check-report` 会进行全文比对。

### A. 浅色令牌三向矩阵

| token | 不透明 RGB | 对 page | 对 card | 对 textSecondary |
|---|---|---:|---:|---:|
| page | #F2F2F2 | 1.000000 | 1.119495 | 4.804950 |
| card | #FFFFFF | 1.119495 | 1.000000 | 5.379116 |
| cardBorder | #CCD0DA | 1.379074 | 1.543866 | 3.484185 |
| divider | #CCD0DA | 1.379074 | 1.543866 | 3.484185 |
| textSecondary | #6A6A6F | 4.804950 | 5.379116 | 1.000000 |
| selection | #E0ECFF | 1.065117 | 1.192393 | 4.511193 |
| pressed | #F2F2F2 | 1.000000 | 1.119495 | 4.804950 |
| placeholder | #6A6A6F | 4.804950 | 5.379116 | 1.000000 |
| tintGreen | #F0FAF2 | 1.048138 | 1.068080 | 5.036250 |
| tintWarning | #FFF4E8 | 1.031935 | 1.084850 | 4.958395 |
| tintError | #FFF4F3 | 1.038810 | 1.077670 | 4.991432 |
| tintClarification | #F3F2FF | 1.010519 | 1.107841 | 4.855495 |
| userDetail | #005FB8 | 5.634827 | 6.308159 | 1.172713 |

### B. 实际局部组合与通用语义色

“面/旧页面”用于看层级；“字/旧页面”用于复核上下文；AA 按“字/实际面”判级。RGB 展示为最接近整字节，计算仍使用未经取整的 alpha 合成结果。

| 组合 / 来源 | 前景 | 实际承载面 | 面/旧页面 | 字/旧页面 | 字/实际面 | 判级 |
|---|---|---|---:|---:|---:|---|
| 旧页面/label · `Flutter colors.dart + 默认控件` | #000000 | #F2F2F7 | 1.000000 | 18.819381 | 18.819381 | 正文 AA 达 |
| 旧页面/secondaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.600000 | #F2F2F7 | 1.000000 | 3.295321 | 3.295321 | 正文 AA 不达标 |
| 旧页面/tertiaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F7 | 1.000000 | 1.698832 | 1.698832 | 正文 AA 不达标 |
| 旧页面/placeholderText · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F7 | 1.000000 | 1.698832 | 1.698832 | 正文 AA 不达标 |
| 旧页面/systemGrey · `Flutter colors.dart + 默认控件` | #8E8E93 | #F2F2F7 | 1.000000 | 2.921958 | 2.921958 | 正文 AA 不达标 |
| 旧页面/activeBlue · `Flutter colors.dart + 默认控件` | #007AFF | #F2F2F7 | 1.000000 | 3.599857 | 3.599857 | 正文 AA 不达标 |
| 白卡/label · `Flutter colors.dart + 默认控件` | #000000 | #FFFFFF | 1.115871 | 18.819381 | 21.000000 | 正文 AA 达 |
| 白卡/secondaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.600000 | #FFFFFF | 1.115871 | 3.295321 | 3.438200 | 正文 AA 不达标 |
| 白卡/tertiaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #FFFFFF | 1.115871 | 1.698832 | 1.725396 | 正文 AA 不达标 |
| 白卡/placeholderText · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #FFFFFF | 1.115871 | 1.698832 | 1.725396 | 正文 AA 不达标 |
| 白卡/systemGrey · `Flutter colors.dart + 默认控件` | #8E8E93 | #FFFFFF | 1.115871 | 2.921958 | 3.260528 | 正文 AA 不达标 |
| 白卡/activeBlue · `Flutter colors.dart + 默认控件` | #007AFF | #FFFFFF | 1.115871 | 3.599857 | 4.016976 | 正文 AA 不达标 |
| 新页面/label · `Flutter colors.dart + 默认控件` | #000000 | #F2F2F2 | 1.003248 | 18.819381 | 18.758462 | 正文 AA 达 |
| 新页面/secondaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.600000 | #F2F2F2 | 1.003248 | 3.295321 | 3.291332 | 正文 AA 不达标 |
| 新页面/tertiaryLabel · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F2 | 1.003248 | 1.698832 | 1.698090 | 正文 AA 不达标 |
| 新页面/placeholderText · `Flutter colors.dart + 默认控件` | #3C3C43 / α=0.298039 | #F2F2F2 | 1.003248 | 1.698832 | 1.698090 | 正文 AA 不达标 |
| 新页面/systemGrey · `Flutter colors.dart + 默认控件` | #8E8E93 | #F2F2F2 | 1.003248 | 2.921958 | 2.912500 | 正文 AA 不达标 |
| 新页面/activeBlue · `Flutter colors.dart + 默认控件` | #007AFF | #F2F2F2 | 1.003248 | 3.599857 | 3.588204 | 正文 AA 不达标 |
| statusGreenText/页面 · `status_colors.dart / diagnostics_models.dart` | #1E7A34 | #F2F2F7 | 1.000000 | 4.839624 | 4.839624 | 正文 AA 达 |
| statusGreenText/白卡 · `status_colors.dart / diagnostics_models.dart` | #1E7A34 | #FFFFFF | 1.115871 | 4.839624 | 5.400396 | 正文 AA 达 |
| statusOrangeText/页面 · `status_colors.dart / diagnostics_models.dart` | #B25000 | #F2F2F7 | 1.000000 | 4.657733 | 4.657733 | 正文 AA 达 |
| statusOrangeText/白卡 · `status_colors.dart / diagnostics_models.dart` | #B25000 | #FFFFFF | 1.115871 | 4.657733 | 5.197428 | 正文 AA 达 |
| statusBlueText/页面 · `status_colors.dart / diagnostics_models.dart` | #005FB8 | #F2F2F7 | 1.000000 | 5.653126 | 5.653126 | 正文 AA 达 |
| statusBlueText/白卡 · `status_colors.dart / diagnostics_models.dart` | #005FB8 | #FFFFFF | 1.115871 | 5.653126 | 6.308159 | 正文 AA 达 |
| statusGreyText/页面 · `status_colors.dart / diagnostics_models.dart` | #595959 | #F2F2F7 | 1.000000 | 6.277365 | 6.277365 | 正文 AA 达 |
| statusGreyText/白卡 · `status_colors.dart / diagnostics_models.dart` | #595959 | #FFFFFF | 1.115871 | 6.277365 | 7.004729 | 正文 AA 达 |
| statusTealText/页面 · `status_colors.dart / diagnostics_models.dart` | #0E7C86 | #F2F2F7 | 1.000000 | 4.432283 | 4.432283 | 正文 AA 不达标 |
| statusTealText/白卡 · `status_colors.dart / diagnostics_models.dart` | #0E7C86 | #FFFFFF | 1.115871 | 4.432283 | 4.945856 | 正文 AA 达 |
| statusRedText/页面 · `status_colors.dart / diagnostics_models.dart` | #B3001B | #F2F2F7 | 1.000000 | 6.417374 | 6.417374 | 正文 AA 达 |
| statusRedText/白卡 · `status_colors.dart / diagnostics_models.dart` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| secondaryText/页面 · `status_colors.dart / diagnostics_models.dart` | #3C3C43 / α=0.741176 | #F2F2F7 | 1.000000 | 4.734341 | 4.734341 | 正文 AA 达 |
| secondaryText/白卡 · `status_colors.dart / diagnostics_models.dart` | #3C3C43 / α=0.741176 | #FFFFFF | 1.115871 | 4.734341 | 5.035494 | 正文 AA 达 |
| _statusDebugText/页面 · `status_colors.dart / diagnostics_models.dart` | #4A6B82 | #F2F2F7 | 1.000000 | 5.063617 | 5.063617 | 正文 AA 达 |
| _statusDebugText/白卡 · `status_colors.dart / diagnostics_models.dart` | #4A6B82 | #FFFFFF | 1.115871 | 5.063617 | 5.650343 | 正文 AA 达 |
| 聊天用户气泡/正文 · `chat/widgets/message_bubble.dart + markdown_styles.dart` | #FFFFFF | #007AFF | 3.599857 | 1.115871 | 4.016976 | 正文 AA 不达标；Leader 指定保留主气泡 |
| 旧方案参考/用户白色代码或引用底 α=0.22 · `chat/widgets/markdown_styles.dart` | #FFFFFF | #3897FF | 2.667098 | 1.115871 | 2.976137 | 正文 AA 不达标 |
| 旧方案参考/用户白色代码或引用底 α=0.15 · `chat/widgets/markdown_styles.dart` | #FFFFFF | #268EFF | 2.943475 | 1.115871 | 3.284538 | 正文 AA 不达标 |
| 旧方案参考/用户白色代码或引用底 α=0.12 · `chat/widgets/markdown_styles.dart` | #FFFFFF | #1F8AFF | 3.067982 | 1.115871 | 3.423472 | 正文 AA 不达标 |
| 非聊天共享默认/assistant 代码引用 · `chat/widgets/markdown_styles.dart` | #000000 | #E5E5EA | 1.125061 | 18.819381 | 16.727430 | 正文 AA 达 |
| 绿色提示卡/正文 · `chat/chat_page.dart bgColor` | #000000 | #F0FAF2 | 1.044745 | 18.819381 | 19.661457 | 正文 AA 达 |
| 绿色提示卡/装饰勾 · `chat/chat_page.dart：已有文字重复语义` | #1E7A34 | #F0FAF2 | 1.044745 | 4.839624 | 5.056174 | 装饰豁免 |
| 绿色提示卡/灰色关闭图标 · `chat/chat_page.dart` | #6A6A6F | #F0FAF2 | 1.044745 | 4.820554 | 5.036250 | 非文本 达 |
| 旧方案参考/聊天提示条/systemBlue · `chat/chat_page.dart` | #007AFF | #DAE6F8 | 1.130522 | 3.599857 | 3.184243 | 正文 AA 不达标 |
| 旧方案参考/聊天提示条/systemRed · `chat/chat_page.dart` | #FF3B30 | #F3E0E3 | 1.136301 | 3.178807 | 2.797505 | 正文 AA 不达标 |
| 旧方案参考/聊天提示条/systemIndigo · `chat/chat_page.dart` | #5856D6 | #E0DFF3 | 1.173728 | 5.062968 | 4.313580 | 正文 AA 不达标 |
| P0/textSecondary/page · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F2F2F2 | 1.003248 | 4.820554 | 4.804950 | 正文 AA 达 |
| P0/cardBorder/page · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F2F2F2 | 1.003248 | 1.383553 | 1.379074 | 装饰豁免 |
| P0/textSecondary/card · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #FFFFFF | 1.115871 | 4.820554 | 5.379116 | 正文 AA 达 |
| P0/cardBorder/card · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #FFFFFF | 1.115871 | 1.383553 | 1.543866 | 装饰豁免 |
| P0/textSecondary/selection · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #E0ECFF | 1.068576 | 4.820554 | 4.511193 | 正文 AA 达 |
| P0/cardBorder/selection · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #E0ECFF | 1.068576 | 1.383553 | 1.294763 | 装饰豁免 |
| P0/textSecondary/pressed · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F2F2F2 | 1.003248 | 4.820554 | 4.804950 | 正文 AA 达 |
| P0/cardBorder/pressed · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F2F2F2 | 1.003248 | 1.383553 | 1.379074 | 装饰豁免 |
| P0/textSecondary/tintGreen · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F0FAF2 | 1.044745 | 4.820554 | 5.036250 | 正文 AA 达 |
| P0/cardBorder/tintGreen · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F0FAF2 | 1.044745 | 1.383553 | 1.445460 | 装饰豁免 |
| P0/textSecondary/tintWarning · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #FFF4E8 | 1.028595 | 4.820554 | 4.958395 | 正文 AA 达 |
| P0/cardBorder/tintWarning · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #FFF4E8 | 1.028595 | 1.383553 | 1.423115 | 装饰豁免 |
| P0/textSecondary/tintError · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #FFF4F3 | 1.035448 | 4.820554 | 4.991432 | 正文 AA 达 |
| P0/cardBorder/tintError · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #FFF4F3 | 1.035448 | 1.383553 | 1.432597 | 装饰豁免 |
| P0/textSecondary/tintClarification · `chat_page + chat/widgets: metadata, fields, cards, menu selections` | #6A6A6F | #F3F2FF | 1.007248 | 4.820554 | 4.855495 | 正文 AA 达 |
| P0/cardBorder/tintClarification · `chat cards/fields: 0.5-1 logical pixel hairline` | #CCD0DA | #F3F2FF | 1.007248 | 1.383553 | 1.393581 | 装饰豁免 |
| P0/user detail/inline code · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/code block · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/link · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/attachment · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/user detail/blockquote · `chat/widgets/markdown_styles.dart + chat_media_view.dart` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P0/approval + queued warning · `chat_page + chat/widgets: light-only status colors` | #B25000 | #FFF4E8 | 1.028595 | 4.657733 | 4.790918 | 正文 AA 达 |
| P0/urgent clarification timer · `chat_page + chat/widgets: light-only status colors` | #B25000 | #F3F2FF | 1.007248 | 4.657733 | 4.691493 | 正文 AA 达 |
| P0/success tool/notice · `chat_page + chat/widgets: light-only status colors` | #1E7A34 | #F0FAF2 | 1.044745 | 4.839624 | 5.056174 | 正文 AA 达 |
| P0/failed tool/error banner · `chat_page + chat/widgets: light-only status colors` | #B3001B | #FFF4F3 | 1.035448 | 6.417374 | 6.644855 | 正文 AA 达 |
| P0/offline banner/selected menu · `chat_page + chat/widgets: light-only status colors` | #005FB8 | #E0ECFF | 1.068576 | 5.653126 | 5.290335 | 正文 AA 达 |
| P0/assistant link · `chat_page + chat/widgets: light-only status colors` | #005FB8 | #F2F2F2 | 1.003248 | 5.653126 | 5.634827 | 正文 AA 达 |
| P0/tool name + selected context title · `chat_page + chat/widgets: light-only status colors` | #005FB8 | #FFFFFF | 1.115871 | 5.653126 | 6.308159 | 正文 AA 达 |
| P0/dialog normal/statusBlueText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #005FB8 | #E8E8E8 | 1.094820 | 5.653126 | 5.163520 | 正文 AA 达 |
| P0/dialog normal/statusRedText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #B3001B | #E8E8E8 | 1.094820 | 6.417374 | 5.861577 | 正文 AA 达 |
| P0/dialog pressed/statusBlueText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #005FB8 | #E1E1E1 | 1.171901 | 5.653126 | 4.823893 | 正文 AA 达 |
| P0/dialog pressed/statusRedText · `SDK dialog surface over modal scrim + uniform chat page; arbitrary backdrop is not certified` | #B3001B | #E1E1E1 | 1.171901 | 6.417374 | 5.476036 | 正文 AA 达 |
| P0/clarification title · `chat/chat_page.dart` | #5856D6 | #F3F2FF | 1.007248 | 5.062968 | 5.099666 | 正文 AA 达 |
| P0/context warning ring · `chat/widgets/context_window_indicator.dart` | #B25000 | #F2F2F2 | 1.003248 | 4.657733 | 4.642655 | 非文本 达 |
| P0/media inverse secondary · `chat/widgets/chat_media_view.dart: fixed black lightbox, unchanged` | #8E8E93 | #000000 | 18.819381 | 2.921958 | 6.440674 | 正文 AA 达 |
| P0/green notice layering · `chat/chat_page.dart: paired with the explicit hairline` | #F0FAF2 | #F2F2F2 | 1.003248 | 1.044745 | 1.048138 | 装饰豁免 |
| P1/readable secondary/page · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #F2F2F2 | 1.003248 | 4.820554 | 4.804950 | 正文 AA 达 |
| P1/structural divider/page · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #F2F2F2 | 1.003248 | 1.383553 | 1.379074 | 装饰豁免 |
| P1/popover hairline/page · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #F2F2F2 | 1.003248 | 1.383553 | 1.379074 | 装饰豁免 |
| P1/readable secondary/card · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #FFFFFF | 1.115871 | 4.820554 | 5.379116 | 正文 AA 达 |
| P1/structural divider/card · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #FFFFFF | 1.115871 | 1.383553 | 1.543866 | 装饰豁免 |
| P1/popover hairline/card · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #FFFFFF | 1.115871 | 1.383553 | 1.543866 | 装饰豁免 |
| P1/readable secondary/selection · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #E0ECFF | 1.068576 | 4.820554 | 4.511193 | 正文 AA 达 |
| P1/structural divider/selection · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #E0ECFF | 1.068576 | 1.383553 | 1.294763 | 装饰豁免 |
| P1/popover hairline/selection · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #E0ECFF | 1.068576 | 1.383553 | 1.294763 | 装饰豁免 |
| P1/readable secondary/pressed · `sidebar toolbar, empty detail, menu title and disabled-message menu` | #6A6A6F | #F2F2F2 | 1.003248 | 4.820554 | 4.804950 | 正文 AA 达 |
| P1/structural divider/pressed · `sidebar resize handle and toolbar/menu separator; cursor and semantics unchanged` | #CCD0DA | #F2F2F2 | 1.003248 | 1.383553 | 1.379074 | 装饰豁免 |
| P1/popover hairline/pressed · `adaptive_popover + popover_dropdown: explicit 1px card boundary` | #CCD0DA | #F2F2F2 | 1.003248 | 1.383553 | 1.379074 | 装饰豁免 |
| P1/selected toolbar icon · `sidebar_utility_toolbar.dart` | #005FB8 | #E0ECFF | 1.068576 | 5.653126 | 5.290335 | 非文本 达 |
| P1/empty detail filled action · `empty_detail_pane.dart: local button fill only` | #FFFFFF | #005FB8 | 5.653126 | 1.115871 | 6.308159 | 正文 AA 达 |
| P1/popover action/statusBlueText/card · `adaptive_action_menu.dart: default/destructive rows` | #005FB8 | #FFFFFF | 1.115871 | 5.653126 | 6.308159 | 正文 AA 达 |
| P1/popover action/statusRedText/card · `adaptive_action_menu.dart: default/destructive rows` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/popover action/statusBlueText/pressed · `adaptive_action_menu.dart: default/destructive rows` | #005FB8 | #F2F2F2 | 1.003248 | 5.653126 | 5.634827 | 正文 AA 达 |
| P1/popover action/statusRedText/pressed · `adaptive_action_menu.dart: default/destructive rows` | #B3001B | #F2F2F2 | 1.003248 | 6.417374 | 6.396600 | 正文 AA 达 |
| P1/native sheet/normal/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #EFEFEF | 1.026734 | 7.397270 | 7.204658 | 正文 AA 达 |
| P1/native sheet/normal/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #EFEFEF | 1.026734 | 6.417374 | 6.250277 | 正文 AA 达 |
| P1/native sheet title + disabled message/page · `menu title and P0 empty-message labels, evaluated on the normal sheet surface` | #6A6A6F | #EFEFEF | 1.026734 | 4.820554 | 4.695035 | 正文 AA 达 |
| P1/native sheet/pressed/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #DADADA | 1.256645 | 7.397270 | 5.886524 | 正文 AA 达 |
| P1/native sheet/pressed/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #DADADA | 1.256645 | 6.417374 | 5.106753 | 正文 AA 达 |
| P1/native sheet/cancel/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #FFFFFF | 1.115871 | 7.397270 | 8.254398 | 正文 AA 达 |
| P1/native sheet/cancel/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/native sheet/cancel pressed/LightSurfaces.menuAction/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #ECECEC | 1.058697 | 7.397270 | 6.987143 | 正文 AA 达 |
| P1/native sheet/cancel pressed/statusRedText/page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #ECECEC | 1.058697 | 6.417374 | 6.061576 | 正文 AA 达 |
| P1/inherited navigation icons/page · `AppBackButton + NarrowNavigationDropdownButton: icon-only, original primary retained` | #007AFF | #F2F2F2 | 1.003248 | 3.599857 | 3.588204 | 非文本 达 |
| P1/inverse exit toast/page · `adaptive_shell.dart: retained fixed inverse content` | #FFFFFF | #2C2C2C | 12.591430 | 1.115871 | 14.050410 | 正文 AA 达 |
| P1/native sheet/normal/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #EFEFF0 | 1.026161 | 7.397270 | 7.208686 | 正文 AA 达 |
| P1/native sheet/normal/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #EFEFF0 | 1.026161 | 6.417374 | 6.253771 | 正文 AA 达 |
| P1/native sheet title + disabled message/global page · `menu title and P0 empty-message labels, evaluated on the normal sheet surface` | #6A6A6F | #EFEFF0 | 1.026161 | 4.820554 | 4.697660 | 正文 AA 达 |
| P1/native sheet/pressed/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #DADADB | 1.255914 | 7.397270 | 5.889948 | 正文 AA 达 |
| P1/native sheet/pressed/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #DADADB | 1.255914 | 6.417374 | 5.109723 | 正文 AA 达 |
| P1/native sheet/cancel/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #FFFFFF | 1.115871 | 7.397270 | 8.254398 | 正文 AA 达 |
| P1/native sheet/cancel/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/native sheet/cancel pressed/LightSurfaces.menuAction/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #ECECEC | 1.058697 | 7.397270 | 6.987143 | 正文 AA 达 |
| P1/native sheet/cancel pressed/statusRedText/global page · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #ECECEC | 1.058697 | 6.417374 | 6.061576 | 正文 AA 达 |
| P1/inherited navigation icons/global page · `AppBackButton + NarrowNavigationDropdownButton: icon-only, original primary retained` | #007AFF | #F2F2F7 | 1.000000 | 3.599857 | 3.599857 | 非文本 达 |
| P1/inverse exit toast/global page · `adaptive_shell.dart: retained fixed inverse content` | #FFFFFF | #2C2C2C | 12.580032 | 1.115871 | 14.037691 | 正文 AA 达 |
| P1/native sheet/normal/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #F2F2F2 | 1.006397 | 7.397270 | 7.350252 | 正文 AA 达 |
| P1/native sheet/normal/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #F2F2F2 | 1.006397 | 6.417374 | 6.376585 | 正文 AA 达 |
| P1/native sheet title + disabled message/card · `menu title and P0 empty-message labels, evaluated on the normal sheet surface` | #6A6A6F | #F2F2F2 | 1.006397 | 4.820554 | 4.789914 | 正文 AA 达 |
| P1/native sheet/pressed/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #DCDCDC | 1.230761 | 7.397270 | 6.010324 | 正文 AA 达 |
| P1/native sheet/pressed/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #DCDCDC | 1.230761 | 6.417374 | 5.214153 | 正文 AA 达 |
| P1/native sheet/cancel/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #FFFFFF | 1.115871 | 7.397270 | 8.254398 | 正文 AA 达 |
| P1/native sheet/cancel/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #FFFFFF | 1.115871 | 6.417374 | 7.160960 | 正文 AA 达 |
| P1/native sheet/cancel pressed/LightSurfaces.menuAction/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #00508F | #ECECEC | 1.058697 | 7.397270 | 6.987143 | 正文 AA 达 |
| P1/native sheet/cancel pressed/statusRedText/card · `adaptive_action_menu.dart + SDK/dialog.dart/route.dart; uniform local backdrop` | #B3001B | #ECECEC | 1.058697 | 6.417374 | 6.061576 | 正文 AA 达 |
| P1/inherited navigation icons/card · `AppBackButton + NarrowNavigationDropdownButton: icon-only, original primary retained` | #007AFF | #FFFFFF | 1.115871 | 3.599857 | 4.016976 | 非文本 达 |
| P1/inverse exit toast/card · `adaptive_shell.dart: retained fixed inverse content` | #FFFFFF | #2E2E2E | 12.186859 | 1.115871 | 13.598961 | 正文 AA 达 |
| P1/popover shadow alpha=0.35 · `popover_dropdown/adaptive_popover: decorative elevation shadow retained` | #C7C7CC / α=0.350000 | #F2F2F2 | 1.003248 | 1.146727 | 1.145569 | 装饰豁免 |
| P1/popover shadow alpha=0.5 · `popover_dropdown/adaptive_popover: decorative elevation shadow retained` | #C7C7CC / α=0.500000 | #F2F2F2 | 1.003248 | 1.218767 | 1.216964 | 装饰豁免 |
| 看板选中标签/白字 · `kanban/kanban_page.dart` | #FFFFFF | #007AFF | 3.599857 | 1.115871 | 4.016976 | 正文 AA 不达标 |
| 看板卡片/secondaryText · `kanban/kanban_page.dart` | #3C3C43 / α=0.741176 | #F2F2F7 | 1.000000 | 4.734341 | 4.734341 | 正文 AA 达 |
| 看板黄色提醒/正文 · `kanban/kanban_page.dart` | #000000 | #F5EAC6 | 1.075725 | 18.819381 | 17.494610 | 正文 AA 达 |
| 诊断日志级别标签/statusGreyText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #595959 | #E6E6E6 | 1.117439 | 6.277365 | 5.617635 | 正文 AA 达 |
| 诊断日志级别标签/_statusDebugText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #4A6B82 | #E4E9EC | 1.097919 | 5.063617 | 4.612014 | 正文 AA 达 |
| 诊断日志级别标签/statusBlueText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #005FB8 | #D9E7F4 | 1.128014 | 5.653126 | 5.011574 | 正文 AA 达 |
| 诊断日志级别标签/statusOrangeText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #B25000 | #F3E5D9 | 1.106606 | 4.657733 | 4.209025 | 正文 AA 不达标 |
| 诊断日志级别标签/statusRedText · `diagnostics/diagnostics_detail_sheet.dart + diagnostics_models.dart` | #B3001B | #F4D9DD | 1.193088 | 6.417374 | 5.378791 | 正文 AA 达 |
| 默认搜索框/页面 · `SDK/search_field.dart` | #3C3C43 / α=0.600000 | #E3E3E9 | 1.141332 | 3.295321 | 3.124865 | 正文 AA 不达标 |
| 默认搜索框/白卡 · `SDK/search_field.dart` | #3C3C43 / α=0.600000 | #EFEFF0 | 1.030757 | 3.295321 | 3.256252 | 正文 AA 不达标 |
| 默认列表按下行/secondaryLabel · `SDK/list_tile.dart` | #3C3C43 / α=0.600000 | #D1D1D6 | 1.363500 | 3.295321 | 2.899310 | 正文 AA 不达标 |
| 框架弹层/label · SDK/dialog.dart#_kDialogColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #F2F2F3 | 1.002603 | 18.819381 | 18.770514 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kDialogPressedColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #E1E1E1 | 1.171901 | 18.819381 | 16.058844 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetPressedColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #E4E4E5 | 1.141384 | 18.819381 | 16.488212 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetCancelColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #FFFFFF | 1.115871 | 18.819381 | 21.000000 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetCancelPressedColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #ECECEC | 1.058697 | 18.819381 | 17.775980 | 正文 AA 达 |
| 框架弹层/label · SDK/dialog.dart#_kActionSheetBackgroundColor · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #000000 | #FAFAFB | 1.068355 | 18.819381 | 20.105776 | 正文 AA 达 |
| 默认 ActionSheet 内容灰字 · `SDK/dialog.dart；以均匀旧页面作模糊下层参考` | #1D1D1D / α=0.521569 | #FAFAFB | 1.068355 | 3.393715 | 3.453471 | 正文 AA 不达标 |
| 用量柱形/默认蓝 · `insights/insights_page.dart` | #007AFF | #FFFFFF | 1.115871 | 3.599857 | 4.016976 | 非文本 达 |
| 用量柱形/触摸深蓝 · `insights/insights_page.dart` | #004999 | #FFFFFF | 1.115871 | 7.799167 | 8.702863 | 非文本 达 |
| 品牌图标承载面/黑色图标 · `onboarding/widgets/onboarding_hero_motion.dart` | #000000 | #E5E5EA | 1.125061 | 18.819381 | 16.727430 | 非文本 达 |
| Mermaid 深色节点/白字 · `chat/widgets/mermaid_block.dart：非浅色 UI 面` | #FFFFFF | #2C2C2E | 12.489479 | 1.115871 | 13.936646 | 深色图表配置豁免 |
| Mermaid 深色 cluster/白字 · `chat/widgets/mermaid_block.dart：非浅色 UI 面` | #FFFFFF | #1C1C1E | 15.247942 | 1.115871 | 17.014735 | 深色图表配置豁免 |
| 会话列表反色 tooltip/新页面 · `session_list/session_list_page.dart` | #FFFFFF | #0E0E0E | 17.271683 | 1.115871 | 19.272968 | 正文 AA 达 |
| 外壳反色 toast/新页面 · `app/shell/adaptive_shell.dart` | #FFFFFF | #2C2C2C | 12.591430 | 1.115871 | 14.050410 | 正文 AA 达 |
| 会话列表反色 tooltip/白卡 · `session_list/session_list_page.dart` | #FFFFFF | #0F0F0F | 17.178193 | 1.115871 | 19.168645 | 正文 AA 达 |
| 外壳反色 toast/白卡 · `app/shell/adaptive_shell.dart` | #FFFFFF | #2E2E2E | 12.186859 | 1.115871 | 13.598961 | 正文 AA 达 |

### C. SDK 默认面、控件文字与装饰实算

私有默认常量从上述同一 SDK 自动读取；动态背景按页面/白卡/黑色三个均匀下层分别合成。渐变/模糊上叠加任意内容时，仍需实际画面复核。

| SDK 来源 | RGB / alpha | 对页面 | 对白卡 | 对黑色 | 用途 |
|---|---|---:|---:|---:|---|
| `SDK/dialog.dart#_kActionSheetBackgroundColor` | #FCFCFC / α=0.784314 | 1.068355 | 1.020272 | 12.249161 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetButtonDividerColor` | #C9C9C9 / α=0.831373 | 1.382589 | 1.510333 | 8.739442 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetCancelColor` | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetCancelPressedColor` | #ECECEC | 1.058697 | 1.181369 | 17.775980 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kActionSheetContentTextColor` | #1D1D1D / α=0.521569 | 3.393715 | 3.492347 | 1.096533 | 文字：按实际面 AA |
| `SDK/dialog.dart#_kActionSheetPressedColor` | #E0E0E0 / α=0.792157 | 1.141384 | 1.242970 | 9.842179 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kDialogColor` | #F2F2F2 / α=0.800000 | 1.002603 | 1.094071 | 11.739865 | 装饰面/边框/状态背景豁免 |
| `SDK/dialog.dart#_kDialogPressedColor` | #E1E1E1 | 1.171901 | 1.307691 | 16.058844 | 装饰面/边框/状态背景豁免 |
| `SDK/list_section.dart#_kHeaderFooterColor` | #6C6C6C | 4.705791 | 5.251056 | 3.999196 | 文字：按实际面 AA |
| `SDK/nav_bar.dart#_kDefaultNavBarBorderColor` | #000000 / α=0.301961 | 2.101806 | 2.120350 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/nav_bar.dart#_kTransparentNavBarBorder` | #000000 / α=0.000000 | 1.000000 | 1.000000 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/route.dart#_kCupertinoPageTransitionBarrierColor` | #000000 / α=0.094118 | 1.234172 | 1.236599 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/route.dart#kCupertinoModalBarrierColor` | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/sliding_segmented_control.dart#_kDisabledContentColor` | #7A7A7A / α=0.450980 | 1.700408 | 1.762196 | 1.764608 | 装饰面/边框/状态背景豁免 |
| `SDK/sliding_segmented_control.dart#_kSeparatorColor` | #8E8E93 / α=0.301961 | 1.326122 | 1.358404 | 1.482935 | 装饰面/边框/状态背景豁免 |
| `SDK/sliding_segmented_control.dart#_kThumbColor` | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#_kClearButtonColor` | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 功能图标：3:1 |
| `SDK/text_field.dart#_kDefaultRoundedBorderDecoration` | #FFFFFF | 1.115871 | 1.000000 | 21.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#_kDefaultRoundedBorderSide` | #000000 / α=0.200000 | 1.598086 | 1.605929 | 1.000000 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#_kDisabledBackground` | #FAFAFA | 1.069082 | 1.043765 | 20.119467 | 装饰面/边框/状态背景豁免 |
| `SDK/text_field.dart#kMisspelledSelectionColor` | #FF9699 / α=0.384314 | 1.272901 | 1.318618 | 2.180202 | 装饰面/边框/状态背景豁免 |

### D. 复验边界

AA 数字评估的是指定颜色组合，不能代替字体大小/字重、模糊下层、动态透明度、照片内容或系统级通知的视觉验证。阶段一的截图和暗色比对证据在任务临时目录；全仓其余页本轮只读，下一阶段按优先级迁移并补对应状态截图。

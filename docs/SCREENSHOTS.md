# README 展示图（SCREENSHOTS）

> 面向**仓库维护者**。README 正文只呈现成品图 —— 工装、环境变量、测试文件路径一律留在本文件。
> 定调：README 是对外展示的窗口，读者要看的是产品，不是我们怎么造图。

## 1. 目录与命名

| 语言 | 目录 | 供谁引用 |
|---|---|---|
| 简体中文（默认） | `docs/screenshots/` | `README.zh-CN.md` |
| English | `docs/screenshots/en/` | `README.md` |

- 浅色：原名（`wide-chat.png`、`phone-chat.png`）；
- 暗色：同名加 `-dark`（`wide-chat-dark.png`）；
- 尺寸：宽屏 2560×1600（DPR 2 ⇒ 1280×800 逻辑，真字体 MiSans）；手机 780×1688；
- 两套目录文件名**逐个对应**，同一文件名在两边必须是同一界面（只差语言）。

README 里的取用口径：桌面暗色打头（`wide-chat-dark` 全宽作首图），桌面/手机各一行三张，末行「浅色 / 深色」三张。改版式时两边 README 同步改。

## 2. 生成（仓库根目录，Windows）

```bash
# 中文 · 浅色
README_SHOTS=1 flutter test test/screenshots/readme_shots_test.dart --update-goldens

# 中文 · 暗色
README_SHOTS=1 README_DARK=1 flutter test test/screenshots/readme_shots_test.dart --update-goldens

# 英文 · 浅色（产物落 docs/screenshots/en/）
README_SHOTS=1 README_LANG=en flutter test test/screenshots/readme_shots_test.dart --update-goldens

# 英文 · 暗色
README_SHOTS=1 README_LANG=en README_DARK=1 flutter test test/screenshots/readme_shots_test.dart --update-goldens
```

- 不带 `README_SHOTS=1` 时该文件整体 skip，日常 `flutter test` 与 CI 零影响；
- 不是金照基线，不参与 CI 比对，可以放心 `--update-goldens`；
- 本机若用 `C:/tmp/f.bat test` 之类的 flutter 包装脚本，把 `flutter test` 换成它即可；
- 临时取图（只为看一眼改动，不想动 README 基线）时，跑完 `git checkout -- docs/screenshots` 还原。

## 3. 红线

- **只录成品**：README 正文不得出现工装名、环境变量、测试路径、主题/语言的机制说明（口径来自一次返工：工装写进 README 被否）。
- **演示数据**：一律中性虚构文案（会话标题、项目名、聊天正文、看板卡片、模型名）；不得出现真实隐私（真路径、真令牌、真会话）。
- **语言一致**：英文图里不得出现中文界面文案，中文图同理。
- **成对更新**：改 UI 后两种主题 × 两种语言四套都要重录，不允许只重录其中一套。
- **改文案先看空态**：截图是首屏印象，空窗、长截断、缺图必须重录后再提交。

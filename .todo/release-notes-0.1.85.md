## 修复

**图片预览的「引用」按钮在手机上误报「当前没有打开的聊天会话」**

- 现象：从对话里点开图片 → 点引用 → 弹「引用失败 / 当前没有打开的聊天会话」，明明图就是从当前对话打开的。
- 真因：手机上从会话列表进入聊天页用的是 `push` 导航，而 go_router 的 `push` 不会更新 `currentConfiguration`（它停在基路由 `/`），被 push 的 `/chat/<id>` 只写进 `routeInformationProvider`。引用按钮原先只读 `currentConfiguration`，于是「人明明在聊天页里」也被判成不在聊天页。
- 修法：聊天页自己声明当前会话（`ChatSessionScope`），灯箱在打开瞬间取到来源会话并带走，不再靠路由猜；路由回退同时读两个来源兜底。
- 影响面：灯箱里所有未自带会话 id 的入口（实时流式图片、待发附件条）在 Android / Windows 桌面端都恢复可用。

## 安装

- Android：`HermesAnywhere-0.1.85-arm64-app-release.apk`（arm64，覆盖安装数据不丢）
- Windows：`HermesAnywhere-0.1.85-x64-setup.exe`
- Linux / macOS：紧随其后由 CI 补齐同名资产

> 说明：本次只做发布，未升级你电脑上已安装的那份（需要时说一声）。

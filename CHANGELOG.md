# Changelog / 更新记录

## 0.2.0 — 2026-11-08 · Two-point selection / 双点框选

### 中文

- 新增双点框选：Option 单击第一角后可松开按键，自由移动，第二次单击固定选区。
- 设置中可将双点设为默认；两次点击不限时，支持任意两个对角。
- Delete 重选第一点、Esc 取消；第二点确认后才显示工具栏并允许输出。
- 新增原始像素放大镜与实时尺寸提示，屏幕边缘自动调整位置。
- 保留直接拖拽、选区移动与四角调整；限制两个点在同一显示器。
- 增加 11 项核心检查（共 30 项）和真实 AppKit 事件回归检查。

### English

- Option-click anchors the first corner; release the modifier, move freely, and click the second corner to confirm.
- Optional two-point default, no timeout, and any pair of diagonal corners.
- Delete resets the first point; Escape cancels. Export actions are enabled only after confirmation.
- Source-pixel magnifier, live dimensions, and edge-aware positioning.
- Drag selection, movement, and corner resizing remain available; both points stay on one display.
- 11 new core checks (30 total) and AppKit event regression checks.

The name remains ishot. This preview is still ad-hoc signed and not notarized.
名称保留 ishot。本预览版仍使用 ad-hoc 签名，未公证。

## 0.1.0 — 2026-11-08 · Public preview / 公开预览版

### 中文

- 区域与全屏截图；基础批注、裁剪、撤销 / 重做、PNG 保存与复制。
- 多张悬浮贴图：拖动缩放、透明度、锁定、继续批注和统一显隐。
- 自定义快捷键、设置、登录项和首次使用引导。
- 中英文 README 和安装指南、应用截图、macOS CI。
- 提供 macOS 14+ Universal DMG，使用独立标识符 `io.github.sunholdshen.ishot`。

### English

- Region and display capture; annotations, crop, undo / redo, PNG save and copy.
- Multiple floating pins with movement, zoom, opacity, locking, editing, and batch visibility.
- Configurable shortcuts, settings, launch at login, and onboarding.
- Chinese and English documentation, screenshots, and macOS CI.
- Universal DMG for macOS 14+, with bundle ID `io.github.sunholdshen.ishot`.

This is an ad-hoc-signed, non-notarized preview. The app UI is Chinese only.
本版为 ad-hoc 签名、未公证的预览版；应用界面目前仅有中文。验证范围见 docs/QA.md。

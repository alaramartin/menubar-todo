# menubar-todo

A tiny to-do list that lives in the macOS menu bar. Your one **top goal** is shown as text in the middle of the menu bar.

- Click the checklist icon (or the goal text) to open a plain white popup.
- Type and press Return to add a task. Click the box to check it off. Hover a task to show:
  - ☆ to make it the top goal (there's only one; it moves to the top of the list)
  - ✕ to delete it
- The goal is centered in the menu bar. If app menus, the notch or other menu bar icons are in the way, it moves as close to the center as it can (with padding) and truncates with "…" if needed. A checked-off goal is hidden from the menu bar.
- Right-click the icon for **Open at Login** and **Quit**.

Everything is saved to `~/Library/Application Support/menubar-todo/todos.json` on every change, so your list is still there after you quit, restart or shut down. The app turns on Open at Login the first time it runs.

## Build & install

```sh
./build.sh --install   # builds, copies to /Applications, launches
```

Requires macOS 14+ and Swift 5.9+.

### Accessibility permission (optional)

On first launch macOS asks for Accessibility access. It's used only to measure how wide the current app's menus are so the goal doesn't cover them. Without it, the app assumes the menus take up to ~30% of the screen. Rebuilding changes the ad-hoc signature, so you may need to toggle the permission off and on again in System Settings → Privacy & Security → Accessibility.

# menubar-todo

A tiny to-do list that lives in the macOS menu bar. Your one **top goal** is shown as text in the middle of the menu bar.

- Click the checklist icon (or the goal text) to open a plain white popup.
- Type and press Return to add a task. Click the box to check it off. Double-click a task to edit it (Return saves, Escape cancels). Drag tasks to reorder them. Hover a task to show:
  - ☆ to make it the top goal (there's only one; it moves to the top of the list)
  - ✕ to delete it
- The goal is centered in the menu bar. If app menus, the notch or other menu bar icons are in the way, it moves as close to the center as it can (with padding) and truncates with "…" if needed. A checked-off goal is hidden from the menu bar.
- Right-click the icon for **Open at Login**, **Check for Updates…** and **Quit**.
- Once a day it checks GitHub for a newer release. If there is one, a link appears at the bottom of the popup and in the right-click menu.

Everything is saved to `~/Library/Application Support/menubar-todo/todos.json` on every change, so your list is still there after you quit, restart or shut down. The app turns on Open at Login the first time it runs.

## Install from a release

1. Download `MenubarTodo.zip` from the [latest release](https://github.com/alaramartin/menubar-todo/releases/latest) and unzip it.
2. Drag **Menubar Todo.app** into **Applications**. Keep it there: the open-at-login setting points at that copy.
3. Open it. The app isn't notarized by Apple, so macOS will block the first launch:
   - Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to "Menubar Todo", then confirm.
   - Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/Menubar Todo.app"`, then open it normally.

After the first launch it opens at login on its own, and your list is saved on disk, so it survives quitting, restarting and shutting down. Works on Apple silicon and Intel Macs running macOS 14 or later.

## Build & install from source

```sh
./build.sh --install   # builds, copies to /Applications, launches
./build.sh --zip       # builds build/MenubarTodo.zip for a release
VERSION=1.2.0 ./build.sh --zip   # set the version (bump it for each release so update notices work)
swift scripts/make-icon.swift    # regenerate Resources/AppIcon.icns
```

Requires macOS 14+ and Swift 5.9+.

### Accessibility permission (optional)

On first launch macOS asks for Accessibility access. It's used only to measure how wide the current app's menus are so the goal doesn't cover them. Without it, the app assumes the menus take up to ~30% of the screen. Rebuilding changes the ad-hoc signature, so you may need to toggle the permission off and on again in System Settings → Privacy & Security → Accessibility.

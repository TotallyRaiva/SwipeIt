# SwipeIt 🔒⌨️

**Lightweight, 100% free & open-source utility to lock your keyboard and trackpad with custom key combinations for cleaning or safety.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-black.svg)](#installation--setup)
[![Zero Ads](https://img.shields.io/badge/Ads%20%26%20Telemetry-Zero-brightgreen.svg)](#philosophy)
[![Download DMG](https://img.shields.io/badge/Download-SwipeIt.dmg-success.svg)](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt.dmg)
[![Website](https://img.shields.io/badge/Website-totallyraiva.github.io%2FSwipeIt-blue.svg)](https://totallyraiva.github.io/SwipeIt/)

---

## 🚨 Emergency Master Key ("Combowombo") — Phone Lookup Card

> **Forgot your custom unlock shortcut while your Mac is locked?**
>
> Hold all **4 keys simultaneously** to immediately unlock SwipeIt at any time:
>
> ### `Esc` + `← (Left Arrow)` + `↑ (Up Arrow)` + `→ (Right Arrow)`
>
> *Or wait for the **Auto-Unlock Safety Timer** (10 minutes by default) to automatically restore input.*

---

## ✨ Features

- **Two Independent Lock Modes**:
  - **Full Lock (`Keyboard + Trackpad/Mouse`)**: Blocks all keys, modifiers, media/volume/brightness buttons, cursor movement, mouse clicks, scroll wheel, and trackpad gestures. Also hides the cursor.
  - **Keyboard-Only Lock**: Blocks all keyboard and media keys while keeping your mouse and trackpad completely active (great for watching videos or cleaning just the keys).
- **Custom Key Combinations & Multi-Key Chords**:
  - Record your own shortcuts for **Lock All** (default `⌃⌥⌘L`), **Lock Keyboard Only** (default `⌃⌥⌘K`), and **Unlock** (default `⌃⌥⌘U`).
  - Supports both standard modifier shortcuts (`⌘`, `⌥`, `⌃`, `⇧` + Key) and multi-key chords.
  - Optional **Toggle Mode** if you want the same shortcut to both lock and unlock.
- **3 Screen Appearance Modes**:
  1. **Blackout Cleaning Screen**: Turns all connected displays pitch-black so dust, fingerprints, and smudges are easy to spot while wiping down your screen and keyboard.
  2. **Frosted Translucent Shield**: Dims and blurs the screen with a lock status indicator.
  3. **Stealth / No Screen Overlay**: Keeps your screen completely visible while blocking input (ideal when watching movies or keeping kids/pets from pressing keys).
- **Privacy / Safety Screen Toggle**:
  - Choose whether to **Show or Hide** the unlock shortcut hint on the screen while locked. Turn it **ON** when cleaning so you have a reminder, or turn it **OFF** when stepping away or protecting against kids so nobody watching the screen can read how to unlock it.
- **3-Layer Anti-Lockout Fail-Safe**:
  1. Custom Unlock Shortcut (`⌃⌥⌘U` by default)
  2. Hardcoded **Master Key** (`Esc + ← + ↑ + →` held simultaneously)
  3. Adjustable **Auto-Unlock Safety Timer** (1 to 120 minutes, **10 minutes** by default)

---

## 🧭 Philosophy

**SwipeIt** is a personal open-source project built for everyday utility:
- **100% Free Forever** under the [MIT License](LICENSE)
- **Zero Ads, Zero Subscriptions, Zero Commercial Bloat**
- **Zero Telemetry or Network Calls** — runs entirely locally using native OS APIs

---

## 🛠️ Installation & Setup (macOS)

### Option 1: Download Pre-Built DMG (Recommended)
1. Download the latest **[SwipeIt.dmg](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt.dmg)**.
2. Open the downloaded `.dmg` and drag **SwipeIt** to your **Applications** folder.
3. Open SwipeIt and grant **Accessibility Permission** when prompted (see below).

### Option 2: Build from Source
- Requires macOS 14.0+ and Xcode 16+
1. Clone the repository:
   ```bash
   git clone https://github.com/TotallyRaiva/SwipeIt.git
   cd SwipeIt
   ```
2. Open `SwipeIt.xcodeproj` in Xcode and press **`⌘R`** to build and run (or run `./scripts/build_dmg.sh` to package a release DMG).

### Granting Accessibility Permission
   - Open **System Settings → Privacy & Security → Accessibility**
   - Enable the toggle next to **SwipeIt**
   *(macOS requires Accessibility permission for any utility that intercepts and blocks low-level `CGEventTap` keyboard and trackpad events).*

---

## ⌨️ Default Shortcuts

| Action | Default Combination | Customizable? |
| :--- | :--- | :--- |
| **Lock Keyboard + Trackpad/Mouse** | `⌃⌥⌘L` (`Ctrl + Option + Cmd + L`) | ✅ Yes |
| **Lock Keyboard Only** | `⌃⌥⌘K` (`Ctrl + Option + Cmd + K`) | ✅ Yes |
| **Custom Unlock** | `⌃⌥⌘U` (`Ctrl + Option + Cmd + U`) | ✅ Yes |
| **Emergency Master Key** | `Esc + ← + ↑ + →` (simultaneously) | 🔒 Built-in Fail-Safe |

---

## 🗺️ Cross-Platform Roadmap

SwipeIt is architected with a clean separation between its core state/chord engine and OS-specific input hooks. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full technical details.

- [x] **macOS (v1.0)**: Native Swift & SwiftUI + Quartz Event Services (`CGEventTap`)
- [ ] **Linux (Planned)**: `evdev` / `uinput` grab (Wayland & X11 compatible)
- [ ] **Windows (Planned)**: Win32 Low-Level Hooks (`SetWindowsHookEx` with `WH_KEYBOARD_LL` & `WH_MOUSE_LL`)

---

## 📄 License

Released under the [MIT License](LICENSE).

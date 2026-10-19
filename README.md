# SwipeIt 🔒⌨️

**Lightweight, 100% free & open-source utility to lock your keyboard and trackpad with custom key combinations for cleaning or safety.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS | Windows | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-black.svg)](#installation--setup)
[![Zero Ads](https://img.shields.io/badge/Ads%20%26%20Telemetry-Zero-brightgreen.svg)](#philosophy)
[![Download macOS DMG](https://img.shields.io/badge/macOS-SwipeIt.dmg-success.svg)](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt.dmg)
[![Download Windows EXE](https://img.shields.io/badge/Windows-SwipeIt--Windows--x64.exe-0078D6.svg)](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt-Windows-x64.exe)
[![Download Linux Tarball](https://img.shields.io/badge/Linux-SwipeIt--Linux--x86__64.tar.gz-FCC624.svg)](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt-Linux-x86_64.tar.gz)
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
- **Built-in Update Checker**:
  - Automatically alerts you in the Menu Bar and Settings when a new version is published on GitHub Releases, with one-click DMG download.

---

## 🧭 Philosophy

**SwipeIt** is a personal open-source project built for everyday utility:
- **100% Free Forever** under the [MIT License](LICENSE)
- **Zero Ads, Zero Subscriptions, Zero Commercial Bloat**
- **Zero Telemetry & Zero Tracking** — runs entirely locally; optional update checker queries public GitHub Releases API only.

---

## 🛠️ Installation & Setup (macOS)

### Option 1: Download Pre-Built DMG (Recommended)
1. Download the latest **[SwipeIt.dmg](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt.dmg)**.
2. Open the downloaded `.dmg` and drag **SwipeIt** to your **Applications** folder.
3. Open SwipeIt and grant **Accessibility Permission** when prompted (see below).

#### ⚠️ First Launch: macOS Gatekeeper Notice
Because SwipeIt is an independent open-source project without a paid Apple Developer ID certificate (\$99/year), macOS Gatekeeper will show a security prompt on first launch:
> *"Apple cannot verify that SwipeIt is free of malware"* (or *«Apple не удалось подтвердить, что файл SwipeIt не содержит вредоносного ПО»*).

To open the app (one-time setup):
- **Method 1 (System Settings — Recommended)**:
  1. Open **System Settings → Privacy & Security** (Системные настройки → Конфиденциальность и безопасность).
  2. Scroll down to the **Security** (Безопасность) section.
  3. Click **"Open Anyway"** (Всё равно открыть / Подтвердить вход) next to *SwipeIt was blocked*.
- **Method 2 (Right-Click in Finder)**:
  In `/Applications`, **Right-click** (or `Control` + click) on `SwipeIt.app` and choose **Open**, then click **Open** in the dialog.
- **Method 3 (Terminal)**:
  ```bash
  xattr -cr /Applications/SwipeIt.app
  ```

### Option 2: Build from Source
- Requires macOS 14.0+ and Xcode 16+
1. Clone the repository:
   ```bash
   git clone https://github.com/TotallyRaiva/SwipeIt.git
   cd SwipeIt
   ```
2. Open `SwipeIt.xcodeproj` in Xcode and press **`⌘R`** to build and run (or run `./scripts/build_dmg.sh` to package a release DMG).

### Granting Accessibility Permission (macOS)
   - Open **System Settings → Privacy & Security → Accessibility**
   - Enable the toggle next to **SwipeIt**
   *(macOS requires Accessibility permission for any utility that intercepts and blocks low-level `CGEventTap` keyboard and trackpad events).*

---

## 🪟 Installation & Setup (Windows 10 / 11)

1. Download the standalone portable executable **[SwipeIt-Windows-x64.exe](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt-Windows-x64.exe)**.
2. Double-click `SwipeIt-Windows-x64.exe` to run (no installer or special OS permissions required — uses native Win32 `WH_KEYBOARD_LL` & `WH_MOUSE_LL` low-level hooks).
3. *(Optional)* If Windows SmartScreen appears on first launch, click **More info → Run anyway**.

---

## 🐧 Installation & Setup (Linux — Wayland & X11)

1. Download **[SwipeIt-Linux-x86_64.tar.gz](https://github.com/TotallyRaiva/SwipeIt/releases/latest/download/SwipeIt-Linux-x86_64.tar.gz)** and extract:
   ```bash
   tar -xzf SwipeIt-Linux-x86_64.tar.gz
   ./SwipeIt
   ```
2. **Wayland / Kernel `evdev` Permissions**: To allow SwipeIt to grab `/dev/input/event*` devices directly (`EVIOCGRAB`) on Wayland without running as root, add your user to the `input` group once and re-login:
   ```bash
   sudo usermod -aG input $USER
   ```

---

## ⌨️ Default Shortcuts

| Action | Default Combination | Customizable? |
| :--- | :--- | :--- |
| **Lock Keyboard + Trackpad/Mouse** | `⌃⌥⌘L` (macOS) / `Ctrl + Alt + Win/Super + L` | ✅ Yes |
| **Lock Keyboard Only** | `⌃⌥⌘K` (macOS) / `Ctrl + Alt + Win/Super + K` | ✅ Yes |
| **Custom Unlock** | `⌃⌥⌘U` (macOS) / `Ctrl + Alt + Win/Super + U` | ✅ Yes |
| **Emergency Master Key** | `Esc + ← + ↑ + →` (simultaneously) | 🔒 Built-in Fail-Safe |

---

## 🗺️ Cross-Platform Architecture

SwipeIt is architected with a clean separation between its core state/chord engine and OS-specific input hooks. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full technical details.

- [x] **macOS**: Native Swift & SwiftUI + Quartz Event Services (`CGEventTap`)
- [x] **Windows**: Rust (`eframe`/`egui`) + Win32 Low-Level Hooks (`SetWindowsHookExW` with `WH_KEYBOARD_LL` & dynamic `WH_MOUSE_LL`)
- [x] **Linux**: Rust (`eframe`/`egui`) + Kernel `evdev` (`EVIOCGRAB`, Wayland & X11 compatible)

---

## 📄 License

Released under the [MIT License](LICENSE).

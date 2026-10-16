# SwipeIt — Architecture & Cross-Platform Design

## 1. High-Level Overview

**SwipeIt** is designed around a strict separation between:
1. **Core Domain & Chord Matching Engine** (`LockMode`, `KeyCombo`, `SettingsStore`, `LockManager`)
2. **OS Platform Interception Layer** (`InputInterceptor`, `AccessibilityManager`, `OverlayWindowManager`)
3. **Declarative UI Layer** (`ContentView`, `MenuBarView`, `LockOverlayView`, `ShortcutRecorderRow`)

This separation keeps the macOS app tiny and native today while making it straightforward to port the input-blocking engine to **Linux** and **Windows** in future iterations.

---

## 2. macOS Event Interception (`InputInterceptor.swift`)

On macOS, blocking physical keyboard and trackpad/mouse input across the entire window server requires a **Quartz Event Tap** (`CGEvent.tapCreate`) configured with:
- **Tap Location**: `.cghidEventTap` (intercepts low-level HID events at the point they enter the window server)
- **Placement**: `.headInsertEventTap`
- **Options**: `.defaultTap` (an active filter capable of modifying or swallowing events by returning `nil`)

### Why App Sandbox Is Disabled (`ENABLE_APP_SANDBOX = NO`)
macOS App Sandbox prohibits active `CGEventTap` filtering (`.defaultTap`) for security reasons. Therefore, SwipeIt runs unsandboxed with **Hardened Runtime** enabled and requests explicit user authorization via **System Settings → Privacy & Security → Accessibility** (`AXIsProcessTrustedWithOptions`).

### Simultaneous Key-Chord Tracking & Master Key
Standard macOS `CGEvent` callbacks deliver one `keyDown` or `keyUp` event at a time. To support multi-key chords like the **Emergency Master Key (`Esc + ← + ↑ + →`)**:
1. `InputInterceptor` maintains a `Set<Int64>` (`pressedKeyCodes`) of all currently depressed physical virtual keycodes.
2. When `keyDown` arrives, its virtual keycode is inserted into `pressedKeyCodes`.
3. When `keyUp` arrives, its virtual keycode is removed from `pressedKeyCodes`.
4. Modifier flags (`CGEventFlags`) are masked with `KeyCombo.relevantModifierMask` (`Command | Option | Control | Shift`) so that macOS's automatic `.maskNumericPad` and `.maskSecondaryFn` flags on arrow keys never interfere with chord matching.
5. Whenever `KeyCombo.masterUnlockKey.keyCodes` (`[53, 123, 126, 124]`) is a subset of `pressedKeyCodes`, `InputInterceptor` immediately clears `pressedKeyCodes` and dispatches `.unlock(.masterKey)`.

---

## 3. Anti-Lockout Safety Architecture

Because locking both keyboard and mouse/trackpad disables normal system interaction, SwipeIt enforces three independent recovery mechanisms:

| Layer | Mechanism | Trigger |
| :--- | :--- | :--- |
| **Layer 1** | **Custom Unlock Shortcut** | User-configured key combo (default `⌃⌥⌘U`) or optional Toggle with Lock Shortcut |
| **Layer 2** | **Master Key ("Combowombo")** | Holding `Esc + ← + ↑ + →` simultaneously |
| **Layer 3** | **Auto-Unlock Safety Timer** | Countdown timer (`Timer` in `LockManager`, default `10 min`) that automatically unlocks when reaching `00:00` |

Additionally, if `CGEventTap` ever receives `.tapDisabledByTimeout` or `.tapDisabledByUserInput` from the macOS WindowServer, `InputInterceptor` immediately clears any held key state and re-enables the tap.

---

## 4. Future Cross-Platform Porting Guide (Linux & Windows)

When expanding SwipeIt to Linux and Windows, the domain logic (`LockMode`, `KeyCombo`, chord-set matching, and safety timer) remains identical; only the platform adapter changes:

### Linux Target
- **Wayland & X11 Unified Approach (`evdev` / `libevdev`)**:
  - Open `/dev/input/event*` devices corresponding to keyboards, mice, and touchpads.
  - Issue `ioctl(fd, EVIOCGRAB, 1)` to exclusively grab input events before they reach the compositor (Wayland) or XServer (X11).
  - Run the same `pressedKeyCodes` chord matcher on `input_event` (`EV_KEY`) structs; release the grab (`EVIOCGRAB, 0`) when the unlock combo, Master Key (`KEY_ESC + KEY_LEFT + KEY_UP + KEY_RIGHT`), or safety timer triggers.

### Windows Target
- **Win32 Low-Level Hooks (`User32.dll`)**:
  - Install `SetWindowsHookExW(WH_KEYBOARD_LL, ...)` and (in Full Lock mode) `SetWindowsHookExW(WH_MOUSE_LL, ...)`.
  - Inside `LowLevelKeyboardProc`, track virtual key codes (`vkCode`) in `pressedKeyCodes`.
  - Return a non-zero value (`1`) to swallow events while locked, or pass to `CallNextHookEx` when unlocked.

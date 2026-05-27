# BetterShortcuts

Global keyboard shortcuts for macOS apps. Shared package used by BetterAudio, BetterCap, and BetterCmdTab — one codebase, maintained once.

Derived from [Sindre Sorhus' KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), which was previously vendored (copy-pasted) into each app.

## Install

Swift Package Manager. In Xcode: **File ▸ Add Package Dependencies…** and enter the repo URL, or add to `Package.swift`:

```swift
.package(url: "https://github.com/rokartur/BetterShortcuts.git", from: "0.1.0")
```

Requires macOS 13+.

## Usage

Define your shortcut names:

```swift
import BetterShortcuts

extension BetterShortcuts.Name {
    static let toggleUnicornMode = Self("toggleUnicornMode")
}
```

Listen for presses:

```swift
BetterShortcuts.onKeyUp(for: .toggleUnicornMode) {
    isUnicornMode.toggle()
}
```

Let the user record a shortcut — SwiftUI:

```swift
BetterShortcuts.Recorder(for: .toggleUnicornMode)
```

…or AppKit via `BetterShortcuts.RecorderCocoa(for:)`.

### Friendly names in the conflict alert (optional)

The recorder warns when a shortcut is already used by another of your shortcuts. To show a human-readable label instead of the raw identifier:

```swift
BetterShortcuts.displayName = { $0.displayName } // your own `Name.displayName`
```

## Storage migration

Shortcuts are stored in `UserDefaults` under the `BetterShortcuts_` prefix. For backward compatibility with apps that previously vendored `KeyboardShortcuts`, the legacy `KeyboardShortcuts_` prefix is read as a fallback and migrated to the new prefix on the next write — existing users keep their shortcuts.

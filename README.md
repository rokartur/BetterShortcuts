# BetterShortcuts

Global keyboard shortcuts for macOS apps: a user-recordable hot key, stored in
`UserDefaults`, fired system-wide through Carbon `RegisterEventHotKey`. One
package shared by [BetterAudio](https://github.com/rokartur/BetterAudio),
[BetterCmdTab](https://github.com/rokartur/BetterCmdTab),
[BetterShutter](https://github.com/rokartur/BetterShutter) and
[BetterCleaner](https://github.com/rokartur/BetterCleaner).

Derived from [Sindre Sorhus' KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
(MIT), which was previously vendored into each app. Differences that matter:

- Recorder policies: decide per app or per recorder whether Shift, modifier-free keys or duplicate chords are allowed
- Reserved chords the recorder refuses (for apps that own an always-on trigger such as a Cmd-Tab switcher)
- Hot keys fire only when the live modifier state still matches the recorded chord
- Reads the legacy `KeyboardShortcuts_` defaults, so users keep their shortcuts after migrating
- Swift 6 language mode, macOS 13+, no dependencies

## Install

Swift Package Manager. In Xcode: **File ▸ Add Package Dependencies…** and
enter the repo URL, or in `Package.swift`:

```swift
.package(url: "https://github.com/rokartur/BetterShortcuts.git", from: "0.3.8")
```

## Usage

Define shortcut names:

```swift
import BetterShortcuts

extension BetterShortcuts.Name {
    static let toggleUnicornMode = Self("toggleUnicornMode")
    static let capture = Self("capture", default: .init(.four, modifiers: [.command, .shift]))
}
```

Listen for presses:

```swift
BetterShortcuts.onKeyUp(for: .toggleUnicornMode) {
    isUnicornMode.toggle()
}

// or as an async stream
for await event in BetterShortcuts.events(for: .capture) {
    switch event {
    case .keyDown: startCapture()
    case .keyUp: finishCapture()
    }
}
```

Let the user record a shortcut:

```swift
BetterShortcuts.Recorder("Capture:", name: .capture)   // SwiftUI
BetterShortcuts.RecorderCocoa(for: .capture)           // AppKit
```

Other entry points: `getShortcut(for:)`, `setShortcut(_:for:)`,
`reset(_:)`, `resetAll()`, `enable(_:)` / `disable(_:)`, `isEnabled` (global
pause), `NSMenuItem.setShortcut(for:)` to mirror a shortcut in the menu bar,
and the SwiftUI `onKeyboardShortcut` / `onGlobalKeyboardShortcut` view
modifiers.

### Friendly names in the conflict alert

The recorder warns when a chord is already used by another of your shortcuts.
To show a label instead of the raw identifier:

```swift
BetterShortcuts.displayName = { $0.displayName } // your own `Name.displayName`
```

### Recorder policy

The recorder validates what the user types. Pick a mode that matches the app:

| Mode | Shift allowed | Hold modifier (⌘/⌥/⌃) required | Modifier-free keys (`F5`) |
| --- | --- | --- | --- |
| `.standard` (default) | yes | yes | no |
| `.switcher` | no, reserved for reverse stepping | yes | no |
| `.unrestricted` | yes | no | yes |

```swift
BetterShortcuts.recorderPolicy = .switcher                                 // app-wide
BetterShortcuts.RecorderCocoa(for: .capture, policy: .unrestricted)        // per recorder
```

`RecorderPolicy` is a plain struct, so you can also build your own:
`allowsDuplicateShortcuts` lets independent scopes (per-profile keys) share a
chord, `rejectsReservedShortcuts` makes a recorder refuse anything in
`BetterShortcuts.reservedShortcuts`:

```swift
BetterShortcuts.reservedShortcuts = { Set(App.switcherTriggerChords()) }
```

## Storage

Shortcuts live in `UserDefaults` under the `BetterShortcuts_<name>` key. The
legacy `KeyboardShortcuts_<name>` key is read as a fallback and migrated to the
new key on the next write.

## Development

```bash
swift build
swift test
swift test --filter RecorderPolicyTests
```

Tests cover the key map, Carbon modifier bridging, shortcut descriptions,
persistence and migration, recorder policies and hot key modifier validation.
Recorder UI behavior is checked by hand in a host app. Conventions and the
release process are in [AGENTS.md](AGENTS.md).

## License

MIT, see [LICENSE](LICENSE). Includes code from KeyboardShortcuts,
copyright Sindre Sorhus, MIT.

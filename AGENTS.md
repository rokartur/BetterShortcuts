# BetterShortcuts, agent guide

Swift package: global keyboard shortcuts for macOS apps, forked from
sindresorhus/KeyboardShortcuts. `README.md` has the public API; this file has
what an agent needs to change the code safely.

## Commands

```bash
swift build
swift test                               # 49 XCTest cases
swift test --filter RecorderPolicyTests  # one suite
```

macOS 13+, Swift 6 tools, no dependencies. There is no demo target: recorder
UI changes are verified by running a host app (BetterCmdTab, BetterShutter)
that links the local package.

## Layout

```
Sources/BetterShortcuts/
  BetterShortcuts.swift        public namespace: handlers, enable/disable, reset, events(for:), globals
  CarbonBetterShortcuts.swift  RegisterEventHotKey bridge, the single Carbon event handler, modifier validation
  Shortcut.swift               Shortcut value type, Carbon <-> NSEvent conversion, system shortcut lookup, descriptions
  Key.swift                    key codes
  Name.swift                   Name + default shortcut + persisted lookup
  RecorderPolicy.swift         what the recorder accepts
  RecorderCocoa.swift          NSSearchField-based recorder (AppKit)
  Recorder.swift               SwiftUI wrapper around RecorderCocoa
  ViewModifiers.swift          onKeyboardShortcut, onGlobalKeyboardShortcut
  NSMenuItem++.swift           mirror a shortcut as a menu key equivalent
  Utilities.swift              string, event and layout helpers
Tests/BetterShortcutsTests/
```

## Conventions

- Indentation is tabs, upstream style. Keep it so diffs against KeyboardShortcuts stay readable.
- Public types live in the `BetterShortcuts` enum namespace; new API goes there too.
- Global state is `nonisolated(unsafe) static` on `BetterShortcuts` and is touched from the main thread only. The Carbon handler is installed once and refreshed through `CarbonBetterShortcuts.updateEventHandler()` whenever the registered set changes.
- Persistence key is `BetterShortcuts_<name>`; the legacy `KeyboardShortcuts_<name>` key is read as fallback and migrated on write. Never drop the fallback, every shipped app has users with legacy keys.
- A `Name` without a handler is persisted but not registered with Carbon (`HandlerlessRegistrationTests`). Registration follows handlers, not storage.
- Hot key callbacks run only after the live modifier state is validated against the recorded chord; a stranded suppression is cleared on the next accepted press. Keep both when touching `CarbonBetterShortcuts`.
- Recorder validation goes through `RecorderPolicy.accepts(modifiers:)` plus the duplicate and reserved checks in `RecorderCocoa`. Add a rule as a policy field, not an ad hoc `if`.
- Shortcut rendering uses `presentableDescription` / `nsMenuItemKeyEquivalent`; both are covered by `ShortcutDescriptionTests`.

## Releases

Tags carry a `v` prefix here (`v0.3.8`), unlike the other `Better*` packages.
Cut manually:

```bash
git tag v<version> && git push origin v<version>
gh release create v<version> -R rokartur/BetterShortcuts --title "v<version>" --notes-file notes.md --verify-tag
```

Release body: a `## <headline>` line, then only the sections that apply
(`### Added`, `### Changed`, `### Fixed`, `### Removed`) with bullets naming
the real symbols that changed, and a `**Full changelog:**` compare link to the
previous tag. A change to the default `recorderPolicy` or to the persistence
key is source- or behavior-breaking for every host app: bump `MINOR` and call
it out in the headline.

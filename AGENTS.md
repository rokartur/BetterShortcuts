# BetterShortcuts, agent guide

`README.md` carries the public API and install. This file carries what the code does not confess.

## Conventions

- Indentation is tabs, upstream KeyboardShortcuts style, so diffs against the fork origin stay readable.
- New public API goes into the `BetterShortcuts` enum namespace.
- Global state is `nonisolated(unsafe) static` on `BetterShortcuts`, main thread only. The Carbon handler is installed once; `CarbonBetterShortcuts.updateEventHandler()` refreshes it whenever the registered set changes.
- Persistence key is `BetterShortcuts_<name>`; the legacy `KeyboardShortcuts_<name>` key is read as fallback and migrated on write. Every shipped app has users on legacy keys, so the fallback ships in every version.
- Registration follows handlers, not storage: a `Name` without a handler is persisted but stays unregistered with Carbon (`HandlerlessRegistrationTests`).
- A hot key callback fires only after the live modifier state matches the recorded chord; a stranded suppression clears on the next accepted press. Both guards live in `CarbonBetterShortcuts`.
- A new recorder rule is a `RecorderPolicy` field evaluated in `RecorderPolicy.accepts(modifiers:)` or beside the duplicate and reserved checks in `RecorderCocoa`.
- The default `recorderPolicy` and the persistence key are behavior contracts for every host app: a change there bumps `MINOR` and leads the release headline.

## Releases

Tag carries a `v` prefix here (`v0.3.8`), unlike the other `Better*` packages; the GitHub Release body is the changelog.

```bash
git tag v<version> && git push origin v<version>
gh release create v<version> -R rokartur/BetterShortcuts --title "v<version>" --notes-file notes.md --verify-tag
```

Body format and SemVer rules: https://github.com/rokartur/BetterSettings/blob/main/AGENTS.md#releases--changelogs

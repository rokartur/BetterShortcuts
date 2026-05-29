import Combine
import AppKit.NSMenu

/**
Global keyboard shortcuts for your macOS app.
*/
public enum BetterShortcuts {
	nonisolated(unsafe) private static var registeredShortcuts = Set<Shortcut>()

	nonisolated(unsafe) private static var legacyKeyDownHandlers = [Name: [() -> Void]]()
	nonisolated(unsafe) private static var legacyKeyUpHandlers = [Name: [() -> Void]]()

	nonisolated(unsafe) private static var streamKeyDownHandlers = [Name: [UUID: () -> Void]]()
	nonisolated(unsafe) private static var streamKeyUpHandlers = [Name: [UUID: () -> Void]]()

	private static var shortcutsForLegacyHandlers: Set<Shortcut> {
		let shortcuts = [legacyKeyDownHandlers.keys, legacyKeyUpHandlers.keys]
			.flatMap { $0 }
			.compactMap(\.shortcut)

		return Set(shortcuts)
	}

	private static var shortcutsForStreamHandlers: Set<Shortcut> {
		let shortcuts = [streamKeyDownHandlers.keys, streamKeyUpHandlers.keys]
			.flatMap { $0 }
			.compactMap(\.shortcut)

		return Set(shortcuts)
	}

	private static var shortcutsForHandlers: Set<Shortcut> {
		shortcutsForLegacyHandlers.union(shortcutsForStreamHandlers)
	}

	nonisolated(unsafe) private static var isInitialized = false

	nonisolated(unsafe) private static var openMenuObserver: NSObjectProtocol?
	nonisolated(unsafe) private static var closeMenuObserver: NSObjectProtocol?

	nonisolated(unsafe) private static var defaults = UserDefaults.standard

	/**
	When `true`, event handlers will not be called for registered keyboard shortcuts.
	Also suspends Carbon hotkey registrations so raw key events reach local event monitors (e.g. RecorderCocoa).
	*/
	nonisolated(unsafe) static var isPaused = false {
		didSet {
			guard isPaused != oldValue else { return }
			if isPaused {
				CarbonBetterShortcuts.softUnregisterAll()
			} else {
				CarbonBetterShortcuts.softRegisterAll()
			}
		}
	}

	/**
	Enable/disable monitoring of all keyboard shortcuts.

	The default is `true`.
	*/
	nonisolated(unsafe) public static var isEnabled = true {
		didSet {
			guard isEnabled != oldValue else {
				return
			}

			CarbonBetterShortcuts.updateEventHandler()
		}
	}

	/**
	Optional provider of a human-readable name for a shortcut, used in the conflict alert shown by ``Recorder``/``RecorderCocoa``.

	Set this once at launch if you want conflict alerts to show a friendly name instead of the raw identifier:

	```swift
	BetterShortcuts.displayName = { $0.displayName }
	```
	*/
	nonisolated(unsafe) public static var displayName: (@Sendable (Name) -> String)?

	static var allNames: Set<Name> {
		defaults.dictionaryRepresentation()
			.compactMap { key, _ -> Name? in
				if key.hasPrefix(userDefaultsPrefix) {
					return .init(key.replacingPrefix(userDefaultsPrefix, with: ""))
				}

				// Include not-yet-migrated shortcuts saved under the legacy prefix.
				if key.hasPrefix(legacyUserDefaultsPrefix) {
					return .init(key.replacingPrefix(legacyUserDefaultsPrefix, with: ""))
				}

				return nil
			}
			.toSet()
	}

	/**
	Enable keyboard shortcuts to work even when an `NSMenu` is open by setting this property when the menu opens and closes.

	`NSMenu` runs in a tracking run mode that blocks keyboard shortcuts events. When you set this property to `true`, it switches to a different kind of event handler, which does work when the menu is open.

	The main use-case for this is toggling the menu of a menu bar app with a keyboard shortcut.
	*/
	nonisolated(unsafe) private(set) static var isMenuOpen = false {
		didSet {
			guard isMenuOpen != oldValue else {
				return
			}

			CarbonBetterShortcuts.updateEventHandler()
		}
	}

	private static func register(_ shortcut: Shortcut) {
		guard !registeredShortcuts.contains(shortcut) else {
			return
		}

        CarbonBetterShortcuts.register(
            shortcut,
            onKeyDown: { shortcut in
                // Carbon event handlers run on the main thread; use assumeIsolated to avoid
                // priority inversion from Task { @MainActor } creating a User-Interactive task.
                MainActor.assumeIsolated {
                    handleOnKeyDown(shortcut)
                }
            },
            onKeyUp: { shortcut in
                MainActor.assumeIsolated {
                    handleOnKeyUp(shortcut)
                }
            }
        )

		registeredShortcuts.insert(shortcut)
	}

	/**
	Register the shortcut for the given name if it has a shortcut.
	*/
	private static func registerShortcutIfNeeded(for name: Name) {
		guard let shortcut = getShortcut(for: name) else {
			return
		}

		register(shortcut)
	}

	private static func unregister(_ shortcut: Shortcut) {
		CarbonBetterShortcuts.unregister(shortcut)
		registeredShortcuts.remove(shortcut)
	}

	/**
	Unregister the given shortcut if it has no handlers.
	*/
	private static func unregisterIfNeeded(_ shortcut: Shortcut) {
		guard !shortcutsForHandlers.contains(shortcut) else {
			return
		}

		unregister(shortcut)
	}

	/**
	Unregister the shortcut for the given name if it has no handlers.
	*/
	private static func unregisterShortcutIfNeeded(for name: Name) {
		guard let shortcut = name.shortcut else {
			return
		}

		unregisterIfNeeded(shortcut)
	}

	private static func unregisterAll() {
		CarbonBetterShortcuts.unregisterAll()
		registeredShortcuts.removeAll()

		// TODO: Should remove user defaults too.
	}

	static func initialize() {
		guard !isInitialized else {
			return
		}

		openMenuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
			isMenuOpen = true
		}

		closeMenuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
			isMenuOpen = false
		}

		isInitialized = true
	}

	/**
	Remove all handlers receiving keyboard shortcuts events.

	This can be used to reset the handlers before re-creating them to avoid having multiple handlers for the same shortcut.

	- Note: This method does not affect listeners using ``events(for:)``.
	*/
	public static func removeAllHandlers() {
		let shortcutsToUnregister = shortcutsForLegacyHandlers.subtracting(shortcutsForStreamHandlers)

		for shortcut in shortcutsToUnregister {
			unregister(shortcut)
		}

		legacyKeyDownHandlers = [:]
		legacyKeyUpHandlers = [:]
	}

	/**
	Remove the keyboard shortcut handler for the given name.

	This can be used to reset the handler before re-creating it to avoid having multiple handlers for the same shortcut.

	- Parameter name: The name of the keyboard shortcut to remove handlers for.

	- Note: This method does not affect listeners using ``events(for:)``.
	*/
	public static func removeHandler(for name: Name) {
		legacyKeyDownHandlers[name] = nil
		legacyKeyUpHandlers[name] = nil

		// Make sure not to unregister stream handlers.
		guard
			let shortcut = getShortcut(for: name),
			!shortcutsForStreamHandlers.contains(shortcut)
		else {
			return
		}

		unregister(shortcut)
	}

	/**
	Returns whether the keyboard shortcut for the given name is enabled.

	This checks if the shortcut is registered and will trigger handlers. It respects the global ``isEnabled``.

	```swift
	let isEnabled = BetterShortcuts.isEnabled(for: .toggleUnicornMode)
	```

	- Tip: Use ``disable(_:)-(Name...)`` and ``enable(_:)-(Name...)`` to change the status.
	*/
	public static func isEnabled(for name: Name) -> Bool {
		guard
			isEnabled,
			let shortcut = getShortcut(for: name)
		else {
			return false
		}

		return registeredShortcuts.contains(shortcut)
	}

	/**
	Disable the keyboard shortcut for one or more names.
	*/
	public static func disable(_ names: [Name]) {
		for name in names {
			guard let shortcut = getShortcut(for: name) else {
				continue
			}

			unregister(shortcut)
		}
	}

	/**
	Disable the keyboard shortcut for one or more names.
	*/
	public static func disable(_ names: Name...) {
		disable(names)
	}

	/**
	Enable the keyboard shortcut for one or more names.
	*/
	public static func enable(_ names: [Name]) {
		for name in names {
			guard let shortcut = getShortcut(for: name) else {
				continue
			}

			register(shortcut)
		}
	}

	/**
	Enable the keyboard shortcut for one or more names.
	*/
	public static func enable(_ names: Name...) {
		enable(names)
	}

	/**
	Reset the keyboard shortcut for one or more names.

	If the `Name` has a default shortcut, it will reset to that.

	- Note: This overload exists as Swift doesn't support splatting.

	```swift
	import SwiftUI
	import BetterShortcuts

	struct SettingsScreen: View {
		var body: some View {
			VStack {
				// …
				Button(String(localized: "Reset", table: "Common")) {
					BetterShortcuts.reset(.toggleUnicornMode)
				}
			}
		}
	}
	```
	*/
	public static func reset(_ names: [Name]) {
		for name in names {
			setShortcut(name.defaultShortcut, for: name)
		}
	}

	/**
	Reset the keyboard shortcut for one or more names.

	If the `Name` has a default shortcut, it will reset to that.

	```swift
	import SwiftUI
	import BetterShortcuts

	struct SettingsScreen: View {
		var body: some View {
			VStack {
				// …
				Button(String(localized: "Reset", table: "Common")) {
					BetterShortcuts.reset(.toggleUnicornMode)
				}
			}
		}
	}
	```
	*/
	public static func reset(_ names: Name...) {
		reset(names)
	}

	/**
	Reset the keyboard shortcut for all the names.

	Unlike `reset(…)`, this resets all the shortcuts to `nil`, not the `defaultValue`.

	```swift
	import SwiftUI
	import BetterShortcuts

	struct SettingsScreen: View {
		var body: some View {
			VStack {
				// …
				Button(String(localized: "Reset All", table: "Shortcuts")) {
					BetterShortcuts.resetAll()
				}
			}
		}
	}
	```
	*/
	public static func resetAll() {
		reset(allNames.toArray())
	}

	/**
	Set the keyboard shortcut for a name.

	Setting it to `nil` removes the shortcut, even if the `Name` has a default shortcut defined. Use `.reset()` if you want it to respect the default shortcut.

	You would usually not need this as the user would be the one setting the shortcut in a settings user-interface, but it can be useful when, for example, migrating from a different keyboard shortcuts package.
	*/
	public static func setShortcut(_ shortcut: Shortcut?, for name: Name) {
		if let shortcut {
			userDefaultsSet(name: name, shortcut: shortcut)
		} else {
			if name.defaultShortcut != nil {
				userDefaultsDisable(name: name)
			} else {
				userDefaultsRemove(name: name)
			}
		}
	}

	/**
	Get the keyboard shortcut for a name.

	Resolution order:
	1. A user-saved shortcut (current key, then the legacy `KeyboardShortcuts_` key).
	2. The `Name`'s `default:` shortcut, when nothing has been saved yet — so a
	   freshly-declared shortcut is *active* immediately, without requiring an
	   explicit save. Without this a `default:` only takes effect once written,
	   which silently leaves `onKeyDown`-registered global hot keys unregistered.
	3. `nil` when the user has explicitly cleared the shortcut (the key holds a
	   `false` "disabled" marker) — a disable must win over the default.
	*/
	public static func getShortcut(for name: Name) -> Shortcut? {
		// Prefer the current key; fall back to the legacy `KeyboardShortcuts_` key for shortcuts saved before the package rename.
		let key = defaults.object(forKey: userDefaultsKey(for: name)) != nil
			? userDefaultsKey(for: name)
			: legacyUserDefaultsKey(for: name)

		// Nothing stored under either key → use the declared default.
		guard defaults.object(forKey: key) != nil else {
			return name.defaultShortcut
		}

		// A value exists. A decodable JSON string is a real shortcut; anything
		// else (the `false` disabled marker) means the user cleared it, so honor
		// the disable instead of falling back to the default.
		guard
			let data = defaults.string(forKey: key)?.data(using: .utf8),
			let decoded = try? JSONDecoder().decode(Shortcut.self, from: data)
		else {
			return nil
		}

		return decoded
	}

	private static func handleOnKeyDown(_ shortcut: Shortcut) {
		guard !isPaused else {
			return
		}

		for (name, handlers) in legacyKeyDownHandlers {
			guard getShortcut(for: name) == shortcut else {
				continue
			}

			for handler in handlers {
				handler()
			}
		}

		for (name, handlers) in streamKeyDownHandlers {
			guard getShortcut(for: name) == shortcut else {
				continue
			}

			for handler in handlers.values {
				handler()
			}
		}
	}

	private static func handleOnKeyUp(_ shortcut: Shortcut) {
		guard !isPaused else {
			return
		}

		for (name, handlers) in legacyKeyUpHandlers {
			guard getShortcut(for: name) == shortcut else {
				continue
			}

			for handler in handlers {
				handler()
			}
		}

		for (name, handlers) in streamKeyUpHandlers {
			guard getShortcut(for: name) == shortcut else {
				continue
			}

			for handler in handlers.values {
				handler()
			}
		}
	}

	/**
	Listen to the keyboard shortcut with the given name being pressed.

	You can register multiple listeners.

	You can safely call this even if the user has not yet set a keyboard shortcut. It will just be inactive until they do.

	- Important: This will be deprecated in the future. Prefer ``events(for:)`` for new code.

	```swift
	import AppKit
	import BetterShortcuts

	@main
	final class AppDelegate: NSObject, NSApplicationDelegate {
		func applicationDidFinishLaunching(_ notification: Notification) {
			BetterShortcuts.onKeyDown(for: .toggleUnicornMode) { [self] in
				isUnicornMode.toggle()
			}
		}
	}
	```
	*/
	public static func onKeyDown(for name: Name, action: @escaping () -> Void) {
		legacyKeyDownHandlers[name, default: []].append(action)
		registerShortcutIfNeeded(for: name)
	}

	/**
	Listen to the keyboard shortcut with the given name being pressed.

	You can register multiple listeners.

	You can safely call this even if the user has not yet set a keyboard shortcut. It will just be inactive until they do.

	- Important: This will be deprecated in the future. Prefer ``events(for:)`` for new code.

	```swift
	import AppKit
	import BetterShortcuts

	@main
	final class AppDelegate: NSObject, NSApplicationDelegate {
		func applicationDidFinishLaunching(_ notification: Notification) {
			BetterShortcuts.onKeyUp(for: .toggleUnicornMode) { [self] in
				isUnicornMode.toggle()
			}
		}
	}
	```
	*/
	public static func onKeyUp(for name: Name, action: @escaping () -> Void) {
		legacyKeyUpHandlers[name, default: []].append(action)
		registerShortcutIfNeeded(for: name)
	}

	private static let userDefaultsPrefix = "BetterShortcuts_"

	/**
	Legacy prefix from when this code was vendored into each app as `KeyboardShortcuts`.

	Kept so existing users don't lose their stored shortcuts. It is read as a fallback and migrated to `userDefaultsPrefix` on the next write.
	*/
	private static let legacyUserDefaultsPrefix = "KeyboardShortcuts_"

	private static func userDefaultsKey(for shortcutName: Name) -> String { "\(userDefaultsPrefix)\(shortcutName.rawValue)"
	}

	private static func legacyUserDefaultsKey(for shortcutName: Name) -> String { "\(legacyUserDefaultsPrefix)\(shortcutName.rawValue)"
	}

	static func userDefaultsDidChange(name: Name) {
		// TODO: Use proper UserDefaults observation instead of this.
		NotificationCenter.default.post(
			name: .shortcutByNameDidChange,
			object: nil,
			userInfo: ["name": name.rawValue]
		)
	}

	static func userDefaultsSet(name: Name, shortcut: Shortcut) {
		guard let encoded = try? JSONEncoder().encode(shortcut).toString else {
			return
		}

		if let oldShortcut = getShortcut(for: name) {
			unregister(oldShortcut)
		}

		register(shortcut)
		defaults.set(encoded, forKey: userDefaultsKey(for: name))
		// Migrate-on-write: drop the legacy key so future reads hit the current key and no orphan remains.
		defaults.removeObject(forKey: legacyUserDefaultsKey(for: name))
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsDisable(name: Name) {
		guard let shortcut = getShortcut(for: name) else {
			return
		}

		defaults.set(false, forKey: userDefaultsKey(for: name))
		defaults.removeObject(forKey: legacyUserDefaultsKey(for: name))
		unregister(shortcut)
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsRemove(name: Name) {
		guard let shortcut = getShortcut(for: name) else {
			return
		}

		defaults.removeObject(forKey: userDefaultsKey(for: name))
		defaults.removeObject(forKey: legacyUserDefaultsKey(for: name))
		unregister(shortcut)
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsContains(name: Name) -> Bool {
		defaults.object(forKey: userDefaultsKey(for: name)) != nil
			|| defaults.object(forKey: legacyUserDefaultsKey(for: name)) != nil
	}
}

extension BetterShortcuts {
	public enum EventType: Sendable {
		case keyDown
		case keyUp

		@inlinable
		func matches(_ other: EventType) -> Bool {
			switch (self, other) {
			case (.keyDown, .keyDown), (.keyUp, .keyUp):
				return true
			default:
				return false
			}
		}
	}
}

extension BetterShortcuts.EventType: Equatable {
	@inlinable
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.matches(rhs)
	}
}
extension BetterShortcuts {
    /**
     Listen to the keyboard shortcut with the given name being pressed.

	You can register multiple listeners.

	You can safely call this even if the user has not yet set a keyboard shortcut. It will just be inactive until they do.

	Ending the async sequence will stop the listener. For example, in the below example, the listener will stop when the view disappears.

	```swift
	import SwiftUI
	import BetterShortcuts

	struct ContentView: View {
		@State private var isUnicornMode = false

		var body: some View {
			Text(isUnicornMode ? "🦄" : "🐴")
				.task {
					for await event in BetterShortcuts.events(for: .toggleUnicornMode) where event == .keyUp {
						isUnicornMode.toggle()
					}
				}
		}
	}
	```

	- Note: This method is not affected by `.removeAllHandlers()`.
	*/
	public static func events(for name: Name) -> AsyncStream<BetterShortcuts.EventType> {
		AsyncStream { continuation in
			let id = UUID()

			DispatchQueue.main.async {
				streamKeyDownHandlers[name, default: [:]][id] = {
					continuation.yield(.keyDown)
				}

				streamKeyUpHandlers[name, default: [:]][id] = {
					continuation.yield(.keyUp)
				}

				registerShortcutIfNeeded(for: name)
			}

			continuation.onTermination = { _ in
				DispatchQueue.main.async {
					streamKeyDownHandlers[name]?[id] = nil
					streamKeyUpHandlers[name]?[id] = nil

					unregisterShortcutIfNeeded(for: name)
				}
			}
		}
	}

	/**
	Listen to keyboard shortcut events with the given name and type.

	You can register multiple listeners.

	You can safely call this even if the user has not yet set a keyboard shortcut. It will just be inactive until they do.

	Ending the async sequence will stop the listener. For example, in the below example, the listener will stop when the view disappears.

	```swift
	import SwiftUI
	import BetterShortcuts

	struct ContentView: View {
		@State private var isUnicornMode = false

		var body: some View {
			Text(isUnicornMode ? "🦄" : "🐴")
				.task {
					for await event in BetterShortcuts.events(for: .toggleUnicornMode) where event == .keyUp {
						isUnicornMode.toggle()
					}
				}
		}
	}
	```

	- Note: This method is not affected by `.removeAllHandlers()`.
	*/
	public static func events(_ type: EventType, for name: Name) -> AsyncFilterSequence<AsyncStream<EventType>> {
		events(for: name).filter { $0 == type }
	}
}

extension Notification.Name {
	static let shortcutByNameDidChange = Self("BetterShortcuts_shortcutByNameDidChange")
}

import Combine
@preconcurrency import AppKit

private final class WeakMenuItemBox: @unchecked Sendable {
	weak var menuItem: NSMenuItem?

	init(_ menuItem: NSMenuItem?) {
		self.menuItem = menuItem
	}
}

extension NSMenuItem {
	private enum AssociatedKeys {
		@MainActor
		static let observer = ObjectAssociation<NSObjectProtocol>()
	}

	@MainActor
	private func clearShortcut() {
		keyEquivalent = ""
		keyEquivalentModifierMask = []

		if #available(macOS 12, *) {
			allowsAutomaticKeyEquivalentLocalization = true
		}
	}

	// TODO: Make this a getter/setter. We must first add the ability to create a `Shortcut` from a `keyEquivalent`.
	/**
	Show a recorded keyboard shortcut in a `NSMenuItem`.

	The menu item will automatically be kept up to date with changes to the keyboard shortcut.

	Pass in `nil` to clear the keyboard shortcut.

	This method overrides `.keyEquivalent` and `.keyEquivalentModifierMask`.

	```swift
	import AppKit
	import BetterShortcuts

	extension BetterShortcuts.Name {
		static let toggleUnicornMode = Self("toggleUnicornMode")
	}

	// … `Recorder` logic for recording the keyboard shortcut …

	let menuItem = NSMenuItem()
	menuItem.title = "Toggle Unicorn Mode"
	menuItem.setShortcut(for: .toggleUnicornMode)
	```

	You can test this method in the example project. Run it, record a shortcut and then look at the “Test” menu in the app's main menu.

	- Important: You will have to disable the global keyboard shortcut while the menu is open, as otherwise, the keyboard events will be buffered up and triggered when the menu closes. This is because `NSMenu` puts the thread in tracking-mode, which prevents the keyboard events from being received. You can listen to whether a menu is open by implementing `NSMenuDelegate#menuWillOpen` and `NSMenuDelegate#menuDidClose`. You then use `BetterShortcuts.disable` and `BetterShortcuts.enable`.
	*/
	@MainActor
	public func setShortcut(for name: BetterShortcuts.Name?) {
		if let observer = AssociatedKeys.observer[self] {
			NotificationCenter.default.removeObserver(observer)
			AssociatedKeys.observer[self] = nil
		}

		guard let name else {
			clearShortcut()
			return
		}

		func set() {
			let shortcut = BetterShortcuts.Shortcut(name: name)
			setShortcut(shortcut)
		}

		set()

			// TODO: Use AsyncStream when targeting macOS 15.
				let menuItemBox = WeakMenuItemBox(self)
				AssociatedKeys.observer[self] = NotificationCenter.default.addObserver(forName: .shortcutByNameDidChange, object: nil, queue: .main) { notification in
					guard
						let rawName = notification.userInfo?["name"] as? String,
						rawName == name.rawValue
					else {
						return
					}

					Task { @MainActor in
						menuItemBox.menuItem?.setShortcut(BetterShortcuts.Shortcut(name: name))
					}
				}
			}

	/**
	Add a keyboard shortcut to a `NSMenuItem`.

	This method is only recommended for dynamic shortcuts. In general, it's preferred to create a static shortcut name and use `NSMenuItem.setShortcut(for:)` instead.

	Pass in `nil` to clear the keyboard shortcut.

	This method overrides `.keyEquivalent` and `.keyEquivalentModifierMask`.

	- Important: You will have to disable the global keyboard shortcut while the menu is open, as otherwise, the keyboard events will be buffered up and triggered when the menu closes. This is because `NSMenu` puts the thread in tracking-mode, which prevents the keyboard events from being received. You can listen to whether a menu is open by implementing `NSMenuDelegate#menuWillOpen` and `NSMenuDelegate#menuDidClose`. You then use `BetterShortcuts.disable` and `BetterShortcuts.enable`.
	*/
	@_disfavoredOverload
	@MainActor
	public func setShortcut(_ shortcut: BetterShortcuts.Shortcut?) {
		guard let shortcut else {
			clearShortcut()
			return
		}

		keyEquivalent = shortcut.nsMenuItemKeyEquivalent ?? ""
		keyEquivalentModifierMask = shortcut.modifiers

		if #available(macOS 12, *) {
			allowsAutomaticKeyEquivalentLocalization = false
		}
	}
}

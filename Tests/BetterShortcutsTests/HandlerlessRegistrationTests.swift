import XCTest
@testable import BetterShortcuts

/// A name with NO handler (no `onKeyDown`/`onKeyUp` closure and no `events(for:)`
/// stream) must persist its shortcut WITHOUT reserving a global Carbon hot key.
/// Reserving one would make the OS swallow that chord system-wide with nothing to
/// act on it — the "setting a handler-less/in-panel key kills the chord in every
/// app" bug. This test never attaches a handler, so `setShortcut` must not call
/// `RegisterEventHotKey`, keeping it safe to run headless.
final class HandlerlessRegistrationTests: XCTestCase {
	private var rawName = ""
	private var shortcutName = BetterShortcuts.Name("placeholder")

	override func setUp() {
		super.setUp()
		rawName = "test_\(UUID().uuidString)"
		shortcutName = BetterShortcuts.Name(rawName)
	}

	override func tearDown() {
		// Clears the stored value and unregisters (a no-op here since nothing was
		// registered), leaving no global state behind for the next test.
		BetterShortcuts.reset(shortcutName)
		super.tearDown()
	}

	func testSetShortcutForHandlerlessNamePersistsButDoesNotRegister() {
		let shortcut = BetterShortcuts.Shortcut(.w, modifiers: [.command])
		BetterShortcuts.setShortcut(shortcut, for: shortcutName)

		// The value is persisted and resolves back...
		XCTAssertEqual(BetterShortcuts.getShortcut(for: shortcutName), shortcut)
		// ...but with no handler the chord is NOT registered globally.
		XCTAssertFalse(BetterShortcuts.isEnabled(for: shortcutName))
	}

	func testRebindingHandlerlessNameNeverRegisters() {
		// Mirrors the reported repro: ⌘W → ⌘S → ⌘W. No step may register.
		let w = BetterShortcuts.Shortcut(.w, modifiers: [.command])
		let s = BetterShortcuts.Shortcut(.s, modifiers: [.command])

		BetterShortcuts.setShortcut(w, for: shortcutName)
		XCTAssertFalse(BetterShortcuts.isEnabled(for: shortcutName))

		BetterShortcuts.setShortcut(s, for: shortcutName)
		XCTAssertFalse(BetterShortcuts.isEnabled(for: shortcutName))

		BetterShortcuts.setShortcut(w, for: shortcutName)
		XCTAssertEqual(BetterShortcuts.getShortcut(for: shortcutName), w)
		XCTAssertFalse(BetterShortcuts.isEnabled(for: shortcutName))
	}
}

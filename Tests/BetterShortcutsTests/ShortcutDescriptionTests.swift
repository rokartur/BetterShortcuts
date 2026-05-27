import XCTest
import Carbon.HIToolbox
@testable import BetterShortcuts

/// `Shortcut.description` is `nonisolated` and uses a static key-code table,
/// so it is safe and deterministic to test off the main thread / without a GUI.
final class ShortcutDescriptionTests: XCTestCase {
	func testLetterKeys() {
		XCTAssertEqual(BetterShortcuts.Shortcut(.a).description, "A")
		XCTAssertEqual(BetterShortcuts.Shortcut(.b).description, "B")
		XCTAssertEqual(BetterShortcuts.Shortcut(.z).description, "Z")
	}

	func testNumberKeys() {
		XCTAssertEqual(BetterShortcuts.Shortcut(.zero).description, "0")
		XCTAssertEqual(BetterShortcuts.Shortcut(.nine).description, "9")
	}

	func testFunctionKeys() {
		XCTAssertEqual(BetterShortcuts.Shortcut(.f1).description, "F1")
		XCTAssertEqual(BetterShortcuts.Shortcut(.f12).description, "F12")
	}

	func testSpecialKeys() {
		XCTAssertEqual(BetterShortcuts.Shortcut(.return).description, "↩")
		XCTAssertEqual(BetterShortcuts.Shortcut(.tab).description, "⇥")
		XCTAssertEqual(BetterShortcuts.Shortcut(.space).description, "Space")
		XCTAssertEqual(BetterShortcuts.Shortcut(.escape).description, "⎋")
		XCTAssertEqual(BetterShortcuts.Shortcut(.leftArrow).description, "←")
	}

	func testModifierPrefix() {
		XCTAssertEqual(BetterShortcuts.Shortcut(.a, modifiers: [.command]).description, "⌘A")
		XCTAssertEqual(BetterShortcuts.Shortcut(.a, modifiers: [.command, .shift]).description, "⇧⌘A")
	}

	func testUnknownKeyCodeFallsBackToKeyLabel() {
		XCTAssertEqual(BetterShortcuts.Shortcut(carbonKeyCode: 999).description, "Key999")
	}
}

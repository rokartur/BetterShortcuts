import XCTest
@testable import BetterShortcuts

/// Exercises the `getShortcut(for:)` read path: JSON decoding, the current
/// `BetterShortcuts_` key, and the legacy `KeyboardShortcuts_` fallback used
/// for shortcuts saved before the package was renamed.
///
/// Values are written straight into `UserDefaults.standard` (the store the
/// library reads) so the test never registers a real Carbon hot key.
final class ShortcutPersistenceTests: XCTestCase {
	private let currentPrefix = "BetterShortcuts_"
	private let legacyPrefix = "KeyboardShortcuts_"

	private var rawName = ""
	private var shortcutName = BetterShortcuts.Name("placeholder")

	override func setUp() {
		super.setUp()
		rawName = "test_\(UUID().uuidString)"
		shortcutName = BetterShortcuts.Name(rawName)
	}

	override func tearDown() {
		UserDefaults.standard.removeObject(forKey: currentPrefix + rawName)
		UserDefaults.standard.removeObject(forKey: legacyPrefix + rawName)
		super.tearDown()
	}

	private func storedJSON(for shortcut: BetterShortcuts.Shortcut) throws -> String {
		try XCTUnwrap(String(data: try JSONEncoder().encode(shortcut), encoding: .utf8))
	}

	func testUnknownNameReturnsNil() {
		XCTAssertNil(BetterShortcuts.getShortcut(for: shortcutName))
	}

	func testReadsFromCurrentKey() throws {
		let shortcut = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		UserDefaults.standard.set(try storedJSON(for: shortcut), forKey: currentPrefix + rawName)

		XCTAssertEqual(BetterShortcuts.getShortcut(for: shortcutName), shortcut)
	}

	func testFallsBackToLegacyKey() throws {
		let shortcut = BetterShortcuts.Shortcut(.b, modifiers: [.command, .shift])
		UserDefaults.standard.set(try storedJSON(for: shortcut), forKey: legacyPrefix + rawName)

		XCTAssertEqual(BetterShortcuts.getShortcut(for: shortcutName), shortcut)
	}

	func testCurrentKeyTakesPrecedenceOverLegacy() throws {
		let current = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		let legacy = BetterShortcuts.Shortcut(.b, modifiers: [.command])
		UserDefaults.standard.set(try storedJSON(for: current), forKey: currentPrefix + rawName)
		UserDefaults.standard.set(try storedJSON(for: legacy), forKey: legacyPrefix + rawName)

		XCTAssertEqual(BetterShortcuts.getShortcut(for: shortcutName), current)
	}

	func testDisabledShortcutDecodesToNil() {
		// A disabled shortcut is stored as `false`, which is not valid shortcut JSON.
		UserDefaults.standard.set(false, forKey: currentPrefix + rawName)
		XCTAssertNil(BetterShortcuts.getShortcut(for: shortcutName))
	}

	// MARK: - `default:` fallback

	func testFallsBackToDefaultWhenUnset() {
		let def = BetterShortcuts.Shortcut(.a, modifiers: [.command, .control])
		let name = BetterShortcuts.Name("test_default_\(UUID().uuidString)", default: def)
		// The `Name` init may seed the default; clear both keys to exercise the
		// genuine "nothing stored" → default fallback path.
		UserDefaults.standard.removeObject(forKey: currentPrefix + name.rawValue)
		UserDefaults.standard.removeObject(forKey: legacyPrefix + name.rawValue)

		XCTAssertEqual(BetterShortcuts.getShortcut(for: name), def)

		UserDefaults.standard.removeObject(forKey: currentPrefix + name.rawValue)
	}

	func testDisableWinsOverDefault() {
		let def = BetterShortcuts.Shortcut(.a, modifiers: [.command, .control])
		let name = BetterShortcuts.Name("test_disabled_\(UUID().uuidString)", default: def)
		// User explicitly cleared the shortcut → stored `false` must beat the default.
		UserDefaults.standard.set(false, forKey: currentPrefix + name.rawValue)

		XCTAssertNil(BetterShortcuts.getShortcut(for: name))

		UserDefaults.standard.removeObject(forKey: currentPrefix + name.rawValue)
	}

	func testSavedValueWinsOverDefault() throws {
		let def = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		let saved = BetterShortcuts.Shortcut(.b, modifiers: [.command, .option])
		let name = BetterShortcuts.Name("test_saved_\(UUID().uuidString)", default: def)
		UserDefaults.standard.set(try storedJSON(for: saved), forKey: currentPrefix + name.rawValue)

		XCTAssertEqual(BetterShortcuts.getShortcut(for: name), saved)

		UserDefaults.standard.removeObject(forKey: currentPrefix + name.rawValue)
	}
}

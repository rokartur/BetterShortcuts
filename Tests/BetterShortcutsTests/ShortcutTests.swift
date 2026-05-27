import XCTest
import Carbon.HIToolbox
@testable import BetterShortcuts

final class ShortcutTests: XCTestCase {
	func testKeyAndModifierInitRoundTripsToCarbon() {
		let shortcut = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		XCTAssertEqual(shortcut.carbonKeyCode, kVK_ANSI_A)
		XCTAssertEqual(shortcut.carbonModifiers, cmdKey)
	}

	func testKeyComputedPropertyMapsBackToKey() {
		XCTAssertEqual(BetterShortcuts.Shortcut(.a).key, .a)
		XCTAssertEqual(BetterShortcuts.Shortcut(.f1).key, .f1)
		XCTAssertEqual(BetterShortcuts.Shortcut(.space).key, .space)
	}

	func testModifiersComputedPropertyReflectsCarbonModifiers() {
		let shortcut = BetterShortcuts.Shortcut(.a, modifiers: [.command, .shift])
		XCTAssertTrue(shortcut.modifiers.contains(.command))
		XCTAssertTrue(shortcut.modifiers.contains(.shift))
		XCTAssertFalse(shortcut.modifiers.contains(.control))
		XCTAssertFalse(shortcut.modifiers.contains(.option))
	}

	func testInitNormalizesUnknownModifierBits() {
		// An unrecognized high bit must be stripped during normalization,
		// leaving only the known Carbon modifier flags.
		let strayBit = 1 << 20
		let shortcut = BetterShortcuts.Shortcut(carbonKeyCode: kVK_ANSI_A, carbonModifiers: cmdKey | strayBit)
		XCTAssertEqual(shortcut.carbonModifiers, cmdKey)
	}

	func testEquatableAndHashable() {
		let a = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		let b = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		let c = BetterShortcuts.Shortcut(.b, modifiers: [.command])

		XCTAssertEqual(a, b)
		XCTAssertEqual(a.hashValue, b.hashValue)
		XCTAssertNotEqual(a, c)

		let set: Set<BetterShortcuts.Shortcut> = [a, b, c]
		XCTAssertEqual(set.count, 2)
	}

	func testCodableRoundTrip() throws {
		let original = BetterShortcuts.Shortcut(.t, modifiers: [.command, .option])
		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(BetterShortcuts.Shortcut.self, from: data)
		XCTAssertEqual(decoded, original)
	}

	func testCodableUsesCarbonFieldNames() throws {
		// getShortcut/setShortcut persist this exact JSON shape; lock it down.
		let shortcut = BetterShortcuts.Shortcut(.a, modifiers: [.command])
		let json = try XCTUnwrap(String(data: try JSONEncoder().encode(shortcut), encoding: .utf8))
		XCTAssertTrue(json.contains("carbonKeyCode"))
		XCTAssertTrue(json.contains("carbonModifiers"))
	}

	func testFunctionKeyShortcutPreservesFunctionModifier() {
		let shortcut = BetterShortcuts.Shortcut(.f2, modifiers: [.function])
		XCTAssertTrue(shortcut.modifiers.contains(.function))
		XCTAssertEqual(shortcut.key, .f2)
	}
}

import XCTest
import AppKit
@testable import BetterShortcuts

final class RecorderPolicyTests: XCTestCase {
	func testStandardAllowsShiftWithHoldModifier() {
		// ⌘⇧4-style shortcuts must be accepted by the default policy.
		XCTAssertTrue(BetterShortcuts.RecorderPolicy.standard.accepts(modifiers: [.command, .shift]))
		XCTAssertTrue(BetterShortcuts.RecorderPolicy.standard.accepts(modifiers: [.command]))
	}

	func testStandardRejectsShiftOnlyAndModifierFree() {
		XCTAssertFalse(BetterShortcuts.RecorderPolicy.standard.accepts(modifiers: [.shift]))
		XCTAssertFalse(BetterShortcuts.RecorderPolicy.standard.accepts(modifiers: []))
	}

	func testSwitcherReservesShift() {
		XCTAssertFalse(BetterShortcuts.RecorderPolicy.switcher.accepts(modifiers: [.command, .shift]))
		XCTAssertTrue(BetterShortcuts.RecorderPolicy.switcher.accepts(modifiers: [.command]))
	}

	func testUnrestrictedAllowsModifierFree() {
		XCTAssertTrue(BetterShortcuts.RecorderPolicy.unrestricted.accepts(modifiers: []))
		XCTAssertTrue(BetterShortcuts.RecorderPolicy.unrestricted.accepts(modifiers: [.shift]))
	}

	func testDefaultGlobalPolicyIsStandard() {
		XCTAssertEqual(BetterShortcuts.recorderPolicy, .standard)
	}

	func testRejectsReservedDefaultsFalseAndRoundTrips() {
		// The presets never opt into reservation rejection.
		XCTAssertFalse(BetterShortcuts.RecorderPolicy.standard.rejectsReservedShortcuts)
		XCTAssertFalse(BetterShortcuts.RecorderPolicy.switcher.rejectsReservedShortcuts)
		XCTAssertFalse(BetterShortcuts.RecorderPolicy.unrestricted.rejectsReservedShortcuts)
		// Opt-in is preserved through the initializer.
		XCTAssertTrue(BetterShortcuts.RecorderPolicy(rejectsReservedShortcuts: true).rejectsReservedShortcuts)
	}

	func testReservedShortcutsProviderDefaultsEmpty() {
		XCTAssertTrue(BetterShortcuts.reservedShortcuts().isEmpty)
	}
}

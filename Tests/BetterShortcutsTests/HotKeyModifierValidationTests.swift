import XCTest
import Carbon.HIToolbox
@testable import BetterShortcuts

final class HotKeyModifierValidationTests: XCTestCase {
	func testExactMatchPasses() {
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: controlKey, registered: controlKey))
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: cmdKey | shiftKey, registered: cmdKey | shiftKey))
	}

	func testWrongModifierRejected() {
		// rokartur/BetterCmdTab#120: ⌥ held while ⌃ is registered.
		XCTAssertFalse(CarbonBetterShortcuts.heldModifiersMatch(held: optionKey, registered: controlKey))
	}

	func testExtraModifierRejected() {
		XCTAssertFalse(CarbonBetterShortcuts.heldModifiersMatch(held: controlKey | optionKey, registered: controlKey))
	}

	// The handler runs a moment after the press, so a fast release can leave
	// nothing held by then — that must still fire. Only an unregistered modifier
	// rejects.
	func testMissingModifierAccepted() {
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: 0, registered: controlKey))
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: cmdKey, registered: cmdKey | shiftKey))
	}

	func testCapsLockAndFnIgnored() {
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: controlKey | alphaLock, registered: controlKey))
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: controlKey | (1 << 17), registered: controlKey))
		XCTAssertTrue(CarbonBetterShortcuts.heldModifiersMatch(held: controlKey, registered: controlKey | (1 << 17)))
	}
}

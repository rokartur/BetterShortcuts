import XCTest
import Carbon.HIToolbox
@testable import BetterShortcuts

final class KeyTests: XCTestCase {
	func testRawValueMatchesCarbonKeyCode() {
		XCTAssertEqual(BetterShortcuts.Key.a.rawValue, kVK_ANSI_A)
		XCTAssertEqual(BetterShortcuts.Key.zero.rawValue, kVK_ANSI_0)
		XCTAssertEqual(BetterShortcuts.Key.space.rawValue, kVK_Space)
		XCTAssertEqual(BetterShortcuts.Key.return.rawValue, kVK_Return)
	}

	func testRawRepresentableRoundTrip() {
		let key = BetterShortcuts.Key(rawValue: kVK_ANSI_A)
		XCTAssertEqual(key, .a)
		XCTAssertEqual(BetterShortcuts.Key(rawValue: key.rawValue), key)
	}

	func testEquatableAndHashable() {
		XCTAssertEqual(BetterShortcuts.Key.a, BetterShortcuts.Key(rawValue: kVK_ANSI_A))
		XCTAssertNotEqual(BetterShortcuts.Key.a, BetterShortcuts.Key.b)

		let set: Set<BetterShortcuts.Key> = [.a, .a, .b]
		XCTAssertEqual(set.count, 2)
	}

	func testIsFunctionKey() {
		XCTAssertTrue(BetterShortcuts.Key.f1.isFunctionKey)
		XCTAssertTrue(BetterShortcuts.Key.f20.isFunctionKey)
		XCTAssertFalse(BetterShortcuts.Key.a.isFunctionKey)
		XCTAssertFalse(BetterShortcuts.Key.space.isFunctionKey)
	}

	func testFunctionKeysSetHoldsExactlyF1ThroughF20() {
		XCTAssertEqual(BetterShortcuts.Key.functionKeys.count, 20)
		XCTAssertTrue(BetterShortcuts.Key.functionKeys.contains(.f1))
		XCTAssertTrue(BetterShortcuts.Key.functionKeys.contains(.f20))
		XCTAssertFalse(BetterShortcuts.Key.functionKeys.contains(.a))
	}
}

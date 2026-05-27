import XCTest
import AppKit
import Carbon.HIToolbox
@testable import BetterShortcuts

final class ModifierFlagsCarbonTests: XCTestCase {
	func testSingleFlagToCarbon() {
		XCTAssertEqual(NSEvent.ModifierFlags.command.carbon, cmdKey)
		XCTAssertEqual(NSEvent.ModifierFlags.control.carbon, controlKey)
		XCTAssertEqual(NSEvent.ModifierFlags.option.carbon, optionKey)
		XCTAssertEqual(NSEvent.ModifierFlags.shift.carbon, shiftKey)
	}

	func testFunctionFlagToCarbon() {
		// Reverse-engineered bit, documented in the source as 1 << 17.
		XCTAssertEqual(NSEvent.ModifierFlags.function.carbon, 1 << 17)
	}

	func testCombinedFlagsToCarbon() {
		let carbon = NSEvent.ModifierFlags([.command, .shift]).carbon
		XCTAssertEqual(carbon, cmdKey | shiftKey)
	}

	func testCarbonToFlags() {
		let flags = NSEvent.ModifierFlags(carbon: cmdKey | optionKey)
		XCTAssertTrue(flags.contains(.command))
		XCTAssertTrue(flags.contains(.option))
		XCTAssertFalse(flags.contains(.shift))
		XCTAssertFalse(flags.contains(.control))
	}

	func testCarbonToFlagsDetectsFunction() {
		XCTAssertTrue(NSEvent.ModifierFlags(carbon: 1 << 17).contains(.function))
	}

	func testRoundTripPreservesKnownFlags() {
		let original: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]
		let roundTripped = NSEvent.ModifierFlags(carbon: original.carbon)
		XCTAssertEqual(roundTripped, original)
	}

	func testCarbonInitIgnoresUnknownBits() {
		let flags = NSEvent.ModifierFlags(carbon: cmdKey | (1 << 20))
		XCTAssertEqual(flags, .command)
	}

	func testSymbolicRepresentationOrder() {
		// Order is fixed: control, option, shift, command.
		XCTAssertEqual(NSEvent.ModifierFlags([.command, .shift]).ks_symbolicRepresentation, "⇧⌘")
		XCTAssertEqual(NSEvent.ModifierFlags([.control, .option, .shift, .command]).ks_symbolicRepresentation, "⌃⌥⇧⌘")
		XCTAssertEqual(NSEvent.ModifierFlags().ks_symbolicRepresentation, "")
	}
}

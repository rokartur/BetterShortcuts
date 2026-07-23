import Combine
import AppKit
import Carbon.HIToolbox
import os

private func carbonBetterShortcutsEventHandler(eventHandlerCall: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
	CarbonBetterShortcuts.handleEvent(event)
}

enum CarbonBetterShortcuts {
	private static let log = Logger(subsystem: "pro.bettershortcuts.BetterShortcuts", category: "hotkeys")

	private final class HotKey {
		let shortcut: BetterShortcuts.Shortcut
		let carbonHotKeyId: Int
		var carbonHotKey: EventHotKeyRef?
		let onKeyDown: (BetterShortcuts.Shortcut) -> Void
		let onKeyUp: (BetterShortcuts.Shortcut) -> Void

		init(
			shortcut: BetterShortcuts.Shortcut,
			carbonHotKeyID: Int,
			carbonHotKey: EventHotKeyRef,
			onKeyDown: @escaping (BetterShortcuts.Shortcut) -> Void,
			onKeyUp: @escaping (BetterShortcuts.Shortcut) -> Void
		) {
			self.shortcut = shortcut
			self.carbonHotKeyId = carbonHotKeyID
			self.carbonHotKey = carbonHotKey
			self.onKeyDown = onKeyDown
			self.onKeyUp = onKeyUp
		}
	}

	nonisolated(unsafe) private static var hotKeys = [Int: HotKey]()

	// Hot key IDs whose key-down was rejected by the modifier check; the matching
	// key-up must be swallowed too so clients never see an unpaired release.
	nonisolated(unsafe) private static var suppressedHotKeyIds = Set<Int>()

	// Modifiers that must match the keyboard state when a hot key fires. Caps
	// Lock and fn are deliberately excluded so they can't block a legitimate
	// press.
	private static let validatedModifiers = cmdKey | optionKey | controlKey | shiftKey

	static func heldModifiersMatch(held: Int, registered: Int) -> Bool {
		held & validatedModifiers == registered & validatedModifiers
	}

	// `SSKS` is just short for `Sindre Sorhus Keyboard Shortcuts`.
	// Using an integer now that `UTGetOSTypeFromString("SSKS" as CFString)` is deprecated.
	// swiftlint:disable:next number_separator
	private static let hotKeySignature: UInt32 = 1397967699 // OSType => "SSKS"

	nonisolated(unsafe) private static var hotKeyId = 0
	nonisolated(unsafe) private static var eventHandler: EventHandlerRef?

	private static let hotKeyEventTypes = [
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
	]
	private static let rawKeyEventTypes = [
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyDown)),
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyUp))
	]

	nonisolated(unsafe) private static var keyEventMonitor: RunLoopLocalEventMonitor? = RunLoopLocalEventMonitor(events: [.keyDown, .keyUp], runLoopMode: .eventTracking) { event in
		guard
			let eventRef = OpaquePointer(event.eventRef),
			handleRawKeyEvent(eventRef) == noErr
		else {
			return event
		}

		return nil
	}

	private static func setUpEventHandlerIfNeeded() {
		guard
			eventHandler == nil,
			let dispatcher = GetEventDispatcherTarget()
		else {
			return
		}

		var handler: EventHandlerRef?
		let error = InstallEventHandler(
			dispatcher,
			carbonBetterShortcutsEventHandler,
			0,
			nil,
			nil,
			&handler
		)

		guard
			error == noErr,
			let handler
		else {
			return
		}

		eventHandler = handler

		updateEventHandler()
	}

	static func updateEventHandler() {
		guard eventHandler != nil else {
			return
		}

		if BetterShortcuts.isEnabled {
			if BetterShortcuts.isMenuOpen {
				softUnregisterAll()
				RemoveEventTypesFromHandler(eventHandler, hotKeyEventTypes.count, hotKeyEventTypes)

				if #available(macOS 14, *) {
					keyEventMonitor?.start()
				} else {
					AddEventTypesToHandler(eventHandler, rawKeyEventTypes.count, rawKeyEventTypes)
				}
			} else {
				softRegisterAll()

				if #available(macOS 14, *) {
					keyEventMonitor?.stop()
				} else {
					RemoveEventTypesFromHandler(eventHandler, rawKeyEventTypes.count, rawKeyEventTypes)
				}

				AddEventTypesToHandler(eventHandler, hotKeyEventTypes.count, hotKeyEventTypes)
			}
		} else {
			softUnregisterAll()
			RemoveEventTypesFromHandler(eventHandler, hotKeyEventTypes.count, hotKeyEventTypes)

			if #available(macOS 14, *) {
				keyEventMonitor?.stop()
			} else {
				RemoveEventTypesFromHandler(eventHandler, rawKeyEventTypes.count, rawKeyEventTypes)
			}
		}
	}

	static func register(
		_ shortcut: BetterShortcuts.Shortcut,
		onKeyDown: @escaping (BetterShortcuts.Shortcut) -> Void,
		onKeyUp: @escaping (BetterShortcuts.Shortcut) -> Void
	) {
		hotKeyId += 1

		var eventHotKey: EventHotKeyRef?
		let registerError = RegisterEventHotKey(
			UInt32(shortcut.carbonKeyCode),
			UInt32(shortcut.carbonModifiers),
			EventHotKeyID(signature: hotKeySignature, id: UInt32(hotKeyId)),
			GetEventDispatcherTarget(),
			0,
			&eventHotKey
		)

		guard
			registerError == noErr,
			let carbonHotKey = eventHotKey
		else {
			log.error("Error registering hotkey \(String(describing: shortcut), privacy: .public): \(registerError)")
			return
		}

		hotKeys[hotKeyId] = HotKey(
			shortcut: shortcut,
			carbonHotKeyID: hotKeyId,
			carbonHotKey: carbonHotKey,
			onKeyDown: onKeyDown,
			onKeyUp: onKeyUp
		)

		setUpEventHandlerIfNeeded()
	}

	static func softRegisterAll() {
		for hotKey in hotKeys.values {
			guard hotKey.carbonHotKey == nil else {
				continue
			}

			var eventHotKey: EventHotKeyRef?
			let error = RegisterEventHotKey(
				UInt32(hotKey.shortcut.carbonKeyCode),
				UInt32(hotKey.shortcut.carbonModifiers),
				EventHotKeyID(signature: hotKeySignature, id: UInt32(hotKey.carbonHotKeyId)),
				GetEventDispatcherTarget(),
				0,
				&eventHotKey
			)

			guard
				error == noErr,
				let eventHotKey
			else {
				log.error("Error registering hotkey \(String(describing: hotKey.shortcut), privacy: .public): \(error)")
				hotKeys.removeValue(forKey: hotKey.carbonHotKeyId)
				continue
			}

			hotKey.carbonHotKey = eventHotKey
		}
	}

	private static func unregisterHotKey(_ hotKey: HotKey) {
		UnregisterEventHotKey(hotKey.carbonHotKey)
		hotKeys.removeValue(forKey: hotKey.carbonHotKeyId)
		suppressedHotKeyIds.remove(hotKey.carbonHotKeyId)
	}

	static func unregister(_ shortcut: BetterShortcuts.Shortcut) {
		for hotKey in hotKeys.values where hotKey.shortcut == shortcut {
			unregisterHotKey(hotKey)
		}
	}

	static func unregisterAll() {
		for hotKey in hotKeys.values {
			unregisterHotKey(hotKey)
		}
	}

	static func softUnregisterAll() {
		for hotKey in hotKeys.values {
			UnregisterEventHotKey(hotKey.carbonHotKey)
			hotKey.carbonHotKey = nil
		}
	}

	fileprivate static func handleEvent(_ event: EventRef?) -> OSStatus {
		guard let event else {
			return OSStatus(eventNotHandledErr)
		}

		switch Int(GetEventKind(event)) {
		case kEventHotKeyPressed, kEventHotKeyReleased:
			return handleHotKeyEvent(event)
		case kEventRawKeyDown, kEventRawKeyUp:
			return handleRawKeyEvent(event)
		default:
			break
		}

		return OSStatus(eventNotHandledErr)
	}

	private static func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
		var eventHotKeyId = EventHotKeyID()
		let error = GetEventParameter(
			event,
			UInt32(kEventParamDirectObject),
			UInt32(typeEventHotKeyID),
			nil,
			MemoryLayout<EventHotKeyID>.size,
			nil,
			&eventHotKeyId
		)

		guard error == noErr else {
			return error
		}

		guard
			eventHotKeyId.signature == hotKeySignature,
			let hotKey = hotKeys[Int(eventHotKeyId.id)]
		else {
			return OSStatus(eventNotHandledErr)
		}

		switch Int(GetEventKind(event)) {
		case kEventHotKeyPressed:
			// Carbon identifies the hot key only by its registration ID. Don't
			// trust it blindly: some layout/remapper combinations deliver the
			// notification with the wrong modifiers held
			// (rokartur/BetterCmdTab#120), so re-check the actual keyboard state
			// and swallow the press on mismatch.
			let held = Int(GetCurrentEventKeyModifiers())
			guard heldModifiersMatch(held: held, registered: hotKey.shortcut.carbonModifiers) else {
				suppressedHotKeyIds.insert(hotKey.carbonHotKeyId)
				log.warning("Ignoring hot key \(String(describing: hotKey.shortcut), privacy: .public): held modifiers \(held) don't match registration")
				return noErr
			}
			hotKey.onKeyDown(hotKey.shortcut)
			return noErr
		case kEventHotKeyReleased:
			guard suppressedHotKeyIds.remove(hotKey.carbonHotKeyId) == nil else {
				return noErr
			}
			hotKey.onKeyUp(hotKey.shortcut)
			return noErr
		default:
			break
		}

		return OSStatus(eventNotHandledErr)
	}

	private static func handleRawKeyEvent(_ event: EventRef) -> OSStatus {
		var eventKeyCode = UInt32()
		let keyCodeError = GetEventParameter(
			event,
			UInt32(kEventParamKeyCode),
			typeUInt32,
			nil,
			MemoryLayout<UInt32>.size,
			nil,
			&eventKeyCode
		)

		guard keyCodeError == noErr else {
			return keyCodeError
		}

		var eventKeyModifiers = UInt32()
		let keyModifiersError = GetEventParameter(
			event,
			UInt32(kEventParamKeyModifiers),
			typeUInt32,
			nil,
			MemoryLayout<UInt32>.size,
			nil,
			&eventKeyModifiers
		)

		guard keyModifiersError == noErr else {
			return keyModifiersError
		}

		let shortcut = BetterShortcuts.Shortcut(carbonKeyCode: Int(eventKeyCode), carbonModifiers: Int(eventKeyModifiers))

		guard let hotKey = (hotKeys.values.first { $0.shortcut == shortcut }) else {
			return OSStatus(eventNotHandledErr)
		}

		switch Int(GetEventKind(event)) {
		case kEventRawKeyDown:
			hotKey.onKeyDown(hotKey.shortcut)
			return noErr
		case kEventRawKeyUp:
			hotKey.onKeyUp(hotKey.shortcut)
			return noErr
		default:
			break
		}

		return OSStatus(eventNotHandledErr)
	}
}

extension CarbonBetterShortcuts {
	static var system: [BetterShortcuts.Shortcut] {
		var shortcutsUnmanaged: Unmanaged<CFArray>?
		guard
			CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
			let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
		else {
			assertionFailure("Could not get system keyboard shortcuts")
			return []
		}

		return shortcuts.compactMap {
			guard
				($0[kHISymbolicHotKeyEnabled] as? Bool) == true,
				let carbonKeyCode = $0[kHISymbolicHotKeyCode] as? Int,
				let carbonModifiers = $0[kHISymbolicHotKeyModifiers] as? Int
			else {
				return nil
			}

			return BetterShortcuts.Shortcut(
				carbonKeyCode: carbonKeyCode,
				carbonModifiers: carbonModifiers
			)
		}
	}
}

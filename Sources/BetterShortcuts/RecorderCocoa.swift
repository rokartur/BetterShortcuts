import Combine
import AppKit
import Carbon.HIToolbox

extension BetterShortcuts {
	/**
	A `NSView` that lets the user record a keyboard shortcut.

	You would usually put this in your settings window.

	It automatically prevents choosing a keyboard shortcut that is already taken by the system or by the app's main menu by showing a user-friendly alert to the user.

	It takes care of storing the keyboard shortcut in `UserDefaults` for you.

	```swift
	import AppKit
	import BetterShortcuts

	final class SettingsViewController: NSViewController {
		override func loadView() {
			view = NSView()

			let recorder = BetterShortcuts.RecorderCocoa(for: .toggleUnicornMode)
			view.addSubview(recorder)
		}
	}
	```
	*/
	public final class RecorderCocoa: NSSearchField, NSSearchFieldDelegate {
		private let minimumWidth = 135.0
		private let onChange: ((_ shortcut: Shortcut?) -> Void)?
		private let policyOverride: RecorderPolicy?
		private var canBecomeKey = false
		private var eventMonitor: LocalEventMonitor?
		/// nonisolated(unsafe) to allow cleanup in deinit
		nonisolated(unsafe) private var shortcutsNameChangeObserver: NSObjectProtocol?
		nonisolated(unsafe) private var windowDidResignKeyObserver: NSObjectProtocol?
		nonisolated(unsafe) private var windowDidBecomeKeyObserver: NSObjectProtocol?

		/**
		The shortcut name for the recorder.

		Can be dynamically changed at any time.
		*/
		public var shortcutName: Name {
			didSet {
				guard shortcutName != oldValue else {
					return
				}

				setStringValue(name: shortcutName)

				// This doesn't seem to be needed anymore, but I cannot test on older OS versions, so keeping it just in case.
				if #unavailable(macOS 12) {
					DispatchQueue.main.async { [weak self] in
						// Prevents the placeholder from being cut off.
						self?.blur()
					}
				}
			}
		}

		/// :nodoc:
		override public var canBecomeKeyView: Bool { canBecomeKey }

		/// :nodoc:
		override public var intrinsicContentSize: CGSize {
			var size = super.intrinsicContentSize
			size.width = max(minimumWidth, measuredContentWidth())
			return size
		}

		private func measuredContentWidth() -> CGFloat {
			guard let cell = cell as? NSSearchFieldCell else {
				return minimumWidth
			}

			return ceil(cell.cellSize.width)
		}

		private func refreshIntrinsicWidth() {
			invalidateIntrinsicContentSize()
		}

		private var cancelButton: NSButtonCell?

		private var showsCancelButton: Bool {
			get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
			set {
				(cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil
			}
		}

		/**
		- Parameter name: Strongly-typed keyboard shortcut name.
		- Parameter onChange: Callback which will be called when the keyboard shortcut is changed/removed by the user. This can be useful when you need more control. For example, when migrating from a different keyboard shortcut solution and you need to store the keyboard shortcut somewhere yourself instead of relying on the built-in storage. However, it's strongly recommended to just rely on the built-in storage when possible.
		*/
		public required init(
			for name: Name,
			policy: RecorderPolicy? = nil,
			onChange: ((_ shortcut: Shortcut?) -> Void)? = nil
		) {
			self.shortcutName = name
			self.policyOverride = policy
			self.onChange = onChange

			// Use a default frame that matches our intrinsic size to prevent zero-size issues
			// when added without constraints (issue #209)
			super.init(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: 24))
			self.delegate = self
			self.placeholderString = "Record Shortcut"
			self.alignment = .center
			(cell as? NSSearchFieldCell)?.searchButtonCell = nil

			self.wantsLayer = true
			setContentHuggingPriority(.defaultHigh, for: .vertical)
			setContentHuggingPriority(.defaultHigh, for: .horizontal)

			// Hide the cancel button when not showing the shortcut so the placeholder text is properly centered. Must be last.
			self.cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell

			setStringValue(name: name)

			setUpEvents()
		}

		deinit {
			if let observer = shortcutsNameChangeObserver {
				NotificationCenter.default.removeObserver(observer)
			}
			if let observer = windowDidResignKeyObserver {
				NotificationCenter.default.removeObserver(observer)
			}
			if let observer = windowDidBecomeKeyObserver {
				NotificationCenter.default.removeObserver(observer)
			}
		}

		@available(*, unavailable)
		public required init?(coder: NSCoder) {
			fatalCoderNotImplemented()
		}

		private func setStringValue(name: BetterShortcuts.Name) {
			stringValue = getShortcut(for: shortcutName).map { "\($0)" } ?? ""

			// If `stringValue` is empty, hide the cancel button to let the placeholder center.
			showsCancelButton = !stringValue.isEmpty
			refreshIntrinsicWidth()
		}

		private func setUpEvents() {
			let expectedName = shortcutName.rawValue
			shortcutsNameChangeObserver = NotificationCenter.default.addObserver(forName: .shortcutByNameDidChange, object: nil, queue: .main) { [weak self] notification in
				guard let self else { return }
				guard let rawName = notification.userInfo?["name"] as? String else { return }
				
				guard rawName == expectedName else { return }

				MainActor.assumeIsolated { [weak self] in
					guard let self else { return }
					self.setStringValue(name: self.shortcutName)
				}
			}
		}

		private func endRecording() {
			eventMonitor = nil
			placeholderString = "Record Shortcut"
			showsCancelButton = !stringValue.isEmpty
			refreshIntrinsicWidth()
			restoreCaret()
			BetterShortcuts.isPaused = false
			NotificationCenter.default.post(name: .recorderActiveStatusDidChange, object: nil, userInfo: ["isActive": false])
		}

		private func preventBecomingKey() {
			canBecomeKey = false

			// Prevent the control from receiving the initial focus.
			DispatchQueue.main.async { [weak self] in
				self?.canBecomeKey = true
			}
		}

		/// :nodoc:
		public func controlTextDidChange(_ object: Notification) {
			if stringValue.isEmpty {
				saveShortcut(nil)
			}

			showsCancelButton = !stringValue.isEmpty
			refreshIntrinsicWidth()

			if stringValue.isEmpty {
				// Hack to ensure that the placeholder centers after the above `showsCancelButton` setter.
				focus()
			}
		}

		/// :nodoc:
		public func controlTextDidEndEditing(_ object: Notification) {
			endRecording()
		}

		/// :nodoc:
		override public func viewDidMoveToWindow() {
			guard let window else {
				if let observer = windowDidResignKeyObserver {
					NotificationCenter.default.removeObserver(observer)
					windowDidResignKeyObserver = nil
				}
				if let observer = windowDidBecomeKeyObserver {
					NotificationCenter.default.removeObserver(observer)
					windowDidBecomeKeyObserver = nil
				}
				endRecording()
				return
			}

			// Ensures the recorder stops when the window is hidden.
			// This is especially important for Settings windows, which as of macOS 13.5, only hides instead of closes when you click the close button.
			windowDidResignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { [weak self] in
					guard let self, let window = self.window else { return }
					self.endRecording()
					window.makeFirstResponder(nil)
				}
			}

			// Ensures the recorder does not receive initial focus when a hidden window becomes unhidden.
			windowDidBecomeKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { [weak self] in
					self?.preventBecomingKey()
				}
			}

			preventBecomingKey()
		}

		/// :nodoc:
		override public func becomeFirstResponder() -> Bool {
			// Ensure we have a valid window before attempting to become first responder
			// This prevents issues in SwiftUI contexts where the view hierarchy might not be fully established
			guard window != nil else {
				return false
			}

			let shouldBecomeFirstResponder = super.becomeFirstResponder()

			guard shouldBecomeFirstResponder else {
				return shouldBecomeFirstResponder
			}

			placeholderString = "Press shortcut…"
			showsCancelButton = !stringValue.isEmpty
			refreshIntrinsicWidth()
			hideCaret()
			BetterShortcuts.isPaused = true // The position here matters.
			NotificationCenter.default.post(name: .recorderActiveStatusDidChange, object: nil, userInfo: ["isActive": true])

			eventMonitor = LocalEventMonitor(events: [.keyDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
				guard let self else {
					return nil
				}

				let clickPoint = convert(event.locationInWindow, from: nil)
				let clickMargin = 3.0

				if
					event.type == .leftMouseUp || event.type == .rightMouseUp,
					!bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)
				{
					blur()
					return event
				}

				guard event.isKeyEvent else {
					return nil
				}

				if
					event.modifiers.isEmpty,
					event.specialKey == .tab
				{
					blur()

					// We intentionally bubble up the event so it can focus the next responder.
					return event
				}

				if
					event.modifiers.isEmpty,
					event.keyCode == kVK_Escape // TODO: Make this strongly typed.
				{
					blur()
					return nil
				}

				if
					event.modifiers.isEmpty,
					event.specialKey == .delete
						|| event.specialKey == .deleteForward
						|| event.specialKey == .backspace
				{
					clear()
					return nil
				}

				// Accept only combinations allowed by the active recorder policy. The default
				// (`.standard`) requires a hold modifier (Command/Option/Control) and allows Shift,
				// so ⌘⇧-style shortcuts work. Switcher apps opt into `.switcher` to reserve Shift.
				let policy = policyOverride ?? BetterShortcuts.recorderPolicy
				guard
					policy.accepts(modifiers: event.modifiers),
					let shortcut = Shortcut(event: event)
				else {
					NSSound.beep()
					return nil
				}

				if let menuItem = shortcut.takenByMainMenu {
					// TODO: Find a better way to make it possible to dismiss the alert by pressing "Enter". How can we make the input automatically temporarily lose focus while the alert is open?
					blur()

					NSAlert.showModal(
						for: window,
						title: String.localizedStringWithFormat("This keyboard shortcut is already used by the menu item “%@”.", menuItem.title)
					)

					focus()

					return nil
				}

				// See: https://developer.apple.com/forums/thread/763878?answerId=804374022#804374022
				if shortcut.isDisallowed {
					blur()

					NSAlert.showModal(
						for: window,
						title: "This keyboard shortcut is not allowed."
					)

					focus()
					return nil
				}

				if shortcut.isTakenBySystem {
					blur()

					let modalResponse = NSAlert.showModal(
						for: window,
						title: "This keyboard shortcut is used by the system.",
						// TODO: Add button to offer to open the relevant system settings pane for the user.
						message: "Most system shortcuts can be changed in “System Settings › Keyboard › Keyboard Shortcuts”.",
						buttonTitles: ["OK", "Use Anyway"]
					)

					focus()

					// If the user has selected "Use Anyway" in the dialog (the second option), we'll continue setting the keyboard shorcut even though it's reserved by the system.
					guard modalResponse == .alertSecondButtonReturn else {
						return nil
					}
				}

				// Check if the shortcut is already assigned to another app function.
				// Skipped when the policy allows duplicates (independent scopes, e.g.
				// per-profile keys, where the same chord may recur under another name).
				if !policy.allowsDuplicateShortcuts,
				   let conflictingName = BetterShortcuts.allNames.first(where: { name in
					name.rawValue != self.shortcutName.rawValue && BetterShortcuts.getShortcut(for: name) == shortcut
				}) {
					// Capture the window reference BEFORE blur() destroys the first-responder chain,
					// since blur() triggers endRecording() → eventMonitor = nil inside this callback.
					let alertWindow = self.window

					blur()

					let alert = NSAlert()
					alert.messageText = String.localizedStringWithFormat(
						"This keyboard shortcut is already used by “%@”.",
						BetterShortcuts.displayName?(conflictingName) ?? conflictingName.rawValue
					)
					alert.informativeText = "Do you want to reassign it to this function instead?"
					alert.alertStyle = .warning
					alert.addButton(withTitle: "Cancel")
					alert.addButton(withTitle: "Reassign")

					let modalResponse: NSApplication.ModalResponse
					if let alertWindow, alertWindow.isVisible {
						// Show as window-modal sheet
						alert.beginSheetModal(for: alertWindow) { returnCode in
							NSApp.stopModal(withCode: returnCode)
						}
						modalResponse = NSApp.runModal(for: alertWindow)
					} else {
						// Fallback to app-modal dialog
						modalResponse = alert.runModal()
					}

					// If the user chose "Reassign" (second button), remove from old function and continue
					guard modalResponse == .alertSecondButtonReturn else {
						focus()
						return nil
					}

					// Remove the shortcut from the conflicting function
					BetterShortcuts.setShortcut(nil, for: conflictingName)
				}

				stringValue = "\(shortcut)"
				showsCancelButton = true
				refreshIntrinsicWidth()

				saveShortcut(shortcut)
				blur()

				return nil
			}.start()

			return shouldBecomeFirstResponder
		}

		private func saveShortcut(_ shortcut: Shortcut?) {
			setShortcut(shortcut, for: shortcutName)
			onChange?(shortcut)
		}
	}
}

extension Notification.Name {
	static let recorderActiveStatusDidChange = Self("BetterShortcuts_recorderActiveStatusDidChange")
}

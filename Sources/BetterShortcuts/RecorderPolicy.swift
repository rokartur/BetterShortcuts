import AppKit

extension BetterShortcuts {
	/**
	Controls which key combinations the recorder UI (``Recorder`` / ``RecorderCocoa``) accepts.

	The default, ``standard``, suits most apps: any combination that includes a "hold" modifier
	(Command / Option / Control), **with Shift allowed** — so ⌘⇧-style shortcuts (common in
	screenshot and productivity apps) can be recorded.

	Hold-to-reveal switchers (Cmd-Tab style) that reserve Shift for reverse stepping should opt into
	``switcher``. Set the global default once at launch, or pass a policy to an individual recorder:

	```swift
	BetterShortcuts.recorderPolicy = .standard          // app-wide
	BetterShortcuts.RecorderCocoa(for: .capture, policy: .unrestricted) // per-recorder override
	```
	*/
	public struct RecorderPolicy: Sendable, Hashable {
		/// Allow combinations that contain Shift (e.g. ⌘⇧4). Default `true`.
		public var allowsShift: Bool

		/// Require at least one "hold" modifier — Command, Option, or Control. Default `true`.
		public var requiresHoldModifier: Bool

		/// Allow shortcuts with no modifier at all (e.g. function keys, `F5`). Default `false`.
		public var allowsModifierFree: Bool

		/// Allow recording a shortcut already assigned to another ``Name``, without
		/// the "already used by …" reassignment alert. Default `false`.
		///
		/// Leave `false` for app-wide hotkeys, where one chord should map to one
		/// function. Set `true` for recorders backing *independent scopes* — e.g.
		/// per-profile / per-document keys where the same chord legitimately recurs
		/// under a different ``Name`` (only the system / main-menu conflict checks
		/// still apply).
		public var allowsDuplicateShortcuts: Bool

		/// Refuse a chord listed in ``BetterShortcuts/reservedShortcuts`` (e.g. the
		/// host's always-on global triggers). Default `false`. Set `true` for
		/// recorders that must not shadow such a trigger; leave `false` for the
		/// recorder that *defines* it (so it can still bind that chord).
		public var rejectsReservedShortcuts: Bool

		public init(
			allowsShift: Bool = true,
			requiresHoldModifier: Bool = true,
			allowsModifierFree: Bool = false,
			allowsDuplicateShortcuts: Bool = false,
			rejectsReservedShortcuts: Bool = false
		) {
			self.allowsShift = allowsShift
			self.requiresHoldModifier = requiresHoldModifier
			self.allowsModifierFree = allowsModifierFree
			self.allowsDuplicateShortcuts = allowsDuplicateShortcuts
			self.rejectsReservedShortcuts = rejectsReservedShortcuts
		}

		/// General-purpose default: a hold modifier is required and Shift is allowed. Good for most apps.
		public static let standard = Self()

		/// Hold-to-reveal switchers: Shift is reserved (rejected), a hold modifier is required.
		public static let switcher = Self(allowsShift: false, requiresHoldModifier: true)

		/// Anything goes, including modifier-free keys such as function keys.
		public static let unrestricted = Self(allowsShift: true, requiresHoldModifier: false, allowsModifierFree: true)

		/// Whether the modifiers of a candidate event satisfy this policy.
		func accepts(modifiers: NSEvent.ModifierFlags) -> Bool {
			if !allowsShift, modifiers.contains(.shift) { return false }
			let hasHold = !modifiers.intersection([.command, .option, .control]).isEmpty
			if requiresHoldModifier, !hasHold { return false }
			if !allowsModifierFree, modifiers.isEmpty { return false }
			return true
		}
	}
}

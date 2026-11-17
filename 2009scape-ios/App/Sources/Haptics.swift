import UIKit

/// Thin wrapper over UIKit feedback generators.
@MainActor
final class Haptics {
	static let shared = Haptics()
	private let light = UIImpactFeedbackGenerator(style: .light)
	private let medium = UIImpactFeedbackGenerator(style: .medium)
	private let selection = UISelectionFeedbackGenerator()

	func prepare() { medium.prepare(); light.prepare() }
	/// Long press opened a menu.
	func menuOpened() { guard MobileSettings.haptics else { return }; medium.impactOccurred() }
	/// An inventory item was picked up or dropped.
	func dragPickup() { guard MobileSettings.haptics else { return }; light.impactOccurred() }
	func dragDrop() { guard MobileSettings.haptics else { return }; medium.impactOccurred() }
	func rowSelected() { guard MobileSettings.haptics else { return }; selection.selectionChanged() }
}

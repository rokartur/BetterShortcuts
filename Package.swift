// swift-tools-version:6.0
import PackageDescription

let package = Package(
	name: "BetterShortcuts",
	platforms: [
		.macOS(.v13)
	],
	products: [
		.library(
			name: "BetterShortcuts",
			targets: ["BetterShortcuts"]
		)
	],
	targets: [
		.target(
			name: "BetterShortcuts"
		),
		.testTarget(
			name: "BetterShortcutsTests",
			dependencies: ["BetterShortcuts"]
		)
	]
)

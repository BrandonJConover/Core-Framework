import SwiftUI

@main
struct Scape530App: App {
	@StateObject private var model = AppModel()

	var body: some Scene {
		WindowGroup {
			RootView()
				.environmentObject(model)
				.statusBarHidden(true)
				.persistentSystemOverlays(.hidden)
				.preferredColorScheme(.dark)
		}
	}
}

import SwiftUI
import Scape530

struct RootView: View {
	@EnvironmentObject var model: AppModel
	@State private var showingServer = false
	@State private var showingSettings = false
	@Environment(\.scenePhase) private var scenePhase

	var body: some View {
		ZStack(alignment: .topTrailing) {
			Color.black.ignoresSafeArea()
			switch model.phase {
			case .updatingCache(let label, let fraction):
				LoadingBar(label: label, fraction: fraction)
			case .ready(let client):
				GameView(client: client).id(ObjectIdentifier(client))
			case .failed(let message):
				VStack(spacing: 16) {
					Text(message)
						.font(.system(size: 14, weight: .bold, design: .default))
						.foregroundColor(.white)
						.multilineTextAlignment(.center)
					HStack(spacing: 24) {
						Button("Set server") { showingServer = true }
						Button("Try again") { model.start() }
					}
				}
				.padding()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			HStack(spacing: 0) {
				Button {
					showingSettings = true
				} label: {
					Image(systemName: "slider.horizontal.3")
						.foregroundColor(.white.opacity(0.6))
						.frame(width: 44, height: 44)
				}
				// Server configuration belongs to setup and error states; on the game screen it would cover
				// gameplay and catch stray taps.
				if !model.isReady {
					Button {
						showingServer = true
					} label: {
						Image(systemName: "server.rack")
							.foregroundColor(.white.opacity(0.6))
							.frame(width: 44, height: 44)
					}
				}
			}
		}
		.onChange(of: scenePhase) { model.scenePhaseChanged($0) }
		.sheet(isPresented: $showingSettings) { TouchSettingsView(plugins: model.plugins) }
		.onAppear {
			// First launch: there is no sensible default server for a phone.
			if !model.hasConfiguredServer { showingServer = true }
		}
		.sheet(isPresented: $showingServer) {
			ServerSettingsView(host: model.host, port: String(model.port)) { host, port in
				model.applyServer(host: host, port: port)
			}
		}
	}
}

/// rt4's pre-cache loading bar (`GameShell.drawProgress`): a red outline and
/// fill on black with white Helvetica-bold text.
struct LoadingBar: View {
	let label: String
	let fraction: Double
	private let red = Color(red: 140 / 255, green: 17 / 255, blue: 17 / 255)

	var body: some View {
		ZStack(alignment: .leading) {
			Rectangle().stroke(red, lineWidth: 1)
			Rectangle().fill(red).frame(width: 300 * fraction)
			Text(label)
				.font(.custom("Helvetica-Bold", size: 13))
				.foregroundColor(.white)
				.frame(width: 300)
		}
		.frame(width: 304, height: 34)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

struct ServerSettingsView: View {
	@Environment(\.dismiss) private var dismiss
	@State var host: String
	@State var port: String
	let onSave: (String, Int) -> Void

	var body: some View {
		NavigationStack {
			Form {
				Section("2009scape server") {
					TextField("Host", text: $host)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.keyboardType(.URL)
					TextField("Port (43594 + world)", text: $port)
						.keyboardType(.numberPad)
				}
				Section {
					Text("The same port serves the cache (JS5) and the game. World 1 is 43595.")
						.font(.footnote)
						.foregroundColor(.secondary)
				}
			}
			.navigationTitle("Server")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						onSave(host.trimmingCharacters(in: .whitespaces), Int(port) ?? 43595)
						dismiss()
					}
				}
			}
		}
	}
}

/// Touch-layer options (bound to the keys in `MobileSettings`).
struct TouchSettingsView: View {
	@Environment(\.dismiss) private var dismiss
	/// The plugins of the running client (nil while the cache is still loading).
	var plugins: PluginManager?
	@AppStorage(MobileSettings.mobileMenuKey) private var mobileMenu = true
	@AppStorage(MobileSettings.tapToDropKey) private var tapToDrop = false
	@AppStorage(MobileSettings.smoothScalingKey) private var smoothScaling = true
	@AppStorage(MobileSettings.hapticsKey) private var haptics = true
	@AppStorage(MobileSettings.smoothMotionKey) private var smoothMotion = true
	@AppStorage(MobileSettings.gpuRendererKey) private var gpuRenderer = false
	@AppStorage(MobileSettings.gpuDrawDistanceKey) private var drawDistance = 56.0
	@AppStorage(MobileSettings.gpuFogKey) private var gpuFog = true
	@AppStorage(MobileSettings.gpuAntialiasKey) private var gpuAntialias = true

	var body: some View {
		NavigationStack {
			Form {
				Section("Touch") {
					Toggle("Mobile options menu", isOn: $mobileMenu)
					Toggle("Tap to drop items", isOn: $tapToDrop)
					Toggle("Haptic feedback", isOn: $haptics)
				}
				Section("Display") {
					Toggle("Smooth scaling", isOn: $smoothScaling)
					Toggle("Smooth motion (60/120 Hz)", isOn: $smoothMotion)
				}
				Section("3D renderer") {
					Toggle("GPU renderer (Metal)", isOn: $gpuRenderer)
					if gpuRenderer {
						VStack(alignment: .leading) {
							Text("Draw distance: \(Int(drawDistance)) tiles")
							Slider(value: $drawDistance, in: 25...100, step: 1)
						}
						Toggle("Distance fog", isOn: $gpuFog)
						Toggle("Anti-aliasing (4x MSAA)", isOn: $gpuAntialias)
					}
					Text(gpuRenderer ? "Longer draw distance, smoothed edges and filtered textures. Turn off for the exact software look (25 tiles)." : "Off: the faithful software renderer (25 tiles).")
						.font(.footnote)
						.foregroundColor(.secondary)
				}
				if let plugins {
					Section("Plugins") {
						NavigationLink("Plugins") { PluginsView(manager: plugins) }
						NavigationLink("XP tracker") { XpTrackerView(manager: plugins) }
					}
				}
				Section {
					Text("Tap does the first action. Touch and hold for the full options. Drag the world to turn the camera; two fingers tilt; pinch zooms.")
						.font(.footnote)
						.foregroundColor(.secondary)
				}
			}
			.navigationTitle("Controls")
			.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
		}
	}
}

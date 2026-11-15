import SwiftUI
import Scape530

struct RootView: View {
	@EnvironmentObject var model: AppModel
	@State private var showingServer = false

	var body: some View {
		ZStack(alignment: .topTrailing) {
			Color.black.ignoresSafeArea()
			switch model.phase {
			case .updatingCache(let label, let fraction):
				LoadingBar(label: label, fraction: fraction)
			case .ready(let client):
				GameView(client: client)
			case .failed(let message):
				VStack(spacing: 16) {
					Text(message)
						.font(.system(size: 14, weight: .bold, design: .default))
						.foregroundColor(.white)
						.multilineTextAlignment(.center)
					Button("Try again") { model.start() }
				}
				.padding()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			Button {
				showingServer = true
			} label: {
				Image(systemName: "server.rack")
					.foregroundColor(.white.opacity(0.6))
					.padding(10)
			}
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

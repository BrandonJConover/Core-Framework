import SwiftUI

/// Container view that manages game state and displays appropriate screens.
struct GameContainerView: View {
    @EnvironmentObject private var gameState: GameState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = gameState.errorMessage {
                ErrorView(message: error) {
                    gameState.errorMessage = nil
                }
            } else if !gameState.isConnected {
                LoginView()
            } else if gameState.loadingProgress < 1.0 {
                LoadingView(
                    progress: gameState.loadingProgress,
                    status: gameState.loadingStatus
                )
            } else {
                GameView()
            }
        }
        .ignoresSafeArea()
    }
}

/// Loading screen with progress bar.
struct LoadingView: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("OpenRSC")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 280)
                    .tint(Color(red: 0.52, green: 0.52, blue: 0.52))

                Text(status)
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.78))
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)

            Text("Powered by OpenRSC")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))

            Spacer()
        }
    }
}

/// Error display view.
struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Error")
                .font(.title)
                .foregroundColor(.white)

            Text(message)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Login/server selection view.
struct LoginView: View {
    @EnvironmentObject private var gameState: GameState
    @State private var serverAddress = "localhost:43594"
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("OpenRSC")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)

            Text("iOS Client")
                .font(.system(size: 18))
                .foregroundColor(.gray)

            Spacer()

            VStack(spacing: 16) {
                TextField("Server Address", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Connect")
                            .font(.headline)
                    }
                }
                .frame(width: 280, height: 44)
                .background(Color(red: 0.52, green: 0.52, blue: 0.52))
                .foregroundColor(.white)
                .cornerRadius(8)
                .disabled(isConnecting)
            }

            Spacer()

            Text("We support open source")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.4))
                .padding(.bottom, 20)
        }
    }

    private func connect() {
        let parts = serverAddress.split(separator: ":")
        gameState.serverHost = String(parts[0])
        if parts.count > 1, let port = Int(parts[1]) {
            gameState.serverPort = port
        }

        isConnecting = true
        Task {
            await gameState.connect()
            isConnecting = false
        }
    }
}

#Preview {
    GameContainerView()
        .environmentObject(GameState())
}

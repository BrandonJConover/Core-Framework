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
            } else if !gameState.isLoggedIn {
                LoginView()
            } else if let gameClient = gameState.gameClient {
                GameView(gameClient: gameClient)
            } else {
                LoadingView(
                    progress: gameState.loadingProgress,
                    status: gameState.loadingStatus
                )
            }
        }
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

/// Login/server selection view with separate fields for host, port, username, and password.
struct LoginView: View {
    @EnvironmentObject private var gameState: GameState
    @State private var password = ""
    @State private var isConnecting = false

    private var canConnect: Bool {
        !isConnecting &&
        !gameState.serverHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !gameState.serverPortText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !gameState.rememberedUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("OpenRSC")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    Text("iOS Client")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                }
                .padding(.top, 60)

                // Connection fields
                VStack(alignment: .leading, spacing: 16) {
                    Text("Server")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(white: 0.7))

                    HStack(spacing: 10) {
                        TextField("Host or LAN IP", text: $gameState.serverHost)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        TextField("Port", text: $gameState.serverPortText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }

                    Text("Login")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(white: 0.7))
                        .padding(.top, 4)

                    TextField("Username", text: $gameState.rememberedUsername)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                .frame(maxWidth: 320)

                // Connect button
                Button(action: connect) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(canConnect
                                  ? Color(red: 0.3, green: 0.55, blue: 0.3)
                                  : Color(white: 0.25))

                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Connect & Login")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: 320, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canConnect)

                // Status
                if !gameState.loadingStatus.isEmpty && gameState.loadingStatus != "Initializing..." {
                    Text(gameState.loadingStatus)
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.6))
                }

                // Tip
                Text("Use localhost in Simulator. On a physical device, enter your Mac's LAN IP.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    private func connect() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            await gameState.connectAndLogin(
                username: gameState.rememberedUsername,
                password: password
            )
        }
    }
}

#Preview {
    GameContainerView()
        .environmentObject(GameState())
}

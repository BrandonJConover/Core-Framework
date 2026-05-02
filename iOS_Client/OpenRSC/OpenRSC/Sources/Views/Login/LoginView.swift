import SwiftUI

struct LoginView: View {
    let server: ServerProfile
    @EnvironmentObject var appState: AppState
    @State private var username: String
    @State private var password = ""
    @State private var isLoggingIn = false

    init(server: ServerProfile) {
        self.server = server
        _username = State(initialValue: server.lastUsername)
    }

    var body: some View {
        ZStack {
            Color(hex: "#1a1a1a").ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { appState.currentView = .serverBrowser(server.gameType) }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color(hex: "#c8a951"))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 44, height: 44)
                    Spacer()
                    Text(server.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .background(Color(hex: "#222222"))

                Spacer()

                VStack(spacing: 20) {
                    Text("Sign In")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "#c8a951"))

                    Text("\(server.host):\(server.port)")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#666666"))

                    VStack(spacing: 12) {
                        RSCTextField(placeholder: "Username", text: $username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        RSCTextField(placeholder: "Password", text: $password, isSecure: true)
                    }

                    if !appState.loginError.isEmpty {
                        Text(appState.loginError)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: login) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: "#c8a951"))
                                .frame(height: 50)
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text("Login")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)

                    Button(action: { appState.currentView = .login(server) }) {
                        Text("Create Account")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "#c8a951"))
                            .underline()
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            appState.loginError = ""
        }
    }

    private func login() {
        isLoggingIn = true
        appState.loginError = ""
        if server.gameType == .rscWeb {
            appState.currentView = .webGame(server, username, password)
        } else {
            // Navigate to game view — engine connects and logs in with these credentials
            appState.currentView = .game(server, username, password)
        }
        isLoggingIn = false
    }
}

struct RSCTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .padding(14)
        .background(Color(hex: "#2a2a2a"))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#444444"), lineWidth: 1))
        .foregroundColor(.white)
        .font(.system(size: 16))
    }
}

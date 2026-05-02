import SwiftUI

struct LoginView: View {
    let server: ServerProfile
    @EnvironmentObject var appState: AppState
    @State private var username: String
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var isUnlocking = false
    @State private var saveForQuickLogin = false
    @State private var savedCredential: SavedLoginCredential?
    @State private var localMessage = ""

    private let biometricKind: BiometricKind

    init(server: ServerProfile) {
        self.server = server
        _username = State(initialValue: server.lastUsername)
        let storedCredential = BiometricLoginStore.loadCredential(for: server)
        _savedCredential = State(initialValue: storedCredential)
        _saveForQuickLogin = State(initialValue: storedCredential != nil)
        biometricKind = DeviceBiometrics.availableKind()
    }

    var body: some View {
        ZStack {
            Color(hex: "#1a1a1a").ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()

                VStack(spacing: 18) {
                    titleBlock

                    if let savedCredential {
                        savedLoginRow(savedCredential)
                    }

                    credentialsForm

                    if biometricKind != .none {
                        quickLoginToggle
                    }

                    statusMessage

                    loginButtons

                    Button(action: { appState.currentView = .login(server) }) {
                        Text("Create Account")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "#c8a951"))
                            .underline()
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 460)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            appState.loginError = ""
            localMessage = ""
        }
    }

    private var header: some View {
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
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Sign In")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(hex: "#c8a951"))

            Text("\(server.host):\(server.port)")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#666666"))
        }
    }

    private func savedLoginRow(_ credential: SavedLoginCredential) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: biometricKind.symbolName)
                    .foregroundColor(Color(hex: "#c8a951"))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved on this device")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(credential.username)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#888888"))
                }

                Spacer()
            }

            Button(action: clearSavedCredential) {
                Text("Remove Saved Login")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#c8a951"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: "#242424"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "#3d3d3d"), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .background(Color(hex: "#202020"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "#333333"), lineWidth: 1)
        )
    }

    private var credentialsForm: some View {
        VStack(spacing: 12) {
            RSCTextField(placeholder: "Username", text: $username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            RSCTextField(placeholder: "Password", text: $password, isSecure: true)
        }
    }

    private var quickLoginToggle: some View {
        Toggle(isOn: $saveForQuickLogin) {
            VStack(alignment: .leading, spacing: 2) {
                Text(biometricKind.toggleTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text("Store this server login securely on this device.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#7b7b7b"))
            }
        }
        .tint(Color(hex: "#c8a951"))
    }

    private var statusMessage: some View {
        Group {
            if !localMessage.isEmpty {
                Text(localMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            } else if !appState.loginError.isEmpty {
                Text(appState.loginError)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var loginButtons: some View {
        VStack(spacing: 12) {
            if biometricKind != .none, savedCredential != nil {
                Button(action: quickLogin) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: "#2b2b2b"))
                            .frame(height: 50)

                        HStack(spacing: 10) {
                            if isUnlocking {
                                ProgressView()
                                    .tint(Color(hex: "#c8a951"))
                            } else {
                                Image(systemName: biometricKind.symbolName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(hex: "#c8a951"))
                                Text(biometricKind.buttonTitle)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .disabled(isUnlocking || isLoggingIn)
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
            .disabled(username.isEmpty || password.isEmpty || isLoggingIn || isUnlocking)
        }
    }

    private func login() {
        localMessage = ""
        isLoggingIn = true
        persistBeforeLogin(username: username, password: password)
        routeToGame(username: username, password: password)
        isLoggingIn = false
    }

    private func quickLogin() {
        guard let savedCredential else { return }

        localMessage = ""
        appState.loginError = ""
        isUnlocking = true

        Task {
            do {
                try await DeviceBiometrics.authenticate(reason: "Quick login to \(server.name)")
                await MainActor.run {
                    username = savedCredential.username
                    password = savedCredential.password
                    persistBeforeLogin(username: savedCredential.username, password: savedCredential.password)
                    routeToGame(username: savedCredential.username, password: savedCredential.password)
                    isUnlocking = false
                }
            } catch {
                await MainActor.run {
                    localMessage = error.localizedDescription.isEmpty ? "Quick login was cancelled." : error.localizedDescription
                    isUnlocking = false
                }
            }
        }
    }

    private func persistBeforeLogin(username: String, password: String) {
        appState.loginError = ""
        appState.updateLastUsername(username, for: server)

        if biometricKind != .none && saveForQuickLogin {
            guard BiometricLoginStore.saveCredential(username: username, password: password, for: server) else {
                localMessage = "Couldn't save this login securely on the device."
                return
            }
            savedCredential = SavedLoginCredential(username: username, password: password)
        } else if savedCredential != nil {
            BiometricLoginStore.deleteCredential(for: server)
            savedCredential = nil
        }
    }

    private func routeToGame(username: String, password: String) {
        if server.gameType == .rscWeb {
            appState.currentView = .webGame(server, username, password)
        } else {
            appState.currentView = .game(server, username, password)
        }
    }

    private func clearSavedCredential() {
        BiometricLoginStore.deleteCredential(for: server)
        savedCredential = nil
        saveForQuickLogin = false
        password = ""
        localMessage = ""
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

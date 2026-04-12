import SwiftUI

struct RegisterView: View {
    let server: ServerProfile
    @EnvironmentObject var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var statusMessage = ""
    @State private var isRegistering = false

    var body: some View {
        ZStack {
            Color(hex: "#1a1a1a").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { appState.currentView = .login(server) }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color(hex: "#c8a951"))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 44, height: 44)
                    Spacer()
                    Text("Create Account")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .background(Color(hex: "#222222"))

                Spacer()

                VStack(spacing: 16) {
                    RSCTextField(placeholder: "Username", text: $username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    RSCTextField(placeholder: "Password", text: $password, isSecure: true)
                    RSCTextField(placeholder: "Email (optional)", text: $email)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 14))
                            .foregroundColor(statusMessage.contains("success") ? .green : .red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: register) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: "#c8a951"))
                                .frame(height: 50)
                            if isRegistering {
                                ProgressView().tint(.black)
                            } else {
                                Text("Register")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isRegistering)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func register() {
        isRegistering = true
        // Registration handled by RSCGameEngine
        isRegistering = false
    }
}

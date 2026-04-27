// Sleep screen — shown while the player rests in a bed. Server sends a
// distorted captcha word (opcode 117) which the player must type to wake.
// On the Java client, `clientPort.getSpriteFromByteArray` decodes the bytes
// — that's a thin wrapper around `BitmapFactory.decodeByteArray` on Android,
// so the wire format is a standard image (JPEG/PNG). We feed the bytes
// straight into `UIImage(data:)`.

import SwiftUI
import UIKit

struct SleepPanel: View {
    @ObservedObject var worldState: RSCWorldState
    @ObservedObject var engine: RSCGameEngine
    @State private var typedWord: String = ""
    @State private var shake: CGFloat = 0

    private var captchaImage: UIImage? {
        guard let data = worldState.sleepCaptchaBytes, !data.isEmpty else { return nil }
        return UIImage(data: data)
    }

    private var isError: Bool {
        worldState.sleepStatusText.lowercased().contains("incorrect")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("You are sleeping…")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "#c8a951"))

                Text("Type the word below to wake up.")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)

                if let image = captchaImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 80)
                        .background(Color.white)
                        .border(Color(hex: "#c8a951"), width: 1)
                        .offset(x: shake)
                } else {
                    // Captcha hasn't been received (or decode failed). Show a
                    // placeholder so the user still has a way to submit.
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 320, height: 80)
                        .overlay(Text("(captcha unavailable)").foregroundColor(.gray))
                }

                TextField("Sleep word", text: $typedWord)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .frame(maxWidth: 240)

                if !worldState.sleepStatusText.isEmpty {
                    Text(worldState.sleepStatusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isError ? .red : Color(hex: "#c8a951"))
                }

                HStack {
                    Text("Fatigue:")
                        .foregroundColor(.gray)
                    // Server sends fatigue scaled to 0..7500.
                    let pct = Double(worldState.sleepFatigue) / 7500.0 * 100.0
                    Text(String(format: "%.0f%%", pct)).foregroundColor(.white)
                }
                .font(.system(size: 12, design: .monospaced))

                HStack(spacing: 12) {
                    Button("Submit") {
                        let word = typedWord.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !word.isEmpty else { return }
                        engine.sendSleepWord(word)
                        // Server replies with WAKE_UP (84) on success or
                        // INCORRECT_SLEEPWORD (194) on failure. The latter is
                        // already handled to set sleepStatusText — also shake
                        // the captcha to give visual feedback.
                        typedWord = ""
                        withAnimation(.default) {
                            shake = -8
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.default) { shake = 8 }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            withAnimation(.default) { shake = 0 }
                        }
                    }
                    .buttonStyle(SleepActionButtonStyle(primary: true))

                    Button("Wake up") {
                        // Local cancel. The server keeps the player asleep
                        // until a correct word is received, but this lets the
                        // player dismiss the dialog if they want.
                        worldState.isSleeping = false
                    }
                    .buttonStyle(SleepActionButtonStyle(primary: false))
                }
            }
            .padding(20)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#1a1a1a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "#c8a951"), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(20)
        }
    }
}

private struct SleepActionButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(primary ? Color(hex: "#c8a951") : Color(hex: "#3a3a3a"))
            .foregroundColor(primary ? .black : .white)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

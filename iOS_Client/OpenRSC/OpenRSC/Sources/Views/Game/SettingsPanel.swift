import SwiftUI

// User-side options panel. Mirrors the Java client's drawUiTabOptions
// (mudclient.java, around line 9700). Persists settings to UserDefaults so
// they survive app relaunch. Block-chat options would normally send opcode
// 64 (CHAT_BLOCK_FLAGS) as a single byte bitmask; we wire that hookup but
// guard it behind the engine method so the panel is also useful offline.
struct SettingsPanel: View {
    @ObservedObject var worldState: RSCWorldState
    @ObservedObject var engine: RSCGameEngine

    // Chat blocks (server-side toggles)
    @AppStorage("rsc.block.public") private var blockPublic: Bool = false
    @AppStorage("rsc.block.private") private var blockPrivate: Bool = false
    @AppStorage("rsc.block.trade") private var blockTrade: Bool = false
    @AppStorage("rsc.block.duel") private var blockDuel: Bool = false

    // Client-side cosmetics
    @AppStorage("rsc.brightness") private var brightness: Double = 1.0
    @AppStorage("rsc.swapMouseButtons") private var swapMouseButtons: Bool = false
    @AppStorage("rsc.soundEnabled") private var soundEnabled: Bool = true
    @AppStorage("rsc.orientation") private var orientationRaw: String = "auto"

    private let orientationOptions: [(String, String)] = [
        ("auto", "Auto"),
        ("left", "Landscape Left"),
        ("right", "Landscape Right"),
        ("portrait", "Portrait"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                section(title: "Chat blocks") {
                    settingToggle("Block public chat", isOn: $blockPublic)
                        .onChange(of: blockPublic) { _ in sendChatBlocks() }
                    settingToggle("Block private chat", isOn: $blockPrivate)
                        .onChange(of: blockPrivate) { _ in sendChatBlocks() }
                    settingToggle("Block trade requests", isOn: $blockTrade)
                        .onChange(of: blockTrade) { _ in sendChatBlocks() }
                    settingToggle("Block duel requests", isOn: $blockDuel)
                        .onChange(of: blockDuel) { _ in sendChatBlocks() }
                }

                section(title: "Display") {
                    HStack {
                        Text("Brightness")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Slider(value: $brightness, in: 0.4...1.6)
                        Text(String(format: "%.1f", brightness))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#c8a951"))
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)

                    HStack {
                        Text("Orientation")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $orientationRaw) {
                            ForEach(orientationOptions, id: \.0) { opt in
                                Text(opt.1).tag(opt.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .accentColor(Color(hex: "#c8a951"))
                    }
                    .padding(.horizontal, 8)
                }

                section(title: "Controls") {
                    settingToggle("Swap mouse/tap buttons", isOn: $swapMouseButtons)
                    settingToggle("Sound effects", isOn: $soundEnabled)
                }

                section(title: "Account") {
                    Button(action: { engine.logout() }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log out")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.5), lineWidth: 1))
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "#c8a951"))
                .padding(.horizontal, 8)
            content()
        }
    }

    @ViewBuilder
    private func settingToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#c8a951")))
        .padding(.horizontal, 8)
    }

    /// Send the 4-byte privacy settings packet (opcode 64). Mirrors
    /// mudclient.java createPacket64 (line 2316): four bytes, one per
    /// chat category. The Java client cycles each value through 0..2;
    /// we simplify to a binary "off (0) or block-everyone (1)" toggle.
    private func sendChatBlocks() {
        engine.setChatBlockFlags(
            chat: blockPublic ? 1 : 0,
            priv: blockPrivate ? 1 : 0,
            trade: blockTrade ? 1 : 0,
            duel: blockDuel ? 1 : 0
        )
    }
}

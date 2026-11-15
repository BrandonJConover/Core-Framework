#if canImport(UIKit)
import SwiftUI
import UIKit
import RSCEngine

/// Full-screen native RSC client: the embedded rsc-c engine's software
/// framebuffer shown on a GPU-composited layer, with touch, keyboard and
/// sound bridged in. rsc-c draws its own login screen, HUD and menus, sized
/// for touch (tap = left click, hold = context menu, drag = rotate camera,
/// pinch = zoom).
struct NativeRSCScreen: View {
    let server: ServerProfile
    @EnvironmentObject var appState: AppState
    @State private var errorText: String?
    @State private var needsRSAKey = false

    var body: some View {
        // Back button sits top-right: rsc-c draws its chat tabs top-left.
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let errorText {
                VStack(spacing: 16) {
                    Text(errorText)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Back") { appState.currentView = .serverBrowser(server.gameType) }
                        .foregroundColor(Color(hex: "#c8a951"))
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !needsRSAKey {
                NativeRSCViewRepresentable(server: server) { error in
                    if case RSCEngineHost.StartError.missingRSAKey = error {
                        needsRSAKey = true
                    } else {
                        errorText = error.localizedDescription
                    }
                }
            }

            Button(action: { appState.currentView = .serverBrowser(server.gameType) }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(hex: "#c8a951"), Color.black.opacity(0.55))
            }
            .padding(.top, 4)
            .padding(.trailing, 4)
            .opacity(0.8)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $needsRSAKey) {
            RSAKeyEntrySheet(server: server) { updated in
                needsRSAKey = false
                if let updated {
                    appState.updateServer(updated)
                    appState.currentView = .nativeGame(updated)
                } else {
                    appState.currentView = .serverBrowser(server.gameType)
                }
            }
        }
    }
}

/// Asks for the server's RSA modulus (printed by the Java server at startup
/// as "RSA modulus: <number>", or the hex value from its client config).
struct RSAKeyEntrySheet: View {
    let server: ServerProfile
    let onDone: (ServerProfile?) -> Void
    @State private var modulus = ""
    @State private var exponent = "10001"

    private var isValid: Bool { RSAKeyText.hex(from: modulus) != nil && RSAKeyText.hex(from: exponent) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("RSA modulus", text: $modulus, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("RSA exponent", text: $exponent)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Paste the \"RSA modulus\" number the game server prints when it starts, or the hex modulus from your web client's world list. It must match the server's client.pem.")
                }
            }
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = server
                        updated.rsaModulus = modulus.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.rsaExponent = exponent.trimmingCharacters(in: .whitespacesAndNewlines)
                        onDone(updated)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            modulus = server.rsaModulus
            exponent = server.rsaExponent.isEmpty ? "10001" : server.rsaExponent
        }
    }
}

private struct NativeRSCViewRepresentable: UIViewRepresentable {
    let server: ServerProfile
    let onError: (Error) -> Void

    func makeUIView(context: Context) -> NativeRSCView {
        let view = NativeRSCView()
        view.server = server
        view.onError = onError
        return view
    }

    func updateUIView(_ uiView: NativeRSCView, context: Context) {}

    static func dismantleUIView(_ uiView: NativeRSCView, coordinator: ()) {
        uiView.stopDisplayLink()
    }
}

/// Displays engine frames and forwards input. Conforms to UIKeyInput so the
/// system keyboard can type into rsc-c's text fields.
final class NativeRSCView: UIView, UIKeyInput {
    var server: ServerProfile?
    var onError: ((Error) -> Void)?

    private var displayLink: CADisplayLink?
    private var frameBuffer: [UInt32] = []
    private var lastFrame: UInt64 = 0
    private var lastSentSize: CGSize = .zero
    private var startAttempted = false
    private var keyboardShown = false
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        isExclusiveTouch = true
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .linear
        layer.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
            if isFirstResponder { resignFirstResponder() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        if !startAttempted {
            startAttempted = true
            startEngine(size: size)
            lastSentSize = size
        } else if size != lastSentSize {
            lastSentSize = size
            rsc_host_resize(Int32(size.width.rounded()), Int32(size.height.rounded()))
        }
    }

    private func startEngine(size: CGSize) {
        guard let server else { return }
        do {
            try RSCEngineHost.shared.start(server: server, windowSize: size)
            // Returning to an engine that is already running: match the
            // current view size.
            rsc_host_resize(Int32(size.width.rounded()), Int32(size.height.rounded()))
        } catch {
            onError?(error)
        }
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: Frames

    @objc private func step() {
        syncKeyboard()

        var width: Int32 = 0
        var height: Int32 = 0
        let available = rsc_host_copy_frame(nil, 0, &width, &height)
        guard available != lastFrame, width > 0, height > 0 else { return }

        let pixelCount = Int(width) * Int(height)
        if frameBuffer.count < pixelCount {
            frameBuffer = [UInt32](repeating: 0, count: pixelCount)
        }

        let frame = frameBuffer.withUnsafeMutableBufferPointer { ptr -> UInt64 in
            rsc_host_copy_frame(ptr.baseAddress, Int32(ptr.count), &width, &height)
        }
        guard frame != 0, width > 0, height > 0 else { return }
        lastFrame = frame

        let w = Int(width)
        let h = Int(height)
        let byteCount = w * h * 4
        // XRGB8888 little-endian == BGRX in memory.
        let data = frameBuffer.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: byteCount) }
        guard let provider = CGDataProvider(data: data as CFData) else { return }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(
            width: w, height: h,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }

    // MARK: Touch

    private func send(_ touches: Set<UITouch>, phase: Int32) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        for touch in touches {
            let p = touch.location(in: self)
            let x = Float(min(max(p.x / size.width, 0), 1))
            let y = Float(min(max(p.y / size.height, 0), 1))
            let id = Int64(UInt(bitPattern: ObjectIdentifier(touch).hashValue) & 0x7fff_ffff_ffff_ffff)
            rsc_host_touch(phase, id, x, y)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !keyboardShown {
            // rsc-c (like Android) treats the first tap after a text field
            // asked for the keyboard as "dismiss keyboard" and drops it. When
            // the keyboard isn't on screen, clear that state so taps land.
            rsc_host_keyboard_dismissed()
        }
        send(touches, phase: Int32(RSC_TOUCH_BEGAN))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches, phase: Int32(RSC_TOUCH_MOVED))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches, phase: Int32(RSC_TOUCH_ENDED))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        send(touches, phase: Int32(RSC_TOUCH_ENDED))
    }

    // MARK: Keyboard

    private func syncKeyboard() {
        let wants = rsc_host_wants_keyboard() != 0
        if wants && !isFirstResponder {
            keyboardShown = becomeFirstResponder()
        } else if !wants && isFirstResponder {
            resignFirstResponder()
            keyboardShown = false
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if keyboardShown {
            keyboardShown = false
            rsc_host_keyboard_dismissed()
        }
        return result
    }

    var hasText: Bool { true }

    func insertText(_ text: String) {
        if text == "\n" {
            pressKey(Int32(RSC_KEY_ENTER))
            return
        }
        rsc_host_text(text)
    }

    func deleteBackward() {
        pressKey(Int32(RSC_KEY_BACKSPACE))
    }

    private func pressKey(_ key: Int32) {
        rsc_host_key(key, 1)
        rsc_host_key(key, 0)
    }

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .asciiCapable
    var returnKeyType: UIReturnKeyType = .done

    // Hardware keyboard (iPad / simulator): arrows rotate the camera, etc.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if let key = Self.specialKey(for: press) {
                rsc_host_key(key, 1)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if let key = Self.specialKey(for: press) {
                rsc_host_key(key, 0)
                handled = true
            }
        }
        if !handled { super.pressesEnded(presses, with: event) }
    }

    private static func specialKey(for press: UIPress) -> Int32? {
        guard let code = press.key?.keyCode else { return nil }
        switch code {
        case .keyboardLeftArrow: return Int32(RSC_KEY_LEFT)
        case .keyboardRightArrow: return Int32(RSC_KEY_RIGHT)
        case .keyboardUpArrow: return Int32(RSC_KEY_UP)
        case .keyboardDownArrow: return Int32(RSC_KEY_DOWN)
        case .keyboardPageUp: return Int32(RSC_KEY_PAGE_UP)
        case .keyboardPageDown: return Int32(RSC_KEY_PAGE_DOWN)
        case .keyboardEscape: return Int32(RSC_KEY_ESCAPE)
        case .keyboardF1: return Int32(RSC_KEY_F1)
        default: return nil
        }
    }
}
#endif

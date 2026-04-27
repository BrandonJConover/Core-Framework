import SwiftUI

/// Character creation / appearance customization panel.
///
/// Mirrors `mudclient.drawAppearancePanel*` (around line 2638) and the
/// confirm-handler at line 11532 of `Client_Base/src/orsc/mudclient.java`,
/// which sends opcode 235 with the 10-byte payload:
///
///     [0] appearanceHeadGender   (0=male, 1=female)
///     [1] appearanceHeadType     (head animation 0..N — Java uses
///                                 EntityHandler.animationCount()-1)
///     [2] appearanceBodyGender   (0=male, 1=female)
///     [3] character2Colour       (Java's "skin tone" sub-pick)
///     [4] appearanceHairColour   (0..9, indexes into playerHairColors)
///     [5] characterTopColour     (0..14, indexes into playerClothingColors)
///     [6] characterBottomColour  (0..14, indexes into playerClothingColors)
///     [7] appearanceSkinColour   (0..4, indexes into playerSkinColors)
///     [8] playerMode1            (game-mode dropdown index — default 0)
///     [9] playerMode2            (game-mode dropdown index — default 0)
///
/// `RSCGameEngine.sendAppearance(...)` already wraps the byte order; this view
/// just collects the values.
///
/// Java palettes (mudclient.java lines 142–168):
///   playerClothingColors: 15 entries
///   playerHairColors:     10 entries
///   playerSkinColors:      5 player-selectable entries (the rest are NPC-only)
struct AppearancePanel: View {
    @ObservedObject var worldState: RSCWorldState
    let engine: RSCGameEngine

    // MARK: - Selection state

    @State private var gender = 0           // 0=male, 1=female
    @State private var headType = 1         // Java starts head 1..14 cycle
    @State private var bodyType = 4         // Java body anims 4..7
    @State private var hairIndex = 2        // Java default: appearanceHairColour = 2
    @State private var topIndex = 0
    @State private var bottomIndex = 0
    @State private var skinIndex = 0

    // MARK: - Java palettes (RGB, hex)

    /// `mudclient.playerClothingColors` line 142.
    private let clothingColors: [Color] = [
        Color(rgbHex: 0xFF0000), Color(rgbHex: 0xFF8000), Color(rgbHex: 0xFFE000),
        Color(rgbHex: 0xA0E000), Color(rgbHex: 0x00E000), Color(rgbHex: 0x008000),
        Color(rgbHex: 0xA080A0), Color(rgbHex: 0xB0FFFF), Color(rgbHex: 0x80FFFF),
        Color(rgbHex: 0x0030F0), Color(rgbHex: 0xE000A0), Color(rgbHex: 0x303030),
        Color(rgbHex: 0x603040), Color(rgbHex: 0x804060), Color(rgbHex: 0xFFFFFF),
    ]

    /// `mudclient.playerHairColors` line 144 (10 entries).
    private let hairColors: [Color] = [
        Color(rgbHex: 0xFFC030), Color(rgbHex: 0xFF9F00), Color(rgbHex: 0x804030),
        Color(rgbHex: 0x603020), Color(rgbHex: 0x303030), Color(rgbHex: 0xFF8060),
        Color(rgbHex: 0xFF6000), Color(rgbHex: 0xFFFFFF), Color(rgbHex: 0x00FF00),
        Color(rgbHex: 0x00FFFF),
    ]
    private let hairNames = ["Blonde", "Orange", "Light Brown", "Dark Brown",
                             "Black", "Red", "Bright Red", "White", "Green", "Cyan"]

    /// First 5 entries of `mudclient.playerSkinColors` (player-selectable).
    private let skinColors: [Color] = [
        Color(rgbHex: 0xECDED0), Color(rgbHex: 0xCCB366), Color(rgbHex: 0xB38C40),
        Color(rgbHex: 0x997326), Color(rgbHex: 0x906020),
    ]
    private let skinNames = ["Fair", "Tan", "Light Bronze", "Bronze", "Dark"]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Design Your Character")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(rgbHex: 0xC8A951))
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Gender (Male / Female)
                    HStack {
                        Text("Gender")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Picker("", selection: $gender) {
                            Text("Male").tag(0)
                            Text("Female").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .onChange(of: gender) { _ in
                            // Java keeps head/body anims in valid ranges for the
                            // selected gender — for now we just snap to gender's
                            // first valid head/body so the values stay plausible.
                            headType = (gender == 0) ? 1 : 8
                        }
                    }

                    // Head style stepper (Java cycles through head animations
                    // 1..14 filtered by gender — we expose the raw index).
                    appearanceStepper(label: "Head Style",
                                      value: $headType,
                                      range: 1...14)

                    // Body style stepper (Java body anims 4..7).
                    appearanceStepper(label: "Body Style",
                                      value: $bodyType,
                                      range: 4...7)

                    Divider().background(Color.white.opacity(0.2))

                    swatchPicker(title: "Hair",
                                 colors: hairColors,
                                 names: hairNames,
                                 selection: $hairIndex)

                    swatchPicker(title: "Skin",
                                 colors: skinColors,
                                 names: skinNames,
                                 selection: $skinIndex)

                    swatchPicker(title: "Top",
                                 colors: clothingColors,
                                 names: nil,
                                 selection: $topIndex)

                    swatchPicker(title: "Trousers",
                                 colors: clothingColors,
                                 names: nil,
                                 selection: $bottomIndex)

                    Spacer().frame(height: 4)

                    Button(action: confirm) {
                        Text("Confirm")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(rgbHex: 0x1A1A1A))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(rgbHex: 0xC8A951))
                            .cornerRadius(10)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: 360)
            .background(Color(rgbHex: 0x1A1A1A).opacity(0.98))
            .cornerRadius(16)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Confirm

    private func confirm() {
        // Java sends head and body genders separately; Authentic UI keeps them
        // synced so we mirror that here. `skinTone` (`character2Colour`) is the
        // Java field at index [3] — we reuse the picked skin slot to keep the
        // values consistent with the chosen palette.
        engine.sendAppearance(
            headGender: gender,
            headType: headType,
            bodyGender: gender,
            skinTone: skinIndex,
            hairColour: hairIndex,
            topColour: topIndex,
            bottomColour: bottomIndex,
            skinColour: skinIndex
        )
        // engine.sendAppearance already flips showAppearanceChange to false.
    }

    // MARK: - Subviews

    @ViewBuilder
    private func swatchPicker(title: String,
                              colors: [Color],
                              names: [String]?,
                              selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if let names = names, selection.wrappedValue < names.count {
                    Text(names[selection.wrappedValue])
                        .font(.system(size: 12))
                        .foregroundColor(Color(rgbHex: 0xC8A951))
                } else {
                    Text("\(selection.wrappedValue + 1) / \(colors.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(rgbHex: 0xC8A951))
                }
            }
            // Wrapped grid of swatches — taps select.
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6),
                                count: 8)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(colors.indices, id: \.self) { idx in
                    let isSelected = (idx == selection.wrappedValue)
                    Button(action: { selection.wrappedValue = idx }) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colors[idx])
                            .frame(height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected
                                            ? Color(rgbHex: 0xC8A951)
                                            : Color.white.opacity(0.15),
                                            lineWidth: isSelected ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func appearanceStepper(label: String,
                                   value: Binding<Int>,
                                   range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button(action: {
                let lo = range.lowerBound
                let hi = range.upperBound
                value.wrappedValue = (value.wrappedValue <= lo) ? hi : value.wrappedValue - 1
            }) {
                Image(systemName: "chevron.left.circle.fill")
                    .foregroundColor(Color(rgbHex: 0xC8A951))
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            Text("\(value.wrappedValue)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 32)
            Button(action: {
                let lo = range.lowerBound
                let hi = range.upperBound
                value.wrappedValue = (value.wrappedValue >= hi) ? lo : value.wrappedValue + 1
            }) {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundColor(Color(rgbHex: 0xC8A951))
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Color RGB hex helper

/// Local helper so this file compiles independently of GameSelectorView's
/// `Color(hex:)` extension. Accepts a 24-bit RGB int (0xRRGGBB).
private extension Color {
    init(rgbHex: UInt32) {
        let r = Double((rgbHex >> 16) & 0xFF) / 255.0
        let g = Double((rgbHex >> 8) & 0xFF) / 255.0
        let b = Double(rgbHex & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

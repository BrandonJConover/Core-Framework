// One-shot warning that fires the first time the local player walks within
// ~10 tiles of the wilderness ditch. Mirrors Java mudclient.java's
// drawDialogWildWarn (line 4656+) — same six lines of body text plus a
// "Click here to close window" affordance. We additionally allow tapping
// the dimmed backdrop to dismiss, since the game runs full-screen on iPhone
// and the centred button can be uncomfortable to reach one-handed.

import SwiftUI

struct WildernessWarningPanel: View {
    @ObservedObject var worldState: RSCWorldState

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { worldState.wildernessWarningOpen = false }

            VStack(spacing: 12) {
                Text("Warning! Proceed with caution")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("If you go much further north you will enter the wilderness.")
                    Text("This is a very dangerous area where other players can attack you!")
                    Text("The further north you go the more dangerous it becomes,")
                    Text("but the more treasure you will find.")
                    Text("")
                    Text("In the wilderness, an indicator at the bottom-right of the screen")
                    Text("will show the current level of danger.")
                }
                .font(.system(size: 13))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { worldState.wildernessWarningOpen = false }) {
                    Text("Click here to close window")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(hex: "#c8a951"))
                        .cornerRadius(6)
                }
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#1a1a1a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.7), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(20)
        }
    }
}

import SwiftUI
import MetalKit

/// Main game view that renders the game world.
/// Equivalent to Android's RSCBitmapSurfaceView.
struct GameView: View {
    @EnvironmentObject private var gameState: GameState
    @StateObject private var gameClient: GameClient

    @State private var showingInventory = false
    @State private var showingSkills = false
    @State private var showingChat = false

    init() {
        // Initialize with a temporary network client
        // In real usage, this would come from GameState
        _gameClient = StateObject(wrappedValue: GameClient(networkClient: NetworkClient()))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Game renderer
                GameRendererView(gameClient: gameClient)
                    .ignoresSafeArea()

                // UI overlay
                VStack {
                    // Top bar
                    TopBar(gameClient: gameClient)

                    Spacer()

                    // Bottom UI
                    HStack(alignment: .bottom, spacing: 0) {
                        // Chat area
                        ChatView(messages: gameClient.chatMessages)
                            .frame(maxWidth: .infinity, maxHeight: 130)

                        // Tab buttons
                        TabButtonsView(
                            showingInventory: $showingInventory,
                            showingSkills: $showingSkills
                        )
                    }
                }
                .padding(.horizontal, 4)

                // Side panels
                if showingInventory {
                    InventoryView(items: gameClient.inventory)
                        .frame(width: 200)
                        .transition(.move(edge: .trailing))
                        .position(x: geometry.size.width - 100, y: geometry.size.height / 2)
                }

                if showingSkills {
                    SkillsView(skills: gameClient.skills)
                        .frame(width: 200)
                        .transition(.move(edge: .trailing))
                        .position(x: geometry.size.width - 100, y: geometry.size.height / 2)
                }
            }
        }
        .gesture(createGameGestures())
    }

    private func createGameGestures() -> some Gesture {
        let tap = TapGesture()
            .onEnded { _ in
                // Handle tap
            }

        let longPress = LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                // Handle long press for context menu
            }

        let drag = DragGesture()
            .onChanged { value in
                gameClient.handlePan(
                    deltaX: Float(value.translation.width),
                    deltaY: Float(value.translation.height)
                )
            }

        let pinch = MagnificationGesture()
            .onChanged { scale in
                gameClient.handlePinch(scale: Float(scale))
            }

        return tap.simultaneously(with: longPress)
            .simultaneously(with: drag)
            .simultaneously(with: pinch)
    }
}

/// Top bar with player info and status.
struct TopBar: View {
    @ObservedObject var gameClient: GameClient

    var body: some View {
        HStack {
            // Compass
            Image(systemName: "safari")
                .foregroundColor(.white)
                .rotationEffect(.degrees(Double(gameClient.cameraRotation) * 1.4))

            Spacer()

            // Player info
            if let player = gameClient.localPlayer {
                Text(player.username)
                    .font(.caption)
                    .foregroundColor(.white)

                Text("Combat: \(player.combatLevel)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Battery/connectivity indicators
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .foregroundColor(.green)
                Image(systemName: "battery.75")
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.5))
    }
}

/// Chat display area.
struct ChatView: View {
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(messages.suffix(20)) { message in
                        HStack(spacing: 4) {
                            if let sender = message.sender {
                                Text("\(sender):")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.cyan)
                            }
                            Text(message.message)
                                .font(.system(size: 11))
                                .foregroundColor(messageColor(for: message.type))
                        }
                    }
                }
                .padding(4)
            }
        }
        .background(Color.black.opacity(0.6))
    }

    private func messageColor(for type: ChatMessage.MessageType) -> Color {
        switch type {
        case .player: return .white
        case .server: return .yellow
        case .quest: return .green
        case .trade: return .purple
        }
    }
}

/// Tab buttons for inventory, skills, etc.
struct TabButtonsView: View {
    @Binding var showingInventory: Bool
    @Binding var showingSkills: Bool

    var body: some View {
        VStack(spacing: 2) {
            TabButton(icon: "bag.fill", isActive: showingInventory) {
                showingInventory.toggle()
                showingSkills = false
            }

            TabButton(icon: "chart.bar.fill", isActive: showingSkills) {
                showingSkills.toggle()
                showingInventory = false
            }

            TabButton(icon: "map.fill", isActive: false) {
                // Toggle map
            }

            TabButton(icon: "gearshape.fill", isActive: false) {
                // Toggle settings
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.5))
        .cornerRadius(4)
    }
}

struct TabButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isActive ? .yellow : .white)
                .frame(width: 32, height: 32)
        }
    }
}

/// Inventory panel.
struct InventoryView: View {
    let items: [InventoryItem]

    let columns = Array(repeating: GridItem(.fixed(32), spacing: 2), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Inventory")
                .font(.caption.bold())
                .foregroundColor(.white)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<30) { index in
                    if index < items.count {
                        InventorySlot(item: items[index])
                    } else {
                        EmptySlot()
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}

struct InventorySlot: View {
    let item: InventoryItem

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 32, height: 32)

            // Item icon placeholder
            Text("\(item.itemId)")
                .font(.system(size: 8))
                .foregroundColor(.white)

            if item.amount > 1 {
                Text("\(item.amount)")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(2)
            }
        }
        .cornerRadius(2)
    }
}

struct EmptySlot: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 32, height: 32)
            .cornerRadius(2)
    }
}

/// Skills panel.
struct SkillsView: View {
    let skills: [Skill]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skills")
                .font(.caption.bold())
                .foregroundColor(.white)

            ForEach(skills) { skill in
                HStack {
                    Text(skill.name)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .frame(width: 70, alignment: .leading)

                    Text("\(skill.currentLevel)/\(skill.maxLevel)")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)

                    Spacer()
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}

#Preview {
    GameView()
        .environmentObject(GameState())
}

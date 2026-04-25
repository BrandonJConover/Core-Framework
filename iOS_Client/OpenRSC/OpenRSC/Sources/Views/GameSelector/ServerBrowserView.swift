import SwiftUI

struct ServerBrowserView: View {
    let gameType: GameType
    @EnvironmentObject var appState: AppState
    @State private var showAddServer = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newPort = "43594"

    var filteredServers: [ServerProfile] {
        appState.servers.filter { $0.gameType == gameType }
    }

    var body: some View {
        ZStack {
            Color(hex: "#1a1a1a").ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { appState.currentView = .selector }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color(hex: "#c8a951"))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 44, height: 44)

                    Spacer()
                    Text(gameType.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()

                    Button(action: { showAddServer = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(Color(hex: "#c8a951"))
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)
                .background(Color(hex: "#222222"))

                if filteredServers.isEmpty {
                    Spacer()
                    Text("No servers. Tap + to add one.")
                        .foregroundColor(Color(hex: "#666666"))
                    Spacer()
                } else {
                    List {
                        ForEach(filteredServers) { server in
                            ServerRow(server: server)
                                .listRowBackground(Color(hex: "#2a2a2a"))
                                .onTapGesture {
                                    appState.currentView = .login(server)
                                }
                        }
                        .onDelete { offsets in
                            let globalOffsets = offsets.map { filteredServers[$0].id }
                            appState.servers.removeAll { globalOffsets.contains($0.id) }
                            appState.saveServers()
                        }
                    }
                    .listStyle(.plain)
                    .background(Color(hex: "#1a1a1a"))
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showAddServer) {
            AddServerSheet(gameType: gameType, isPresented: $showAddServer)
                .environmentObject(appState)
        }
    }
}

private struct ServerRow: View {
    let server: ServerProfile
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium))
                Text("\(server.host):\(server.port)")
                    .foregroundColor(Color(hex: "#888888"))
                    .font(.system(size: 13))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(Color(hex: "#c8a951"))
                .font(.system(size: 14))
        }
        .padding(.vertical, 8)
    }
}

private struct AddServerSheet: View {
    let gameType: GameType
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState
    @State private var name = ""
    @State private var host = ""
    @State private var port = "43594"
    @State private var wsPort = "43494"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#1a1a1a").ignoresSafeArea()
                Form {
                    Section("Server Details") {
                        TextField("Name", text: $name)
                        TextField("Host", text: $host)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                        TextField("Port", text: $port)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        TextField("WebSocket Port", text: $wsPort)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(Color(hex: "#c8a951"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.isEmpty, !host.isEmpty else { return }
                        let profile = ServerProfile(
                            name: name,
                            host: host,
                            port: Int(port) ?? 43594,
                            wsPort: Int(wsPort) ?? 43494,
                            lastUsername: "",
                            gameType: gameType
                        )
                        appState.addServer(profile)
                        isPresented = false
                    }
                    .foregroundColor(Color(hex: "#c8a951"))
                    .disabled(name.isEmpty || host.isEmpty)
                }
            }
        }
    }
}

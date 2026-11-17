import SwiftUI
import Scape530

/// The "Plugins" list of the settings sheet: every plugin with a toggle, and a row into its settings.
struct PluginsView: View {
	let manager: PluginManager

	var body: some View {
		List {
			Section {
				ForEach(manager.plugins, id: \.id) { plugin in
					PluginRow(manager: manager, plugin: plugin)
				}
			} footer: {
				Text("Plugins draw over the game and adjust menus. Changes apply at once.")
			}
			Section("Panels") {
				NavigationLink("XP tracker") { XpTrackerView(manager: manager) }
				NavigationLink("Quests") { QuestsView(manager: manager) }
			}
		}
		.navigationTitle("Plugins")
	}
}

private struct PluginRow: View {
	let manager: PluginManager
	let plugin: ClientPlugin
	@State private var isOn: Bool

	init(manager: PluginManager, plugin: ClientPlugin) {
		self.manager = manager
		self.plugin = plugin
		_isOn = State(initialValue: plugin.enabled)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Toggle(isOn: Binding(get: { isOn }, set: { on in
				isOn = on
				manager.setEnabled(on, id: plugin.id)
				// Idle Notifier needs the system's permission before it can post while the app is in the background.
				if on && plugin.id == "idleNotifier" { PluginNotifier.shared.requestAuthorization() }
			})) {
				Text(plugin.name)
			}
			Text(plugin.summary)
				.font(.footnote)
				.foregroundColor(.secondary)
			if !plugin.config.fields.isEmpty {
				NavigationLink("Settings") { PluginConfigView(plugin: plugin) }
					.font(.footnote)
			}
		}
	}
}

/// Renders a plugin's `PluginConfig.fields` generically: toggles, steppers or number fields, text, one-per-line lists
/// and pickers.
struct PluginConfigView: View {
	let plugin: ClientPlugin

	var body: some View {
		Form {
			ForEach(plugin.config.fields, id: \.key) { field in
				Section {
					PluginFieldView(config: plugin.config, field: field)
				} footer: {
					if !field.help.isEmpty { Text(field.help) }
				}
			}
			Section {
				Button("Reset to defaults", role: .destructive) { plugin.config.reset() }
			}
		}
		.navigationTitle(plugin.name)
	}
}

private struct PluginFieldView: View {
	let config: PluginConfig
	let field: PluginField
	@State private var flag = false
	@State private var number = 0
	@State private var text = ""
	@State private var loaded = false

	var body: some View {
		Group {
			switch field.kind {
			case .toggle:
				Toggle(field.title, isOn: $flag)
					.onChange(of: flag) { config.set(field.key, .bool($0)) }
			case let .number(lo, hi):
				if hi - lo <= 100 {
					Stepper(value: $number, in: lo...hi) { Text("\(field.title): \(number)") }
						.onChange(of: number) { config.set(field.key, .int($0)) }
				} else {
					HStack {
						Text(field.title)
						Spacer()
						TextField("0", value: $number, format: .number)
							.keyboardType(.numberPad)
							.multilineTextAlignment(.trailing)
							.frame(maxWidth: 120)
					}
					.onChange(of: number) { config.set(field.key, .int(min(max($0, lo), hi))) }
				}
			case .text:
				TextField(field.title, text: $text)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.onChange(of: text) { config.set(field.key, .string($0)) }
			case .list:
				VStack(alignment: .leading) {
					Text(field.title).font(.subheadline)
					TextEditor(text: $text)
						.font(.system(.body, design: .monospaced))
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
						.frame(minHeight: 110)
						.onChange(of: text) { new in
							config.set(field.key, .list(new.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
						}
				}
			case .choice(let options):
				Picker(field.title, selection: $text) {
					ForEach(options, id: \.self) { Text($0).tag($0) }
				}
				.onChange(of: text) { config.set(field.key, .string($0)) }
			}
		}
		.onAppear {
			// Load once; the onChange handlers above only run for edits after this.
			guard !loaded else { return }
			switch field.kind {
			case .toggle: flag = config.bool(field.key)
			case .number: number = config.int(field.key)
			case .list: text = config.list(field.key).joined(separator: "\n")
			case .text, .choice: text = config.string(field.key)
			}
			loaded = true
		}
	}
}

/// Session experience per skill, refreshed twice a second while open.
struct XpTrackerView: View {
	let manager: PluginManager
	@State private var rows: [XpTrackerPlugin.Row] = []
	private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

	private var tracker: XpTrackerPlugin? { manager.plugin(ofType: XpTrackerPlugin.self) }

	var body: some View {
		List {
			if tracker?.enabled != true {
				Text("Turn on the XP Tracker plugin to record experience.")
					.foregroundColor(.secondary)
			} else if rows.isEmpty {
				Text("Gain some experience and it shows up here.")
					.foregroundColor(.secondary)
			}
			ForEach(rows, id: \.skill) { row in
				VStack(alignment: .leading, spacing: 2) {
					HStack {
						Text(row.name).font(.headline)
						Spacer()
						Text("Level \(row.level)" + (row.levelsGained > 0 ? " (+\(row.levelsGained))" : ""))
							.font(.subheadline)
					}
					Text("\(row.gained.formatted()) xp gained   \(row.xpPerHour.formatted()) xp/hr")
						.font(.footnote)
					if let eta = row.secondsToNextLevel {
						Text("Next level in \(Self.duration(eta))")
							.font(.footnote)
							.foregroundColor(.secondary)
					}
				}
			}
			if !rows.isEmpty {
				Section {
					Button("Reset", role: .destructive) { tracker?.reset(); rows = [] }
				}
			}
		}
		.navigationTitle("XP tracker")
		.onAppear { rows = tracker?.snapshot() ?? [] }
		.onReceive(timer) { _ in rows = tracker?.snapshot() ?? [] }
	}

	static func duration(_ seconds: Int) -> String {
		let h = seconds / 3600, m = (seconds % 3600) / 60
		return h > 0 ? "\(h)h \(m)m" : "\(m)m \(seconds % 60)s"
	}
}

/// The Quest Helper's quest list: every guided quest with its status, tap one to follow it (or "Automatic" to follow
/// whichever quest changed last).
struct QuestsView: View {
	let manager: PluginManager
	@State private var rows: [QuestListEntry] = []
	@State private var automatic = true
	private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

	private var helper: QuestHelperPlugin? { manager.plugin(ofType: QuestHelperPlugin.self) }

	var body: some View {
		List {
			if helper?.enabled != true {
				Section {
					Button("Turn on the Quest Helper") { manager.setEnabled(true, id: "questHelper"); reload() }
				} footer: {
					Text("The helper shows the current step, highlights the target and outlines the items you need.")
				}
			}
			Section {
				Button {
					helper?.setActive(nil); reload()
				} label: {
					HStack {
						Text("Automatic")
						Spacer()
						if automatic { Image(systemName: "checkmark") }
					}
				}
			} footer: {
				Text("Automatic follows the quest whose progress changed last.")
			}
			Section("Quests") {
				ForEach(rows, id: \.id) { row in
					Button {
						helper?.setActive(row.id); reload()
					} label: {
						QuestRow(row: row)
					}
					.foregroundColor(.primary)
				}
			}
			if rows.contains(where: { $0.isActive && $0.status == .inProgress }) {
				Section {
					Button("I did this step") { helper?.skipCurrentStep(); reload() }
				} footer: {
					Text("Use it when the helper is stuck on a step you have already done.")
				}
			}
		}
		.navigationTitle("Quests")
		.onAppear { reload() }
		.onReceive(timer) { _ in reload() }
	}

	private func reload() {
		rows = helper?.entries ?? []
		automatic = helper?.isAutomatic ?? true
	}
}

private struct QuestRow: View {
	let row: QuestListEntry

	private var colour: Color {
		switch row.status {
		case .notStarted: return .red
		case .inProgress: return .yellow
		case .complete: return .green
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Circle().fill(colour).frame(width: 10, height: 10)
				Text(row.name).font(.headline)
				Spacer()
				if row.isActive { Image(systemName: "location.fill").foregroundColor(.accentColor) }
			}
			if let step = row.stepText, row.status == .inProgress {
				Text(step).font(.footnote)
			}
			if row.status == .notStarted, !row.requirements.isEmpty {
				Text(row.requirements.joined(separator: ", ")).font(.footnote).foregroundColor(.secondary)
			}
		}
	}
}

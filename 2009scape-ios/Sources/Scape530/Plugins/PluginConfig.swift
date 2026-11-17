import Foundation

/// One configuration value of a plugin. Everything a plugin stores is one of these, so the App can render
/// and edit any plugin's settings generically and the settings store can persist them as JSON.
public enum PluginValue: Codable, Equatable {
	case bool(Bool)
	case int(Int)
	case string(String)
	case list([String])

	private enum CodingKeys: String, CodingKey { case type, value }

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		switch try c.decode(String.self, forKey: .type) {
		case "bool": self = .bool(try c.decode(Bool.self, forKey: .value))
		case "int": self = .int(try c.decode(Int.self, forKey: .value))
		case "list": self = .list(try c.decode([String].self, forKey: .value))
		default: self = .string(try c.decode(String.self, forKey: .value))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case .bool(let v): try c.encode("bool", forKey: .type); try c.encode(v, forKey: .value)
		case .int(let v): try c.encode("int", forKey: .type); try c.encode(v, forKey: .value)
		case .string(let v): try c.encode("string", forKey: .type); try c.encode(v, forKey: .value)
		case .list(let v): try c.encode("list", forKey: .type); try c.encode(v, forKey: .value)
		}
	}
}

/// Describes one setting so a generic UI can render it.
public struct PluginField: Equatable {
	public enum Kind: Equatable {
		case toggle
		/// An integer with an allowed range (the UI shows a stepper).
		case number(min: Int, max: Int)
		case text
		/// One entry per line (names, "target=option" rules).
		case list
		/// One of a fixed set of strings.
		case choice([String])
	}

	public let key: String
	public let title: String
	public let help: String
	public let kind: Kind
	public let defaultValue: PluginValue

	public init(key: String, title: String, help: String = "", kind: Kind, defaultValue: PluginValue) {
		self.key = key
		self.title = title
		self.help = help
		self.kind = kind
		self.defaultValue = defaultValue
	}

	public static func toggle(_ key: String, _ title: String, _ value: Bool, help: String = "") -> PluginField {
		PluginField(key: key, title: title, help: help, kind: .toggle, defaultValue: .bool(value))
	}
	public static func number(_ key: String, _ title: String, _ value: Int, min: Int, max: Int, help: String = "") -> PluginField {
		PluginField(key: key, title: title, help: help, kind: .number(min: min, max: max), defaultValue: .int(value))
	}
	public static func text(_ key: String, _ title: String, _ value: String, help: String = "") -> PluginField {
		PluginField(key: key, title: title, help: help, kind: .text, defaultValue: .string(value))
	}
	public static func list(_ key: String, _ title: String, _ value: [String], help: String = "") -> PluginField {
		PluginField(key: key, title: title, help: help, kind: .list, defaultValue: .list(value))
	}
	public static func choice(_ key: String, _ title: String, _ options: [String], _ value: String, help: String = "") -> PluginField {
		PluginField(key: key, title: title, help: help, kind: .choice(options), defaultValue: .string(value))
	}
}

/// The settings of one plugin: typed reads with the field defaults as fallback, and a change callback the
/// manager uses to persist. Safe to read on the game thread while the App edits on the main thread.
public final class PluginConfig {
	public let fields: [PluginField]
	private var values: [String: PluginValue] = [:]
	private let lock = NSLock()
	/// Called (outside the lock) after any value changed.
	var onChange: (() -> Void)?

	public init(_ fields: [PluginField] = []) { self.fields = fields }

	public func value(_ key: String) -> PluginValue? {
		lock.lock(); defer { lock.unlock() }
		return values[key] ?? fields.first { $0.key == key }?.defaultValue
	}

	public func bool(_ key: String) -> Bool {
		if case .bool(let b)? = value(key) { return b }
		return false
	}

	public func int(_ key: String) -> Int {
		if case .int(let i)? = value(key) { return i }
		return 0
	}

	public func string(_ key: String) -> String {
		switch value(key) {
		case .string(let s)?: return s
		case .list(let l)?: return l.joined(separator: "\n")
		default: return ""
		}
	}

	public func list(_ key: String) -> [String] {
		switch value(key) {
		case .list(let l)?: return l
		case .string(let s)?: return s.split(separator: "\n").map(String.init)
		default: return []
		}
	}

	public func set(_ key: String, _ v: PluginValue) {
		lock.lock()
		if values[key] == v { lock.unlock(); return }
		values[key] = v
		lock.unlock()
		onChange?()
	}

	/// Back to the field defaults.
	public func reset() {
		lock.lock(); values = [:]; lock.unlock()
		onChange?()
	}

	/// Only the values that differ from the defaults (what gets persisted).
	var overrides: [String: PluginValue] {
		lock.lock(); defer { lock.unlock() }
		return values.filter { k, v in fields.first { $0.key == k }?.defaultValue != v }
	}

	/// Replaces the stored values with `loaded`, ignoring keys that are not fields (an older settings file).
	func load(_ loaded: [String: PluginValue]) {
		lock.lock()
		values = loaded.filter { k, _ in fields.contains { $0.key == k } }
		lock.unlock()
	}
}

/// Where plugin settings live. The App backs this with UserDefaults; tests use `InMemoryPluginSettingsStore`.
public protocol PluginSettingsStore: AnyObject {
	func data(forPlugin id: String) -> Data?
	func setData(_ data: Data?, forPlugin id: String)
}

public final class InMemoryPluginSettingsStore: PluginSettingsStore {
	public var blobs: [String: Data] = [:]
	public init() {}
	public func data(forPlugin id: String) -> Data? { blobs[id] }
	public func setData(_ data: Data?, forPlugin id: String) { blobs[id] = data }
}

/// What gets stored per plugin.
struct PluginStoredState: Codable {
	var enabled: Bool?
	var values: [String: PluginValue] = [:]
}

// Client settings: port of rsc-c's options.c. Values stay ints (0/1 for
// switches) so the additional-options panels can bind to them by key path.

import Foundation

public enum CacheVersion {
    public static let config = 85
    public static let entity = 24
    public static let maps = 63
    public static let media = 59
    public static let models = 36
    public static let sounds = 1
    public static let textures = 17

    static func entityIsTGA(_ v: Int) -> Bool { v < 9 }
    static func mediaIsTGA(_ v: Int) -> Bool { v < 28 }
    static func hasSeparateLand(_ v: Int) -> Bool { v > 27 }
}

public final class Options {
    // server
    public var members = 0, fatigue = 0
    public var versionConfig = 0, versionMaps = 0, versionEntity = 0, versionMedia = 0
    public var versionModels = 0, versionTextures = 0, versionSounds = 0
    public var lastWorld = 0, maxQuests = 0, maxSkills = 0, registration = 0, idleLogout = 0
    public var rememberUsername = 0, rememberPassword = 0
    public var username = "", password = ""
    public var browserCommand = "", wikiURL = ""
    public var diversifyNpcs = 0, renameHerblawItems = 0
    // controls
    public var mouseWheel = 0, middleClickCamera = 0, zoomCamera = 0, tabRespond = 0, optionNumbers = 0
    public var compassMenu = 0, transactionMenus = 0, offerX = 0, lastOfferX = 0, wikiLookup = 0
    public var combatStyleAlways = 0, holdToBuy = 0, touchVerticalDrag = 0, touchPinch = 0, touchMenuDelay = 0
    // display
    public var lowmem = 0, interlace = 0, flicker = 0, fogOfWar = 0, ranTargetFps = 0, displayFps = 0
    public var uiScale = 0, antiAlias = 0, fieldOfView = 0, showRoofs = 0, numberCommas = 0
    public var remainingExperience = 0, totalExperience = 0, experienceDrops = 0, inventoryCount = 0
    public var condenseItemAmounts = 0, certificateItems = 0, wildernessWarning = 0, statusBars = 0
    public var groundItemModels = 0, groundItemText = 0, distantAnimation = 0, tgaSprites = 0
    public var showHoverTooltip = 0, touchKeyboardRight = 0
    // bank
    public var bankUnstackbleWithdraw = 0, bankSearch = 0, bankCapacity = 0, bankValue = 0, bankExpand = 0
    public var bankScroll = 0, bankMenus = 0, bankInventory = 0, bankMaintainSlot = 0
    // presets
    public var accountManagement = 0, antiMacro = 0, retryLoginOnDisconnect = 0
    public var showAdditionalOptions = 0, skipTutorial = 0, escapeClear = 0, offHandleScrollDrag = 0
    public var thickWalls = 0

    /// options_new
    public init() {
        lastWorld = 0
        accountManagement = 0
        antiMacro = 0
        retryLoginOnDisconnect = 0
        showAdditionalOptions = 1
        skipTutorial = 1
        thickWalls = 0
        setDefaults()
    }

    private func setVersions() {
        members = 1
        versionConfig = CacheVersion.config; versionEntity = CacheVersion.entity
        versionMaps = CacheVersion.maps; versionMedia = CacheVersion.media
        versionModels = CacheVersion.models; versionSounds = CacheVersion.sounds
        versionTextures = CacheVersion.textures
        fatigue = 1; maxQuests = 50; maxSkills = 18; registration = 0
        rememberUsername = 0; rememberPassword = 0; diversifyNpcs = 0; renameHerblawItems = 0
    }

    /// options_set_defaults
    public func setDefaults() {
        setVersions()
        idleLogout = 0
        browserCommand = "open \"%s\""
        wikiURL = "https://classic.runescape.wiki/w/%s"
        offHandleScrollDrag = 1; escapeClear = 1; mouseWheel = 1; middleClickCamera = 25; zoomCamera = 1
        tabRespond = 1; optionNumbers = 1; compassMenu = 1; transactionMenus = 1; offerX = 1; lastOfferX = 1
        wikiLookup = 1; combatStyleAlways = 0; holdToBuy = 1; touchVerticalDrag = 33; touchPinch = 50
        touchMenuDelay = 350
        lowmem = 0; interlace = 0; flicker = 1; fogOfWar = 1; ranTargetFps = 10; displayFps = 0
        numberCommas = 1; showRoofs = 1; remainingExperience = 1; totalExperience = 1; experienceDrops = 0
        inventoryCount = 0; condenseItemAmounts = 1; certificateItems = 0; wildernessWarning = 1; statusBars = 0
        groundItemModels = 0; groundItemText = 1; distantAnimation = 1; tgaSprites = 0; showHoverTooltip = 0
        touchKeyboardRight = 0
        bankUnstackbleWithdraw = 1; bankSearch = 1; bankCapacity = 1; bankValue = 1; bankExpand = 1
        bankScroll = 1; bankMenus = 1; bankInventory = 1; bankMaintainSlot = 1
        uiScale = 1; antiAlias = 1; fieldOfView = 360
    }

    /// options_set_vanilla
    public func setVanilla() {
        setVersions()
        idleLogout = 1
        offHandleScrollDrag = 0; escapeClear = 0; mouseWheel = 0; middleClickCamera = 0; zoomCamera = 0
        tabRespond = 0; optionNumbers = 0; compassMenu = 0; transactionMenus = 0; offerX = 0; lastOfferX = 0
        wikiLookup = 0; combatStyleAlways = 0; holdToBuy = 0; touchVerticalDrag = 33; touchPinch = 50
        touchMenuDelay = 350
        lowmem = 0; interlace = 0; flicker = 1; fogOfWar = 1; ranTargetFps = 50; displayFps = 0
        numberCommas = 0; showRoofs = 1; remainingExperience = 0; totalExperience = 0; experienceDrops = 0
        inventoryCount = 0; condenseItemAmounts = 0; certificateItems = 0; wildernessWarning = 1; statusBars = 0
        groundItemModels = 0; groundItemText = 0; distantAnimation = 0; tgaSprites = 0; showHoverTooltip = 0
        touchKeyboardRight = 0
        bankUnstackbleWithdraw = 0; bankSearch = 0; bankCapacity = 0; bankValue = 0; bankExpand = 0
        bankScroll = 0; bankMenus = 0; bankInventory = 0; bankMaintainSlot = 0
        uiScale = 0; antiAlias = 0; fieldOfView = 360
    }

    // MARK: - options.ini

    static let intKeys: [(String, ReferenceWritableKeyPath<Options, Int>, Int, Int)] = [
        ("members", \.members, 0, 1), ("version_config", \.versionConfig, 0, 256),
        ("version_maps", \.versionMaps, 0, 256), ("version_entity", \.versionEntity, 0, 256),
        ("version_media", \.versionMedia, 0, 256), ("version_models", \.versionModels, 0, 256),
        ("version_textures", \.versionTextures, 0, 256), ("version_sounds", \.versionSounds, 0, 256),
        ("fatigue", \.fatigue, 0, 1), ("last_world", \.lastWorld, 0, 256), ("max_quests", \.maxQuests, 0, 50),
        ("max_skills", \.maxSkills, 0, 18), ("registration", \.registration, 0, 1),
        ("account_management", \.accountManagement, 0, 1), ("idle_logout", \.idleLogout, 0, 1),
        ("remember_username", \.rememberUsername, 0, 1), ("remember_password", \.rememberPassword, 0, 1),
        ("diversify_npcs", \.diversifyNpcs, 0, 1), ("rename_herblaw_items", \.renameHerblawItems, 0, 1),
        ("mouse_wheel", \.mouseWheel, 0, 1), ("middle_click_camera", \.middleClickCamera, -100, 100),
        ("zoom_camera", \.zoomCamera, 0, 1), ("tab_respond", \.tabRespond, 0, 1),
        ("option_numbers", \.optionNumbers, 0, 1), ("compass_menu", \.compassMenu, 0, 1),
        ("transaction_menus", \.transactionMenus, 0, 1), ("offer_x", \.offerX, 0, 1),
        ("last_offer_x", \.lastOfferX, 0, 1), ("wiki_lookup", \.wikiLookup, 0, 1),
        ("combat_style_always", \.combatStyleAlways, 0, 1), ("hold_to_buy", \.holdToBuy, 0, 1),
        ("touch_vertical_drag", \.touchVerticalDrag, -100, 100), ("touch_pinch", \.touchPinch, -100, 100),
        ("touch_menu_delay", \.touchMenuDelay, 80, 2000),
        ("lowmem", \.lowmem, 0, 1), ("interlace", \.interlace, 0, 1), ("flicker", \.flicker, 0, 1),
        ("fog_of_war", \.fogOfWar, 0, 1), ("ran_target_fps", \.ranTargetFps, 0, 50),
        ("display_fps", \.displayFps, 0, 1), ("ui_scale", \.uiScale, 0, 1), ("anti_alias", \.antiAlias, 0, 1),
        ("field_of_view", \.fieldOfView, 0, 880), ("show_roofs", \.showRoofs, 0, 1),
        ("number_commas", \.numberCommas, 0, 1), ("remaining_experience", \.remainingExperience, 0, 1),
        ("total_experience", \.totalExperience, 0, 1), ("experience_drops", \.experienceDrops, 0, 1),
        ("inventory_count", \.inventoryCount, 0, 1), ("condense_item_amounts", \.condenseItemAmounts, 0, 1),
        ("certificate_items", \.certificateItems, 0, 1), ("wilderness_warning", \.wildernessWarning, 0, 1),
        ("status_bars", \.statusBars, 0, 1), ("ground_item_models", \.groundItemModels, 0, 1),
        ("ground_item_text", \.groundItemText, 0, 1), ("distant_animation", \.distantAnimation, 0, 1),
        ("tga_sprites", \.tgaSprites, 0, 1), ("show_hover_tooltip", \.showHoverTooltip, 0, 1),
        ("touch_keyboard_right", \.touchKeyboardRight, 0, 1),
        ("bank_unstackble_withdraw", \.bankUnstackbleWithdraw, 0, 1), ("bank_search", \.bankSearch, 0, 1),
        ("bank_capacity", \.bankCapacity, 0, 1), ("bank_value", \.bankValue, 0, 1),
        ("bank_expand", \.bankExpand, 0, 1), ("bank_scroll", \.bankScroll, 0, 1),
        ("bank_menus", \.bankMenus, 0, 1), ("bank_inventory", \.bankInventory, 0, 1),
        ("bank_maintain_slot", \.bankMaintainSlot, 0, 1),
    ]

    /// options_load: applies "key = value" lines, clamping each to its range.
    public func load(ini text: String) {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix(";"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "username" { username = String(value.prefix(20)); continue }
            if key == "password" { password = String(value.prefix(20)); continue }
            if let (_, path, lo, hi) = Options.intKeys.first(where: { $0.0 == key }), let v = Int(value) {
                self[keyPath: path] = min(max(v, lo), hi)
            }
        }
    }

    /// options_save, as "key = value" lines.
    public func iniText() -> String {
        var out = ""
        for (key, path, _, _) in Options.intKeys { out += "\(key) = \(self[keyPath: path])\n" }
        out += "username = \(username)\npassword = \(password)\n"
        return out
    }

    /// Where options.ini lives; nil keeps settings in memory only (tests).
    public var fileURL: URL?

    public func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        load(ini: String(decoding: data, as: UTF8.self))
    }

    public func save() {
        guard let url = fileURL else { return }
        try? Data(iniText().utf8).write(to: url)
    }
}

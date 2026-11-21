// Optional item renames from rsc-c's custom/clarify-herblaw-items.c.

extension GameData {
    private mutating func rename(_ id: Int, _ name: String, _ description: String? = nil) {
        items[id].name = name
        if let description { items[id].description = description }
    }

    public mutating func modifyUnidentifiedHerbs() {
        guard items.count >= 454 else { return }
        let suffix = ", but I need a closer look to not poison myself"
        rename(165, "Unidentified guam leaf", "It can be extracted to improve coordination" + suffix)
        rename(435, "Unidentified marrentill", "I think it's a poison cure" + suffix)
        rename(436, "Unidentified tarromin", "It can be extracted to improve strength" + suffix)
        rename(437, "Unidentified harralander", "I think it's harralander" + suffix)
        rename(438, "Unidentified ranarr weed", "A floral weed, I need a closer look to process it into something useful")
        rename(439, "Unidentified irit leaf", "A leafy herb" + suffix)
        rename(440, "Unidentified avantoe", "I think it's avantoe" + suffix)
        rename(441, "Unidentified kwuarm", "It's leaking foul smelling sap, I need to process it very carefully")
        rename(442, "Unidentified cadantine", "I think it's cadantine" + suffix)
        rename(443, "Unidentified dwarf weed", "It smells like dwarven settlements" + suffix)
        if items.count >= 933 {
            rename(933, "Unidentified rare herb", "A very unusual herb, I need a closer look to not poison myself")
        }
    }

    public mutating func modifyUnfinishedPotions() {
        guard items.count >= 454 else { return }
        let names = ["guam", "marrentill", "tarromin", "harralander", "ranarr", "irit", "avantoe", "kwuarm",
                     "cadantine", "dwarf weed"]
        for (i, n) in names.enumerated() { rename(454 + i, "Unfinished \(n) potion") }
        if items.count >= 935 { rename(935, "Unfinished torstol potion") }
        if items.count >= 1052 { rename(1052, "Unfinished shamanic potion") }
        if items.count >= 1074 { rename(1074, "Unfinished jangerberry potion") }
    }

    private mutating func appendDosage(_ id: Int) {
        if items[id].name == "Members object" { return }
        items[id].name += " (3)"
        items[id + 1].name += " (2)"
        items[id + 2].name += " (1)"
    }

    public mutating func modifyPotionDosage() {
        items[221].name += " (4)"
        appendDosage(222)
        if items.count > 474 { for i in 0..<9 { appendDosage(474 + i * 3) } }
        if items.count > 566 { for i in 0..<2 { appendDosage(566 + i * 3) } }
        if items.count > 963 { appendDosage(963) }
    }
}

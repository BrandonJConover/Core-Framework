import Foundation

// Client -> Server opcodes (from Opcodes.java Out enum)
enum RSCOutOpcode: UInt8 {
    case login              = 0
    case logout             = 1
    case register           = 2
    case ping               = 67
    case walkToEntity       = 16
    case walkToPoint        = 187
    case confirmLogout      = 31
    case chatMessage        = 216
    case npcTalkTo          = 153
    case npcAttack          = 190
    case playerAttack       = 171
    case playerFollow       = 165
    case groundItemTake     = 247
    case itemDrop           = 246
    case itemCommand        = 90
    case itemEquip          = 169
    case itemUnequip        = 170
    case objectCommand1     = 136
    case objectCommand2     = 79
    case shopBuy            = 236
    case shopSell           = 221
    case shopClose          = 166
    case tradeAccept        = 55
    case tradeDecline       = 230
    case bankClose          = 212
    case castOnSelf         = 137
    case castOnLand         = 158
    case serverConfigRequest = 19
}

// Server -> Client opcodes (from PacketHandler.java)
enum RSCInOpcode: UInt8 {
    case serverConfig       = 19
    case showOtherPlayers   = 191
    case showNPCs           = 79
    case chatMessage        = 131
    case loadArea           = 25
    case updateInventory    = 53
    case updateEquipment    = 254
    case updateEquipmentSlot = 255
    case loadStats          = 156
    case showBank           = 42
    case updateBank         = 249
    case updateInventoryItem = 90
    case showGameObjects    = 48
    case showWalls          = 91
    case generateCounts     = 211
    case npcAppearances     = 104
    case showOptionsMenu    = 245
    case playSound          = 204
    case showLoginDialog    = 182
    case systemUpdate       = 52
    case connectionMessage  = 149
    case closeConnection    = 4
    case cantLogout         = 183
    case forceDisconnect    = 165
    case createNPC          = 88
    case updateExperience   = 159

    case killAnnouncement   = 118
    case showServerMsg      = 222
    case receivePrivateMsg  = 120
    case updateIgnoreList   = 109
}

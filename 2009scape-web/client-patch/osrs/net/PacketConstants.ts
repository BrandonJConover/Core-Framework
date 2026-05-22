/**
 * PacketConstants — Rev 530 (2009scape) packet size table.
 *
 * Replaces the 377 size table. Values:
 *   >= 0  : fixed size (that many payload bytes)
 *   -1    : variable-byte (next byte = payload length)
 *   -2    : variable-short (next 2 bytes = payload length)
 *   -3    : unknown / unhandled opcode
 *
 * Source: 2009scape Server/src/main/core/net/packet/in/GameReadEvent.java
 */
export class PacketConstants {
    // Client → Server (incoming on server side) packet sizes
    static readonly PACKET_SIZES: number[] = [
        -3, -3, -3,  2,  2, -3,  8, -3, -3,  6,  // 0-9
         4, -3, -3, -3, -3, -3, -3,  0, -3, -3,  // 10-19
         4,  4,  1,  4, -3, -3, -3, 16, -3, -3,  // 20-29
         2, -3, -3,  6,  8, -3, -3, -3, -3, -1,  // 30-39
        -3, -3, -3, -3, -1, -3, -3, -3,  6, -3,  // 40-49
        -3, -3, -3,  6, -3,  8, -3,  8, -3, -3,  // 50-59
        -3, -3, -3, -3,  6, -1,  6, -3,  2, -3,  // 60-69
        -3,  2,  2, 12, -3,  6, -3, -1,  2, 12,  // 70-79
        -3,  8, 12, -3,  6,  8, -3, -3, -3, -3,  // 80-89
        -3, -3,  2,  0,  2, -3, -3, -3,  4, 10,  // 90-99
        -3, 14, -3, -3,  8, -3,  2, -3, -3,  6,  // 100-109
         0,  2, -3, -3,  2, 10, -3, -1, -3, -3,  // 110-119
         8, -3, -3, -1,  6, -3, -3, -3, -3, -3,  // 120-129
        -3, 10,  6,  2, 14,  8, -3,  4, -3, -3,  // 130-139
        -3, -3, -3, -3, -3, -3, -3, -3,  2, -3,  // 140-149
        -3, -3, -3,  8,  8,  6,  8,  3, -3, -3,  // 150-159
        -3,  8,  8, -3, -3, -3,  6, -1,  6, -3,  // 160-169
         6, -3, -3, -3, -3,  2, -3,  2, -1,  4,  // 170-179
         2, -3, -3, -3,  0, -3, -3, -3,  9, -3,  // 180-189
        -3, -3, -3, -3,  6,  8,  6, -3, -3,  6,  // 190-199
        -3, -1, -3, -3, -3, -3,  8, -3, -3, -3,  // 200-209
        -3, -3, -3,  8, -3, -1, -3, -3,  2, -3,  // 210-219
        -3, -3, -3, -3, -3, -3, -3, -3,  6, -3,  // 220-229
        -3,  9, -3, 12,  6, -3, -3, -1, -3,  8,  // 230-239
        -3, -3, -3,  6,  8,  0, -3,  6, 10, -3,  // 240-249
        -3, -3, -3, 14,  6, -3                     // 250-255
    ];
}

/**
 * Server → Client opcodes (outgoing from server)
 * Key packets for the web client to handle.
 */
export const ServerOpcode = {
    // Core sync
    PLAYER_UPDATE:         225,
    NPC_UPDATE:             32,

    // Map / scene
    UPDATE_SCENE_GRAPH:    162,
    BUILD_DYNAMIC_SCENE:   214,
    UPDATE_AREA_CHUNK:     230,
    UPDATE_AREA_POSITION:   26,

    // Session
    LOGOUT:                 86,

    // Interface / UI
    INTERFACE:             155,
    CLOSE_INTERFACE:       149,
    WINDOWS_PANE:          145,
    ACCESS_MASK:           165,
    STRING_PACKET:         171,
    RUN_SCRIPT:            115,
    INTERACTION_OPTION:     44,
    CLEAR_MINIMAP_FLAG:    153,

    // Stats / player state
    SKILL_LEVEL:            38,
    RUN_ENERGY:            234,
    CONFIG_SMALL:           60,
    CONFIG_LARGE:          226,
    VARBIT_SMALL:           37,
    VARBIT_LARGE:           84,

    // Inventory / items
    CONTAINER_FULL:        105,
    CONTAINER_SLOT:         22,
    CONTAINER_CLEAR:       144,

    // Ground items
    CONSTRUCT_GROUND_ITEM:  33,
    CLEAR_GROUND_ITEM:     240,

    // Scenery
    CONSTRUCT_SCENERY:     179,
    CLEAR_SCENERY:         195,

    // Chat / messages
    GAME_MESSAGE:           70,
    RECEIVE_PM:              0,
    SENT_PM:                71,
    CLAN_MESSAGE:           54,

    // Social
    CONTACT_UPDATE_STATE:  197,
    CONTACT_IGNORE_LIST:   126,
    CONTACT_UPDATE_FRIEND:  62,

    // Audio
    MUSIC_PRIMARY:           4,
    MUSIC_JINGLE:          208,
    SOUND_EFFECT:          172,
    SOUND_POSITIONED:       97,

    // Misc
    HINT_ICON:             217,
} as const;

/**
 * Client → Server opcodes (incoming on server)
 * Actions the web client can send.
 */
export const ClientOpcode = {
    // Walking
    WALK_WORLD:            215,
    WALK_MINIMAP:           39,
    WALK_INTERACT:          77,

    // NPC actions
    NPC_ACTION_1:           78,
    NPC_ACTION_2:            3,
    NPC_ACTION_3:          148,
    NPC_ACTION_4:           30,
    NPC_ACTION_5:          218,

    // Player actions
    PLAYER_ACTION_1:        68,
    PLAYER_ACTION_FOLLOW:   71,
    PLAYER_ACTION_TRADE:   180,
    PLAYER_REQ_ASSIST:     114,
    PLAYER_ACTION_5:       175,
    PLAYER_ACTION_BLOCK:   109,
    // Legacy aliases kept for existing call sites while the 530 action layer
    // is wired into Game.processMenuActions.
    PLAYER_ACTION_3:        71,
    PLAYER_ACTION_4:       180,

    // Scenery (object) actions
    SCENERY_ACTION_1:      254,
    SCENERY_ACTION_2:      194,
    SCENERY_ACTION_3:       84,
    SCENERY_ACTION_4:      247,
    SCENERY_ACTION_5:      170,

    // Item actions
    ITEM_ACTION_1:         156,
    ITEM_ACTION_2:          55,
    ITEM_ACTION_3:         153,
    ITEM_ACTION_4:         161,
    ITEM_ACTION_5:         135,
    ITEM_OPERATE:          206,
    ITEM_IN_COMPONENT_ACTION_1: 81,
    ITEM_IN_COMPONENT_ACTION_2: 154,
    ITEM_IN_COMPONENT_ACTION_3: 85,
    ITEM_IN_COMPONENT_ACTION_5: 6,

    // Ground items
    GROUND_ITEM_ACTION_1:   66,
    GROUND_ITEM_ACTION_2:   33,
    GROUND_ITEM_ACTION_5:   48,

    // Use-with
    USE_ON_NPC:            115,
    USE_ON_PLAYER:         248,
    USE_ON_ITEM:            27,
    USE_ON_SCENERY:        134,
    USE_ON_GROUND_ITEM:    101,

    // Selected component target actions
    COMPONENT_NPC_ACTION:  239,
    COMPONENT_ITEM_ACTION: 253,
    COMPONENT_SCENERY_ACTION: 233,
    COMPONENT_PLAYER_ACTION: 195,
    COMPONENT_GROUND_ITEM_ACTION: 73,

    // Interface actions
    IF_ACTION_1:           155,
    IF_ACTION_2:           196,
    IF_ACTION_3:           124,
    IF_ACTION_4:           199,
    IF_ACTION_5:           234,
    IF_ACTION_6:           168,
    IF_ACTION_7:           166,
    IF_ACTION_8:            64,
    IF_ACTION_9:            53,
    IF_ACTION_10:            9,
    IF_CS2:                 10,
    DIALOG_ACTION:         111,
    CONTINUE_DIALOGUE:     132,
    CLOSE_IFACE:           184,
    RESUME_COUNT_DIALOG:    23,
    RESUME_NAME_DIALOG:    244,
    RESUME_STRING_DIALOG:   65,

    // Chat
    CHAT_MESSAGE:          237,
    CHAT_SETTINGS:         157,
    COMMAND:                44,
    PRIVATE_MESSAGE:       201,
    BUG_REPORT:             99,

    // Social
    ADD_FRIEND:            120,
    REMOVE_FRIEND:          57,
    ADD_IGNORE:             34,
    REMOVE_IGNORE:         213,

    // Examine
    EXAMINE_SCENERY:        94,
    EXAMINE_ITEM:           92,
    EXAMINE_NPC:            72,

    // Misc
    FOCUS_CHANGE:           22,
    CAMERA_MOVEMENT:        21,
    DISPLAY_UPDATE:        243,
    AFK_TIMEOUT:           245,
    MOUSE_CLICKED:          75,
    PING:                   93,
    PACKET_COUNT:          177,
    MAP_REBUILD_STARTED:    20,
    MAP_REBUILD_FINISHED:  110,
} as const;

// Players and NPCs: port of rsc-c's game-character.c. Field widths follow the
// C struct where they wrap (step_count is a uint8_t, so walking animation
// frames depend on it rolling over at 256).

public enum AnimationIndex {
    public static let head = 0, body = 1, legs = 2, leftHand = 3, rightHand = 4
    public static let headOverlay = 5, bodyOverlay = 6, legsOverlay = 7, index8 = 8
    public static let boots = 9, neck = 10, cape = 11
    public static let count = 12
}

public final class GameCharacter {
    public static let waypointCount = 10

    /// Draw order of the twelve equipment slots for each of the eight facing directions.
    public static let animationOrder: [[Int]] = [
        [11, 2, 9, 7, 1, 6, 10, 0, 5, 8, 3, 4],
        [11, 2, 9, 7, 1, 6, 10, 0, 5, 8, 3, 4],
        [11, 3, 2, 9, 7, 1, 6, 10, 0, 5, 8, 4],
        [3, 4, 2, 9, 7, 1, 6, 10, 8, 11, 0, 5],
        [3, 4, 2, 9, 7, 1, 6, 10, 8, 11, 0, 5],
        [4, 3, 2, 9, 7, 1, 6, 10, 8, 11, 0, 5],
        [11, 4, 2, 9, 7, 1, 6, 10, 0, 5, 8, 3],
        [11, 2, 9, 7, 1, 6, 10, 0, 5, 8, 4, 3],
    ]
    public static let walkModel = [0, 1, 2, 1]
    public static let combatModel1 = [0, 1, 2, 1, 0, 0, 0, 0]
    public static let combatModel2 = [0, 0, 0, 0, 0, 1, 2, 1]
    public static let hairColours: [Int32] = [0xffc030, 0xffa040, 0x805030, 0x604020, 0x303030,
                                              0xff6020, 0xff4000, 0xffffff, 0x00ff00, 0x00ffff]
    public static let topBottomColours: [Int32] = [0xff0000, 0xff8000, 0xffe000, 0xa0e000, 0x00e000,
                                                   0x008000, 0x00a080, 0x00b0ff, 0x0080ff, 0x0030f0,
                                                   0xe000e0, 0x303030, 0x604000, 0x805000, 0xffffff]
    public static let skinColours: [Int32] = [0xecded0, 0xccb366, 0xb38c40, 0x997326, 0x906020]

    public var encodedUsername: Int64 = 0
    public var name = ""
    public var serverIndex = 0
    public var serverId = 0
    /// -1 for players.
    public var npcId = -1
    public var stepCount: UInt8 = 0
    public var movingStep = 0
    public var waypointCurrent = 0
    public var currentX = 0
    public var currentY = 0
    public var waypointsX = [Int](repeating: 0, count: waypointCount)
    public var waypointsY = [Int](repeating: 0, count: waypointCount)
    public var currentAnimation = 0
    public var nextAnimation = 0
    public var messageTimeout = 0
    public var message = ""
    public var damageTaken = 0
    public var currentHits = 0
    public var maxHits = 0
    public var combatTimer = 0
    public var hairColour = 0
    public var topColour = 0
    public var bottomColour = 0
    public var skinColour = 0
    public var skullVisible = 0
    public var bubbleTimeout = 0
    public var bubbleItem = 0
    public var level = -1
    public var animations = [Int](repeating: 0, count: AnimationIndex.count)
    public var incomingProjectileSprite = 0
    public var projectileRange = 0
    public var attackingPlayerServerIndex = 0
    public var attackingNpcServerIndex = 0

    public init() {}

    /// game_character_move
    public func move() {
        let nextWaypoint = (waypointCurrent + 1) % 10
        if movingStep != nextWaypoint {
            var animation = -1
            let step = movingStep
            let deltaStep = step < nextWaypoint ? nextWaypoint - step : (10 + nextWaypoint) - step
            var j5 = 4
            if deltaStep > 2 { j5 = (deltaStep - 1) * 4 }
            let loc = 128
            if waypointsX[step] - currentX > loc * 3 || waypointsY[step] - currentY > loc * 3 ||
                waypointsX[step] - currentX < -loc * 3 || waypointsY[step] - currentY < -loc * 3 || deltaStep > 8 {
                currentX = waypointsX[step]
                currentY = waypointsY[step]
            } else {
                if currentX < waypointsX[step] {
                    currentX += j5; stepCount &+= 1; animation = 2
                } else if currentX > waypointsX[step] {
                    currentX -= j5; stepCount &+= 1; animation = 6
                }
                if currentX - waypointsX[step] < j5 && currentX - waypointsX[step] > -j5 { currentX = waypointsX[step] }
                if currentY < waypointsY[step] {
                    currentY += j5; stepCount &+= 1
                    animation = animation == -1 ? 4 : animation == 2 ? 3 : 5
                } else if currentY > waypointsY[step] {
                    currentY -= j5; stepCount &+= 1
                    animation = animation == -1 ? 0 : animation == 2 ? 1 : 7
                }
                if currentY - waypointsY[step] < j5 && currentY - waypointsY[step] > -j5 { currentY = waypointsY[step] }
            }
            if animation != -1 { currentAnimation = animation }
            if currentX == waypointsX[step] && currentY == waypointsY[step] { movingStep = (step + 1) % 10 }
        } else {
            currentAnimation = nextAnimation
            if npcId == Mudclient.giantBatId { stepCount &+= 1 }
        }
        if messageTimeout > 0 { messageTimeout -= 1 }
        if bubbleTimeout > 0 { bubbleTimeout -= 1 }
        if combatTimer > 0 { combatTimer -= 1 }
    }
}

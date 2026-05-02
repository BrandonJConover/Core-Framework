/**
 * Tiny value containers for rev-530 zone-update state.
 *
 * rt4-client stores these in LinkedList-backed Node wrappers so the renderer
 * can iterate scene-global queues. The web-client Tier 5a port only needs the
 * decoded state to survive dispatch; renderer tiers will decide how to consume
 * it.
 */

export class ObjStack {
    constructor(
        public type: number = 0,
        public amount: number = 0,
    ) {}
}

export class ObjStackNode {
    constructor(public value: ObjStack) {}
}

export class ProjAnim {
    public targetX: number = 0;
    public targetY: number = 0;
    public targetZ: number = 0;
    public targetCycle: number = 0;

    constructor(
        public spotanimId: number,
        public plane: number,
        public sourceX: number,
        public sourceY: number,
        public sourceZ: number,
        public startCycle: number,
        public endCycle: number,
        public elevationPitch: number,
        public startDistance: number,
        public targetIndex: number,
        public endHeight: number,
    ) {}

    setTarget(targetX: number, targetCycle: number, targetZ: number, targetY: number): void {
        this.targetX = targetX;
        this.targetY = targetY;
        this.targetZ = targetZ;
        this.targetCycle = targetCycle;
    }
}

export class SpotAnim {
    constructor(
        public spotanimId: number,
        public plane: number,
        public x: number,
        public y: number,
        public z: number,
        public delay: number,
        public loop: number,
        public target: number = 0,
        public height: number = 0,
    ) {}
}

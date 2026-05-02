export interface PrivateMessage {
    senderName: string;
    senderName37: string;
    rights: number;
    body: string;
    receivedAt: number;
    direction: "in" | "out" | "clan";
    messageId?: string;
    quickchatId?: number;
    clanName?: string;
}

export interface ClanMember {
    name: string;
    name37: string;
    world: number;
    worldName: string;
    rank: number;
}

export interface ClanState {
    name: string;
    owner: string;
    world: number;
    rank: number;
    minKick: number;
    members: ClanMember[];
    messages: PrivateMessage[];
}

export class PrivateMessageQueue {
    private buf: PrivateMessage[] = [];
    private cap: number = 100;

    push(msg: PrivateMessage) {
        this.buf.push(msg);
        if (this.buf.length > this.cap) this.buf.shift();
    }

    all(): PrivateMessage[] {
        return this.buf.slice();
    }
}

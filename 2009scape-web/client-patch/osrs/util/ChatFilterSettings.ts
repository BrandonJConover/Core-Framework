import { Buffer } from "../net/Buffer";

export class ChatFilterSettings {
    public publicFilter: number = 0;
    public privateFilter: number = 0;
    public tradeFilter: number = 0;

    static default(): ChatFilterSettings {
        return new ChatFilterSettings();
    }

    static fromValues(publicFilter: number, privateFilter: number, tradeFilter: number): ChatFilterSettings {
        const settings = new ChatFilterSettings();
        settings.publicFilter = publicFilter;
        settings.privateFilter = privateFilter;
        settings.tradeFilter = tradeFilter;
        return settings;
    }

    static fromServer(buf: Buffer): ChatFilterSettings {
        const g1 = () => buf.buffer[buf.currentPosition++] & 0xFF;
        return ChatFilterSettings.fromValues(g1(), g1(), g1());
    }
}

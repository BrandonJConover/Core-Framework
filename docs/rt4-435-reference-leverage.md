# 435 Reference Leverage Map

`reference/refactored-client-435` is a read-only advisory source for first-playable work. It is useful because it is a clearer nearby-era Java client, but it is not the parity target. `reference/rt4-client` remains authoritative for rev-530 packet bytes, cache formats, CS2, interface ids, update masks, and rendering behavior. The local 2009scape Java server remains authoritative for current playable-stack emissions.

## How Much We Can Reuse

| Area | Leverage | Use | Do Not Use |
| --- | --- | --- | --- |
| Chatbox/dialogue state | High conceptual leverage | Separate normal chat scroll, permanent dialogue, and chatbox interface state; use this to guide browser state transitions when 530 opens chatbox/dialogue surfaces | 435 interface ids, opcodes, packet sizes, or dialogue option packet details |
| Menu/action flow | High conceptual leverage | Preserve the original row model: build rows from the active UI/scene area, choose the left-click/default row, dispatch through the existing native 530 action encoder | 435 `ActionRowType` ids or outbound message formats |
| Bank/inventory UI | Medium conceptual leverage | Use the component/container relationship and drag/click state shape to reason about bank side-inventory and component-backed slots | 435 container ids, bank interface ids, or inventory packet bodies |
| Combat smoke | Medium conceptual leverage | Use the high-level flow of rendered NPC row -> target action -> feedback surface | 435 combat update masks, hit formats, or NPC packet details |
| Browser/mobile shell | Low leverage | Treat mouse-first flow as the gameplay model that touch should adapt into | Any expectation that 435 has mobile support or responsive browser behavior |
| Rendering/cache/audio | Low first-playable leverage | Use only for architecture orientation if a file is easier to read than the obfuscated 530 client | 435 cache layout, model details, texture behavior, sprites, fonts, or audio formats |

Roughly, 435 can accelerate 10-20% of first-playable work by clarifying structure. Very little should be copied literally because the target is a browser TypeScript client speaking rev-530 to 2009scape Java.

## First Phase: Dialogue And Chatbox

Use 435 to guide state shape, then confirm behavior against RT4 530 and live Java:

- 435 evidence: `GameInterface.chatboxInterfaceId` is separate from `ChatBox.dialogueId`; chatbox interface rendering takes precedence over normal chat scroll when open.
- 435 evidence: chat area input is blocked while a chatbox/fullscreen interface is open.
- 435 evidence: chatbox-area menu generation routes through chatbox or permanent dialogue interface actions before normal chat-name right-click handling.
- 530/Java confirmation required: the actual 530 server packet is `IF_OPENSUB`/`IF_OPENTOP`, the actual interface id for the local NPC dialogue surface, and the continue packet remains `Outgoing530.continueDialogue`.

Implementation target:

- When Java opens an NPC chatbox/dialogue surface, `PacketHandler530` should update the 530 component stack and mirror enough legacy state (`backDialogueId` or `dialogueId`) for existing TS draw/menu paths and the Playwright NPC dialogue smoke to observe it.
- The guard for that mirror is `node .packet-handler530-chatbox-state-test.mjs` in `2009scape-web/client-patch`.
- The smoke result must include the Java diagnostic line showing `NPCTalkListener opened=true`, browser state showing an open chatbox/dialogue interface, and native continue-dialogue opcode `132` emitted by `Outgoing530`.

## First Phase: Menu And Bank

Use 435 to guide row selection and component-backed slot reasoning, but keep current packet truth:

- Menu rows should come from the rendered scene or active interface area when possible; direct row injection remains a test fallback only.
- Bank/inventory action probes should choose a non-empty component-backed slot and dispatch through `Game.processMenuActions()`, which must route to `Outgoing530`.
- Container ids `93` and `95` are current local Java fixture evidence, not 435 evidence.

## Reference-Use Rule

Every 435-informed implementation summary should name the 530 or Java-server source that confirmed the behavior. Never copy 435 opcodes, packet sizes, cache layouts, interface ids, update masks, or combat packet details unless confirmed against `reference/rt4-client` and live 2009scape Java output.

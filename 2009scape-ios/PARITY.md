# Feature parity with rt4 (rev 530)

Goal (Brandon, 2026-11-21): full feature parity of the Swift client with the original rt4 client.
Verified 2026-11-21: every server packet decodes; no CS2 opcode hits the unported branch; live
playthrough tests (tutorial, combat, bank, shop, magic, woodcutting, fires, cooking) pass.

## Done
- [x] World map (archive 23 data, ground/icons/labels, overview, ops 5200-5220, pan/pinch)
- [x] Client cycle catch-up like rt4 (no slow motion on slow frames)
- [x] IF_OPENTOP keeps sub-interfaces (chatbox returns after the world map)
- [x] CS2 obj ops treat missing items as blank types

## In progress
- [ ] CS2 host ops that silently did nothing: character designer (403/404/410), script sounds/music/jingles (3200-3202), item search (4210-4212), chat filter packet (5001), bug report (5002), invParamTotal (3331/3332), animateSelf, clickPlayerOption, setObjRecolour, minimap/viewport opts
- [ ] Preferences applied, persisted and sent (packet 98): roofs, all levels, ground decorations, idle anims, shadows, stereo...
- [ ] Title screen: titlebg + logo, Flames (clientCode 1402), ops 5424-5426, title music
- [ ] Legacy IF1/CS1 scripts (dynamic text, active states, IF1 scrollbars), ops 3108/3109
- [ ] Scrolling lists (onScroll, wheel and finger drag) for bank, quests, chat history

## To do
- [ ] Full interface sweep (all 483) clean
- [ ] World list and world hopping (ops 6500-6507, 5309, 6600/6601)
- [ ] Hardware keyboard (iPad/BT keyboards): arrow-key camera, F-keys, Esc, modifiers, Ctrl-run
- [ ] Login reply messages for every rt4 reply code
- [ ] Housekeeping packets: TRANSMITVAR_VERIFYID, applet focus, camera position, window status
- [ ] Fixed 765x503 mode (interface 548)
- [ ] Large-creature terrain tilt (PathingEntity.method2685) and BAS roll/pitch (method2687)
- [ ] RoofHider mode 1, client-local ::commands
- [ ] Account creation (ops 5603-5610), probably not needed for a private server
- [ ] HD (GL) paths: lighting, shadows, water, overlay edge blend (Metal renderer roadmap)

Not needed: particles (rt4's ParticleSystem is a stub); camera spline op 5502 (its arrays are never filled in rt4).

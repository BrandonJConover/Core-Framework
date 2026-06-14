RT4 wrapper server patches
==========================

These files mirror the Kotlin packet changes currently applied to the Pi-hosted
2009scape server used by the CheerpJ RT4 wrapper.

They are kept here because the live 2009scape server checkout is not part of
this repository tree. Apply them over the matching server files before building
the Pi server image:

- `Server/src/main/core/net/packet/in/Decoders530.kt`
- `Server/src/main/core/net/packet/PacketProcessor.kt`

The current patch set adds RT4 530 packet decoding/bridging for interface,
dialogue, NPC, object, item, and equipment actions used by the browser wrapper.

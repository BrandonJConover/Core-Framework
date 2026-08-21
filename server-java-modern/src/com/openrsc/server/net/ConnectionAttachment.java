package com.openrsc.server.net;

import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.net.rsc.ISAACContainer;

import java.util.concurrent.atomic.AtomicReference;

public class ConnectionAttachment {

	public AtomicReference<Player> player = new AtomicReference<>();

	public AtomicReference<ISAACContainer> ISAAC = new AtomicReference<>();

	public AtomicReference<Short> authenticClient = new AtomicReference<>();

	public AtomicReference<PcapLogger> pcapLogger = new AtomicReference<>();

	public AtomicReference<Integer> sessionId = new AtomicReference<>();
	public AtomicReference<Boolean> canSendSessionId = new AtomicReference<>();
	public AtomicReference<Boolean> isLongSessionId = new AtomicReference<>();
	public AtomicReference<Boolean> isWebSocket = new AtomicReference<>(false);

	/**
	 * Real client IP recovered from the reverse proxy's X-Forwarded-For header
	 * during the WebSocket handshake, when the direct peer is a trusted proxy.
	 * Null for direct connections or when no trusted forwarding was present.
	 */
	public AtomicReference<String> forwardedFor = new AtomicReference<>();

}

package com.openrsc.server.net;

import io.netty.channel.Channel;

import java.net.InetSocketAddress;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Resolves the real client IP for a connection, accounting for a trusted
 * reverse proxy (nginx/Caddy) in front of the game/WebSocket listeners.
 *
 * The game protocol reads the socket peer address, but web clients reach the
 * server through a proxy on loopback, so they all appear as 127.0.0.1 — which
 * defeats per-IP password throttling, session caps and flood bans. When the
 * direct peer is a configured trusted proxy we recover the client IP from the
 * X-Forwarded-For header captured at the WebSocket handshake.
 *
 * X-Forwarded-For is only consulted when the direct peer is trusted, so a
 * direct attacker cannot spoof the header to dodge bans or forge another IP.
 * Trusted proxies default to loopback; override with
 * -Dopenrsc.trustedProxies=ip1,ip2,...
 */
public final class ClientAddress {

	private static final Set<String> TRUSTED_PROXIES = parse(
		System.getProperty("openrsc.trustedProxies", "127.0.0.1,::1,0:0:0:0:0:0:0:1"));

	private ClientAddress() {}

	private static Set<String> parse(String csv) {
		Set<String> set = new LinkedHashSet<>();
		for (String s : csv.split(",")) {
			String t = s.trim();
			if (!t.isEmpty()) set.add(t);
		}
		return set;
	}

	public static boolean isTrustedProxy(String ip) {
		return ip != null && TRUSTED_PROXIES.contains(ip.trim());
	}

	/**
	 * Given the direct peer IP and a raw X-Forwarded-For header value, return
	 * the real client IP, or null if the peer is not a trusted proxy or the
	 * header is absent/unusable. Walks the header right-to-left and returns the
	 * first hop that is not itself a trusted proxy (the client that connected
	 * to our edge); a proxy appends the connecting client, so the rightmost
	 * non-proxy entry is authoritative and the leftmost is client-controllable.
	 */
	public static String forwardedClientIp(String directPeerIp, String xForwardedFor) {
		if (!isTrustedProxy(directPeerIp)) return null;
		if (xForwardedFor == null || xForwardedFor.isBlank()) return null;
		String[] hops = xForwardedFor.split(",");
		for (int i = hops.length - 1; i >= 0; i--) {
			String hop = hops[i].trim();
			if (!hop.isEmpty() && !isTrustedProxy(hop)) {
				return hop;
			}
		}
		return null;
	}

	/**
	 * Effective client IP for a channel: the proxy-forwarded IP recovered at
	 * the WebSocket handshake if present, otherwise the socket peer address.
	 */
	public static String effectiveIp(Channel channel) {
		ConnectionAttachment att = channel.attr(RSCConnectionHandler.attachment).get();
		if (att != null && att.forwardedFor != null) {
			String fwd = att.forwardedFor.get();
			if (fwd != null && !fwd.isEmpty()) {
				return fwd;
			}
		}
		return ((InetSocketAddress) channel.remoteAddress()).getAddress().getHostAddress();
	}
}

package com.openrsc.server.net;

import io.netty.channel.ChannelHandlerContext;
import io.netty.handler.codec.MessageToMessageEncoder;
import io.netty.handler.codec.http.websocketx.BinaryWebSocketFrame;
import io.netty.util.Attribute;
import io.netty.util.AttributeKey;
import io.netty.util.AttributeMap;

import java.util.List;

public final class RSCProtocolWebEncoder extends MessageToMessageEncoder<Packet> implements AttributeMap {
	private final RSCProtocolEncoderMain encoder = new RSCProtocolEncoderMain();

	@Override
	protected void encode(ChannelHandlerContext ctx, Packet message, List<Object> out) throws Exception {
		out.add(new BinaryWebSocketFrame(encoder.encode(ctx, message)));
	}

	@Override
	public <T> Attribute<T> attr(AttributeKey<T> attributeKey) {
		return null;
	}

	@Override
	public <T> boolean hasAttr(AttributeKey<T> attributeKey) {
		return false;
	}
}

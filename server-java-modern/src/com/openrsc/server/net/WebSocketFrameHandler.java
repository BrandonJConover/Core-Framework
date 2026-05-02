package com.openrsc.server.net;

import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.handler.codec.http.websocketx.BinaryWebSocketFrame;
import io.netty.handler.codec.http.websocketx.CloseWebSocketFrame;
import io.netty.handler.codec.http.websocketx.PingWebSocketFrame;
import io.netty.handler.codec.http.websocketx.PongWebSocketFrame;
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketServerProtocolHandler;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Locale;

public class WebSocketFrameHandler extends SimpleChannelInboundHandler<WebSocketFrame> {
	private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

	@Override
	public void userEventTriggered(ChannelHandlerContext ctx, Object evt) throws Exception {
		// If the WebSocket handshake was successful, we remove the HttpRequestHandler from the pipeline as we are no more supporting raw HTTP requests
		if (evt instanceof WebSocketServerProtocolHandler.HandshakeComplete) {
			ctx.pipeline().remove(HttpRequestHandler.class);
		} else {
			// otherwise forward to next handler
			super.userEventTriggered(ctx, evt);
		}
	}

	@Override
	protected void channelRead0(ChannelHandlerContext ctx, WebSocketFrame frame) throws Exception {
		if (frame instanceof TextWebSocketFrame textFrame) {
			String request = textFrame.text();
			LOGGER.debug("Ignoring text WebSocket frame from {}: {}", ctx.channel().remoteAddress(), request);
			ctx.channel().writeAndFlush(new TextWebSocketFrame(request.toUpperCase(Locale.US)));
		} else if (frame instanceof BinaryWebSocketFrame binframe) {
			ByteBuf buffer = binframe.content().retain();
			ctx.fireChannelRead(buffer);
		} else if (frame instanceof PingWebSocketFrame) {
			ctx.writeAndFlush(new PongWebSocketFrame(frame.content().retain()));
		} else if (frame instanceof PongWebSocketFrame) {
			LOGGER.debug("Received WebSocket pong from {}", ctx.channel().remoteAddress());
		} else if (frame instanceof CloseWebSocketFrame) {
			ctx.close();
		} else {
			String message = "unsupported frame type: " + frame.getClass().getName();
			throw new UnsupportedOperationException(message);
		}
	}
}

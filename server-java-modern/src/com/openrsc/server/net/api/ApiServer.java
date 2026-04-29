package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import com.openrsc.server.util.NamedThreadFactory;
import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.ChannelFuture;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.ChannelOption;
import io.netty.channel.ChannelPipeline;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpMethod;
import io.netty.handler.codec.http.HttpObjectAggregator;
import io.netty.handler.codec.http.HttpServerCodec;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.net.InetSocketAddress;

/**
 * Embedded HTTP/JSON listener for the modern client API. Runs on a separate
 * port from the game protocol so legacy TCP/WS handlers aren't disturbed.
 *
 * Bootstrapped from {@link Server#start()} after the game protocol is up.
 * Stopped from {@link Server#stop()} before the global shutdown.
 *
 * Routes are registered in {@link #buildRouter(Server)}; add new endpoints
 * there. Per-endpoint handler classes live next to this file.
 */
public final class ApiServer {

    private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

    /** Port the listener binds on. Reverse-proxied behind nginx in production. */
    public static final int DEFAULT_PORT = 43595;

    /** Max body size we accept. JSON requests are small; reject bodies > 1MB. */
    private static final int MAX_BODY_BYTES = 1 << 20;

    private final Server server;
    private final int port;

    private EventLoopGroup bossGroup;
    private EventLoopGroup workerGroup;
    private ChannelFuture channel;

    public ApiServer(Server server) {
        this(server, DEFAULT_PORT);
    }

    public ApiServer(Server server, int port) {
        this.server = server;
        this.port = port;
    }

    public void start() throws InterruptedException {
        HttpRouter router = buildRouter(server);

        bossGroup = new NioEventLoopGroup(
            1,
            new NamedThreadFactory(server.getName() + " : ApiBossThread", server.getConfig()));
        workerGroup = new NioEventLoopGroup(
            2,
            new NamedThreadFactory(server.getName() + " : ApiWorkerThread", server.getConfig()));

        ServerBootstrap bootstrap = new ServerBootstrap();
        bootstrap.group(bossGroup, workerGroup)
            .channel(NioServerSocketChannel.class)
            .childOption(ChannelOption.TCP_NODELAY, true)
            .childOption(ChannelOption.SO_KEEPALIVE, true)
            .childHandler(new ChannelInitializer<SocketChannel>() {
                @Override
                protected void initChannel(SocketChannel ch) {
                    ChannelPipeline p = ch.pipeline();
                    p.addLast(new HttpServerCodec());
                    p.addLast(new HttpObjectAggregator(MAX_BODY_BYTES));
                    p.addLast(new ApiRequestHandler(router));
                }
            });

        channel = bootstrap.bind(new InetSocketAddress(port)).sync();
        LOGGER.info("API listener online on port {}", port);
    }

    public void stop() {
        try {
            if (channel != null) {
                channel.channel().close().sync();
                channel = null;
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        if (workerGroup != null) {
            workerGroup.shutdownGracefully();
            workerGroup = null;
        }
        if (bossGroup != null) {
            bossGroup.shutdownGracefully();
            bossGroup = null;
        }
        LOGGER.info("API listener stopped");
    }

    /** Wires endpoint handlers into a router. Add new endpoints here. */
    private static HttpRouter buildRouter(Server server) {
        StatusEndpoint status = new StatusEndpoint(server);
        JwtUtil jwt = new JwtUtil(server.getName());
        AuthEndpoint auth = new AuthEndpoint(server, jwt);

        return new HttpRouter()
            .route(HttpMethod.GET,  "/api/status",     req -> status.handle())
            .route(HttpMethod.GET,  "/healthz",        req -> status.handle())
            .route(HttpMethod.POST, "/api/auth/login", auth::handle);
    }

    /** Single-shot dispatcher: aggregator gives us a complete request, we reply once. */
    private static final class ApiRequestHandler extends SimpleChannelInboundHandler<FullHttpRequest> {
        private final HttpRouter router;

        ApiRequestHandler(HttpRouter router) {
            this.router = router;
        }

        @Override
        protected void channelRead0(ChannelHandlerContext ctx, FullHttpRequest request) {
            FullHttpResponse response = router.dispatch(request);
            ctx.writeAndFlush(response).addListener(io.netty.channel.ChannelFutureListener.CLOSE);
        }

        @Override
        public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
            LOGGER.warn("API connection error: {}", cause.getMessage());
            ctx.close();
        }
    }
}

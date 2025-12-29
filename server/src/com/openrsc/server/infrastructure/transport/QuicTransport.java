package com.openrsc.server.infrastructure.transport;

import io.netty.bootstrap.Bootstrap;
import io.netty.channel.*;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.nio.NioDatagramChannel;
import io.netty.incubator.codec.quic.*;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.net.InetSocketAddress;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * QUIC transport implementation using Netty QUIC.
 * Provides low-latency, multiplexed connections with built-in encryption.
 */
public class QuicTransport implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(QuicTransport.class);

    private final QuicTransportSettings settings;
    private final EventLoopGroup group;
    private final QuicSslContext sslContext;
    private Channel serverChannel;

    public QuicTransport(QuicTransportSettings settings) {
        this.settings = settings;
        this.group = new NioEventLoopGroup(settings.getWorkerThreads());
        this.sslContext = createSslContext();
    }

    private QuicSslContext createSslContext() {
        try {
            return QuicSslContextBuilder.forServer(
                    settings.getCertificatePath(),
                    settings.getPrivateKeyPath())
                .applicationProtocols("openrsc/1.0")
                .build();
        } catch (Exception e) {
            LOGGER.error("Failed to create QUIC SSL context", e);
            throw new RuntimeException("Failed to initialize QUIC SSL", e);
        }
    }

    /**
     * Starts the QUIC server.
     */
    public CompletableFuture<Void> start(Consumer<QuicStreamChannel> streamHandler) {
        CompletableFuture<Void> future = new CompletableFuture<>();

        QuicServerCodecBuilder codecBuilder = new QuicServerCodecBuilder()
            .sslContext(sslContext)
            .maxIdleTimeout(settings.getIdleTimeoutMs(), TimeUnit.MILLISECONDS)
            .initialMaxData(settings.getInitialMaxData())
            .initialMaxStreamDataBidirectionalLocal(settings.getMaxStreamDataBidiLocal())
            .initialMaxStreamDataBidirectionalRemote(settings.getMaxStreamDataBidiRemote())
            .initialMaxStreamsBidirectional(settings.getMaxStreamsBidi())
            .tokenHandler(InsecureQuicTokenHandler.INSTANCE)
            .streamHandler(new ChannelInboundHandlerAdapter() {
                @Override
                public void channelActive(ChannelHandlerContext ctx) {
                    QuicStreamChannel stream = (QuicStreamChannel) ctx.channel();
                    LOGGER.debug("New QUIC stream: {}", stream.streamId());
                    streamHandler.accept(stream);
                }

                @Override
                public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
                    LOGGER.error("QUIC stream error", cause);
                    ctx.close();
                }
            });

        try {
            Bootstrap bootstrap = new Bootstrap()
                .group(group)
                .channel(NioDatagramChannel.class)
                .handler(codecBuilder.build());

            serverChannel = bootstrap.bind(
                    new InetSocketAddress(settings.getHost(), settings.getPort()))
                .sync()
                .channel();

            LOGGER.info("QUIC server started on {}:{}", settings.getHost(), settings.getPort());
            future.complete(null);
        } catch (Exception e) {
            LOGGER.error("Failed to start QUIC server", e);
            future.completeExceptionally(e);
        }

        return future;
    }

    /**
     * Creates a QUIC client connection.
     */
    public CompletableFuture<QuicChannel> connect(String host, int port) {
        CompletableFuture<QuicChannel> future = new CompletableFuture<>();

        try {
            QuicSslContext clientSslContext = QuicSslContextBuilder.forClient()
                .applicationProtocols("openrsc/1.0")
                .build();

            QuicClientCodecBuilder codecBuilder = new QuicClientCodecBuilder()
                .sslContext(clientSslContext)
                .maxIdleTimeout(settings.getIdleTimeoutMs(), TimeUnit.MILLISECONDS)
                .initialMaxData(settings.getInitialMaxData())
                .initialMaxStreamDataBidirectionalLocal(settings.getMaxStreamDataBidiLocal())
                .initialMaxStreamsBidirectional(settings.getMaxStreamsBidi());

            Bootstrap bootstrap = new Bootstrap()
                .group(group)
                .channel(NioDatagramChannel.class)
                .handler(codecBuilder.build());

            Channel channel = bootstrap.bind(0).sync().channel();

            QuicChannel.newBootstrap(channel)
                .streamHandler(new ChannelInboundHandlerAdapter())
                .remoteAddress(new InetSocketAddress(host, port))
                .connect()
                .addListener((ChannelFuture f) -> {
                    if (f.isSuccess()) {
                        future.complete((QuicChannel) f.channel());
                        LOGGER.info("Connected to QUIC server at {}:{}", host, port);
                    } else {
                        future.completeExceptionally(f.cause());
                    }
                });
        } catch (Exception e) {
            future.completeExceptionally(e);
        }

        return future;
    }

    /**
     * Creates a new stream on an existing connection.
     */
    public CompletableFuture<QuicStreamChannel> createStream(QuicChannel connection, boolean bidirectional) {
        CompletableFuture<QuicStreamChannel> future = new CompletableFuture<>();

        QuicStreamType streamType = bidirectional
            ? QuicStreamType.BIDIRECTIONAL
            : QuicStreamType.UNIDIRECTIONAL;

        connection.createStream(streamType, new ChannelInboundHandlerAdapter())
            .addListener((ChannelFuture f) -> {
                if (f.isSuccess()) {
                    future.complete((QuicStreamChannel) f.channel());
                } else {
                    future.completeExceptionally(f.cause());
                }
            });

        return future;
    }

    @Override
    public void close() {
        if (serverChannel != null) {
            serverChannel.close();
        }
        group.shutdownGracefully();
        LOGGER.info("QUIC transport closed");
    }

    /**
     * QUIC transport settings.
     */
    public static class QuicTransportSettings {
        private String host = "0.0.0.0";
        private int port = 43595;
        private int workerThreads = 4;
        private long idleTimeoutMs = 30000;
        private long initialMaxData = 10_000_000;
        private long maxStreamDataBidiLocal = 1_000_000;
        private long maxStreamDataBidiRemote = 1_000_000;
        private long maxStreamsBidi = 100;
        private String certificatePath;
        private String privateKeyPath;

        public String getHost() { return host; }
        public void setHost(String host) { this.host = host; }

        public int getPort() { return port; }
        public void setPort(int port) { this.port = port; }

        public int getWorkerThreads() { return workerThreads; }
        public void setWorkerThreads(int workerThreads) { this.workerThreads = workerThreads; }

        public long getIdleTimeoutMs() { return idleTimeoutMs; }
        public void setIdleTimeoutMs(long idleTimeoutMs) { this.idleTimeoutMs = idleTimeoutMs; }

        public long getInitialMaxData() { return initialMaxData; }
        public void setInitialMaxData(long initialMaxData) { this.initialMaxData = initialMaxData; }

        public long getMaxStreamDataBidiLocal() { return maxStreamDataBidiLocal; }
        public void setMaxStreamDataBidiLocal(long maxStreamDataBidiLocal) { this.maxStreamDataBidiLocal = maxStreamDataBidiLocal; }

        public long getMaxStreamDataBidiRemote() { return maxStreamDataBidiRemote; }
        public void setMaxStreamDataBidiRemote(long maxStreamDataBidiRemote) { this.maxStreamDataBidiRemote = maxStreamDataBidiRemote; }

        public long getMaxStreamsBidi() { return maxStreamsBidi; }
        public void setMaxStreamsBidi(long maxStreamsBidi) { this.maxStreamsBidi = maxStreamsBidi; }

        public String getCertificatePath() { return certificatePath; }
        public void setCertificatePath(String certificatePath) { this.certificatePath = certificatePath; }

        public String getPrivateKeyPath() { return privateKeyPath; }
        public void setPrivateKeyPath(String privateKeyPath) { this.privateKeyPath = privateKeyPath; }
    }
}

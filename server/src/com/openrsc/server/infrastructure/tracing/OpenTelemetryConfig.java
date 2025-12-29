package com.openrsc.server.infrastructure.tracing;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.sdk.trace.samplers.Sampler;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;

/**
 * OpenTelemetry configuration for distributed tracing.
 * Provides comprehensive tracing for game server operations.
 */
public class OpenTelemetryConfig implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(OpenTelemetryConfig.class);

    private static final String INSTRUMENTATION_NAME = "openrsc-server";

    private final OpenTelemetrySdk openTelemetry;
    private final Tracer tracer;
    private final String serviceName;

    public OpenTelemetryConfig(TracingConfig config) {
        this.serviceName = config.serviceName();

        // Build resource with service information
        Resource resource = Resource.getDefault()
            .merge(Resource.create(Attributes.of(
                AttributeKey.stringKey("service.name"), config.serviceName(),
                AttributeKey.stringKey("service.version"), config.serviceVersion(),
                AttributeKey.stringKey("deployment.environment"), config.environment(),
                AttributeKey.stringKey("host.name"), getHostName()
            )));

        // Build span exporter
        OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
            .setEndpoint(config.otlpEndpoint())
            .setTimeout(config.exportTimeoutMs(), TimeUnit.MILLISECONDS)
            .build();

        // Build span processor
        BatchSpanProcessor spanProcessor = BatchSpanProcessor.builder(spanExporter)
            .setMaxExportBatchSize(config.batchSize())
            .setMaxQueueSize(config.queueSize())
            .setScheduleDelay(config.scheduleDelayMs(), TimeUnit.MILLISECONDS)
            .build();

        // Build sampler
        Sampler sampler = config.samplingRatio() >= 1.0
            ? Sampler.alwaysOn()
            : Sampler.traceIdRatioBased(config.samplingRatio());

        // Build tracer provider
        SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
            .addSpanProcessor(spanProcessor)
            .setResource(resource)
            .setSampler(sampler)
            .build();

        // Build OpenTelemetry SDK
        this.openTelemetry = OpenTelemetrySdk.builder()
            .setTracerProvider(tracerProvider)
            .buildAndRegisterGlobal();

        this.tracer = openTelemetry.getTracer(INSTRUMENTATION_NAME, config.serviceVersion());

        LOGGER.info("OpenTelemetry initialized - exporting to {}", config.otlpEndpoint());
    }

    /**
     * Gets the tracer instance.
     */
    public Tracer getTracer() {
        return tracer;
    }

    /**
     * Starts a new span.
     */
    public Span startSpan(String name) {
        return tracer.spanBuilder(name)
            .setSpanKind(SpanKind.INTERNAL)
            .startSpan();
    }

    /**
     * Starts a new span as a child of the current span.
     */
    public Span startSpan(String name, SpanKind kind) {
        return tracer.spanBuilder(name)
            .setSpanKind(kind)
            .startSpan();
    }

    /**
     * Starts a packet processing span.
     */
    public SpanContext startPacketSpan(String opcode, String clientId) {
        Span span = tracer.spanBuilder("packet." + opcode)
            .setSpanKind(SpanKind.SERVER)
            .setAttribute("packet.opcode", opcode)
            .setAttribute("client.id", clientId)
            .startSpan();
        return new SpanContext(span, span.makeCurrent());
    }

    /**
     * Starts a player action span.
     */
    public SpanContext startPlayerSpan(String action, String username, long playerId) {
        Span span = tracer.spanBuilder("player." + action)
            .setSpanKind(SpanKind.INTERNAL)
            .setAttribute("player.action", action)
            .setAttribute("player.username", username)
            .setAttribute("player.id", playerId)
            .startSpan();
        return new SpanContext(span, span.makeCurrent());
    }

    /**
     * Starts a database operation span.
     */
    public SpanContext startDbSpan(String operation, String query) {
        Span span = tracer.spanBuilder("db." + operation)
            .setSpanKind(SpanKind.CLIENT)
            .setAttribute("db.system", "mysql")
            .setAttribute("db.operation", operation)
            .setAttribute("db.statement", sanitizeQuery(query))
            .startSpan();
        return new SpanContext(span, span.makeCurrent());
    }

    /**
     * Starts a game tick span.
     */
    public SpanContext startGameTickSpan(long tickNumber) {
        Span span = tracer.spanBuilder("game.tick")
            .setSpanKind(SpanKind.INTERNAL)
            .setAttribute("game.tick_number", tickNumber)
            .startSpan();
        return new SpanContext(span, span.makeCurrent());
    }

    /**
     * Executes an operation within a span.
     */
    public <T> T trace(String name, Supplier<T> operation) {
        Span span = startSpan(name);
        try (Scope ignored = span.makeCurrent()) {
            T result = operation.get();
            span.setStatus(StatusCode.OK);
            return result;
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    /**
     * Executes an operation within a span (no return value).
     */
    public void trace(String name, Runnable operation) {
        Span span = startSpan(name);
        try (Scope ignored = span.makeCurrent()) {
            operation.run();
            span.setStatus(StatusCode.OK);
        } catch (Exception e) {
            span.setStatus(StatusCode.ERROR, e.getMessage());
            span.recordException(e);
            throw e;
        } finally {
            span.end();
        }
    }

    /**
     * Sanitizes a query to remove sensitive data.
     */
    private String sanitizeQuery(String query) {
        if (query == null) return "";
        // Remove potential sensitive data patterns
        return query.replaceAll("password\\s*=\\s*'[^']*'", "password='***'")
            .replaceAll("'\\d{13,19}'", "'[CARD_MASKED]'");
    }

    private String getHostName() {
        try {
            return java.net.InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "unknown";
        }
    }

    @Override
    public void close() {
        openTelemetry.close();
        LOGGER.info("OpenTelemetry shutdown complete");
    }

    /**
     * Span context wrapper for proper cleanup.
     */
    public static class SpanContext implements AutoCloseable {
        private final Span span;
        private final Scope scope;

        public SpanContext(Span span, Scope scope) {
            this.span = span;
            this.scope = scope;
        }

        public Span getSpan() {
            return span;
        }

        public void setSuccess() {
            span.setStatus(StatusCode.OK);
        }

        public void setError(String message) {
            span.setStatus(StatusCode.ERROR, message);
        }

        public void recordException(Throwable e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, e.getMessage());
        }

        public void setAttribute(String key, String value) {
            span.setAttribute(key, value);
        }

        public void setAttribute(String key, long value) {
            span.setAttribute(key, value);
        }

        public void setAttribute(String key, boolean value) {
            span.setAttribute(key, value);
        }

        @Override
        public void close() {
            scope.close();
            span.end();
        }
    }

    /**
     * Tracing configuration record.
     */
    public record TracingConfig(
        String serviceName,
        String serviceVersion,
        String environment,
        String otlpEndpoint,
        double samplingRatio,
        int exportTimeoutMs,
        int batchSize,
        int queueSize,
        int scheduleDelayMs
    ) {
        public static TracingConfig defaults() {
            return new TracingConfig(
                "openrsc-server",
                "2.0.0",
                "development",
                "http://localhost:4317",
                1.0,
                10000,
                512,
                2048,
                5000
            );
        }
    }
}

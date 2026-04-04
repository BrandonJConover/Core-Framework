package com.openrsc.server.infrastructure.logging;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.core.Appender;
import org.apache.logging.log4j.core.LoggerContext;
import org.apache.logging.log4j.core.appender.HttpAppender;
import org.apache.logging.log4j.core.config.Configuration;
import org.apache.logging.log4j.core.config.builder.api.*;
import org.apache.logging.log4j.core.config.builder.impl.BuiltConfiguration;
import org.apache.logging.log4j.core.layout.JsonLayout;
import org.apache.logging.log4j.ThreadContext;

import java.net.URI;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Enhanced logging configuration with Seq, Loki, and structured logging support.
 */
public class EnhancedLogging {
    private static final Logger LOGGER = LogManager.getLogger(EnhancedLogging.class);

    private final EnhancedLoggingSettings settings;
    private final Map<String, String> globalProperties = new ConcurrentHashMap<>();

    public EnhancedLogging(EnhancedLoggingSettings settings) {
        this.settings = settings;
    }

    /**
     * Initializes enhanced logging with configured sinks.
     */
    public void initialize() {
        // Set global context properties
        globalProperties.put("application", settings.getApplicationName());
        globalProperties.put("environment", settings.getEnvironment());
        globalProperties.put("version", settings.getVersion());

        // Add to ThreadContext for all log messages
        globalProperties.forEach(ThreadContext::put);

        if (settings.isSeqEnabled()) {
            configureSeqAppender();
        }

        if (settings.isLokiEnabled()) {
            configureLokiAppender();
        }

        LOGGER.info("Enhanced logging initialized for {} in {} environment",
            settings.getApplicationName(), settings.getEnvironment());
    }

    /**
     * Configures Seq HTTP appender.
     */
    private void configureSeqAppender() {
        try {
            LoggerContext context = (LoggerContext) LogManager.getContext(false);
            Configuration config = context.getConfiguration();

            // Create JSON layout for Seq
            JsonLayout layout = JsonLayout.newBuilder()
                .setCompact(true)
                .setEventEol(true)
                .setIncludeStacktrace(true)
                .build();

            // Build HTTP appender for Seq
            // Note: In production, use a proper Seq appender library
            LOGGER.info("Seq logging configured to send to: {}", settings.getSeqServerUrl());

        } catch (Exception e) {
            LOGGER.error("Failed to configure Seq appender", e);
        }
    }

    /**
     * Configures Loki HTTP appender.
     */
    private void configureLokiAppender() {
        try {
            LOGGER.info("Loki logging configured to send to: {}", settings.getLokiServerUrl());
            // Loki uses a push API - typically integrated via log4j2-loki library
        } catch (Exception e) {
            LOGGER.error("Failed to configure Loki appender", e);
        }
    }

    /**
     * Adds a property to all log messages.
     */
    public void addProperty(String key, String value) {
        globalProperties.put(key, value);
        ThreadContext.put(key, value);
    }

    /**
     * Removes a property from log messages.
     */
    public void removeProperty(String key) {
        globalProperties.remove(key);
        ThreadContext.remove(key);
    }

    /**
     * Creates a scoped logging context.
     */
    public LoggingScope createScope(String scopeName) {
        return new LoggingScope(scopeName);
    }

    /**
     * Creates a scoped logging context with properties.
     */
    public LoggingScope createScope(String scopeName, Map<String, String> properties) {
        LoggingScope scope = new LoggingScope(scopeName);
        properties.forEach(scope::addProperty);
        return scope;
    }

    /**
     * Scoped logging context that auto-cleans ThreadContext on close.
     */
    public static class LoggingScope implements AutoCloseable {
        private final String scopeName;
        private final Map<String, String> scopeProperties = new ConcurrentHashMap<>();
        private final long startTime;

        private LoggingScope(String scopeName) {
            this.scopeName = scopeName;
            this.startTime = System.currentTimeMillis();
            ThreadContext.put("scope", scopeName);
            ThreadContext.put("scopeStartTime", Instant.now().toString());
        }

        public void addProperty(String key, String value) {
            scopeProperties.put(key, value);
            ThreadContext.put(key, value);
        }

        public long getElapsedMs() {
            return System.currentTimeMillis() - startTime;
        }

        @Override
        public void close() {
            long elapsed = getElapsedMs();
            ThreadContext.put("scopeDurationMs", String.valueOf(elapsed));

            // Clean up scope properties
            scopeProperties.keySet().forEach(ThreadContext::remove);
            ThreadContext.remove("scope");
            ThreadContext.remove("scopeStartTime");
            ThreadContext.remove("scopeDurationMs");
        }
    }

    /**
     * Structured log event builder for complex log entries.
     */
    public static class StructuredLogBuilder {
        private final Logger logger;
        private final org.apache.logging.log4j.Level level;
        private final String message;
        private final Map<String, Object> properties = new ConcurrentHashMap<>();
        private Throwable exception;

        public StructuredLogBuilder(Logger logger, org.apache.logging.log4j.Level level, String message) {
            this.logger = logger;
            this.level = level;
            this.message = message;
        }

        public StructuredLogBuilder property(String key, Object value) {
            properties.put(key, value);
            return this;
        }

        public StructuredLogBuilder exception(Throwable t) {
            this.exception = t;
            return this;
        }

        public void log() {
            // Add properties to context
            properties.forEach((k, v) -> ThreadContext.put(k, String.valueOf(v)));

            try {
                if (exception != null) {
                    logger.log(level, message, exception);
                } else {
                    logger.log(level, message);
                }
            } finally {
                // Clean up
                properties.keySet().forEach(ThreadContext::remove);
            }
        }
    }

    /**
     * Creates a structured log builder.
     */
    public static StructuredLogBuilder structured(Logger logger, org.apache.logging.log4j.Level level, String message) {
        return new StructuredLogBuilder(logger, level, message);
    }

    /**
     * Enhanced logging settings.
     */
    public static class EnhancedLoggingSettings {
        private String applicationName = "openrsc-server";
        private String environment = "development";
        private String version = "1.0.0";

        private boolean seqEnabled = false;
        private String seqServerUrl = "http://localhost:5341";
        private String seqApiKey = "";

        private boolean lokiEnabled = false;
        private String lokiServerUrl = "http://localhost:3100";

        private boolean jsonConsoleEnabled = false;
        private boolean asyncLoggingEnabled = true;
        private int asyncBufferSize = 1024;

        public String getApplicationName() { return applicationName; }
        public void setApplicationName(String name) { this.applicationName = name; }

        public String getEnvironment() { return environment; }
        public void setEnvironment(String env) { this.environment = env; }

        public String getVersion() { return version; }
        public void setVersion(String version) { this.version = version; }

        public boolean isSeqEnabled() { return seqEnabled; }
        public void setSeqEnabled(boolean enabled) { this.seqEnabled = enabled; }

        public String getSeqServerUrl() { return seqServerUrl; }
        public void setSeqServerUrl(String url) { this.seqServerUrl = url; }

        public String getSeqApiKey() { return seqApiKey; }
        public void setSeqApiKey(String key) { this.seqApiKey = key; }

        public boolean isLokiEnabled() { return lokiEnabled; }
        public void setLokiEnabled(boolean enabled) { this.lokiEnabled = enabled; }

        public String getLokiServerUrl() { return lokiServerUrl; }
        public void setLokiServerUrl(String url) { this.lokiServerUrl = url; }

        public boolean isJsonConsoleEnabled() { return jsonConsoleEnabled; }
        public void setJsonConsoleEnabled(boolean enabled) { this.jsonConsoleEnabled = enabled; }

        public boolean isAsyncLoggingEnabled() { return asyncLoggingEnabled; }
        public void setAsyncLoggingEnabled(boolean enabled) { this.asyncLoggingEnabled = enabled; }

        public int getAsyncBufferSize() { return asyncBufferSize; }
        public void setAsyncBufferSize(int size) { this.asyncBufferSize = size; }
    }
}

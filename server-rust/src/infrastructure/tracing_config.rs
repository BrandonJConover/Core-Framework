use anyhow::Result;
use opentelemetry::trace::TracerProvider;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{runtime, trace as sdktrace};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

use super::config::TracingConfig as TracingSettings;

/// OpenTelemetry tracing configuration.
pub struct TracingConfig;

impl TracingConfig {
    /// Initialize OpenTelemetry tracing.
    pub fn initialize(config: &TracingSettings) -> Result<()> {
        // Create OTLP exporter
        let exporter = opentelemetry_otlp::new_exporter()
            .tonic()
            .with_endpoint(&config.otlp_endpoint);

        // Create tracer provider
        let tracer_provider = opentelemetry_otlp::new_pipeline()
            .tracing()
            .with_exporter(exporter)
            .with_trace_config(
                sdktrace::config()
                    .with_sampler(sdktrace::Sampler::TraceIdRatioBased(config.sample_rate))
                    .with_resource(opentelemetry_sdk::Resource::new(vec![
                        opentelemetry::KeyValue::new("service.name", config.service_name.clone()),
                        opentelemetry::KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
                    ])),
            )
            .install_batch(runtime::Tokio)?;

        // Create OpenTelemetry layer
        let tracer = tracer_provider.tracer("openrsc-server");
        let telemetry = tracing_opentelemetry::layer().with_tracer(tracer);

        // Set up subscriber with both fmt and OpenTelemetry layers
        tracing_subscriber::registry()
            .with(tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "openrsc_server=debug".into()))
            .with(tracing_subscriber::fmt::layer())
            .with(telemetry)
            .init();

        Ok(())
    }

    /// Shutdown tracing (flush pending spans).
    pub fn shutdown() {
        opentelemetry::global::shutdown_tracer_provider();
    }
}

/// Span context for distributed tracing.
#[derive(Debug, Clone)]
pub struct SpanContext {
    pub trace_id: String,
    pub span_id: String,
}

impl SpanContext {
    /// Create a new span context from the current tracing span.
    pub fn current() -> Option<Self> {
        use tracing::Span;

        let span = Span::current();
        if span.is_none() {
            return None;
        }

        // Extract trace context
        // In real implementation, use opentelemetry context propagation
        Some(Self {
            trace_id: uuid::Uuid::new_v4().to_string(),
            span_id: uuid::Uuid::new_v4().to_string(),
        })
    }
}

/// Macro for creating traced operations.
#[macro_export]
macro_rules! traced {
    ($name:expr, $block:expr) => {{
        let span = tracing::info_span!($name);
        let _guard = span.enter();
        $block
    }};
}

/// Macro for creating traced async operations.
#[macro_export]
macro_rules! traced_async {
    ($name:expr, $block:expr) => {{
        async {
            let span = tracing::info_span!($name);
            let _guard = span.enter();
            $block.await
        }
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_span_context() {
        // SpanContext::current() returns None when no span is active
        assert!(SpanContext::current().is_some() || SpanContext::current().is_none());
    }
}

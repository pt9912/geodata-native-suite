import os
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.sdk.trace.export import SpanExportResult
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.instrumentation.celery import CeleryInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.boto3sqs import Boto3SQSInstrumentor
#from opentelemetry.instrumentation.boto3sqs import AioBoto3Instrumentor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace.sampling import ParentBasedTraceIdRatio

def init_tracing(app=None):
    # Ressourcen-Attribute
    resource = Resource.create({
        "service.name": os.getenv("OTEL_SERVICE_NAME", "index-service"),
        "service.version": os.getenv("APP_VERSION", "1.0.0"),
        "deployment.environment": os.getenv("ENV", "production"),
    })

    # Tracer Provider mit Sampling
    trace.set_tracer_provider(
        TracerProvider(
            resource=resource,
            sampler=ParentBasedTraceIdRatio(
                float(os.getenv("OTEL_TRACES_SAMPLE_RATE", "0.1"))
            )
        )
    )

    # OTLP Exporter (gRPC)
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")
    otlp_span_exporter = OTLPSpanExporter(
        endpoint=otlp_endpoint,
        insecure=True,  # Für lokale Entwicklung; in Produktion mit TLS
        timeout=10,     # Timeout in Sekunden
    )

    # Span Processor mit Fehlerbehandlung
    class SafeBatchSpanProcessor(BatchSpanProcessor):
        def on_end(self, span):
            try:
                super().on_end(span)
            except Exception as e:
                print(f"Failed to export span: {e}")

    trace.get_tracer_provider().add_span_processor(
        SafeBatchSpanProcessor(
            otlp_span_exporter,
            schedule_delay_millis=5000,  # Alle 5 Sekunden senden
            max_export_batch_size=50,    # Max. 50 Spans pro Batch
        )
    )

    # Optional: ConsoleSpanExporter für lokale Entwicklung
    if os.getenv("ENV") == "development":
        trace.get_tracer_provider().add_span_processor(
            BatchSpanProcessor(ConsoleSpanExporter())
        )


    # Metriken-Exporter (OTLP für Produktion, Prometheus für Entwicklung)
    if os.getenv("ENV") == "development":
        metrics_reader = PeriodicExportingMetricReader(
            PrometheusMetricReader(),
            export_interval_millis=int(os.getenv("OTEL_METRIC_EXPORT_INTERVAL_MS", "5000"))
        )
    else:
        otlp_metric_exporter = OTLPMetricExporter(
            endpoint=otlp_endpoint,
            insecure=True,
        )
        metrics_reader = PeriodicExportingMetricReader(
            otlp_metric_exporter,
            export_interval_millis=int(os.getenv("OTEL_METRIC_EXPORT_INTERVAL_MS", "5000"))
        )
        
    # Instrumentierung
    CeleryInstrumentor().instrument()
    RedisInstrumentor().instrument()
    Boto3SQSInstrumentor().instrument()
#    AioBoto3Instrumentor().instrument()
    if app:
        FastAPIInstrumentor.instrument_app(app)

    # Metriken-Provider
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[metrics_reader]))


    return trace.get_tracer(__name__)

# Initialisierung
tracer = init_tracing()

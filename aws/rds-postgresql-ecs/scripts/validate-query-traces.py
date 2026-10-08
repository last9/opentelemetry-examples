"""Validation only: real database spans, scoped propagation and connection reuse."""

import os
from concurrent.futures import ThreadPoolExecutor
from threading import Timer

import psycopg
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
from psycopg.pq import TransactionStatus


def query(connection, tracer, sql, parameters=None, cancel=False):
    # Own the transaction: SET LOCAL would leak until commit in an outer transaction.
    if not connection.autocommit or connection.info.transaction_status != TransactionStatus.IDLE:
        raise ValueError("Validation wrapper requires an idle autocommit connection")
    original = connection.execute("SHOW application_name").fetchone()[0]
    timer = None
    try:
        with tracer.start_as_current_span(
            "postgresql.query", kind=trace.SpanKind.CLIENT,
            attributes={"db.system.name": "postgresql", "db.system": "postgresql",
                        "db.namespace": connection.info.dbname,
                        "server.address": connection.info.host, "net.peer.name": connection.info.host,
                        "server.port": connection.info.port,
                        "db.query.text": sql},
        ):
            carrier = {}
            TraceContextTextMapPropagator().inject(carrier)
            with connection.transaction():
                connection.execute("SELECT set_config('application_name', %s, true)", (carrier["traceparent"],))
                assert connection.execute("SHOW application_name").fetchone()[0] == carrier["traceparent"]
                if cancel:
                    timer = Timer(0.2, connection.cancel)
                    timer.start()
                connection.execute(sql, parameters)
            return carrier["traceparent"]
    finally:
        if timer:
            timer.cancel()
            timer.join()
        if connection.info.transaction_status != TransactionStatus.IDLE:
            connection.close()
            raise AssertionError("Connection did not return to idle")
        if connection.execute("SHOW application_name").fetchone()[0] != original:
            connection.close()
            raise AssertionError("Trace context leaked across connection reuse")


def connect():
    return psycopg.connect(
        host=os.environ["PG_ENDPOINT"], port=os.environ.get("PG_PORT", "5432"),
        dbname=os.environ["PG_DATABASE"], user=os.environ["PG_USERNAME"],
        password=os.environ["PG_PASSWORD"], sslmode="verify-full",
        sslrootcert=os.environ["PG_CA_FILE"], autocommit=True,
        application_name="fde372-trace-validation",
    )


def concurrent_query(tracer):
    with connect() as connection:
        return query(connection, tracer, "SELECT pg_sleep(%s)", (8,))


def main():
    if not os.environ["PG_DATABASE"].startswith("fde372_"):
        raise ValueError("Use an isolated fde372_ validation database")
    if not os.environ.get("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"):
        raise ValueError("Set an explicit OTLP traces endpoint for validation")
    recorded = InMemorySpanExporter()
    provider = TracerProvider(resource=Resource.create({"service.name": "fde372-postgres-validation"}))
    provider.add_span_processor(SimpleSpanProcessor(recorded))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    tracer = provider.get_tracer("fde372.postgresql.validation")
    try:
        with connect() as connection:
            query(connection, tracer, "SELECT 1")
            try:
                query(connection, tracer, "SELECT 1 / 0")
                raise AssertionError("Expected database error")
            except psycopg.errors.DivisionByZero:
                pass
            try:
                query(connection, tracer, "SELECT pg_sleep(8)", cancel=True)
                raise AssertionError("Expected cancellation")
            except psycopg.errors.QueryCanceled:
                pass
            query(connection, tracer, "SELECT 1")
        with ThreadPoolExecutor(max_workers=2) as pool:
            carriers = list(pool.map(concurrent_query, [tracer, tracer]))
        assert len(set(carriers)) == 2, "Concurrent queries shared trace context"
        spans = recorded.get_finished_spans()
        assert len(spans) == 6 and all(span.context.is_valid for span in spans)
        assert len({span.context.trace_id for span in spans}) == 6
        assert provider.force_flush(), "Trace export did not flush"
        print("PASS: 6 genuine SDK spans; concurrency and reset after success/error/cancellation")
    finally:
        provider.shutdown()


if __name__ == "__main__":
    main()

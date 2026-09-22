import asyncio
import unittest
from unittest.mock import AsyncMock, patch

import app
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.exporter = InMemorySpanExporter()
        self.provider = TracerProvider()
        self.provider.add_span_processor(SimpleSpanProcessor(self.exporter))
        self.tracer = patch.object(
            app.trace,
            "get_tracer",
            return_value=self.provider.get_tracer("test"),
        )
        self.tracer.start()
        self.addCleanup(self.tracer.stop)
        self.addCleanup(self.provider.shutdown)

    def recorded(self):
        spans = self.exporter.get_finished_spans()
        self.assertEqual(len(spans), 1)
        return repr(dict(spans[0].attributes)) + repr(
            [dict(event.attributes) for event in spans[0].events]
        )

    def test_query_is_removed_and_upgrade_span_ends(self):
        socket = object()
        with patch.object(app.websockets, "connect", AsyncMock(return_value=socket)):
            self.assertIs(
                asyncio.run(
                    app.connect_websocket(
                        "wss://example.invalid/socket?token=synthetic-secret"
                    )
                ),
                socket,
            )
        self.assertNotIn("synthetic-secret", self.recorded())
        self.assertEqual(
            self.exporter.get_finished_spans()[0].attributes["http.status_code"], 101
        )

    def test_basic_auth_is_not_exported(self):
        with patch.object(app.websockets, "connect", AsyncMock(return_value=object())):
            asyncio.run(
                app.connect_websocket(
                    "wss://alice:synthetic-secret@example.invalid/socket"
                )
            )
        self.assertNotIn("synthetic-secret", self.recorded())

    def test_invalid_uri_does_not_export_query_secret(self):
        with self.assertRaises(app.websockets.exceptions.InvalidURI):
            asyncio.run(
                app.connect_websocket(
                    "wss://example.invalid/socket?token=synthetic-secret#fragment"
                )
            )
        self.assertNotIn("synthetic-secret", self.recorded())


if __name__ == "__main__":
    unittest.main()

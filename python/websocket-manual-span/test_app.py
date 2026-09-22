from app import sanitized_url


assert (
    sanitized_url("wss://example.com/stream?token=secret#fragment")
    == "wss://example.com/stream"
)


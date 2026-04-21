"""
Fake OTLP HTTP server that half-closes mid-request to force
RemoteDisconnected on the client. Deterministic repro.

Behavior: accept POST, read headers, send FIN (close write side) without
response body. Client sees 'Remote end closed connection without response'.

Run: python flaky_server.py
Point exporter at: http://localhost:4319/v1/traces
"""
import socket
import threading

HOST, PORT = "127.0.0.1", 4319
counter = {"n": 0}
lock = threading.Lock()


def handle(conn: socket.socket, addr):
    with lock:
        counter["n"] += 1
        n = counter["n"]
    try:
        # Drain request headers
        data = b""
        conn.settimeout(5)
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        # Every 2nd request: close without responding (RemoteDisconnected)
        if n % 2 == 0:
            print(f"[{n}] half-close — dropping connection")
            conn.shutdown(socket.SHUT_RDWR)
        else:
            print(f"[{n}] ok → 200")
            conn.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: application/x-protobuf\r\n"
                b"Content-Length: 0\r\n"
                b"Connection: keep-alive\r\n\r\n"
            )
    except Exception as e:
        print(f"[{n}] err {e}")
    finally:
        conn.close()


def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(16)
    print(f"flaky OTLP on {HOST}:{PORT}")
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()

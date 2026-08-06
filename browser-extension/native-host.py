#!/usr/bin/env python3

import argparse
import fcntl
import json
import os
import queue
import signal
import socket
import struct
import sys
import threading
import time
import uuid
from pathlib import Path

MAX_NATIVE_MESSAGE_BYTES = 16 * 1024 * 1024
MAX_CLIENT_MESSAGE_BYTES = 64 * 1024
ACTIVATION_TIMEOUT_SECONDS = 5


def runtime_paths() -> tuple[Path, Path, Path, Path]:
    runtime_root = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_root:
        raise RuntimeError("XDG_RUNTIME_DIR is not set")

    state_dir = Path(runtime_root) / "desktop-shell"
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(state_dir, 0o700)
    return (
        state_dir / "browser-tabs.json",
        state_dir / "browser-tabs.sock",
        state_dir / "browser-tabs.lock",
        state_dir,
    )


def encode_json(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def read_exact(stream, length: int) -> bytes | None:
    chunks: list[bytes] = []
    remaining = length
    while remaining > 0:
        chunk = stream.read(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def read_native_message() -> dict | None:
    header = read_exact(sys.stdin.buffer, 4)
    if header is None:
        return None

    length = struct.unpack("@I", header)[0]
    if length > MAX_NATIVE_MESSAGE_BYTES:
        raise RuntimeError(f"native message is too large: {length} bytes")

    payload = read_exact(sys.stdin.buffer, length)
    if payload is None:
        raise RuntimeError("native message ended before its declared length")
    value = json.loads(payload.decode("utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("native message must be a JSON object")
    return value


def read_client_message(client: socket.socket) -> dict:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = client.recv(4096)
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
        if total > MAX_CLIENT_MESSAGE_BYTES:
            raise RuntimeError("client message is too large")
        if b"\n" in chunk:
            break

    raw = b"".join(chunks).split(b"\n", 1)[0]
    if not raw:
        raise RuntimeError("client sent an empty request")
    value = json.loads(raw.decode("utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("client request must be a JSON object")
    return value


def send_client_message(client: socket.socket, value: object) -> None:
    client.sendall(encode_json(value) + b"\n")


class BrowserTabBridge:
    def __init__(self) -> None:
        self.state_path, self.socket_path, self.lock_path, _ = runtime_paths()
        self.session = uuid.uuid4().hex
        self.generated_at = 0
        self.tabs: list[dict] = []
        self.stop_event = threading.Event()
        self.stdout_lock = threading.Lock()
        self.pending_lock = threading.Lock()
        self.pending: dict[str, queue.Queue] = {}
        self.server_socket: socket.socket | None = None
        self.lock_file = self.lock_path.open("a+b")

    def acquire(self) -> None:
        try:
            fcntl.flock(self.lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("another desktop-shell browser bridge is already running") from error

    def write_native(self, value: object) -> None:
        payload = encode_json(value)
        with self.stdout_lock:
            sys.stdout.buffer.write(struct.pack("@I", len(payload)))
            sys.stdout.buffer.write(payload)
            sys.stdout.buffer.flush()

    def write_snapshot(self) -> None:
        value = {
            "version": 1,
            "session": self.session,
            "connected": True,
            "generatedAt": self.generated_at,
            "tabs": self.tabs,
        }
        temporary_path = self.state_path.with_name(
            f".{self.state_path.name}.{os.getpid()}.tmp"
        )
        descriptor = os.open(
            temporary_path,
            os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
            0o600,
        )
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(encode_json(value))
                stream.write(b"\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary_path, self.state_path)
        finally:
            if temporary_path.exists():
                temporary_path.unlink()

    def handle_native_message(self, message: dict) -> None:
        message_type = message.get("type")
        if message_type == "snapshot":
            tabs = message.get("tabs")
            if not isinstance(tabs, list):
                raise RuntimeError("snapshot tabs must be an array")
            self.tabs = [tab for tab in tabs if isinstance(tab, dict)]
            self.generated_at = int(message.get("generatedAt") or time.time() * 1000)
            self.write_snapshot()
            return

        if message_type == "activateResult":
            request_id = str(message.get("requestId") or "")
            with self.pending_lock:
                waiter = self.pending.get(request_id)
            if waiter is not None:
                waiter.put(message)

    def activate(self, request: dict) -> dict:
        if request.get("session") != self.session:
            return {"ok": False, "error": "stale browser tab session"}

        try:
            tab_id = int(request["tabId"])
            window_id = int(request["windowId"])
        except (KeyError, TypeError, ValueError):
            return {"ok": False, "error": "tabId and windowId must be integers"}

        request_id = uuid.uuid4().hex
        waiter: queue.Queue = queue.Queue(maxsize=1)
        with self.pending_lock:
            self.pending[request_id] = waiter

        try:
            self.write_native(
                {
                    "type": "activate",
                    "requestId": request_id,
                    "tabId": tab_id,
                    "windowId": window_id,
                }
            )
            try:
                result = waiter.get(timeout=ACTIVATION_TIMEOUT_SECONDS)
            except queue.Empty:
                return {"ok": False, "error": "browser activation timed out"}
            return {
                "ok": bool(result.get("ok")),
                "error": str(result.get("error") or ""),
            }
        finally:
            with self.pending_lock:
                self.pending.pop(request_id, None)

    def handle_client(self, client: socket.socket) -> None:
        with client:
            client.settimeout(ACTIVATION_TIMEOUT_SECONDS + 1)
            try:
                request = read_client_message(client)
                command = request.get("command")
                if command == "activate":
                    response = self.activate(request)
                else:
                    response = {"ok": False, "error": "unknown browser bridge command"}
            except Exception as error:
                response = {"ok": False, "error": str(error)}
            send_client_message(client, response)

    def open_server(self) -> None:
        if self.socket_path.exists():
            self.socket_path.unlink()

        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket = server
        server.bind(str(self.socket_path))
        os.chmod(self.socket_path, 0o600)
        server.listen(4)
        server.settimeout(0.5)

    def serve_clients(self) -> None:
        server = self.server_socket
        if server is None:
            return

        while not self.stop_event.is_set():
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(
                target=self.handle_client,
                args=(client,),
                daemon=True,
            ).start()

    def run(self) -> None:
        self.acquire()
        server_thread = None
        try:
            self.open_server()
            self.generated_at = int(time.time() * 1000)
            self.write_snapshot()
            server_thread = threading.Thread(target=self.serve_clients, daemon=True)
            server_thread.start()

            while not self.stop_event.is_set():
                message = read_native_message()
                if message is None:
                    break
                self.handle_native_message(message)
        finally:
            self.stop_event.set()
            if self.server_socket is not None:
                self.server_socket.close()
            if server_thread is not None:
                server_thread.join(timeout=1)
            self.cleanup()

    def cleanup(self) -> None:
        if self.socket_path.exists():
            self.socket_path.unlink()

        try:
            state = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            state = {}
        if state.get("session") == self.session and self.state_path.exists():
            self.state_path.unlink()

        fcntl.flock(self.lock_file.fileno(), fcntl.LOCK_UN)
        self.lock_file.close()


def client_activate(session: str, tab_id: int, window_id: int) -> int:
    _, socket_path, _, _ = runtime_paths()
    request = {
        "command": "activate",
        "session": session,
        "tabId": tab_id,
        "windowId": window_id,
    }

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(ACTIVATION_TIMEOUT_SECONDS + 1)
    try:
        client.connect(str(socket_path))
        send_client_message(client, request)
        response = read_client_message(client)
    except (FileNotFoundError, ConnectionRefusedError, socket.timeout, OSError) as error:
        print(f"browser bridge unavailable: {error}", file=sys.stderr)
        return 1
    finally:
        client.close()

    if response.get("ok"):
        return 0
    print(str(response.get("error") or "browser activation failed"), file=sys.stderr)
    return 1


def parse_client_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["activate"])
    parser.add_argument("session")
    parser.add_argument("tab_id", type=int)
    parser.add_argument("window_id", type=int)
    return parser.parse_args()


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "activate":
        args = parse_client_args()
        return client_activate(args.session, args.tab_id, args.window_id)

    # Firefox appends the native manifest path and extension ID. They are
    # transport metadata, not commands for this host.
    bridge = BrowserTabBridge()

    def stop_bridge(_signal_number, _frame) -> None:
        bridge.stop_event.set()

    signal.signal(signal.SIGTERM, stop_bridge)
    signal.signal(signal.SIGINT, stop_bridge)
    bridge.run()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"desktop-shell browser bridge: {error}", file=sys.stderr)
        raise SystemExit(1)

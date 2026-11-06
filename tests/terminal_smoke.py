"""Runs inside the container, against toolbox-terminal started by tests/smoke.sh."""

import asyncio
import json
import os
import pathlib
import time

from tornado.httpclient import AsyncHTTPClient, HTTPRequest
from tornado.websocket import websocket_connect

BASE = "127.0.0.1:8888/console"
SESSIONS = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"toolbox-terminal-{os.getuid()}"


async def wait_for_server():
    client = AsyncHTTPClient()
    for _ in range(120):
        try:
            await client.fetch(f"http://{BASE}/healthz")
            return
        except OSError:
            await asyncio.sleep(0.5)
    raise AssertionError("terminal did not start")


async def read_until(connection, marker, timeout=30):
    output = ""
    deadline = time.monotonic() + timeout
    while marker not in output:
        message = await asyncio.wait_for(connection.read_message(), deadline - time.monotonic())
        if message is None:
            raise AssertionError(f"socket closed before {marker!r}; got {output!r}")
        kind, *data = json.loads(message)
        if kind == "stdout":
            output += data[0]
    return output


async def run_in_shell(connection, command, marker):
    await connection.write_message(json.dumps(["stdin", command + "\n"]))
    return await read_until(connection, marker)


async def session_homes_after(expected, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        homes = list(SESSIONS.glob("session-*"))
        if len(homes) == expected:
            return homes
        await asyncio.sleep(0.25)
    raise AssertionError(f"expected {expected} session directories, found {list(SESSIONS.glob('session-*'))}")


async def main():
    await wait_for_server()
    client = AsyncHTTPClient()

    page = await client.fetch(f"http://{BASE}/")
    body = page.body.decode()
    assert "SMOKE" in body and "vendor/xterm.js" in body, body
    assert "Content-Security-Policy" in page.headers
    for asset in ("vendor/xterm.js", "vendor/xterm.css", "vendor/addon-fit.js", "terminal.js", "terminal.css"):
        await client.fetch(f"http://{BASE}/static/{asset}")

    url = f"ws://{BASE}/websocket"
    first = await websocket_connect(url)
    second = await websocket_connect(url)
    await run_in_shell(first, 'echo "sum=$((40+2))"', "sum=42")
    await run_in_shell(first, "echo first > $HOME/marker; echo wrote-$?", "wrote-0")
    # Each marker appears only in a command's output, never in the shell's echo of the command.
    await run_in_shell(second, "test -e $HOME/marker; echo isolated-$?", "isolated-1")
    await run_in_shell(second, "echo colors-$(tput colors)", "colors-256")
    await run_in_shell(second, "printf 'ğüş%s\\n' iöç-ok", "ğüşiöç-ok")
    await session_homes_after(2)

    # The limit is two sessions, so a third is refused.
    third = await websocket_connect(url)
    assert await asyncio.wait_for(third.read_message(), 15) is None
    assert third.close_code == 1013, third.close_code

    # A page on another origin must not be able to open a shell.
    foreign = HTTPRequest(url, headers={"Origin": "https://attacker.example"})
    try:
        await websocket_connect(foreign)
    except Exception as error:
        assert getattr(error, "code", None) == 403, error
    else:
        raise AssertionError("cross-origin WebSocket was accepted")

    # Closing a socket ends its shell and removes its HOME.
    first.close()
    second.close()
    await session_homes_after(0)
    print("terminal smoke test passed")


asyncio.run(main())

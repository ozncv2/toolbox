"""Browser terminal: every WebSocket connection gets its own shell.

There is no authentication here. Keep the default localhost bind and put an
authenticating reverse proxy in front of this server. Anyone who can reach it
gets a shell with the container's permissions.
"""

import asyncio
from dataclasses import dataclass
import logging
import os
from pathlib import Path
import re
import shutil
import signal
import tempfile
import time

from terminado import TermSocket, UniqueTermManager
from terminado.management import MaxTerminalsReached
from tornado.ioloop import PeriodicCallback
from tornado.web import Application, RedirectHandler, RequestHandler

ROOT = Path(__file__).parent
LOG = logging.getLogger("toolbox-terminal")
TONES = ("neutral", "warning", "danger")
CONTENT_SECURITY_POLICY = (
    "default-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws: wss:; "
    "frame-ancestors 'self'; base-uri 'none'"
)


@dataclass(frozen=True)
class Config:
    bind: str
    port: int
    prefix: str
    shell: str
    title: str
    label: str
    tone: str
    max_sessions: int
    idle_seconds: int
    ephemeral_home: bool


def load_config():
    def setting(name, default):
        return os.environ.get(f"TOOLBOX_TERMINAL_{name}", default)

    prefix = setting("PREFIX", "").strip("/")
    tone = os.environ.get("TOOLBOX_ENV_TONE", "neutral")
    return Config(
        bind=setting("BIND", "127.0.0.1"),
        port=int(setting("PORT", "8888")),
        prefix=f"/{prefix}" if prefix else "",
        shell=setting("SHELL", "/bin/bash"),
        title=setting("TITLE", "Toolbox"),
        label=re.sub(r"[^A-Za-z0-9._ -]", "", os.environ.get("TOOLBOX_ENV_LABEL", "")),
        tone=tone if tone in TONES else "danger",
        max_sessions=int(setting("MAX_SESSIONS", "16")),
        idle_seconds=int(setting("IDLE_SECONDS", "0")),
        ephemeral_home=setting("EPHEMERAL_HOME", "true").lower() != "false",
    )


class SessionManager(UniqueTermManager):
    """Gives each shell a private temporary HOME and removes it when the shell ends."""

    def __init__(self, sessions_dir, ephemeral_home, **kwargs):
        super().__init__(**kwargs)
        self.sessions_dir = sessions_dir
        self.ephemeral_home = ephemeral_home

    def new_terminal(self, **kwargs):
        extra_env = {"HISTFILE": "/dev/null"}
        home = None
        if self.ephemeral_home:
            home = tempfile.mkdtemp(prefix="session-", dir=self.sessions_dir)
            extra_env["HOME"] = home
        working_dir = "/workspace" if os.access("/workspace", os.W_OK) else home or os.environ.get("HOME", "/")
        try:
            terminal = super().new_terminal(cwd=working_dir, extra_env=extra_env, **kwargs)
        except Exception:
            if home:
                shutil.rmtree(home, ignore_errors=True)
            raise
        terminal.session_home = home
        return terminal

    def on_eof(self, ptywclients):
        super().on_eof(ptywclients)
        if ptywclients.session_home:
            shutil.rmtree(ptywclients.session_home, ignore_errors=True)

    def client_disconnected(self, websocket):
        terminal = websocket.terminal
        try:
            super().client_disconnected(websocket)
        except ProcessLookupError:
            pass
        if terminal is not None:
            # A closed tab must not leave anything running, even a process that ignores SIGHUP.
            asyncio.ensure_future(terminate(terminal))


async def terminate(terminal):
    try:
        await terminal.terminate(force=True)
    except (OSError, RuntimeError) as error:
        LOG.warning("could not terminate shell: %s", type(error).__name__)


class TerminalSocket(TermSocket):
    def initialize(self, term_manager, sockets):
        super().initialize(term_manager)
        self.sockets = sockets
        self.last_input = time.monotonic()

    def open(self, url_component=None):
        try:
            super().open(url_component)
        except MaxTerminalsReached:
            self.close(1013, "session limit reached")
            return
        self.sockets.add(self)

    def on_message(self, message):
        self.last_input = time.monotonic()
        super().on_message(message)

    def on_close(self):
        self.sockets.discard(self)
        super().on_close()


class SecureHandler(RequestHandler):
    def set_default_headers(self):
        self.set_header("Content-Security-Policy", CONTENT_SECURITY_POLICY)
        self.set_header("X-Content-Type-Options", "nosniff")
        self.set_header("Referrer-Policy", "no-referrer")
        self.set_header("Cache-Control", "no-store")


class TerminalPage(SecureHandler):
    def initialize(self, config):
        self.config = config

    def get(self):
        self.render("index.html", title=self.config.title, label=self.config.label, tone=self.config.tone)


class Health(SecureHandler):
    def get(self):
        self.write("OK")


def make_app(config, manager, sockets):
    routes = [
        (f"{config.prefix}/", TerminalPage, {"config": config}),
        (f"{config.prefix}/websocket", TerminalSocket, {"term_manager": manager, "sockets": sockets}),
        (f"{config.prefix}/healthz", Health),
    ]
    if config.prefix:
        routes.append((config.prefix, RedirectHandler, {"url": f"{config.prefix}/", "permanent": False}))
        routes.append(("/healthz", Health))
    return Application(
        routes,
        template_path=str(ROOT / "templates"),
        static_path=str(ROOT / "static"),
        static_url_prefix=f"{config.prefix}/static/",
        websocket_ping_interval=30,
        websocket_ping_timeout=30,
        log_function=lambda handler: None,
    )


def close_idle_sockets(sockets, idle_seconds):
    deadline = time.monotonic() - idle_seconds
    for socket in list(sockets):
        if socket.last_input < deadline:
            socket.close(1000, "idle timeout")


def prepare_sessions_dir():
    sessions_dir = Path(tempfile.gettempdir()) / f"toolbox-terminal-{os.getuid()}"
    shutil.rmtree(sessions_dir, ignore_errors=True)
    sessions_dir.mkdir(mode=0o700, parents=True)
    return sessions_dir


async def main():
    logging.basicConfig(level=logging.WARNING, format="toolbox-terminal %(levelname)s %(message)s")
    config = load_config()
    sockets = set()
    manager = SessionManager(
        sessions_dir=prepare_sessions_dir(),
        ephemeral_home=config.ephemeral_home,
        shell_command=[config.shell],
        max_terminals=config.max_sessions,
        term_settings={"type": "xterm-256color"},
    )
    server = make_app(config, manager, sockets).listen(config.port, address=config.bind)

    if config.idle_seconds > 0:
        PeriodicCallback(lambda: close_idle_sockets(sockets, config.idle_seconds), 15_000).start()

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for stop_signal in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(stop_signal, stop.set)

    print(f"toolbox-terminal listening on {config.bind}:{config.port}{config.prefix}/", flush=True)
    await stop.wait()

    server.stop()
    await manager.shutdown()
    await server.close_all_connections()


if __name__ == "__main__":
    asyncio.run(main())

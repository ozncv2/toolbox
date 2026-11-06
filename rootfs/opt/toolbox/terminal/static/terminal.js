(() => {
  "use strict";

  const statusLabel = document.getElementById("status");
  const endedOverlay = document.getElementById("ended");
  const searchForm = document.getElementById("search");
  const searchInput = document.getElementById("search-input");

  const terminal = new Terminal({
    allowProposedApi: true,
    cursorBlink: true,
    fontFamily: 'ui-monospace, "SF Mono", Menlo, Consolas, "DejaVu Sans Mono", monospace',
    fontSize: 14,
    scrollback: 10000,
    theme: { background: "#14171c", foreground: "#d7dce2" },
  });

  const fit = new FitAddon.FitAddon();
  const search = new SearchAddon.SearchAddon();
  terminal.loadAddon(fit);
  terminal.loadAddon(search);
  terminal.loadAddon(new WebLinksAddon.WebLinksAddon());
  terminal.loadAddon(new Unicode11Addon.Unicode11Addon());
  terminal.unicode.activeVersion = "11";
  terminal.open(document.getElementById("terminal"));
  fit.fit();

  const socketUrl = new URL("websocket", window.location.href);
  socketUrl.protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const socket = new WebSocket(socketUrl);
  let sessionOpen = false;

  const send = (message) => {
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(message));
    }
  };
  const sendSize = () => send(["set_size", terminal.rows, terminal.cols]);

  socket.onopen = () => {
    sessionOpen = true;
    statusLabel.textContent = "Connected";
    sendSize();
    terminal.focus();
  };

  socket.onmessage = (event) => {
    const [kind, data] = JSON.parse(event.data);
    if (kind === "stdout") {
      terminal.write(data);
    }
  };

  socket.onclose = (event) => {
    sessionOpen = false;
    statusLabel.textContent = event.reason || "Disconnected";
    endedOverlay.hidden = false;
    document.getElementById("reconnect").focus();
  };

  terminal.onData((data) => send(["stdin", data]));
  terminal.onResize(sendSize);
  new ResizeObserver(() => fit.fit()).observe(document.getElementById("terminal"));

  const openSearch = () => {
    searchForm.hidden = false;
    searchInput.focus();
    searchInput.select();
  };
  const closeSearch = () => {
    searchForm.hidden = true;
    search.clearDecorations();
    terminal.focus();
  };

  // Ctrl+C copies when text is selected and interrupts otherwise; Ctrl+V uses the browser's paste.
  terminal.attachCustomKeyEventHandler((event) => {
    if (event.type !== "keydown" || !event.ctrlKey) {
      return true;
    }
    const key = event.key.toLowerCase();
    if (key === "c" && (event.shiftKey || terminal.hasSelection())) {
      navigator.clipboard?.writeText(terminal.getSelection());
      terminal.clearSelection();
      return false;
    }
    if (key === "v") {
      return false;
    }
    if (key === "f" && event.shiftKey) {
      event.preventDefault();
      openSearch();
      return false;
    }
    return true;
  });

  searchForm.addEventListener("submit", (event) => {
    event.preventDefault();
    search.findNext(searchInput.value);
  });
  document.getElementById("search-previous").addEventListener("click", () => {
    search.findPrevious(searchInput.value);
  });
  document.getElementById("search-close").addEventListener("click", closeSearch);
  searchInput.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeSearch();
    }
  });

  const newSession = () => window.location.reload();
  document.getElementById("reconnect").addEventListener("click", newSession);
  window.addEventListener("keydown", (event) => {
    if (!sessionOpen && !endedOverlay.hidden && event.key === "Enter") {
      event.preventDefault();
      newSession();
    }
  });
})();

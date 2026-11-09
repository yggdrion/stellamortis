"""Headless network test, in two runs:
1. One dedicated server and two bot clients over ENet, through tools/lag_proxy.py (round trip
   --lag ms, default 100, plus --jitter ms, default 20). Each bot walks a circle and exits 0 once
   it has moved and seen the other bot move.
2. Player host over WebRTC: a local lobby (lobby/, pinned Bun), a --host bot that spawns its own
   server with a lobby room, and a bot joining by the room code; the same checks as run 1. A
   join with a wrong code must fail with the lobby's reason.
Fails if any process fails or a run takes too long.

Usage: python tools/run_network_test.py [--lag=MS] [--jitter=MS]
"""

import os
import re
import threading
import subprocess
import sys
import time
import urllib.request

import lag_proxy
from _common import GAME, ROOT, bun, fail, godot, godot_import, log

PORT = 17791
PROXY_PORT = PORT + 1
LOBBY_PORT = 17795
TIMEOUT = 60
options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
lag_proxy.start(PROXY_PORT, PORT, int(options.get("lag", 100)), int(options.get("jitter", 20)))

godot_bin = godot()
godot_import(godot_bin)


def start(*cmd, **kwargs):
    return subprocess.Popen([godot_bin, "--headless", "--path", ".", "--", *cmd], cwd=GAME, **kwargs)


server = start("--server", f"--port={PORT}")
time.sleep(1.0)
bots = [
    # Staggered, so the two never quit in the same instant: the server would then tell the
    # second about the first leaving after its connection closed ("Unable to send packet").
    start("--bot", "--expect=2", f"--duration={6 + 3 * i}", f"--connect=127.0.0.1:{PROXY_PORT}", f"--name=bot{i}")
    for i in range(2)
]
deadline = time.time() + TIMEOUT
codes = []
try:
    for bot in bots:
        codes.append(bot.wait(timeout=max(1, deadline - time.time())))
except subprocess.TimeoutExpired:
    fail("Network test timed out")
finally:
    for p in [server, *bots]:
        p.kill()
if any(codes):
    fail(f"Network test failed, bot exit codes {codes}")
log("ENet run passed")

lobby = subprocess.Popen(
    [bun(), str(ROOT / "lobby" / "src" / "server.ts")],
    env={**os.environ, "PORT": str(LOBBY_PORT)},
    stdout=subprocess.DEVNULL,
)
lobby_url = f"ws://127.0.0.1:{LOBBY_PORT}/ws"
procs = [lobby]
try:
    deadline = time.time() + 10
    while True:
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{LOBBY_PORT}/healthz", timeout=1)
            break
        except OSError:
            if time.time() > deadline:
                fail("The local lobby did not start")
            time.sleep(0.2)
    host = start(
        "--host", f"--lobby={lobby_url}", "--bot", "--expect=2", "--duration=12", "--name=host",
        stdout=subprocess.PIPE, text=True,
    )
    procs.append(host)
    code = ""
    host_lines = []
    deadline = time.time() + 30
    while not code and time.time() < deadline:
        line = host.stdout.readline()
        if not line:
            break
        host_lines.append(line)
        if match := re.search(r"Hosting room ([A-Z]{8})", line):
            code = match.group(1)
    if not code:
        fail("The host bot opened no room:\n" + "".join(host_lines[-20:]))
    # Keep reading the host's output, so its pipe never fills up.
    drain = threading.Thread(target=host.stdout.read, daemon=True)
    drain.start()
    friend = start("--join=" + code, f"--lobby={lobby_url}", "--bot", "--expect=2", "--duration=8", "--name=friend")
    procs.append(friend)
    bad = start("--join=ZZZZZZZZ", f"--lobby={lobby_url}", "--bot", "--name=bad", stdout=subprocess.PIPE, text=True)
    procs.append(bad)
    deadline = time.time() + TIMEOUT
    rtc_codes = [p.wait(timeout=max(1, deadline - time.time())) for p in (friend, host)]
    bad_out = bad.communicate(timeout=20)[0]
except subprocess.TimeoutExpired:
    fail("WebRTC run timed out")
finally:
    for p in procs:
        p.kill()
if any(rtc_codes):
    fail(f"WebRTC run failed, exit codes (friend, host) {rtc_codes}")
if bad.returncode == 0 or "No room with that code" not in bad_out:
    fail(f"A wrong room code did not fail as expected (exit {bad.returncode})")
log("WebRTC run passed")
log("Network test passed")

"""Headless network test: one dedicated server and two bot clients over ENet, through
tools/lag_proxy.py (round trip --lag ms, default 100, plus --jitter ms, default 20). Each bot
walks a circle and exits 0 once it has moved and seen the other bot move. Fails if any process
fails or the run takes too long.

Usage: python tools/run_network_test.py [--lag=MS] [--jitter=MS]
"""

import subprocess
import sys
import time

import lag_proxy
from _common import GAME, fail, godot, godot_import, log

PORT = 17791
PROXY_PORT = PORT + 1
TIMEOUT = 60
options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
lag_proxy.start(PROXY_PORT, PORT, int(options.get("lag", 100)), int(options.get("jitter", 20)))

godot_bin = godot()
godot_import(godot_bin)


def start(*cmd):
    return subprocess.Popen([godot_bin, "--headless", "--path", ".", "--", *cmd], cwd=GAME)


server = start("--server", f"--port={PORT}")
time.sleep(1.0)
bots = [
    start("--bot", "--expect=2", "--duration=6", f"--connect=127.0.0.1:{PROXY_PORT}", f"--name=bot{i}")
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
log("Network test passed")

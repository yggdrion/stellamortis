"""Headless network test: one dedicated server and two bot clients on localhost over ENet,
each bot with fake latency. Each bot walks a circle and exits 0 once it has seen the other bot
move and its own prediction stayed close to the server. Fails if any process fails or the run
takes too long.

Usage: python tools/run_network_test.py [--lag=MS]   (default 100)
"""

import subprocess
import sys
import time

from _common import GAME, fail, godot, godot_import, log

PORT = 17791
TIMEOUT = 60
lag = next((a for a in sys.argv[1:] if a.startswith("--lag=")), "--lag=100")

godot_bin = godot()
godot_import(godot_bin)


def start(*cmd):
    return subprocess.Popen([godot_bin, "--headless", "--path", ".", "--", *cmd], cwd=GAME)


server = start("--server", f"--port={PORT}")
time.sleep(1.0)
bots = [
    start("--bot", "--expect=2", "--duration=6", f"--connect=127.0.0.1:{PORT}", f"--name=bot{i}", lag)
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

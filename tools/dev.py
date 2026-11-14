"""Dev launcher: one headless server plus N windowed clients joining it on localhost.

Usage: python tools/dev.py [clients, default 2] [--lag=MS]
Clients join as dev1..devN. --lag routes them through tools/lag_proxy.py with that round trip.
Closing every client window (or Ctrl+C) stops the server too. For plain solo, run the game
without arguments instead: python tools/godot.py
"""

import subprocess
import sys

import lag_proxy
from _common import GAME, fail, godot, godot_import

PORT = 17777

args = sys.argv[1:]
lag = [a for a in args if a.startswith("--lag=")]
rest = [a for a in args if not a.startswith("--lag=")]
if len(rest) > 1 or (rest and not rest[0].isdigit()):
    fail("Usage: python tools/dev.py [clients] [--lag=MS]")
count = int(rest[0]) if rest else 2
godot_bin = godot()
godot_import(godot_bin)


def start(*cmd):
    return subprocess.Popen([godot_bin, "--path", ".", *cmd], cwd=GAME)


server = start("--headless", "--", "--server", f"--port={PORT}", "--bind=127.0.0.1")
target = PORT
if lag:
    target = PORT + 1
    lag_proxy.start(target, PORT, int(lag[0].split("=", 1)[1]))
clients = [
    start("--", "--windowed", f"--connect=127.0.0.1:{target}", f"--name=dev{i + 1}")
    for i in range(count)
]
try:
    for client in clients:
        client.wait()
except KeyboardInterrupt:
    pass
finally:
    for p in [server, *clients]:
        p.kill()

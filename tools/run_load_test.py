"""Load test (PLAN M7): one headless server and N headless bot clients over ENet on this
machine. Bots walk, fight the dummies, switch weapons and lock on (GameClient._bot_controls);
each must see every other bot move. The server prints one stats line per second
(STELLAMORTIS_SERVER_STATS); once all bots are in, this reads them and reports ticks per second,
tick loop time, rollback resimulation and bytes per player.

Usage: python tools/run_load_test.py [--players=6] [--seconds=40] [--lag=MS]
Fails if a bot fails or the server falls below 29 ticks per second on average. A tick loop
can run several ticks when the server is behind, so a loop over 33 ms alone is no failure; it
shows the server has no headroom. All processes share this machine's CPU.
"""

import os
import re
import statistics
import subprocess
import sys
import threading
import time

import tempfile
from pathlib import Path

import lag_proxy
from _common import GAME, fail, godot, godot_import, log

PORT = 17801
PROXY_PORT = PORT + 1
options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
players = int(options.get("players", 6))
seconds = int(options.get("seconds", 40))
lag = int(options.get("lag", 0))
target = PORT
if lag > 0:
    lag_proxy.start(PROXY_PORT, PORT, lag, 0)
    target = PROXY_PORT

godot_bin = godot()
godot_import(godot_bin)


def start(*cmd, **kwargs):
    return subprocess.Popen([godot_bin, "--headless", "--path", ".", "--", *cmd], cwd=GAME, **kwargs)


server = start(
    "--server", f"--port={PORT}",
    env={**os.environ, "STELLAMORTIS_SERVER_STATS": "1"},
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
)
stats = []
warnings = []


def read_server():
    for line in server.stdout:
        if line.startswith("stats "):
            stats.append(dict(kv.split("=") for kv in line.split()[1:]))
        elif "exceeds packet limit" in line:
            warnings.append(line.strip())


threading.Thread(target=read_server, daemon=True).start()
time.sleep(1.0)
logs = Path(tempfile.mkdtemp(prefix="stellamortis-load-"))
bots = []
for i in range(players):
    out = open(logs / f"bot{i}.log", "w")  # noqa: SIM115, closed with the process
    bots.append(start(
        "--bot", f"--expect={players}", f"--duration={seconds}", f"--connect=127.0.0.1:{target}",
        f"--name=bot{i}", stdout=out, stderr=subprocess.STDOUT,
    ))
    time.sleep(0.5)
codes = []
try:
    deadline = time.time() + seconds + 60
    for bot in bots:
        codes.append(bot.wait(timeout=max(1, deadline - time.time())))
except subprocess.TimeoutExpired:
    for line in stats[-5:]:
        log(line)
    fail(f"Load test timed out (bot logs in {logs})")
finally:
    for p in [server, *bots]:
        p.kill()

full = [s for s in stats if int(s["players"]) == players]
if not full:
    fail(f"The server never had all {players} players; bot exit codes {codes}")


def column(name):
    return [float(s[name]) for s in full]


tps = column("tps")
tick_avg = column("tick_avg_ms")
report = (
    f"{players} players, {len(full)} s with everyone in: "
    f"tps {statistics.mean(tps):.1f} (min {min(tps):.1f}), "
    f"tick loop avg {statistics.mean(tick_avg):.2f} ms (worst second {max(tick_avg):.2f}, "
    f"max {max(column('tick_max_ms')):.2f}), "
    f"resim ticks per loop {statistics.mean(column('resim_ticks')):.1f}, "
    f"per player out {statistics.mean(column('out_kbps_per_player')):.1f} kB/s, "
    f"in {statistics.mean(column('in_kbps_per_player')):.1f} kB/s, "
    f"packet limit warnings {len(warnings)}; per resimulated tick: "
    f"restore {statistics.mean(column('restore_ms')):.2f} ms, "
    f"simulate {statistics.mean(column('simulate_ms')):.2f} ms, "
    f"record and send {statistics.mean(column('record_send_ms')):.2f} ms"
)
log(report)
if any(codes):
    fail(f"Load test failed, bot exit codes {codes} (bot logs in {logs})")
if statistics.mean(tps) < 29.0:
    fail("The server could not hold 30 ticks per second")
log("Load test passed")

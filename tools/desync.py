"""Compares the state lines of the server's event log with a client's (game/scripts/net/event_log.gd).

Both sides log, every 30 ticks and 48 ticks after the fact (so every correction and late input
for that tick has long arrived), what netfox's history holds for a player: a hash, the position
in cm, health in tenths and the action. A line pair (same peer, same `at` tick) whose hashes
differ outlived the rollback window: a desync. A pair that differs by at most 1 cm in each
coordinate and nowhere else is rounding of two machines' float noise at a cm boundary, counted
apart as `noise`.

    python tools/desync.py SERVER.jsonl CLIENT.jsonl [CLIENT2.jsonl ...]   # exit 1 on a desync

`compare` is for the playtest runner (M24 task 3).
"""

import json
import sys


def load(path):
    """The state lines of a log file, as {(peer, at): line}; the last line of a key wins."""
    states = {}
    with open(path, encoding="utf-8") as file:
        for text in file:
            try:
                line = json.loads(text)
            except ValueError:
                continue  # a log cut off mid-line when a process was killed
            if line.get("e") == "state":
                states[(line["peer"], line["at"])] = line
    return states


def compare(server, client):
    """{checked, noise, desyncs}: server and client are dicts from load(). Only keys both logged
    count (the client logs its own player; the server logs every player)."""
    checked = noise = 0
    desyncs = []
    for key in sorted(server.keys() & client.keys(), key=lambda k: (k[1], k[0])):
        a, b = server[key], client[key]
        checked += 1
        if a["h"] == b["h"]:
            continue
        near = all(abs(x - y) <= 1 for x, y in zip(a["pos"], b["pos"]))
        if near and a["hp"] == b["hp"] and a["act"] == b["act"]:
            noise += 1
            continue
        desyncs.append({"peer": key[0], "at": key[1], "server": a, "client": b})
    return {"checked": checked, "noise": noise, "desyncs": desyncs}


def selftest():
    def line(peer, at, pos, hp=1000, act=0, h=None):
        return {"e": "state", "peer": peer, "at": at, "pos": pos, "hp": hp, "act": act,
                "h": h if h is not None else hash((tuple(pos), hp, act))}

    server = {(1, 30): line(1, 30, [0, 0, 0]), (1, 60): line(1, 60, [5, 0, 0]),
              (2, 60): line(2, 60, [9, 9, 9])}
    client = {(1, 30): line(1, 30, [0, 0, 0]), (1, 60): line(1, 60, [5, 0, 0])}
    assert compare(server, client) == {"checked": 2, "noise": 0, "desyncs": []}
    client[(1, 60)] = line(1, 60, [6, 0, 0])  # 1 cm off: cm boundary noise
    assert compare(server, client)["noise"] == 1 and not compare(server, client)["desyncs"]
    client[(1, 60)] = line(1, 60, [5, 0, 40])  # 40 cm off: desync
    assert len(compare(server, client)["desyncs"]) == 1
    client[(1, 60)] = line(1, 60, [5, 0, 0], hp=900)  # hurt differently: desync
    assert len(compare(server, client)["desyncs"]) == 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        selftest()
        print("desync.py selftest ok; usage: desync.py SERVER.jsonl CLIENT.jsonl [...]")
        sys.exit(0)
    server_states = load(sys.argv[1])
    failed = False
    for path in sys.argv[2:]:
        result = compare(server_states, load(path))
        print(f"{path}: checked {result['checked']}, noise {result['noise']}, "
              f"desyncs {len(result['desyncs'])}")
        for d in result["desyncs"]:
            print(f"  peer {d['peer']} at tick {d['at']}: server {d['server']} client {d['client']}")
        failed = failed or bool(result["desyncs"])
    sys.exit(1 if failed else 0)

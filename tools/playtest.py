"""Bot play-tests (M24): runs a scenario (tools/scenarios/NAME.json) on a headless server with
headless bot clients, each through its own lag proxy, then reads the event logs and writes
build/playtest/NAME/report.md and report.json. Expectations in the scenario fail the run.

    python tools/playtest.py SCENARIO [--repeat=N] [--short]
    python tools/playtest.py --suite [--repeat=N] [--short]     every scenario, one summary table

--short caps every scenario's duration at 30 s (a quick look at soak_30min). Exit code 1 when an
expectation fails or a run breaks. All processes share this machine's CPU: the report keeps the
server's own tick loop time next to tps, so a starved server shows as such.

Scenario fields: seed, spawn ("X,Y,Z" or "X,Y,Z;X,Y,Z", handed to the bots in turn), encounter
("boss"), duration (seconds after everyone joined), end_on ("boss": stop when the Warden falls or
every bot died once), fps (bot frame rate cap, big parties), repeats, party (per bot: skill, goal,
seed, role, lag = round trip ms, jitter ms, loss percent), expect (see `check_expectations`).
"""

import json
import os
import socket
import statistics
import subprocess
import sys
import time
from pathlib import Path

import desync
import lag_proxy
from _common import GAME, ROOT, fail, godot, godot_import, log

SCENARIOS = ROOT / "tools" / "scenarios"
OUT = ROOT / "build" / "playtest"
JOIN_TIMEOUT = 90
STOP_TIMEOUT = 30
TPS = 30.0
# Jumps of the own player above this are teleports (join, respawn), not corrections.
TELEPORT_M = 50.0


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def read_events(path):
    events = []
    if Path(path).exists():
        for text in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
            try:
                events.append(json.loads(text))
            except ValueError:
                pass  # a line cut off by a kill
    events.sort(key=lambda e: e.get("tick", 0))
    return events


def death_peers(path):
    return {e["who"] for e in read_events(path) if e.get("e") == "death"}


def phases(events):
    first = {}
    for e in events:
        if e.get("e") == "phase":
            first.setdefault(e["phase"], e["tick"])
    return first


def execute(scenario, out, godot_bin):
    """One run: starts everything, waits, stops cleanly. Returns what analyse() needs."""
    shutil_rmtree(out)
    out.mkdir(parents=True)
    party = scenario["party"]
    n = len(party)
    port = free_port()
    stop = out / "stop"
    events_path = out / "server.jsonl"
    env = {**os.environ, "STELLAMORTIS_SERVER_STATS": "1", "STELLAMORTIS_EVENT_LOG": str(events_path),
           "STELLAMORTIS_STOP_FILE": str(stop)}

    def start(args, logfile, **kwargs):
        f = open(out / logfile, "w", encoding="utf-8")  # noqa: SIM115, closed in the finally below
        files.append(f)
        return subprocess.Popen([godot_bin, "--headless", "--path", ".", "--", *args], cwd=GAME, env=env,
                                stdout=f, stderr=subprocess.STDOUT, **kwargs)

    files = []
    procs = []
    try:
        server_args = ["--server", f"--port={port}", "--bind=127.0.0.1", f"--seed={scenario.get('seed', 1234)}"]
        for key in ("spawn", "encounter"):
            if scenario.get(key):
                server_args.append(f"--{key}={scenario[key]}")
        server = start(server_args, "server.log")
        procs.append(server)
        # The server builds the world (seconds) before it listens; a bot behind a lag proxy that
        # connects earlier never hears back and gives up.
        end = time.time() + JOIN_TIMEOUT
        while "Server listening" not in (out / "server.log").read_text(encoding="utf-8", errors="replace"):
            if server.poll() is not None or time.time() > end:
                fail(f"The server did not start listening (logs in {out})")
            time.sleep(0.5)
        bots = []
        for i, b in enumerate(party):
            target = port
            if b.get("lag", 0) or b.get("jitter", 0) or b.get("loss", 0):
                target = free_port()
                lag_proxy.start(target, port, b.get("lag", 0), b.get("jitter", 0), b.get("loss", 0))
            args = ["--bot", "--expect=1", f"--duration={scenario['duration'] + 3600}",
                    f"--connect=127.0.0.1:{target}", f"--name=bot{i}", f"--bot-goal={b.get('goal', 'camp')}",
                    f"--bot-seed={b.get('seed', i + 1)}"]
            if b.get("skill"):
                args.append(f"--bot-skill={b['skill']}")
            if b.get("role"):
                args.append(f"--bot-role={b['role']}")
            if scenario.get("fps"):
                args.append(f"--max-fps={scenario['fps']}")
            bots.append(start(args, f"bot{i}.log"))
            procs.append(bots[-1])
            time.sleep(0.5)
        joined = wait_joined(events_path, n, server)
        began = time.time()
        deadline = began + scenario["duration"]
        reason = "duration"
        while time.time() < deadline:
            if server.poll() is not None:
                reason = "server died"
                break
            if scenario.get("end_on") == "boss":
                ev = read_events(events_path)
                if "CLEARED" in phases(ev):
                    reason = "boss fell"
                    break
                if len(death_peers(events_path)) >= n:
                    reason = "wipe"
                    break
            time.sleep(2.0)
        seconds = time.time() - began
        stop.write_text("stop")
        try:
            server.wait(timeout=STOP_TIMEOUT)
        except subprocess.TimeoutExpired:
            log("server did not stop on its own, killing it (events of the last 2 s are lost)")
        for b in bots:  # the disconnect sends bots back to quit
            try:
                b.wait(timeout=STOP_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
        return {"joined": joined, "seconds": seconds, "ended": reason,
                "codes": [p.returncode for p in procs]}
    finally:
        for p in procs:
            if p.poll() is None:
                p.kill()
        for f in files:
            f.close()


def shutil_rmtree(path):
    import shutil

    shutil.rmtree(path, ignore_errors=True)


def wait_joined(events_path, n, server):
    """Waits until a stats event of the server's log shows n players."""
    end = time.time() + JOIN_TIMEOUT
    while time.time() < end:
        if server.poll() is not None:
            fail(f"The server exited early (logs in {events_path.parent})")
        if any(e.get("e") == "stats" and e["players"] == n for e in read_events(events_path)):
            return True
        time.sleep(1.0)
    fail(f"Not all {n} bots joined within {JOIN_TIMEOUT} s (logs in {events_path.parent})")


def script_errors(out, n):
    count = 0
    for name in ["server.log", *[f"bot{i}.log" for i in range(n)]]:
        path = out / name
        if path.exists():
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                if "SCRIPT ERROR" in line or "Parse Error" in line:
                    count += 1
    return count


def mean(values):
    return statistics.mean(values) if values else 0.0


def analyse(scenario, out, info):
    """Reads one run's logs. Returns {scalars, tables, ...}: scalars are numbers the repeats
    average, tables are per skill, per attack and per lag class."""
    party = scenario["party"]
    n = len(party)
    ev = read_events(out / "server.jsonl")
    names = {e["peer"]: e["name"] for e in ev if e.get("e") == "join"}
    bot_of = {peer: int(name[3:]) for peer, name in names.items() if name.startswith("bot")}
    skill = {peer: party[i].get("skill") or "plan" for peer, i in bot_of.items()}
    stat = lambda: {"hits": 0, "dealt": 0.0, "taken": 0.0, "deaths": 0, "parries": 0, "blocks": 0, "rolls": 0}  # noqa: E731
    per_skill = {}
    taken_by_attack = {}
    kills = {}
    for e in ev:
        kind = e.get("e")
        if kind == "hit" or kind == "parry":
            if e["attacker"] in skill:
                s = per_skill.setdefault(skill[e["attacker"]], stat())
                s["hits"] += 1
                s["dealt"] += e["damage"]
            elif e["target"] in skill:
                s = per_skill.setdefault(skill[e["target"]], stat())
                s["taken"] += e["damage"]
                s["blocks"] += 1 if e.get("blocked") else 0
                s["parries"] += 1 if kind == "parry" else 0
                a = taken_by_attack.setdefault(e["attack"], {"hits": 0, "damage": 0.0, "deaths": 0})
                a["hits"] += 1
                a["damage"] += e["damage"]
        elif kind == "death" and e["who"] in skill:
            per_skill.setdefault(skill[e["who"]], stat())["deaths"] += 1
            taken_by_attack.setdefault(e["attack"], {"hits": 0, "damage": 0.0, "deaths": 0})["deaths"] += 1
        elif kind == "roll" and e["peer"] in skill:
            per_skill.setdefault(skill[e["peer"]], stat())["rolls"] += 1
        elif kind == "kill":
            kills[e["kind"]] = kills.get(e["kind"], 0) + 1
    deaths = {names[p]: sum(1 for e in ev if e.get("e") == "death" and e["who"] == p) for p in bot_of}
    ph = phases(ev)
    boss = {}
    if "BOSS" in ph:
        boss["win"] = "CLEARED" in ph
        boss["wipe"] = not boss["win"] and info["ended"] == "wipe"
        if boss["win"]:
            boss["ttk"] = (ph["CLEARED"] - ph["BOSS"]) / TPS

    full = [e for e in ev if e.get("e") == "stats" and e["players"] == n]
    col = lambda k: [float(e[k]) for e in full]  # noqa: E731
    net = {
        "tps": mean(col("tps")), "tps_min": min(col("tps"), default=0.0),
        "tick_avg_ms": mean(col("tick_avg_ms")), "tick_max_ms": max(col("tick_max_ms"), default=0.0),
        "resim_ticks": mean(col("resim_ticks")), "out_kbps": mean(col("out_kbps")),
        "in_kbps": mean(col("in_kbps")), "awake_max": max(col("awake"), default=0.0),
    }

    # Corrections per lag class (bots with the same lag and loss), from each client's own log.
    classes = {}
    desyncs = checked = 0
    server_states = desync.load(out / "server.jsonl")
    minutes = max(info["seconds"], 1.0) / 60.0
    for peer, i in bot_of.items():
        b = party[i]
        label = f"{b.get('lag', 0)} ms" + (f", {b['loss']} % loss" if b.get("loss") else "")
        c = classes.setdefault(label, {"bots": 0, "snaps": 0, "teleports": 0, "sizes": [], "pings": []})
        c["bots"] += 1
        path = Path(f"{out / 'server.jsonl'}.{peer}")
        if not path.exists():
            continue
        for e in read_events(path):
            if e.get("e") == "snap" and e["m"] > TELEPORT_M:
                c["teleports"] += 1  # a spawn, respawn or portal, not a correction
            elif e.get("e") == "snap":
                c["snaps"] += 1
                c["sizes"].append(e["m"])
            elif e.get("e") == "client" and e.get("ping"):
                c["pings"].append(e["ping"])
        result = desync.compare(server_states, desync.load(path))
        desyncs += len(result["desyncs"])
        checked += result["checked"]
    lag_table = {
        k: {"bots": c["bots"], "corrections_per_min": c["snaps"] / c["bots"] / minutes,
            "mean_m": mean(c["sizes"]), "max_m": max(c["sizes"], default=0.0), "ping_ms": mean(c["pings"]), "teleports": c["teleports"]}
        for k, c in classes.items()
    }
    player_hits = sum(s["hits"] for s in per_skill.values())
    scalars = {
        "seconds": info["seconds"], "hits": player_hits, "deaths": sum(deaths.values()),
        "kills": sum(kills.values()), "dealt": sum(s["dealt"] for s in per_skill.values()),
        "taken": sum(s["taken"] for s in per_skill.values()), "desyncs": desyncs,
        "script_errors": script_errors(out, n), "snap_max_m": max((c["max_m"] for c in lag_table.values()), default=0.0),
        **{f"net_{k}": v for k, v in net.items()},
    }
    if boss:
        scalars["win"] = 1.0 if boss["win"] else 0.0
        scalars["wipe"] = 1.0 if boss["wipe"] else 0.0
        if "ttk" in boss:
            scalars["ttk"] = boss["ttk"]
    return {"scalars": scalars, "per_skill": per_skill, "taken_by_attack": taken_by_attack, "kills": kills,
            "deaths": deaths, "net": net, "lag_classes": lag_table, "state_pairs_checked": checked,
            "ended": info["ended"], "exit_codes": info["codes"], "stamina_empty": None}


def spread(runs, key):
    vals = [r["scalars"][key] for r in runs if key in r["scalars"]]
    if not vals:
        return None
    return {"mean": mean(vals), "min": min(vals), "max": max(vals),
            "stdev": statistics.stdev(vals) if len(vals) > 1 else 0.0, "n": len(vals)}


def check_expectations(expect, runs):
    """Returns [(ok, text)]. Rates and means are over the repeats, extremes over every run."""
    def sc(key):
        return [r["scalars"].get(key, 0.0) for r in runs]

    results = []

    def add(ok, text):
        results.append((ok, text))

    checks = {
        "desyncs_max": lambda v: (sum(sc("desyncs")) <= v, f"desyncs {sum(sc('desyncs')):.0f} <= {v}"),
        "script_errors_max": lambda v: (sum(sc("script_errors")) <= v,
                                        f"script errors {sum(sc('script_errors')):.0f} <= {v}"),
        "tps_min": lambda v: (mean(sc("net_tps")) >= v, f"mean tps {mean(sc('net_tps')):.1f} >= {v}"),
        "tick_avg_ms_max": lambda v: (mean(sc("net_tick_avg_ms")) <= v,
                                      f"tick loop {mean(sc('net_tick_avg_ms')):.1f} ms <= {v}"),
        "hits_min": lambda v: (min(sc("hits")) >= v, f"player hits (worst run) {min(sc('hits')):.0f} >= {v}"),
        "kills_min": lambda v: (min(sc("kills")) >= v, f"kills (worst run) {min(sc('kills')):.0f} >= {v}"),
        "snap_max_m": lambda v: (max(sc("snap_max_m")) <= v, f"largest correction {max(sc('snap_max_m')):.2f} m <= {v}"),
        "win_rate_min": lambda v: (mean(sc("win")) >= v, f"win rate {mean(sc('win')):.2f} >= {v}"),
        "win_rate_max": lambda v: (mean(sc("win")) <= v, f"win rate {mean(sc('win')):.2f} <= {v}"),
    }
    for key, value in expect.items():
        if key not in checks:
            add(False, f"unknown expectation {key}")
            continue
        ok, text = checks[key](value)
        add(ok, text)
    return results


def fmt(x):
    return f"{x:.2f}" if isinstance(x, float) else str(x)


def write_report(scenario, name, runs, results, out):
    summary = {k: spread(runs, k) for k in sorted({k for r in runs for k in r["scalars"]})}
    data = {"scenario": name, "about": scenario.get("about", ""), "repeats": len(runs),
            "expectations": [{"ok": ok, "text": t} for ok, t in results],
            "summary": summary, "runs": runs, "party": scenario["party"]}
    (out / "report.json").write_text(json.dumps(data, indent=2), encoding="utf-8", newline="\n")
    md = [f"# Play-test {name}", "", scenario.get("about", ""), "",
          f"{len(runs)} run(s); a repeated scenario shows mean (min to max, stdev).", "", "## Expectations", ""]
    md += [f"- {'PASS' if ok else 'FAIL'}: {t}" for ok, t in results] or ["- none"]
    md += ["", "## Numbers", "", "| value | mean | min | max | stdev |", "|---|---|---|---|---|"]
    for k, s in summary.items():
        md.append(f"| {k} | {fmt(s['mean'])} | {fmt(s['min'])} | {fmt(s['max'])} | {fmt(s['stdev'])} |")
    last = runs[-1]
    md += ["", f"## Fight (last run, ended: {last['ended']})", "",
           "| skill | hits | dealt | taken | deaths | parries | blocks | rolls |", "|---|---|---|---|---|---|---|---|"]
    for s, v in sorted(last["per_skill"].items()):
        md.append(f"| {s} | {v['hits']} | {v['dealt']:.0f} | {v['taken']:.0f} | {v['deaths']} | "
                  f"{v['parries']} | {v['blocks']} | {v['rolls']} |")
    md += ["", "Damage taken per enemy attack:", "", "| attack | hits | damage | deaths |", "|---|---|---|---|"]
    for a, v in sorted(last["taken_by_attack"].items(), key=lambda kv: -kv[1]["damage"]):
        md.append(f"| {a} | {v['hits']} | {v['damage']:.0f} | {v['deaths']} |")
    md += ["", f"Deaths per player: {last['deaths']}. Kills: {last['kills']}. "
           "Dodge success and stamina-empty time are not in the log yet (open item of M24).",
           "", "## Network (last run)", "", json.dumps({k: round(v, 2) for k, v in last["net"].items()}), "",
           "| lag class | bots | corrections/min per bot | mean m | max m | ping ms |", "|---|---|---|---|---|---|"]
    for k, v in last["lag_classes"].items():
        md.append(f"| {k} | {v['bots']} | {v['corrections_per_min']:.1f} | {v['mean_m']:.2f} | "
                  f"{v['max_m']:.2f} | {v['ping_ms']:.0f} |")
    md += ["", f"State pairs compared with the server: {last['state_pairs_checked']}; exit codes "
           f"(server, bots): {last['exit_codes']}."]
    (out / "report.md").write_text("\n".join(md) + "\n", encoding="utf-8", newline="\n")


def run_scenario(name, repeat, short, godot_bin):
    scenario = json.loads((SCENARIOS / f"{name}.json").read_text(encoding="utf-8"))
    if short:
        scenario["duration"] = min(scenario["duration"], 30)
    count = repeat or scenario.get("repeats", 1)
    base = OUT / name
    runs = []
    for i in range(count):
        log(f"== {name} run {i + 1}/{count}")
        out = base / f"run{i + 1}"
        info = execute(scenario, out, godot_bin)
        runs.append(analyse(scenario, out, info))
    results = check_expectations(scenario.get("expect", {}), runs)
    # A process that crashed fails the run too (the server exits 0 on the stop file, bots 2 on the disconnect).
    if any(r["exit_codes"][0] not in (0, None) for r in runs):
        results.append((False, f"server exit codes {[r['exit_codes'][0] for r in runs]}"))
    base.mkdir(parents=True, exist_ok=True)
    write_report(scenario, name, runs, results, base)
    for ok, text in results:
        log(f"  {'PASS' if ok else 'FAIL'}: {text}")
    return runs, results


def main():
    args = sys.argv[1:]
    options = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in args if a.startswith("--"))
    names = [a for a in args if not a.startswith("--")]
    if "suite" in options:
        names = sorted(p.stem for p in SCENARIOS.glob("*.json"))
    if not names:
        fail(__doc__)
    godot_bin = godot()
    godot_import(godot_bin)
    table = []
    failed = False
    for name in names:
        runs, results = run_scenario(name, int(options.get("repeat", 0)), "short" in options, godot_bin)
        ok = all(r[0] for r in results)
        failed = failed or not ok
        s = {k: spread(runs, k) for k in ("net_tps", "net_tick_avg_ms", "hits", "deaths", "kills", "win", "ttk")}
        table.append((name, ok, s))
    print("\n| scenario | result | tps | tick ms | hits | deaths | kills | win | ttk s |\n|---|---|---|---|---|---|---|---|---|")
    for name, ok, s in table:
        cells = [fmt(s[k]["mean"]) if s[k] else "-" for k in ("net_tps", "net_tick_avg_ms", "hits", "deaths", "kills", "win", "ttk")]
        print(f"| {name} | {'pass' if ok else 'FAIL'} | " + " | ".join(cells) + " |")
    print(f"\nReports in {OUT}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

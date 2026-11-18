"""Runs the gdUnit4 tests headless with the pinned Godot version: all of res://tests, or only
the suites (or suite:test) given with -a, e.g.
  python tools/run_tests.py -a res://tests/net_test.gd -a res://tests/hud_test.gd:test_bars
Other extra arguments go to gdUnit4 as they are (-c goes on past the first failure).
Set GODOT_BIN to use your own binary; it must match .godot-version.

Without -a the suites run in parallel: --jobs=N Godot processes (default min(8, CPUs); 1 = one
process for everything), each taking the next suite file of game/tests. Every process gets its
own user:// (a temp dir) and report dir, so suites that write saves do not collide.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import install
from _common import GAME, VERSION, fail, godot, godot_import

args = [a for a in sys.argv[1:] if not a.startswith("--jobs=")]
jobs = next((int(a[7:]) for a in sys.argv[1:] if a.startswith("--jobs=")), min(8, os.cpu_count() or 1))

godot_bin = godot()
out = subprocess.run([godot_bin, "--headless", "--version"], capture_output=True, text=True, check=False)
actual = (out.stdout.strip().splitlines() or [""])[-1].strip()
if not actual.startswith(f"{VERSION}.stable."):
    fail(f"GODOT_BIN is Godot {actual}, but .godot-version pins {VERSION}")

install.gdunit4()
godot_import(godot_bin)  # once, before any process: concurrent imports would race on .godot
RUNNER = ["--path", ".", "-s", "-d", "--remote-debug", "tcp://127.0.0.1:0", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"]


def single() -> int:
    # gdUnit4 adds every -a to the run, so the default res://tests only goes in without one.
    picked = [] if "-a" in args else ["-a", "res://tests"]
    test_args = ["--headless", "--ignoreHeadlessMode", *picked, *args]
    # What the addon's runtest.sh/.cmd do. The unreachable remote debugger keeps Godot from
    # dropping into its interactive debugger on script errors.
    code = subprocess.run([godot_bin, *RUNNER, *test_args], cwd=GAME, check=False).returncode
    print(f"Run tests ends with {code}", flush=True)
    subprocess.run(
        [godot_bin, "--headless", "--path", ".", "--quiet", "-s", "res://addons/gdUnit4/bin/GdUnitCopyLog.gd", *test_args],
        cwd=GAME, stdout=subprocess.DEVNULL, check=False,
    )
    return code


def user_dir_env(home: Path) -> dict:
    """The env var Godot builds user:// from, pointed into home."""
    name = "APPDATA" if sys.platform == "win32" else "HOME" if sys.platform == "darwin" else "XDG_DATA_HOME"
    return {**os.environ, name: str(home)}


def parallel() -> int:
    # Biggest files first: the long suites start early and the short ones fill the gaps.
    suites = sorted((GAME / "tests").glob("*_test.gd"), key=lambda p: -p.stat().st_size)
    queue = list(suites)
    lock = threading.Lock()
    results = {}
    work = Path(tempfile.mkdtemp(prefix="stellamortis-tests-"))

    def worker() -> None:
        while True:
            with lock:
                if not queue:
                    return
                suite = queue.pop(0)
            home = work / suite.stem
            (home / "reports").mkdir(parents=True)
            test_args = ["--headless", "--ignoreHeadlessMode", "-a", f"res://tests/{suite.name}",
                         "-rd", str(home / "reports"), *args]
            start = time.time()
            proc = subprocess.run([godot_bin, *RUNNER, *test_args], cwd=GAME, env=user_dir_env(home / "user"),
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", check=False)
            seconds = time.time() - start
            lines = [line for line in proc.stdout.splitlines() if "Statistics:" in line]
            summary = re.sub(chr(27) + r"\[[0-9;]*m", "", lines[-1]).strip() if lines else ""
            with lock:
                results[suite.name] = proc.returncode
                print(f"{'ok  ' if proc.returncode == 0 else 'FAIL'} {suite.name} {seconds:.0f}s {summary}", flush=True)
                if proc.returncode:
                    print(proc.stdout, flush=True)

    threads = [threading.Thread(target=worker) for _ in range(max(1, jobs))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    shutil.rmtree(work, ignore_errors=True)
    failed = [name for name, code in results.items() if code]
    print(f"{len(results) - len(failed)}/{len(results)} suites passed" + (f", failed: {' '.join(failed)}" if failed else ""), flush=True)
    return 1 if failed else 0


sys.exit(single() if "-a" in args or jobs <= 1 else parallel())

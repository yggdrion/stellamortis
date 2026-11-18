"""Runs all checks locally and in CI (.github/workflows/release.yml) and stops at the first failure:
  1. gdlint + gdformat --check   2. lobby tests (pinned Bun)   3. gdUnit4 tests (pinned Godot)
  4. headless network test (ENet with fake lag, and WebRTC through a local lobby)
  5. the smoke play-test (two bots at a camp, 40 s; tools/playtest.py)

Usage: python tools/check.py [--quick | --tests | --net]
  --quick   only step 1 (no Godot), a few seconds
  --tests   steps 1-3 (no network test)
  --net     steps 4-5 only (CI runs this beside --tests in its own job)
With no flag, steps 4 and 5 run beside step 3 when the machine has 8 or more CPUs (all ports
are free ones and every Godot process has its own user://); their output is printed when they
fail. Fewer CPUs: one after the other.
python tools/setup.py installs it as a git pre-push hook (skip once with: git push --no-verify).
"""

import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import install
import make_bodies
from _common import ROOT, fail, run

args = set(sys.argv[1:])
if len(args) > 1 or not args <= {"--quick", "--tests", "--net"}:
    fail("Usage: python tools/check.py [--quick | --tests | --net]")
py = sys.executable
dirs = ["game/scripts", "game/tests"]


def step(name):
    print(f"\n== {name}", flush=True)


def tool(name, *tool_args):
    run(py, f"tools/{name}.py", *tool_args, cwd=ROOT)


def quiet(name, *tool_args):
    """Runs a tool with its output captured: (name, exit code, output)."""
    done = subprocess.run([py, f"tools/{name}.py", *tool_args], cwd=ROOT, capture_output=True, text=True, errors="replace", check=False)
    return name, done.returncode, done.stdout + done.stderr


def report(result):
    """Prints a captured step: all of it when it failed, else its last line."""
    name, code, output = result
    lines = output.strip().splitlines()
    if code:
        print(f"\n== {name} FAILED\n{output}", flush=True)
        fail(f"{name} failed (exit {code})")
    print(f"\n== {name}: {lines[-1] if lines else 'passed'}", flush=True)


if "--net" not in args:
    step("Lint and format")
    venv_py = install.venv()
    run(venv_py, "-m", "gdtoolkit.linter", *dirs, cwd=ROOT)
    run(venv_py, "-m", "gdtoolkit.formatter", "--check", *dirs, cwd=ROOT)

    if os.path.exists(make_bodies.BLENDER_EXE):
        # CI has no Blender: the committed bodies are what ships.
        step("Bodies (Blender)")
        tool("make_bodies", "--check")

    if "--quick" in args:
        print("\nQuick checks passed (Godot tests skipped).")
        sys.exit(0)

    step("Lobby tests")
    tool("run_lobby_tests")

net = [("run_network_test",), ("playtest", "smoke")]
if not args:
    with ThreadPoolExecutor() as pool:
        pending = [pool.submit(quiet, *n) for n in net] if (os.cpu_count() or 1) >= 8 else []
        step("gdUnit4 tests")
        tool("run_tests")
        for future in pending:
            report(future.result())
    if not pending:
        step("Network test")
        tool(*net[0])
        step("Bot play-test smoke scenario")
        tool(*net[1])
elif "--tests" in args:
    step("gdUnit4 tests")
    tool("run_tests")
    print("\nTest checks passed (network test skipped).")
    sys.exit(0)
else:
    step("Network test")
    tool(*net[0])
    step("Bot play-test smoke scenario")
    tool(*net[1])

print("\nAll checks passed.")

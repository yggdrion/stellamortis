"""Runs all checks locally (there is no CI) and stops at the first failure:
  1. gdlint + gdformat --check   2. lobby tests (pinned Bun)   3. gdUnit4 tests (pinned Godot)
  4. headless network test (ENet with fake lag, and WebRTC through a local lobby)
  5. the smoke play-test (two bots at a camp, 40 s; tools/playtest.py)

Usage: python tools/check.py [--quick | --tests]
  --quick   only step 1 (no Godot), a few seconds
  --tests   steps 1-3 (no network test)
python tools/setup.py installs it as a git pre-push hook (skip once with: git push --no-verify).
"""

import os
import sys

import install
import make_bodies
from _common import ROOT, fail, run

args = set(sys.argv[1:])
if not args <= {"--quick"} and not args <= {"--tests"}:
    fail("Usage: python tools/check.py [--quick | --tests]")
py = sys.executable
dirs = ["game/scripts", "game/tests"]


def step(name):
    print(f"\n== {name}", flush=True)


def tool(name, *tool_args):
    run(py, f"tools/{name}.py", *tool_args, cwd=ROOT)


step("Lint and format")
venv_py = install.venv()
run(venv_py, "-m", "gdtoolkit.linter", *dirs, cwd=ROOT)
run(venv_py, "-m", "gdtoolkit.formatter", "--check", *dirs, cwd=ROOT)

if os.path.exists(make_bodies.BLENDER_EXE):
    # CI has no Blender (there is no CI): the committed bodies are what ships.
    step("Bodies (Blender)")
    tool("make_bodies", "--check")

if "--quick" in args:
    print("\nQuick checks passed (Godot tests skipped).")
    sys.exit(0)

step("Lobby tests")
tool("run_lobby_tests")

step("gdUnit4 tests")
tool("run_tests")

if "--tests" in args:
    print("\nTest checks passed (network test skipped).")
    sys.exit(0)

step("Network test")
tool("run_network_test")

step("Bot play-test smoke scenario")
tool("playtest", "smoke")

print("\nAll checks passed.")

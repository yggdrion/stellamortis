"""Runs all checks locally (there is no CI) and stops at the first failure:
  1. gdlint + gdformat --check   2. gdUnit4 tests (pinned Godot)
  3. headless network test (one server, two bot clients over ENet with fake lag)

Usage: python tools/check.py [--quick | --tests]
  --quick   only step 1 (no Godot), a few seconds
  --tests   steps 1-2 (no network test)
python tools/setup.py installs it as a git pre-push hook (skip once with: git push --no-verify).
"""

import sys

import install
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

if "--quick" in args:
    print("\nQuick checks passed (Godot tests skipped).")
    sys.exit(0)

step("gdUnit4 tests")
tool("run_tests")

if "--tests" in args:
    print("\nTest checks passed (network test skipped).")
    sys.exit(0)

step("Network test")
tool("run_network_test")

print("\nAll checks passed.")

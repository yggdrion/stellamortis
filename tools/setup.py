"""One-time setup of a dev machine; safe to re-run. Installs the pinned Python packages
(gdtoolkit, pre-commit) into a shared venv, the pinned Godot, webrtc-native and gdUnit4, the
pre-push hook, then runs the quick check.

Needs: Python 3.12+ and git on PATH.
"""

import sys

import install
from _common import ROOT, run

py = sys.executable

print("== Python packages", flush=True)
venv_py = install.venv()
print("\n== Godot", flush=True)
install.godot()
print("\n== webrtc-native", flush=True)
install.webrtc()
print("\n== netfox", flush=True)
install.netfox()
print("\n== gdUnit4", flush=True)
install.gdunit4()
print("\n== Git hooks", flush=True)
run(venv_py, "-m", "pre_commit", "install", "-f", "--hook-type", "pre-push", cwd=ROOT)
run(py, "tools/check.py", "--quick", cwd=ROOT)
print("\nSetup done. Run python tools/check.py for the full check.")

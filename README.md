# Stellamortis

Third-person coop action game in space (Godot 4.7.2, GDScript). Scope, design and architecture:
[docs/PLAN.md](docs/PLAN.md).

## Setup

Needs Python 3.12+ and git. Safe to re-run:

    python tools/setup.py

Installs gdtoolkit and pre-commit (a venv), the pinned Godot (`.godot-version`, checked against
`tools/godot-<version>.sha512`, into a per-user dir shared by all checkouts, see
`tools/install.py`), the webrtc-native GDExtension, netfox (netcode), gdUnit4 and the pre-push hook.

## Run

    python tools/godot.py                    # solo: spawns a local headless server and joins it
    python tools/godot.py -e                 # editor
    python tools/dev.py 2 --lag=100          # headless server + 2 windowed clients through a 100 ms lag proxy
    python tools/lag_proxy.py 17778 17777 150 --jitter=20   # lag proxy on its own

Command line (after `--`, see `game/scripts/boot/main.gd`): `--server --port=N [--solo]`,
`--connect=host:port`, `--name=NAME`, `--windowed`, `--look=YAW,PITCH`, `--spawn=X,Y,Z`, `--bot [--expect=N] [--duration=S]`.

Controls: WASD move, mouse look, Shift sprint, Space jump, Esc frees the mouse (click to capture
again), F3 debug overlay, F11 fullscreen.

The low gravity zone (blue, east of the spawn) has a jump pad: stand on it and press Space to fly
up to the asteroid, walk all the way around it, and use the pad on its underside to come back.
The red zone to the west has high gravity.

## Check

    python tools/check.py            # lint, gdUnit4 tests, headless network test
    python tools/check.py --quick    # lint only

`--screenshot=PATH` saves a PNG after a few seconds and quits, for checking visuals without
playing.

## Release

Every push to `main` runs `.github/workflows/release.yml`: `tools/check.py` on Linux, then
`tools/export.py` on a Linux, Windows and macOS runner each (macOS: universal app, ad-hoc signed,
not notarized, so Gatekeeper asks once: right click, Open). The exports are kept as workflow
artifacts for 3 days and published as a GitHub Release `v<VERSION>.<patch>` with
`stellamortis-linux.zip`, `stellamortis-windows.zip` and `stellamortis-macos.zip`.

Versions: every milestone is a minor version. The commit that finishes milestone Mn sets
`VERSION` to `0.<n+1>` (M1 done: `0.2`), so its release is `v0.<n+1>.0`; every push after it
until the next milestone is a patch (`v0.2.1`, `v0.2.2`, ...).

    python tools/export.py           # local export for this platform into build/<platform>/

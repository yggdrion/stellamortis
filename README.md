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

    python tools/godot.py                    # main menu: Solo, Host, Join by code, Settings, name
    python tools/godot.py -- --solo          # straight into solo: a local headless server, joined
    python tools/godot.py -e                 # editor
    python tools/dev.py 2 --lag=100          # headless server + 2 windowed clients through a 100 ms lag proxy
    python tools/lag_proxy.py 17778 17777 150 --jitter=20   # lag proxy on its own

With Discord running, your Discord status shows the mode, where you are, the party size and the
time played (on Linux and macOS it needs `nc`, `ncat` or `socat` installed).

Play with friends (player host, over WebRTC through the lobby at `lobby.r4b2.de`):

    python tools/godot.py -- --host          # opens a room; the code shows top right, F2 copies it
    python tools/godot.py -- --join=CODE     # a friend joins by that code

`--lobby=ws://127.0.0.1:8080/ws` uses a local lobby instead: `cd lobby && bun src/server.ts`, or
lobby and coturn together with `docker compose -f deploy/lobby/docker-compose.local.yml up --build`
(`deploy/lobby/README.md`). `--relay-only` forces a client through the TURN relay.

Command line (after `--`, see `game/scripts/boot/main.gd`): `--server --port=N [--solo]`,
`--connect=host:port`, `--solo`, `--host`, `--join=CODE`, `--lobby=URL`, `--relay-only`, `--encounter=boss`, `--bench=N`, `--name=NAME`, `--windowed`, `--look=YAW,PITCH`, `--spawn=X,Y,Z`, `--delay=S`, `--frames=N`, `--graphics=PRESET`, `--bot-plan=shoot|combo|combo_walk`, `--bot [--expect=N] [--duration=S]`.

Controls: WASD move, mouse look, Shift sprint, Space jump, Ctrl or C roll, 1, 2 or the mouse wheel
switch weapons, Esc pause menu (Resume, Settings, Leave to menu, Quit), F3 debug overlay, F4 graphics
preset, F11 fullscreen.

- Sword and shield (1): LMB attack (press again for the combo), Q heavy attack, RMB raises the
  shield (press it just before a hit lands to parry).
- Crossbow (2): RMB aims over the shoulder, hold LMB to draw (the ring around the crosshair
  fills), release to shoot. Bolts fall with the gravity they fly through.
- No lock-on (Valheim style): attacks and the shield turn you to where the camera looks, rolls go
  where you move (no direction: where the camera looks).

You start in the keep, a walled yard on a small planet. Two training squires stand north of the
spawn: the left one only takes hits, the right one
swings at you every few seconds. Its windup glows orange and draws its reach on the ground (a
filled area with a bright edge, from the first windup frame): roll
through it, block it, or parry it for a stagger and a riposte that hits 2.5 times as hard.

The gate portal at the south end of the yard leads to the Barrows, another planet. There the dead
walk in front of the barrow wall: two with rusted swords and one with a crossbow. Put all three
down and the Warden rises, a giant dead knight in black iron, with a wide sweep (roll through it),
a slam in front of it (roll out of the circle) and a fan of embers (block or strafe). Below half
health it is enraged and opens a gravity well that drags you in; sprint or roll out. When it falls
a golden portal home opens where it stood. Dying sends you back to the keep; once nobody is left
in the Barrows, they reset. The portal beside the arrival also leads home. `--encounter=boss`
starts with the mobs down.

In the Barrows, the low gravity zone (blue, east of the arrival) has a jump pad: stand on it and press Space to fly
up to the asteroid, walk all the way around it, and use the pad on its underside to come back.
The red zone to the west has high gravity.

## Check

    python tools/check.py            # lint, lobby tests, gdUnit4 tests, network test (ENet, WebRTC)
    python tools/run_load_test.py    # 6 bots on one server: ticks per second, tick loop, kB/s (--lag=MS)
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

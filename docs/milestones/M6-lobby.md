# M6 Lobby

Status: done (2026-11-09), v0.7.0.

Written before the briefs existed, so this file keeps the milestone's original "done when" text. What was built is in `docs/PLAN.md` §4; what it left open is in §8.

## Done when

`lobby/` (Bun, lobby protocol 1) and `deploy/lobby/` (lobby + coturn) in this repo; `net/lobby_client.gd` and the WebRTC transport; `--host` spawns the server with a lobby room, host and friends join by code via WebRTC (TURN relay when direct fails); `bun test` and a WebRTC run in `tools/check.py`; works against a local lobby + coturn compose

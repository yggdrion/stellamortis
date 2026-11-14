# M8 Lobby deploy

Status: done (2026-11-09).

Written before the briefs existed, so this file keeps the milestone's original "done when" text. What was built is in `docs/PLAN.md` §4; what it left open is in §8.

## Done when

`deploy/lobby/` runs on the gvm host from `/root/stellamortis` (compose project `stellamortis-lobby`) in place of the stack there before, with its `TURN_SECRET`; gvm's Caddy routes `lobby.r4b2.de` (`/ws`, `/healthz`) to `stellamortis-lobby:8080`. coturn runs on the host network: behind Docker's NAT it mapped its own public address to the container's and denied relay to relay as a private peer (403 on CreatePermission). Checked with a host bot and a friend bot forced through the public TURN relay (`--relay-only`)

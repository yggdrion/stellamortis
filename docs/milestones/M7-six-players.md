# M7 6 players

Status: done (2026-11-09), v0.8.0.

Written before the briefs existed, so this file keeps the milestone's original "done when" text. What was built is in `docs/PLAN.md` §4; what it left open is in §8.

## Done when

Headless bots fill a game (`tools/run_load_test.py`); server holds 30 tps; bandwidth per player measured; state packets fit netfox's 508 byte limit (netfox schemas). Planned for 10 players; measured, netfox's server rollback holds 6 (§4.3, §8), and the cap is 6 by decision (2026-11-09)

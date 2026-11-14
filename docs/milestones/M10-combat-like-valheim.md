# M10 Combat like Valheim

Status: done (2026-11-09).

Written before the briefs existed, so this file keeps the milestone's original "done when" text. What was built is in `docs/PLAN.md` §4; what it left open is in §8.

## Done when

Combat should feel like Valheim, not Elden Ring. Remove lock-on completely (code, tests, Tab/MMB bindings, camera framing, outline and dot, docs). Attacks and blocks turn the character toward where the camera looks; rolls go in the movement direction (camera forward without input). Find and fix the moments where the player seems to teleport toward an enemy (suspects: facing slerp, roll direction, rollback corrections on attacks). The enemy's ground telegraph is clearly visible through the whole windup (filled area plus a bright outline from the first windup tick, more opaque toward the hit). Damage numbers when the own player is hit pop next to the health bar (blocked hits smaller, grey). The death notice says "YOU DIED". The F3 overlay no longer covers the encounter title

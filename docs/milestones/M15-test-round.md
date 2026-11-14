# M15 Test round

Status: done (2026-11-14, the user's play-test: "first tests pass").

## Goal

One milestone for everything left to verify after M2 to M14 were built blind, trusting tests and screenshots.

## What it covered

- The user play-tests by hand: solo, with a friend on another network, one player behind a strict NAT without `--relay-only`.
- The headless network test fights the encounter (mobs, Warden phases, enemy shots) under 100 ms lag.
- `--host --bot` gives up on its own after `--duration`.
- Screenshots of every enemy state and effect (gravity well, phase 2).
- Numbers (damage, windups, ranges, boss health, well strength) tuned from the play-test.

The per milestone lists of what to look at (M10 to M14, platforms, outfits, sound) are in `docs/PLAN.md` §8.

## Result

The user declared the round done on 2026-11-14. No item by item record was written. Fixes from the play-test rounds of 2026-11-09 and 2026-11-10 are logged in `docs/PLAN.md` §8.

Anything from §8's lists that still looks wrong goes into the play-test that ends the milestone touching it (M19 for hits and deaths, M22 for the Warden, M23 for the menus), not back into M15.

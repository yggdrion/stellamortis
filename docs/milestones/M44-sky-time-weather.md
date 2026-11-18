# M44 Sky, time and weather

Status: Planned.

## Goal

The world has a day: dawn, grey noon, dusk and a long night, with weather that drifts in and out per realm (mist, rain, wind; ash and still fog later). Light and sky follow the realm's palette, so the flat look holds at every hour.

## Depends on

M36 (palette), M37 (the ground and scatter the light falls on). World time exists since M23 (`WorldSave.world_seconds`).

## Design

- Time of day is a pure function of world time: `Daylight.at(world_seconds) -> phase` with a day of `Tuning` length (starting value 30 minutes, night a third of it). The server sends `world_seconds` at join and every 10 s (a reliable RPC in `net/net.gd`; protocol bump); clients advance it locally between. It is not rolled back and never decides anything in the sim in this milestone.
- Weather is a pure function too: `Weather.at(realm, world_seed, world_seconds) -> {kind, strength, wind}` from slow noise, so every peer sees the same sky without syncing more than the time. Kinds per realm are data (`RealmDef.weather`): the Barrowlands has clear, mist, drizzle, rain, gale.
- `Sky` (`scripts/client/sky.gd`) owns the sun and moon lights, the sky shader's uniforms, fog and ambient light, and blends between palette entries per phase (`Palette` gains `sky_*`, `sun_*`, `fog_*` per phase). `Arena`'s environment setup moves into it.
- Effects are view-only: rain and drizzle as `GPUParticles3D` around the camera along local gravity, mist as fog density and distance, gale as the wind strength M45 reads. Sounds: rain and wind loops on the Ambience bus (`Sounds.ambience`).
- Nights must stay playable: a floor on ambient light, and torches matter. A setting for night brightness is not added unless the play-test asks.
- `--time=HOUR` and `--weather=KIND` boot flags pin both for screenshots.

## Tasks

1. **Time and weather functions, sync (Opus).** `scripts/sim/daylight.gd`, `scripts/sim/weather.gd` (pure, tested), the RPC, `RealmDef.weather`, `data/tuning.tres`. Tests: same inputs same result on two peers; a joiner mid-day gets the same phase.
2. **Sky and light (Sonnet).** `scripts/client/sky.gd`, the sky shader, palette entries per phase, `scripts/sim/arena.gd`. Screenshots at four hours on Low and Ultra.
3. **Weather effects and sound, close (Sonnet).** Particles, fog, sound loops (`tools/make_sounds.py` for rain and wind), the boot flags, play-test items, milestone closed.

File level detail is added when M37 lands.

## Out of scope

Weather or darkness that changes gameplay (wet, cold, enemies by night): later, if wanted, as sim rules. Seasons. Clouds as geometry. Other realms' weather tables (their milestones add data).

## Pitfalls

- Rain falls along local gravity, not world down: on a round realm the camera's `up` decides.
- Fog already hides the realm's curve (§4.8); weather must never lower fog so far that the horizon shows.
- Shadows from a moving sun make cascades shimmer on flat-shaded ground: step the sun in small jumps and measure.
- A solo server pauses world time when it exits; clients must take the server's time, never their own clock.

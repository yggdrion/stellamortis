# M54 Emotes, pings and map pins

Status: Planned.

## Goal

Players can talk without words: wave, point, cheer, sit, bow on an emote wheel; ping a spot or an enemy so the party sees a marker; put pins on the map that everyone shares.

## Depends on

M33 (map). Independent of the combat milestones: can be built any time after M24.

## Design

- Emotes: a wheel (hold a key) with eight UAL clips; the emote id is one small synced value on the player, cancelled by moving or acting; sitting regains stamina a little faster.
- Pings: a key puts a marker where the camera looks (ground, enemy, object, player): a reliable RPC through the server to the party, shown in the world and on the compass and map for some seconds, with a sound; kinds by what was hit ("enemy here", "look", "loot", "help"). Rate limited.
- Map pins: placed on the map panel with an icon and a short label, saved in the world file, shared with everyone in the world; a personal pin set stays in the character file.
- Other players show on the map and as edge markers on screen with their names.

## Tasks

1. **Emotes (Sonnet).** `sim/sim_player.gd` (the value, in `STATE` and `wire.gd`), `client/player_view.gd`, a wheel in `client/`; `Net.PROTOCOL_VERSION`.
2. **Pings and pins (Sonnet).** RPCs in `net/net.gd`, `client/map_panel.gd`, world markers, `sim/world_save.gd`; tests for save and rate limit.
3. **Close (Sonnet).** Settings for keys, play-test items; bots ping when they die (useful in reports).

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Voice chat. Emotes with gameplay effects beyond sitting.

## Pitfalls

- The emote value is rolled back state: one byte, and it must not block the action machine.
- Pin labels are player text shown to others: limit length and strip control characters.

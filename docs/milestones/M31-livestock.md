# M31 Livestock

Status: planned.

## Goal

A base keeps animals. Players tame wild goats, boars, sheep and hens by feeding them, pen them, breed them and live off their wool, milk, eggs, hide and meat. Animals never fight.

## Depends on

M30 (world time, crops as feed), M29 (fences and gates as pieces), M23 (items, drops, saves), M20's scatter for wild herds. File level detail is added by M30's last task.

## Design

- Models first: the milestone starts with the search for CC0 animal models that fit the dark northern look (Quaternius animal packs are the first look; record them in `docs/RESOURCES.md`). Four kinds: goat (milk, hide), sheep (wool), boar (meat, hide), hen (eggs, feathers for bolts).
- Animals are not enemies and stay out of rollback and out of the enemy pool. They are server-authoritative actors: the server moves them (wander, follow food, flee when hit) at a low rate in loaded chunks and sends positions unreliably; clients interpolate. Players and enemies pass through them (no collision with bodies, so prediction never meets a body the server moves); animals collide with the terrain and pieces, so fences hold them.
- `AnimalDef` (resource): model, clips, speed, health, feed items, products with interval, breed time, grow time, meat yield.
- Wild herds spawn from the seed in each realm's meadows (a few per region, regrowing slowly). Hitting a wild animal makes it flee; killing it drops meat and hide.
- Taming: drop a feed item near a wild animal; it eats, and after enough feeds within a time it is tame (owned by the world, not a player). Tame animals follow a player holding feed and otherwise stay near where they were left.
- Breeding: two fed tame animals of a kind near each other breed after their breed time of world time, if the pen is under its cap; the young one grows up over its grow time. A per-base cap (about 20 animals within a base's radius) and a world cap (from a load test, start at 150) keep the server cheap.
- Products: fed tame animals produce on an interval of world time (eggs laid on the ground, milk and wool taken with a use while the animal is ready). Unfed animals stop producing and stop breeding, but never die of hunger.
- Feeding troughs (a piece) hold feed that nearby animals eat from; M32 can fill them.
- Saved: kind, position, tame, fed until, age, last product time. Unloaded chunks do nothing; on load, growth and products catch up from world time, movement does not.

## Tasks

1. **Animals on the server (Opus).** The actor (movement, collision with terrain and pieces, no collision with bodies), unreliable position sync and interpolation, wild herds from the seed, taming, follow, flee, kill and drops, save and catch-up, the caps. Tests: two peers see the same herd spawn; a fence holds an animal; a tame animal is still tame after a restart and for a late joiner; the cap stops breeding; the load test with the world cap of animals near 6 players still holds 29 tps.
2. **Breeding and products (Sonnet).** `AnimalDef` data for the four kinds, breed and grow by world time, products and their uses, troughs. Tests: a fed pair breeds after its time and an unfed pair does not; a young animal grows up; products come on their interval.
3. **Look and sound (Sonnet).** Models and clips, a hearts-free tame cue that fits the look (a rune mark or a collar), calls and footsteps, the use prompts, the HUD hint for feed. Then detail M32's brief and close the milestone.

## Out of scope

Mounts. Beasts that fight for players. Animals attacking anything. Diseases, aging to death.

## Pitfalls

- Animals moving near a predicted player must not collide with it: any collision between a server-moved body and a rolled back one is a desync. Keep them on their own physics layer that bodies ignore.
- Herds are cheap only if they sleep: animals far from every player stop moving and are only counted, never ticked.
- A pen full of animals means many nodes on every client: share meshes and materials per kind and skip animation for animals far away.

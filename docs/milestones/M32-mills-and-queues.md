# M32 Mills and station queues

Status: planned.

## Goal

A base works while its people are away. Smelters, kilns, mills and ovens take fuel and a queue and keep working unattended; water wheels and windmills turn wooden shafts that drive a millstone, a bellows and a saw, so a well built hall turns grain into flour, ore into iron and logs into planks on its own.

## Depends on

M29 (pieces with snap points), M30 (world time, the first queued stations), M25 (recipes, materials). M31 only for filling troughs. File level detail is added by M31's last task.

## Design

- No conveyors, pipes or electricity: everything is wood, stone, water, wind and fire, in keeping with §3.2.
- Station queues: a processing station is a piece with an input slot (a queue of up to N items), a fuel slot, an output slot and a recipe it runs. `ProcessDef` (resource: station, input, output, fuel per item, world time per item, power needed). The station's state is (queue, fuel, output, `started_at`); its progress is computed from world time when anyone looks at it or its chunk loads, so stations far away cost nothing and catch up exactly. Stations: charcoal kiln (logs to charcoal), smelter (ore to bars), millstone (barley to flour), sawbench (logs to planks), oven (M30's meals, longer queue), tannery (hides to leather).
- Power: water wheels (only on running water, M20 terrain with water or Myrkfen's channels; strength from the flow) and windmills (anywhere; strength from the realm's wind, data per realm: the Skyshards strongest, Myrkfen weakest). Wooden shafts and gears are M29 pieces with power snap points. The server keeps a power graph per connected network, rebuilt only when a piece in it changes: sources add power, machines draw it; a network short of power runs every machine on it slower in proportion.
- Powered machines: the millstone, the sawbench and the bellows (a smelter next to a powered bellows runs faster and burns less fuel). Unpowered, the millstone and sawbench still work by hand (a player using them), slowly.
- Hoppers: a hopper piece under a chest feeds the station below it; a chute under a station's output drops into a chest below. That is the only item transport: by gravity, straight down, so the local up of the realm matters (on the Skyshards a chute pours sideways if a rock's gravity says so).
- Troughs from M31 fill from a hopper too, so animals feed themselves from a chest.
- Every piece and its state is saved with the world. The budget of M29 counts these pieces too.

## Tasks

1. **Queues in the world (Opus).** `ProcessDef`, station state, progress from world time, catch-up on load and on use, insert and take by the server, save. Tests: a smelter with fuel and ore yields the right bars after the right world time; it stops when fuel ends; a restart and a late joiner see the same queue; an unloaded chunk catches up exactly.
2. **Power networks (Opus).** Water wheel and windmill, shafts and gears with power snap points, the graph rebuilt on change, the speed share, wind and flow per realm as data. Tests: two windmills drive a millstone faster than one; a cut shaft stops the machine behind it; a network with too many machines runs them all slower; the graph survives a restart.
3. **Hoppers and chutes (Sonnet).** Feed by gravity from chest to station and from station to chest, the trough link. Tests: a chest over a hopper over a smelter empties into it; an output chute fills the chest below; it follows local gravity.
4. **Look and sound (Sonnet).** Turning wheels and sails, shafts that spin when powered, smoke and glow on working stations, creaks, grinding and the forge roar as loops near running machines, a panel that shows queue, fuel, output and power. Close the milestone.

## Out of scope

Conveyor belts, pipes, logic, electricity, automated combat (traps). Item sorting beyond one hopper per chest. Machines that build pieces.

## Pitfalls

- Never tick stations: compute progress from world time. A ticked station far from players costs server time and drifts on restart.
- Spinning wheels and shafts are client visuals driven by the network's power; they must never be physics bodies.
- A power graph rebuilt every tick is a hidden cost: rebuild on piece change only, and test with a hall of a few hundred pieces.

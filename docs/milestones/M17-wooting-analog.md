# M17 Wooting analog

Status: optional. Build only when the user asks for it.

## Goal

Analog movement from Wooting keyboards: how far W, A, S and D are pressed becomes how fast the character walks.

## Design

- The Wooting Analog SDK through a GDExtension or a small native bridge.
- Key depth becomes the length of `PlayerControls.move`; the sim already scales walk speed by it.
- Digital keys stay the fallback when no Wooting device or SDK is present.

## Before starting

Detail this brief: pick GDExtension or bridge, check the SDK's license and record it in `docs/RESOURCES.md`, check all three export platforms build, and confirm how `PlayerControls.move` is quantized on the wire (`net/wire.gd`) so partial values survive.

## Pitfalls

- Input is part of the netfox input stream: a change to its encoding bumps `Net.PROTOCOL_VERSION`.
- A native library in the export must not break players without the device.

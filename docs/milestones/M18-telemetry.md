# M18 Telemetry

Status: optional. Build only when the user asks for it.

## Goal

Opt-in game telemetry, so problems show up without asking players: sessions, joins, connection type, tick and frame times.

## Design

- Off by default; a clear choice in the settings, saved in `user://settings.cfg`.
- Sent through the lobby host (`lobby/`), which already exposes Prometheus metrics (`stellamortis_lobby_*`).
- No names, room codes, addresses or anything that identifies a player.

## Before starting

Detail this brief: the event list, the endpoint and its rate limits in `lobby/src/server.ts`, how it reaches Grafana on the gvm host, and what the settings text says. A lobby change needs a redeploy on gvm, which needs the user's go-ahead.

## Pitfalls

- A new lobby endpoint is public: validate sizes and rates, accept nothing free-form.
- The lobby protocol (`LobbyClient.PROTOCOL`) is separate from `Net.PROTOCOL_VERSION`; decide which one telemetry rides on.

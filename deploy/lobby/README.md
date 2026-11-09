# Deploy: lobby and coturn (player host)

The player-host stack runs from a clone of this repo on the gvm host (`grafana.r4b2.de`,
Hetzner, 91.99.227.111) as its own compose project. gvm's Caddy (ports 80/443) terminates TLS
for `lobby.r4b2.de` and proxies to the lobby, which joins gvm's network `gvm_default` as
`stellamortis-lobby`. The game connects to `wss://lobby.r4b2.de/ws` (`LobbyClient.DEFAULT_URL`;
`--lobby=URL` picks another). DNS: an A record to the host, no Cloudflare proxy, since TURN is
UDP.

| Service | Public | Notes |
|---|---|---|
| `lobby` (built from `lobby/`) | `/ws`, `/healthz` through gvm's Caddy | `/metrics` stays internal |
| `coturn` | 3478 TCP/UDP, relay UDP 49160–49259 | credentials minted by the lobby from `TURN_SECRET` |

Deploying it is milestone M8 (PLAN §6) and needs a go-ahead first: it replaces the stack that
holds these ports and the Caddy route today.

## First setup

    cd /root && git clone https://github.com/yggdrion/stellamortis.git
    cd stellamortis/deploy/lobby
    cp .env.example .env && chmod 600 .env    # fill in TURN_SECRET
    docker compose up -d --build

If another stack already holds port 3478, the relay range or the network alias, stop it first
(`docker compose down` in its directory) and copy its TURN secret into `.env` instead of making a
new one. Bring the Caddy change up with `docker compose up -d caddy` in `/root/gvm` (not
`restart`) when the change also touches Caddy's environment.

The host firewall must let in 3478 TCP/UDP and UDP 49160–49259. gvm's `Caddyfile` (repo
`yggdrion/gvm`) routes `lobby.r4b2.de` to `stellamortis-lobby:8080`, only `/ws` and `/healthz`;
after changing it, `cd /root/gvm && git pull && docker compose restart caddy`.

## Update

    cd /root/stellamortis && git pull && cd deploy/lobby && docker compose up -d --build

The lobby's message format has its own version (`PROTOCOL` in `lobby/src/server.ts`,
`LobbyClient.PROTOCOL` in the game), so game-only changes need no lobby redeploy.

## Check

    curl https://lobby.r4b2.de/healthz          # ok
    docker compose logs coturn --tail 20

The lobby prints one JSON line per room event (`hosted`, `joined`, `join_refused`, `signal` with
its kind only, `left`, `room_closed` with its reason, `guest_timeout`): never signal data,
credentials or IP addresses. To see why a friend could not join:

    cd /root/stellamortis/deploy/lobby && docker compose logs lobby | grep -E 'join_refused|room_closed|guest_timeout'

A TURN credential for manual tests, minted the way the lobby does it:

    . ./.env; U="$(( $(date +%s) + 1800 )):check"
    P="$(printf %s "$U" | openssl dgst -sha1 -hmac "$TURN_SECRET" -binary | base64)"; echo "$U $P"

## Local test

    docker compose -f deploy/lobby/docker-compose.local.yml up --build

runs both on this machine (lobby on 8080, coturn on 127.0.0.1:3478 with a test secret). Host
with `--host --lobby=ws://127.0.0.1:8080/ws`, join with `--join=CODE --lobby=ws://127.0.0.1:8080/ws`.

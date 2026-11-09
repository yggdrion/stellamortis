"""UDP proxy that adds latency (and optional jitter and loss) between game clients and a
server, so prediction and rollback can be tested with every packet delayed, netfox's included.

Usage: python tools/lag_proxy.py LISTEN_PORT SERVER_PORT RTT_MS [--jitter=MS] [--loss=PERCENT]
Clients connect to LISTEN_PORT; each direction waits RTT_MS / 2 (plus up to --jitter ms).
Stdlib only. Also importable: start(listen_port, server_port, rtt_ms) runs it in a thread.
"""

import asyncio
import random
import sys
import threading


class _Upstream(asyncio.DatagramProtocol):
    """One socket per client toward the server, so the server sees separate peers."""

    def __init__(self, proxy, client_addr):
        self.proxy = proxy
        self.client_addr = client_addr
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        self.proxy.delay(lambda: self.proxy.transport.sendto(data, self.client_addr))


class _Proxy(asyncio.DatagramProtocol):
    def __init__(self, server_port, rtt_ms, jitter_ms, loss):
        self.server = ("127.0.0.1", server_port)
        self.one_way = rtt_ms / 2000.0
        self.jitter = jitter_ms / 1000.0
        self.loss = loss / 100.0
        self.transport = None
        self.upstreams = {}
        self.loop = asyncio.get_event_loop()
        # Packets keep their order per direction (ENet copes with reordering, but real
        # jitter mostly delays, it rarely reorders).
        self.last_due = 0.0

    def connection_made(self, transport):
        self.transport = transport

    def delay(self, send):
        if random.random() < self.loss:
            return
        due = self.loop.time() + self.one_way + random.uniform(0.0, self.jitter)
        due = max(due, self.last_due)
        self.last_due = due
        self.loop.call_at(due, send)

    def datagram_received(self, data, addr):
        upstream = self.upstreams.get(addr)
        if upstream is None:
            upstream = _Upstream(self, addr)
            self.upstreams[addr] = upstream
            self.loop.create_task(
                self.loop.create_datagram_endpoint(lambda: upstream, remote_addr=self.server)
            )

        def send():
            if upstream.transport:
                upstream.transport.sendto(data)

        self.delay(send)


async def _serve(listen_port, server_port, rtt_ms, jitter_ms, loss):
    loop = asyncio.get_event_loop()
    await loop.create_datagram_endpoint(
        lambda: _Proxy(server_port, rtt_ms, jitter_ms, loss), local_addr=("127.0.0.1", listen_port)
    )
    await asyncio.Event().wait()


def start(listen_port, server_port, rtt_ms, jitter_ms=0, loss=0.0):
    """Runs the proxy in a daemon thread."""
    thread = threading.Thread(
        target=lambda: asyncio.run(_serve(listen_port, server_port, rtt_ms, jitter_ms, loss)),
        daemon=True,
    )
    thread.start()
    return thread


if __name__ == "__main__":
    positional = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if len(positional) != 3:
        sys.exit(__doc__)
    listen, server, rtt = map(int, positional)
    print(f"Proxy 127.0.0.1:{listen} -> 127.0.0.1:{server}, {rtt} ms round trip", flush=True)
    try:
        asyncio.run(
            _serve(listen, server, rtt, int(options.get("jitter", 0)), float(options.get("loss", 0)))
        )
    except KeyboardInterrupt:
        pass

"""Request protection: rate limiting and security headers.

The in-memory limiter is correct for a single API process. When running more
than one instance, move the counters to Redis (same interface).
"""
from __future__ import annotations

import time
from collections import deque
from threading import Lock

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
}
HSTS = ("Strict-Transport-Security", "max-age=63072000; includeSubDomains")

MAX_BODY_BYTES = 8 * 1024


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: float = 60.0, max_keys: int = 100_000):
        self.limit, self.window, self.max_keys = limit, window_seconds, max_keys
        self._hits: dict[str, deque[float]] = {}
        self._lock = Lock()

    def allow(self, key: str, now: float | None = None) -> tuple[bool, int]:
        """Return (allowed, retry_after_seconds)."""
        now = time.monotonic() if now is None else now
        with self._lock:
            if len(self._hits) > self.max_keys:
                self._hits.clear()  # memory guard under attack
            q = self._hits.setdefault(key, deque())
            while q and q[0] <= now - self.window:
                q.popleft()
            if len(q) >= self.limit:
                return False, max(1, int(q[0] + self.window - now) + 1)
            q.append(now)
            return True, 0


def client_ip(headers: dict[str, str], peer: str | None, trust_proxy: bool) -> str:
    """Client IP. X-Forwarded-For is honoured only behind ONE trusted proxy.

    The proxy appends the real client IP as the LAST entry; earlier entries
    can be forged by the client, so they are ignored.
    """
    if trust_proxy:
        xff = headers.get("x-forwarded-for", "")
        if xff:
            return xff.split(",")[-1].strip()
    return peer or "unknown"

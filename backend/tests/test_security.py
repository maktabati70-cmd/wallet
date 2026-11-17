from app.security import SlidingWindowLimiter, client_ip


def test_limiter_blocks_then_recovers():
    lim = SlidingWindowLimiter(limit=3, window_seconds=60)
    assert all(lim.allow("ip", now=t)[0] for t in (0, 1, 2))
    ok, retry = lim.allow("ip", now=3)
    assert not ok and retry >= 1
    assert lim.allow("other", now=3)[0]
    assert lim.allow("ip", now=61)[0]


def test_client_ip_ignores_spoofed_header_by_default():
    h = {"x-forwarded-for": "1.2.3.4"}
    assert client_ip(h, "10.0.0.1", trust_proxy=False) == "10.0.0.1"
    assert client_ip(h, "10.0.0.1", trust_proxy=True) == "1.2.3.4"
    # a client-forged first entry is ignored; the proxy-appended last one wins
    forged = {"x-forwarded-for": "6.6.6.6, 1.2.3.4"}
    assert client_ip(forged, "10.0.0.1", trust_proxy=True) == "1.2.3.4"

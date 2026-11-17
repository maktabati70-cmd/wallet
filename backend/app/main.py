"""TRON Wallet backend API (Phase 1).

Non-custodial: the server never sees or stores private keys or seed phrases.
Phase 1 endpoints are read-only plus fee quoting. There is deliberately NO
send/broadcast endpoint yet — sending is implemented in Phase 3.

Privacy: wallet addresses are sent in POST bodies (not URLs) so they do not
end up in access logs, and they are not stored except inside fee quotes.
"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from . import fees
from .chain import ChainError, ChainReader
from .config import Settings, load_settings
from .money import format_usdt, parse_usdt
from .repository import Repository
from .schemas import AddressRequest, HistoryRequest, QuoteRequest
from .security import HSTS, MAX_BODY_BYTES, SECURITY_HEADERS, SlidingWindowLimiter, client_ip

log = logging.getLogger("wallet")

RESOURCE_DISCLOSURE = (
    "TRON network costs are paid in Energy/Bandwidth (TRX resources), not in USDT. "
    "We provide those resources for your transfer and charge a network resource fee "
    "in USDT to cover our cost. This is separate from our service fee."
)


def create_app(settings: Settings | None = None,
               repo: Repository | None = None,
               chain: ChainReader | None = None) -> FastAPI:
    settings = settings or load_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        nonlocal repo, chain
        if repo is None:
            from .repository import PostgresRepository
            repo = PostgresRepository(settings.database_url)
        if chain is None:
            from .chain import TronGridReader
            chain = TronGridReader(settings.tron_rpc_url, settings.usdt_contract, settings.tron_api_key)
        app.state.repo, app.state.chain = repo, chain
        yield
        if hasattr(chain, "aclose"):
            await chain.aclose()

    app = FastAPI(
        title="TRON Wallet API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/openapi.json",
    )
    limiter = SlidingWindowLimiter(settings.rate_limit_per_minute, 60)
    quote_limiter = SlidingWindowLimiter(max(5, settings.rate_limit_per_minute // 4), 60)

    @app.middleware("http")
    async def protect(request: Request, call_next):
        if int(request.headers.get("content-length") or 0) > MAX_BODY_BYTES:
            return JSONResponse({"detail": "request too large"}, status_code=413)
        ip = client_ip(dict(request.headers), request.client.host if request.client else None,
                       settings.trust_proxy_headers)
        ok, retry = limiter.allow(ip)
        if ok and request.url.path == "/v1/quotes":
            ok, retry = quote_limiter.allow(ip)
        if not ok:
            resp = JSONResponse({"detail": "too many requests"}, status_code=429)
            resp.headers["Retry-After"] = str(retry)
        else:
            resp = await call_next(request)
        for k, v in SECURITY_HEADERS.items():
            resp.headers.setdefault(k, v)
        if settings.is_production:
            resp.headers[HSTS[0]] = HSTS[1]
        return resp

    def _chain(request: Request) -> ChainReader:
        return request.app.state.chain

    def _repo(request: Request) -> Repository:
        return request.app.state.repo

    # ------------------------------------------------------------------ public
    @app.get("/health")
    def health(request: Request):
        return {"status": "ok", "network": settings.tron_network,
                "database": _repo(request).ping(), "sending_enabled": False}

    @app.get("/v1/config")
    def public_config(request: Request):
        _, s = _repo(request).active_fee_schedule()
        return {
            "network": settings.tron_network,
            "is_testnet": settings.tron_network != "mainnet",
            "usdt_contract": settings.usdt_contract,
            "explorer_tx_url": settings.explorer_tx_url,
            "sending_enabled": False,
            "min_app_version": settings.min_app_version,
            "fees": {
                "service_fee_percent": f"{s.service_fee_bps / 100:.2f}",
                "min_service_fee": format_usdt(s.min_service_fee_micro),
                "max_service_fee": format_usdt(s.max_service_fee_micro),
                "min_send": format_usdt(s.min_send_micro),
                "max_send": format_usdt(s.max_send_micro),
                "resource_fee_disclosure": RESOURCE_DISCLOSURE,
            },
            "legal": {
                "support_email": settings.support_email,
                "privacy_policy_url": settings.privacy_policy_url,
                "terms_url": settings.terms_url,
            },
        }

    @app.post("/v1/wallet/balance")
    async def balance(body: AddressRequest, request: Request):
        try:
            a = await _chain(request).get_account(body.address)
        except ChainError as exc:
            raise HTTPException(503, str(exc))
        return {"address": a.address, "activated": a.activated,
                "usdt": format_usdt(a.usdt_micro), "usdt_micro": a.usdt_micro,
                "trx": format_usdt(a.trx_sun), "trx_sun": a.trx_sun}

    @app.post("/v1/wallet/history")
    async def history(body: HistoryRequest, request: Request):
        try:
            items, nxt = await _chain(request).usdt_history(body.address, body.limit, body.fingerprint)
        except ChainError as exc:
            raise HTTPException(503, str(exc))
        return {
            "items": [{
                "txid": t.txid, "timestamp_ms": t.timestamp_ms,
                "from": t.from_address, "to": t.to_address,
                "amount": format_usdt(t.amount_micro), "amount_micro": t.amount_micro,
                "direction": t.direction,
                "status": "confirmed" if t.confirmed else "pending",
                "explorer_url": settings.explorer_tx_url + t.txid,
            } for t in items],
            "next": nxt,
        }

    @app.post("/v1/quotes")
    async def create_quote(body: QuoteRequest, request: Request):
        if body.from_address == body.to_address:
            raise HTTPException(422, "You cannot send to your own address.")
        if body.to_address == settings.usdt_contract:
            raise HTTPException(422, "This is the USDT token contract, not a wallet. "
                                     "Funds sent here would be lost.")
        amount = parse_usdt(body.amount)
        chain = _chain(request)
        try:
            sender = await chain.get_account(body.from_address)
            recipient = await chain.get_account(body.to_address)
        except ChainError as exc:
            raise HTTPException(503, str(exc))
        if sender.usdt_micro < amount:
            raise HTTPException(422, "Insufficient USDT balance.")

        repo = _repo(request)
        schedule_id, schedule = await run_in_threadpool(repo.active_fee_schedule)
        holds = recipient.usdt_micro > 0
        mode = fees.DeliveryMode(settings.delivery_mode)
        # Phase 3 will check the user's allowance to the relayer; until then
        # assume first use so the activation cost is never under-charged.
        needs_activation = mode == fees.DeliveryMode.RELAYER
        energy_needed, _ = fees.resources_needed(holds, mode, needs_activation)
        source = fees.EnergySource.RENTED
        if settings.energy_account:
            try:
                if await chain.free_energy(settings.energy_account) >= energy_needed:
                    source = fees.EnergySource.STAKED
            except ChainError:
                pass  # fall back to rented pricing: never under-charge
        try:
            q = fees.quote(amount, holds, schedule, mode=mode, source=source,
                           needs_activation=needs_activation)
        except fees.QuoteError as exc:
            raise HTTPException(422, str(exc))
        quote_id, expires_at = await run_in_threadpool(
            lambda: repo.save_quote(
                network=settings.tron_network, from_address=body.from_address,
                to_address=body.to_address, q=q, schedule_id=schedule_id,
                ttl_seconds=settings.quote_ttl_seconds))

        return {
            "quote_id": quote_id,
            "expires_at": expires_at.isoformat(),
            "network": settings.tron_network,
            "from_address": body.from_address,
            "to_address": body.to_address,
            "amount": format_usdt(q.amount_micro),
            "service_fee": format_usdt(q.service_fee_micro),
            "service_fee_percent": f"{schedule.service_fee_bps / 100:.2f}",
            "resource_fee": format_usdt(q.resource_fee_micro),
            "total_fee": format_usdt(q.total_fee_micro),
            "recipient_receives": format_usdt(q.recipient_micro),
            "recipient_is_new": not recipient.activated,
            "recipient_holds_usdt": q.recipient_holds_usdt,
            "energy_units": q.energy_units,
            "delivery_mode": q.mode,
            "energy_source": q.energy_source,
            "activation_fee_included": q.activation_included,
            "resource_fee_disclosure": RESOURCE_DISCLOSURE,
            "sending_enabled": False,
        }

    return app

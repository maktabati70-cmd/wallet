"""Application settings, read from environment variables (and an optional .env file).

Secrets are NEVER hard-coded. In production, inject them from the hosting
platform's secret manager rather than a .env file.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from .tron_address import is_valid_address

NETWORKS = {
    # USDT contract per network. Testnet contracts are test tokens with no value.
    # Verify the Nile/Shasta addresses on the official explorer before use.
    "nile": {
        "rpc": "https://nile.trongrid.io",
        "usdt": "TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf",
        "explorer": "https://nile.tronscan.org/#/transaction/",
    },
    "shasta": {
        "rpc": "https://api.shasta.trongrid.io",
        "usdt": "TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs",
        "explorer": "https://shasta.tronscan.org/#/transaction/",
    },
    "mainnet": {
        "rpc": "https://api.trongrid.io",
        "usdt": "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
        "explorer": "https://tronscan.org/#/transaction/",
    },
}


def _load_dotenv(path: Path) -> None:
    """Minimal .env loader (KEY=VALUE lines). Real env vars take precedence."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def _bool(name: str, default: bool) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)))


@dataclass
class Settings:
    app_env: str = "development"
    database_url: str = ""
    tron_network: str = "nile"
    tron_rpc_url: str = ""
    tron_api_key: str = ""                 # TronGrid key; optional on testnet
    usdt_contract: str = ""
    treasury_address: str = ""             # receives service + resource fees
    energy_account: str = ""               # platform account holding staked TRX (Energy)
    delivery_mode: str = "two_transfers"   # two_transfers | relayer (needs deployed contract)
    relayer_contract: str = ""             # Phase 3: audited relayer contract address
    operator_private_key: str = ""         # hot operator wallet (Energy lending) — secret
    operator_mnemonic: str = ""            # alternative to the private key — secret
    auto_stake: bool = True                # testnet: stake idle operator TRX on startup
    collect_fees: bool = True              # False = personal mode: no fees, no fee transaction
    allow_mainnet: bool = False
    sending_enabled: bool = False          # real sending (testnet first)
    trust_proxy_headers: bool = False      # only behind a trusted reverse proxy
    rate_limit_per_minute: int = 60
    quote_ttl_seconds: int = 60
    support_email: str = ""
    privacy_policy_url: str = ""
    terms_url: str = ""
    min_app_version: str = "0.1.0"
    cors_origins: list[str] = field(default_factory=list)

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def explorer_tx_url(self) -> str:
        return NETWORKS[self.tron_network]["explorer"]

    def validate(self) -> None:
        if self.tron_network not in NETWORKS:
            raise RuntimeError(f"TRON_NETWORK must be one of {sorted(NETWORKS)}")
        if self.tron_network == "mainnet" and not self.allow_mainnet:
            raise RuntimeError(
                "Mainnet is blocked. Set ALLOW_MAINNET=true only after the security, "
                "legal and Google Play reviews are complete."
            )
        if self.sending_enabled:
            if self.collect_fees and not self.treasury_address:
                raise RuntimeError("SENDING_ENABLED requires TREASURY_ADDRESS (your fee wallet) "
                                   "unless COLLECT_FEES=false")
            # No operator wallet = users pay the network fee with their own TRX.
        if not is_valid_address(self.usdt_contract):
            raise RuntimeError("USDT contract address is invalid")
        for name in ("treasury_address", "energy_account", "relayer_contract"):
            value = getattr(self, name)
            if value and not is_valid_address(value):
                raise RuntimeError(f"{name.upper()} is not a valid TRON address")
        if self.delivery_mode not in ("two_transfers", "relayer"):
            raise RuntimeError("DELIVERY_MODE must be two_transfers or relayer")
        if self.delivery_mode == "relayer" and not self.relayer_contract:
            raise RuntimeError("DELIVERY_MODE=relayer requires RELAYER_CONTRACT")
        if self.is_production and not self.database_url:
            raise RuntimeError("DATABASE_URL is required in production")


def load_settings(env_file: str | None = ".env") -> Settings:
    if env_file:
        _load_dotenv(Path(env_file))
    network = os.environ.get("TRON_NETWORK", "nile").strip().lower()
    net = NETWORKS.get(network, NETWORKS["nile"])
    s = Settings(
        app_env=os.environ.get("APP_ENV", "development"),
        database_url=os.environ.get("DATABASE_URL", ""),
        tron_network=network,
        tron_rpc_url=os.environ.get("TRON_RPC_URL", net["rpc"]),
        tron_api_key=os.environ.get("TRON_API_KEY", ""),
        usdt_contract=os.environ.get("USDT_CONTRACT", net["usdt"]),
        treasury_address=os.environ.get("TREASURY_ADDRESS", ""),
        energy_account=os.environ.get("ENERGY_ACCOUNT", ""),
        delivery_mode=os.environ.get("DELIVERY_MODE", "two_transfers"),
        relayer_contract=os.environ.get("RELAYER_CONTRACT", ""),
        operator_private_key=os.environ.get("OPERATOR_PRIVATE_KEY", "").strip(),
        operator_mnemonic=os.environ.get("OPERATOR_MNEMONIC", "").strip(),
        auto_stake=_bool("AUTO_STAKE", True),
        collect_fees=_bool("COLLECT_FEES", True),
        allow_mainnet=_bool("ALLOW_MAINNET", False),
        sending_enabled=_bool("SENDING_ENABLED", False),
        trust_proxy_headers=_bool("TRUST_PROXY_HEADERS", False),
        rate_limit_per_minute=_int("RATE_LIMIT_PER_MINUTE", 60),
        quote_ttl_seconds=_int("QUOTE_TTL_SECONDS", 60),
        support_email=os.environ.get("SUPPORT_EMAIL", ""),
        privacy_policy_url=os.environ.get("PRIVACY_POLICY_URL", ""),
        terms_url=os.environ.get("TERMS_URL", ""),
        min_app_version=os.environ.get("MIN_APP_VERSION", "0.1.0"),
        cors_origins=[o for o in os.environ.get("CORS_ORIGINS", "").split(",") if o],
    )
    s.validate()
    return s
